import AppKit
import IdkthenCore

@MainActor enum UsabilityChecks {
    static func run() -> Bool {
        var total = 0, failed = 0
        func check(_ value: Bool, _ label: String) {
            total += 1; if !value { failed += 1 }
            print("USABILITY \(label): \(value ? "PASS" : "FAIL")")
        }
        let suite = "dev.pairtype.usability." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        check(model.setupStep == .languages && !model.liveEnabled, "first launch starts with languages and no monitoring")
        check(AppModel(defaults: defaults).setupStep == .languages, "unfinished first run survives relaunch")
        model.setSetupStep(.practice)
        check(AppModel(defaults: defaults).setupStep == .practice, "trial step resumes without claiming completion")
        model.setSetupStep(.verify)
        check(model.verifiedApp == nil && AppModel(defaults: defaults).verifiedApp == nil, "local trial and relaunch cannot verify an external app")
        model.setSetupStep(.done)
        check(AppModel(defaults: defaults).setupStep == .done, "Later and finished setup keep the home compact")
        model.startSetup()
        check(model.setupStep == .languages && model.verifiedApp == nil, "setup can be revisited without fabricated success")
        defaults.removeObject(forKey: "setupStep")
        check(AppModel(defaults: defaults).setupStep == .done, "existing installs keep their home")
        model.setUndoShortcut(.commandOptionZ); model.setUndoShortcutEnabled(false)
        let restored = AppModel(defaults: defaults)
        check(restored.undoShortcutChoice == .commandOptionZ && !restored.undoShortcutEnabled && !restored.bridge.undoShortcutEnabled,
              "undo shortcut preferences persist without a global registration")
        model.setLanguages(LanguageSelection([.spanish, .french, .korean]))
        let passage = "Nous préparons la prochaine reunion avec toute notre équipe demain matin."
        model.reviewLocalText(passage)
        print("FOCUSED_REVIEW \(model.review?.changes.map(\.original) ?? []) hidden=\(model.quieterReadingCount)")
        check(model.review?.changes.map(\.original) == ["reunion"] && model.quieterReadingCount >= 4,
              "French sentence reduces five choices to reunion")
        check(model.review?.changes.first?.candidates.first == "réunion" && !model.hasChanges,
              "French ranking remains advisory and unselected")
        model.setShowOtherReadings(true)
        check(model.review?.changes.contains(where: { $0.original == "notre" }) == true, "other valid readings remain explicitly accessible")
        if let notre = model.review?.changes.first(where: { $0.original == "notre" }) {
            model.choose(notre, "nôtre"); model.setShowOtherReadings(false)
            check(model.review?.changes.contains(where: { $0.original == "notre" }) == true && model.choices[notre.id] == "nôtre",
                  "hiding alternatives preserves an explicit choice")
        } else { check(false, "explicit-choice fixture") }
        model.reviewLocalText("notre")
        check(model.review?.changes.contains(where: { $0.candidates.contains("nôtre") }) == true, "single-word review still offers other readings")
        for (pair, text, quiet) in [(LanguagePair.spanish, "si tu papa viene", "si"), (.german, "Das ist schon", "schon"),
                                  (.portuguese, "Ele pode vir", "pode"), (.italian, "si e la", "si")] {
            model.select(pair); model.reviewLocalText(text)
            check(model.review?.changes.contains(where: { $0.original == quiet }) == false, "quiet valid \(pair.code) reading in a passage")
        }
        model.setLanguages(LanguageSelection([.spanish, .french, .korean]))
        model.reviewLocalText("manana l'ecole chromedptj")
        check(model.output == "mañana l'école chrome에서", "needed mixed-language corrections survive filtering")
        model.setLiveMode(.automatic)
        let originalProfile = model.languages(for: "com.apple.TextEdit")
        model.pauseApp("com.apple.TextEdit")
        check(model.pausedApps.contains("com.apple.TextEdit") && !model.liveEnabled, "pause does not start monitoring")
        model.resumeApp("com.apple.TextEdit")
        check(model.pausedApps.isEmpty && model.languages(for: "com.apple.TextEdit") == originalProfile, "resume keeps app languages")
        check(defaults.object(forKey: "pausedApps") == nil, "temporary pause is not persisted")

        func trial() -> TypingTrial {
            let value = TypingTrial(); value.configure(languages: LanguageSelection([.korean]), mode: .automatic, keepWords: [])
            return value
        }
        @discardableResult func enter(_ text: String, _ value: TypingTrial, caret: Int? = nil) -> TypingTrial.Edit? {
            value.userEdited(text, selection: NSRange(location: caret ?? text.utf16.count, length: 0))
        }
        let continuing = trial()
        enter("chromedptj ", continuing); enter("chrome에서 next words 👩‍💻", continuing)
        check(continuing.canUndo, "recent correction stays recoverable after more typing")
        let undo = continuing.undo()
        check(undo?.after == "chromedptj next words 👩‍💻" && undo?.afterSelection.location == "chromedptj next words 👩‍💻".utf16.count,
              "Undo preserves new words emoji and caret")
        check(continuing.didCorrect && continuing.didUndo, "first-run trial verifies correction and undo separately")
        let retyped = trial()
        enter("chromedptj ", retyped); enter("chrome ", retyped); enter("chromedptj ", retyped)
        check(retyped.text == "chromedptj " && !retyped.canUndo, "manual original retyping prevents a correction loop")
        enter("chromedptj chromedptj ", retyped)
        check(retyped.text == "chromedptj chromedptj ", "manual retyping is a session-only keep")
        let changed = trial()
        enter("prefix chromedptj ", changed); enter("changed chrome에서 next", changed)
        check(changed.undo() == nil && changed.text == "changed chrome에서 next", "unrelated edits cannot be overwritten by Undo")
        let middle = trial()
        enter("chromedptj | suffix", middle, caret: 11)
        enter("chrome에서 next | suffix", middle, caret: 14)
        let restoredMiddle = middle.undo()
        check(restoredMiddle?.after == "chromedptj next | suffix" && restoredMiddle?.afterSelection.location == 16,
              "Undo in middle preserves the existing suffix and caret")
        check(!model.learnedWords.contains("chromedptj"), "local recovery never teaches persistent words")
        let pasted = trial()
        pasted.userEdited("dkssud ", selection: NSRange(location: 7, length: 0), isPaste: true)
        check(pasted.text == "dkssud " && !pasted.canUndo && pasted.pending == nil, "pasted text stays as written in the native trial")
        let prefix = String(repeating: "a ", count: 40_000)
        let correction = TextTransaction(before: prefix + "dkssud ", range: NSRange(location: prefix.utf16.count, length: 6), replacement: "안녕")
        let recovery = CorrectionRecovery(transaction: correction, caretAfter: prefix.utf16.count + 3)
        let continued = prefix + "안녕 next"
        var timing: [Double] = []
        var recovered = true
        for _ in 0..<100 {
            let start = ContinuousClock.now
            recovered = recovered && recovery.canRecover(current: continued, selection: NSRange(location: continued.utf16.count, length: 0))
            let duration = start.duration(to: .now).components
            timing.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        }
        timing.sort()
        check(recovered, "large-document recovery availability remains valid")
        print(String(format: "RECOVERY_AVAILABILITY_100 units=%d median=%.3fms p95=%.3fms max=%.3fms; cached anchor, excludes AX/UI", continued.utf16.count, timing[50], timing[95], timing[99]))
        print("USABILITY_CHECKS \(failed == 0 ? "PASS" : "FAIL") \(total - failed)/\(total)")
        return failed == 0
    }
}
