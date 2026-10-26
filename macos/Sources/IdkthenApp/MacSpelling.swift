import AppKit
import IdkthenCore

/// Uses the installed macOS spelling service. No remote model, API key, or bundled copied dictionary.
final class MacSpelling: SpellingProvider {
    private let checker = NSSpellChecker.shared
    private let documentTag = NSSpellChecker.uniqueSpellDocumentTag()
    private var validCache: [String: Bool] = [:]
    private var guessCache: [String: [String]] = [:]
    func isAvailable(_ language: String) -> Bool { checker.availableLanguages.contains(language) }
    func supportsAutomaticLayoutDetection(_ language: String) -> Bool {
        guard language == "uk" || language == "ru" else { return true }
        // On some macOS services the Ukrainian check returns "no error" even for
        // deliberately invalid consonant sequences. Availability alone is not confidence.
        return isAvailable(language) && isWord(language == "ru" ? "привет" : "привіт", language: language)
            && !isWord("фжщьйцщжц", language: language) && !isWord("щщщщщщщ", language: language)
    }
    func isWord(_ word: String, language: String) -> Bool {
        let key = language + ":" + word
        if let value = validCache[key] { return value }
        guard isAvailable(language) else { return false }
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: documentTag, wordCount: nil)
        let value = range.location == NSNotFound
        validCache[key] = value
        return value
    }
    func guesses(_ word: String, language: String) -> [String] {
        let key = language + ":" + word
        if let value = guessCache[key] { return value }
        let value = checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word, language: language, inSpellDocumentWithTag: documentTag) ?? []
        guessCache[key] = value
        return value
    }
    func clearCache() { validCache.removeAll(); guessCache.removeAll() }
    deinit { checker.closeSpellDocument(withTag: documentTag) }
}
