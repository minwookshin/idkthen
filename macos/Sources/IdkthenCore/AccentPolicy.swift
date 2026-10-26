import Foundation

/// Only add missing accents. An existing accent (or ß) is evidence to preserve,
/// even when the spelling service offers another word with the same folded form.
enum AccentPolicy {
    static func permits(_ candidate: String, for original: String) -> Bool {
        let source = original.lowercased().precomposedStringWithCanonicalMapping
        let target = candidate.lowercased().precomposedStringWithCanonicalMapping
        guard source != target, ReviewEngine.folded(source) == ReviewEngine.folded(target) else { return false }
        var targetUnits: [Int: String] = [:]
        var offset = 0
        for character in target {
            let unit = String(character)
            targetUnits[offset] = unit
            offset += ReviewEngine.folded(unit).utf16.count
        }
        offset = 0
        for character in source {
            let unit = String(character)
            let base = ReviewEngine.folded(unit)
            if unit != base && targetUnits[offset] != unit { return false }
            offset += base.utf16.count
        }
        return true
    }
}
