import Foundation

/// Layout recovery maps physical keys. Accent review only inspects written text.
/// Unknown layouts must never be interpreted as US QWERTY implicitly.
public enum KeyboardLayoutPolicy {
    private static let qwerty: Set<String> = [
        "com.apple.keylayout.US", "com.apple.keylayout.ABC",
        "com.apple.keylayout.USInternational-PC", "com.apple.keylayout.ABC-Extended"
    ]
    public static func permits(_ pair: LanguagePair, sourceID: String?) -> Bool {
        if pair.usesAccents { return true }
        guard let sourceID else { return false }
        if qwerty.contains(sourceID) { return true }
        switch pair {
        case .korean: return sourceID == "com.apple.inputmethod.Korean.2SetKorean"
        case .russian: return ["com.apple.keylayout.Russian", "com.apple.keylayout.Russian-PC"].contains(sourceID)
        case .ukrainian: return ["com.apple.keylayout.Ukrainian", "com.apple.keylayout.Ukrainian-PC"].contains(sourceID)
        default: return false
        }
    }
}
