import Foundation

// Standalone deterministic invariant checks against the production core sources.
// No AX access, preferences, network, or synthetic keyboard events.
@main struct StressQA {
    static func main() throws {
        var assertions = 0
        var scenarios = 0
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            assertions += 1
            if !condition && failures.count < 30 { failures.append(name) }
        }
        let prefixes = ["", "Hello ", "안녕 ", "🧑🏽‍💻 ", "👨‍👩‍👧‍👦 ", "🇨🇦 ", "cafe\u{301} ", "café ", "한글 ", "العربية ", "עברית ", "中文 日本語 "]
        let suffixes = ["", " suffix", " 🚀", " cafe\u{301}", " 한글", "\nnext line", " 👋🏽", " 🇺🇸 end"]
        let inserted = ["", "next", "two words ", "👨‍👩‍👧‍👦", "e\u{301}", "한글", "\nsecond line"]
        let pairs = [("manana", "mañana"), ("francais", "français"), ("coracao", "coração"), ("strasse", "straße"), ("perche", "perché"), ("ghbdtn", "привет"), ("ghbdsn", "привіт"), ("chromedptj", "chrome에서")]
        let started = Date()
        for prefix in prefixes { for suffix in suffixes { for (original, replacement) in pairs {
            let before = prefix + original + " " + suffix
            let expected = prefix + replacement + " " + suffix
            let tx = TextTransaction(before: before, range: NSRange(location: prefix.utf16.count, length: original.utf16.count), replacement: replacement)
            check(tx.after.map { TextIdentity.matches($0, expected) } == true, "transaction Unicode preservation")
            if let browser = BrowserReplacementPlan(transaction: tx, caret: prefix.utf16.count + original.utf16.count + 1) {
                check(TextTransaction(before: before, range: browser.range, replacement: browser.text).after.map { TextIdentity.matches($0, expected) } == true, "browser automatic preservation")
            } else { check(false, "browser automatic plan missing") }
            if let browser = BrowserReplacementPlan(transaction: tx, caret: nil) {
                check(TextTransaction(before: before, range: browser.range, replacement: browser.text).after.map { TextIdentity.matches($0, expected) } == true, "browser manual preservation")
            } else { check(false, "browser manual plan missing") }
            let caret = prefix.utf16.count + replacement.utf16.count + 1
            let recovery = CorrectionRecovery(transaction: tx, caretAfter: caret)
            for added in inserted {
                scenarios += 1
                let current = prefix + replacement + " " + added + suffix
                let restored = prefix + original + " " + added + suffix
                let selection = NSRange(location: caret + added.utf16.count, length: 0)
                let plan = recovery.plan(current: current, selection: selection)
                check(plan?.transaction.after.map { TextIdentity.matches($0, restored) } == true, "undo preservation")
                check(plan?.selection.location == (prefix + original + " " + added).utf16.count, "undo caret")
                check(recovery.recognizesOriginal(in: restored), "host undo recognition")
                check(recovery.plan(current: "X" + current, selection: selection) == nil, "stale prefix refusal")
                if !suffix.isEmpty { check(recovery.plan(current: current + "X", selection: selection) == nil, "stale suffix refusal") }
                check(recovery.plan(current: prefix + "X" + replacement + " " + added + suffix, selection: selection) == nil, "changed correction refusal")
            }
        } } }
        for fragment in prefixes.dropFirst() {
            let text = fragment + "dkssud "
            let boundaries = Set(text.indices.map { $0.utf16Offset(in: text) } + [text.utf16.count])
            for offset in 0...text.utf16.count {
                if !boundaries.contains(offset) {
                    check(TextTransaction(before: text, range: NSRange(location: offset, length: 0), replacement: "X").after == nil, "split-grapheme insertion refusal")
                    check(LiveWord.completed(in: text, selection: NSRange(location: offset, length: 0)) == nil, "split-grapheme caret refusal")
                }
            }
        }
        let invalid = [NSRange(location: -1, length: 0), NSRange(location: 0, length: -1), NSRange(location: Int.max, length: 1), NSRange(location: 0, length: Int.max)]
        for range in invalid {
            check(TextTransaction(before: "hello", range: range, replacement: "안녕").after == nil, "invalid range refusal")
        }
        let output: [String: Any] = ["scenarios": scenarios, "assertions": assertions, "failures": failures, "passed": failures.isEmpty, "seconds": Date().timeIntervalSince(started), "scope": "Synthetic core transaction/recovery invariants; not OS typing or language recognition accuracy."]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        if !failures.isEmpty { exit(1) }
    }
}
