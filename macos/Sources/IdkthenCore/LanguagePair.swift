import Foundation

public enum LanguagePair: String, CaseIterable, Identifiable, Codable, Sendable {
    case spanish, french, german, portuguese, korean, ukrainian, italian, russian
    public var id: String { rawValue }
    public var code: String {
        switch self { case .spanish: "ES"; case .french: "FR"; case .german: "DE"; case .portuguese: "PT"; case .korean: "KO"; case .ukrainian: "UK"; case .italian: "IT"; case .russian: "RU" }
    }
    public var language: String {
        switch self { case .spanish: "Spanish"; case .french: "French"; case .german: "German"; case .portuguese: "Portuguese"; case .korean: "Korean"; case .ukrainian: "Ukrainian"; case .italian: "Italian"; case .russian: "Russian" }
    }
    public var nativeName: String {
        switch self { case .spanish: "Español"; case .french: "Français"; case .german: "Deutsch"; case .portuguese: "Português"; case .korean: "한국어"; case .ukrainian: "Українська"; case .italian: "Italiano"; case .russian: "Русский" }
    }
    public var spellLanguage: String {
        switch self { case .spanish: "es"; case .french: "fr"; case .german: "de"; case .portuguese: "pt_BR"; case .korean: "ko"; case .ukrainian: "uk"; case .italian: "it"; case .russian: "ru" }
    }
    public var usesAccents: Bool { self != .korean && self != .ukrainian && self != .russian }
    public var modeName: String { usesAccents ? "Accent review" : "Layout recovery" }
    public var detail: String {
        switch self {
        case .spanish: "Add accents while keeping your English keyboard."
        case .french: "Keep QWERTY. Review French accents in mixed text."
        case .german: "Review umlauts and ß without changing your layout."
        case .portuguese: "Review Portuguese accents alongside English."
        case .korean: "Recover Korean typing while keeping English names intact."
        case .ukrainian: "Recover US QWERTY ↔ Ukrainian standard letters."
        case .italian: "Add missing Italian accents while keeping your English keyboard."
        case .russian: "Recover US QWERTY ↔ Russian PC letters. Phonetic layouts are not supported."
        }
    }
    public var sample: String {
        switch self {
        case .spanish: "See you manana — la reunion empieza despues.\nKeep the GitHub link: https://example.com/manana"
        case .french: "The next reunion is deja confirmed.\nPlease review the resume before Friday."
        case .german: "Thanks fur the update — das ist schon.\nWe can discuss it at the next meeting."
        case .portuguese: "The update is ready — a reuniao e amanha.\nPlease keep the GitHub issue in English."
        case .korean: "chromedptj dkssudgktpdy — the design is ready.\nrkatkgkqslek! See you on Friday."
        case .ukrainian: "ghbdsn — the design is ready.\nlzre. for the update!"
        case .italian: "Meet on lunedi — perche la citta is nearby.\nKeep https://example.com/perche unchanged."
        case .russian: "ghbdtn — the design is ready.\ncgfcb,j for the update!"
        }
    }
    public var ambiguitySample: String {
        switch self {
        case .spanish: "si tu papa resume el menu"
        case .french: "Please resume the meeting. Le resume est pret."
        case .german: "Das ist schon. Fur is an English word."
        case .portuguese: "Eu vou por aqui. Ele pode vir."
        case .korean: "hello 안녕하세요 SwiftUI dkssud"
        case .ukrainian: "hello привіт GitHub ghbdsn"
        case .italian: "si e la. Sara sara qui lunedi."
        case .russian: "hello привет GitHub ghbdtn"
        }
    }
}

public enum ReviewDirection: String, CaseIterable, Identifiable, Sendable {
    case detect, toPartner, toEnglish
    public var id: String { rawValue }
}

public struct Change: Identifiable, Equatable, Sendable {
    public let range: NSRange
    public let original: String
    public let candidates: [String]
    public let reason: String
    public let ambiguous: Bool
    public let requiresExplicitChoice: Bool
    public let languages: [LanguagePair]
    public var id: Int { range.location }
    public init(range: NSRange, original: String, candidates: [String], reason: String, ambiguous: Bool, requiresExplicitChoice: Bool = false, languages: [LanguagePair] = []) {
        self.range = range; self.original = original; self.candidates = candidates
        self.reason = reason; self.ambiguous = ambiguous
        self.requiresExplicitChoice = requiresExplicitChoice
        self.languages = LanguagePair.allCases.filter { languages.contains($0) }
    }
}

public struct Review: Sendable {
    public let original: String
    public let changes: [Change]
    public let protectedCount: Int
    public let notice: String?
    public let protectedRanges: [NSRange]
    public init(original: String, changes: [Change], protectedCount: Int, notice: String? = nil, protectedRanges: [NSRange] = []) {
        self.original = original; self.changes = changes; self.protectedCount = protectedCount; self.notice = notice
        self.protectedRanges = protectedRanges
    }
    public func applying(_ choices: [Int: String]) -> String {
        let output = NSMutableString(string: original)
        for change in changes.sorted(by: { $0.range.location > $1.range.location }) {
            guard let replacement = choices[change.id], change.candidates.contains(replacement),
                  NSMaxRange(change.range) <= output.length,
                  TextIdentity.matches(output.substring(with: change.range), change.original),
                  TextTransaction(before: output as String, range: change.range, replacement: replacement).after != nil else { continue }
            output.replaceCharacters(in: change.range, with: replacement)
        }
        return output as String
    }
}

/// Pure precondition shared by Accessibility replacement and tests. Never restore over newer edits.
public struct TextTransaction: Sendable {
    public let before: String
    public let range: NSRange
    public let replacement: String
    public init(before: String, range: NSRange, replacement: String) {
        self.before = before; self.range = range; self.replacement = replacement
    }
    public var after: String? {
        guard range.location >= 0, range.length >= 0, range.location <= (before as NSString).length,
              range.length <= (before as NSString).length - range.location else { return nil }
        let boundaries = Set(before.indices.map { $0.utf16Offset(in: before) } + [(before as NSString).length])
        guard boundaries.contains(range.location), boundaries.contains(range.location + range.length) else { return nil }
        return (before as NSString).replacingCharacters(in: range, with: replacement)
    }
    public var originalSelection: String? {
        guard after != nil else { return nil }
        return (before as NSString).substring(with: range)
    }
    public var replacementRange: NSRange { NSRange(location: range.location, length: (replacement as NSString).length) }
    public func canApply(to current: String) -> Bool { after != nil && TextIdentity.matches(current, before) }
    public func canUndo(current: String) -> Bool { after.map { TextIdentity.matches(current, $0) } ?? false }
}
