import Foundation

/// Small authored recognition seeds. They protect exact English terms, not arbitrary
/// substrings or every future name/meme. User-kept vocabulary remains the extension point.
enum RecognizedVocabulary {
    static let englishNames: Set<String> = [
        "chrome", "safari", "firefox", "edge", "figma", "notion", "slack", "discord",
        "chatgpt", "github", "gitlab", "openai", "swiftui", "vscode", "youtube", "gmail",
        "ai", "ui", "ux", "ios", "macos", "iphone", "ipad", "obsidian", "linear",
        "svelte", "nextjs", "vercel", "supabase", "claude", "llama", "deepseek"
    ]
    static let internetExpressions: Set<String> = [
        "lol", "lmao", "rofl", "skibidi", "rizz", "delulu", "sus", "yeet", "afaik",
        "ngl", "tbh", "idk", "brb", "imo", "imho", "fomo", "yolo"
    ]
    static let protectedEnglish = englishNames.union(internetExpressions)
}
