import XCTest
@testable import IdkthenCore

private struct AmbiguousAccentSpelling: SpellingProvider {
    let base = TestSpelling()
    func isAvailable(_ language: String) -> Bool { base.isAvailable(language) }
    func isWord(_ word: String, language: String) -> Bool {
        // Match real dictionary ambiguities, including valid unaccented words.
        let additional = ["en": ["deja", "arrive"], "fr": ["arrive", "arrivé", "près", "prés"], "pt_BR": ["amanha", "amanhã"], "es": ["deja"]]
        return additional[language]?.contains(word.lowercased()) == true || base.isWord(word, language: language)
    }
    func guesses(_ word: String, language: String) -> [String] { base.guesses(word, language: language) }
}

final class AccentContextTests: XCTestCase {
    private let engine = ReviewEngine(spelling: AmbiguousAccentSpelling())
    private func automatic(_ text: String, pair: LanguagePair, keep: Set<String> = []) throws -> String {
        let word = try XCTUnwrap(LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0)))
        if case let .immediate(change) = FastTypingPlan.make(word: word, document: text, engine: engine, pair: pair, keepWords: keep) {
            return try XCTUnwrap(TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after)
        }
        return text
    }
    func testFrenchAuxiliaryDisambiguatesAccentsWithoutAContextModel() throws {
        for (input, expected) in [("Je suis deja ", "Je suis déjà "), ("Je suis déjà arrive. ", "Je suis déjà arrivé. "),
                                  ("Il est enfin arrive ", "Il est enfin arrivé "), ("Nous sommes bien arrives ", "Nous sommes bien arrivés ")] {
            XCTAssertEqual(try automatic(input, pair: .french), expected)
        }
    }
    func testFrenchLocationChoosesNearInsteadOfMeadows() throws {
        for input in ["Il habite pres ", "Elle habite tout pres ", "Nous habitons assez pres ", "J’habite pres "] {
            XCTAssertEqual(try automatic(input, pair: .french), input.replacingOccurrences(of: "pres", with: "près"))
        }
        for input in ["Les pres ", "dans les pres ", "pres "] {
            XCTAssertEqual(try automatic(input, pair: .french), input)
        }
    }
    func testPortugueseScheduleChoosesTomorrowWithoutChangingVerb() throws {
        for input in ["A reunião e amanha. ", "A consulta é amanha ", "O encontro será amanha "] {
            XCTAssertEqual(try automatic(input, pair: .portuguese), input.replacingOccurrences(of: "amanha", with: "amanhã"))
        }
        for input in ["Ele amanha ", "amanha ", "Ela amanha ", "ele amanha a terra "] {
            XCTAssertEqual(try automatic(input, pair: .portuguese), input)
        }
    }
    func testValidWordsAndNamesRemainUnchangedWithoutLocalEvidence() throws {
        for input in ["We arrive ", "J’arrive ", "Elle arrive ", "deja ", "Ask Deja ", "Je suis Deja ", "Je suis calme "] {
            XCTAssertEqual(try automatic(input, pair: .french), input)
        }
    }
    func testContextDoesNotCrossSentenceLineOrQuoteBoundaries() throws {
        for input in ["Je suis. arrive ", "Je suis\narrive ", "Je suis: arrive ", "\"Je suis arrive\" ", "Il habite. pres "] {
            XCTAssertEqual(try automatic(input, pair: .french), input)
        }
    }
    func testKeptWordsAndOtherEnabledLanguagesStillTakePriority() throws {
        XCTAssertEqual(try automatic("Je suis arrive ", pair: .french, keep: ["arrive"]), "Je suis arrive ")
        let review = engine.review("Je suis deja", languages: LanguageSelection([.french, .spanish]))
        let change = try XCTUnwrap(review.changes.first { $0.original == "deja" })
        XCTAssertTrue(change.requiresExplicitChoice, "A competing enabled language still requires a choice")
    }
    func testWholeReviewAndLiveReviewUseTheSameBoundedRules() {
        let review = engine.review("Je suis deja arrive. Il habite pres de Paris.", pair: .french)
        var choices = ReviewChoices(); choices.update(review, preserving: false)
        XCTAssertEqual(review.applying(choices.selected), "Je suis déjà arrivé. Il habite près de Paris.")
    }
}
