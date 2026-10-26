import AppKit
import IdkthenCore

/// Real installed dictionaries and the native trial state machine, exercised
/// character by character. These are not external Accessibility or human tests.
@MainActor enum ConversationChecks {
    static func run() -> Bool {
        var count = 0, failures = 0
        var boundaryTimes: [Double] = []
        func check(_ label: String, _ condition: Bool) {
            count += 1; if !condition { failures += 1 }
            print("CONVERSATION \(label): \(condition ? "PASS" : "FAIL")")
        }
        let four = LanguageSelection([.spanish, .french, .korean])
        let input = "yeah i think 너는 지금 going home and 그리고 집에 rktj 이제 작업을 gkrpTwld and you will be glaema "
        let expected = "yeah i think 너는 지금 going home and 그리고 집에 가서 이제 작업을 하겠징 and you will be 힘듬 "
        func enter(_ text: String, trial: TypingTrial) {
            for character in text {
                let current = trial.text + String(character)
                let start = ProcessInfo.processInfo.systemUptime
                trial.userEdited(current, selection: NSRange(location: current.utf16.count, length: 0))
                if character == " " { boundaryTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1_000) }
            }
        }
        let trial = TypingTrial()
        trial.configure(languages: four, mode: .automatic, keepWords: [])
        let starts = ContextGuard.inferenceStarts
        enter(input, trial: trial)
        check("reported mixed sentence: \(trial.text)", trial.text == expected)
        enter("next", trial: trial)
        check("Undo preserves following input", trial.undo()?.after == expected.replacingOccurrences(of: "힘듬 ", with: "glaema ") + "next")
        enter(" glaema ", trial: trial)
        check("undone word stays literal", trial.text.hasSuffix("next glaema "))
        trial.clear()
        enter("dkssud dkssud dkssud rmsep sksms wlrma i'm thinking about sj ", trial: trial)
        check("layout switches and short final word: \(trial.text)", trial.text == "안녕 안녕 안녕 근데 나는 지금 i'm thinking about 너 ")
        trial.clear(); enter("👩‍💻 cafe\u{301} 지금 gkrpTwld! ", trial: trial)
        check("Unicode, punctuation, Shift", TextIdentity.matches(trial.text, "👩‍💻 cafe\u{301} 지금 하겠징! "))
        trial.clear()
        let pasted = "지금 gkrpTwld "
        trial.userEdited(pasted, selection: NSRange(location: pasted.utf16.count, length: 0), isPaste: true)
        check("paste preserved", trial.text == pasted && !trial.canUndo)
        trial.clear()
        trial.userEdited(pasted, selection: NSRange(location: pasted.utf16.count, length: 0), hasMarkedText: true)
        check("IME marked text preserved", trial.text == pasted && !trial.canUndo)
        check("no model work for conversation", starts == ContextGuard.inferenceStarts)

        let spelling = MacSpelling(), engine = ReviewEngine(spelling: spelling)
        let candidates: [(LanguagePair, String, String)] = [
            (.spanish, "ojala", "ojalá"), (.spanish, "musica", "música"),
            (.french, "desole", "désolé"), (.french, "desolee", "désolée"),
            (.portuguese, "otimo", "ótimo"), (.portuguese, "ultima", "última"),
            (.german, "fruher", "früher"), (.german, "naturlich", "natürlich"),
            (.italian, "giovedi", "giovedì"), (.italian, "venerdi", "venerdì"),
            (.russian, "ctqxfc", "сейчас"), (.russian, "hf,jnf.", "работаю"),
            (.ukrainian, "pfhfp", "зараз"), (.ukrainian, "lj,ht", "добре")
        ]
        for (pair, source, target) in candidates {
            let review = engine.review(source, pair: pair)
            check("\(pair.code) review \(source) → \(target)", review.changes.contains { $0.candidates.contains(target) })
            if !spelling.supportsAutomaticLayoutDetection(pair.spellLanguage) {
                check("\(pair.code) unreliable dictionary requires choice", review.changes.allSatisfy(\.requiresExplicitChoice))
            }
        }
        let chat: [LanguagePair: String] = [.spanish: "jajsjaja tqm porfa", .french: "ptdr stp jsp", .portuguese: "kkk blz vlw", .german: "vllt hdl bzw", .italian: "cmq xke tvb", .russian: "спс щас хз", .ukrainian: "дяк пліз імхо", .korean: "ㅋㅋ ㄱㅅ ㅇㅈ"]
        for (pair, words) in chat {
            let probe = TypingTrial()
            probe.configure(languages: LanguageSelection([pair, .korean]), mode: .automatic, keepWords: [])
            let source = "지금 ngl lmfao iykyk " + words + " "
            enter(source, trial: probe)
            check("\(pair.code) chat unchanged", probe.text == source)
        }
        for _ in 0..<50 {
            trial.clear(); enter(input, trial: trial)
            check("repeat sentence", trial.text == expected)
        }
        let sorted = boundaryTimes.sorted()
        print("NATIVE_BOUNDARY_DECISION count=\(sorted.count) p50=\(String(format: "%.3f", sorted[sorted.count / 2]))ms p95=\(String(format: "%.3f", sorted[Int(Double(sorted.count - 1) * 0.95)]))ms max=\(String(format: "%.3f", sorted.last!))ms; real dictionaries, includes first-use cost, excludes AX/UI")
        var cold: [Double] = []
        for _ in 0..<30 {
            spelling.clearCache()
            let source = "지금 작업을 gkrpTwld "
            let start = ProcessInfo.processInfo.systemUptime
            if let word = LiveWord.completed(in: source, selection: NSRange(location: source.utf16.count, length: 0)),
               case .immediate = FastTypingPlan.make(word: word, document: source, engine: engine, languages: four, keepWords: []) {
                cold.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            }
        }
        check("cold four-language decisions", cold.count == 30)
        if !cold.isEmpty { let times = cold.sorted(); print("COLD_FOUR_LANGUAGE p95=\(String(format: "%.3f", times[Int(Double(times.count - 1) * 0.95)]))ms max=\(String(format: "%.3f", times.last!))ms; spelling caches cleared per word") }
        print("CONVERSATION_CHECKS \(failures == 0 ? "PASS" : "FAIL") \(count - failures)/\(count); authored cases, not user accuracy")
        return failures == 0
    }
}
