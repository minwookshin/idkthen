import Foundation

/// A conservative automatic-mode guard, not a spelling rule. Some real words and
/// abbreviations fail it; manual review remains available for those cases.
enum LayoutCandidateSafety {
    private static let ukrainianVowels = Set("аеєиіїоуюя")
    static func permitsAutomaticUkrainian(_ candidate: String) -> Bool {
        permits(candidate, vowels: ukrainianVowels)
    }
    static func permitsAutomaticRussian(_ candidate: String) -> Bool { permits(candidate, vowels: Set("аеёиоуыэюя")) }
    private static func permits(_ candidate: String, vowels vowelLetters: Set<Character>) -> Bool {
        var nonVowelRun = 0, vowels = 0
        for letter in candidate.lowercased() {
            if vowelLetters.contains(letter) { vowels += 1; nonVowelRun = 0 }
            else if letter.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
                nonVowelRun += 1
                if nonVowelRun >= 5 { return false }
            } else { nonVowelRun = 0 }
        }
        return vowels > 0
    }
}
