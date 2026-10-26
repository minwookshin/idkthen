import AppKit
import SwiftUI
import IdkthenCore

/// An ephemeral, local exercise of the same deterministic rules used while typing.
/// It never starts the event tap, requests Accessibility, or invokes the AI model.
@MainActor final class TypingTrial: ObservableObject {
    struct Edit {
        let transaction: TextTransaction
        let beforeSelection: NSRange
        let afterSelection: NSRange
        let word: String
        var after: String { transaction.after! }
    }
    struct Pending {
        let before: String
        let selection: NSRange
        let change: Change
        let word: String
    }
    @Published private(set) var text = ""
    @Published private(set) var status = "Try an example, then press Space."
    @Published private(set) var pending: Pending?
    @Published private var lastEdit: Edit?
    @Published private(set) var generation = 0
    @Published private(set) var didCorrect = false
    @Published private(set) var didUndo = false
    var canUndo: Bool {
        guard let lastEdit else { return false }
        return recovery(lastEdit).plan(current: text, selection: selection) != nil
    }
    var editHandler: ((Edit) -> Void)?
    private var selection = NSRange(location: 0, length: 0)
    private var languages = LanguageSelection([.spanish])
    private var mode = LiveCorrectionMode.automatic
    private var keepWords = Set<String>()
    private var sessionKept = Set<String>()
    private let spelling = MacSpelling()
    private lazy var engine = ReviewEngine(spelling: spelling)

    func configure(languages: LanguageSelection, mode: LiveCorrectionMode, keepWords: Set<String>) {
        guard self.languages != languages || self.mode != mode || self.keepWords != keepWords else { return }
        self.languages = languages; self.mode = mode; self.keepWords = keepWords
        didCorrect = false; didUndo = false
        spelling.clearCache(); cancelPending()
        status = "Type a word, then press Space."
    }
    func cancelPending() {
        if pending != nil || lastEdit != nil { status = "Type a word, then press Space." }
        pending = nil; lastEdit = nil
    }
    func clear() {
        text = ""; selection = NSRange(location: 0, length: 0)
        sessionKept.removeAll(); cancelPending(); generation += 1
        status = "Try an example, then press Space."
    }
    func loadExample() {
        text = Self.example(for: languages)
        selection = NSRange(location: (text as NSString).length, length: 0)
        cancelPending(); generation += 1
        status = "Press Space after the example."
    }
    static func example(for languages: LanguageSelection) -> String {
        let examples: [LanguagePair: String] = [.korean: "chromedptj", .spanish: "manana", .french: "l'ecole",
            .german: "strasse", .portuguese: "amanha", .ukrainian: "ghbdsn", .italian: "perche", .russian: "ghbdtn"]
        let preferred = languages.contains(.korean) ? LanguagePair.korean : languages.partners[0]
        return examples[preferred]!
    }

    /// The caller supplies the native editor's current snapshot, including IME state.
    /// Returned edits are synchronous and must still match that snapshot in the editor.
    @discardableResult func userEdited(_ current: String, selection currentSelection: NSRange,
                                      hasMarkedText: Bool = false, isHistoryChange: Bool = false, isPaste: Bool = false) -> Edit? {
        let previousEdit = lastEdit
        text = current; selection = currentSelection; pending = nil
        if let previousEdit, recovery(previousEdit).recognizesOriginal(in: current) {
            sessionKept.insert(previousEdit.word.lowercased().precomposedStringWithCanonicalMapping)
            lastEdit = nil; didUndo = true
        }
        if isHistoryChange {
            if let previousEdit, TextIdentity.matches(current, previousEdit.transaction.before) {
                sessionKept.insert(previousEdit.word.lowercased())
            }
            status = "History restored. No correction applied."
            lastEdit = nil
            return nil
        }
        guard !isPaste else { status = "Pasted as written. Use text review to check it."; return nil }
        guard !hasMarkedText else { status = "Finish composing before checking."; return nil }
        guard (current as NSString).length <= 4_000 else { status = "Use a shorter example (up to 4,000 characters)."; return nil }
        guard let word = LiveWord.completed(in: current, selection: currentSelection) else {
            status = "Type a word, then press Space."; return nil
        }
        let kept = keepWords.union(sessionKept)
        switch FastTypingPlan.make(word: word, document: current, engine: engine, languages: languages, keepWords: kept) {
        case .skip:
            let review = engine.review(word.text, languages: languages, keepWords: kept)
            status = review.changes.isEmpty ? "Kept as typed." : "Needs your choice. Open text review to see the readings."
            return nil
        case .immediate(let change):
            let proposal = Pending(before: current, selection: currentSelection, change: change, word: word.text)
            if mode == .automatic { return apply(proposal) }
            pending = proposal; status = "Suggestion ready. Apply it when you want."
            return nil
        case .context(let change):
            pending = Pending(before: current, selection: currentSelection, change: change, word: word.text)
            status = "This reading needs context. Choose whether to apply it."
            return nil
        }
    }
    func selectionChanged(text current: String, selection currentSelection: NSRange) {
        // NSTextView can send selection notifications before textDidChange.
        guard TextIdentity.matches(current, text), currentSelection != selection else { return }
        selection = currentSelection; pending = nil
        status = "Type a word, then press Space."
    }
    func accept() -> Edit? {
        guard let pending else { return nil }
        return apply(pending)
    }
    func undo() -> Edit? {
        guard let last = lastEdit, let plan = recovery(last).plan(current: text, selection: selection) else {
            cancelPending(); return nil
        }
        let edit = Edit(transaction: plan.transaction, beforeSelection: selection, afterSelection: plan.selection, word: last.word)
        text = edit.after; selection = edit.afterSelection
        sessionKept.insert(last.word.lowercased()); cancelPending()
        didUndo = true
        status = "Restored. Kept unchanged for this test."
        return edit
    }
    func requestAccept() { if let edit = accept() { editHandler?(edit) } }
    func requestUndo() { if let edit = undo() { editHandler?(edit) } }
    func resetExercise() { clear(); didCorrect = false; didUndo = false }
    private func recovery(_ edit: Edit) -> CorrectionRecovery {
        CorrectionRecovery(transaction: edit.transaction, caretAfter: edit.afterSelection.location)
    }
    private func apply(_ proposal: Pending) -> Edit? {
        guard TextIdentity.matches(text, proposal.before), selection == proposal.selection,
              proposal.change.candidates.count == 1 else { cancelPending(); return nil }
        let transaction = TextTransaction(before: text, range: proposal.change.range, replacement: proposal.change.candidates[0])
        guard let original = transaction.originalSelection, TextIdentity.matches(original, proposal.change.original),
              transaction.after != nil else { cancelPending(); return nil }
        let offset = transaction.replacementRange.length - transaction.range.length
        let edit = Edit(transaction: transaction, beforeSelection: selection,
                        afterSelection: NSRange(location: selection.location + offset, length: 0), word: proposal.word)
        text = edit.after; selection = edit.afterSelection; pending = nil; lastEdit = edit; didCorrect = true
        status = "\(proposal.change.original) → \(proposal.change.candidates[0])"
        return edit
    }
}

