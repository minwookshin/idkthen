import XCTest
@testable import IdkthenCore

final class ContextEfficiencyTests: XCTestCase {
    func testWorkBudgetHasNoQueueAndUsesBoundedMonotonicWindow() {
        var budget = ContextWorkBudget()
        XCTAssertTrue(budget.admit(at: 0))
        XCTAssertFalse(budget.admit(at: 0.1))
        XCTAssertFalse(budget.admit(at: -1))
        XCTAssertFalse(budget.admit(at: .nan))
        for instant in [3.0, 6, 9, 12, 15] { XCTAssertTrue(budget.admit(at: instant)) }
        XCTAssertFalse(budget.admit(at: 18))
        XCTAssertFalse(budget.admit(at: 59.9))
        XCTAssertTrue(budget.admit(at: 60))
        XCTAssertFalse(budget.admit(at: 60.1))
        XCTAssertTrue(budget.admit(at: 63))
    }
    @MainActor func testDeadlineReturnsWhileNoncooperativeWorkerKeepsOnlySlot() async {
        let scheduler = ContextWorkScheduler(budget: ContextWorkBudget(minimumInterval: 0, maximumPerMinute: 1000))
        var release: CheckedContinuation<ContextDecision, Never>?
        let result = await scheduler.evaluate(deadline: .milliseconds(30)) {
            await withCheckedContinuation { release = $0 }
        }
        XCTAssertEqual(result, .unsure)
        XCTAssertTrue(scheduler.isBusy)
        for _ in 0..<100 {
            let blocked = await scheduler.evaluate { XCTFail("Must not queue work"); return .correct }
            XCTAssertEqual(blocked, .unsure)
        }
        XCTAssertEqual(scheduler.startedCount, 1)
        release?.resume(returning: .correct)
        for _ in 0..<20 { if !scheduler.isBusy { break }; await Task.yield() }
        XCTAssertFalse(scheduler.isBusy)
        let next = await scheduler.evaluate { .keep }
        XCTAssertEqual(next, .keep, "A late answer must not affect another request")
    }
    @MainActor func testCancellationReturnsBeforeUnderlyingModelCompletes() async {
        let scheduler = ContextWorkScheduler()
        var release: CheckedContinuation<ContextDecision, Never>?
        let request = Task {
            await scheduler.evaluate(deadline: .seconds(5)) { await withCheckedContinuation { release = $0 } }
        }
        for _ in 0..<100 { if release != nil { break }; await Task.yield() }
        XCTAssertNotNil(release)
        request.cancel()
        let result = await request.value
        XCTAssertEqual(result, .unsure)
        XCTAssertTrue(scheduler.isBusy)
        release?.resume(returning: .correct)
        for _ in 0..<20 { if !scheduler.isBusy { break }; await Task.yield() }
        XCTAssertFalse(scheduler.isBusy)
    }
    @MainActor func testResourcesAndAlreadyCancelledRequestsDoNotStartWork() async {
        let scheduler = ContextWorkScheduler()
        let skipped = await scheduler.evaluate(resourcesAllowed: false) { XCTFail("Resource gate ignored"); return .correct }
        XCTAssertEqual(skipped, .unsure)
        let cancelled = Task { await scheduler.evaluate { XCTFail("Cancelled request started"); return .correct } }
        cancelled.cancel()
        let result = await cancelled.value
        XCTAssertEqual(result, .unsure)
        XCTAssertEqual(scheduler.startedCount, 0)
    }
    @MainActor func testSuccessReleasesSlotButRateBudgetStillApplies() async {
        var now: TimeInterval = 0
        let scheduler = ContextWorkScheduler(now: { now })
        let first = await scheduler.evaluate { .correct }
        XCTAssertEqual(first, .correct)
        XCTAssertFalse(scheduler.isBusy)
        let second = await scheduler.evaluate { XCTFail("Rate limit ignored"); return .correct }
        XCTAssertEqual(second, .unsure)
        now = 3
        let third = await scheduler.evaluate { .keep }
        XCTAssertEqual(third, .keep)
        XCTAssertEqual(scheduler.startedCount, 2)
    }
    @MainActor func testLateResultIsRejectedEvenIfDeadlineTaskCannotRunYet() async {
        func temporarilyBlockingProvider() -> ContextDecision {
            // Simulate a framework synchronously blocking delivery of the deadline task.
            Thread.sleep(forTimeInterval: 0.02)
            return .correct
        }
        let scheduler = ContextWorkScheduler()
        let result = await scheduler.evaluate(deadline: .milliseconds(1)) { temporarilyBlockingProvider() }
        XCTAssertEqual(result, .unsure)
        XCTAssertFalse(scheduler.isBusy)
    }
    private func context(_ prefix: String) -> CorrectionContext {
        let text = prefix + "dkssud "
        return CorrectionContext(text: text, change: Change(range: NSRange(location: prefix.utf16.count, length: 6), original: "dkssud", candidates: ["안녕"], reason: "fixture", ambiguous: false))!
    }
    func testLiteralIntentAcrossSupportedLanguagesIsKeptWithoutModel() {
        for prefix in ["My username is ", "My username is\n", "Mi nombre de usuario es ", "Mi apodo es ", "Mon pseudo est ", "Mon pseudo est\n",
                       "Le nom d’utilisateur est ", "Mein Benutzername ist ", "Bitte nicht ändern ",
                       "Meu nome de usuário é ", "Não altere ", "Il mio nome utente è ", "Non modificare ",
                       "Мой ник ", "Имя пользователя ", "Наш мем ", "Мій нік ", "Не змінюй ", "내 닉네임은 "] {
            XCTAssertTrue(context(prefix).protectsLiteralOrSlang, prefix)
        }
    }
    func testLiteralGuardDoesNotLeakAcrossParagraphsOrMatchWordFragments() {
        for prefix in ["I discussed a meme yesterday.\n\n", "My usernamestats show ", "친구에게 ", "Nous préparons ", "우리 밈\n\n친구에게 "] {
            XCTAssertFalse(context(prefix).protectsLiteralOrSlang, prefix)
        }
    }
    func testNewProtectionsApplyToImmediatePathWithoutBreakingOrdinaryTyping() {
        let engine = ReviewEngine(spelling: TestSpelling())
        for prefix in ["Mon pseudo est ", "Meu nome de usuário é ", "Мой ник "] {
            let text = prefix + "dkssud "
            let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
            if case .immediate = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) { XCTFail(prefix) }
        }
        let text = "친구에게 dkssud "
        let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
        guard case .immediate = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) else { return XCTFail("Ordinary fast path regressed") }
    }
    func testRepeatedLatinChatExpressionsStayIntactInKoreanContext() {
        let engine = ReviewEngine(spelling: TestSpelling())
        for token in ["gogo", "gogogo", "nana", "lulu", "momo", "nono", "gogo!"] {
            let text = "지금 " + token + " "
            let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
            for languages in [LanguageSelection([.korean]), LanguageSelection([.korean, .spanish, .french])] {
                guard case .skip = FastTypingPlan.make(word: word, document: text, engine: engine, languages: languages, keepWords: []) else {
                    XCTFail("Repeated expression must not be guessed: \(token)"); continue
                }
            }
        }
    }
    func testRepeatedLatinGuardPreservesExactKoreanLaughterRecovery() {
        let engine = ReviewEngine(spelling: TestSpelling())
        for (token, expected) in [("gkgk", "하하"), ("gkgkgk", "하하하"), ("dkssud", "안녕")] {
            let text = "친구야 " + token + " "
            let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
            guard case .immediate(let change) = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) else {
                XCTFail("Exact recovery should work: \(token)"); continue
            }
            XCTAssertEqual(change.candidates, [expected])
        }
    }
}
