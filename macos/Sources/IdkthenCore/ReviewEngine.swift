import Foundation

public protocol SpellingProvider {
    func isAvailable(_ language: String) -> Bool
    func isWord(_ word: String, language: String) -> Bool
    func guesses(_ word: String, language: String) -> [String]
    func supportsAutomaticLayoutDetection(_ language: String) -> Bool
}

public extension SpellingProvider {
    func supportsAutomaticLayoutDetection(_ language: String) -> Bool { true }
}

public struct ReviewEngine {
    public let spelling: any SpellingProvider
    public init(spelling: any SpellingProvider) { self.spelling = spelling }
    public static let maxSelectionLength = 4000
    private static let codePattern = try! NSRegularExpression(pattern: "```[\\s\\S]*?(?:```|$)|`[^`\\n]*(?:`|$)")
    private static let chunkPattern = try! NSRegularExpression(pattern: "\\S+")
    private static let latinTokenizer = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}]+(?:['’][\\p{L}\\p{M}]+)*")
    private static let cyrillicTokenizer = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}\\[\\];',.]+")
    // In a passage, surfacing “the → thé” repeatedly makes review noisy. A single-word
    // selection can still request these accents explicitly. This is a heuristic, not grammar detection.
    private static let englishFunctionWords: Set<String> = Set("a an the and or but as at by for from if in into is it its of on onto so than that this to up us was we were will with".split(separator: " ").map(String.init))
    public static func folded(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public func review(_ text: String, pair: LanguagePair, direction: ReviewDirection = .detect, keepWords: Set<String> = [], precedingContext: String = "") -> Review {
        guard (text as NSString).length <= Self.maxSelectionLength else {
            return Review(original: text, changes: [], protectedCount: 0, notice: "Select up to 4,000 characters at a time.")
        }
        let languageAvailable = spelling.isAvailable(pair.spellLanguage)
        let automaticLayoutValidation = pair.usesAccents || spelling.supportsAutomaticLayoutDetection(pair.spellLanguage)
        if !languageAvailable && (pair.usesAccents || direction == .detect) {
            return Review(original: text, changes: [], protectedCount: 0, notice: "The macOS \(pair.language) dictionary is unavailable.\(pair.usesAccents ? " Enable it in Keyboard → Text Input → Spelling." : " Choose a conversion direction to review the layout directly.")")
        }
        let ns = text as NSString
        let kept = Set(keepWords.map { $0.lowercased().precomposedStringWithCanonicalMapping })
        let full = NSRange(location: 0, length: ns.length)
        let codeRanges = Self.codePattern.matches(in: text, range: full).map(\.range)
        let chunks = Self.chunkPattern.matches(in: text, range: full)
        let tokenizer = pair.usesCyrillicLayout ? Self.cyrillicTokenizer : Self.latinTokenizer
        var changes: [Change] = []
        var contextResolved: Set<Int> = []
        var protectedRanges: [NSRange] = []
        for chunk in chunks {
            let value = ns.substring(with: chunk.range)
            if TypingProtection.isLiteral(value) || TypingProtection.isKept(value, words: kept) || codeRanges.contains(where: { NSIntersectionRange($0, chunk.range).length > 0 }) {
                protectedRanges.append(chunk.range); continue
            }
            for match in tokenizer.matches(in: text, range: chunk.range) {
                let word = ns.substring(with: match.range)
                guard word.unicodeScalars.contains(where: CharacterSet.letters.contains) else { continue }
                let letters = word.unicodeScalars.filter(CharacterSet.letters.contains)
                let isAcronym = letters.count > 1 && word == word.uppercased() && word != word.lowercased()
                let camelCase = word.range(of: #"[a-z][A-Z]"#, options: .regularExpression) != nil
                if kept.contains(word.lowercased().precomposedStringWithCanonicalMapping) || isAcronym {
                    protectedRanges.append(match.range); continue
                }
                if direction == .detect && (RecognizedVocabulary.protectedEnglish.contains(word.lowercased().precomposedStringWithCanonicalMapping) || ConversationPolicy.isChatLiteral(word, pair: pair)) {
                    protectedRanges.append(match.range); continue
                }
                if pair == .korean, direction == .detect,
                   let candidate = ConversationPolicy.koreanCandidate(for: word, before: String((precedingContext + ns.substring(to: match.range.location)).suffix(96)), spelling: spelling) {
                    changes.append(Change(range: match.range, original: word, candidates: [candidate],
                                          reason: "Exact two-set recovery; conversational phrasing preserved.", ambiguous: false))
                    continue
                }
                if pair == .korean, direction == .detect,
                   let proposal = KoreanSuffixRecovery.proposal(for: word, before: String((precedingContext + ns.substring(to: match.range.location)).suffix(64)), spelling: spelling, kept: kept) {
                    // Keep the complete original token as the undo/keep identity. The English
                    // stem is copied byte-for-byte into the candidate, including its case.
                    changes.append(Change(range: match.range, original: word, candidates: proposal.candidates,
                                          reason: proposal.ambiguous ? "A short ending or competing boundary needs context. Check the intended language." : "Keep the English stem and recover the exact Korean ending.",
                                          ambiguous: proposal.ambiguous))
                    continue
                }
                if camelCase { protectedRanges.append(match.range); continue }
                if pair.usesAccents {
                    if chunks.count > 1 && Self.englishFunctionWords.contains(word.lowercased()) {
                        protectedRanges.append(match.range); continue
                    }
                    let transcription = pair == .german ? GermanTranscription.candidates(for: word, spelling: spelling) : []
                    let candidates = (AccentCandidates.make(for: word, pair: pair, spelling: spelling) + transcription)
                        .map { matchCase($0, to: word) }
                    var unique = candidates.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    guard !unique.isEmpty else { continue }
                    let before = precedingContext + ns.substring(to: match.range.location)
                    if direction == .detect,
                       let preferred = AccentContext.preferred(for: word, pair: pair, before: before, candidates: unique) {
                        unique = [preferred]
                        contextResolved.insert(match.range.location)
                    }
                    let capitalized = word.first?.isUppercase == true
                    // Sara is also a personal name, even in lowercase chat. Some
                    // macOS dictionaries accept only the accented verb. Do not let
                    // dictionary coverage or a context model choose a person's name.
                    let nameReading = pair == .italian && Self.folded(word) == "sara"
                    let explicit = !transcription.isEmpty || nameReading
                    let resolved = contextResolved.contains(match.range.location)
                    let ambiguous = explicit || capitalized || (!resolved && (spelling.isWord(word, language: "en") || spelling.isWord(word, language: pair.spellLanguage) || unique.count > 1))
                    changes.append(Change(range: match.range, original: word, candidates: unique,
                                          reason: resolved ? "A nearby phrase identifies this accent reading." : (nameReading ? "Sara can be a name. Choose whether you mean the verb sarà." : (!transcription.isEmpty ? "ASCII umlaut spelling can be intentional. Choose this change explicitly." : (capitalized ? "This could be a name. Choose whether to add the accent." : (ambiguous ? "Both readings may work. Choose the meaning you intend." : "Only a missing accent changes.")))), ambiguous: ambiguous, requiresExplicitChoice: explicit))
                } else {
                    let supportedScript = letters.allSatisfy { scalar in
                        let value = scalar.value
                        if (65...90).contains(value) || (97...122).contains(value) { return true }
                        if pair == .korean { return (0xAC00...0xD7A3).contains(value) || (0x3130...0x318F).contains(value) }
                        return (0x0400...0x04FF).contains(value)
                    }
                    if !supportedScript { protectedRanges.append(match.range); continue }
                    let containsPartner = pair.containsPartnerScript(word)
                    if containsPartner && word.range(of: "[A-Za-z]", options: .regularExpression) != nil {
                        protectedRanges.append(match.range); continue
                    }
                    let toEnglish = direction == .toEnglish || (direction == .detect && containsPartner)
                    if direction == .toEnglish && !containsPartner { continue }
                    if direction == .toPartner && containsPartner { continue }
                    var candidate = pair.mappedLayout(word, toEnglish: toEnglish)
                    guard candidate != word else { continue }
                    let target = toEnglish ? "en" : pair.spellLanguage
                    let originalValid = spelling.isWord(word, language: containsPartner ? pair.spellLanguage : "en")
                    var targetValid = spelling.isAvailable(target) && spelling.isWord(candidate, language: target)
                    // Cyrillic punctuation keys can be letters. Prefer the full mapping when
                    // it is a word (lzre. → дякую); otherwise preserve sentence punctuation.
                    if pair.usesCyrillicLayout && !toEnglish && !targetValid {
                        var stem = word, punctuation = ""
                        while let last = stem.last, ".,;".contains(last) {
                            punctuation = String(stem.removeLast()) + punctuation
                            let mapped = pair.mappedLayout(stem, toEnglish: false)
                            if spelling.isAvailable(target), spelling.isWord(mapped, language: target) {
                                candidate = mapped + punctuation; targetValid = true; break
                            }
                        }
                    }
                    if direction == .detect && (!targetValid || (originalValid && !toEnglish) || letters.count < 3) { continue }
                    let cautiousLayout = pair.usesCyrillicLayout && !toEnglish && !pair.permitsAutomaticLayout(candidate)
                    let explicit = !automaticLayoutValidation
                    let ambiguous = originalValid || !targetValid || cautiousLayout || explicit
                    let reason = explicit ? "This Mac cannot confidently validate this language. Choose the layout change explicitly." : (direction != .detect ? "Explicit layout conversion. Check the result before applying." : (cautiousLayout ? "Dictionary acceptance alone is insufficient for this letter sequence. Review it explicitly." : (ambiguous ? "Both layouts are accepted by the dictionary. You choose." : "The alternate layout matches a dictionary word.")))
                    changes.append(Change(range: match.range, original: word, candidates: [candidate], reason: reason, ambiguous: ambiguous, requiresExplicitChoice: explicit))
                }
            }
        }
        let attributed = changes.map { change in
            // A valid spelling is evidence of intent, not an invitation for a
            // context model to choose another meaning. This also covers the
            // single-language-set path (multi-language conflicts already opt out).
            let englishScript = change.original.unicodeScalars.allSatisfy {
                CharacterSet.letters.contains($0) ? $0.isASCII : "'’ʼ-".unicodeScalars.contains($0)
            }
            let accepted = direction == .detect && !contextResolved.contains(change.range.location) && (
                (englishScript && spelling.isAvailable("en") && spelling.isWord(change.original, language: "en"))
                || (pair.canValidateScript(in: change.original) && languageAvailable
                    && automaticLayoutValidation && spelling.isWord(change.original, language: pair.spellLanguage)))
            return Change(range: change.range, original: change.original, candidates: change.candidates,
                          reason: accepted ? "Your spelling is valid. Choose another reading only if you mean it." : change.reason,
                          ambiguous: change.ambiguous || accepted,
                          requiresExplicitChoice: change.requiresExplicitChoice || accepted, languages: [pair])
        }
        return Review(original: text, changes: attributed, protectedCount: protectedRanges.count,
                      notice: !automaticLayoutValidation && direction == .detect ? "\(pair.language) layout recovery needs your review on this Mac. Automatic correction is paused for this pair." : nil, protectedRanges: protectedRanges)
    }
    private func matchCase(_ candidate: String, to original: String) -> String {
        if original == original.uppercased() { return candidate.uppercased() }
        if let first = original.first, first.isUppercase { return candidate.prefix(1).uppercased() + candidate.dropFirst().lowercased() }
        return candidate.lowercased()
    }
}
