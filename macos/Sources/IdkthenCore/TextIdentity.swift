import Foundation

/// Swift String equality is canonical, but Accessibility ranges use exact UTF-16 offsets.
/// An equivalent-looking newer value must still invalidate a captured edit or undo.
public enum TextIdentity {
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }
}
