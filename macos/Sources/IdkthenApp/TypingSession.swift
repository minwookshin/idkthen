import Foundation

/// Keeps the user's choice separate from temporary permission availability.
/// Reconciliation is event-driven; this type never polls or requests permission.
@MainActor final class TypingSession {
    private let defaults: UserDefaults
    private let start: () throws -> Void
    private let stop: () -> Void
    private(set) var requested: Bool
    private(set) var running = false
    private(set) var failure: String?

    init(defaults: UserDefaults, start: @escaping () throws -> Void, stop: @escaping () -> Void) {
        self.defaults = defaults; self.start = start; self.stop = stop
        requested = defaults.bool(forKey: "liveEnabled")
    }

    func setRequested(_ enabled: Bool) {
        requested = enabled
        defaults.set(enabled, forKey: "liveEnabled")
    }

    func reconcile(hasAccess: Bool, hasApps: Bool, blockedByAnotherCopy: Bool = false) {
        guard requested, hasAccess, hasApps else {
            if running { stop() }
            running = false; failure = nil
            return
        }
        guard !blockedByAnotherCopy else {
            if running { stop() }
            running = false; failure = AppInstance.conflictMessage
            return
        }
        guard !running else { return }
        do { try start(); running = true; failure = nil }
        catch { running = false; failure = error.localizedDescription }
    }
}

enum MenuBarState: Equatable {
    case on, off, pausedHere, needsAccess, needsApps, unavailable

    init(requested: Bool, running: Bool, hasAccess: Bool, hasApps: Bool, appPaused: Bool) {
        if !requested { self = .off }
        else if !hasAccess { self = .needsAccess }
        else if !hasApps { self = .needsApps }
        else if !running { self = .unavailable }
        else if appPaused { self = .pausedHere }
        else { self = .on }
    }

    var symbol: String {
        switch self {
        case .on: "character.cursor.ibeam"
        case .off, .pausedHere: "pause.circle"
        case .needsAccess, .needsApps, .unavailable: "exclamationmark.circle"
        }
    }

    var label: String {
        switch self {
        case .on: "On"
        case .off: "Paused"
        case .pausedHere: "Paused in This App"
        case .needsAccess: "Accessibility Needed"
        case .needsApps: "Choose an App"
        case .unavailable: "Connection Needed"
        }
    }
}
