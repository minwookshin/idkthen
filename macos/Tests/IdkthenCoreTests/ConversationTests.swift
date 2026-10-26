import XCTest
@testable import IdkthenCore

final class ConversationTests: XCTestCase {
    private let four = LanguageSelection([.spanish, .french, .korean])
    private func immediate(_ text: String, languages: LanguageSelection? = nil, keep: Set<String> = []) -> String {
        guard let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0), whileContinuing: true),
              case let .immediate(change) = FastTypingPlan.make(word: word, document: text, engine: ReviewEngine(spelling: TestSpelling()), languages: languages ?? four, keepWords: keep) else { return text }
        return TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after ?? text
    }
    func testReportedMixedConversationKeepsTheWritersPhrasing() {
        let input = "yeah i think 너는 지금 going home and 그리고 집에 rktj 이제 작업을 gkrpTwld and you will be glaema "
        var text = ""
        for token in input.split(separator: " ") { text = immediate(text + token + " ") }
        XCTAssertEqual(text, "yeah i think 너는 지금 going home and 그리고 집에 가서 이제 작업을 하겠징 and you will be 힘듬 ")
    }
    func testShortKoreanRequiresRecentContextAndKeepsNextWord() {
        XCTAssertEqual(immediate("안녕 근데 sksms "), "안녕 근데 나는 ")
        XCTAssertEqual(immediate("안녕 나는 지금 i'm thinking about sj "), "안녕 나는 지금 i'm thinking about 너 ")
        XCTAssertEqual(immediate("👩‍💻 지금 sj next"), "👩‍💻 지금 너 next")
        for text in ["sj ", "hello sj ", "안녕\nsj ", "안녕\u{2028}sj ", "지금 'sj' ", "지금 My username is sj "] {
            XCTAssertEqual(immediate(text), text)
        }
        XCTAssertEqual(immediate("지금 sj ", keep: ["sj"]), "지금 sj ")
        XCTAssertEqual(immediate("지금 sj ", languages: LanguageSelection([.spanish, .french])), "지금 sj ")
    }
    func testConversationShiftPunctuationAndUnicode() {
        for (input, output) in [("지금 gkrpTwld! ", "지금 하겠징! "), ("지금 glaema, ", "지금 힘듬, "), ("👩‍💻 cafe\u{301} 지금 (gkrpTwld), ", "👩‍💻 cafe\u{301} 지금 (하겠징), ")] {
            XCTAssertTrue(TextIdentity.matches(immediate(input), output), input)
        }
        let complete = "지금 gkrpTwld\n"
        XCTAssertEqual(immediate(complete), complete, "Return can send a chat; keep the Mac's Space/Tab boundary")
    }
    func testChatLiteralsAcrossEverySelectedCombination() {
        let samples: [LanguagePair: [String]] = [.spanish: ["jajsjaja", "tqm", "porfa"], .french: ["ptdr", "stp", "jsp"], .portuguese: ["kkk", "blz", "vlw"], .german: ["vllt", "hdl", "bzw"], .italian: ["cmq", "xke", "tvb"], .russian: ["спс", "щас", "хз"], .ukrainian: ["дяк", "пліз", "імхо"], .korean: ["ㅋㅋ", "ㄱㅅ", "ㅇㅈ"]]
        for mask in 1..<(1 << LanguagePair.allCases.count) where mask.nonzeroBitCount <= 3 {
            let partners = LanguagePair.allCases.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil }
            let languages = LanguageSelection(partners)
            for word in ["ngl", "lmfao", "iykyk", "rn", "gogo"] + partners.flatMap({ samples[$0] ?? [] }) {
                let source = "지금 " + word + " "
                XCTAssertEqual(immediate(source, languages: languages), source, languages.codes + ": " + word)
            }
        }
    }
    func testUnknownTokensAndLiteralUsesStayUntouched() {
        for source in ["지금 rkskehf ", "지금 Rkskehf ", "지금 helloWorld ", "지금 #gkrpTwld ", "지금 https://example.com/gkrpTwld ", "지금 `gkrpTwld` ", "닉네임은 gkrpTwld "] {
            XCTAssertEqual(immediate(source), source)
        }
    }
    func testSelectedShorthandWinsEvenWhenAnotherDictionarySuggestsAWord() {
        struct Collision: SpellingProvider {
            func isAvailable(_ language: String) -> Bool { true }
            func isWord(_ word: String, language: String) -> Bool { language == "ko" && word == Hangul.fromQWERTY("ptdr") }
            func guesses(_ word: String, language: String) -> [String] { [] }
        }
        let review = ReviewEngine(spelling: Collision()).review("ptdr", languages: four)
        XCTAssertTrue(review.changes.isEmpty, "French shorthand must protect against the Korean dictionary too")
    }
}
