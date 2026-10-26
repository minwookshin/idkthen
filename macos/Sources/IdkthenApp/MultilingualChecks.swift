import Foundation
import IdkthenCore

/// A repeatable local corpus using the installed spelling services and production live
/// planner. It performs no Accessibility edits and cannot measure screen-level latency.
@MainActor enum MultilingualChecks {
    static func run() -> Bool {
        let spelling = MacSpelling(), engine = ReviewEngine(spelling: MacSpelling())
        var checks = 0, failures = 0
        func check(_ label: String, _ condition: Bool, detail: String = "") {
            checks += 1
            if !condition { failures += 1 }
            print("\(condition ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " | " + detail)")
        }
        func plan(_ text: String, pair: LanguagePair, kept: Set<String> = []) -> FastTypingPlan {
            guard let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0), whileContinuing: true) else { return .skip }
            return FastTypingPlan.make(word: word, document: text, engine: engine, pair: pair, keepWords: kept)
        }
        func immediate(_ text: String, pair: LanguagePair, kept: Set<String> = []) -> String {
            guard case let .immediate(change) = plan(text, pair: pair, kept: kept) else { return text }
            return TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after ?? text
        }
        let clearCases: [(LanguagePair, String, String)] = [
            (.spanish, "manana-despues", "mañana-después"),
            (.portuguese, "reuniao-acao", "reunião-ação"),
            (.french, "l'ecole", "l'école"), (.french, "l’ecole", "l’école"), (.french, "lʼecole", "lʼécole"),
            (.ukrainian, "ghbdsn", "привіт"), (.korean, "chromedptj", "chrome에서")
        ]
        for (pair, original, target) in clearCases where pair.usesAccents || spelling.supportsAutomaticLayoutDetection(pair.spellLanguage) {
            for (prefix, suffix) in [("", " "), ("👩‍💻 (", "), "), ("cafe\u{301} — ", "! next"), ("", "\t"), ("", "  ")] {
                let source = prefix + original + suffix
                let expected = prefix + target + suffix
                let actual = immediate(source, pair: pair)
                check("EXACT \(pair.code) \(source.debugDescription)", TextIdentity.matches(actual, expected), detail: actual.debugDescription)
                check("STABLE \(pair.code) \(expected.debugDescription)", TextIdentity.matches(immediate(expected, pair: pair), expected))
            }
        }
        for ending in ["에서라도", "에서조차", "에서마저", "에서부터는", "으로부터는", "에게서는", "한테서는", "로부터", "로까지", "에다가", "에게서", "한테서", "한테까지", "까지도", "부터도", "처럼도", "처럼만", "보다도", "이라서", "라서", "이니까", "니까", "이라면", "라면", "이지만", "지만", "이거나", "거나", "이든지", "이든", "든"] {
            let source = "chrome" + Hangul.toQWERTY(ending) + " "
            check("KOREAN_ENDING \(ending)", immediate(source, pair: .korean) == "chrome" + ending + " ", detail: immediate(source, pair: .korean))
        }
        for (source, target) in [("fuer", "für"), ("ueber", "über"), ("schoen", "schön"), ("zurueck", "zurück"), ("groesser", "größer"), ("Haeuser", "Häuser")] {
            let changes = engine.review(source, pair: .german).changes
            check("GERMAN_EXPLICIT \(source)", changes.contains { $0.candidates.contains(target) && $0.ambiguous && $0.requiresExplicitChoice })
            if case .skip = plan(source + " ", pair: .german) { check("GERMAN_NO_MODEL_AUTO \(source)", true) }
            else { check("GERMAN_NO_MODEL_AUTO \(source)", false) }
        }
        let ambiguous: [(LanguagePair, [String])] = [
            (.spanish, ["si", "tu", "como", "papa", "manana-si"]),
            (.french, ["resume", "l'ecole-resume", "Deja"]),
            (.german, ["schon", "fur", "Mueller", "Goethe", "Feuer", "Treue", "neue", "queue", "aerobic"]),
            (.portuguese, ["por", "pode", "amanha", "reuniao-amanha"])
        ]
        for (pair, words) in ambiguous {
            for word in words { check("KEEP_AMBIGUOUS \(pair.code) \(word)", immediate(word + " ", pair: pair) == word + " ") }
        }
        if !spelling.supportsAutomaticLayoutDetection("uk") {
            for source in ["ghbdsn", "lzre.", "qwertasdf"] {
                let review = engine.review(source, pair: .ukrainian)
                check("UK_REVIEW_REQUIRED \(source)", review.notice != nil && review.changes.allSatisfy { $0.ambiguous && $0.requiresExplicitChoice })
                if case .skip = plan(source + " ", pair: .ukrainian) { check("UK_AUTO_BLOCKED \(source)", true) }
                else { check("UK_AUTO_BLOCKED \(source)", false) }
            }
            print("UK_AUTOMATIC_PAUSED: installed dictionary fails negative controls; explicit review remains available")
        }
        let seeds: [(LanguagePair, String)] = [(.spanish, "manana"), (.french, "l'ecole"), (.german, "ueber"), (.portuguese, "reuniao"), (.korean, "chromedptj"), (.ukrainian, "ghbdsn")]
        for (pair, seed) in seeds {
            for text in ["https://example.com/\(seed) ", "\(seed)@example.com ", "#\(seed) ", "@\(seed) ", "\(seed)_id ", "\(seed)42 ", "`\(seed)` ", "--\(seed) ", "<\(seed)> ", "x::\(seed) ", "\(seed)\u{200B} ", "\(seed)\u{00AD} ", "\u{202E}\(seed) ", "«\(seed)» ", "„\(seed)“ ", "「\(seed)」 ", "\(seed)\n", "\(seed)    "] {
                check("PROTECTED \(pair.code) \(text.debugDescription)", TextIdentity.matches(immediate(text, pair: pair), text))
            }
            check("KEPT_WORD \(pair.code)", immediate("(" + seed + "), ", pair: pair, kept: [seed]) == "(" + seed + "), ")
        }
        for pair in LanguagePair.allCases {
            for script in ["こんにちは", "你好", "مرحبا", "हैलो", "γειά", "привет"] {
                let text = script + " "
                check("OTHER_SCRIPT \(pair.code) \(script)", immediate(text, pair: pair) == text)
            }
        }
        for pair in LanguagePair.allCases {
            for term in ["chrome", "figma", "notion", "slack", "chatgpt", "vscode", "github", "openai", "obsidian", "linear", "svelte", "nextjs", "vercel", "supabase", "claude", "llama", "deepseek", "lol", "lmao", "rofl", "skibidi", "rizz", "delulu", "sus", "yeet", "afaik", "ngl", "tbh", "idk", "brb", "imo", "imho", "fomo", "yolo"] {
                let source = term + " "
                let actual = immediate(source, pair: pair)
                check("LITERAL_VOCABULARY \(pair.code) \(term)", actual == source, detail: actual == source ? "" : actual)
            }
        }
        check("WHOLE_COMPOUND_KEEP", immediate("(reuniao-acao), ", pair: .portuguese, kept: ["reuniao-acao"]) == "(reuniao-acao), ")
        check("COMPONENT_KEEP", immediate("reuniao-acao ", pair: .portuguese, kept: ["reuniao"]) == "reuniao-ação ")
        check("SHORT_ENDING_NEW_PARAGRAPH", immediate("오늘\nchromedp ", pair: .korean) == "오늘\nchromedp ")
        check("COLLOQUIAL_NEW_PARAGRAPH", immediate("안녕\ndltdjd ", pair: .korean) == "안녕\ndltdjd ")
        let nfd = "오늘".decomposedStringWithCanonicalMapping
        check("NFD_CONTEXT", TextIdentity.matches(immediate(nfd + " chromedp ", pair: .korean), nfd + " chrome에 "))
        for (pair, seed) in seeds {
            let text = "👩‍💻 " + seed + " after"
            for length in 0...text.utf16.count {
                let range = NSRange(location: length, length: 0)
                guard let word = LiveWord.completed(in: text, selection: range, whileContinuing: true),
                      case let .immediate(change) = FastTypingPlan.make(word: word, document: text, engine: engine, pair: pair, keepWords: []) else { continue }
                let transaction = TextTransaction(before: text, range: change.range, replacement: change.candidates[0])
                check("CARET_TRANSACTION \(pair.code) \(length)", transaction.after != nil && NSMaxRange(change.range) < length && transaction.originalSelection == change.original && !transaction.canApply(to: text + "new"))
            }
        }
        var samples: [Double] = []
        let benchmark = ReviewEngine(spelling: spelling)
        for (pair, seed) in seeds {
            for _ in 0..<10 {
                let text = "👩‍💻 " + seed + " "
                let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
                spelling.clearCache()
                let start = ProcessInfo.processInfo.systemUptime
                _ = FastTypingPlan.make(word: word, document: text, engine: benchmark, pair: pair, keepWords: [])
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
        }
        samples.sort()
        print("SIX_PAIR_DECISION_60_RUNS median=\(String(format: "%.3f", (samples[29] + samples[30]) / 2))ms p95=\(String(format: "%.3f", samples[56]))ms max=\(String(format: "%.3f", samples.last!))ms; app caches cleared, warm system service, excludes AX/UI/model latency")
        let longDocument = String(repeating: "cafe\u{301} 👩‍💻 ", count: 5_000) + "chromedptj "
        var longSamples: [Double] = []
        for _ in 0..<10 {
            let start = ProcessInfo.processInfo.systemUptime
            let word = LiveWord.completed(in: longDocument, selection: NSRange(location: longDocument.utf16.count, length: 0))!
            let decision = FastTypingPlan.make(word: word, document: longDocument, engine: benchmark, pair: .korean, keepWords: [])
            if case let .immediate(change) = decision {
                let result = TextTransaction(before: longDocument, range: change.range, replacement: change.candidates[0]).after
                check("LONG_DOCUMENT_UNICODE", result?.hasSuffix("chrome에서 ") == true)
            } else { check("LONG_DOCUMENT_UNICODE", false) }
            longSamples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        longSamples.sort()
        print("LONG_DOCUMENT_10_RUNS units=\(longDocument.utf16.count) median=\(String(format: "%.3f", (longSamples[4] + longSamples[5]) / 2))ms max=\(String(format: "%.3f", longSamples.last!))ms; extraction + planning + simulated replacement, excludes AX/UI")
        print("MULTILINGUAL_CHECKS \(failures == 0 ? "PASS" : "FAIL") — \(checks) fixtures, \(failures) failures; curated regressions, not population accuracy")
        return failures == 0
    }
}
