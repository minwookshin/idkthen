import Foundation

/// Field-local intent protection. An insertion we could not classify as typing
/// must not become an automatic correction merely because another key arrives.
/// AX cannot distinguish an atomic paste from a whole-word notification burst.
public struct LiveCandidateGate: Sendable {
    private var excluded: [String] = []
    private var lastOffered: String?
    public init() {}

    private func key(_ word: LiveWord) -> String { "\(word.range.location):\(word.text)" }
    private mutating func exclude(_ word: LiveWord?) {
        guard let word else { return }
        let value = key(word)
        if !excluded.contains(value) { excluded.append(value) }
        if excluded.count > 16 { excluded.removeFirst(excluded.count - 16) }
    }
    private mutating func protectCurrentWords(_ text: String, selection: NSRange) {
        guard selection.length == 0, let range = Range(selection, in: text) else { return }
        exclude(LiveWord.completed(in: text, selection: selection, whileContinuing: true))
        let prefix = String(text[..<range.lowerBound])
        // Also protect a pasted/unobserved unfinished word when Space arrives later.
        if prefix.last?.isWhitespace == false {
            let completed = prefix + " "
            exclude(LiveWord.completed(in: completed, selection: NSRange(location: completed.utf16.count, length: 0)))
        }
    }
    public mutating func reset(text: String? = nil, selection: NSRange = NSRange(location: 0, length: 0)) {
        excluded.removeAll(keepingCapacity: true); lastOffered = nil
        if let text { protectCurrentWords(text, selection: selection) }
    }
    public mutating func completed(previous: String, current: String, selection: NSRange,
                                   valueChanged: Bool = true, acceptsSelectionSignal: Bool = false,
                                   whileContinuing: Bool = false) -> LiveWord? {
        guard LiveEditPolicy.permits(previous: previous, current: current, selection: selection,
                                     valueChanged: valueChanged, acceptsSelectionSignal: acceptsSelectionSignal) else {
            protectCurrentWords(current, selection: selection)
            return nil
        }
        guard let word = LiveWord.completed(in: current, selection: selection, whileContinuing: whileContinuing) else { return nil }
        let value = key(word)
        guard !excluded.contains(value), lastOffered != value else { return nil }
        lastOffered = value
        return word
    }
}
