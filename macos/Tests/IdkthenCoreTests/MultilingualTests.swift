import XCTest
@testable import IdkthenCore

final class MultilingualTests: XCTestCase {
    private struct Spelling: SpellingProvider {
        let base = TestSpelling()
        func isAvailable(_ language: String) -> Bool { base.isAvailable(language) }
        func isWord(_ word: String, language: String) -> Bool {
            if language == "de", ["für", "über", "schön", "zurück", "größer", "Häuser", "neue", "Feuer", "Mueller"].contains(word) { return true }
            if language == "en", ["queue", "aerobic"].contains(word) { return true }
            return base.isWord(word, language: language)
        }
        func guesses(_ word: String, language: String) -> [String] {
            if language == "fr", word == "l'ecole" { return ["l'école", "d'école"] }
            if language == "pt_BR", word == "acao" { return ["ação", "acho"] }
            return base.guesses(word, language: language)
        }
    }
    private var engine: ReviewEngine { ReviewEngine(spelling: Spelling()) }
    private func plan(_ text: String, pair: LanguagePair, kept: Set<String> = []) -> FastTypingPlan {
        guard let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0), whileContinuing: true) else { return .skip }
        return FastTypingPlan.make(word: word, document: text, engine: engine, pair: pair, keepWords: kept)
    }
    private func immediate(_ text: String, pair: LanguagePair, kept: Set<String> = []) -> String {
        guard case let .immediate(change) = plan(text, pair: pair, kept: kept) else { return text }
        return TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after ?? text
    }
    func testCompoundCorrectionIsOneTransactionAndKeepsSurroundingText() throws {
        for (pair, original, replacement) in [(LanguagePair.spanish, "manana-despues", "mañana-después"), (.portuguese, "reuniao-acao", "reunião-ação"), (.korean, "chromedptj-GitHubfmf", "chrome에서-GitHub를")] {
            let source = "👩‍💻 cafe\u{301} (" + original + "), next"
            guard case let .immediate(change) = plan(source, pair: pair) else { return XCTFail(source) }
            XCTAssertEqual(change.original, original)
            XCTAssertEqual(change.candidates, [replacement])
            let transaction = TextTransaction(before: source, range: change.range, replacement: replacement)
            let result = try XCTUnwrap(transaction.after)
            XCTAssertTrue(TextIdentity.matches(result, "👩‍💻 cafe\u{301} (" + replacement + "), next"))
            XCTAssertTrue(transaction.canUndo(current: result))
            XCTAssertFalse(transaction.canUndo(current: result + "!"))
            XCTAssertEqual(immediate(source, pair: pair, kept: [original]), source, "An undone compound must not be corrected again")
        }
    }
    func testCompoundCannotHideAnAmbiguousOrQuotedComponent() {
        for (pair, text) in [(LanguagePair.spanish, "manana-si "), (.french, "deja-resume "), (.portuguese, "reuniao-por "), (.spanish, "manana-\"despues\" "), (.spanish, "manana-«despues» ")] {
            XCTAssertEqual(immediate(text, pair: pair), text)
        }
    }
    func testKeepingWholeCompoundAndKeepingOnePartAreDifferent() {
        let text = "(reuniao-acao), "
        XCTAssertEqual(immediate(text, pair: .portuguese, kept: ["reuniao-acao"]), text)
        XCTAssertEqual(immediate(text, pair: .portuguese, kept: ["reuniao"]), "(reuniao-ação), ")
        XCTAssertEqual(immediate("manana-despues ", pair: .spanish, kept: ["reuniao-acao"]), "mañana-después ")
    }
    func testApostropheVariantsUseDictionaryWithoutChangingTheirStyle() {
        for mark in ["'", "’", "ʼ"] {
            let source = "l" + mark + "ecole "
            XCTAssertTrue(TextIdentity.matches(immediate(source, pair: .french), "l" + mark + "école "))
            XCTAssertEqual(immediate(source, pair: .french, kept: ["l" + mark + "ecole"]), source)
        }
    }
    func testGermanTranscriptionIsExplicitEvenWithOnlyOneCandidate() {
        for (source, expected) in [("fuer", "für"), ("ueber", "über"), ("schoen", "schön"), ("groesser", "größer"), ("Haeuser", "Häuser")] {
            let review = engine.review(source, pair: .german)
            XCTAssertTrue(review.changes.contains { $0.candidates.contains(expected) && $0.ambiguous && $0.requiresExplicitChoice }, source)
            var choices = ReviewChoices(); choices.update(review, preserving: false)
            XCTAssertTrue(choices.selected.isEmpty)
            guard case .skip = plan(source + " ", pair: .german) else { return XCTFail("An on-device model must not approve an intentional ASCII spelling") }
        }
    }
    func testGermanTranscriptionKeepsNamesExistingWordsAndHasABoundedSearch() {
        for word in ["Mueller", "neue", "Feuer", "queue", "aerobic", "MÜNCHEN", "ueber_id", "https://ueber.de"] {
            XCTAssertTrue(engine.review(word, pair: .german).changes.isEmpty, word)
        }
        XCTAssertTrue(GermanTranscription.candidates(for: String(repeating: "ae", count: 5), spelling: Spelling()).isEmpty)
        XCTAssertTrue(GermanTranscription.candidates(for: String(repeating: "a", count: 49) + "ue", spelling: Spelling()).isEmpty)
        XCTAssertEqual(immediate("ueber ", pair: .spanish), "ueber ")
    }
    func testBroaderKoreanEndingsCopyTheStemAndExactWording() {
        for ending in ["에서라도", "에서조차", "에서마저", "에서부터는", "으로부터는", "에게서는", "한테서는", "로부터", "에다가", "이라서", "이니까", "이라면", "이지만", "이거나", "이든지"] {
            let source = "GitHub" + Hangul.toQWERTY(ending) + " "
            XCTAssertEqual(immediate(source, pair: .korean), "GitHub" + ending + " ")
            XCTAssertEqual(immediate("GitHub" + ending + " ", pair: .korean), "GitHub" + ending + " ")
        }
    }
    func testRecentKoreanContextSupportsNFDAndStopsAtNewlines() {
        let nfd = "오늘".decomposedStringWithCanonicalMapping
        XCTAssertTrue(TextIdentity.matches(immediate(nfd + " chromedp ", pair: .korean), nfd + " chrome에 "))
        for separator in ["\n", "\r\n", "\u{2028}", "\u{2029}"] {
            for word in ["chromedp", "dltdjd"] {
                let source = "안녕" + separator + word + " "
                XCTAssertEqual(immediate(source, pair: .korean), source)
            }
        }
    }
    func testUnicodeEquivalentNewerTextInvalidatesApplyAndUndo() throws {
        let before = "café dkssud "
        let transaction = TextTransaction(before: before, range: (before as NSString).range(of: "dkssud"), replacement: "안녕")
        let nfd = before.decomposedStringWithCanonicalMapping
        XCTAssertEqual(nfd, before, "Swift canonical equality demonstrates the stale-range hazard")
        XCTAssertFalse(transaction.canApply(to: nfd))
        let after = try XCTUnwrap(transaction.after)
        XCTAssertFalse(transaction.canUndo(current: after.decomposedStringWithCanonicalMapping))
        XCTAssertTrue(transaction.canApply(to: before)); XCTAssertTrue(transaction.canUndo(current: after))
        let change = Change(range: NSRange(location: 0, length: 4), original: "café", candidates: ["candidate"], reason: "fixture", ambiguous: false)
        XCTAssertNil(CorrectionContext(text: "cafe\u{301}", change: change))
        let reordered = "a\u{301}\u{323}", otherOrder = "a\u{323}\u{301}"
        XCTAssertEqual(reordered, otherOrder)
        XCTAssertEqual(reordered.utf16.count, otherOrder.utf16.count)
        XCTAssertFalse(TextIdentity.matches(reordered, otherOrder))
    }
    func testStaleLiveWordCannotCorrectAnUnrelatedNewerDocument() throws {
        let word = try XCTUnwrap(LiveWord.completed(in: "dkssud ", selection: NSRange(location: 7, length: 0)))
        guard case .skip = FastTypingPlan.make(word: word, document: "abcdef ", engine: engine, pair: .korean, keepWords: []) else { return XCTFail("Word and document no longer match") }
    }
    func testLiteralProtectionAcrossAllPairs() {
        for (pair, word) in [(LanguagePair.spanish, "manana"), (.french, "deja"), (.german, "ueber"), (.portuguese, "reuniao"), (.korean, "chromedptj"), (.ukrainian, "ghbdsn")] {
            for text in ["--" + word, "<" + word + ">", "x::" + word, word + "\u{200B}", word + "\u{00AD}", "\u{202E}" + word] {
                XCTAssertTrue(engine.review(text, pair: pair).changes.isEmpty, text)
            }
            for text in ["«" + word + "» ", "„" + word + "“ ", "「" + word + "」 "] {
                XCTAssertEqual(immediate(text, pair: pair), text)
            }
        }
    }
    func testUnavailableKoreanDictionaryCannotUseColloquialFallback() throws {
        var spelling = TestSpelling(); spelling.available.remove("ko")
        let text = "안녕 dltdjd "
        let word = try XCTUnwrap(LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0)))
        guard case .skip = FastTypingPlan.make(word: word, document: text, engine: ReviewEngine(spelling: spelling), pair: .korean, keepWords: []) else { return XCTFail("Unavailable language should not silently enable fallback") }
    }
    func testKnownEnglishNamesAndInternetExpressionsSurviveAllPairs() {
        for pair in LanguagePair.allCases {
            for term in ["figma", "chatgpt", "vscode", "openai", "vercel", "sus", "lmao", "rizz"] {
                XCTAssertTrue(engine.review(term, pair: pair).changes.isEmpty, "\(pair.code) \(term)")
                XCTAssertEqual(immediate("안녕 " + term + " ", pair: pair), "안녕 " + term + " ")
            }
        }
        XCTAssertEqual(immediate("verceldptj ", pair: .korean), "vercel에서 ")
        XCTAssertFalse(engine.review("sus", pair: .korean, direction: .toPartner).changes.isEmpty, "Explicit layout review remains available")
    }
    func testUnreliableDictionaryCannotApproveAnAutomaticOrModelEdit() throws {
        struct Unreliable: SpellingProvider {
            let base = TestSpelling()
            func isAvailable(_ language: String) -> Bool { true }
            func isWord(_ word: String, language: String) -> Bool { language == "uk" || base.isWord(word, language: language) }
            func guesses(_ word: String, language: String) -> [String] { [] }
            func supportsAutomaticLayoutDetection(_ language: String) -> Bool { language != "uk" }
        }
        let engine = ReviewEngine(spelling: Unreliable())
        let review = engine.review("ghbdsn", pair: .ukrainian)
        XCTAssertNotNil(review.notice)
        let change = try XCTUnwrap(review.changes.first)
        XCTAssertEqual(change.candidates, ["привіт"])
        XCTAssertTrue(change.ambiguous); XCTAssertTrue(change.requiresExplicitChoice)
        var choices = ReviewChoices(); choices.update(review, preserving: false)
        XCTAssertTrue(choices.selected.isEmpty)
        choices.choose("привіт", for: change)
        XCTAssertEqual(review.applying(choices.selected), "привіт", "The user can still review and apply an exact mapping")
        let word = try XCTUnwrap(LiveWord.completed(in: "ghbdsn ", selection: NSRange(location: 7, length: 0)))
        guard case .skip = FastTypingPlan.make(word: word, document: "ghbdsn ", engine: engine, pair: .ukrainian, keepWords: []) else { return XCTFail("Unreliable dictionary must not authorize AI or immediate replacement") }
    }

}
