import Foundation

/// Presentation policy, not a grammar classifier. Common valid readings are
/// quiet in passages; an explicit single-word review still exposes alternatives.
public enum ReviewVisibility {
    private static let ordinaryReadings: [LanguagePair: Set<String>] = [
        .spanish: words("si tu el mi te mas que quien como donde cuando cuanto papa ano anos solo esta estas este estas"),
        .french: words("a la ou du des notre votre sur mur matin tache cote peche jeune"),
        .german: words("schon fur wurde mochte konnte musste"),
        .portuguese: words("a as e por pode nos tem esta estas"),
        .italian: words("si e la li da ne se sara")
    ]
    private static func words(_ value: String) -> Set<String> { Set(value.split(separator: " ").map(String.init)) }
    public static func isQuietAlternative(_ change: Change, in text: String, spelling: any SpellingProvider) -> Bool {
        guard change.ambiguous, !change.languages.isEmpty, change.languages.allSatisfy(\.usesAccents),
              text.split(whereSeparator: \.isWhitespace).count > 1 else { return false }
        let word = change.original.lowercased().precomposedStringWithCanonicalMapping
        return change.languages.allSatisfy { language in
            ordinaryReadings[language]?.contains(word) == true
                || (ReviewEngine.folded(word) != word && spelling.isWord(word, language: language.spellLanguage))
        }
    }
    public static func focused(_ review: Review, spelling: any SpellingProvider, preserving ids: Set<Int> = []) -> Review {
        Review(original: review.original,
               changes: review.changes.filter { ids.contains($0.id) || !isQuietAlternative($0, in: review.original, spelling: spelling) },
               protectedCount: review.protectedCount, notice: review.notice, protectedRanges: review.protectedRanges)
    }
}
