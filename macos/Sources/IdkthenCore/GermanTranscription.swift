import Foundation

/// ASCII umlaut transcriptions can be intentional, especially in names. Offer only
/// explicitly reviewed candidates, never automatic or model-approved replacements.
enum GermanTranscription {
    static func candidates(for word: String, spelling: any SpellingProvider) -> [String] {
        guard word.count >= 3, word.count <= 48,
              !spelling.isWord(word, language: "de"), !spelling.isWord(word, language: "en") else { return [] }
        let chars = Array(word)
        var variants = [""], index = 0, positions = 0, hasUmlaut = false
        while index < chars.count {
            if index + 1 < chars.count {
                let pair = String(chars[index...index + 1])
                let replacements = ["ae": "ä", "oe": "ö", "ue": "ü", "Ae": "Ä", "Oe": "Ö", "Ue": "Ü", "ss": "ß"]
                if let replacement = replacements[pair] {
                    positions += 1
                    guard positions <= 4 else { return [] }
                    hasUmlaut = hasUmlaut || pair != "ss"
                    variants = variants.flatMap { [$0 + pair, $0 + replacement] }
                    index += 2; continue
                }
            }
            variants = variants.map { $0 + String(chars[index]) }; index += 1
        }
        guard hasUmlaut else { return [] }
        return variants.filter { $0 != word && spelling.isWord($0, language: "de") }
    }
}
