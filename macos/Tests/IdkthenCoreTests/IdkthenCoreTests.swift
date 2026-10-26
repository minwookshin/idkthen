import XCTest
@testable import IdkthenCore

struct TestSpelling: SpellingProvider {
    var available = Set(["en", "es", "fr", "de", "pt_BR", "ko", "uk", "it", "ru"])
    let words: [String: Set<String>] = [
        "en": ["hello", "the", "design", "is", "ready", "resume", "fur", "see", "you", "for", "update", "please", "review", "before", "friday", "we", "can", "it", "at", "next", "meeting", "keep", "link", "thanks", "openai", "swiftui", "github", "chrome", "spark", "mark", "spa", "download", "notion", "slack"],
        "es": ["mañana", "reunión", "después", "si", "sí", "tu", "tú", "papa", "papá", "resume", "menú"],
        "fr": ["réunion", "déjà", "résumé", "resume", "prêt"],
        "de": ["für", "schon", "schön", "das", "ist"],
        "pt_BR": ["reunião", "amanhã", "é", "e", "por", "pôr", "pode", "pôde"],
        "ko": ["안녕", "안녕하세요", "감사합니다"], "uk": ["привіт", "дякую"],
        "it": ["lunedì", "perché", "città"], "ru": ["привет", "спасибо"]
    ]
    let candidates: [String: [String]] = [
        "es:manana": ["mañana", "banana", "manzana"], "es:reunion": ["reunión"], "es:despues": ["después"],
        "es:si": ["sí"], "es:tu": ["tú"], "es:papa": ["papá"], "es:menu": ["menú"],
        "fr:reunion": ["réunion"], "fr:deja": ["déjà"], "fr:resume": ["résumé", "resumé", "presume"],
        "de:fur": ["für"], "de:schon": ["schön"], "pt_BR:reuniao": ["reunião"], "pt_BR:amanha": ["amanhã"], "pt_BR:e": ["é"],
        "pt_BR:por": ["pôr"], "pt_BR:pode": ["pôde"],
        "it:lunedi": ["lunedì"], "it:perche": ["perché"], "it:citta": ["città"]
    ]
    func isAvailable(_ language: String) -> Bool { available.contains(language) }
    func isWord(_ word: String, language: String) -> Bool { words[language]?.contains(word.lowercased()) == true }
    func guesses(_ word: String, language: String) -> [String] { candidates[language + ":" + word.lowercased()] ?? [] }
}

