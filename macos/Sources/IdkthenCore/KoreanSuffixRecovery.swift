import Foundation

/// A word may contain an intentional English stem and a mistyped Korean ending.
/// Boundaries must be supported by a known stem and an exact two-set ending;
/// this is deliberately not unrestricted substring spell correction.
enum KoreanSuffixRecovery {
    struct Proposal {
        let candidates: [String]
        let ambiguous: Bool
    }
    private static let latinWord = try! NSRegularExpression(pattern: #"^\p{Latin}[\p{Latin}\p{M}]*$"#)
    private static let endings: [(text: String, keys: String)] = [
        "에서부터는", "으로부터는", "에서라도", "에서조차", "에서마저", "에게서는", "한테서는",
        "에서부터", "에서까지", "에서는", "에서도", "에서만", "에게는", "에게도", "에게만",
        "으로부터", "으로는", "으로도", "으로만", "한테는", "한테도", "부터는", "까지는",
        "처럼은", "보다는", "만큼은", "이라도", "이라고", "입니다", "이에요", "이네요",
        "로부터", "로까지", "에다가", "에게서", "한테서", "한테까지", "까지도", "부터도", "처럼도", "처럼만", "보다도",
        "이라서", "라서", "이니까", "니까", "이라면", "라면", "이지만", "지만", "이거나", "거나", "이든지", "이든", "든",
        "에서", "에게", "으로", "한테", "처럼", "보다", "부터", "까지", "마저", "조차",
        "밖에", "하고", "이랑", "라도", "든지", "이나", "로는", "로도", "로만", "에는",
        "에도", "에만", "인데", "예요", "라고", "이고", "이야", "네요", "만큼",
        "은", "는", "이", "가", "을", "를", "의", "에", "로", "와", "과", "랑", "도", "만"
    ].map { ($0, Hangul.toQWERTY($0)) }.sorted { $0.1.count > $1.1.count }

    static func proposal(for word: String, before: String, spelling: any SpellingProvider, kept: Set<String>) -> Proposal? {
        let normalized = word.lowercased().precomposedStringWithCanonicalMapping
        guard word.count <= 96, !kept.contains(normalized) else { return nil }
        let koreanContext = KoreanTypingContext.isRecent(before)
        var candidates: [(text: String, weak: Bool)] = []
        if isLatinWord(word) {
            guard !spelling.isWord(word, language: "en") else { return nil }
            for ending in endings where word.hasSuffix(ending.keys) {
                let stem = String(word.dropLast(ending.keys.count))
                guard recognizes(stem, spelling: spelling, kept: kept) else { continue }
                // Two-key endings such as 에/이/가 are too easy to mistake for a Latin suffix.
                candidates.append((stem + ending.text, ending.keys.count <= 2 && !koreanContext))
            }
        } else if word.unicodeScalars.allSatisfy({ (0xAC00...0xD7A3).contains($0.value) || (0x3130...0x318F).contains($0.value) }),
                  !spelling.isWord(word, language: "ko") {
            // Reverse direction: an English stem typed in Korean layout, then a correctly
            // typed Korean ending. Require visible uncomposed jamo as extra evidence.
            for ending in endings where ending.text.count >= 2 && word.hasSuffix(ending.text) {
                let stem = String(word.dropLast(ending.text.count))
                guard stem.unicodeScalars.contains(where: { (0x3130...0x318F).contains($0.value) }) else { continue }
                let english = Hangul.toQWERTY(stem)
                guard recognizes(english, spelling: spelling, kept: kept) else { continue }
                candidates.append((english + ending.text, false))
            }
        }
        let unique = candidates.reduce(into: [(text: String, weak: Bool)]()) { result, item in
            if !result.contains(where: { $0.text == item.text }) { result.append(item) }
        }
        guard !unique.isEmpty else { return nil }
        return Proposal(candidates: unique.map(\.text), ambiguous: unique.count > 1 || unique.contains(where: \.weak))
    }

    private static func recognizes(_ stem: String, spelling: any SpellingProvider, kept: Set<String>) -> Bool {
        guard stem.count >= 2, isLatinWord(stem) else { return false }
        let normalized = stem.lowercased().precomposedStringWithCanonicalMapping
        if kept.contains(normalized) || RecognizedVocabulary.englishNames.contains(normalized) { return true }
        // NSSpellChecker can accept camelCase identifiers by checking their parts.
        // Only an explicitly recognized term may cross that protection boundary.
        guard stem.count >= 3, stem.range(of: #"[a-z][A-Z]"#, options: .regularExpression) == nil else { return false }
        return spelling.isWord(stem, language: "en")
    }
    private static func isLatinWord(_ word: String) -> Bool {
        latinWord.firstMatch(in: word, range: NSRange(location: 0, length: (word as NSString).length)) != nil
    }
}

enum KoreanTypingContext {
    static func isRecent(_ before: String) -> Bool {
        // A new paragraph is a new language opportunity. Canonical NFD Hangul still
        // provides context, without normalizing or modifying the user's document.
        let line = before.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).last ?? ""
        return String(line.suffix(64)).precomposedStringWithCanonicalMapping.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count >= 2
    }
}
