import Foundation
import NaturalLanguage
import IdkthenCore

/// Small language-ID model, used on demand for ambiguous review candidates only.
/// It never authorizes an edit, runs on keystrokes, or retains a document history.
@MainActor enum LocalLanguageContext {
    private static let recognizer = NLLanguageRecognizer()
    struct Hint { let code: String; let name: String }
    static func hint(before: String, after: String, languages: LanguageSelection) -> Hint? {
        let left = String((before.components(separatedBy: "\n\n").last ?? "").suffix(160))
        let right = String((after.components(separatedBy: "\n\n").first ?? "").prefix(80))
        let sample = left + " " + right
        guard sample.unicodeScalars.filter(CharacterSet.letters.contains).count >= 16,
              sample.split(whereSeparator: \.isWhitespace).count >= 3 else { return nil }
        let codes = ["en"] + languages.partners.map { $0.spellLanguage == "pt_BR" ? "pt" : $0.spellLanguage }
        recognizer.reset()
        defer { recognizer.reset() }
        recognizer.processString(sample)
        let scores = recognizer.languageHypotheses(withMaximum: codes.count).sorted { $0.value > $1.value }
        // Do not renormalize an unselected language into a false high-confidence match.
        guard let best = scores.first, codes.contains(best.key.rawValue), best.value >= 0.82,
              best.value - (scores.dropFirst().first?.value ?? 0) >= 0.35 else { return nil }
        let name = best.key == .english ? "English" : languages.partners.first { ($0.spellLanguage == "pt_BR" ? "pt" : $0.spellLanguage) == best.key.rawValue }?.language
        return name.map { Hint(code: best.key.rawValue, name: $0) }
    }
    static func rank(_ review: Review, languages: LanguageSelection, spelling: MacSpelling) -> Review {
        guard languages.count > 2, review.changes.contains(where: { $0.ambiguous && $0.candidates.count > 1 }) else { return review }
        let started = ProcessInfo.processInfo.systemUptime
        var inspected = 0
        let changes = review.changes.map { change -> Change in
            guard change.ambiguous, change.candidates.count > 1, inspected < 8,
                  ProcessInfo.processInfo.systemUptime - started < 0.012,
                  let range = Range(change.range, in: review.original) else { return change }
            inspected += 1
            let before = String(review.original[..<range.lowerBound].suffix(160))
            let after = String(review.original[range.upperBound...].prefix(80))
            guard let preferred = hint(before: before, after: after, languages: languages),
                  let language = change.languages.first(where: { $0.usesAccents && ($0.spellLanguage == "pt_BR" ? "pt" : $0.spellLanguage) == preferred.code }) else { return change }
            let matches = change.candidates.filter { spelling.isWord($0, language: language.spellLanguage) }
            guard matches.count == 1, let candidate = matches.first else { return change }
            let candidates = [candidate] + change.candidates.filter { $0 != candidate }
            return Change(range: change.range, original: change.original, candidates: candidates,
                          reason: "Recent context suggests \(preferred.name). Choose the reading you mean.",
                          ambiguous: change.ambiguous, requiresExplicitChoice: change.requiresExplicitChoice, languages: change.languages)
        }
        return Review(original: review.original, changes: changes, protectedCount: review.protectedCount,
                      notice: review.notice, protectedRanges: review.protectedRanges)
    }
}
