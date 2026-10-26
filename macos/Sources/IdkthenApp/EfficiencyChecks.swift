import AppKit
import IdkthenCore

@MainActor enum EfficiencyChecks {
    static func run() async -> Bool {
        var count = 0, failures = 0
        func check(_ label: String, _ value: Bool) {
            count += 1; if !value { failures += 1 }
            print("EFFICIENCY \(value ? "PASS" : "FAIL") \(label)")
        }
        let languages = LanguageSelection([.spanish, .french])
        let samples: [(String, String)] = [
            ("Nous préparons la prochaine reunion avec toute notre équipe demain matin.", "réunion"),
            ("Mañana tenemos una reunion con todos los compañeros de trabajo.", "reunión")
        ]
        let spelling = MacSpelling(), engine = ReviewEngine(spelling: spelling)
        let cold = ProcessInfo.processInfo.systemUptime
        check("French context hint", LocalLanguageContext.hint(before: "Nous préparons la prochaine ", after: " avec toute notre équipe demain matin.", languages: languages)?.code == "fr")
        print(String(format: "LANGUAGE_HINT_FIRST_CALL %.3fms; includes framework initialization", (ProcessInfo.processInfo.systemUptime - cold) * 1000))
        check("Short context abstains", LocalLanguageContext.hint(before: "la ", after: "", languages: languages) == nil)
        check("Unselected language cannot be forced into an enabled one", LocalLanguageContext.hint(before: "Сегодня мы обсуждаем важный проект ", after: "вместе с нашей командой.", languages: languages) == nil)
        check("Previous paragraph does not bias current word", LocalLanguageContext.hint(before: "Nous préparons la prochaine réunion avec toute notre équipe.\n\n", after: "", languages: languages) == nil)
        var timings: [Double] = []
        for (text, expected) in samples {
            let base = engine.review(text, languages: languages)
            let ranked = LocalLanguageContext.rank(base, languages: languages, spelling: spelling)
            let change = ranked.changes.first { $0.original == "reunion" }
            check("Rank \(expected) using nearby text", change?.candidates.first == expected)
            check("Ranking keeps explicit approval", change?.ambiguous == true && change?.requiresExplicitChoice == true)
            check("Ranking cannot add or remove candidates", Set(change?.candidates ?? []) == Set(base.changes.first { $0.original == "reunion" }?.candidates ?? []))
            check("No automatic change from ranking", ranked.applying([:]) == text)
            for _ in 0..<50 {
                let start = ProcessInfo.processInfo.systemUptime
                _ = LocalLanguageContext.rank(base, languages: languages, spelling: spelling)
                timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
        }
        for text in ["reunion", "https://example.com/reunion", "My username is reunion"] {
            let base = engine.review(text, languages: languages, keepWords: ["reunion"])
            check("Kept and literal candidates unaffected: \(text)", LocalLanguageContext.rank(base, languages: languages, spelling: spelling).changes == base.changes)
        }
        let suite = "dev.pairtype.efficiency-checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.setLanguages(languages); model.setContextEnabled(true)
        model.reviewLocalText(samples[0].0)
        if let change = model.review?.changes.first(where: { $0.original == "reunion" }) {
            check("Manual review begins unchecked", !model.decisions.isSelected(change))
            model.choose(change, "reunión"); model.analyze()
            check("Re-ranking preserves user choice", model.choices[change.id] == "reunión")
            model.setContextEnabled(false)
            check("Turning context off preserves explicit choice", model.choices[change.id] == "reunión")
        } else { check("Review fixture exists", false) }
        model.setContextEnabled(true)
        model.setAppLanguages(LanguageSelection([.italian, .russian]), for: "com.apple.TextEdit")
        model.reviewLocalText("lunedi ghbdtn", for: "com.apple.TextEdit")
        check("App override still determines review", model.output == "lunedì привет")
        let four = LanguageSelection([.spanish, .french, .korean])
        let beforeStarts = ContextGuard.inferenceStarts
        for text in ["chromedptj ", "manana ", "l'ecole ", "안녕 dltdjd "] {
            let word = LiveWord.completed(in: text, selection: NSRange(location: text.utf16.count, length: 0))!
            if case .immediate = FastTypingPlan.make(word: word, document: text, engine: engine, languages: four, keepWords: []) {
                check("Fast path \(text)", true)
            } else { check("Fast path \(text)", false) }
        }
        check("Immediate paths never start model inference", ContextGuard.inferenceStarts == beforeStarts)
        let local = TypingTrial(); local.configure(languages: four, mode: .automatic, keepWords: [])
        for prefix in ["Mon pseudo est ", "Meu nome de usuário é ", "Мой ник "] {
            local.clear(); let text = prefix + "dkssud "
            _ = local.userEdited(text, selection: NSRange(location: text.utf16.count, length: 0))
            check("Local trial protects literal intent: \(prefix)", local.text == text)
        }
        check("Trial protections start no model inference", ContextGuard.inferenceStarts == beforeStarts)

        // Deliberately non-cooperative work proves that the caller returns without
        // waiting for completion, while a second worker cannot be scheduled.
        let scheduler = ContextWorkScheduler()
        var release: CheckedContinuation<ContextDecision, Never>?
        let start = ProcessInfo.processInfo.systemUptime
        let expired = await scheduler.evaluate(deadline: .milliseconds(60)) { await withCheckedContinuation { release = $0 } }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        check("Deadline returns independently of model completion", expired == .unsure && elapsed < 250 && scheduler.isBusy)
        let blocked = await scheduler.evaluate { check("No queued worker", false); return .correct }
        check("Expired worker retains the only slot", blocked == .unsure && scheduler.startedCount == 1)
        release?.resume(returning: .correct)
        for _ in 0..<20 { if !scheduler.isBusy { break }; await Task.yield() }
        check("Late completion releases resources without delivering correction", !scheduler.isBusy)
        print(String(format: "DEADLINE_60MS measured=%.3fms; injected non-cooperative worker", elapsed))
        timings.sort()
        print(String(format: "LANGUAGE_RANK_100 ms median=%.3f p95=%.3f max=%.3f; bounded manual-review ranking only, warm model", timings[timings.count / 2], timings[Int(Double(timings.count - 1) * 0.95)], timings.last!))
        print("EFFICIENCY_CHECKS \(failures == 0 ? "PASS" : "FAIL") \(count - failures)/\(count)")
        return failures == 0
    }
}
