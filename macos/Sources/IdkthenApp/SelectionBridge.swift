import AppKit
import ApplicationServices
import Carbon
import IdkthenCore

enum SelectionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct SelectionSnapshot {
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let before: String
    let range: NSRange
    var selectedText: String { (before as NSString).substring(with: range) }
}

@MainActor final class SelectionBridge {
    private var hotKey: EventHotKeyRef?
    private var undoHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onShortcut: (() -> Void)?
    var onUndoShortcut: (() -> Void)?
    var trusted: Bool { AXIsProcessTrusted() }
    var enabled: Bool { hotKey != nil }
    var undoShortcutEnabled: Bool { undoHotKey != nil }
    var hasLiveUndo: Bool { undoCaret != nil && undoTransaction != nil }
    private(set) var undoSnapshot: SelectionSnapshot?
    private(set) var undoTransaction: TextTransaction?
    private var undoCaret: Int?
    private var liveRecovery: CorrectionRecovery?
    private var replacing = false
    private var capabilityElement: AXUIElement?
    private var markerOperationAvailable = false

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func enable(_ choice: ShortcutChoice) throws {
        guard trusted else { throw SelectionError.message("Allow idkthen in System Settings → Privacy & Security → Accessibility, then enable the shortcut again.") }
        guard hotKey == nil else { return }
        try installHandler()
        do { try updateShortcut(choice) }
        catch { disable(); throw error }
    }
    private func installHandler() throws {
        guard eventHandler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let install = InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let data, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x50616972, [1, 2].contains(identifier.id) else { return OSStatus(eventNotHandledErr) }
            let bridge = Unmanaged<SelectionBridge>.fromOpaque(data).takeUnretainedValue()
            let isUndo = identifier.id == 2
            Task { @MainActor in
                if isUndo { bridge.onUndoShortcut?() } else { bridge.onShortcut?() }
            }
            return noErr
        }, 1, &type, context, &eventHandler)
        guard install == noErr else { throw SelectionError.message("Could not install the selection shortcut (\(install)).") }
    }
    @discardableResult func enableUndoShortcut(_ choice: UndoShortcutChoice) -> Bool {
        guard trusted, hasLiveUndo else { return false }
        guard undoHotKey == nil else { return true }
        do { try installHandler() } catch { return false }
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_Z), choice.modifiers,
                                        EventHotKeyID(signature: 0x50616972, id: 2), GetApplicationEventTarget(), 0, &undoHotKey)
        if result != noErr { undoHotKey = nil; removeUnusedHandler() }
        return undoHotKey != nil
    }
    func disableUndoShortcut() {
        if let undoHotKey { UnregisterEventHotKey(undoHotKey) }
        undoHotKey = nil; removeUnusedHandler()
    }
    func updateShortcut(_ choice: ShortcutChoice) throws {
        var newHotKey: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x50616972, id: 1)
        let result = RegisterEventHotKey(choice.keyCode, choice.modifiers, identifier, GetApplicationEventTarget(), 0, &newHotKey)
        guard result == noErr, let newHotKey else {
            throw SelectionError.message("\(choice.label) is unavailable (\(result)). Choose another shortcut or use Import selection.")
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
    }
    func disable() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil; removeUnusedHandler()
    }
    private func removeUnusedHandler() {
        if hotKey == nil, undoHotKey == nil, let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }
    static func canReadApplication(_ app: NSRunningApplication) -> Bool {
        let blocked = ["terminal", "iterm", "warp", "xcode", "vscode", "com.microsoft.vs", "jetbrains", "cursor", "password", "keychain", "com.apple.systempreferences"]
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        return app.processIdentifier != ProcessInfo.processInfo.processIdentifier && !app.isTerminated && !blocked.contains(where: bundle.contains)
    }
    func capture(from selectedApp: NSRunningApplication? = nil) throws -> SelectionSnapshot {
        guard trusted else { throw SelectionError.message("Accessibility access is not enabled. You can still paste text into idkthen.") }
        guard !IsSecureEventInputEnabled() else { throw SelectionError.message("Secure input is active. idkthen leaves this field alone.") }
        guard let app = selectedApp ?? NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw SelectionError.message("Select text in another app, then press Control–Option–Space.")
        }
        guard Self.canReadApplication(app) else {
            throw SelectionError.message("idkthen skips terminals, code editors, password managers, and System Settings. Paste a sample here to review it.")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        guard let raw = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw SelectionError.message("This app does not expose a text selection. Paste the text into idkthen instead.")
        }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.5)
        try checkField(element)
        guard let value = attribute(element, kAXValueAttribute) as? String,
              (value as NSString).length <= 100_000,
              let range = selectedRange(element), range.length > 0,
              range.length <= ReviewEngine.maxSelectionLength,
              TextTransaction(before: value, range: range, replacement: "").after != nil,
              let selection = attribute(element, kAXSelectedTextAttribute) as? String,
              TextIdentity.matches((value as NSString).substring(with: range), selection) else {
            throw SelectionError.message("Select 1–4,000 characters in an editable text field. If this app hides its selection, paste into idkthen instead.")
        }
        guard canReplace(element) else {
            throw SelectionError.message("This app does not allow direct selection replacement. Paste into idkthen, then copy the reviewed result.")
        }
        return SelectionSnapshot(element: element, pid: app.processIdentifier, appName: app.localizedName ?? "your app", before: value, range: range)
    }
    func captureCaret(from app: NSRunningApplication) throws -> SelectionSnapshot {
        guard trusted, !IsSecureEventInputEnabled(), Self.canReadApplication(app),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw SelectionError.message("Live suggestions are waiting for an allowed app.")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let raw = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw SelectionError.message("Click an editable text field to start typing.")
        }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.2)
        try checkLiveField(element)
        if let marked = rangeAttribute(element, "AXMarkedTextRange"), marked.length > 0 {
            throw SelectionError.message("Waiting for the current word to finish.")
        }
        guard canReplace(element), let value = attribute(element, kAXValueAttribute) as? String,
              (value as NSString).length <= 100_000, let range = selectedRange(element),
              range.length == 0, TextTransaction(before: value, range: range, replacement: "").after != nil else {
            throw SelectionError.message("Live mode needs an editable field with a caret. Select text and use Import selection otherwise.")
        }
        return SelectionSnapshot(element: element, pid: app.processIdentifier, appName: app.localizedName ?? "your app", before: value, range: range)
    }
    func bounds(for element: AXUIElement, range: NSRange) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let rectValue = unsafeBitCast(raw, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(rectValue) == .cgRect, AXValueGetValue(rectValue, .cgRect, &rect),
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.height > 0 else { return nil }
        return rect
    }
    func apply(_ replacement: String, snapshot: SelectionSnapshot, caret: Int? = nil) async throws {
        guard !replacing else { throw SelectionError.message("A correction is already in progress.") }
        replacing = true; defer { replacing = false }
        let transaction = TextTransaction(before: snapshot.before, range: snapshot.range, replacement: replacement)
        guard let expected = transaction.after else {
            throw SelectionError.message("The selection splits a character or is no longer valid. Select complete characters and try again.")
        }
        guard transaction.originalSelection != replacement else {
            throw SelectionError.message("No changed text is selected for replacement.")
        }
        // Safari may omit its focused AX element while our menu is active.
        // Only an explicit review action may return to that browser; automatic
        // correction still requires it to be frontmost throughout.
        if caret == nil, isBrowser(snapshot.element) { try await prepareBrowser(snapshot) }
        try validate(snapshot, expected: snapshot.before)
        if let caret {
            try checkLiveField(snapshot.element)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid,
                  selectedRange(snapshot.element) == NSRange(location: caret, length: 0) else {
                throw SelectionError.message("The caret moved. Keep typing; the old suggestion was dismissed.")
            }
        }
        let browser = isBrowser(snapshot.element)
        let plan = try await replace(snapshot, transaction: transaction, caret: browser ? caret : nil)
        let finalCaret = caret.map { $0 + transaction.replacementRange.length - transaction.range.length }
        if !browser, let finalCaret { try setRange(snapshot.element, NSRange(location: finalCaret, length: 0)) }
        guard let confirmation = await confirm(snapshot, transaction: transaction, inserted: plan, caretAfter: finalCaret) else {
            clearUndo()
            throw SelectionError.message("The app did not confirm the replacement. Check the original field before trying again.")
        }
        let confirmedTransaction = confirmation.transaction
        if browser { restoreCaretIfUnmoved(snapshot, expected: confirmedTransaction.after ?? expected, inserted: plan, selection: finalCaret.map { NSRange(location: $0, length: 0) }) }
        undoSnapshot = SelectionSnapshot(element: snapshot.element, pid: snapshot.pid, appName: snapshot.appName, before: confirmedTransaction.before, range: snapshot.range)
        undoTransaction = confirmedTransaction; undoCaret = caret
        liveRecovery = finalCaret.map { CorrectionRecovery(transaction: confirmedTransaction, caretAfter: $0) }
    }
    @discardableResult func undo() async throws -> String? {
        guard !replacing else { throw SelectionError.message("A correction is already in progress.") }
        replacing = true; defer { replacing = false }
        // Restore the browser's focus reporting before reading recovery anchors.
        // prepareBrowser never selects a field or steals focus from a third app.
        if let saved = undoSnapshot, isBrowser(saved.element) { try await prepareBrowser(saved) }
        if let saved = undoSnapshot, let value = attribute(saved.element, kAXValueAttribute) as? String,
           let selection = selectedRange(saved.element) {
            refreshBrowserRecovery(in: saved, current: value, selection: selection)
        }
        guard let snapshot = undoSnapshot, let transaction = undoTransaction, let expected = transaction.after,
              let original = transaction.originalSelection else { return nil }
        var current = expected, result = snapshot.before
        var selection: NSRange?
        if let recovery = liveRecovery {
            try checkLiveField(snapshot.element)
            guard let value = attribute(snapshot.element, kAXValueAttribute) as? String,
                  let range = selectedRange(snapshot.element), let plan = recovery.plan(current: value, selection: range),
                  let restored = plan.transaction.after else {
                throw SelectionError.message("That word or its surrounding text changed. Nothing was replaced.")
            }
            current = value; result = restored; selection = plan.selection
        }
        try validate(snapshot, expected: current)
        let reversal = TextTransaction(before: current, range: transaction.replacementRange, replacement: original)
        let browser = isBrowser(snapshot.element)
        let plan = try await replace(snapshot, transaction: reversal, caret: browser && selection?.length == 0 ? selection.map { $0.location - reversal.replacementRange.length + reversal.range.length } : nil)
        if !browser, let selection { try setRange(snapshot.element, selection) }
        guard let confirmation = await confirm(snapshot, transaction: reversal, inserted: plan, caretAfter: selection?.length == 0 ? selection?.location : nil) else {
            clearUndo()
            throw SelectionError.message("The app did not confirm Undo. Check the original field.")
        }
        if browser { restoreCaretIfUnmoved(snapshot, expected: confirmation.transaction.after ?? result, inserted: plan, selection: selection) }
        clearUndo()
        return confirmation.value
    }
    func canRecover(in snapshot: SelectionSnapshot) -> Bool {
        guard let saved = undoSnapshot, saved.pid == snapshot.pid, CFEqual(saved.element, snapshot.element) else { return false }
        refreshBrowserRecovery(in: snapshot, current: snapshot.before, selection: snapshot.range)
        return liveRecovery?.canRecover(current: snapshot.before, selection: snapshot.range) == true
    }
    private func refreshBrowserRecovery(in snapshot: SelectionSnapshot, current: String, selection: NSRange) {
        guard let recovery = liveRecovery,
              !recovery.canRecover(current: current, selection: selection), isBrowser(snapshot.element),
              let saved = undoSnapshot, saved.pid == snapshot.pid, CFEqual(saved.element, snapshot.element),
              let transaction = undoTransaction,
              let actual = BrowserEditConfirmation.transaction(transaction, current: current,
                  affected: transaction.replacementRange, caretAfter: recovery.caretAfter) else { return }
        let refreshed = CorrectionRecovery(transaction: actual, caretAfter: recovery.caretAfter)
        guard refreshed.canRecover(current: current, selection: selection) else { return }
        undoTransaction = actual
        undoSnapshot = SelectionSnapshot(element: saved.element, pid: saved.pid, appName: saved.appName,
                                         before: actual.before, range: saved.range)
        liveRecovery = refreshed
    }
    func restoredOriginal(in snapshot: SelectionSnapshot) -> String? {
        guard let saved = undoSnapshot, saved.pid == snapshot.pid, CFEqual(saved.element, snapshot.element),
              liveRecovery?.recognizesOriginal(in: snapshot.before) == true else { return nil }
        return undoTransaction?.originalSelection
    }
    func clearUndo() { disableUndoShortcut(); undoSnapshot = nil; undoTransaction = nil; undoCaret = nil; liveRecovery = nil }
    private func validate(_ snapshot: SelectionSnapshot, expected: String) throws {
        guard !AppInstance.hasOtherCopy else { throw SelectionError.message(AppInstance.conflictMessage) }
        guard trusted, !IsSecureEventInputEnabled() else { throw SelectionError.message("Text access is unavailable. Nothing was replaced.") }
        try checkField(snapshot.element)
        let root = AXUIElementCreateApplication(snapshot.pid)
        AXUIElementSetMessagingTimeout(root, 0.5)
        guard let app = NSRunningApplication(processIdentifier: snapshot.pid), Self.canReadApplication(app),
              let current = attribute(snapshot.element, kAXValueAttribute) as? String, TextIdentity.matches(current, expected),
              let focused = attribute(root, kAXFocusedUIElementAttribute), CFEqual(focused, snapshot.element) else {
            throw SelectionError.message("The original field or its text has changed. Select the text again to avoid overwriting newer work.")
        }
    }
    private func isWritable(_ element: AXUIElement, _ name: String) -> Bool {
        var writable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &writable) == .success && writable.boolValue
    }
    private func isBrowser(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return false }
        return ["com.apple.Safari", "com.google.Chrome"].contains(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "")
    }
    private func canReplace(_ element: AXUIElement) -> Bool {
        if isBrowser(element) {
            // Chromium does not advertise AXSelectedText as writable. AXValue is
            // used only to check editability; never replace an entire document.
            return isWritable(element, kAXValueAttribute) && isWritable(element, kAXSelectedTextRangeAttribute)
        }
        return isWritable(element, kAXSelectedTextAttribute)
    }
    private func supportsMarkerOperation(_ element: AXUIElement) -> Bool {
        if capabilityElement.map({ CFEqual($0, element) }) != true {
            capabilityElement = element
            var raw: CFArray?
            markerOperationAvailable = AXUIElementCopyParameterizedAttributeNames(element, &raw) == .success
                && (raw as? [String])?.contains("AXTextOperation") == true
        }
        return markerOperationAvailable
    }
    private func parameter(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, value, &result) == .success else { return nil }
        return result
    }
    private func prepareBrowser(_ snapshot: SelectionSnapshot) async throws {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let app = NSRunningApplication(processIdentifier: snapshot.pid) {
            NSApp.yieldActivation(to: app)
            app.activate(from: .current, options: [.activateAllWindows])
        }
        for _ in 0..<8 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SelectionError.message("Return to the original browser field before applying this correction.")
    }
    private func replace(_ snapshot: SelectionSnapshot, transaction: TextTransaction, caret: Int?) async throws -> BrowserReplacementPlan {
        guard let plan = BrowserReplacementPlan(transaction: transaction, caret: caret) else {
            throw SelectionError.message("The caret moved too far from this word. Nothing was replaced.")
        }
        let browser = isBrowser(snapshot.element)
        let useMarkers = browser && supportsMarkerOperation(snapshot.element)
        if browser {
            guard canReplace(snapshot.element), useMarkers || plan.permitsUnicodeInsertion else {
                throw SelectionError.message("This browser can replace short words here. Use Copy result for a longer selection.")
            }
            try await prepareBrowser(snapshot)
            if !useMarkers {
                // A global Undo callback arrives on key-down. Wait for the
                // shortcut to be released before selecting any browser text.
                // Cancellation or a held shortcut leaves the field untouched.
                for _ in 0..<20 {
                    if CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else {
                    throw SelectionError.message("Release the keyboard shortcut before correcting this word.")
                }
            }
        }
        try validate(snapshot, expected: transaction.before)
        let originalRange = selectedRange(snapshot.element)
        if let caret, originalRange != NSRange(location: caret, length: 0) {
            throw SelectionError.message("The caret moved. Nothing was replaced.")
        }
        try setRange(snapshot.element, plan.range)
        var writeIssued = false
        do {
            // Web content selection is asynchronous. Never type into an
            // unconfirmed selection, and never retry a write after a timeout.
            for _ in 0..<8 {
                if selectedRange(snapshot.element) == plan.range { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try validate(snapshot, expected: transaction.before)
            guard selectedRange(snapshot.element) == plan.range,
                  (rangeAttribute(snapshot.element, "AXMarkedTextRange")?.length ?? 0) == 0,
                  !browser || NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid else {
                throw SelectionError.message("The selection changed before replacement. Nothing was replaced.")
            }
            if useMarkers {
                guard let marker = attribute(snapshot.element, "AXSelectedTextMarkerRange"),
                      let selected = parameter(snapshot.element, "AXStringForTextMarkerRange", marker) as? String,
                      TextIdentity.matches(selected, (transaction.before as NSString).substring(with: plan.range)) else {
                    throw SelectionError.message("The browser could not confirm the selected word. Nothing was replaced.")
                }
                try validate(snapshot, expected: transaction.before)
                let request = ["AXTextOperationType": "TextOperationReplacePreserveCase",
                               "AXTextOperationMarkerRanges": [marker],
                               "AXTextOperationReplacementString": plan.text,
                               "AXTextOperationSmartReplace": false] as CFDictionary
                writeIssued = true
                guard parameter(snapshot.element, "AXTextOperation", request) != nil else {
                    throw SelectionError.message("The browser did not confirm the edit request. Check the original field.")
                }
            } else if browser {
                // Only the two supported browsers, their current focused editable
                // field, and a single small Unicode insertion. No clipboard,
                // global event tap, simulated shortcuts, or whole-field writes.
                let modifiers = CGEventSource.flagsState(.combinedSessionState)
                guard modifiers.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
                      let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    throw SelectionError.message("Finish the keyboard shortcut before correcting this word.")
                }
                let units = Array(plan.text.utf16)
                down.flags = []; up.flags = []
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                writeIssued = true
                down.postToPid(snapshot.pid); up.postToPid(snapshot.pid)
            } else {
                writeIssued = true
                guard AXUIElementSetAttributeValue(snapshot.element, kAXSelectedTextAttribute as CFString, plan.text as CFString) == .success else {
                    throw SelectionError.message("This app refused the replacement. Use Copy result instead.")
                }
            }
        } catch {
            // Restore only our own selection, while the entire text is unchanged.
            if !writeIssued, let originalRange, selectedRange(snapshot.element) == plan.range,
               let value = attribute(snapshot.element, kAXValueAttribute) as? String,
               TextIdentity.matches(value, transaction.before) {
                try? setRange(snapshot.element, originalRange)
            }
            throw error
        }
        return plan
    }
    private func confirm(_ snapshot: SelectionSnapshot, transaction: TextTransaction, inserted: BrowserReplacementPlan, caretAfter: Int?) async -> (value: String, transaction: TextTransaction)? {
        guard let expected = transaction.after else { return nil }
        for _ in 0..<16 {
            if let value = attribute(snapshot.element, kAXValueAttribute) as? String {
                if TextIdentity.matches(value, expected) { return (value, transaction) }
                if let caretAfter, let selection = selectedRange(snapshot.element),
                   CorrectionRecovery(transaction: transaction, caretAfter: caretAfter).canRecover(current: value, selection: selection) { return (value, transaction) }
                if isBrowser(snapshot.element),
                   let actual = BrowserEditConfirmation.transaction(transaction, current: value,
                       affected: NSRange(location: inserted.range.location, length: inserted.text.utf16.count), caretAfter: caretAfter),
                   TextIdentity.matches(value, actual.after ?? "") || (caretAfter.flatMap { caret in
                       selectedRange(snapshot.element).map { CorrectionRecovery(transaction: actual, caretAfter: caret).canRecover(current: value, selection: $0) }
                   } ?? false) { return (value, actual) }
                // A different edit is not a stale AX response. Stop, never repair it.
                if !TextIdentity.matches(value, transaction.before) { return nil }
            }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return nil }
        }
        return nil
    }
    private func restoreCaretIfUnmoved(_ snapshot: SelectionSnapshot, expected: String, inserted: BrowserReplacementPlan, selection: NSRange?) {
        guard let selection, let current = selectedRange(snapshot.element),
              current == NSRange(location: inserted.range.location + inserted.text.utf16.count, length: 0)
                || current == NSRange(location: inserted.range.location, length: inserted.text.utf16.count),
              let value = attribute(snapshot.element, kAXValueAttribute) as? String, TextIdentity.matches(value, expected),
              (try? validate(snapshot, expected: expected)) != nil else { return }
        if current != selection { try? setRange(snapshot.element, selection) }
    }
    private func setRange(_ element: AXUIElement, _ range: NSRange) throws {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success else {
            throw SelectionError.message("This app could not restore the selection. Nothing was replaced.")
        }
    }
    private func checkField(_ element: AXUIElement) throws {
        let role = attribute(element, kAXRoleAttribute) as? String
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        let protected = attribute(element, "AXProtectedContent") as? Bool ?? false
        guard [kAXTextAreaRole, kAXTextFieldRole].contains(role ?? ""), subrole != kAXSecureTextFieldSubrole, !protected else {
            throw SelectionError.message("idkthen only reads editable, non-secure text fields.")
        }
    }
    func checkLiveField(_ element: AXUIElement, duringObservation: Bool = false) throws {
        let editable = canReplace(element)
        let completion = (attribute(element, "AXExpanded") as? Bool == true)
            || ((attribute(element, "AXARIAAutocomplete") as? String).map { !["none", ""].contains($0) } ?? false)
        guard LiveFieldPolicy.allows(role: attribute(element, kAXRoleAttribute) as? String,
                                    subrole: attribute(element, kAXSubroleAttribute) as? String,
                                    protected: attribute(element, "AXProtectedContent") as? Bool ?? false,
                                    editable: editable,
                                    hasMarkedText: !duringObservation && (rangeAttribute(element, "AXMarkedTextRange")?.length ?? 0) > 0,
                                    hasCompletion: !duringObservation && completion,
                                    contentRole: attribute(element, "AXARIARole") as? String) else {
            throw SelectionError.message("This field is review-only. Live correction skips single-line, search, completion and secure fields.")
        }
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        rangeAttribute(element, kAXSelectedTextRangeAttribute)
    }
    private func rangeAttribute(_ element: AXUIElement, _ name: String) -> NSRange? {
        guard let raw = attribute(element, name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
