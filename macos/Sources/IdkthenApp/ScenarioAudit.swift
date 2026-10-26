import Foundation
import IdkthenCore

/// Developer-only, reproducible scenario evaluation. Never reads preferences or another app.
@MainActor enum ScenarioAudit {
    struct Scenario: Codable {
        let id: String
        let category: String
        let languages: [LanguagePair]
        let input: String
        let expected: String
        let keepWords: [String]?
    }
    struct Decision: Codable {
        let original: String
        let replacement: String
        let mode: String
        let milliseconds: Double
    }
    struct Result: Codable {
        let id: String
        let category: String
        let languages: [String]
        let input: String
        let expected: String
        let actual: String
        let passed: Bool
        let decisions: [Decision]
    }
    struct Report: Codable {
        let scope: String
        let system: String
        let total: Int
        let passed: Int
        let plannerMilliseconds: [Double]
        let results: [Result]
    }
    static func run(path: String) -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard data.count < 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let scenarios = try JSONDecoder().decode([Scenario].self, from: data)
            guard !scenarios.isEmpty, scenarios.count <= 2000,
                  Set(scenarios.map(\.id)).count == scenarios.count,
                  scenarios.allSatisfy({ (1...3).contains($0.languages.count) && Set($0.languages).count == $0.languages.count && $0.input.utf16.count <= 4000 }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let spelling = MacSpelling()
            let engine = ReviewEngine(spelling: spelling)
            var results: [Result] = [], times: [Double] = []
            for scenario in scenarios {
                var text = "", decisions: [Decision] = []
                for character in scenario.input {
                    text.append(character)
                    guard character == " " || character == "\t",
                          let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0)) else { continue }
                    // Match LiveTypingController's per-completed-word cache policy.
                    spelling.clearCache()
                    let start = ProcessInfo.processInfo.systemUptime
                    let plan = FastTypingPlan.make(word: word, document: text, engine: engine,
                                                  languages: LanguageSelection(scenario.languages), keepWords: Set(scenario.keepWords ?? []))
                    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                    times.append(elapsed)
                    switch plan {
                    case .skip: break
                    case .immediate(let change):
                        let replacement = change.candidates[0]
                        if let after = TextTransaction(before: text, range: change.range, replacement: replacement).after { text = after }
                        decisions.append(Decision(original: change.original, replacement: replacement, mode: "automatic", milliseconds: elapsed))
                    case .context(let change):
                        decisions.append(Decision(original: change.original, replacement: change.candidates[0], mode: "context-only-not-applied", milliseconds: elapsed))
                    }
                }
                results.append(Result(id: scenario.id, category: scenario.category, languages: scenario.languages.map(\.code),
                                      input: scenario.input, expected: scenario.expected, actual: text,
                                      passed: TextIdentity.matches(text, scenario.expected), decisions: decisions))
            }
            let report = Report(scope: "Authored scenarios through the native deterministic planner and this Mac's dictionaries, clearing app spelling caches per word as live typing does. Not a user study, OS event test, AI evaluation or population accuracy estimate.",
                                system: ProcessInfo.processInfo.operatingSystemVersionString,
                                total: results.count, passed: results.filter(\.passed).count,
                                plannerMilliseconds: times, results: results)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
            return true
        } catch {
            fputs("Scenario audit could not read a valid corpus.\n", stderr)
            return false
        }
    }
}
