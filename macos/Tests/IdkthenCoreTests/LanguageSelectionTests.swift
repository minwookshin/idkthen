import XCTest
@testable import IdkthenCore

final class LanguageSelectionTests: XCTestCase {
    private struct Spelling: SpellingProvider {
        var base = TestSpelling()
        var unreliableUkrainian = false
        var acceptsLatinInKorean = false
        var overlappingUkrainian = false
        func isAvailable(_ language: String) -> Bool { base.isAvailable(language) }
        func supportsAutomaticLayoutDetection(_ language: String) -> Bool { language != "uk" || !unreliableUkrainian }
        func isWord(_ word: String, language: String) -> Bool {
            if language == "uk", unreliableUkrainian { return true }
            if language == "uk", overlappingUkrainian, word == UkrainianLayout.convert("manana,", toEnglish: false) { return true }
            if language == "ko", acceptsLatinInKorean, word == "manana" { return true }
            if language == "fr", ["l'école", "café", "menu", "dltdjd"].contains(word) { return true }
            if language == "es", ["café", "deja", "hola"].contains(word) { return true }
            return base.isWord(word, language: language)
        }
        func guesses(_ word: String, language: String) -> [String] {
            if language == "fr", word == "l'ecole" { return ["l'école"] }
            if ["fr", "es"].contains(language), word == "cafe" { return ["café"] }
            return base.guesses(word, language: language)
        }
    }
    private let four = LanguageSelection([.spanish, .french, .korean])
    private func plan(_ text: String, selection: LanguageSelection, spelling: Spelling = Spelling(), kept: Set<String> = []) -> FastTypingPlan {
        guard let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0), whileContinuing: true) else { return .skip }
        return FastTypingPlan.make(word: word, document: text, engine: ReviewEngine(spelling: spelling), languages: selection, keepWords: kept)
    }
    private func immediate(_ text: String, selection: LanguageSelection, spelling: Spelling = Spelling(), kept: Set<String> = []) -> String {
        guard case let .immediate(change) = plan(text, selection: selection, spelling: spelling, kept: kept) else { return text }
        return TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after ?? text
    }
    func testSelectionCountsEnglishAndEnforcesLimitsWithoutReplacingAnExistingLanguage() throws {
        XCTAssertEqual(LanguageSelection([]).count, 2)
        XCTAssertEqual(LanguageSelection([.korean, .korean]).partners, [.korean])
        XCTAssertNil(LanguageSelection([.korean]).toggling(.korean))
        XCTAssertEqual(four.count, 4)
        XCTAssertNil(four.toggling(.german))
        let three = try XCTUnwrap(four.toggling(.spanish))
        XCTAssertEqual(three.count, 3)
        XCTAssertTrue(try XCTUnwrap(three.toggling(.portuguese)).contains(.portuguese))
        XCTAssertEqual(LanguageSelection([.korean, .spanish, .french, .german]).partners, four.partners)
    }
    func testOneSharedReviewContainsThreePartnerLanguages() throws {
        let text = "👩‍💻 manana l'ecole chromedptj https://example.com/manana"
        let review = ReviewEngine(spelling: Spelling()).review(text, languages: four)
        let choices = Dictionary(uniqueKeysWithValues: review.changes.filter { !$0.ambiguous }.map { ($0.id, $0.candidates[0]) })
        XCTAssertEqual(review.applying(choices), "👩‍💻 mañana l'école chrome에서 https://example.com/manana")
        XCTAssertEqual(Set(review.changes.flatMap(\.languages)), Set([.spanish, .french, .korean]))
        XCTAssertEqual(review.protectedCount, 1)
    }
    func testCompetingAccentsStayUnselectedAndNeverReachAI() throws {
        let review = ReviewEngine(spelling: Spelling()).review("reunion", languages: four)
        let change = try XCTUnwrap(review.changes.first)
        XCTAssertEqual(Set(change.candidates), Set(["reunión", "réunion"]))
        XCTAssertTrue(change.ambiguous && change.requiresExplicitChoice)
        var choices = ReviewChoices(); choices.update(review, preserving: false)
        XCTAssertTrue(choices.selected.isEmpty)
        if case .skip = plan("reunion ", selection: four) {} else { XCTFail("A conflict must not enter automatic/model approval") }
        XCTAssertEqual(review.applying([change.id: "réunion"]), "réunion")
    }
    func testWordAcceptedByAnotherEnabledLanguageRequiresAnExplicitChoice() throws {
        for original in ["deja", "menu"] {
            let change = try XCTUnwrap(ReviewEngine(spelling: Spelling()).review(original, languages: four).changes.first)
            XCTAssertTrue(change.requiresExplicitChoice)
            XCTAssertEqual(immediate(original + " ", selection: four), original + " ")
        }
        XCTAssertEqual(immediate("안녕 dltdjd ", selection: four), "안녕 dltdjd ", "Colloquial fallback must consult other enabled languages")
        XCTAssertEqual(immediate("안녕 dltdjd ", selection: LanguageSelection([.korean])), "안녕 잇엉 ")
    }
    func testSameCandidateIsDeduplicatedWithoutCreatingAnArtificialConflict() throws {
        let change = try XCTUnwrap(ReviewEngine(spelling: Spelling()).review("cafe", languages: four).changes.first)
        XCTAssertEqual(change.candidates, ["café"])
        XCTAssertEqual(change.languages, [.spanish, .french])
        XCTAssertFalse(change.ambiguous)
    }
    func testUnvalidatedForeignScriptDoesNotBlockAClearAccent() {
        var spelling = Spelling(); spelling.acceptsLatinInKorean = true
        XCTAssertEqual(immediate("manana ", selection: four, spelling: spelling), "mañana ")
    }
    func testUnreliableLayoutCannotPoisonOtherEnabledLanguages() {
        var spelling = Spelling(); spelling.unreliableUkrainian = true
        let selection = LanguageSelection([.spanish, .ukrainian])
        let review = ReviewEngine(spelling: spelling).review("manana", languages: selection)
        XCTAssertNotNil(review.notice)
        XCTAssertEqual(review.changes.flatMap(\.languages), [.spanish])
        XCTAssertEqual(immediate("manana ", selection: selection, spelling: spelling), "mañana ")
    }
    func testOverlappingTokenizersProduceOneExplicitNonOverlappingChoice() throws {
        var spelling = Spelling(); spelling.overlappingUkrainian = true
        let selection = LanguageSelection([.spanish, .ukrainian])
        let text = "manana,"
        let review = ReviewEngine(spelling: spelling).review(text, languages: selection)
        XCTAssertEqual(review.changes.count, 1)
        let change = try XCTUnwrap(review.changes.first)
        XCTAssertEqual(change.original, text)
        XCTAssertTrue(change.candidates.contains("mañana,"))
        XCTAssertTrue(change.requiresExplicitChoice)
        XCTAssertEqual(immediate(text + " ", selection: selection, spelling: spelling), text + " ")
        for candidate in change.candidates { XCTAssertEqual(review.applying([change.id: candidate]), candidate) }
    }
    func testMixedCompoundHasOneUndoableEditAndNeverHidesAConflict() throws {
        let text = "👩‍💻 cafe\u{301} manana-chromedptj next"
        guard case let .immediate(change) = plan(text, selection: four) else { return XCTFail("Expected a mixed compound") }
        let transaction = TextTransaction(before: text, range: change.range, replacement: change.candidates[0])
        XCTAssertTrue(TextIdentity.matches(try XCTUnwrap(transaction.after), "👩‍💻 cafe\u{301} mañana-chrome에서 next"))
        XCTAssertTrue(transaction.canUndo(current: transaction.after!))
        XCTAssertFalse(transaction.canUndo(current: transaction.after! + "new"))
        XCTAssertFalse(transaction.canApply(to: text.precomposedStringWithCanonicalMapping))
        XCTAssertEqual(immediate(text, selection: four, kept: ["manana-chromedptj"]), text)
        XCTAssertEqual(immediate("manana-reunion ", selection: four), "manana-reunion ")
    }
    func testEveryTwoToFourLanguageCombinationPreservesProtectionAndStableOrder() {
        let pairs = LanguagePair.allCases
        var count = 0
        for bits in 1..<(1 << pairs.count) {
            let selected = pairs.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element)
            guard selected.count <= 3 else { continue }
            count += 1
            let selection = LanguageSelection(selected)
            let reverse = LanguageSelection(selected.reversed())
            let engine = ReviewEngine(spelling: Spelling())
            let corpus = "manana reunion l'ecole chromedptj ghbdsn"
            XCTAssertEqual(engine.review(corpus, languages: selection).changes, engine.review(corpus, languages: reverse).changes)
            for text in ["https://example.com/manana ", "#chromedptj ", "`l'ecole` ", "sus ", "figma ", "reunion\n", "manana_id ", "manana\u{200B} "] {
                XCTAssertEqual(immediate(text, selection: selection), text, selection.codes)
            }
            if let single = selection.singlePair {
                XCTAssertEqual(engine.review(corpus, languages: selection).changes, engine.review(corpus, pair: single).changes)
            }
        }
        XCTAssertEqual(count, 92)
    }
    func testMissingDictionaryDoesNotDisableTheRemainingLanguages() {
        var spelling = Spelling(); spelling.base.available.remove("fr")
        let review = ReviewEngine(spelling: spelling).review("manana chromedptj", languages: four)
        XCTAssertNotNil(review.notice)
        XCTAssertEqual(review.changes.flatMap(\.languages), [.spanish, .korean])
        XCTAssertEqual(immediate("chromedptj ", selection: four, spelling: spelling), "chrome에서 ")
    }
    func testStaleTextAndForcedDirectionsCannotBypassTheCombinedReview() throws {
        let word = try XCTUnwrap(LiveWord.completed(in: "dkssud ", selection: NSRange(location: 7, length: 0)))
        if case .skip = FastTypingPlan.make(word: word, document: "abcdef ", engine: ReviewEngine(spelling: Spelling()), languages: four, keepWords: []) {} else { XCTFail("Stale input") }
        let review = ReviewEngine(spelling: Spelling()).review("manana", languages: four, direction: .toPartner)
        XCTAssertTrue(review.changes.isEmpty); XCTAssertNotNil(review.notice)
    }
}
