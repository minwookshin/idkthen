import Foundation

enum AccentCandidates {
    static func make(for word: String, pair: LanguagePair, spelling: any SpellingProvider) -> [String] {
        var candidates = spelling.guesses(word, language: pair.spellLanguage) + AccentHints.candidates(for: word, pair: pair)
        // Some spelling services reject modifier-letter or curly apostrophes. Look up
        // the straight form, then restore each original apostrophe without changing it.
        let apostrophes: Set<Character> = ["'", "’", "ʼ"]
        let originals = word.filter { apostrophes.contains($0) }
        if !originals.isEmpty {
            let lookup = String(word.map { apostrophes.contains($0) ? "'" : $0 })
            for guess in spelling.guesses(lookup, language: pair.spellLanguage) {
                guard guess.filter({ apostrophes.contains($0) }).count == originals.count else { continue }
                var marks = originals.makeIterator()
                candidates.append(String(guess.map { apostrophes.contains($0) ? marks.next()! : $0 }))
            }
        }
        return candidates.filter { AccentPolicy.permits($0, for: word) }
    }
}
