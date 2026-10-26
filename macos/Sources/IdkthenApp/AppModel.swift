import AppKit
import SwiftUI
import IdkthenCore

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var languages: LanguageSelection
    var pair: LanguagePair { languages.partners[0] }
    @Published var input: String
    @Published var direction: ReviewDirection = .detect
    @Published var review: Review?
    @Published private(set) var decisions = ReviewChoices()
    @Published var message = ""
    @Published var isError = false
    @Published var keepList: String
    @Published var lastKeptWord: String?
    @Published private(set) var lastRestoredWord: String?
    @Published var shortcutEnabled = false
    @Published var shortcutChoice: ShortcutChoice
    @Published var permissionGranted = false
    @Published var sourceApp: String?
    @Published private(set) var sourceBundleIdentifier: String?
    @Published var availableSourceApps: [NSRunningApplication] = []
    @Published var applying = false
    @Published var canUndo = false
    @Published var canRedo = false
    var canUndoReview: Bool { localUndo != nil || (bridge.undoTransaction != nil && !bridge.hasLiveUndo) }
    @Published private(set) var liveEnabled = false
    @Published private(set) var liveRequested: Bool
    @Published private(set) var liveStatus = "Off · no background text access"
    @Published private(set) var liveApps: [String: String]
    @Published private(set) var liveMode: LiveCorrectionMode
    @Published private(set) var contextEnabled: Bool
    @Published private(set) var appLanguages: [String: LanguageSelection]
    @Published private(set) var learningEnabled: Bool
    @Published private(set) var undoShortcutChoice: UndoShortcutChoice
    @Published private(set) var undoShortcutEnabled: Bool
    @Published private(set) var setupStep: SetupStep
    @Published private(set) var verifiedApp: String?
    @Published private(set) var connectionStatuses: [String: ConnectionStatus] = [:]
    func connectionStatus(for bundle: String?) -> ConnectionStatus {
        bundle.flatMap { connectionStatuses[$0] } ?? .waitingForField
    }
    var homeStatus: String {
        guard liveRequested else { return "Paused. Your text stays as typed." }
        guard permissionGranted else { return "Allow Accessibility to use idkthen in your apps." }
        guard !liveApps.isEmpty else { return "Choose an app to use While You Type." }
        guard liveEnabled else { return "Could not connect. Turn While You Type off and on to retry." }
        guard let bundle = currentAppBundle, let name = liveApps[bundle] else { return "Waiting for an enabled app." }
        if pausedApps.contains(bundle) { return "\(name) · paused for 10 minutes" }
        return "\(name) · \(connectionStatus(for: bundle).summary)"
    }
    var menuBarState: MenuBarState {
        MenuBarState(requested: liveRequested, running: liveEnabled, hasAccess: permissionGranted,
                     hasApps: !liveApps.isEmpty, appPaused: currentAppBundle.map { pausedApps.contains($0) } ?? false)
    }
    private func recordConnection(_ status: ConnectionStatus, for bundle: String) {
        guard liveApps[bundle] != nil else { return }
        connectionStatuses[bundle] = status
        if case .replacementFailed = status, verifiedApp == bundle { verifiedApp = nil }
        liveDidChange?()
    }
    @Published private(set) var currentAppBundle: String?
    @Published private(set) var pausedApps: Set<String> = []
    @Published private(set) var showOtherReadings = false
    @Published private(set) var quieterReadingCount = 0
    @Published private var undoLearning: UndoLearning
    var learnedWords: [String] { undoLearning.learnedWords }
    var hasUndoMemory: Bool { undoLearning.storedWordCount > 0 }
    var reviewLanguages: LanguageSelection { languages(for: sourceBundleIdentifier) }
    func languages(for bundle: String?) -> LanguageSelection {
        LanguageProfiles(defaults: languages, overrides: appLanguages).selection(for: bundle)
    }
    var contextStatus: String {
        let ready = languages.partners.filter { ContextGuard.availability(for: $0) == nil }
        if ready.isEmpty { return ContextGuard.availability(for: pair) ?? "On-device context unavailable" }
        let unavailable = languages.partners.filter { !ready.contains($0) }
        return "On-device context ready: " + ready.map(\.code).joined(separator: ", ")
            + (unavailable.isEmpty ? " · text stays on this Mac" : " · manual review for " + unavailable.map(\.code).joined(separator: ", "))
    }
    private var snapshot: SelectionSnapshot?
    private struct LocalCorrection { let before: String; let after: String; let feedback: UndoFeedback? }
    private var localUndo: LocalCorrection?
    private var localRedo: LocalCorrection?
    private var externalRedo: (snapshot: SelectionSnapshot, result: String, feedback: UndoFeedback?)?
    private var externalFeedback: UndoFeedback?
    private var keepUndo: (list: String, decisions: ReviewChoices)?
    private let defaults: UserDefaults
    private let spelling = MacSpelling()
    let bridge = SelectionBridge()
    let productSupport = ProductSupport()
    var supportReport: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return SupportReport(version: productSupport.version, system: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                             architecture: architecture, installed: productSupport.installed,
                             accessibility: bridge.trusted, liveEnabled: liveEnabled,
                             automatic: liveMode == .automatic, contextEnabled: contextEnabled,
                             languageCodes: languages.codes, appCount: liveApps.count,
                             customProfileCount: appLanguages.count, keptWordCount: manualKeepWords.count,
                             learnedWordCount: learnedWords.count).text
    }
    private lazy var live = LiveTypingController(bridge: bridge)
    private lazy var typingSession = TypingSession(defaults: defaults, start: { [weak self] in
        guard let self else { throw SelectionError.message("idkthen is no longer running.") }
        self.configureLive(); try self.live.start()
    }, stop: { [weak self] in self?.live.stop() })
    var revealWindow: (() -> Void)?
    var pairDidChange: (() -> Void)?
    var liveDidChange: (() -> Void)?
    var choices: [Int: String] { decisions.selected }
    var selectedCount: Int { choices.count }
    var pendingCount: Int { review?.changes.filter { $0.ambiguous && !decisions.isSelected($0) }.count ?? 0 }
    var output: String { review?.applying(choices) ?? input }
    var hasChanges: Bool { !TextIdentity.matches(output, input) }
    var isCurrent: Bool { review.map { TextIdentity.matches($0.original, input) } ?? false }
    var keepWords: Set<String> { manualKeepWords.union(learnedWords) }
    private var manualKeepWords: Set<String> {
        Set(keepList.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        liveRequested = defaults.bool(forKey: "liveEnabled")
        let existing = defaults.object(forKey: "enabledLanguages") != nil || defaults.object(forKey: "languagePair") != nil
        let startingStep = SetupStep(rawValue: defaults.string(forKey: "setupStep") ?? "") ?? (existing ? .done : .languages)
        setupStep = startingStep; defaults.set(startingStep.rawValue, forKey: "setupStep")
        undoShortcutChoice = UndoShortcutChoice(rawValue: defaults.string(forKey: "undoShortcut") ?? "controlShiftZ") ?? .controlShiftZ
        undoShortcutEnabled = defaults.object(forKey: "undoShortcutEnabled") as? Bool ?? true
        let selected = LanguagePair(rawValue: defaults.string(forKey: "languagePair") ?? "spanish") ?? .spanish
        let saved = defaults.stringArray(forKey: "enabledLanguages")?.compactMap(LanguagePair.init(rawValue:)) ?? []
        let selection = LanguageSelection(saved.isEmpty ? [selected] : saved)
        languages = selection; input = selection.sample()
        defaults.set(selection.partners.map(\.rawValue), forKey: "enabledLanguages")
        keepList = defaults.string(forKey: "keepWords") ?? "GitHub, SwiftUI, OpenAI"
        shortcutChoice = ShortcutChoice(rawValue: defaults.string(forKey: "selectionShortcut") ?? "controlOptionSpace") ?? .controlOptionSpace
        let savedApps = defaults.dictionary(forKey: "liveApps") as? [String: String] ?? ["com.apple.TextEdit": "TextEdit"]
        liveApps = savedApps
        let restoredProfiles = LanguageProfiles.restore(defaults.dictionary(forKey: "appLanguages") as? [String: [String]] ?? [:], allowed: Set(savedApps.keys))
        appLanguages = restoredProfiles
        defaults.set(restoredProfiles.mapValues { $0.partners.map(\.rawValue) }, forKey: "appLanguages")
        learningEnabled = defaults.object(forKey: "learnFromUndo") as? Bool ?? true
        if let data = defaults.data(forKey: "undoLearning"), data.count <= 65_536,
           let restored = try? JSONDecoder().decode(UndoLearning.self, from: data) { undoLearning = restored }
        else { undoLearning = UndoLearning() }
        liveMode = LiveCorrectionMode(rawValue: defaults.string(forKey: "liveMode") ?? "suggest") ?? .suggest
        contextEnabled = defaults.object(forKey: "contextEnabled") as? Bool ?? true
        permissionGranted = bridge.trusted
        bridge.onShortcut = { [weak self] in self?.captureSelection() }
        analyze(rankingContext: false); refreshSourceApps()
        live.onStatus = { [weak self] in self?.liveStatus = $0 }
        live.onWordUndone = { [weak self] in self?.recordUndoFeedback($0) ?? false }
        live.onPauseChanged = { [weak self] in self?.refreshPauses() }
        live.onFrontmostApp = { [weak self] in self?.currentAppBundle = $0; self?.refreshPauses() }
        live.onCorrectionApplied = { [weak self] bundle in
            self?.verifiedApp = bundle; self?.recordConnection(.corrected, for: bundle)
        }
        live.onConnectionStatus = { [weak self] bundle, status in self?.recordConnection(status, for: bundle) }
        live.configureUndoShortcut(undoShortcutChoice, enabled: undoShortcutEnabled)
        live.onHistoryChanged = { [weak self] message in
            guard let self else { return }
            self.snapshot = nil; self.sourceApp = nil; self.localUndo = nil
            self.sourceBundleIdentifier = nil; self.externalFeedback = nil
            self.localRedo = nil; self.externalRedo = nil
            self.liveStatus = message
            self.message = ""; self.isError = false; self.updateHistoryState()
        }
    }
    func select(_ newPair: LanguagePair) { setLanguages(LanguageSelection([newPair])) }
    func toggleLanguage(_ language: LanguagePair) {
        guard !applying else { return }
        guard let next = languages.toggling(language) else {
            message = languages.contains(language) ? "Keep at least one language alongside English." : "Four languages are enabled. Remove one before adding another."
            isError = false; return
        }
        setLanguages(next)
    }
    func setLanguages(_ selection: LanguageSelection) {
        guard !applying, selection != languages else { return }
        let isExample = TextIdentity.matches(input, languages.sample()) || TextIdentity.matches(input, languages.sample(ambiguous: true))
        languages = selection; direction = .detect
        clearRedo()
        defaults.set(selection.partners.map(\.rawValue), forKey: "enabledLanguages")
        defaults.set(pair.rawValue, forKey: "languagePair")
        if isExample && snapshot == nil { input = selection.sample(); clearHistory() }
        decisions = ReviewChoices(); analyze(); pairDidChange?(); configureLive()
    }
    func changeDirection() { decisions = ReviewChoices(); clearRedo(); analyze() }
    func analyze(preservingChoices: Bool = true, rankingContext: Bool = true) {
        guard !applying else { return }
        spelling.clearCache()
        let base = ReviewEngine(spelling: spelling).review(input, languages: reviewLanguages, direction: direction, keepWords: keepWords)
        let ranked = rankingContext && contextEnabled && ContextGuard.resourcesAllowed
            ? LocalLanguageContext.rank(base, languages: reviewLanguages, spelling: spelling) : base
        let focused = ReviewVisibility.focused(ranked, spelling: spelling,
                                              preserving: preservingChoices && isCurrent ? Set(choices.keys) : [])
        quieterReadingCount = ranked.changes.count - focused.changes.count
        let result = showOtherReadings ? ranked : focused
        decisions.update(result, preserving: preservingChoices)
        review = result; message = result.notice ?? ""
        let anyAvailable = reviewLanguages.partners.contains { spelling.isAvailable($0.spellLanguage) && ($0.usesAccents || spelling.supportsAutomaticLayoutDetection($0.spellLanguage)) }
        isError = result.notice != nil && (reviewLanguages.singlePair != nil || !anyAvailable || input.utf16.count > ReviewEngine.maxSelectionLength || direction != .detect)
    }
    func textChanged() {
        showOtherReadings = false; quieterReadingCount = 0
        review = nil; decisions = ReviewChoices(); message = ""; isError = false
        clearHistory(); keepUndo = nil; lastKeptWord = nil
    }
    func setShowOtherReadings(_ show: Bool) { showOtherReadings = show; analyze() }
    func startSetup() { verifiedApp = nil; setSetupStep(.languages) }
    func setSetupStep(_ step: SetupStep) { setupStep = step; defaults.set(step.rawValue, forKey: "setupStep") }
    func setUndoShortcut(_ choice: UndoShortcutChoice) {
        undoShortcutChoice = choice; defaults.set(choice.rawValue, forKey: "undoShortcut")
        live.configureUndoShortcut(choice, enabled: undoShortcutEnabled)
    }
    func setUndoShortcutEnabled(_ enabled: Bool) {
        undoShortcutEnabled = enabled; defaults.set(enabled, forKey: "undoShortcutEnabled")
        live.configureUndoShortcut(undoShortcutChoice, enabled: enabled)
    }
    func pauseApp(_ bundle: String) { live.pause(bundle) }
    func resumeApp(_ bundle: String) { live.resume(bundle) }
    private func refreshPauses() { pausedApps = Set(liveApps.keys.filter { live.isPaused($0) }); liveDidChange?() }
    func rememberCurrentApp() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            currentAppBundle = SelectionBridge.canReadApplication(front) ? front.bundleIdentifier : nil
        }
        refreshPauses()
    }
    func setSelected(_ selected: Bool, for change: Change) { decisions.setSelected(selected, for: change); clearRedo() }
    func choose(_ change: Change, _ candidate: String) { decisions.choose(candidate, for: change); clearRedo() }
    func selectSuggested() { if let review { decisions.selectSuggested(in: review) }; clearRedo() }
    func deselectAll() { decisions.deselectAll(); clearRedo() }
    func keep(_ change: Change) {
        clearRedo()
        keepUndo = (keepList, decisions)
        var words = manualKeepWords; words.insert(change.original)
        keepList = words.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: ", ")
        defaults.set(keepList, forKey: "keepWords"); analyze()
        configureLive()
        lastKeptWord = change.original
        lastRestoredWord = nil
        message = "Keeping “\(change.original)” in every enabled language."
    }
    func keepRestoredSpelling() {
        guard let original = lastRestoredWord, UndoLearning.validWord(original) != nil else { return }
        keep(Change(range: NSRange(location: 0, length: original.utf16.count), original: original,
                    candidates: [], reason: "Explicitly kept after Undo", ambiguous: false))
    }
    func undoKeep() {
        guard let previous = keepUndo else { return }
        clearRedo()
        keepList = previous.list; decisions = previous.decisions
        defaults.set(keepList, forKey: "keepWords")
        configureLive()
        keepUndo = nil; lastKeptWord = nil; analyze()
        message = "Removed the last word added to your keep list."
    }
    func saveKeepWords() {
        clearRedo()
        defaults.set(keepList, forKey: "keepWords"); keepUndo = nil; lastKeptWord = nil
        configureLive()
    }
    func setLearningEnabled(_ enabled: Bool) {
        learningEnabled = enabled; defaults.set(enabled, forKey: "learnFromUndo")
    }
    @discardableResult func recordUndoFeedback(_ feedback: UndoFeedback) -> Bool {
        lastRestoredWord = nil
        if let word = UndoLearning.validWord(feedback.original), !keepWords.contains(where: { UndoLearning.validWord($0) == word }) {
            lastRestoredWord = feedback.original
        }
        guard learningEnabled, !manualKeepWords.contains(where: { UndoLearning.validWord($0) == UndoLearning.validWord(feedback.original) }) else { return false }
        let learned = undoLearning.record(feedback)
        persistLearning()
        if learned { lastRestoredWord = nil; configureLive() }
        return learned
    }
    func forgetLearnedWord(_ word: String) {
        undoLearning.forget(word); live.forgetWord(word); persistLearning()
        clearRedo(); configureLive(); analyze()
    }
    func forgetAllLearnedWords() {
        for word in learnedWords { live.forgetWord(word) }
        undoLearning.forgetAll(); persistLearning()
        clearRedo(); configureLive(); analyze()
    }
    private func persistLearning() { if let data = try? JSONEncoder().encode(undoLearning) { defaults.set(data, forKey: "undoLearning") } }
    func setAppLanguages(_ selection: LanguageSelection?, for bundle: String) {
        guard !applying, liveApps[bundle] != nil else { return }
        appLanguages[bundle] = selection
        defaults.set(appLanguages.mapValues { $0.partners.map(\.rawValue) }, forKey: "appLanguages")
        if sourceBundleIdentifier == bundle { direction = .detect; clearRedo(); decisions = ReviewChoices(); analyze() }
        configureLive(); liveDidChange?()
    }
    func toggleAppLanguage(_ language: LanguagePair, for bundle: String) {
        guard let current = appLanguages[bundle], let next = current.toggling(language) else { return }
        setAppLanguages(next, for: bundle)
    }
    func loadExample(ambiguous: Bool = false) {
        guard !applying else { return }
        snapshot = nil; sourceApp = nil; sourceBundleIdentifier = nil; clearHistory()
        input = languages.sample(ambiguous: ambiguous)
        decisions = ReviewChoices(); analyze()
    }
    func editCopy() {
        guard !applying else { return }
        snapshot = nil; sourceApp = nil; sourceBundleIdentifier = nil; clearHistory()
        message = "Editing a copy. The original app stays unchanged."; isError = false
    }
    func reviewLocalText(_ text: String, for bundle: String? = nil) {
        editCopy(); input = text; textChanged()
        sourceBundleIdentifier = bundle.flatMap { liveApps[$0] == nil ? nil : $0 }
        direction = .detect; analyze()
    }
    func clear() {
        guard !applying else { return }
        live.clearSession()
        input = ""; review = nil; decisions = ReviewChoices(); snapshot = nil; sourceApp = nil; sourceBundleIdentifier = nil
        clearHistory(); spelling.clearCache(); keepUndo = nil; lastKeptWord = nil; lastRestoredWord = nil
        message = "Text cleared from this session."; isError = false
    }
    func apply() {
        guard isCurrent, hasChanges, !applying else { return }
        let result = output
        let feedback = feedbackForCurrentCorrection()
        clearRedo()
        if let snapshot { applyExternal(result, to: snapshot, feedback: feedback) }
        else {
            bridge.clearUndo(); localUndo = LocalCorrection(before: input, after: result, feedback: feedback)
            input = result; review = nil; decisions = ReviewChoices(); updateHistoryState()
            message = "Applied. Undo with ⌘Z."; isError = false
        }
    }
    private func feedbackForCurrentCorrection() -> UndoFeedback? {
        guard selectedCount == 1, let change = review?.changes.first(where: { decisions.isSelected($0) }),
              UndoLearning.validWord(change.original) != nil else { return nil }
        return UndoFeedback(original: change.original)
    }
    private func applyExternal(_ result: String, to snapshot: SelectionSnapshot, feedback: UndoFeedback?) {
        externalFeedback = nil
        applying = true
        Task {
            do {
                try await bridge.apply(result, snapshot: snapshot)
                self.snapshot = nil; sourceApp = nil; sourceBundleIdentifier = nil; localUndo = nil
                externalFeedback = feedback
                input = result; review = nil; decisions = ReviewChoices()
                message = "Applied to \(snapshot.appName). Undo with ⌘Z while that field stays unchanged."; isError = false
            } catch {
                if let bundle = NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier {
                    recordConnection(.replacementFailed, for: bundle)
                }
                message = error.localizedDescription; isError = true
            }
            applying = false; updateHistoryState()
        }
    }
    func undo() {
        guard !applying else { return }
        if bridge.hasLiveUndo { live.undoRecent(); return }
        if let undo = localUndo, TextIdentity.matches(input, undo.after) {
            input = undo.before; localRedo = undo; localUndo = nil
            let learned = undo.feedback.map { recordUndoFeedback($0) } ?? false
            analyze(); message = learned ? "Restored. “\(undo.feedback!.original)” will now be kept across apps." : "Restored your original text."; isError = false; updateHistoryState()
        } else if let captured = bridge.undoSnapshot, let transaction = bridge.undoTransaction {
            let feedback = externalFeedback
            applying = true
            Task {
                do {
                    try await bridge.undo()
                    live.rememberUndo(captured.selectedText, transaction: transaction)
                    if let feedback { recordUndoFeedback(feedback) }
                    self.snapshot = captured; sourceApp = captured.appName
                    sourceBundleIdentifier = NSRunningApplication(processIdentifier: captured.pid)?.bundleIdentifier
                    input = captured.selectedText; externalRedo = (captured, transaction.replacement, feedback)
                    applying = false; analyze()
                    message = "Restored the original selection in \(captured.appName)."; isError = false
                } catch { message = error.localizedDescription; isError = true }
                applying = false; updateHistoryState()
            }
        }
    }
    func undoReview() {
        guard canUndoReview else { return }
        undo()
    }
    func redo() {
        guard !applying else { return }
        if let redo = localRedo, TextIdentity.matches(input, redo.before) {
            input = redo.after; localUndo = redo; localRedo = nil
            review = nil; decisions = ReviewChoices(); message = "Reapplied the correction."; isError = false; updateHistoryState()
        } else if let redo = externalRedo {
            externalRedo = nil; applyExternal(redo.result, to: redo.snapshot, feedback: redo.feedback)
        }
    }
    private func clearRedo() { localRedo = nil; externalRedo = nil; updateHistoryState() }
    private func clearHistory() {
        localUndo = nil; localRedo = nil; externalRedo = nil; externalFeedback = nil; bridge.clearUndo(); updateHistoryState()
    }
    private func updateHistoryState() { canUndo = localUndo != nil || bridge.undoTransaction != nil; canRedo = localRedo != nil || externalRedo != nil }
    func copyResult() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string)
        message = "Copied to your clipboard."; isError = false
    }
    func setShortcut(_ choice: ShortcutChoice) {
        guard choice != shortcutChoice else { return }
        do {
            if bridge.enabled { try bridge.updateShortcut(choice) }
            shortcutChoice = choice; defaults.set(choice.rawValue, forKey: "selectionShortcut")
            message = "Selection shortcut: \(choice.label)."; isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
    func enableShortcut() {
        if bridge.enabled {
            bridge.disable(); shortcutEnabled = false; updateHistoryState()
            message = "Selection shortcut is off. Import selection is still available."; isError = false; return
        }
        permissionGranted = bridge.trusted
        if !permissionGranted { bridge.requestPermission() }
        do { try bridge.enable(shortcutChoice); shortcutEnabled = true; message = "Select text in another app, then press \(shortcutChoice.label)."; isError = false }
        catch { message = error.localizedDescription; isError = true }
    }
    func refreshPermission() {
        refreshTypingAvailability(); refreshSourceApps(); refreshPauses(); productSupport.refresh()
    }
    /// Called on activation/unlock/wake, without timers or background text reads.
    func refreshTypingAvailability() {
        permissionGranted = bridge.trusted
        typingSession.reconcile(hasAccess: permissionGranted, hasApps: !liveApps.isEmpty)
        liveRequested = typingSession.requested; liveEnabled = typingSession.running
        if let failure = typingSession.failure { message = failure; isError = true }
        liveDidChange?()
    }
    private func configureLive() { live.configure(languages: languages, appLanguages: appLanguages, keepWords: keepWords, allowed: Set(liveApps.keys), mode: liveMode, useContext: contextEnabled) }
    func setLiveMode(_ mode: LiveCorrectionMode) {
        liveMode = mode; defaults.set(mode.rawValue, forKey: "liveMode"); configureLive(); liveDidChange?()
    }
    func setContextEnabled(_ enabled: Bool) {
        contextEnabled = enabled; defaults.set(enabled, forKey: "contextEnabled"); configureLive(); analyze()
    }
    func restoreLivePreference() {
        refreshTypingAvailability()
    }
    func setLiveEnabled(_ enabled: Bool) {
        typingSession.setRequested(enabled)
        message = ""; isError = false
        refreshTypingAvailability()
        if enabled && !permissionGranted { bridge.requestPermission() }
        if enabled && liveEnabled {
            message = "\(liveMode == .automatic ? "Automatic correction is" : "Live suggestions are") on for your enabled apps. Type a word, then Space."; isError = false
        }
    }
    func addLiveApp(_ app: NSRunningApplication) {
        guard SelectionBridge.canReadApplication(app), let bundle = app.bundleIdentifier else { return }
        liveApps[bundle] = app.localizedName ?? bundle
        defaults.set(liveApps, forKey: "liveApps"); configureLive(); refreshTypingAvailability()
    }
    func removeLiveApp(_ bundle: String) {
        setAppLanguages(nil, for: bundle)
        connectionStatuses.removeValue(forKey: bundle)
        if verifiedApp == bundle { verifiedApp = nil }
        liveApps.removeValue(forKey: bundle); defaults.set(liveApps, forKey: "liveApps")
        if liveApps.isEmpty { setLiveEnabled(false) } else { configureLive() }
    }
    func openLiveApp(_ bundle: String) {
        guard liveApps[bundle] != nil else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            NSApp.yieldActivation(to: app)
            app.activate(from: .current, options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    func refreshSourceApps() {
        availableSourceApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && SelectionBridge.canReadApplication($0) }.sorted {
            ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
        }
    }
    func captureSelection(from app: NSRunningApplication? = nil) {
        guard !applying else { return }
        do {
            let captured = try bridge.capture(from: app)
            clearHistory(); snapshot = captured; sourceApp = captured.appName
            sourceBundleIdentifier = NSRunningApplication(processIdentifier: captured.pid)?.bundleIdentifier
            direction = .detect
            input = captured.selectedText; decisions = ReviewChoices(); analyze()
        } catch { message = error.localizedDescription; isError = true }
        revealWindow?()
    }
}
