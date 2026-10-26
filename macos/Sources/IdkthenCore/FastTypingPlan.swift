import Foundation

public enum FastTypingPlan {
    case skip
    case immediate(Change)
    case context(Change)

    public static func make(word: LiveWord, document: String, engine: ReviewEngine, languages: LanguageSelection, keepWords: Set<String>) -> FastTypingPlan {
        let keepWords = keepWords.union(ConversationPolicy.protectedWords(for: languages.partners))
        if let pair = languages.singlePair { return make(word: word, document: document, engine: engine, pair: pair, keepWords: keepWords) }
        guard let range = Range(word.range, in: document), TextIdentity.matches(String(document[range]), word.text) else { return .skip }
        let before = String(document[..<range.lowerBound].suffix(64))
        let review = engine.review(word.text, languages: languages, keepWords: keepWords, precedingContext: before)
        if let change = word.suggestion(from: review, precedingContext: before),
           let context = CorrectionContext(text: document, change: change), !context.protectsLiteralOrSlang {
            return .immediate(change)
        }
        if word.text.utf16.count >= 3, review.changes.count == 1, let local = review.changes.first, local.ambiguous, !local.requiresExplicitChoice,
           local.candidates.count == 1, local.original.first?.isUppercase != true {
            if local.languages.contains(where: { $0.usesCyrillicLayout && $0.containsPartnerScript(local.candidates[0]) && !$0.permitsAutomaticLayout(local.candidates[0]) }) { return .skip }
            let change = adjusted(local, by: word.range.location, ambiguous: true)
            if let context = CorrectionContext(text: document, change: change), !context.protectsLiteralOrSlang { return .context(change) }
        }
        return .skip
    }

    public static func make(word: LiveWord, document: String, engine: ReviewEngine, pair: LanguagePair, keepWords: Set<String>) -> FastTypingPlan {
        guard let wordRange = Range(word.range, in: document), TextIdentity.matches(String(document[wordRange]), word.text) else { return .skip }
        let precedingContext = String(document[..<wordRange.lowerBound].suffix(64))
        let review = engine.review(word.text, pair: pair, keepWords: keepWords, precedingContext: precedingContext)
        if let change = word.suggestion(from: review, precedingContext: precedingContext),
           let context = CorrectionContext(text: document, change: change), !context.protectsLiteralOrSlang {
            return .immediate(change)
        }
        // A single ambiguous reading may be considered asynchronously. No speculative rewrite.
        if word.text.utf16.count >= 3, review.changes.count == 1, let local = review.changes.first, local.ambiguous, !local.requiresExplicitChoice,
           local.candidates.count == 1, local.original.first?.isUppercase != true {
            if pair.usesCyrillicLayout, pair.containsPartnerScript(local.candidates[0]), !pair.permitsAutomaticLayout(local.candidates[0]) { return .skip }
            let change = adjusted(local, by: word.range.location, ambiguous: true)
            if let context = CorrectionContext(text: document, change: change), !context.protectsLiteralOrSlang { return .context(change) }
        }
        return .skip
    }
    private static func adjusted(_ change: Change, by offset: Int, ambiguous: Bool) -> Change {
        Change(range: NSRange(location: offset + change.range.location, length: change.range.length), original: change.original,
               candidates: change.candidates, reason: ambiguous ? change.reason : "Exact two-set recovery in recent Korean context; original phrasing preserved.", ambiguous: ambiguous, requiresExplicitChoice: change.requiresExplicitChoice, languages: change.languages)
    }
}
