import XCTest
@testable import IdkthenCore

final class IntentSafetyTests: XCTestCase {
    private let engine = ReviewEngine(spelling: TestSpelling())

    func testValidSpellingCannotBeApprovedByContextInASinglePair() throws {
        for (pair, original) in [(LanguagePair.french, "resume"), (.spanish, "si"), (.spanish, "tu"),
                                 (.spanish, "papa"), (.german, "schon"), (.german, "fur"),
                                 (.portuguese, "por"), (.portuguese, "pode")] {
            let change = try XCTUnwrap(engine.review(original, pair: pair).changes.first, original)
            XCTAssertTrue(change.requiresExplicitChoice, original)
            var decisions = ReviewChoices(); decisions.update(engine.review(original, pair: pair), preserving: false)
            XCTAssertTrue(decisions.selected.isEmpty, original)
            let text = original + " "
            let word = try XCTUnwrap(LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0)))
            guard case .skip = FastTypingPlan.make(word: word, document: text, engine: engine, pair: pair, keepWords: [])
            else { return XCTFail("A context model could override valid spelling: \(original)") }
        }
    }

    func testSlangNamesAndIdentifiersSurviveAll92LanguageSets() throws {
        let partners = LanguagePair.allCases
        var sets = partners.map { LanguageSelection([$0]) }
        for i in partners.indices {
            for j in partners.indices where j > i {
                sets.append(LanguageSelection([partners[i], partners[j]]))
                for k in partners.indices where k > j { sets.append(LanguageSelection([partners[i], partners[j], partners[k]])) }
            }
        }
        XCTAssertEqual(sets.count, 92)
        for selection in sets {
            for literal in ["lol", "lmao", "idk", "tbh", "GitHub", "OpenAI", "iPhone", "@manana", "#resume", "user_name", "https://site.com/ghbdtn", "`chromedptj`"] {
                let text = literal + " "
                guard let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0)) else { continue }
                guard case .skip = FastTypingPlan.make(word: word, document: text, engine: engine, languages: selection, keepWords: [])
                else { return XCTFail("\(selection.codes) changed \(literal)") }
            }
        }
    }

    func testSourceLayoutDoesNotSilentlyFallBackToTwoSet() {
        for id in ["com.apple.inputmethod.Korean.3SetKorean", "com.apple.inputmethod.Korean.390Sebulshik",
                   "com.apple.inputmethod.Korean.HNCRomaja", "com.apple.keylayout.Dvorak", "custom.layout"] {
            XCTAssertFalse(KeyboardLayoutPolicy.permits(.korean, sourceID: id))
            XCTAssertTrue(KeyboardLayoutPolicy.permits(.spanish, sourceID: id), "Accent review does not interpret physical keys")
        }
        XCTAssertFalse(KeyboardLayoutPolicy.permits(.korean, sourceID: nil))
        XCTAssertTrue(KeyboardLayoutPolicy.permits(.korean, sourceID: "com.apple.keylayout.ABC"))
        XCTAssertTrue(KeyboardLayoutPolicy.permits(.korean, sourceID: "com.apple.inputmethod.Korean.2SetKorean"))
        XCTAssertTrue(KeyboardLayoutPolicy.permits(.russian, sourceID: "com.apple.keylayout.Russian"))
        XCTAssertFalse(KeyboardLayoutPolicy.permits(.korean, sourceID: "com.apple.keylayout.Russian"))
    }
}
