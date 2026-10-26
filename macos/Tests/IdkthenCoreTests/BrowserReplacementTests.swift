import XCTest
@testable import IdkthenCore

final class BrowserReplacementTests: XCTestCase {
    func testManualChangeDoesNotRewriteUnchangedStyledSuffix() throws {
        let before = "Before 🚀 chromedptj after 👋"
        let range = (before as NSString).range(of: "chromedptj after 👋")
        let tx = TextTransaction(before: before, range: range, replacement: "chrome에서 after 👋")
        let plan = try XCTUnwrap(BrowserReplacementPlan(transaction: tx, caret: nil))
        XCTAssertEqual((before as NSString).substring(with: plan.range), "dptj")
        XCTAssertEqual(plan.text, "에서")
        XCTAssertEqual(TextTransaction(before: before, range: plan.range, replacement: plan.text).after, tx.after)
    }
    func testIncludesSeparatorAndContinuedTextWithoutChangingResult() throws {
        let before = "prefix chromedptj ne suffix"
        let change = TextTransaction(before: before, range: NSRange(location: 7, length: 10), replacement: "chrome에서")
        let plan = try XCTUnwrap(BrowserReplacementPlan(transaction: change, caret: 20))
        XCTAssertEqual(plan.text, "chrome에서 ne")
        XCTAssertEqual(TextTransaction(before: before, range: plan.range, replacement: plan.text).after, change.after)
        XCTAssertEqual(plan.caretAfter, 18)
    }
    func testPreservesUTF16EmojiAndCombiningMarks() throws {
        let before = "🧑🏽‍💻 café dkssud 🌱 end"
        let range = (before as NSString).range(of: "dkssud")
        let caret = NSMaxRange(range) + 1
        let tx = TextTransaction(before: before, range: range, replacement: "안녕")
        let plan = try XCTUnwrap(BrowserReplacementPlan(transaction: tx, caret: caret))
        XCTAssertEqual(TextTransaction(before: before, range: plan.range, replacement: plan.text).after, "🧑🏽‍💻 café 안녕 🌱 end")
    }
    func testRejectsMovedCaretAndInvalidCharacterBoundary() {
        let tx = TextTransaction(before: "dkssud 😀", range: NSRange(location: 0, length: 6), replacement: "안녕")
        XCTAssertNil(BrowserReplacementPlan(transaction: tx, caret: 4))
        XCTAssertNil(BrowserReplacementPlan(transaction: tx, caret: 8))
        XCTAssertNil(BrowserReplacementPlan(transaction: tx, caret: 50))
    }
    func testRejectsLongDistanceUndoWithoutTouchingDocument() {
        let tx = TextTransaction(before: "안녕 " + String(repeating: "x", count: 40), range: NSRange(location: 0, length: 2), replacement: "dkssud")
        XCTAssertNil(BrowserReplacementPlan(transaction: tx, caret: 43))
    }
    func testUnicodeTransportNeverSplitsLongOrMultilineWrite() throws {
        for replacement in [String(repeating: "x", count: 21), "안녕\nhello", "hello\rworld", ""] {
            let tx = TextTransaction(before: "dkssud", range: NSRange(location: 0, length: 6), replacement: replacement)
            XCTAssertFalse(try XCTUnwrap(BrowserReplacementPlan(transaction: tx, caret: nil)).permitsUnicodeInsertion)
        }
    }
    func testShortWordUndoRetainsFollowingInput() throws {
        let tx = TextTransaction(before: "chrome에서 next", range: NSRange(location: 0, length: 8), replacement: "chromedptj")
        let plan = try XCTUnwrap(BrowserReplacementPlan(transaction: tx, caret: 13))
        XCTAssertEqual(plan.text, "chromedptj next")
        XCTAssertEqual(plan.caretAfter, 15)
        XCTAssertTrue(plan.permitsUnicodeInsertion)
    }
    func testConfirmationRejectsDifferentEditButAcceptsContinuedTyping() {
        let tx = TextTransaction(before: "dkssud ", range: NSRange(location: 0, length: 6), replacement: "안녕")
        let recovery = CorrectionRecovery(transaction: tx, caretAfter: 3)
        XCTAssertTrue(recovery.canRecover(current: "안녕 next", selection: NSRange(location: 7, length: 0)))
        XCTAssertFalse(recovery.canRecover(current: "안녕next ", selection: NSRange(location: 6, length: 0)))
        XCTAssertFalse(recovery.canRecover(current: "wrong 안녕 ", selection: NSRange(location: 9, length: 0)))
    }
}
