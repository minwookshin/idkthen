import AppKit
import ApplicationServices
import Carbon
import IdkthenCore

/// Observes Accessibility text-change notifications only in explicitly enabled apps.
/// No event tap, keystroke buffer, clipboard reads, or input-monitoring permission.
@MainActor final class LiveTypingController {
    var onStatus: ((String) -> Void)?
    var onHistoryChanged: ((String) -> Void)?
    var onWordUndone: ((UndoFeedback) -> Bool)?
    var onCorrectionApplied: ((String) -> Void)?
    var onConnectionStatus: ((String, ConnectionStatus) -> Void)?
    var onPauseChanged: (() -> Void)?
    var onFrontmostApp: ((String?) -> Void)?
    private let bridge: SelectionBridge
    private let spelling = MacSpelling()
    private let panel = LiveSuggestionPanel()
    private var observer: AXObserver?
    private var root: AXUIElement?
    private var field: AXUIElement?
    private var app: NSRunningApplication?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var inputSourceToken: NSObjectProtocol?
    private var inputSourceID: String?
    private var pending: Task<Void, Never>?
    private var inspection: Task<Void, Never>?
    private var pauseWake: Task<Void, Never>?
    private var undoExpiry: Task<Void, Never>?
    private var interventions = TypingInterventions()
    private var undoChoice = UndoShortcutChoice.controlShiftZ
    private var wantsUndoShortcut = true
    private var allowed: Set<String> = []
    private var languages = LanguageSelection([.korean])
    private var profiles = LanguageProfiles(defaults: LanguageSelection([.korean]))
    private var undoFeedback: (transaction: TextTransaction, receipt: UndoFeedback)?
    private var mode = LiveCorrectionMode.suggest
    private var useContext = true
    private var sessionKeep: Set<String> = []
    private var keepWords: Set<String> = []
    private var lastValue: String?
    private var candidateGate = LiveCandidateGate()
    private var sawValueChange = false
    private var running = false
    private var sessionActive = true
    private var mutating = false
    private var current: (snapshot: SelectionSnapshot, change: Change, caret: Int, bounds: CGRect?)?

