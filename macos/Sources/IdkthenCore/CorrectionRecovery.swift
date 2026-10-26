import Foundation

/// One recent correction, anchored to the unchanged text on both sides of the
/// original caret. Only text inserted there may differ. No fuzzy matching/rebase.
public struct CorrectionRecovery: Sendable {
    public struct Plan: Sendable {
        public let transaction: TextTransaction
        public let selection: NSRange
    }
    public let transaction: TextTransaction
    public let caretAfter: Int
    private let corrected: String?
    private let original: String?
    private let validCaret: Bool
    public init(transaction: TextTransaction, caretAfter: Int) {
        self.transaction = transaction; self.caretAfter = caretAfter
        corrected = transaction.after
        original = corrected == nil ? nil : (transaction.before as NSString).substring(with: transaction.range)
        validCaret = corrected.map { TextTransaction(before: $0, range: NSRange(location: caretAfter, length: 0), replacement: "").after != nil } ?? false
    }
    /// Cheap availability check for typing notifications. Full character/selection
    /// validation happens only when building the actual undo plan.
    public func canRecover(current: String, selection: NSRange) -> Bool {
        guard validCaret, let corrected, caretAfter >= NSMaxRange(transaction.replacementRange),
              selection.location >= 0, selection.length >= 0, selection.location <= current.utf16.count,
              selection.length <= current.utf16.count - selection.location,
              hasInsertionOnly(current, around: corrected, caret: caretAfter) else { return false }
        let range = transaction.replacementRange
        return NSIntersectionRange(range, selection).length == 0
            && (selection.location <= range.location || selection.location >= NSMaxRange(range))
    }
    public func plan(current: String, selection: NSRange) -> Plan? {
        guard let original, canRecover(current: current, selection: selection),
              TextTransaction(before: current, range: selection, replacement: "").after != nil else { return nil }
        let range = transaction.replacementRange
        // A selection overlapping the corrected word is a new editing intention.
        guard NSIntersectionRange(range, selection).length == 0,
              selection.location <= range.location || selection.location >= NSMaxRange(range) else { return nil }
        let reverse = TextTransaction(before: current, range: range, replacement: original)
        guard let result = reverse.after else { return nil }
        let shift = transaction.range.length - range.length
        let start = selection.location >= NSMaxRange(range) ? selection.location + shift : selection.location
        let restored = NSRange(location: start, length: selection.length)
        guard TextTransaction(before: result, range: restored, replacement: "").after != nil else { return nil }
        return Plan(transaction: reverse, selection: restored)
    }
    /// Explicitly restoring the exact original spelling is a session-only veto.
    /// Surrounding text must still match; it is never a permanent learning event.
    public func recognizesOriginal(in current: String) -> Bool {
        guard validCaret, original != nil else { return false }
        let originalCaret = caretAfter + transaction.range.length - transaction.replacementRange.length
        return hasInsertionOnly(current, around: transaction.before, caret: originalCaret)
    }
    private func hasInsertionOnly(_ current: String, around anchor: String, caret: Int) -> Bool {
        let source = anchor as NSString, value = current as NSString
        guard value.length <= 100_000, caret >= 0, caret <= source.length,
              value.length >= source.length else { return false }
        let suffixLength = source.length - caret
        return TextIdentity.matches(value.substring(to: caret), source.substring(to: caret))
            && TextIdentity.matches(value.substring(from: value.length - suffixLength), source.substring(from: caret))
    }
}
