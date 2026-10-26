import AppKit
import IdkthenCore

/// Local trial checks do not load or modify the user's preferences or live access.
@MainActor enum PracticeChecks {
    static func run() -> Bool {
        var count = 0, failures = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1; if !condition { failures += 1 }
            print("PRACTICE \(name): \(condition ? "PASS" : "FAIL")")
        }
        func trial(_ partners: [LanguagePair] = [.korean], mode: LiveCorrectionMode = .automatic, keep: Set<String> = []) -> TypingTrial {
            let value = TypingTrial(); value.configure(languages: LanguageSelection(partners), mode: mode, keepWords: keep)
            return value
        }
        @discardableResult func enter(_ text: String, into value: TypingTrial, marked: Bool = false, history: Bool = false) -> TypingTrial.Edit? {
            value.userEdited(text, selection: NSRange(location: (text as NSString).length, length: 0), hasMarkedText: marked, isHistoryChange: history)
        }
        let korean = trial()
        check(enter("dkssud", into: korean) == nil && korean.text == "dkssud", "no correction before word boundary")
        let greeting = enter("dkssud ", into: korean)
        check(korean.text == "안녕 " && greeting?.afterSelection.location == 3 && korean.canUndo, "Space applies clear Korean and preserves caret")
        check(korean.undo()?.after == "dkssud " && !korean.canUndo, "Undo restores exact original and space")
        enter("dkssud dkssud ", into: korean)
        check(korean.text == "dkssud dkssud ", "undone word stays unchanged for the trial session")
        korean.clear(); enter("dkssud ", into: korean)
        check(korean.text == "안녕 ", "Clear removes temporary keep history")
        let compound = trial()
        enter("chromedptj ", into: compound)
        check(compound.text == "chrome에서 ", "mixed English name and Korean ending")
        compound.userEdited(compound.text, selection: NSRange(location: 0, length: 0), isHistoryChange: true)
        check(compound.undo() == nil && compound.text == "chrome에서 ", "moving or editing cannot restore stale correction")
        let four = trial([.spanish, .french, .korean])
        for word in ["manana", "l'ecole", "chromedptj"] { enter(four.text + word + " ", into: four) }
        check(four.text == "mañana l'école chrome에서 ", "four-language continuous local typing")
        let suggest = trial(mode: .suggest)
        enter("chromedptj ", into: suggest)
        check(suggest.text == "chromedptj " && suggest.pending != nil && !suggest.canUndo, "Suggest never applies before a choice")
        check(suggest.accept()?.after == "chrome에서 " && suggest.pending == nil && suggest.canUndo, "Apply accepts current suggestion")
        let stale = trial(mode: .suggest)
        enter("dkssud ", into: stale)
        stale.selectionChanged(text: stale.text, selection: NSRange(location: 0, length: 0))
        check(stale.accept() == nil && stale.text == "dkssud ", "caret movement invalidates pending Apply")
        enter("dkssud ", into: stale); enter("dkssud newer", into: stale)
        check(stale.accept() == nil && stale.text == "dkssud newer", "new input invalidates pending Apply")
        let competing = trial([.spanish, .french, .korean])
        enter("reunion ", into: competing)
        check(competing.text == "reunion " && competing.pending == nil, "competing languages require full review")
        let german = trial([.german])
        enter("fuer ", into: german)
        check(german.text == "fuer " && german.pending == nil, "explicit-choice German transcription cannot auto apply")
        let protected = trial(keep: ["chromedptj"])
        enter("chromedptj ", into: protected)
        check(protected.text == "chromedptj " && protected.pending == nil, "Words to Keep are respected")
        for literal in ["hello ", "https://example.com/chromedptj ", "`dkssud` "] {
            let value = trial(); enter(literal, into: value)
            check(value.text == literal && value.pending == nil, "protect literal \(literal.trimmingCharacters(in: .whitespaces))")
        }
        let unicode = trial()
        let prefix = "👩‍💻 cafe\u{301} "
        let unicodeEdit = enter(prefix + "chromedptj ", into: unicode)
        check(TextIdentity.matches(unicode.text, prefix + "chrome에서 ") && unicodeEdit?.afterSelection.location == (unicode.text as NSString).length,
              "emoji and NFD surroundings keep exact UTF-16 and caret")
        check(TextIdentity.matches(unicode.undo()?.after ?? "", prefix + "chromedptj "), "Unicode Undo restores original encoding")
        let composition = trial()
        enter("dkssud ", into: composition, marked: true)
        check(composition.text == "dkssud " && composition.pending == nil, "marked IME composition is untouched")
        let selected = trial()
        selected.userEdited("dkssud ", selection: NSRange(location: 0, length: 6))
        check(selected.text == "dkssud " && !selected.canUndo, "noncollapsed selection cannot auto apply")
        let oversized = trial()
        let longText = String(repeating: "a", count: 4_001) + " dkssud "
        enter(longText, into: oversized)
        check(oversized.text == longText && !oversized.canUndo, "bounded trial keeps long input unchanged")
        let history = trial()
        enter("dkssud ", into: history); enter("dkssud ", into: history, history: true)
        enter("dkssud dkssud ", into: history)
        check(history.text == "dkssud dkssud ", "native Undo does not trigger a correction loop")
        let reconfigured = trial(mode: .suggest)
        enter("dkssud ", into: reconfigured)
        reconfigured.configure(languages: LanguageSelection([.spanish]), mode: .automatic, keepWords: [])
        check(reconfigured.text == "dkssud " && reconfigured.pending == nil && reconfigured.accept() == nil, "settings changes preserve text and invalidate choices")
        let example = trial([.spanish, .french, .korean])
        example.loadExample()
        check(example.text == "chromedptj" && !example.canUndo && example.pending == nil, "example requires a real Space before checking")
        example.clear()
        check(example.text.isEmpty && example.pending == nil && !example.canUndo, "Clear removes all local test state")
        print("PRACTICE_CHECKS \(failures == 0 ? "PASS" : "FAIL") \(count - failures)/\(count)")
        return failures == 0
    }
}
