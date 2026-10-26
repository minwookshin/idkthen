import Foundation

/// A receipt identifies one actual correction, so undo/redo cannot manufacture feedback.
public struct UndoFeedback: Equatable, Sendable {
    public let id: UUID
    public let original: String
    public init(original: String, id: UUID = UUID()) { self.original = original; self.id = id }
}

/// Stores bounded word-only feedback, never document text or app/window history.
public struct UndoLearning: Codable, Sendable {
    public static let threshold = 3
    public static let capacity = 128
    private struct Entry: Codable, Sendable { var word: String; var count: Int }
    private var entries: [Entry] = []
    private var counted: Set<UUID> = []
    private var receiptOrder: [UUID] = []
    private enum CodingKeys: CodingKey { case entries }
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([Entry].self, forKey: .entries)
        var seen: Set<String> = []
        for entry in decoded.prefix(Self.capacity) {
            guard let word = Self.validWord(entry.word), (1...Self.threshold).contains(entry.count), seen.insert(word).inserted else { continue }
            entries.append(Entry(word: word, count: entry.count))
        }
    }
    public var learnedWords: [String] { entries.filter { $0.count >= Self.threshold }.map(\.word).sorted() }
    public var storedWordCount: Int { entries.count }
    public static func validWord(_ original: String) -> String? {
        let word = original.lowercased().precomposedStringWithCanonicalMapping
        guard (2...96).contains(word.utf16.count), !TypingProtection.isLiteral(word),
              word.unicodeScalars.filter(CharacterSet.letters.contains).count >= 2,
              word.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0) || "'’ʼ-".unicodeScalars.contains($0) }) else { return nil }
        return word
    }
    /// Returns true only when this feedback newly promotes a word to the keep list.
    @discardableResult public mutating func record(_ feedback: UndoFeedback) -> Bool {
        guard let word = Self.validWord(feedback.original), counted.insert(feedback.id).inserted else { return false }
        receiptOrder.append(feedback.id)
        if receiptOrder.count > 256 { counted.remove(receiptOrder.removeFirst()) }
        if let index = entries.firstIndex(where: { $0.word == word }) {
            guard entries[index].count < Self.threshold else { return false }
            entries[index].count += 1
            return entries[index].count == Self.threshold
        }
        if entries.count == Self.capacity {
            // Retain learned words until the user forgets them; discard old partial evidence first.
            guard let index = entries.firstIndex(where: { $0.count < Self.threshold }) else { return false }
            entries.remove(at: index)
        }
        entries.append(Entry(word: word, count: 1)); return false
    }
    public mutating func forget(_ word: String) {
        guard let key = Self.validWord(word) else { return }
        entries.removeAll { $0.word == key }
    }
    public mutating func forgetAll() { entries.removeAll() }
}
