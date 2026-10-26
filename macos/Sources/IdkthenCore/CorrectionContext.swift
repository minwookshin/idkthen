import Foundation

public enum LiveCorrectionMode: String, CaseIterable, Identifiable, Sendable {
    case suggest, automatic
    public var id: String { rawValue }
}

/// Only this bounded context is sent to the on-device model; no document history is accumulated.
public struct CorrectionContext: Sendable, Equatable {
    private static let literalMarkers: NSRegularExpression = {
        let terms = ["literal", "verbatim", "username", "user name", "handle", "meme", "slang", "nickname", "called", "named", "sequence", "spelling", "type exactly", "do not change", "don't change",
                     "nombre de usuario", "mi apodo", "mi nick", "no cambies", "tal cual",
                     "nom d'utilisateur", "nom d’utilisateur", "mon pseudo", "surnom", "ne modifie pas",
                     "benutzername", "spitzname", "zeichenfolge", "nicht andern",
                     "nome de usuario", "meu apelido", "nao altere",
                     "nome utente", "soprannome", "non modificare",
                     "никнейм", "мой ник", "имя пользователя", "мем", "не меняй",
                     "нікнейм", "мій нік", "ім'я користувача", "ім’я користувача", "не змінюй"]
        let normalized = terms.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        let pattern = #"(?<![\p{L}\p{N}_])(?:"# + normalized.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")(?![\p{L}\p{N}_])"#
        return try! NSRegularExpression(pattern: pattern)
    }()
    public let before: String
    public let original: String
    public let candidate: String
    public let after: String
    public let ambiguous: Bool
    public init?(text: String, change: Change) {
        guard change.candidates.count == 1,
              let original = TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).originalSelection,
              TextIdentity.matches(original, change.original),
              let range = Range(change.range, in: text) else { return nil }
        before = String(text[..<range.lowerBound].suffix(240))
        after = String(text[range.upperBound...].prefix(80))
        self.original = change.original; candidate = change.candidates[0]
        ambiguous = change.ambiguous
    }
    /// Deterministic guards remain in force even when a generative model gets intent wrong.
    public var protectsLiteralOrSlang: Bool {
        let scalars = original.unicodeScalars
        if !scalars.isEmpty && scalars.allSatisfy({ (0x3130...0x318F).contains($0.value) || (0x1100...0x11FF).contains($0.value) }) { return true }
        if original.count >= 3, Set(original.lowercased()).count == 1 { return true }
        // Short repeated Latin syllables often are deliberate chat expressions or
        // names (gogo, nana, lulu). Korean context alone cannot establish intent.
        // Require a Latin vowel so actual two-set laughter such as gkgk still works.
        let letters = Array(original.lowercased().utf8)
        if (4...12).contains(letters.count), letters.count.isMultiple(of: 2),
           letters.allSatisfy({ (97...122).contains($0) }),
           ![97, 101, 105, 111, 117, 121].contains(letters[0]),
           [97, 101, 105, 111, 117, 121].contains(letters[1]),
           letters.indices.allSatisfy({ letters[$0] == letters[$0 % 2] }) { return true }
        if before.last.map({ "\"'‘“„‚«‹「『`#@".contains($0) }) == true || after.first.map({ "\"'’”»›」』`".contains($0) }) == true { return true }
        // A single line break may introduce the literal itself; only a blank
        // paragraph break discards the nearby intent marker.
        let recent = String((before.components(separatedBy: "\n\n").last ?? "").suffix(100))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if Self.literalMarkers.firstMatch(in: recent, range: NSRange(location: 0, length: recent.utf16.count)) != nil { return true }
        return ["밈", "유행어", "신조어", "줄임말", "닉네임", "사용자명", "문자열", "그대로", "바꾸지", "철자", "이름은", "이름이"].contains(where: recent.contains)
    }
    public var modelPayload: String {
        let value = ["before": before, "original": original, "candidate": candidate, "after": after, "originalMayBeValid": ambiguous ? "true" : "false"]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }
}
