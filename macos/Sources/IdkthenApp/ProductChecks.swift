import Foundation
import IdkthenCore

@MainActor enum ProductChecks {
    static func run() -> Bool {
        let suite = "dev.pairtype.checks.product.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["korean", "french"], forKey: "enabledLanguages")
        defaults.set("ConfidentialClientName, PrivateTerm", forKey: "keepWords")
        defaults.set(["example.secret.app": "Sensitive App Name"], forKey: "liveApps")
        let model = AppModel(defaults: defaults)
        model.input = "Private conversation never belongs in diagnostics."
        let report = model.supportReport
        var failures = 0, checks = 0
        func check(_ value: Bool, _ name: String) {
            checks += 1
            if !value { failures += 1; print("FAIL: \(name)") }
        }
        check(report.contains("Enabled app count: 1"), "app count available")
        check(report.contains("Kept word count: 2"), "word count available")
        check(report.contains("Accessibility trusted:"), "actual permission state included")
        check(report.contains("Languages:"), "language selection included")
        for secret in [model.input, "ConfidentialClientName", "PrivateTerm", "Sensitive App Name", "example.secret.app", NSHomeDirectory(), suite] {
            check(!report.contains(secret), "excluded sensitive content")
        }
        check(!report.contains("downloadURL"), "no invented release endpoint")
        print("Product checks: \(checks - failures)/\(checks) passed")
        return failures == 0
    }
}
