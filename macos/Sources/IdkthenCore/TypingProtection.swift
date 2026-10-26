import Foundation

enum TypingProtection {
    private static let domain = try! NSRegularExpression(pattern: #"[\w-]+\.[A-Za-z]{2,63}\b"#, options: .caseInsensitive)
    private static let wrappers = CharacterSet(charactersIn: "()[]!?.,:;\"'‘’“”«»‹›「」『』¿¡")
    static func isKept(_ chunk: String, words: Set<String>) -> Bool {
        let normalized = chunk.lowercased().precomposedStringWithCanonicalMapping
        return words.contains(normalized) || words.contains(normalized.trimmingCharacters(in: wrappers))
    }
    static func isLiteral(_ chunk: String) -> Bool {
        if chunk.contains(where: { "@#\\/_={}`<>".contains($0) }) || chunk.contains("://") || chunk.contains("::") || chunk.hasPrefix("--") || chunk.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        // Hidden separators, directional overrides and soft hyphens make substring
        // boundaries unreliable. Emoji ZWJ sequences remain ordinary surrounding text.
        if chunk.unicodeScalars.contains(where: {
            [0x00AD, 0x200B, 0x200C, 0x200E, 0x200F, 0x2060, 0xFEFF].contains($0.value) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
        }) { return true }
        return domain.firstMatch(in: chunk, range: NSRange(location: 0, length: (chunk as NSString).length)) != nil
    }
}
