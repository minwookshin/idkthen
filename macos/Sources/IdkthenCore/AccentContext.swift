import Foundation

/// Bounded spelling patterns, not a grammar model. These resolve only an existing
/// accent candidate; they cannot change letters, infer agreement, or rewrite text.
enum AccentContext {
    private static let frenchAuxiliary = pattern(#"(?:^|[^\p{L}])(?:je suis|tu es|il est|elle est|on est|nous sommes|vous etes|ils sont|elles sont) $"#)
    private static let frenchArrival = pattern(#"(?:^|[^\p{L}])(?:je suis|tu es|il est|elle est|on est|nous sommes|vous etes|ils sont|elles sont) (?:(?:deja|bien|enfin) ){0,2}$"#)
    private static let frenchLocation = pattern(#"(?:^|[^\p{L}])(?:j'habite|tu habites|il habite|elle habite|on habite|nous habitons|vous habitez|ils habitent|elles habitent) (?:(?:tout|assez|tres) )?$"#)
    private static let portugueseSchedule = pattern(#"(?:^|[^\p{L}])(?:a reuniao|a consulta|a festa|a viagem|a aula|o encontro|o evento|o prazo) (?:e|sera) $"#)

    static func preferred(for word: String, pair: LanguagePair, before: String, candidates: [String]) -> String? {
        guard word == word.lowercased(), word.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        // Never carry a grammatical cue across a sentence, line, or quote boundary.
        let suffix = String(before.suffix(64))
        guard !suffix.contains(where: { "\"“”«»".contains($0) }) else { return nil }
        let clause = suffix.split(omittingEmptySubsequences: false, whereSeparator: { "\n\r.!?;:".contains($0) }).last.map(String.init) ?? ""
        let context = ReviewEngine.folded(clause).replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"[^\S\r\n]+"#, with: " ", options: .regularExpression)
        let proposed: String?
        switch (pair, word) {
        case (.french, "deja") where matches(frenchAuxiliary, context): proposed = "déjà"
        case (.french, "arrive"), (.french, "arrives"), (.french, "arrivee"), (.french, "arrivees"):
            proposed = matches(frenchArrival, context) ? word.replacingOccurrences(of: "arrive", with: "arrivé") : nil
        case (.french, "pres") where matches(frenchLocation, context): proposed = "près"
        case (.portuguese, "amanha") where matches(portugueseSchedule, context): proposed = "amanhã"
        default: proposed = nil
        }
        guard let proposed, candidates.contains(proposed) else { return nil }
        return proposed
    }
    private static func pattern(_ source: String) -> NSRegularExpression { try! NSRegularExpression(pattern: source) }
    private static func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil
    }
}
