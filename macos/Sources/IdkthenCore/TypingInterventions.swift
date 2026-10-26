import Foundation

/// Small, in-memory limits. Time is monotonic; pausing never changes app profiles.
public struct TypingInterventions: Sendable {
    private var pauses: [String: TimeInterval] = [:]
    private var ignored: [String: (count: Int, until: TimeInterval)] = [:]
    public init() {}
    public mutating func pause(_ app: String, now: TimeInterval, duration: TimeInterval = 600) {
        pauses = pauses.filter { $0.value > now }
        if pauses.count >= 64 { pauses.removeValue(forKey: pauses.min(by: { $0.value < $1.value })!.key) }
        pauses[app] = now + duration
    }
    public mutating func resume(_ app: String) { pauses.removeValue(forKey: app) }
    public func paused(_ app: String, now: TimeInterval) -> Bool { (pauses[app] ?? 0) > now }
    public func deadline(for app: String) -> TimeInterval? { pauses[app] }
    public mutating func ignore(_ word: String, now: TimeInterval) {
        ignored = ignored.filter { $0.value.until > now }
        let key = word.lowercased().precomposedStringWithCanonicalMapping
        guard !key.isEmpty, key.utf16.count <= 96 else { return }
        if ignored.count >= 64, ignored[key] == nil { ignored.removeValue(forKey: ignored.min(by: { $0.value.until < $1.value.until })!.key) }
        ignored[key] = (min(2, (ignored[key]?.count ?? 0) + 1), now + 300)
    }
    public func suppressed(_ word: String, now: TimeInterval) -> Bool {
        guard let record = ignored[word.lowercased().precomposedStringWithCanonicalMapping] else { return false }
        return record.count >= 2 && record.until > now
    }
    public mutating func resetField() { ignored.removeAll(keepingCapacity: true) }
    public mutating func clear() { pauses.removeAll(); ignored.removeAll() }
}

public enum LiveFieldPolicy {
    /// Single-line/search/combobox fields are review-only. Browsers frequently
    /// expose their omnibox as an ordinary AXTextField with no reliable subtype.
    public static func allows(role: String?, subrole: String?, protected: Bool,
                              editable: Bool, hasMarkedText: Bool, hasCompletion: Bool,
                              contentRole: String? = nil) -> Bool {
        role == "AXTextArea" && subrole != "AXSecureTextField" && subrole != "AXSearchField"
            && !protected && editable && !hasMarkedText && !hasCompletion
            && !["code", "search", "searchbox", "combobox", "terminal"].contains(contentRole?.lowercased() ?? "")
    }
}

public enum LiveEditPolicy {
    /// AX does not identify paste events. Accept only a small insertion at the
    /// current caret; larger or multiword bursts get manual review instead.
    public static func permits(previous: String, current: String, selection: NSRange,
                               valueChanged: Bool = true, acceptsSelectionSignal: Bool = false) -> Bool {
        guard valueChanged || acceptsSelectionSignal else { return false }
        let old = previous as NSString, new = current as NSString
        let added = new.length - old.length
        guard selection.length == 0, added > 0, added <= 4, selection.location >= added,
              selection.location <= new.length else { return false }
        let start = selection.location - added
        guard start <= old.length,
              TextIdentity.matches(old.substring(to: start), new.substring(to: start)),
              TextIdentity.matches(old.substring(from: start), new.substring(from: selection.location)) else { return false }
        let inserted = new.substring(with: NSRange(location: start, length: added))
        return !inserted.contains(where: \.isNewline) && inserted.filter(\.isWhitespace).count <= 1
    }
}
