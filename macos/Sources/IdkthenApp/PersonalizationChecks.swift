import AppKit
import IdkthenCore

/// Persistence and real spelling-service checks use disposable preferences only.
@MainActor enum PersonalizationChecks {
    static func run() -> Bool {
        let suite = "dev.pairtype.personalization-checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["com.apple.TextEdit": "TextEdit", "dev.fixture.Mail": "Fixture Mail"], forKey: "liveApps")
        var count = 0, failures = 0
        func check(_ condition: Bool, _ label: String) {
            count += 1; if !condition { failures += 1 }
            print("PERSONALIZATION \(condition ? "PASS" : "FAIL") \(label)")
        }
        func input(_ text: String, _ model: AppModel) { model.editCopy(); model.input = text; model.textChanged(); model.analyze() }
        let model = AppModel(defaults: defaults)
        model.select(.korean)
        let personal = LanguageSelection([.italian, .russian])
        model.setAppLanguages(personal, for: "com.apple.TextEdit")
        check(model.languages(for: "com.apple.TextEdit") == personal && model.languages(for: "dev.fixture.Mail") == LanguageSelection([.korean]), "app override and default are independent")
        model.setLanguages(LanguageSelection([.spanish, .french]))
        check(model.languages(for: "com.apple.TextEdit") == personal && model.languages(for: "dev.fixture.Mail") == model.languages, "default changes reach only inheriting apps")
        model.setAppLanguages(LanguageSelection([.russian]), for: "not.enabled")
        check(model.appLanguages["not.enabled"] == nil, "unapproved app cannot acquire a profile")
        let restored = AppModel(defaults: defaults)
        check(restored.appLanguages == model.appLanguages && restored.languages == model.languages && !restored.liveEnabled, "profiles persist without starting monitoring")
        let controller = LiveTypingController(bridge: SelectionBridge())
        controller.configure(languages: model.languages, appLanguages: model.appLanguages, keepWords: [], allowed: Set(model.liveApps.keys), mode: .automatic, useContext: false)
        check(controller.resolvedLanguages(for: "com.apple.TextEdit") == personal && controller.resolvedLanguages(for: "dev.fixture.Mail") == model.languages, "live controller resolves actual configured profiles")
        restored.reviewLocalText("lunedi ghbdtn", for: "com.apple.TextEdit")
        check(restored.reviewLanguages == personal && restored.output == "lunedì привет", "app-specific trial handoff uses its languages in review")
        restored.setAppLanguages(LanguageSelection([.french]), for: "com.apple.TextEdit")
        check(restored.selectedCount == 0 && restored.reviewLanguages == LanguageSelection([.french]), "changing source profile discards old approvals")
        restored.setAppLanguages(nil, for: "com.apple.TextEdit")
        check(restored.languages(for: "com.apple.TextEdit") == restored.languages, "Use Default removes the override")
        restored.setAppLanguages(personal, for: "com.apple.TextEdit"); restored.removeLiveApp("com.apple.TextEdit")
        check(restored.appLanguages["com.apple.TextEdit"] == nil && AppModel(defaults: defaults).appLanguages["com.apple.TextEdit"] == nil, "removing an app also removes its saved override")

        model.select(.korean); input("chromedptj", model); model.apply(); model.undo()
        for _ in 0..<6 { model.redo(); model.undo() }
        check(model.learnedWords.isEmpty && model.input == "chromedptj", "repeated Undo/Redo of one correction counts once")
        model.apply(); model.undo()
        check(model.learnedWords.isEmpty, "second independent correction is not learned yet")
        let afterRestart = AppModel(defaults: defaults)
        afterRestart.select(.korean); input("chromedptj", afterRestart); afterRestart.apply(); afterRestart.undo()
        check(afterRestart.learnedWords == ["chromedptj"] && afterRestart.keepWords.contains("chromedptj"), "third separate undo after restart learns the word")
        check(afterRestart.review?.changes.isEmpty == true, "learned word is excluded from immediate re-review")
        let learnedReload = AppModel(defaults: defaults)
        check(learnedReload.learnedWords == ["chromedptj"] && learnedReload.keepList == "GitHub, SwiftUI, OpenAI", "learned words persist separately from explicit keeps")
        let text = "chromedptj "
        let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
        let engine = ReviewEngine(spelling: MacSpelling())
        if case .skip = FastTypingPlan.make(word: word, document: text, engine: engine, languages: LanguageSelection([.korean]), keepWords: learnedReload.keepWords) { check(true, "learned word reaches the live planner") }
        else { check(false, "learned word reaches the live planner") }
        learnedReload.setLearningEnabled(false)
        for _ in 0..<4 { learnedReload.recordUndoFeedback(UndoFeedback(original: "dkssud")) }
        check(learnedReload.learnedWords == ["chromedptj"] && !AppModel(defaults: defaults).learningEnabled, "learning off persists and retains previous words")
        learnedReload.forgetLearnedWord("chromedptj")
        input("chromedptj", learnedReload)
        check(learnedReload.learnedWords.isEmpty && learnedReload.output == "chrome에서", "Forget restores eligibility without deleting explicit keeps")
        learnedReload.setLearningEnabled(true)
        learnedReload.select(.korean)
        for _ in 0..<3 { input("dkssud chromedptj", learnedReload); learnedReload.apply(); learnedReload.undo() }
        check(learnedReload.learnedWords.isEmpty, "batch Undo does not guess which word was rejected")
        for _ in 0..<2 { learnedReload.recordUndoFeedback(UndoFeedback(original: "dkssud")) }
        learnedReload.forgetAllLearnedWords()
        check(!AppModel(defaults: defaults).hasUndoMemory, "Reset removes partial evidence as well as learned words")
        let trial = TypingTrial()
        trial.configure(languages: LanguageSelection([.korean]), mode: .automatic, keepWords: learnedReload.keepWords)
        for _ in 0..<4 { trial.clear(); trial.userEdited("dkssud ", selection: NSRange(location: 7, length: 0)); _ = trial.undo() }
        check(!AppModel(defaults: defaults).hasUndoMemory, "practice Undo never trains the personal dictionary")

        learnedReload.setLearningEnabled(false)
        learnedReload.recordUndoFeedback(UndoFeedback(original: "myOwnSpelling"))
        check(learnedReload.lastRestoredWord == "myOwnSpelling", "Undo offers an explicit keep even when automatic learning is off")
        learnedReload.keepRestoredSpelling()
        check(learnedReload.lastRestoredWord == nil && learnedReload.keepWords.contains("myOwnSpelling"), "one explicit keep closes the offer")
        check(AppModel(defaults: defaults).keepWords.contains("myOwnSpelling"), "explicit keep survives restart")
        learnedReload.recordUndoFeedback(UndoFeedback(original: "two words"))
        check(learnedReload.lastRestoredWord == nil, "batch feedback cannot create a stale keep offer")

        for (pair, raw, expected) in [(LanguagePair.italian, "lunedi", "lunedì"), (.italian, "perche", "perché"), (.russian, "ghbdtn", "привет"), (.russian, "cgfcb,j", "спасибо"), (.russian, "руддщ", "hello")] {
            let value = raw + " ", selection = LanguageSelection([pair])
            let current = LiveWord.completed(in: value, selection: NSRange(location: value.utf16.count, length: 0))!
            let review = engine.review(raw, pair: pair)
            check(review.changes.contains { $0.candidates.contains(expected) }, "new dictionary candidate \(pair.code) \(raw)")
            if case let .immediate(change) = FastTypingPlan.make(word: current, document: value, engine: engine, languages: selection, keepWords: []) {
                check(TextTransaction(before: value, range: change.range, replacement: change.candidates[0]).after == expected + " ", "new automatic candidate \(pair.code) \(raw)")
            } else { check(false, "new automatic candidate \(pair.code) \(raw)") }
        }
        for literal in ["hello", "github", "chatgpt", "sus", "lmao", "username", "https://example.com/ghbdtn", "`ghbdtn`", "#perche"] {
            for pair in [LanguagePair.italian, .russian] { check(engine.review(literal, pair: pair).changes.isEmpty, "new language literal protection \(pair.code) \(literal)") }
        }
        print("PERSONALIZATION_CHECKS \(failures == 0 ? "PASS" : "FAIL") \(count - failures)/\(count)")
        return failures == 0
    }
}
