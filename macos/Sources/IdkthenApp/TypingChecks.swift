import Foundation
import IdkthenCore

@MainActor enum TypingChecks {
    static func run() -> Bool {
        let spelling = MacSpelling(), engine = ReviewEngine(spelling: MacSpelling())
        var passed = true, checks = 0, times: [Double] = []
        func check(_ name: String, _ condition: Bool) {
            checks += 1; passed = passed && condition
            print("\(name): \(condition ? "PASS" : "FAIL")")
        }
        func immediate(_ input: String, pair: LanguagePair = .korean, kept: Set<String> = []) -> String {
            guard let word = LiveWord.completed(in: input, selection: NSRange(location: (input as NSString).length, length: 0), whileContinuing: true),
                  case let .immediate(change) = FastTypingPlan.make(word: word, document: input, engine: engine, pair: pair, keepWords: kept) else { return input }
            return TextTransaction(before: input, range: change.range, replacement: change.candidates[0]).after ?? input
        }
        var output = ""
        for word in ["dkssud", "gkdl", "rmsep", "sjsms", "anjgkrh", "dltdjd"] {
            output += word + " "
            output = immediate(output)
        }
        check("CONTINUOUS_PHRASE \(output.debugDescription)", output == "안녕 하이 근데 너는 뭐하고 잇엉 ")
        let mixedCases = [
            ("chromedptj ", "chrome에서 "), ("Chromedptj ", "Chrome에서 "),
            ("CHROMEdptj ", "CHROME에서 "), ("figmadptjsms ", "figma에서는 "),
            ("GitHubfmf ", "GitHub를 "), ("OpenAIdmfh ", "OpenAI으로 "),
            ("SwiftUIgkrh ", "SwiftUI하고 "), ("notionRkwl ", "notion까지 "),
            ("slackqnxj ", "slack부터 "), ("chatgptdlfkrh ", "chatgpt이라고 "),
            ("AIdptj ", "AI에서 "), ("macOSdptj ", "macOS에서 "), ("cafédptj ", "café에서 "),
            ("오늘 chromedp ", "오늘 chrome에 "), ("👩‍💻 chromedptj dk", "👩‍💻 chrome에서 dk"),
            ("(chromedptj), ", "(chrome에서), "), ("chrome에서 ", "chrome에서 "),
            (Hangul.fromQWERTY("chrome") + "에서 ", "chrome에서 ")
        ]
        for (input, expected) in mixedCases {
            let actual = immediate(input)
            check("MIXED \(input.debugDescription) -> \(actual.debugDescription)", actual == expected)
        }
        check("CUSTOM_STEM", immediate("AcmeTooldptj ", kept: ["AcmeTool"]) == "AcmeTool에서 ")
        check("WHOLE_TOKEN_KEEP", immediate("chromedptj ", kept: ["chromedptj"]) == "chromedptj ")
        check("KEEP_DOES_NOT_DISABLE_OTHER_COMPOUNDS", immediate("figmadptj ", kept: ["chromedptj"]) == "figma에서 ")
        for input in [
            "My username is dkssud ", "우리 밈은 dkssud ", "hello ", "ㅋㅋㅋ ", "https://example.com/dkssud ",
            "spark ", "mark ", "chromedp ", "myProjectdptj ", "qxzvdptj ", "CHROMEDPTJ ", "chromedptj_id ",
            "chrome.dptj ", "https://chromedptj.com ", "chromedptj@example.com ", "#chromedptj ", "@chromedptj ",
            "`chromedptj` ", "chromedptj2 ", "GPT4dptj ", "asdptj ", "chrоmedptj ", "My username is chromedptj ", "우리 밈은 chromedptj ",
            "\"chromedptj\" ", "님차에서 ", "chrome에서\n", "chromedptj\n"
        ] { check("PROTECTION \(input.debugDescription)", immediate(input) == input) }
        let otherPairs: [(LanguagePair, String, String, String)] = [
            (.spanish, "¿manana?", "manana", "mañana"), (.french, "l'ecole", "l'ecole", "l'école"),
            (.french, "l’ecole", "l’ecole", "l’école"), (.french, "d'etre", "d'etre", "d'être"),
            (.german, "strasse", "strasse", "straße"), (.portuguese, "reuniao-online", "reuniao", "reunião"),
            (.ukrainian, "GitHub-ghbdsn", "ghbdsn", "привіт"), (.ukrainian, "ghbdsn!", "ghbdsn", "привіт")
        ]
        for (pair, input, original, candidate) in otherPairs {
            let review = engine.review(input, pair: pair)
            check("CANDIDATE_ONLY \(pair.code) \(input)", review.changes.contains { $0.original == original && $0.candidates.contains(candidate) })
        }
        for (pair, input) in [(LanguagePair.spanish, "si "), (.spanish, "tu "), (.french, "resume "), (.german, "schon "), (.german, "fur "), (.portuguese, "por "), (.portuguese, "pode ")] {
            check("AMBIGUITY \(pair.code) \(input)", immediate(input, pair: pair) == input)
        }
        for pair in LanguagePair.allCases where pair != .korean {
            check("PAIR_ISOLATION \(pair.code)", immediate("chromedptj ", pair: pair) == "chromedptj ")
            check("IDENTIFIER \(pair.code)", immediate("#manana ", pair: pair) == "#manana ")
        }
        let benchmarkEngine = ReviewEngine(spelling: spelling)
        for _ in 0..<30 {
            let input = "👩‍💻 chromedptj "
            let word = LiveWord.completed(in: input, selection: NSRange(location: (input as NSString).length, length: 0))!
            spelling.clearCache()
            let start = ProcessInfo.processInfo.systemUptime
            _ = FastTypingPlan.make(word: word, document: input, engine: benchmarkEngine, pair: .korean, keepWords: [])
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        let sorted = times.sorted(), median = (sorted[14] + sorted[15]) / 2
        print("MIXED_DECISION_30_RUNS median=\(String(format: "%.3f", median))ms p95=\(String(format: "%.3f", sorted[28]))ms max=\(String(format: "%.3f", sorted.last!))ms; excludes UI/AX, caches cleared per run")
        print("TYPING_CHECKS \(passed ? "PASS" : "FAIL") — \(checks) fixtures, not a population accuracy estimate")
        return passed
    }
}
