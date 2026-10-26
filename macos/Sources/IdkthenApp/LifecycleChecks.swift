import AppKit

/// Disposable preferences and a fake observer verify lifecycle transitions without
/// requesting access, registering login items, or reading another application's text.
@MainActor enum LifecycleChecks {
    static func run() -> Bool {
        let suite = "dev.pairtype.lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks = 0, failures = 0, starts = 0, stops = 0, refuseStart = false
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures += 1 }
            print("LIFECYCLE \(condition ? "PASS" : "FAIL") \(label)")
        }
        let session = TypingSession(defaults: defaults, start: {
            starts += 1
            if refuseStart { throw SelectionError.message("Test connection unavailable") }
        }, stop: { stops += 1 })
        session.reconcile(hasAccess: true, hasApps: true)
        check(!session.requested && !session.running && starts == 0, "new installation never starts observation on its own")
        session.setRequested(true)
        session.reconcile(hasAccess: false, hasApps: true)
        check(session.requested && !session.running && starts == 0 && defaults.bool(forKey: "liveEnabled"), "missing permission preserves the explicit On choice without starting")
        session.reconcile(hasAccess: true, hasApps: true)
        check(session.running && starts == 1, "permission recovery starts once")
        for _ in 0..<100 { session.reconcile(hasAccess: true, hasApps: true) }
        check(starts == 1 && stops == 0, "repeated activation events do not install duplicate observers")
        session.reconcile(hasAccess: false, hasApps: true)
        check(!session.running && stops == 1 && defaults.bool(forKey: "liveEnabled"), "revocation stops observation while preserving intent")
        session.setRequested(false)
        session.reconcile(hasAccess: false, hasApps: true)
        session.reconcile(hasAccess: true, hasApps: true)
        check(!session.running && starts == 1 && !defaults.bool(forKey: "liveEnabled"), "Pause during denied access prevents future automatic resume")
        session.setRequested(true)
        session.reconcile(hasAccess: true, hasApps: false)
        check(!session.running && starts == 1, "empty app allowlist cannot start observation")
        refuseStart = true
        session.reconcile(hasAccess: true, hasApps: true)
        check(!session.running && session.requested && session.failure != nil, "failed start is never presented as On")
        refuseStart = false
        session.reconcile(hasAccess: true, hasApps: true)
        check(session.running && session.failure == nil && starts == 3, "later activation can recover without resetting preferences")
        session.reconcile(hasAccess: true, hasApps: false)
        check(!session.running && stops == 2, "losing the final allowed app stops observation")
        let restored = TypingSession(defaults: defaults, start: { starts += 1 }, stop: { stops += 1 })
        check(restored.requested && !restored.running, "restoring preferences alone never starts observation")
        restored.reconcile(hasAccess: true, hasApps: true)
        check(restored.running && starts == 4, "configured On state resumes on relaunch")
        restored.setRequested(false); restored.reconcile(hasAccess: true, hasApps: true)
        let paused = TypingSession(defaults: defaults, start: { starts += 1 }, stop: {})
        paused.reconcile(hasAccess: true, hasApps: true)
        check(!paused.requested && !paused.running && starts == 4, "Pause survives relaunch")

        let cases: [(Bool, Bool, Bool, Bool, Bool, MenuBarState)] = [
            (false, false, false, false, false, .off),
            (true, false, false, true, false, .needsAccess),
            (true, false, true, false, false, .needsApps),
            (true, false, true, true, false, .unavailable),
            (true, true, true, true, true, .pausedHere),
            (true, true, true, true, false, .on)
        ]
        for (requested, running, access, apps, paused, expected) in cases {
            let state = MenuBarState(requested: requested, running: running, hasAccess: access, hasApps: apps, appPaused: paused)
            check(state == expected && NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil) != nil,
                  "menu has an available native symbol for \(expected.label)")
        }
        check(MenuBarState.on.symbol != MenuBarState.off.symbol && MenuBarState.on.symbol != MenuBarState.needsAccess.symbol,
              "On, Pause and unavailable are distinguishable without color")
        print("LIFECYCLE_CHECKS \(failures == 0 ? "PASS" : "FAIL") \(checks - failures)/\(checks)")
        return failures == 0
    }
}
