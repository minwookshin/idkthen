import XCTest
@testable import IdkthenCore

final class AdditionalLanguageTests: XCTestCase {
    struct Spelling: SpellingProvider {
        var reliable = true
        func isAvailable(_ language: String) -> Bool { ["en", "it", "ru"].contains(language) }
        func supportsAutomaticLayoutDetection(_ language: String) -> Bool { language != "ru" || reliable }
        func isWord(_ word: String, language: String) -> Bool {
            let words = ["en": ["hello", "the", "name"], "it": ["perché", "città", "caffè", "sì", "si", "e", "è"], "ru": ["привет", "спасибо", "работа"]]
            return words[language]?.contains(word.lowercased()) == true
        }
        func guesses(_ word: String, language: String) -> [String] { [] }
    }
    func testRussianPCMappingRoundTripAndCase() {
        let source = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>~"
        let mapped = RussianLayout.convert(source, toEnglish: false)
        XCTAssertEqual(RussianLayout.convert(mapped, toEnglish: true), source)
        XCTAssertEqual(RussianLayout.convert("Ghbdtn", toEnglish: false), "Привет")
        XCTAssertEqual(RussianLayout.convert("руддщ", toEnglish: true), "hello")
        XCTAssertEqual(RussianLayout.convert("ЁЖ", toEnglish: true), "~:")
    }
    func testRussianRecoveryPunctuationAndMixedScriptProtection() {
        let engine = ReviewEngine(spelling: Spelling())
        let review = engine.review("ghbdtn. cgfcb,j hello руддщ", pair: .russian)
        let choices = Dictionary(uniqueKeysWithValues: review.changes.filter { !$0.ambiguous }.map { ($0.id, $0.candidates[0]) })
        XCTAssertEqual(review.applying(choices), "привет. спасибо hello hello")
        for text in ["helloпривет", "한국ghbdtn", "https://x.com/ghbdtn", "`ghbdtn`", "ghbdtn_id"] {
            XCTAssertTrue(engine.review(text, pair: .russian).changes.isEmpty, text)
        }
    }
    func testRussianUnreliableDictionaryCannotAutoApprove() {
        let engine = ReviewEngine(spelling: Spelling(reliable: false))
        let review = engine.review("ghbdtn", pair: .russian)
        XCTAssertTrue(review.changes.first?.requiresExplicitChoice == true)
        XCTAssertNotNil(review.notice)
        let text = "ghbdtn "
        let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
        guard case .skip = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .russian, keepWords: []) else { return XCTFail("Unreliable Russian must stay manual") }
    }
    func testItalianAccentsAndMeaningRemainSeparate() {
        let engine = ReviewEngine(spelling: Spelling())
        let review = engine.review("perche citta caffe", pair: .italian)
        XCTAssertEqual(review.applying(Dictionary(uniqueKeysWithValues: review.changes.map { ($0.id, $0.candidates[0]) })), "perché città caffè")
        XCTAssertTrue(engine.review("si", pair: .italian).changes.allSatisfy(\.ambiguous))
        XCTAssertTrue(engine.review("Perche", pair: .italian).changes.allSatisfy(\.ambiguous))
        XCTAssertTrue(engine.review("perché", pair: .italian).changes.isEmpty)
        XCTAssertTrue(engine.review("perche", pair: .italian, keepWords: ["perche"]).changes.isEmpty)
    }
    func testNewLanguagesWorkInCombinedSelection() {
        let engine = ReviewEngine(spelling: Spelling())
        let selection = LanguageSelection([.russian, .italian])
        let review = engine.review("perche ghbdtn", languages: selection)
        XCTAssertEqual(review.applying(Dictionary(uniqueKeysWithValues: review.changes.map { ($0.id, $0.candidates[0]) })), "perché привет")
        XCTAssertEqual(selection.codes, "EN · IT · RU")
    }
    func testLowercaseSaraRequiresChoiceEvenWhenDictionaryOmitsTheName() {
        let engine = ReviewEngine(spelling: Spelling())
        let review = engine.review("sara", pair: .italian)
        XCTAssertEqual(review.changes.first?.candidates, ["sarà"])
        XCTAssertTrue(review.changes.first?.requiresExplicitChoice == true)
        for text in ["Ask sara ", "Sara sara ", "Domani sara "] {
            let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
            for languages in [LanguageSelection([.italian]), LanguageSelection([.italian, .spanish, .korean])] {
                guard case .skip = FastTypingPlan.make(word: word, document: text, engine: engine, languages: languages, keepWords: []) else {
                    XCTFail("Name/verb ambiguity needs explicit choice: \(text)"); continue
                }
            }
        }
    }
}
