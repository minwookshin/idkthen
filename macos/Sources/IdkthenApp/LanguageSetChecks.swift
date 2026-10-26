import Foundation
import IdkthenCore

/// Real macOS dictionaries + the production combined planner. No Accessibility
/// edits, saved user text, or model requests. Timings exclude UI and model latency.
@MainActor enum LanguageSetChecks {
    static func run() -> Bool {
        let spelling = MacSpelling(), engine = ReviewEngine(spelling: MacSpelling())
        var checks = 0, failures = 0
        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            checks += 1; if !condition { failures += 1 }
            print("\(condition ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " | " + detail)")
        }
        func plan(_ text: String, _ languages: LanguageSelection, kept: Set<String> = []) -> FastTypingPlan {
            guard let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0), whileContinuing: true) else { return .skip }
            return FastTypingPlan.make(word: word, document: text, engine: engine, languages: languages, keepWords: kept)
        }
        func immediate(_ text: String, _ languages: LanguageSelection, kept: Set<String> = []) -> String {
            guard case let .immediate(change) = plan(text, languages, kept: kept) else { return text }
            return TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after ?? text
        }
        let four = LanguageSelection([.spanish, .french, .korean])
        let clear = [("manana", "mañana"), ("despues", "después"), ("l'ecole", "l'école"), ("l’ecole", "l’école"), ("chromedptj", "chrome에서"), ("GitHubfmf", "GitHub를"), ("dkssud", "안녕"), ("manana-chromedptj", "mañana-chrome에서")]
        for (raw, result) in clear {
            for (prefix, suffix) in [("", " "), ("👩‍💻 (", "), next"), ("cafe\u{301} ", "\t")] {
                let text = prefix + raw + suffix, expected = prefix + result + suffix
                let actual = immediate(text, four)
                check("FOUR_LANGUAGE_CLEAR \(text.debugDescription)", TextIdentity.matches(actual, expected), actual.debugDescription)
                check("STABLE \(expected.debugDescription)", TextIdentity.matches(immediate(expected, four), expected))
                check("KEEP \(raw)", TextIdentity.matches(immediate(text, four, kept: [raw]), text))
            }
        }
        for word in ["reunion", "resume", "deja", "menu", "manana-reunion", "manana-deja"] {
            check("CONFLICT_KEPT \(word)", immediate(word + " ", four) == word + " ")
        }
        let conflict = engine.review("reunion", languages: four)
        check("REUNION_ALTERNATIVES", conflict.changes.count == 1 && Set(conflict.changes[0].candidates) == Set(["reunión", "réunion"]))
        check("REUNION_EXPLICIT", conflict.changes.first?.requiresExplicitChoice == true)
        for word in ["hola", "gracias", "trabajo", "tengo", "perro", "amigo", "mensaje", "bonjour", "merci", "clavier", "travail", "demain"] {
            let text = "안녕 " + word + " "
            check("KEEP_VALID_PARTNER \(word)", immediate(text, four) == text, immediate(text, four))
        }
        let pairs = LanguagePair.allCases
        var configurations = 0
        for bits in 1..<(1 << pairs.count) {
            let enabled = pairs.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element)
            guard enabled.count <= 3 else { continue }
            let languages = LanguageSelection(enabled); configurations += 1
            for word in ["hello", "github", "figma", "chatgpt", "lmao", "rizz", "sus", "https://example.com/manana", "#chromedptj", "manana_id", "--manana", "`manana`", "«manana»", "manana\u{200B}"] {
                let text = word + " "
                check("PROTECTED \(languages.codes) \(word)", immediate(text, languages) == text)
            }
            let text = "manana l'ecole chromedptj reunion ghbdsn"
            let review = engine.review(text, languages: languages)
            check("ORDER_INDEPENDENT \(languages.codes)", review.changes == engine.review(text, languages: LanguageSelection(enabled.reversed())).changes)
            var end = 0
            for change in review.changes {
                check("NONOVERLAP \(languages.codes) \(change.original)", change.range.location >= end && change.languages.allSatisfy(languages.contains))
                end = NSMaxRange(change.range)
            }
        }
        check("ALL_CONFIGURATIONS", configurations == pairs.count + pairs.count * (pairs.count - 1) / 2 + pairs.count * (pairs.count - 1) * (pairs.count - 2) / 6)
        if !spelling.supportsAutomaticLayoutDetection("uk") {
            let withUkrainian = LanguageSelection([.spanish, .ukrainian])
            check("UNRELIABLE_LAYOUT_ISOLATED", immediate("manana ", withUkrainian) == "mañana " && engine.review("manana", languages: withUkrainian).notice != nil)
        }
        let benchmark = ReviewEngine(spelling: spelling)
        var timings: [Double] = []
        for text in ["manana ", "l'ecole ", "chromedptj ", "reunion ", "안녕 gracias "] {
            let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
            for _ in 0..<10 {
                spelling.clearCache()
                let start = ProcessInfo.processInfo.systemUptime
                _ = FastTypingPlan.make(word: word, document: text, engine: benchmark, languages: four, keepWords: [])
                timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
        }
        timings.sort()
        print(String(format: "FOUR_LANGUAGE_PLANNER ms median=%.3f p95=%.3f max=%.3f n=%d; app caches cleared, OS spelling service warm; excludes AX/UI/model", timings[timings.count / 2], timings[Int(Double(timings.count - 1) * 0.95)], timings.last!, timings.count))
        print("LANGUAGE_SET_CHECKS \(failures == 0 ? "PASS" : "FAIL") — \(checks) checks, \(configurations) configurations, \(failures) failures")
        return failures == 0
    }
}
