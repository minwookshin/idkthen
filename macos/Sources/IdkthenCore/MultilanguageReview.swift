import Foundation

extension ReviewEngine {
    public func review(_ text: String, languages: LanguageSelection, direction: ReviewDirection = .detect,
                       keepWords: Set<String> = [], precedingContext: String = "") -> Review {
        let keepWords = keepWords.union(ConversationPolicy.protectedWords(for: languages.partners))
        if let pair = languages.singlePair {
            return review(text, pair: pair, direction: direction, keepWords: keepWords, precedingContext: precedingContext)
        }
        guard text.utf16.count <= Self.maxSelectionLength else {
            return Review(original: text, changes: [], protectedCount: 0, notice: "Select up to 4,000 characters at a time.")
        }
        guard direction == .detect else {
            return Review(original: text, changes: [], protectedCount: 0, notice: "Choose English and one layout language for a forced conversion.")
        }
        var proposals: [Change] = [], protectedRanges: [NSRange] = [], notices: [String] = []
        for pair in languages.partners {
            // A spelling service which accepts deliberate nonsense cannot compete with
            // healthy languages. Its explicit two-language review remains available.
            if !pair.usesAccents && !spelling.supportsAutomaticLayoutDetection(pair.spellLanguage) {
                notices.append("\(pair.language) needs a separate English + \(pair.language) review on this Mac.")
                continue
            }
            let result = review(text, pair: pair, keepWords: keepWords, precedingContext: precedingContext)
            if let notice = result.notice { notices.append(notice) }
            protectedRanges += result.protectedRanges
            proposals += result.changes
        }
        // Group intersecting spans as well as identical spans. This prevents competing
        // tokenizers (apostrophes / punctuation keys) from producing overlapping edits.
        let ordered = proposals.sorted {
            $0.range.location == $1.range.location ? $0.range.length < $1.range.length : $0.range.location < $1.range.location
        }
        var groups: [[Change]] = []
        for proposal in ordered {
            if let last = groups.last, proposal.range.location < last.map({ NSMaxRange($0.range) }).max()! {
                groups[groups.count - 1].append(proposal)
            } else { groups.append([proposal]) }
        }
        let ns = text as NSString
        let changes = groups.compactMap { group -> Change? in
            let start = group.map(\.range.location).min()!, end = group.map({ NSMaxRange($0.range) }).max()!
            let range = NSRange(location: start, length: end - start)
            let original = ns.substring(with: range)
            var candidates: [String] = []
            for change in group {
                for candidate in change.candidates {
                    let local = NSRange(location: change.range.location - start, length: change.range.length)
                    guard let value = TextTransaction(before: original, range: local, replacement: candidate).after,
                          !TextIdentity.matches(value, original), !candidates.contains(where: { TextIdentity.matches($0, value) }) else { continue }
                    candidates.append(value)
                }
            }
            guard !candidates.isEmpty else { return nil }
            candidates.sort() // Selection order must never pick a different default.
            let sources = LanguagePair.allCases.filter { language in group.contains { $0.languages.contains(language) } }
            let acceptedElsewhere = languages.partners.contains { pair in
                guard (sources.count > 1 || !sources.contains(pair)), pair.canValidateScript(in: original),
                      pair.usesAccents || spelling.supportsAutomaticLayoutDetection(pair.spellLanguage) else { return false }
                return spelling.isAvailable(pair.spellLanguage) && spelling.isWord(original, language: pair.spellLanguage)
            }
            let differingSpans = group.contains { $0.range != range }
            let competing = candidates.count > 1
            let explicit = acceptedElsewhere || differingSpans || competing || group.contains(where: \.requiresExplicitChoice)
            let ambiguous = explicit || group.contains(where: \.ambiguous)
            let reason: String
            if acceptedElsewhere { reason = "This spelling is accepted in another enabled language. Keep it or choose explicitly." }
            else if competing || differingSpans { reason = "Enabled languages suggest different readings. Choose the one you mean." }
            else { reason = group[0].reason }
            return Change(range: range, original: original, candidates: candidates, reason: reason,
                          ambiguous: ambiguous, requiresExplicitChoice: explicit, languages: sources)
        }
        // Count each untouched protected span once, even if every language protected it.
        var kept: [NSRange] = []
        for range in protectedRanges.sorted(by: { $0.location < $1.location }) {
            if changes.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { continue }
            if kept.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
            kept.append(range)
        }
        return Review(original: text, changes: changes, protectedCount: kept.count,
                      notice: notices.isEmpty ? nil : notices.joined(separator: " "), protectedRanges: kept)
    }
}
