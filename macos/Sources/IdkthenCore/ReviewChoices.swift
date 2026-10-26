import Foundation

/// A candidate and its approval are separate, so unticking a word never forgets
/// the alternative the writer chose. Refreshing the same text preserves decisions.
public struct ReviewChoices: Sendable {
    private var candidates: [Int: String] = [:]
    private var approved: Set<Int> = []
    private var originals: [Int: String] = [:]
    private var text: String?
    public init() {}
    public var selected: [Int: String] { candidates.filter { approved.contains($0.key) } }
    public func candidate(for change: Change) -> String { candidates[change.id] ?? change.candidates[0] }
    public func isSelected(_ change: Change) -> Bool { approved.contains(change.id) }
    public mutating func update(_ review: Review, preserving: Bool) {
        let canPreserve = preserving && text.map { TextIdentity.matches($0, review.original) } == true
        let previous = candidates, previousApproved = approved, previousOriginals = originals
        candidates = [:]; originals = [:]; approved = []
        for change in review.changes {
            originals[change.id] = change.original
            if canPreserve, previousOriginals[change.id] == change.original,
               let choice = previous[change.id], change.candidates.contains(choice) {
                candidates[change.id] = choice
                if previousApproved.contains(change.id) { approved.insert(change.id) }
            } else {
                candidates[change.id] = change.candidates[0]
                if !change.ambiguous { approved.insert(change.id) }
            }
        }
        text = review.original
    }
    public mutating func setSelected(_ selected: Bool, for change: Change) {
        if selected { approved.insert(change.id) } else { approved.remove(change.id) }
    }
    public mutating func choose(_ candidate: String, for change: Change) {
        guard change.candidates.contains(candidate) else { return }
        candidates[change.id] = candidate; approved.insert(change.id)
    }
    public mutating func selectSuggested(in review: Review) {
        approved = Set(review.changes.filter { !$0.ambiguous }.map(\.id))
    }
    public mutating func deselectAll() { approved = [] }
}
