import XCTest
@testable import IdkthenCore

final class LiveCandidateGateTests: XCTestCase {
    private func end(_ text: String) -> NSRange { NSRange(location: text.utf16.count, length: 0) }

    func testWholeWordBurstIsNotResurrectedByLaterTyping() {
        var gate = LiveCandidateGate()
        let burst = "GitHubdptjsms "
        XCTAssertNil(gate.completed(previous: "", current: burst, selection: end(burst), whileContinuing: true))
        XCTAssertNil(gate.completed(previous: burst, current: burst + "n", selection: end(burst + "n"), whileContinuing: true))
        XCTAssertNil(gate.completed(previous: burst + "n", current: burst + "ne", selection: end(burst + "ne"), whileContinuing: true))
    }
    func testPastedUnfinishedWordStaysLiteralOnFollowingSpace() {
        var gate = LiveCandidateGate()
        XCTAssertNil(gate.completed(previous: "", current: "dkssud", selection: end("dkssud")))
        XCTAssertNil(gate.completed(previous: "dkssud", current: "dkssud ", selection: end("dkssud ")))
    }
    func testSmallObservedInsertionsRemainEligibleAtSpace() {
        var gate = LiveCandidateGate(); var before = ""
        for piece in ["Git", "Hub", "dpt", "js", "ms"] {
            let next = before + piece
            XCTAssertNil(gate.completed(previous: before, current: next, selection: end(next)))
            before = next
        }
        XCTAssertEqual(gate.completed(previous: before, current: before + " ", selection: end(before + " "))?.text, "GitHubdptjsms")
    }
    func testNextIndependentlyTypedWordWorksAfterIgnoredPaste() {
        var gate = LiveCandidateGate(); var before = "dkssud "
        XCTAssertNil(gate.completed(previous: "", current: before, selection: end(before), whileContinuing: true))
        for ch in "gkdl" {
            let next = before + String(ch)
            XCTAssertNil(gate.completed(previous: before, current: next, selection: end(next), whileContinuing: true))
            before = next
        }
        XCTAssertEqual(gate.completed(previous: before, current: before + " ", selection: end(before + " "), whileContinuing: true)?.text, "gkdl")
    }
    func testFieldResetPreventsOldTextFromBeingChangedAndDoesNotLeakToAnotherField() {
        var gate = LiveCandidateGate()
        gate.reset(text: "dkssud", selection: end("dkssud"))
        XCTAssertNil(gate.completed(previous: "dkssud", current: "dkssud ", selection: end("dkssud ")))
        gate.reset()
        XCTAssertEqual(gate.completed(previous: "dkssud", current: "dkssud ", selection: end("dkssud "))?.text, "dkssud")
    }
    func testChromeNBSPAndContinuedTypingRetainTheirOriginalRanges() {
        var gate = LiveCandidateGate()
        let old = "Hi 🚀 dkssud", next = old + "\u{a0}n"
        let word = gate.completed(previous: old, current: next, selection: end(next), valueChanged: false, acceptsSelectionSignal: true, whileContinuing: true)
        XCTAssertEqual(word?.text, "dkssud")
        XCTAssertEqual(word?.range, NSRange(location: 6, length: 6))
    }
}
