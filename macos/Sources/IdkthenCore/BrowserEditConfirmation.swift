import Foundation

public enum BrowserEditConfirmation {
    /// Rich HTML editors may turn an adjacent space into a nonbreaking space
    /// during a native edit. Accept only that local, length-preserving change;
    /// keep the browser's actual surrounding text as the anchor for Undo.
    public static func transaction(_ transaction: TextTransaction, current: String,
                                   affected: NSRange, caretAfter: Int?) -> TextTransaction? {
        guard let expected = transaction.after, let original = transaction.originalSelection else { return nil }
        let expectedLength = expected.utf16.count, value = current as NSString
        let added = value.length - expectedLength
        guard added >= 0, value.length <= 100_000 else { return nil }
        let base: String
        if added > 0 {
            guard let caretAfter, caretAfter >= NSMaxRange(transaction.replacementRange), caretAfter <= expectedLength,
                  TextTransaction(before: current, range: NSRange(location: caretAfter, length: added), replacement: "").after != nil else { return nil }
            base = value.substring(to: caretAfter) + value.substring(from: caretAfter + added)
        } else { base = current }
        let a = Array(expected.utf16), b = Array(base.utf16)
        guard a.count == b.count, affected.location >= 0, affected.length >= 0,
              affected.location <= a.count, affected.length <= a.count - affected.location else { return nil }
        let lower = max(0, affected.location - 1), upper = min(a.count, NSMaxRange(affected) + 1)
        for i in a.indices where a[i] != b[i] {
            guard i >= lower, i < upper, [32, 160].contains(a[i]), [32, 160].contains(b[i]) else { return nil }
        }
        let actual = base as NSString, range = transaction.replacementRange
        let before = actual.substring(to: range.location) + original + actual.substring(from: NSMaxRange(range))
        return TextTransaction(before: before, range: transaction.range, replacement: actual.substring(with: range))
    }
}
