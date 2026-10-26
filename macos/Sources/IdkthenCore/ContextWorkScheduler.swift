import Foundation

public enum ContextDecision: Equatable, Sendable { case correct, keep, unsure }

/// A bounded admission policy; no timers or work run while idle.
public struct ContextWorkBudget: Sendable {
    public let minimumInterval: TimeInterval
    public let maximumPerMinute: Int
    private var starts: [TimeInterval] = []
    public init(minimumInterval: TimeInterval = 3, maximumPerMinute: Int = 6) {
        self.minimumInterval = max(0, minimumInterval)
        self.maximumPerMinute = max(1, maximumPerMinute)
    }
    public mutating func admit(at now: TimeInterval) -> Bool {
        guard now.isFinite else { return false }
        starts.removeAll { now - $0 >= 60 }
        guard starts.count < maximumPerMinute, starts.last.map({ now - $0 >= minimumInterval }) ?? true else { return false }
        starts.append(now); return true
    }
}

/// Resumes the caller at the scheduled deadline even if a suspended provider
/// ignores cancellation. Executor delays may postpone delivery, never validity.
/// The worker retains the sole slot until it really ends: no overlap or queue.
@MainActor public final class ContextWorkScheduler {
    private final class Request {
        let id: UUID
        let expiresAt: ContinuousClock.Instant
        var continuation: CheckedContinuation<ContextDecision, Never>?
        var worker: Task<Void, Never>?
        var deadline: Task<Void, Never>?
        init(id: UUID, deadline: Duration, continuation: CheckedContinuation<ContextDecision, Never>) {
            self.id = id; self.expiresAt = ContinuousClock.now.advanced(by: deadline); self.continuation = continuation
        }
    }
    private var active: Request?
    private var budget: ContextWorkBudget
    private let now: @MainActor () -> TimeInterval
    public private(set) var startedCount = 0
    public var isBusy: Bool { active != nil }
    public init(budget: ContextWorkBudget = ContextWorkBudget(), now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.budget = budget; self.now = now
    }
    public func evaluate(deadline: Duration = .milliseconds(600), resourcesAllowed: Bool = true,
                         operation: @escaping @MainActor () async -> ContextDecision) async -> ContextDecision {
        guard !Task.isCancelled, resourcesAllowed, active == nil else { return .unsure }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, budget.admit(at: now()) else { continuation.resume(returning: .unsure); return }
                let request = Request(id: id, deadline: deadline, continuation: continuation)
                active = request; startedCount += 1
                request.deadline = Task {
                    do { try await Task.sleep(for: deadline) } catch { return }
                    expire(id)
                }
                request.worker = Task {
                    guard !Task.isCancelled else { complete(id, with: .unsure); return }
                    let decision = await operation()
                    complete(id, with: Task.isCancelled ? .unsure : decision)
                }
            }
        } onCancel: {
            Task { @MainActor in self.expire(id) }
        }
    }
    private func expire(_ id: UUID) {
        guard let request = active, request.id == id else { return }
        request.worker?.cancel(); request.deadline?.cancel()
        request.continuation?.resume(returning: .unsure); request.continuation = nil
    }
    private func complete(_ id: UUID, with result: ContextDecision) {
        guard let request = active, request.id == id else { return }
        request.deadline?.cancel()
        request.continuation?.resume(returning: ContinuousClock.now < request.expiresAt ? result : .unsure)
        request.continuation = nil
        active = nil
    }
}