final class IdkthenCoreTests: XCTestCase {
    let engine = ReviewEngine(spelling: TestSpelling())
    func testEnglishStemWithKoreanEndingsPreservesCaseAndPunctuation() {
        for (source, target) in [
            ("chromedptj", "chrome에서"), ("Chromedptj", "Chrome에서"),
            ("CHROMEdptj", "CHROME에서"), ("figmadptjsms", "figma에서는"),
            ("GitHubfmf", "GitHub를"), ("OpenAIdmfh", "OpenAI으로"),
            ("SwiftUIgkrh", "SwiftUI하고"), ("notionRkwl", "notion까지"),
            ("AIdptj", "AI에서"), ("macOSdptj", "macOS에서"),
            ("slackqnxj", "slack부터"), ("chatgptdlfkrh", "chatgpt이라고")
        ] {
            let input = "👩‍💻 오늘 (" + source + "), done"
            let review = engine.review(input, pair: .korean, keepWords: ["GitHub", "OpenAI", "SwiftUI"])
            XCTAssertEqual(suggested(review), "👩‍💻 오늘 (" + target + "), done", source)
            XCTAssertEqual(review.changes.first?.original, source, "Undo must preserve the full mixed token identity")
            XCTAssertTrue(engine.review(target, pair: .korean).changes.isEmpty, "Already-correct mixed words must remain intact")
        }
    }
    func testMixedRecoveryWorksInLivePlanWhileNextWordIsBeingTyped() {
        let text = "👩‍💻 chromedptj dk"
        let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0), whileContinuing: true)!
        guard case let .immediate(change) = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) else { return XCTFail("Expected an immediate mixed-token recovery") }
        let transaction = TextTransaction(before: text, range: change.range, replacement: change.candidates[0])
        XCTAssertEqual(transaction.after, "👩‍💻 chrome에서 dk")
        XCTAssertEqual(transaction.originalSelection, "chromedptj")
        XCTAssertTrue(transaction.canUndo(current: transaction.after!))
        XCTAssertFalse(transaction.canUndo(current: transaction.after! + "new"))
    }
    func testShortKoreanEndingNeedsRecentKoreanContext() {
        let isolated = engine.review("chromedp", pair: .korean)
        XCTAssertEqual(isolated.changes.first?.candidates, ["chrome에"])
        XCTAssertEqual(isolated.changes.first?.ambiguous, true)
        XCTAssertEqual(suggested(isolated), "chromedp")
        let text = "오늘 chromedp "
        let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0))!
        guard case let .immediate(change) = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) else { return XCTFail("Recent Korean context was lost at the token boundary") }
        XCTAssertEqual(change.candidates, ["chrome에"])
    }
    func testMixedRecoveryKeepsLiteralIdentifiersAndUnknownBoundaries() {
        for token in ["spark", "mark", "myProjectdptj", "qxzvdptj", "chrome에서", "hello안녕", "CHROMEDPTJ", "chromedptj_id", "chrome.dptj", "https://chromedptj.com", "chromedptj@example.com", "#chromedptj", "@chromedptj", "`chromedptj`", "chromedptj2", "GPT4dptj", "asdptj", "chrоmedptj"] {
            XCTAssertTrue(engine.review(token, pair: .korean).changes.isEmpty, token)
        }
        for text in ["My username is chromedptj ", "우리 밈은 chromedptj ", "\"chromedptj\" ", "#chromedptj "] {
            guard let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0)) else { continue }
            if case .immediate = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) { XCTFail(text) }
        }
        XCTAssertTrue(engine.review("chromedptj", pair: .korean, keepWords: ["chromedptj"]).changes.isEmpty)
        XCTAssertEqual(suggested(engine.review("AcmeTooldptj", pair: .korean, keepWords: ["AcmeTool"])), "AcmeTool에서")
        XCTAssertTrue(engine.review("AcmeTooldptj", pair: .korean).changes.isEmpty)
        XCTAssertEqual(suggested(engine.review("dptj", pair: .korean, keepWords: ["chromedptj"])), "dptj", "Keeping a compound must not add its suffix to the keep list")
    }
    func testCompetingMixedTokenBoundariesRequireChoice() {
        let review = engine.review("chromedptjsms", pair: .korean, keepWords: ["chromedptj"])
        XCTAssertEqual(Set(review.changes.first?.candidates ?? []), Set(["chrome에서는", "chromedptj는"]))
        XCTAssertEqual(review.changes.first?.ambiguous, true)
        XCTAssertEqual(suggested(review), "chromedptjsms")
    }
    func testReverseEnglishStemRecoveryRequiresJamoAndKnownStem() {
        for stem in ["chrome", "github"] {
            let wrong = Hangul.fromQWERTY(stem) + "에서"
            let review = engine.review(wrong, pair: .korean)
            XCTAssertEqual(suggested(review), stem + "에서", wrong)
        }
        for correct in ["크롬에서", "노션에서", "사람들은", "한글에서", "chrome에서", "님차에서"] {
            XCTAssertTrue(engine.review(correct, pair: .korean).changes.isEmpty, correct)
        }
    }
    func testMixedTokenRuleNeverLeaksIntoOtherLanguagePairs() {
        for pair in LanguagePair.allCases where pair != .korean {
            XCTAssertTrue(engine.review("chromedptj", pair: pair).changes.isEmpty, pair.code)
        }
        for (pair, text) in [(LanguagePair.spanish, "si"), (.spanish, "tu"), (.french, "resume"), (.german, "schon"), (.german, "fur"), (.portuguese, "pode"), (.portuguese, "por")] {
            XCTAssertEqual(suggested(engine.review(text, pair: pair)), text, "Meaning ambiguity must stay explicit: \(pair.code) \(text)")
        }
        for pair in LanguagePair.allCases {
            XCTAssertTrue(engine.review("#manana #ghbdsn", pair: pair).changes.isEmpty)
        }
    }
    func testDictionaryOverAcceptanceCannotBypassIdentifierOrLayoutGuards() {
        struct OverAcceptingSpelling: SpellingProvider {
            let base = TestSpelling()
            func isAvailable(_ language: String) -> Bool { true }
            func isWord(_ word: String, language: String) -> Bool {
                if language == "uk" { return true }
                if language == "en" && word == "myProject" { return true }
                return base.isWord(word, language: language)
            }
            func guesses(_ word: String, language: String) -> [String] { base.guesses(word, language: language) }
        }
        let cautious = ReviewEngine(spelling: OverAcceptingSpelling())
        XCTAssertTrue(cautious.review("myProjectdptj", pair: .korean).changes.isEmpty)
        let review = cautious.review("chromedptj", pair: .ukrainian)
        XCTAssertEqual(review.changes.first?.ambiguous, true)
        XCTAssertEqual(suggested(review), "chromedptj")
        let text = "chromedptj "
        let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0))!
        guard case .skip = FastTypingPlan.make(word: word, document: text, engine: cautious, pair: .ukrainian, keepWords: []) else { return XCTFail("Unreliable dictionary result must not become an automatic or AI-approved edit") }
        XCTAssertEqual(suggested(cautious.review("ghbdsn", pair: .ukrainian)), "привіт")
    }
    func testAccentedAndDecomposedKeptStemsRetainTheirExactSpelling() {
        for stem in ["café", "cafe\u{301}", "Müller"] {
            let text = stem + "dptj"
            XCTAssertEqual(suggested(engine.review(text, pair: .korean, keepWords: [stem.precomposedStringWithCanonicalMapping])), stem + "에서")
        }
        XCTAssertTrue(engine.review("chrоmedptj", pair: .korean).changes.isEmpty, "Cyrillic o must not become an English stem")
        XCTAssertTrue(engine.review("한국ghbdsn", pair: .ukrainian).changes.isEmpty, "Unselected scripts must remain intact")
    }
    func testFastKoreanContextRecoversInformalWordingWithoutRespelling() {
        var text = ""
        for input in ["dkssud", "gkdl", "rmsep", "sjsms", "anjgkrh", "dltdjd"] {
            text += input + " "
            let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0))!
            guard case let .immediate(change) = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) else {
                return XCTFail("Expected immediate recovery for \(input)")
            }
            text = TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after!
        }
        XCTAssertEqual(text, "안녕 하이 근데 너는 뭐하고 잇엉 ", "Do not respell informal wording")
        let shifted = "안녕 dlTdjd "
        let word = LiveWord.completed(in: shifted, selection: NSRange(location: (shifted as NSString).length, length: 0))!
        guard case let .immediate(change) = FastTypingPlan.make(word: word, document: shifted, engine: engine, pair: .korean, keepWords: []) else { return XCTFail("Two-set Shift key was mistaken for camelCase") }
        XCTAssertEqual(change.candidates, ["있엉"])
    }
    func testFastRecoveryCanCorrectPreviousWordWithoutOverwritingNextWord() {
        let text = "👩‍💻 dkssud gk"
        let caret = NSRange(location: (text as NSString).length, length: 0)
        XCTAssertNil(LiveWord.completed(in: text, selection: caret))
        let word = LiveWord.completed(in: text, selection: caret, whileContinuing: true)!
        XCTAssertEqual(word.text, "dkssud")
        guard case let .immediate(change) = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) else { return XCTFail("Missing immediate plan") }
        XCTAssertEqual(TextTransaction(before: text, range: change.range, replacement: change.candidates[0]).after, "👩‍💻 안녕 gk")
    }
    func testFastRecoveryKeepsSlangNamesQuotesAndEnglish() {
        for text in ["안녕 My username is rksk ", "안녕 밈은 dltdjd ", "안녕 hello ", "안녕 `dltdjd` ", "안녕 ㅋㅋㅋ ", "dltdjd "] {
            guard let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0)) else { continue }
            if case .immediate = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: []) { XCTFail(text) }
        }
        let text = "안녕 dltdjd "
        let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0))!
        if case .immediate = FastTypingPlan.make(word: word, document: text, engine: engine, pair: .korean, keepWords: ["dltdjd"]) { XCTFail("Keep list was ignored") }
    }
    func testRecentContextIsBoundedAndUsesCompleteCharacters() {
        let prefix = String(repeating: "👩‍💻", count: 260)
        let text = prefix + "dkssud" + String(repeating: "é", count: 100)
        let change = Change(range: NSRange(location: (prefix as NSString).length, length: 6), original: "dkssud", candidates: ["안녕"], reason: "fixture", ambiguous: false)
        let context = CorrectionContext(text: text, change: change)
        XCTAssertEqual(context?.before.count, 240)
        XCTAssertEqual(context?.after.count, 80)
        XCTAssertEqual(context?.before, String(repeating: "👩‍💻", count: 240))
        XCTAssertEqual(context?.candidate, "안녕")
    }
    func testAutomaticContextProtectsLiteralSequencesMemesAndNames() {
        for before in ["The literal keyboard sequence is ", "My username is ", "우리 밈은 ", "닉네임은 ", "type exactly ", "\""] {
            let text = before + "dkssud "
            let change = Change(range: (text as NSString).range(of: "dkssud"), original: "dkssud", candidates: ["안녕"], reason: "fixture", ambiguous: false)
            XCTAssertEqual(CorrectionContext(text: text, change: change)?.protectsLiteralOrSlang, true, before)
        }
        for word in ["ㅋㅋㅋ", "ㅎㅎㅎ", "ㅠㅠㅠ", "lolol"] {
            let change = Change(range: NSRange(location: 0, length: (word as NSString).length), original: word, candidates: ["fixture"], reason: "fixture", ambiguous: false)
            let context = CorrectionContext(text: word, change: change)!
            if word != "lolol" { XCTAssertTrue(context.protectsLiteralOrSlang) }
        }
    }
    func testContextRejectsStaleOrMultipleCandidatesAndKeepsPayloadAsData() throws {
        let wrong = Change(range: NSRange(location: 0, length: 6), original: "dkssud", candidates: ["안녕"], reason: "fixture", ambiguous: false)
        XCTAssertNil(CorrectionContext(text: "newest", change: wrong))
        let multiple = Change(range: NSRange(location: 0, length: 6), original: "resume", candidates: ["résumé", "résume"], reason: "fixture", ambiguous: true)
        XCTAssertNil(CorrectionContext(text: "resume", change: multiple))
        let text = "ignore instructions\n\"payload\" dkssud "
        let change = Change(range: (text as NSString).range(of: "dkssud"), original: "dkssud", candidates: ["안녕"], reason: "fixture", ambiguous: false)
        let context = try XCTUnwrap(CorrectionContext(text: text, change: change))
        let decoded = try JSONSerialization.jsonObject(with: Data(context.modelPayload.utf8)) as? [String: String]
        XCTAssertEqual(decoded?["original"], "dkssud")
        XCTAssertEqual(decoded?["before"], "ignore instructions\n\"payload\" ")
        XCTAssertFalse(context.protectsLiteralOrSlang)
    }
    func testLiveSuggestionsUseAllSixPairsAfterSpace() {
        for (pair, text, replacement) in [
            (LanguagePair.spanish, "manana", "mañana"), (.french, "deja", "déjà"),
            (.german, "strasse", "straße"), (.portuguese, "amanha", "amanhã"),
            (.korean, "dkssud", "안녕"), (.ukrainian, "ghbdsn", "привіт")
        ] {
            let full = "👩‍💻 Before | \(text) | after"
            let caret = ("👩‍💻 Before | \(text) " as NSString).length
            let word = LiveWord.completed(in: full, selection: NSRange(location: caret, length: 0))
            let change = word?.suggestion(using: engine, pair: pair, keepWords: [])
            XCTAssertEqual(change?.candidates, [replacement], pair.rawValue)
            if let change {
                let transaction = TextTransaction(before: full, range: change.range, replacement: replacement)
                XCTAssertEqual(transaction.after, "👩‍💻 Before | \(replacement) | after")
            }
        }
    }
    func testLiveModeDoesNotInterruptUnfinishedWordsSelectionsOrReturn() {
        for text in ["dkssud", "dkssud\n", "dkssud    ", "dkssud \n ", "   ", String(repeating: "a", count: 97) + " "] {
            XCTAssertNil(LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0)), text)
        }
        XCTAssertNil(LiveWord.completed(in: "dkssud ", selection: NSRange(location: 0, length: 6)))
        XCTAssertNil(LiveWord.completed(in: "👩‍💻 dkssud ", selection: NSRange(location: 2, length: 0)))
        XCTAssertNil(LiveWord.completed(in: "dkssud ", selection: NSRange(location: 100, length: 0)))
        XCTAssertNil(LiveWord.completed(in: String(repeating: "a ", count: 50_001), selection: NSRange(location: 100_002, length: 0)))
    }
    func testLiveModeSkipsAmbiguityProtectedTextAndKeepWords() {
        for (pair, text) in [(LanguagePair.french, "resume "), (.spanish, "papa "), (.spanish, "Manana "),
                             (.spanish, "https://example.com/manana "), (.spanish, "manana@company.com "),
                             (.spanish, "manana_id "), (.korean, "dkssud안녕 "), (.korean, "hello ")] {
            let word = LiveWord.completed(in: text, selection: NSRange(location: (text as NSString).length, length: 0))
            XCTAssertNil(word?.suggestion(using: engine, pair: pair, keepWords: []), text)
        }
        let text = "manana "
        let word = LiveWord.completed(in: text, selection: NSRange(location: 7, length: 0))
        XCTAssertNil(word?.suggestion(using: engine, pair: .spanish, keepWords: ["manana"]))
        for code in ["`some dkssud ", "```\nexample dkssud ", "`dkssud` "] {
            XCTAssertNil(LiveWord.completed(in: code, selection: NSRange(location: (code as NSString).length, length: 0)))
        }
    }
    func suggested(_ review: Review) -> String {
        review.applying(Dictionary(uniqueKeysWithValues: review.changes.filter { !$0.ambiguous }.map { ($0.id, $0.candidates[0]) }))
    }
    func testEveryModernHangulSyllableRoundTripsThroughTwoSet() {
        for value in 0xAC00...0xD7A3 {
            let syllable = String(UnicodeScalar(value)!)
            XCTAssertEqual(Hangul.fromQWERTY(Hangul.toQWERTY(syllable)), syllable, "Unicode \(value)")
        }
    }
    func testHangulCompositionResyllabifiesFinalsAndCompoundVowels() {
        XCTAssertEqual(Hangul.fromQWERTY("dkssudgktpdy"), "안녕하세요")
        XCTAssertEqual(Hangul.fromQWERTY("rkatkgkqslek"), "감사합니다")
        XCTAssertEqual(Hangul.fromQWERTY("rhoscksgdkdy"), "괜찮아요")
        XCTAssertEqual(Hangul.fromQWERTY("rkqt"), "값")
        XCTAssertEqual(Hangul.fromQWERTY("rkqtk"), "갑사")
        XCTAssertEqual(Hangul.fromQWERTY("rkqt! 👋"), "값! 👋")
        XCTAssertEqual(Hangul.toQWERTY("ㅗ디ㅣㅐ"), "hello")
    }
    func testUkrainianStandardLetterAndPunctuationRecovery() {
        XCTAssertEqual(UkrainianLayout.convert("ghbdsn", toEnglish: false), "привіт")
        XCTAssertEqual(UkrainianLayout.convert("lzre.", toEnglish: false), "дякую")
        XCTAssertEqual(UkrainianLayout.convert("руддщ", toEnglish: true), "hello")
        XCTAssertEqual(UkrainianLayout.convert("Ghbdsl", toEnglish: false), "Привід")
    }
    func testEverySupportedLanguageHasCandidateBehavior() {
        for pair in LanguagePair.allCases {
            XCTAssertFalse(engine.review(pair.sample, pair: pair).changes.isEmpty, pair.rawValue)
        }
    }
    func testMixedSpanishPreservesEnglishAndWhitespaceExactly() {
        let input = "👋 See you manana!\n\tla reunion — despues."
        XCTAssertEqual(suggested(engine.review(input, pair: .spanish)), "👋 See you mañana!\n\tla reunión — después.")
    }
    func testAmbiguousMeaningRequiresExplicitChoice() {
        let review = engine.review("resume", pair: .french)
        XCTAssertEqual(review.changes.first?.ambiguous, true)
        XCTAssertEqual(suggested(review), "resume")
        XCTAssertEqual(review.applying([0: "résumé"]), "résumé")
        XCTAssertEqual(review.applying([0: "presume"]), "resume", "Do not allow a general rewrite")
        for (pair, word) in [(LanguagePair.spanish, "si"), (.german, "schon"), (.portuguese, "por")] {
            XCTAssertTrue(engine.review(word, pair: pair).changes.allSatisfy(\.ambiguous))
        }
    }
    func testLinksEmailsCodeNamesAndAcronymsAreProtected() {
        let input = "https://example.com/manana name@manana.io /tmp/reunion `manana reunion` manana_id \"SwiftUI\" MANANA"
        let review = engine.review(input, pair: .spanish)
        XCTAssertTrue(review.changes.isEmpty)
        XCTAssertEqual(suggested(review), input)
        XCTAssertTrue(engine.review("manana", pair: .spanish, keepWords: ["Manana"]).changes.isEmpty)
        XCTAssertTrue(engine.review("```text\nmanana reunion\n```", pair: .spanish).changes.isEmpty)
    }
    func testDetectLeavesValidWordsInBothLanguagesAlone() {
        let review = engine.review("hello 안녕하세요 dkssud", pair: .korean)
        XCTAssertEqual(suggested(review), "hello 안녕하세요 안녕")
        XCTAssertEqual(review.changes.count, 1)
        XCTAssertEqual(suggested(engine.review("hello привіт ghbdsn", pair: .ukrainian)), "hello привіт привіт")
    }
    func testExplicitMappingIsNotPresentedAsLanguageCertainty() {
        let review = engine.review("hello", pair: .korean, direction: .toPartner)
        XCTAssertEqual(review.changes.first?.ambiguous, true)
        XCTAssertEqual(suggested(review), "hello")
        XCTAssertTrue(engine.review("https://example.com/hello", pair: .korean, direction: .toPartner).changes.isEmpty)
    }
    func testDictionaryOverAcceptanceOffersAnUncheckedReverseCandidate() {
        struct PermissiveSpelling: SpellingProvider {
            func isAvailable(_ language: String) -> Bool { true }
            func isWord(_ word: String, language: String) -> Bool { true }
            func guesses(_ word: String, language: String) -> [String] { [] }
        }
        let review = ReviewEngine(spelling: PermissiveSpelling()).review("руддщ", pair: .ukrainian)
        XCTAssertEqual(review.changes.first?.candidates, ["hello"])
        XCTAssertEqual(review.changes.first?.ambiguous, true)
        XCTAssertEqual(suggested(review), "руддщ")
        XCTAssertTrue(ReviewEngine(spelling: PermissiveSpelling()).review("hello", pair: .ukrainian).changes.isEmpty)
    }
    func testUnavailableDictionaryNeverPretendsToCheck() {
        var speller = TestSpelling(); speller.available.remove("ko")
        let result = ReviewEngine(spelling: speller).review("dkssud", pair: .korean)
        XCTAssertNotNil(result.notice); XCTAssertTrue(result.changes.isEmpty)
    }
    func testEnglishFunctionWordsDoNotClutterFrenchPassages() {
        struct AccentSpelling: SpellingProvider {
            func isAvailable(_ language: String) -> Bool { true }
            func isWord(_ word: String, language: String) -> Bool { true }
            func guesses(_ word: String, language: String) -> [String] { word.lowercased() == "the" ? ["thé"] : [] }
        }
        let engine = ReviewEngine(spelling: AccentSpelling())
        XCTAssertTrue(engine.review("The report", pair: .french).changes.isEmpty)
        XCTAssertEqual(engine.review("the", pair: .french).changes.first?.candidates, ["thé"])
    }
    func testOversizedSelectionIsNotAnalyzed() {
        let result = engine.review(String(repeating: "a", count: 4001), pair: .spanish)
        XCTAssertNotNil(result.notice); XCTAssertTrue(result.changes.isEmpty)
    }
    func testExistingAccentsAreNeverRemovedOrMoved() {
        XCTAssertFalse(AccentPolicy.permits("cafe", for: "café"))
        XCTAssertFalse(AccentPolicy.permits("càfe", for: "café"))
        XCTAssertFalse(AccentPolicy.permits("avô", for: "avó"))
        XCTAssertFalse(AccentPolicy.permits("strasse", for: "straße"))
        XCTAssertFalse(AccentPolicy.permits("cafe", for: "cafe\u{301}"))
        XCTAssertTrue(AccentPolicy.permits("résumé", for: "resumé"))
        XCTAssertTrue(AccentPolicy.permits("mañana", for: "manana"))
        XCTAssertTrue(AccentPolicy.permits("straße", for: "strasse"))
        XCTAssertTrue(engine.review("avó avô café résumé", pair: .portuguese).changes.isEmpty)
    }
    func testCapitalizedAccentCandidatesRequireTheWritersChoice() {
        let review = engine.review("Manana", pair: .spanish)
        XCTAssertEqual(review.changes.first?.candidates, ["Mañana"])
        XCTAssertEqual(review.changes.first?.ambiguous, true)
        XCTAssertEqual(suggested(review), "Manana")
    }
    func testUkrainianRecoveryPreservesSentencePunctuationAndLayoutLetters() {
        let review = engine.review("ghbdsn. ghbdsn, lzre.", pair: .ukrainian)
        XCTAssertEqual(suggested(review), "привіт. привіт, дякую")
    }
    func testMixedScriptWordsStayIntactEvenWithExplicitConversion() {
        for (pair, input) in [(LanguagePair.korean, "hello안녕"), (.ukrainian, "helloпривіт")] {
            XCTAssertTrue(engine.review(input, pair: pair).changes.isEmpty)
            XCTAssertTrue(engine.review(input, pair: pair, direction: .toEnglish).changes.isEmpty)
        }
    }
    func testKeepListMatchesEquivalentUnicodeWithoutIgnoringAccents() {
        XCTAssertTrue(engine.review("resumé", pair: .french, keepWords: ["resume\u{301}"]).changes.isEmpty)
        XCTAssertFalse(engine.review("resume", pair: .french, keepWords: ["résumé"]).changes.isEmpty)
    }
    func testCandidateSurvivesUntickingAndReviewRefresh() {
        let review = engine.review("resume", pair: .french)
        let change = review.changes[0]
        var choices = ReviewChoices(); choices.update(review, preserving: false)
        XCTAssertTrue(choices.selected.isEmpty)
        choices.choose("resumé", for: change)
        choices.setSelected(false, for: change)
        choices.update(review, preserving: true)
        XCTAssertEqual(choices.candidate(for: change), "resumé")
        XCTAssertTrue(choices.selected.isEmpty)
        choices.setSelected(true, for: change)
        XCTAssertEqual(review.applying(choices.selected), "resumé")
        choices.choose("injected rewrite", for: change)
        XCTAssertEqual(choices.candidate(for: change), "resumé")
    }
    func testSuggestedOnlyCannotSelectAmbiguousChanges() {
        let review = engine.review("manana si", pair: .spanish)
        var choices = ReviewChoices(); choices.update(review, preserving: false)
        for change in review.changes { choices.setSelected(true, for: change) }
        choices.selectSuggested(in: review)
        XCTAssertEqual(review.applying(choices.selected), "mañana si")
        choices.deselectAll(); choices.update(review, preserving: true)
        XCTAssertTrue(choices.selected.isEmpty)
        choices.update(review, preserving: false)
        XCTAssertEqual(review.applying(choices.selected), "mañana si")
    }
    func testChangedTextDoesNotInheritAnOldApprovalAtTheSameOffset() {
        var choices = ReviewChoices()
        let old = engine.review("resume", pair: .french)
        choices.update(old, preserving: false); choices.choose("résumé", for: old.changes[0])
        let new = engine.review("si", pair: .spanish)
        choices.update(new, preserving: true)
        XCTAssertTrue(choices.selected.isEmpty)
    }
    func testTransactionUsesUTF16RangesAndRejectsStaleUndo() {
        let original = "👩‍💻 says manana!"
        let range = (original as NSString).range(of: "manana")
        let tx = TextTransaction(before: original, range: range, replacement: "mañana")
        XCTAssertEqual(tx.after, "👩‍💻 says mañana!")
        XCTAssertTrue(tx.canApply(to: original))
        XCTAssertFalse(tx.canApply(to: original + "new edit"))
        XCTAssertTrue(tx.canUndo(current: tx.after!))
        XCTAssertFalse(tx.canUndo(current: tx.after! + "new edit"))
        XCTAssertNil(TextTransaction(before: "hi", range: NSRange(location: 9, length: 1), replacement: "x").after)
        XCTAssertNil(TextTransaction(before: "👋", range: NSRange(location: 1, length: 1), replacement: "x").after)
        XCTAssertNil(TextTransaction(before: "👩‍💻", range: NSRange(location: 0, length: 2), replacement: "x").after)
        XCTAssertNil(TextTransaction(before: "e\u{301}", range: NSRange(location: 0, length: 1), replacement: "x").after)
    }
}