private final class TrialTextView: NSTextView {
    private(set) var handlingPaste = false
    override func paste(_ sender: Any?) {
        handlingPaste = true; defer { handlingPaste = false }
        super.paste(sender)
    }
}

/// Native text input preserves selection, IME composition and standard Edit-menu undo.
struct PracticeTextEditor: NSViewRepresentable {
    @ObservedObject var trial: TypingTrial
    func makeCoordinator() -> Coordinator { Coordinator(trial) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = TrialTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        view.isRichText = false; view.allowsUndo = true; view.drawsBackground = false
        view.font = .systemFont(ofSize: 17); view.textColor = .labelColor
        view.textContainerInset = NSSize(width: 2, height: 4)
        view.isAutomaticSpellingCorrectionEnabled = false; view.isContinuousSpellCheckingEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticTextCompletionEnabled = false
        view.isGrammarCheckingEnabled = false
        view.autoresizingMask = [.width]; view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.string = trial.text
        view.setAccessibilityLabel("Typing test")
        context.coordinator.editor = view
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        trial.editHandler = { [weak coordinator] in coordinator?.apply($0) }
        if coordinator.generation != trial.generation {
            coordinator.generation = trial.generation
            coordinator.changing = true
            view.string = trial.text; view.undoManager?.removeAllActions()
            view.setSelectedRange(NSRange(location: (trial.text as NSString).length, length: 0))
            coordinator.changing = false
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }; view.window?.makeFirstResponder(view)
            }
        }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.trial.editHandler = nil
        (scroll.documentView as? NSTextView)?.delegate = nil
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let trial: TypingTrial
        weak var editor: NSTextView?
        var generation = -1
        var changing = false
        init(_ trial: TypingTrial) { self.trial = trial }
        func textDidChange(_ notification: Notification) {
            guard !changing, let view = notification.object as? NSTextView else { return }
            if let edit = trial.userEdited(view.string, selection: view.selectedRange(), hasMarkedText: view.hasMarkedText(),
                                           isHistoryChange: view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true,
                                           isPaste: (view as? TrialTextView)?.handlingPaste == true) {
                apply(edit)
            }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !changing, let view = notification.object as? NSTextView else { return }
            trial.selectionChanged(text: view.string, selection: view.selectedRange())
        }
        func apply(_ edit: TypingTrial.Edit) {
            guard let view = editor else { return }
            guard edit.transaction.canApply(to: view.string), view.selectedRange() == edit.beforeSelection, !view.hasMarkedText() else {
                trial.userEdited(view.string, selection: view.selectedRange(), isHistoryChange: true); return
            }
            changing = true
            view.breakUndoCoalescing()
            view.insertText(edit.transaction.replacement, replacementRange: edit.transaction.range)
            view.setSelectedRange(edit.afterSelection)
            view.breakUndoCoalescing()
            changing = false
            if !TextIdentity.matches(view.string, edit.after) {
                trial.userEdited(view.string, selection: view.selectedRange(), isHistoryChange: true)
            }
        }
    }
}
