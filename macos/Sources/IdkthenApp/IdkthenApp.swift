import AppKit
import SwiftUI
import IdkthenCore

@main enum IdkthenApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--audit-corpus") {
            guard CommandLine.arguments.indices.contains(index + 1) else { exit(2) }
            exit(ScenarioAudit.run(path: CommandLine.arguments[index + 1]) ? 0 : 2)
        }
        if CommandLine.arguments.contains("--product-test") { exit(ProductChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--lifecycle-test") { exit(LifecycleChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--efficiency-test") {
            Task { @MainActor in exit(await EfficiencyChecks.run() ? 0 : 1) }
            app.run(); return
        }
        if CommandLine.arguments.contains("--context-test") {
            Task { @MainActor in exit(await ContextGuard.runChecks() ? 0 : 1) }
            app.run(); return
        }
        if CommandLine.arguments.contains("--self-test") { exit(ModelChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--usability-test") { exit(UsabilityChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--practice-test") { exit(PracticeChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--personalization-test") { exit(PersonalizationChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--language-set-test") { exit(LanguageSetChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--multilingual-test") { exit(MultilingualChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--typing-test") { exit(TypingChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--conversation-test") { exit(ConversationChecks.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--smoke-test") {
            let spelling = MacSpelling()
            let engine = ReviewEngine(spelling: spelling)
            var failures = 0
            for pair in LanguagePair.allCases {
                let result = engine.review(pair.sample, pair: pair)
                let choices = Dictionary(uniqueKeysWithValues: result.changes.filter { !$0.ambiguous }.map { ($0.id, $0.candidates[0]) })
                print("\(pair.code): \(result.changes.count) suggestions, \(choices.count) preselected, \(result.protectedCount) protected")
                print(result.applying(choices))
                if result.changes.isEmpty || (result.notice != nil && spelling.supportsAutomaticLayoutDetection(pair.spellLanguage)) { failures += 1 }
            }
            let cases: [(LanguagePair, String, String)] = [
                (.spanish, "manana", "mañana"), (.french, "resume", "résumé"),
                (.german, "strasse", "straße"), (.portuguese, "amanha", "amanhã"),
                (.korean, "dkssud", "안녕"), (.korean, "ㅗ디ㅣㅐ", "hello"),
                (.ukrainian, "ghbdsn", "привіт"), (.ukrainian, "руддщ", "hello")
            ]
            for (pair, input, expected) in cases {
                let result = engine.review(input, pair: pair)
                let passed = result.changes.contains { $0.original == input && $0.candidates.contains(expected) }
                print("CHECK \(pair.code) \(input) → \(expected): \(passed ? "PASS" : "FAIL")")
                if !passed { failures += 1 }
            }
            let ambiguous = engine.review("resume", pair: .french).changes
            if ambiguous.isEmpty || !ambiguous.allSatisfy(\.ambiguous) { failures += 1 }
            if !engine.review("https://example.com/manana", pair: .spanish).changes.isEmpty { failures += 1 }
            print("SYSTEM_DICTIONARY_SMOKE \(failures == 0 ? "PASS" : "FAIL")")
            exit(failures == 0 ? 0 : 1)
        }
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let model = AppModel()
    private let navigation = PanelNavigation()
    private let popover = NSPopover()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var workspaceTokens: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.revealWindow = { [weak self] in self?.showWindow() }
        model.pairDidChange = { [weak self] in self?.updateStatus() }
        model.liveDidChange = { [weak self] in self?.updateStatus() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("idkthen")
        }
        let controller = NSHostingController(rootView: MenuBarView(model: model, navigation: navigation,
            openReview: { [weak self] in self?.showWindow() },
            closePanel: { [weak self] in self?.popover.performClose(nil) }))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = controller.view.fittingSize
        popover.behavior = .transient
        popover.animates = false
        updateStatus(); buildMainMenu(); model.restoreLivePreference()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.refreshTypingAvailability() }
            })
        }
        // A configured utility stays in the menu bar without stealing typing focus.
        if model.setupStep != .done || model.hasConflictingCopy { DispatchQueue.main.async { [weak self] in self?.showPanel() } }
    }
    func showWindow() {
        popover.performClose(nil)
        if window == nil {
            let review = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            review.title = "idkthen · Text review"
            review.minSize = NSSize(width: 780, height: 580)
            review.isReleasedWhenClosed = false
            review.delegate = self
            review.contentView = NSHostingView(rootView: MainView(model: model,
                openSettings: { [weak self] in self?.showPanel(.settings) },
                openLanguages: { [weak self] in self?.showReviewLanguages() }))
            review.center(); window = review
        }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refreshPermission()
    }
    private func showPanel(_ page: PanelPage = .home) {
        guard let button = statusItem?.button else { return }
        model.rememberCurrentApp()
        navigation.page = page == .home && model.setupStep != .done ? .setup : page
        model.refreshPermission()
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
    private func showReviewLanguages() {
        if let bundle = model.sourceBundleIdentifier, model.liveApps[bundle] != nil {
            navigation.appBundle = bundle; showPanel(.appLanguages)
        } else { showPanel(.languages) }
    }
    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control),
           let button = statusItem?.button {
            popover.performClose(nil)
            model.rememberCurrentApp(); model.refreshPermission()
            NSMenu.popUpContextMenu(quickMenu(), with: event, for: button)
            return
        }
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }
    @objc private func toggleTyping() {
        if !model.liveRequested && (!model.permissionGranted || model.liveApps.isEmpty) {
            showPanel(model.permissionGranted ? .apps : .settings); return
        }
        model.setLiveEnabled(!model.liveRequested)
    }
    @objc private func toggleCurrentApp() {
        guard let bundle = model.currentAppBundle, model.liveApps[bundle] != nil, model.liveEnabled else { return }
        if model.pausedApps.contains(bundle) { model.resumeApp(bundle) } else { model.pauseApp(bundle) }
    }
    @objc private func undoLiveCorrection() { model.undo() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshPermission() }
    func windowDidBecomeKey(_ notification: Notification) { model.refreshPermission() }
    @objc private func openReview() { showWindow() }
    @objc private func showSettings() { showPanel(.settings) }
    @objc private func closeWindow() {
        if popover.isShown { popover.performClose(nil) }
        else { window?.performClose(nil) }
    }
    @objc private func undoAction(_ sender: Any?) {
        if NSApp.keyWindow === window, model.canUndoReview { model.undoReview() }
        else if let manager = NSApp.keyWindow?.firstResponder?.undoManager, manager.canUndo { manager.undo() }
    }
    @objc private func redoAction(_ sender: Any?) {
        if NSApp.keyWindow === window, model.canRedo { model.redo() }
        else if let manager = NSApp.keyWindow?.firstResponder?.undoManager, manager.canRedo { manager.redo() }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTyping) {
            menuItem.title = model.liveRequested ? "Pause idkthen" : "Turn On idkthen"
            return !model.applying
        }
        if menuItem.action == #selector(undoLiveCorrection) { return model.bridge.hasLiveUndo && !model.applying }
        if menuItem.action == #selector(closeWindow) { return popover.isShown || window?.isVisible == true }
        if menuItem.action == #selector(undoAction(_:)) {
            let editorCanUndo = NSApp.keyWindow?.firstResponder?.undoManager?.canUndo == true
            let correctionCanUndo = NSApp.keyWindow === window && model.canUndoReview
            menuItem.title = correctionCanUndo ? "Undo Correction" : "Undo"
            return !model.applying && (editorCanUndo || correctionCanUndo)
        }
        if menuItem.action == #selector(redoAction(_:)) {
            let editorCanRedo = NSApp.keyWindow?.firstResponder?.undoManager?.canRedo == true
            let correctionCanRedo = NSApp.keyWindow === window && model.canRedo
            menuItem.title = correctionCanRedo ? "Redo Correction" : "Redo"
            return !model.applying && (editorCanRedo || correctionCanRedo)
        }
        return true
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let state = model.menuBarState
        let icon = NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        icon?.isTemplate = true
        button.image = icon
        let mode = model.liveMode == .automatic ? "Automatic" : "Suggest"
        button.toolTip = "idkthen · \(state.label)\n\(model.homeStatus)\n\(mode) · \(model.languages(for: model.currentAppBundle).codes)\nRight-click for quick controls."
        button.setAccessibilityValue(state.label)
    }
    private func quickMenu() -> NSMenu {
        let menu = NSMenu()
        let status = menu.addItem(withTitle: "idkthen · \(model.menuBarState.label)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        let toggle = menu.addItem(withTitle: model.liveRequested ? "Pause idkthen" : "Turn On idkthen", action: #selector(toggleTyping), keyEquivalent: "")
        toggle.target = self
        if model.liveEnabled, let bundle = model.currentAppBundle, let name = model.liveApps[bundle] {
            let title = model.pausedApps.contains(bundle) ? "Resume in \(name)" : "Pause \(name) for 10 Minutes"
            menu.addItem(withTitle: title, action: #selector(toggleCurrentApp), keyEquivalent: "").target = self
        }
        if model.bridge.hasLiveUndo {
            menu.addItem(withTitle: "Undo Last Correction", action: #selector(undoLiveCorrection), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit idkthen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
        return menu
    }
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Pause idkthen", action: #selector(toggleTyping), keyEquivalent: "").target = self
        let prefs = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ","); prefs.target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit idkthen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let file = NSMenu(title: "File")
        let review = file.addItem(withTitle: "Review text…", action: #selector(openReview), keyEquivalent: ""); review.target = self
        let close = file.addItem(withTitle: "Close Window", action: #selector(closeWindow), keyEquivalent: "w"); close.target = self
        fileItem.submenu = file; main.addItem(fileItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let edit = NSMenu(title: "Edit")
        let undo = edit.addItem(withTitle: "Undo", action: #selector(undoAction(_:)), keyEquivalent: "z"); undo.target = self
        let redo = edit.addItem(withTitle: "Redo", action: #selector(redoAction(_:)), keyEquivalent: "Z"); redo.target = self
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
