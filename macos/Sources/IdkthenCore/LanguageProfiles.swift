import Foundation

/// No override means the app follows future changes to the default selection.
public struct LanguageProfiles: Equatable, Sendable {
    public let defaults: LanguageSelection
    public let overrides: [String: LanguageSelection]
    public init(defaults: LanguageSelection, overrides: [String: LanguageSelection] = [:]) {
        self.defaults = defaults; self.overrides = overrides
    }
    public func selection(for bundleIdentifier: String?) -> LanguageSelection {
        bundleIdentifier.flatMap { overrides[$0] } ?? defaults
    }
    public static func restore(_ raw: [String: [String]], allowed: Set<String>) -> [String: LanguageSelection] {
        var result: [String: LanguageSelection] = [:]
        for (bundle, values) in raw where allowed.contains(bundle) {
            let known = values.compactMap(LanguagePair.init(rawValue:))
            if !known.isEmpty { result[bundle] = LanguageSelection(known) }
        }
        return result
    }
}
