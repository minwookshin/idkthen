import XCTest
@testable import IdkthenCore

final class UsabilityTests: XCTestCase {
    func testUndoPreservesContinuedTypingAndCaret() {
        let correction = TextTransaction(before: "dkssud ", range: NSRange(location: 0, length: 6), replacement: "안녕")
        let anchor = CorrectionRecovery(transaction: correction, caretAfter: 3)
        let plan = anchor.plan(current: "안녕 next word 👩‍💻", selection: NSRange(location: 18, length: 0))
        XCTAssertEqual(plan?.transaction.after, "dkssud next word 👩‍💻")
        XCTAssertEqual(plan?.selection, NSRange(location: 22, length: 0))
        XCTAssertTrue(anchor.recognizesOriginal(in: "dkssud next word 👩‍💻"))
    }
    func testUndoInMiddleKeepsOriginalSuffixAndSelectedNewText() {
        let before = "Hi chromedptj | END"
        let correction = TextTransaction(before: before, range: NSRange(location: 3, length: 10), replacement: "chrome에서")
        let anchor = CorrectionRecovery(transaction: correction, caretAfter: 12)
        let current = "Hi chrome에서 next | END"
        let plan = anchor.plan(current: current, selection: NSRange(location: 12, length: 4))
        XCTAssertEqual(plan?.transaction.after, "Hi chromedptj next | END")
        XCTAssertEqual(plan?.selection, NSRange(location: 14, length: 4))
        XCTAssertNil(anchor.plan(current: "Hi chrome에서 next | changed", selection: NSRange(location: 12, length: 0)))
        XCTAssertNil(anchor.plan(current: "Bye chrome에서 next | END", selection: NSRange(location: 13, length: 0)))
    }
    func testUndoRejectsOtherEditsAndSplitCharacters() {
        let correction = TextTransaction(before: "👩‍💻 dkssud ", range: NSRange(location: 6, length: 6), replacement: "안녕")
        let anchor = CorrectionRecovery(transaction: correction, caretAfter: 9)
        XCTAssertNil(anchor.plan(current: "👩‍💻 다른 next", selection: NSRange(location: 15, length: 0)))
        XCTAssertNil(anchor.plan(current: "👩‍💻 안녕 next", selection: NSRange(location: 1, length: 0)))
        XCTAssertNil(anchor.plan(current: "👩‍💻 안녕 next", selection: NSRange(location: 7, length: 1)))
        XCTAssertNotNil(anchor.plan(current: "👩‍💻 안녕 next", selection: NSRange(location: 13, length: 0)))
        XCTAssertFalse(anchor.recognizesOriginal(in: "OTHER dkssud "))
        let nfd = TextTransaction(before: "cafe\u{301} dkssud ", range: NSRange(location: 6, length: 6), replacement: "안녕")
        XCTAssertNil(CorrectionRecovery(transaction: nfd, caretAfter: 9).plan(current: "café 안녕 next", selection: NSRange(location: 12, length: 0)))
    }
    func testRecoveryLengthChangesAcrossLanguages() {
        for (original, replacement) in [("manana", "mañana"), ("l'ecole", "l'école"), ("strasse", "straße"), ("amanha", "amanhã"), ("perche", "perché"), ("ghbdtn", "привет"), ("ghbdsn", "привіт"), ("chromedptj", "chrome에서")] {
            let correction = TextTransaction(before: original + " ", range: NSRange(location: 0, length: original.utf16.count), replacement: replacement)
            let after = replacement + " ", current = after + "more"
            let plan = CorrectionRecovery(transaction: correction, caretAfter: after.utf16.count)
                .plan(current: current, selection: NSRange(location: current.utf16.count, length: 0))
            XCTAssertEqual(plan?.transaction.after, original + " more", original)
            XCTAssertEqual(plan?.selection.location, (original + " more").utf16.count, original)
        }
    }
    func testPauseExpiresAndIsScopedToApp() {
        var policy = TypingInterventions()
        policy.pause("one", now: 10)
        XCTAssertTrue(policy.paused("one", now: 609.99))
        XCTAssertFalse(policy.paused("two", now: 20))
        XCTAssertFalse(policy.paused("one", now: 610))
        policy.pause("one", now: 700); policy.resume("one")
        XCTAssertFalse(policy.paused("one", now: 701))
    }
    func testIgnoredSuggestionsAreTemporaryAndFieldScoped() {
        var policy = TypingInterventions()
        policy.ignore("resume", now: 1)
        XCTAssertFalse(policy.suppressed("resume", now: 2))
        policy.ignore("resume", now: 2)
        XCTAssertTrue(policy.suppressed("Resume", now: 3))
        XCTAssertFalse(policy.suppressed("reunion", now: 3))
        XCTAssertFalse(policy.suppressed("resume", now: 302))
        policy.ignore("resume", now: 4); policy.resetField()
        XCTAssertFalse(policy.suppressed("resume", now: 5))
    }
    func testFieldProtectionFailsClosed() {
        func allowed(_ role: String?, subrole: String? = nil, marked: Bool = false, completion: Bool = false, content: String? = nil) -> Bool {
            LiveFieldPolicy.allows(role: role, subrole: subrole, protected: false, editable: true, hasMarkedText: marked, hasCompletion: completion, contentRole: content)
        }
        XCTAssertTrue(allowed("AXTextArea"))
        for role in [nil, "AXTextField", "AXComboBox", "AXSearchField", "AXUnknown"] { XCTAssertFalse(allowed(role)) }
        XCTAssertFalse(allowed("AXTextArea", subrole: "AXSecureTextField"))
        XCTAssertFalse(allowed("AXTextArea", marked: true))
        XCTAssertFalse(allowed("AXTextArea", completion: true))
        XCTAssertFalse(allowed("AXTextArea", content: "code"))
        XCTAssertFalse(LiveFieldPolicy.allows(role: "AXTextArea", subrole: nil, protected: true, editable: true, hasMarkedText: false, hasCompletion: false))
        XCTAssertFalse(LiveFieldPolicy.allows(role: "AXTextArea", subrole: nil, protected: false, editable: false, hasMarkedText: false, hasCompletion: false))
    }
    func testBulkInputAndDeletionCannotTriggerLiveCorrection() {
        XCTAssertTrue(LiveEditPolicy.permits(previous: "dkssud", current: "dkssud ", selection: NSRange(location: 7, length: 0)))
        XCTAssertTrue(LiveEditPolicy.permits(previous: "dkssud", current: "dkssud ne", selection: NSRange(location: 9, length: 0)))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "", current: "dkssud ", selection: NSRange(location: 7, length: 0)))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "dkssud ", current: "dkssud", selection: NSRange(location: 6, length: 0)))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "dkssud", current: "dkssud\n", selection: NSRange(location: 7, length: 0)))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "abcd", current: "efgh ", selection: NSRange(location: 5, length: 0)))
        XCTAssertFalse(LiveEditPolicy.permits(previous: "dkssud", current: "dkssud x y", selection: NSRange(location: 10, length: 0)))
    }
}