    init(bridge: SelectionBridge) {
        self.bridge = bridge
        panel.onAccept = { [weak self] in self?.accept() }
        panel.onDismiss = { [weak self] in self?.dismiss(recordIgnored: true) }
        panel.onUndo = { [weak self] in self?.undo() }
        bridge.onUndoShortcut = { [weak self] in self?.undoFromKeyboard() }
    }
    func configure(languages: LanguageSelection, appLanguages: [String: LanguageSelection] = [:], keepWords: Set<String>, allowed: Set<String>, mode: LiveCorrectionMode, useContext: Bool) {
        profiles = LanguageProfiles(defaults: languages, overrides: appLanguages)
        self.languages = profiles.selection(for: app?.bundleIdentifier); self.keepWords = keepWords; self.allowed = allowed
        self.mode = mode; self.useContext = useContext
        spelling.clearCache()
        if running { attachFrontmost() }
    }
    func start() throws {
        guard bridge.trusted else { throw SelectionError.message("Allow Accessibility access, then turn on Live suggestions.") }
        guard !allowed.isEmpty else { throw SelectionError.message("Add an app below before turning on Live suggestions.") }
        guard !running else { return }
        running = true; sessionActive = true
        inputSourceToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.attachFrontmost() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if name == NSWorkspace.sessionDidBecomeActiveNotification { self?.sessionActive = true }
                    self?.attachFrontmost()
                }
            })
        }
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sessionActive = false; self?.pauseWake?.cancel(); self?.pauseWake = nil
                self?.detach(); self?.onStatus?("Paused while your Mac is locked.")
            }
        })
        attachFrontmost()
    }
    func stop() {
        running = false; detach(); pauseWake?.cancel(); pauseWake = nil
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll(); spelling.clearCache()
        if let inputSourceToken { DistributedNotificationCenter.default().removeObserver(inputSourceToken) }
        inputSourceToken = nil
        onStatus?("Off · no background text access")
    }
    func dismiss(recordIgnored: Bool = false, cancelInspection: Bool = true) {
        if recordIgnored, let current { interventions.ignore(current.change.original, now: ProcessInfo.processInfo.systemUptime) }
        pending?.cancel(); pending = nil; current = nil; panel.hide()
        if cancelInspection { inspection?.cancel(); inspection = nil }
    }
    func configureUndoShortcut(_ choice: UndoShortcutChoice, enabled: Bool) {
        undoChoice = choice; wantsUndoShortcut = enabled; bridge.disableUndoShortcut()
        if running, let app, let captured = try? bridge.captureCaret(from: app) { updateUndoShortcut(captured) }
    }
    func isPaused(_ bundle: String) -> Bool { interventions.paused(bundle, now: ProcessInfo.processInfo.systemUptime) }
    func pause(_ bundle: String) {
        guard allowed.contains(bundle) else { return }
        interventions.pause(bundle, now: ProcessInfo.processInfo.systemUptime)
        if running { attachFrontmost() }; onPauseChanged?()
    }
    func resume(_ bundle: String) {
        interventions.resume(bundle)
        if running { attachFrontmost() }; onPauseChanged?()
    }
    private func schedulePauseExpiry() {
        pauseWake?.cancel(); pauseWake = nil
        let now = ProcessInfo.processInfo.systemUptime
        guard running, let next = allowed.compactMap({ interventions.deadline(for: $0) }).filter({ $0 > now }).min() else { return }
        pauseWake = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(next - now)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.attachFrontmost(); self.onPauseChanged?()
        }
    }
    private func updateUndoShortcut(_ captured: SelectionSnapshot) {
        if wantsUndoShortcut, bridge.canRecover(in: captured) { bridge.enableUndoShortcut(undoChoice) }
        else { bridge.disableUndoShortcut() }
    }
    private func expireUndoLater() {
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if self.bridge.hasLiveUndo { self.bridge.clearUndo(); self.undoFeedback = nil; self.panel.hide(); self.onHistoryChanged?("Recent correction expired.") }
        }
    }
    func resolvedLanguages(for bundle: String) -> LanguageSelection { profiles.selection(for: bundle) }
    @discardableResult func rememberUndo(_ original: String, transaction: TextTransaction? = nil) -> Bool {
        guard original.count <= 96, !original.contains(where: { $0.isWhitespace }) else { return false }
        keepForSession(original)
        guard let transaction, let feedback = undoFeedback,
              TextIdentity.matches(transaction.before, feedback.transaction.before), transaction.range == feedback.transaction.range,
              TextIdentity.matches(transaction.replacement, feedback.transaction.replacement) else { return false }
        undoFeedback = nil
        return onWordUndone?(feedback.receipt) ?? false
    }
    private func keepForSession(_ original: String) {
        let word = original.lowercased().precomposedStringWithCanonicalMapping
        if sessionKeep.count >= 256, !sessionKeep.contains(word), let oldest = sessionKeep.first { sessionKeep.remove(oldest) }
        sessionKeep.insert(word)
    }
    func forgetWord(_ original: String) { sessionKeep.remove(original.lowercased().precomposedStringWithCanonicalMapping) }
    func clearSession() {
        dismiss(); sessionKeep.removeAll(); undoFeedback = nil; spelling.clearCache()
        undoExpiry?.cancel(); interventions.clear(); onPauseChanged?()
        if running { attachFrontmost() }
    }
    private func detach() {
        dismiss(); bridge.disableUndoShortcut(); interventions.resetField()
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; root = nil; field = nil; app = nil; lastValue = nil; candidateGate.reset(); sawValueChange = false
    }
    private func attachFrontmost() {
        detach()
        guard running, sessionActive else { return }
        inputSourceID = KeyboardInputSource.identifier
        schedulePauseExpiry()
        // Opening the popover may activate idkthen before its action runs.
        // Remember foreground app metadata from workspace changes, not UI focus.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            onFrontmostApp?(front.bundleIdentifier)
        }
        guard bridge.trusted else { onStatus?("Accessibility access is unavailable. Turn live mode off and check Settings."); return }
        guard let target = NSWorkspace.shared.frontmostApplication, let bundle = target.bundleIdentifier,
              allowed.contains(bundle), SelectionBridge.canReadApplication(target) else {
            onStatus?("On · waiting for an enabled app"); return
        }
        guard !isPaused(bundle) else { onStatus?("Paused in \(target.localizedName ?? "this app") · resumes automatically"); return }
        languages = profiles.selection(for: bundle)
        var newObserver: AXObserver?
        guard AXObserverCreate(target.processIdentifier, { _, _, name, context in
            guard let context else { return }
            let owner = Unmanaged<LiveTypingController>.fromOpaque(context).takeUnretainedValue()
            let name = name as String
            Task { @MainActor in owner.received(name) }
        }, &newObserver) == .success, let newObserver else {
            onConnectionStatus?(bundle, .unsupported)
            onStatus?("This app cannot provide live text updates. Use Import selection."); return
        }
        app = target; observer = newObserver
        let application = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2); root = application
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(newObserver, application, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        bindField()
    }
    private func bindField() {
        dismiss(); bridge.disableUndoShortcut(); interventions.resetField(); sawValueChange = false; lastValue = nil; candidateGate.reset()
        guard let observer, let root, let app else { return }
        if let field {
            for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification, kAXUIElementDestroyedNotification] {
                AXObserverRemoveNotification(observer, field, name as CFString)
            }
        }
        field = nil
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            if let bundle = app.bundleIdentifier { onConnectionStatus?(bundle, .waitingForField) }
            onStatus?("Click a text field in \(app.localizedName ?? "the enabled app")."); return
        }
        let focused = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, 0.2)
        do { try bridge.checkLiveField(focused, duringObservation: true) }
        catch {
            if let bundle = app.bundleIdentifier { onConnectionStatus?(bundle, .unsupported) }
            onStatus?(error.localizedDescription); return
        }
        field = focused
        let context = Unmanaged.passUnretained(self).toOpaque()
        let valueResult = AXObserverAddNotification(observer, focused, kAXValueChangedNotification as CFString, context)
        AXObserverAddNotification(observer, focused, kAXSelectedTextChangedNotification as CFString, context)
        AXObserverAddNotification(observer, focused, kAXUIElementDestroyedNotification as CFString, context)
        var capturedCaret = false
        if let captured = try? bridge.captureCaret(from: app) {
            capturedCaret = true
            lastValue = captured.before
            updateUndoShortcut(captured)
            candidateGate.reset(text: captured.before, selection: captured.range)
        }
        if let bundle = app.bundleIdentifier {
            onConnectionStatus?(bundle, valueResult == .success || valueResult == .notificationAlreadyRegistered
                                ? (capturedCaret ? .observing : .waitingForField) : .unsupported)
        }
        if languages.partners.contains(where: { !KeyboardLayoutPolicy.permits($0, sourceID: inputSourceID) }) {
            if let bundle = app.bundleIdentifier { onConnectionStatus?(bundle, .unsupportedLayout) }
            onStatus?("Layout recovery is paused for this keyboard. Accent review is still available.")
            return
        }
        if languages.partners.allSatisfy({ !$0.usesAccents && !spelling.supportsAutomaticLayoutDetection($0.spellLanguage) }) {
            onStatus?("Enabled layouts need manual review on this Mac · use Import selection.")
            return
        }
        onStatus?(valueResult == .success || valueResult == .notificationAlreadyRegistered
                  ? "Ready in \(app.localizedName ?? "your app") · type a word, then Space"
                  : "This field does not provide live text updates. Use Import selection.")
    }
    private func received(_ name: String) {
        guard running, !mutating else { return }
        if name == kAXFocusedUIElementChangedNotification || name == kAXFocusedWindowChangedNotification || name == kAXUIElementDestroyedNotification {
            bindField(); return
        }
        // Hide immediately when the caret or text changes. A stale card never follows the user.
        dismiss(recordIgnored: true, cancelInspection: false)
        if name == kAXValueChangedNotification { sawValueChange = true }
        // Inspect within one 20 ms window from the first notification. Repeated
        // selection/value signals cannot slide this deadline indefinitely.
        guard inspection == nil else { return }
        inspection = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.inspection = nil
            self.pending = Task { [weak self] in await self?.inspectCompletedWord() }
        }
    }
    private func inspectCompletedWord() async {
        guard running, !mutating, let app else { return }
        // Check again at the boundary in case the distributed notification is late.
        guard KeyboardInputSource.identifier == inputSourceID else { attachFrontmost(); return }
        let valueChanged = sawValueChange
        sawValueChange = false
        do {
            let captured = try bridge.captureCaret(from: app)
            guard let field, CFEqual(captured.element, field) else { bindField(); return }
            if let original = bridge.restoredOriginal(in: captured) {
                // The host's own Undo is also a rejection, but only after the
                // same anchored transaction has demonstrably returned to its original.
                _ = rememberUndo(original, transaction: bridge.undoTransaction)
                bridge.clearUndo(); undoFeedback = nil
                onHistoryChanged?("Kept your restored spelling for this session.")
            }
            updateUndoShortcut(captured)
            let acceptsSelectionSignal = app.bundleIdentifier == "com.google.Chrome"
            guard valueChanged || acceptsSelectionSignal else { return }
            guard lastValue.map({ TextIdentity.matches($0, captured.before) }) != true else { return }
            let previous = lastValue
            lastValue = captured.before
            // Preserve paste/IME protection without resurrecting an ignored word
            // when a later keystroke produces a small delta.
            guard let previous, let word = candidateGate.completed(previous: previous, current: captured.before,
                selection: captured.range, valueChanged: valueChanged, acceptsSelectionSignal: acceptsSelectionSignal,
                whileContinuing: mode == .automatic) else { return }
            spelling.clearCache()
            let engine = ReviewEngine(spelling: spelling)
            let compatible = languages.partners.filter { KeyboardLayoutPolicy.permits($0, sourceID: inputSourceID) }
            guard !compatible.isEmpty else { return }
            let activeLanguages = LanguageSelection(compatible)
            let change: Change
            var automatic = false
            var needsContext = false
            if mode == .automatic {
                switch FastTypingPlan.make(word: word, document: captured.before, engine: engine, languages: activeLanguages, keepWords: keepWords.union(sessionKeep)) {
                case .skip: return
                case .immediate(let candidate): change = candidate; automatic = true
                case .context(let candidate): change = candidate; needsContext = useContext
                }
            } else {
                let before = String((captured.before as NSString).substring(to: word.range.location).suffix(64))
                guard let candidate = word.suggestion(using: engine, languages: activeLanguages, keepWords: keepWords.union(sessionKeep), precedingContext: before) else { return }
                change = candidate
            }
            guard !interventions.suppressed(change.original, now: ProcessInfo.processInfo.systemUptime),
                  !ReviewVisibility.isQuietAlternative(change, in: captured.before, spelling: spelling) else { return }
            guard let context = CorrectionContext(text: captured.before, change: change), !context.protectsLiteralOrSlang else { return }
            if mode == .suggest {
                do { try await Task.sleep(for: .milliseconds(330)) } catch { return }
            }
            guard !Task.isCancelled, let latest = try? bridge.captureCaret(from: app),
                  TextIdentity.matches(latest.before, captured.before), latest.range == captured.range, CFEqual(latest.element, captured.element) else { return }
            let bounds = bridge.bounds(for: captured.element, range: captured.range)
            // A verified character offset is required for every edit. Screen
            // geometry is only needed to place a suggestion, not for a quiet
            // automatic edit (Chrome rich fields may omit AXBoundsForRange).
            guard automatic || bounds != nil else {
                onStatus?("This app does not expose the caret position. Use Import selection."); return
            }
            let snapshot = SelectionSnapshot(element: captured.element, pid: captured.pid, appName: captured.appName, before: captured.before, range: change.range)
            current = (snapshot, change, captured.range.location, bounds)
            if automatic { accept(automatically: true); return }
            guard let bounds else { return }
            // A useful suggestion is available immediately; a model never blocks its UI.
            panel.show(original: change.original, replacement: change.candidates[0], languages: languages, near: bounds)
            guard needsContext, ContextGuard.resourcesAllowed else { return }
            // Continuing to type cancels here before loading an expensive model.
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard !Task.isCancelled, running, current != nil else { return }
            let decision = await ContextGuard.evaluate(context, languages: languages, candidateLanguages: change.languages)
            guard !Task.isCancelled, running, !mutating, current != nil,
                  let fresh = try? bridge.captureCaret(from: app),
                  TextIdentity.matches(fresh.before, captured.before), fresh.range == captured.range,
                  CFEqual(fresh.element, captured.element) else { return }
            switch decision {
            case .keep:
                current = nil; panel.hide(); onStatus?("Kept “\(change.original)” in this context.")
            case .unsure:
                onStatus?("Suggestion ready · choose whether to apply it")
            case .correct:
                accept(automatically: true)
            }
        } catch { onStatus?(error.localizedDescription) }
    }
    private func accept(automatically: Bool = false) {
        guard let suggestion = current, !mutating else { return }
        guard KeyboardInputSource.identifier == inputSourceID else { attachFrontmost(); return }
        let replacement = suggestion.change.candidates[0]
        mutating = true; dismiss(); sawValueChange = false
        Task {
            do {
                try await bridge.apply(replacement, snapshot: suggestion.snapshot, caret: suggestion.caret)
                if let transaction = bridge.undoTransaction {
                    undoFeedback = (transaction, UndoFeedback(original: suggestion.change.original))
                }
                lastValue = bridge.undoTransaction?.after
                let message = "\(automatically ? "Auto-corrected" : "Applied") “\(replacement)” in \(suggestion.snapshot.appName)."
                onHistoryChanged?(message); onStatus?(message)
                if let bundle = NSRunningApplication(processIdentifier: suggestion.snapshot.pid)?.bundleIdentifier { onCorrectionApplied?(bundle) }
                expireUndoLater()
                if running, NSWorkspace.shared.frontmostApplication?.processIdentifier == suggestion.snapshot.pid {
                    if let app, let captured = try? bridge.captureCaret(from: app) { updateUndoShortcut(captured) }
                    // Quiet success when keyboard recovery is available. A conflict or
                    // disabled shortcut keeps the visible, accessible Undo fallback.
                    if let bounds = suggestion.bounds,
                       !automatically || !bridge.undoShortcutEnabled || NSWorkspace.shared.isVoiceOverEnabled {
                        panel.showUndo(replacement: replacement, near: bounds, automatic: automatically)
                    }
                }
            } catch {
                if let bundle = NSRunningApplication(processIdentifier: suggestion.snapshot.pid)?.bundleIdentifier {
                    onConnectionStatus?(bundle, .replacementFailed)
                }
                onStatus?(error.localizedDescription); onHistoryChanged?(error.localizedDescription)
            }
            mutating = false
            if running, let app, let latest = try? bridge.captureCaret(from: app), lastValue.map({ TextIdentity.matches($0, latest.before) }) != true {
                received(kAXValueChangedNotification)
            }
        }
    }
    private func undoFromKeyboard() {
        guard running, let app, let bundle = app.bundleIdentifier, !isPaused(bundle),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let captured = try? bridge.captureCaret(from: app), bridge.canRecover(in: captured) else {
            bridge.disableUndoShortcut(); return
        }
        undo()
    }
    func undoRecent() { undo() }
    private func undo() {
        guard !mutating, let transaction = bridge.undoTransaction, let original = transaction.originalSelection else { return }
        let bundle = bridge.undoSnapshot.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier }
        mutating = true; dismiss(); sawValueChange = false
        Task {
            do {
                lastValue = try await bridge.undo()
                let learned = rememberUndo(original, transaction: transaction)
                if let bundle { onConnectionStatus?(bundle, .observing) }
                onHistoryChanged?(learned ? "Restored. “\(original)” will now be kept across apps." : "Restored the original word. Keeping it unchanged for this session.")
            } catch {
                if let bundle {
                    onConnectionStatus?(bundle, .undoFailed)
                }
                onStatus?(error.localizedDescription); onHistoryChanged?(error.localizedDescription)
            }
            mutating = false
        }
    }
}
