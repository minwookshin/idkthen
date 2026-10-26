import Foundation

/// English is the shared keyboard base. A selection contains one to three partner
/// languages, for two to four languages in total. Order never decides a correction.
public struct LanguageSelection: Equatable, Sendable {
    public static let maximumPartners = 3
    public let partners: [LanguagePair]

    public init(_ partners: [LanguagePair]) {
        var unique: [LanguagePair] = []
        for language in partners where !unique.contains(language) {
            if unique.count < Self.maximumPartners { unique.append(language) }
        }
        if unique.isEmpty { unique = [.spanish] }
        self.partners = LanguagePair.allCases.filter { unique.contains($0) }
    }
    public var count: Int { partners.count + 1 }
    public var singlePair: LanguagePair? { partners.count == 1 ? partners.first : nil }
    public var codes: String { (["EN"] + partners.map(\.code)).joined(separator: " · ") }
    public var names: String { (["English"] + partners.map(\.language)).joined(separator: " + ") }
    public var nativeNames: String { (["English"] + partners.map(\.nativeName)).joined(separator: " + ") }
    public func contains(_ language: LanguagePair) -> Bool { partners.contains(language) }
    public func canToggle(_ language: LanguagePair) -> Bool {
        contains(language) ? partners.count > 1 : partners.count < Self.maximumPartners
    }
    public func toggling(_ language: LanguagePair) -> LanguageSelection? {
        guard canToggle(language) else { return nil }
        return LanguageSelection(contains(language) ? partners.filter { $0 != language } : partners + [language])
    }
    public func sample(ambiguous: Bool = false) -> String {
        partners.map { ambiguous ? $0.ambiguitySample : $0.sample }.joined(separator: "\n")
    }
}

extension LanguagePair {
    /// Some system dictionaries report no error for scripts they do not check.
    /// That is not evidence that a word belongs to that language.
    func canValidateScript(in word: String) -> Bool {
        let letters = word.precomposedStringWithCanonicalMapping.unicodeScalars.filter(CharacterSet.letters.contains)
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { scalar in
            let value = scalar.value
            if self == .korean { return (0xAC00...0xD7A3).contains(value) || (0x3130...0x318F).contains(value) }
            if usesCyrillicLayout { return (0x0400...0x052F).contains(value) }
            return (65...90).contains(value) || (97...122).contains(value) || (0x00C0...0x024F).contains(value) || (0x1E00...0x1EFF).contains(value)
        }
    }
}
