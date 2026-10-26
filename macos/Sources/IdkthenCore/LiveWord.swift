import Foundation

/// A bounded, completed chunk before a collapsed caret. No incomplete IME text is reviewed.
public struct LiveWord: Equatable, Sendable {
    private static let codePattern = try! NSRegularExpression(pattern: "```[\\s\\S]*?(?:```|$)|`[^`\\n]*(?:`|$)")
    public let text: String
    public let range: NSRange
    // HTML contenteditable stores a typed trailing Space as NBSP. Newlines and
    // other typographic separators must still not trigger a chat correction.
    private static func commitsWord(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\u{a0}"
    }

    public static func completed(in text: String, selection: NSRange, whileContinuing: Bool = false) -> LiveWord? {
        let ns = text as NSString
        guard ns.length <= 100_000, selection.length == 0, selection.location > 0,
              selection.location <= ns.length,
              TextTransaction(before: text, range: selection, replacement: "").after != nil,
              let caret = Range(selection, in: text)?.lowerBound else { return nil }
        var prefix = text[..<caret]
        // Automatic mode can repair the completed word while the next word is being typed.
        // The entire field/caret is still checked again before the edit is applied.
        if whileContinuing, let last = prefix.last, !last.isWhitespace {
            guard let separator = prefix.lastIndex(where: { $0.isWhitespace }),
                  commitsWord(prefix[separator]),
                  prefix[separator...].count <= 48 else { return nil }
            prefix = prefix[...separator]
        }
        // Space/Tab commits a word. Return can send a chat message, so do not surface there.
        guard let last = prefix.last, commitsWord(last) else { return nil }
        let end = prefix.lastIndex(where: { !$0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        guard end > text.startIndex else { return nil }
        let trailing = text[end..<prefix.endIndex]
        guard trailing.count <= 3, !trailing.contains(where: { $0.isNewline }) else { return nil }
        let start = text[..<end].lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        let range = NSRange(start..<end, in: text)
        guard range.length >= 2, range.length <= 96 else { return nil }
        // Keep code protection when the last chunk is inside an earlier backtick span.
        guard !Self.codePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).contains(where: {
            NSIntersectionRange($0.range, range).length > 0
        }) else { return nil }
        return LiveWord(text: String(text[start..<end]), range: range)
    }

    /// Live mode is deliberately quieter than an explicitly requested review.
    public func suggestion(using engine: ReviewEngine, pair: LanguagePair, keepWords: Set<String>, precedingContext: String = "") -> Change? {
        let review = engine.review(text, pair: pair, keepWords: keepWords, precedingContext: precedingContext)
        return suggestion(from: review, precedingContext: precedingContext)
    }
    public func suggestion(using engine: ReviewEngine, languages: LanguageSelection, keepWords: Set<String>, precedingContext: String = "") -> Change? {
        suggestion(from: engine.review(text, languages: languages, keepWords: keepWords, precedingContext: precedingContext), precedingContext: precedingContext)
    }
    func suggestion(from review: Review, precedingContext: String) -> Change? {
        guard !review.changes.isEmpty, review.changes.count <= 4,
              text.utf16.count >= 3 || review.changes.allSatisfy({ $0.languages == [.korean] }),
              review.changes.allSatisfy({ !$0.ambiguous && !$0.requiresExplicitChoice && $0.candidates.count == 1 }) else { return nil }
        // Every part must pass the same literal guard; joining changes must not hide a
        // quote around one component. Apply a completed compound as one undoable edit.
        let contextText = precedingContext + text
        for change in review.changes {
            let adjusted = Change(range: NSRange(location: precedingContext.utf16.count + change.range.location, length: change.range.length), original: change.original, candidates: change.candidates, reason: change.reason, ambiguous: false)
            guard let context = CorrectionContext(text: contextText, change: adjusted), !context.protectsLiteralOrSlang else { return nil }
        }
        let sorted = review.changes.sorted { $0.range.location < $1.range.location }
        let first = sorted[0], last = sorted[sorted.count - 1]
        let localRange = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        let output = review.applying(Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.candidates[0]) })) as NSString
        let suffixLength = text.utf16.count - NSMaxRange(localRange)
        let replacement = output.substring(with: NSRange(location: localRange.location, length: output.length - localRange.location - suffixLength))
        return Change(range: NSRange(location: range.location + localRange.location, length: localRange.length),
                      original: (text as NSString).substring(with: localRange), candidates: [replacement],
                      reason: sorted.count == 1 ? first.reason : "Each part has one clear correction. Punctuation is preserved.", ambiguous: false, languages: sorted.flatMap(\.languages))
    }
}
