import XCTest
@testable import IdkthenCore

final class PersonalizationTests: XCTestCase {
    func testThreeIndependentCorrectionsRequired() throws {
        var memory = UndoLearning()
        let first = UndoFeedback(original: "Chromedptj")
        XCTAssertFalse(memory.record(first))
        for _ in 0..<8 { XCTAssertFalse(memory.record(first)) }
        XCTAssertTrue(memory.learnedWords.isEmpty)
        XCTAssertFalse(memory.record(UndoFeedback(original: "chromedptj")))
        XCTAssertTrue(memory.record(UndoFeedback(original: "CHROMEDPTJ")))
        XCTAssertEqual(memory.learnedWords, ["chromedptj"])
        XCTAssertFalse(memory.record(UndoFeedback(original: "chromedptj")))
    }
    func testEvidencePersistsButNoReceiptOrContextIsSerialized() throws {
        var memory = UndoLearning()
        let receipt = UndoFeedback(original: "cafe\u{301}")
        memory.record(receipt); memory.record(UndoFeedback(original: "café"))
        let encoded = try JSONEncoder().encode(memory)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(receipt.id.uuidString))
        var restored = try JSONDecoder().decode(UndoLearning.self, from: encoded)
        XCTAssertTrue(restored.record(UndoFeedback(original: "CAFÉ")))
        XCTAssertEqual(restored.learnedWords, ["café"])
    }
    func testRejectSentencesAddressesCodeAndControls() {
        var memory = UndoLearning()
        for word in ["a", "two words", "a\nb", "user@example.com", "https://example.com", "token123", "a\u{200B}b", "🙂🙂", String(repeating: "a", count: 97)] {
            for _ in 0..<3 { memory.record(UndoFeedback(original: word)) }
        }
        XCTAssertEqual(memory.storedWordCount, 0)
        for _ in 0..<3 { memory.record(UndoFeedback(original: "l'ecole")) }
        XCTAssertEqual(memory.learnedWords, ["l'ecole"])
    }
    func testForgetClearsCountWithoutAllowingReplay() {
        var memory = UndoLearning()
        let receipts = (0..<3).map { _ in UndoFeedback(original: "ghbdtn") }
        receipts.forEach { memory.record($0) }
        memory.forget("GHBDTN")
        receipts.forEach { memory.record($0) }
        XCTAssertTrue(memory.learnedWords.isEmpty)
        memory.record(UndoFeedback(original: "ghbdtn")); memory.forgetAll()
        XCTAssertEqual(memory.storedWordCount, 0)
    }
    func testStorageBoundRetainsLearnedWords() throws {
        var memory = UndoLearning()
        for _ in 0..<3 { memory.record(UndoFeedback(original: "perche")) }
        for i in 0..<300 { memory.record(UndoFeedback(original: "word" + String(UnicodeScalar(0x4e00 + i)!))) }
        XCTAssertEqual(memory.storedWordCount, UndoLearning.capacity)
        XCTAssertEqual(memory.learnedWords, ["perche"])
        XCTAssertLessThan(try JSONEncoder().encode(memory).count, 65_536)
    }
    func testRestoreSanitizesCorruptEntries() throws {
        let data = #"{"entries":[{"word":"valid","count":3},{"word":"VALID","count":3},{"word":"private sentence","count":3},{"word":"invalid","count":200},{"word":"zero","count":0}]}"#.data(using: .utf8)!
        let restored = try JSONDecoder().decode(UndoLearning.self, from: data)
        XCTAssertEqual(restored.learnedWords, ["valid"])
        XCTAssertEqual(restored.storedWordCount, 1)
    }
    func testProfilesFollowDefaultsOnlyWithoutOverride() {
        let spanish = LanguageSelection([.spanish]), french = LanguageSelection([.french])
        let original = LanguageProfiles(defaults: spanish, overrides: ["mail": spanish])
        let changed = LanguageProfiles(defaults: french, overrides: original.overrides)
        XCTAssertEqual(changed.selection(for: "mail"), spanish)
        XCTAssertEqual(changed.selection(for: "browser"), french)
        XCTAssertEqual(changed.selection(for: nil), french)
    }
    func testProfilesRestoreOnlyKnownAllowedAppsAndLanguages() {
        let raw = ["mail": ["russian", "italian", "korean", "french", "russian"], "browser": ["unknown"], "removed": ["spanish"]]
        let restored = LanguageProfiles.restore(raw, allowed: ["mail", "browser"])
        XCTAssertEqual(restored, ["mail": LanguageSelection([.russian, .italian, .korean])])
    }
}
