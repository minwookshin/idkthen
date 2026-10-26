import XCTest
@testable import IdkthenCore

final class BrowserConfirmationTests: XCTestCase {
    func testChromeSelectionSignalRequiresRealSmallInsertion() {
        let end = NSRange(location: 7, length: 0)
        XCTAssertTrue(LiveEditPolicy.permits(previous: "dkssud", current: "dkssud\u{a0}", selection: end,
            valueChanged: false, acceptsSelectionSignal: true))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "dkssud", current: "dkssud\u{a0}", selection: end,
            valueChanged: false))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "dkssud\u{a0}", current: "dkssud\u{a0}", selection: end,
            valueChanged: false, acceptsSelectionSignal: true))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "", current: "dkssud\u{a0}", selection: end,
            valueChanged: false, acceptsSelectionSignal: true))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "dkssud", current: "dkssud\u{a0}", selection: NSRange(location: 2, length: 0),
            valueChanged: false, acceptsSelectionSignal: true))
    }
    func testRichEditorNonbreakingSpaceCommitsWordAndKeepsItsExactRange() {
        let text = "Before 🚀 glaema\u{a0}"
        let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))
        XCTAssertEqual(word?.text, "glaema")
        XCTAssertEqual(word?.range, NSRange(location: 10, length: 6))
        let continued = text + "n"
        XCTAssertEqual(LiveWord.completed(in: continued, selection: NSRange(location: continued.utf16.count, length: 0), whileContinuing: true)?.text, "glaema")
        XCTAssertTrue(LiveEditPolicy.permits(previous: "glaema", current: "glaema\u{a0}", selection: NSRange(location: 7, length: 0)))
    }
    func testReturnAndOtherSeparatorsStillDoNotCommitWord() {
        for separator in ["\n", "\r", "\u{2028}", "\u{2029}", "\u{202f}"] {
            let text = "glaema" + separator
            XCTAssertNil(LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0)))
        }
    }
    let transaction = TextTransaction(before: "Before 🚀 chromedptj after 👋", range: NSRange(location: 10, length: 10), replacement: "chrome에서")
    let affected = NSRange(location: 16, length: 2)
    func testSafariAdjacentSpaceNormalizationKeepsUndoAvailable() throws {
        let tx = try XCTUnwrap(BrowserEditConfirmation.transaction(transaction, current: "Before 🚀 chrome에서\u{a0}after 👋", affected: affected, caretAfter: nil))
        XCTAssertEqual(tx.after, "Before 🚀 chrome에서\u{a0}after 👋")
        XCTAssertEqual(tx.before, "Before 🚀 chromedptj\u{a0}after 👋")
        XCTAssertEqual(tx.originalSelection, "chromedptj")
    }
    func testRejectsWhitespaceChangeElsewhereAndAnyChangedLetter() {
        for current in ["Before\u{a0}🚀 chrome에서 after 👋", "Before 🚀 chrome에서 other 👋", "Before 🚀 chrome에서\nafter 👋", "Before 🚀 chrome에서after 👋"] {
            XCTAssertNil(BrowserEditConfirmation.transaction(transaction, current: current, affected: affected, caretAfter: nil))
        }
    }
    func testKeepsContinuedTypingWhenSpaceNormalizes() throws {
        let tx = try XCTUnwrap(BrowserEditConfirmation.transaction(transaction, current: "Before 🚀 chrome에서\u{a0}new after 👋", affected: affected, caretAfter: 19))
        XCTAssertEqual(tx.after, "Before 🚀 chrome에서\u{a0}after 👋")
        let recovery = CorrectionRecovery(transaction: tx, caretAfter: 19)
        XCTAssertNotNil(recovery.plan(current: "Before 🚀 chrome에서\u{a0}new after 👋", selection: NSRange(location: 23, length: 0)))
    }
    func testRejectsInsertionWithoutRecordedCaret() {
        XCTAssertNil(BrowserEditConfirmation.transaction(transaction, current: "Before 🚀 chrome에서 new after 👋", affected: affected, caretAfter: nil))
    }
    func testContinuedRichTypingNormalizesPreviousSpaceWithoutLosingUndo() throws {
        let original = TextTransaction(before: "sksms\u{a0}", range: NSRange(location: 0, length: 5), replacement: "나는")
        let current = "나는 next\u{a0}"
        let tx = try XCTUnwrap(BrowserEditConfirmation.transaction(original, current: current, affected: original.replacementRange, caretAfter: 3))
        let plan = try XCTUnwrap(CorrectionRecovery(transaction: tx, caretAfter: 3).plan(current: current, selection: NSRange(location: 8, length: 0)))
        XCTAssertEqual(plan.transaction.after, "sksms next\u{a0}")
        XCTAssertEqual(plan.selection, NSRange(location: 11, length: 0))
        XCTAssertNil(BrowserEditConfirmation.transaction(original, current: "나는 newt\u{a0}", affected: original.replacementRange, caretAfter: nil))
        XCTAssertNil(BrowserEditConfirmation.transaction(original, current: "너는 next\u{a0}", affected: original.replacementRange, caretAfter: 3))
    }
}
