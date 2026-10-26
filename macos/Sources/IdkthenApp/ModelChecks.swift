import AppKit
import IdkthenCore

/// Synthetic state checks use an isolated defaults suite, never the writer's settings.
@MainActor enum ModelChecks {
    static func run() -> Bool {
        let suite = "dev.pairtype.checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        var passed = true
        func check(_ condition: Bool, _ name: String) { print("MODEL \(name): \(condition ? "PASS" : "FAIL")"); passed = passed && condition }
        model.input = "manana reunion despues"; model.textChanged(); model.analyze()
        let original = model.input
        let corrected = model.output
        model.apply()
        check(model.input == corrected && model.canUndo && model.canUndoReview && !model.canRedo, "apply creates one review undo")
        model.undoReview()
        check(model.input == original && model.canRedo && !model.canUndo, "undo restores original")
        model.redo()
        check(model.input == corrected && model.canUndo && !model.canRedo, "redo restores correction")
        model.input += " new work"; model.textChanged()
        check(!model.canUndo && !model.canRedo, "typing invalidates correction history")
        model.clear(); model.canUndo = true
        check(!model.canUndoReview, "global Undo availability alone cannot label an empty review Applied")
        model.undoReview()
        check(model.input.isEmpty, "review Undo with no review receipt cannot change text")
        model.canUndo = false
        model.loadExample(); model.deselectAll(); model.analyze()
        check(model.selectedCount == 0, "review again preserves deselections")
        if let change = model.review?.changes.first {
            let keepList = model.keepList
            model.keep(change)
            check(model.review?.changes.contains(where: { $0.original == change.original }) == false, "keep removes suggestion")
            model.undoKeep()
            check(model.keepList == keepList && model.review?.changes.contains(where: { $0.original == change.original }) == true && model.selectedCount == 0, "undo keep restores choices")
        } else { check(false, "keep fixture exists") }
        model.loadExample(); model.apply(); model.undo()
        if let change = model.review?.changes.first {
            model.keep(change)
            check(!model.canRedo, "keeping a word invalidates earlier redo")
            model.undoKeep()
        }
        model.select(.korean); model.setShortcut(.commandShiftJ)
        let reloaded = AppModel(defaults: defaults)
        check(reloaded.pair == .korean && reloaded.shortcutChoice == .commandShiftJ && !reloaded.shortcutEnabled, "preferences persist without activating hotkey")
        model.setLiveMode(.automatic); model.setContextEnabled(true)
        let liveReloaded = AppModel(defaults: defaults)
        check(liveReloaded.liveMode == .automatic && liveReloaded.contextEnabled && !liveReloaded.liveEnabled,
              "automatic context preference persists without starting monitoring in initialization")
        model.input = "dkssud"; model.textChanged(); model.analyze(); model.apply(); model.loadExample()
        check(!model.canUndo && !model.canRedo, "new example clears unrelated undo")
        model.select(.spanish); model.input = "café manana"; model.textChanged(); model.analyze()
        let encodedOriginal = model.input
        model.input = model.input.decomposedStringWithCanonicalMapping
        check(!model.isCurrent, "equivalent-looking newer encoding invalidates review")
        model.apply()
        check(TextIdentity.matches(model.input, encodedOriginal.decomposedStringWithCanonicalMapping), "stale review cannot apply after encoding changes")
        model.input = encodedOriginal; model.textChanged(); model.analyze(); model.apply()
        let normalizedNewerText = model.input.decomposedStringWithCanonicalMapping
        model.input = normalizedNewerText; model.undo()
        check(TextIdentity.matches(model.input, normalizedNewerText), "undo cannot overwrite equivalent-looking newer text")
        model.select(.german); model.input = "fuer ueber"; model.textChanged(); model.analyze()
        check(model.review?.changes.count == 2 && model.selectedCount == 0, "German ASCII transcriptions require explicit choice")
        let four = LanguageSelection([.spanish, .french, .korean])
        model.setLanguages(four)
        model.input = "manana l'ecole chromedptj"; model.textChanged(); model.analyze()
        check(model.output == "mañana l'école chrome에서", "one review handles all four enabled languages")
        model.apply(); model.undo()
        check(model.input == "manana l'ecole chromedptj" && model.canRedo, "four-language apply and undo preserve the original")
        let custom = model.input
        model.toggleLanguage(.german)
        check(model.languages == four && model.input == custom, "fifth language cannot replace an enabled language or user text")
        model.toggleLanguage(.spanish)
        check(model.languages.count == 3 && model.input == custom && !model.canRedo, "removing a language preserves custom text and clears stale redo")
        model.toggleLanguage(.portuguese)
        let groupReloaded = AppModel(defaults: defaults)
        check(groupReloaded.languages == model.languages && !groupReloaded.liveEnabled, "language set persists without starting live access")
        model.select(.korean); model.toggleLanguage(.korean)
        check(model.languages == LanguageSelection([.korean]), "last partner language cannot be removed")
        model.select(.spanish); model.input = "reunion"; model.textChanged(); model.analyze()
        if let change = model.review?.changes.first { model.setSelected(true, for: change) }
        model.toggleLanguage(.french)
        check(model.selectedCount == 0 && model.review?.changes.first?.requiresExplicitChoice == true, "adding a competing language discards an earlier approval")
        defaults.removeObject(forKey: "enabledLanguages"); defaults.set("korean", forKey: "languagePair")
        let migrated = AppModel(defaults: defaults)
        check(migrated.languages == LanguageSelection([.korean]), "legacy pair migrates without changing languages")
        defaults.set(["spanish", "unknown", "french", "korean", "german", "spanish"], forKey: "enabledLanguages")
        let repaired = AppModel(defaults: defaults)
        check(repaired.languages == four && defaults.stringArray(forKey: "enabledLanguages")?.count == 3, "invalid duplicate and over-limit saved languages are normalized")
        print("MODEL_CHECKS \(passed ? "PASS" : "FAIL")")
        return passed
    }
}
