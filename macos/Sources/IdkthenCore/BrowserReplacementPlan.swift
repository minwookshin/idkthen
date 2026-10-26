import Foundation

/// Replace through the existing caret so a browser's native insert leaves it
/// after the separator, even when its accessibility selection updates later.
public struct BrowserReplacementPlan: Sendable {
    public let range: NSRange
    public let text: String
    public let caretAfter: Int?

    public init?(transaction: TextTransaction, caret: Int?) {
        guard transaction.after != nil, transaction.originalSelection != nil else { return nil }
        if let caret {
            let end = NSMaxRange(transaction.range)
            guard caret >= end, caret - end <= 32,
                  TextTransaction(before: transaction.before, range: NSRange(location: caret, length: 0), replacement: "").after != nil else { return nil }
            let tail = (transaction.before as NSString).substring(with: NSRange(location: end, length: caret - end))
            range = NSRange(location: transaction.range.location, length: caret - transaction.range.location)
            text = transaction.replacement + tail
            caretAfter = transaction.range.location + text.utf16.count
        } else {
            // Browser selections may include unchanged surrounding text. Keep
            // those nodes and their formatting by editing the smallest span of
            // complete characters, with exact (not canonically equal) matching.
            let old = Array(transaction.originalSelection!)
            let new = Array(transaction.replacement)
            var prefix = 0
            while prefix < min(old.count, new.count), TextIdentity.matches(String(old[prefix]), String(new[prefix])) { prefix += 1 }
            var suffix = 0
            while suffix < min(old.count - prefix, new.count - prefix),
                  TextIdentity.matches(String(old[old.count - suffix - 1]), String(new[new.count - suffix - 1])) { suffix += 1 }
            let start = old.prefix(prefix).reduce(0) { $0 + String($1).utf16.count }
            let removed = old[prefix..<(old.count - suffix)].reduce(0) { $0 + String($1).utf16.count }
            range = NSRange(location: transaction.range.location + start, length: removed)
            text = String(new[prefix..<(new.count - suffix)])
            caretAfter = nil
        }
    }

    /// A single bounded Unicode event, never a sequence of partial writes.
    public var permitsUnicodeInsertion: Bool { !text.isEmpty && text.utf16.count <= 20 && !text.contains("\n") && !text.contains("\r") }
}
