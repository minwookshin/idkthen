import Foundation

/// Standard Russian PC letter positions against US QWERTY. Not phonetic transliteration.
/// Backtick stays protected as code; numbers and general symbol remapping are not supported.
public enum RussianLayout {
    private static let forward: [Character: Character] = Dictionary(uniqueKeysWithValues:
        zip(Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>~"), Array("йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ")))
    private static let backward = Dictionary(uniqueKeysWithValues: forward.map { ($0.value, $0.key) })
    public static func convert(_ text: String, toEnglish: Bool) -> String {
        let map = toEnglish ? backward : forward
        return text.map { letter in
            if let exact = map[letter] { return String(exact) }
            let lower = String(letter).lowercased()
            if lower.count == 1, let mapped = map[Character(lower)] { return String(mapped).uppercased() }
            return String(letter)
        }.joined()
    }
}

extension LanguagePair {
    var usesCyrillicLayout: Bool { self == .ukrainian || self == .russian }
    func containsPartnerScript(_ word: String) -> Bool {
        self == .korean ? Hangul.containsHangul(word) : UkrainianLayout.containsUkrainian(word)
    }
    func mappedLayout(_ word: String, toEnglish: Bool) -> String {
        if self == .korean { return toEnglish ? Hangul.toQWERTY(word) : Hangul.fromQWERTY(word) }
        if self == .russian { return RussianLayout.convert(word, toEnglish: toEnglish) }
        return UkrainianLayout.convert(word, toEnglish: toEnglish)
    }
    func permitsAutomaticLayout(_ candidate: String) -> Bool {
        if self == .ukrainian { return LayoutCandidateSafety.permitsAutomaticUkrainian(candidate) }
        if self == .russian { return LayoutCandidateSafety.permitsAutomaticRussian(candidate) }
        return true
    }
}
