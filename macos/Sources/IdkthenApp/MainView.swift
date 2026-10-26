import AppKit
import SwiftUI
import IdkthenCore

private enum Palette {
    static let accent = IdkthenStyle.accent
    static let paper = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.10)
}

struct MainView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    let openLanguages: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Text review").font(IdkthenStyle.headline)
                Spacer()
                Button(action: openLanguages) { Label(model.reviewLanguages.codes, systemImage: "globe").labelStyle(idkthenLabelStyle()).frame(height: IdkthenStyle.controlSize) }
                    .accessibilityLabel("Change review languages")
                Button(action: openSettings) { idkthenSymbol(name: "gearshape", toolbar: true).frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize) }
                    .accessibilityLabel("Settings").help("Settings (⌘,)")
            }.buttonStyle(.plain).font(IdkthenStyle.caption).padding(.horizontal, 24).frame(height: IdkthenStyle.headerHeight)
            ScrollView { workspace }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor)).tint(Palette.accent)
        .frame(minWidth: 780, minHeight: 558).disabled(model.applying)
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.reviewLanguages.nativeNames).font(.system(size: model.reviewLanguages.count > 2 ? 21 : 25, weight: .semibold)).tracking(-0.6)
                    Text(model.reviewLanguages.singlePair?.detail ?? "Write in your enabled languages on the same keyboard. Conflicting readings stay your choice.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 9) {
                    importMenu
                    Menu("Examples") {
                        Button("Mixed-language example") { model.loadExample() }
                        Button("Ambiguous words") { model.loadExample(ambiguous: true) }
                    }.fixedSize().controlSize(.small)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) { inputCard; outputCard }.frame(maxWidth: .infinity)
                changesCard.frame(width: 274)
            }
            Label(model.reviewLanguages.singlePair.map { $0 == .german ? "Missing umlauts and ß. Spellings such as ueber → über need your explicit choice." : ($0.usesAccents ? "Adds missing accents. Existing accents and your wording stay intact." : "Standard layouts only. Use a direction for words the dictionary does not know.") } ?? "All enabled languages are checked together. Words accepted in another language and competing readings need your choice.", systemImage: "text.badge.checkmark")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 24).padding(.bottom, 20)
    }
    private var importMenu: some View {
        Menu {
            if model.permissionGranted {
                Text("Select text in an app, then choose it here.")
                ForEach(model.availableSourceApps, id: \.processIdentifier) { app in
                    Button("From \(app.localizedName ?? "app")") { model.captureSelection(from: app) }
                }
                Divider()
                Button("Refresh app list") { model.refreshSourceApps() }
            } else {
                Button("Set up selection access…", action: openSettings)
            }
        } label: { Label("Import selection", systemImage: "arrow.down.doc") }
            .fixedSize().controlSize(.small).help("Reads only the app you choose, when you choose it. Requires Accessibility access.")
    }
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(model.sourceApp.map { "FROM \($0.uppercased())" } ?? "YOUR TEXT", systemImage: model.sourceApp == nil ? "pencil.line" : "app")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
                Spacer()
                Text("\((model.input as NSString).length) / 4,000").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(14)
            LocalTextEditor(text: $model.input, editable: model.sourceApp == nil, changed: model.textChanged)
                .frame(height: 112).padding(.horizontal, 10)
            if let pair = model.reviewLanguages.singlePair, !pair.usesAccents {
                Picker("Conversion direction", selection: $model.direction) {
                    Text("Detect").tag(ReviewDirection.detect)
                    Text("To \(pair.code)").tag(ReviewDirection.toPartner)
                    Text("To English").tag(ReviewDirection.toEnglish)
                }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.top, 9)
                    .onChange(of: model.direction) { _, _ in model.changeDirection() }
            }
            HStack(spacing: 12) {
                if model.sourceApp != nil { Button("Edit a copy") { model.editCopy() }.help("Review locally without changing the source app.") }
                else { Button("Clear") { model.clear() } }
                Spacer(minLength: 0)
                Button("Review text") { model.analyze() }.keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent).disabled(model.input.isEmpty).help("Review text (⌘Return)")
            }.font(.system(size: 12)).controlSize(.small).padding(14)
        }.card()
    }
    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("RESULT", systemImage: "text.badge.checkmark").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(Palette.accent)
                Spacer()
                Text(model.isCurrent ? "\(model.selectedCount) selected" : (model.canUndoReview ? "Applied" : "Preview")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                if model.input.isEmpty {
                    Text("Your reviewed text will appear here.").foregroundStyle(.secondary).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text(highlightedOutput).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).accessibilityLabel("Reviewed text: \(model.output)")
                }
            }.frame(height: 100)
            Divider()
            HStack(spacing: 9) {
                Button { model.copyResult() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(model.input.isEmpty).keyboardShortcut("c", modifiers: [.command, .shift]).help("Copy result (⇧⌘C)")
                Button { model.undoReview() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo correction (⌘Z)").accessibilityLabel("Undo correction").disabled(!model.canUndoReview)
                Spacer(minLength: 0)
                Button(model.sourceApp.map { "Apply to \($0)" } ?? "Apply changes") { model.apply() }
                    .buttonStyle(.borderedProminent).disabled(!model.hasChanges || !model.isCurrent)
                    .keyboardShortcut(.return, modifiers: [.command, .shift]).help("Apply selected changes (⇧⌘Return)")
            }.controlSize(.small)
        }.padding(14).background(Palette.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.accent.opacity(0.22)))
    }
    private var highlightedOutput: AttributedString {
        guard let review = model.review, model.isCurrent else { return AttributedString(model.input) }
        var result = AttributedString(); let text = review.original as NSString; var position = 0
        for change in review.changes {
            result += AttributedString(text.substring(with: NSRange(location: position, length: change.range.location - position)))
            var part = AttributedString(model.choices[change.id] ?? change.original)
            if model.choices[change.id] != nil { part.foregroundColor = Palette.accent; part.font = .system(size: 15, weight: .semibold); part.underlineStyle = .single }
            result += part; position = NSMaxRange(change.range)
        }
        result += AttributedString(text.substring(from: position)); return result
    }
    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Changes").font(.system(size: 14, weight: .semibold))
                Spacer()
                if model.pendingCount > 0 { Text("\(model.pendingCount) to decide").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange) }
                else { Text("\(model.review?.changes.count ?? 0)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
            }.padding(14)
            Divider()
            if let review = model.review, !review.changes.isEmpty {
                HStack {
                    Button("Suggested only") { model.selectSuggested() }.help("Select only unambiguous suggestions. Leave meaning choices unchecked.")
                    Spacer()
                    Button("Deselect all") { model.deselectAll() }
                }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.horizontal, 14).padding(.vertical, 10)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(review.changes) { change in
                            changeRow(change)
                            if change.id != review.changes.last?.id { Divider().padding(.horizontal, 14) }
                        }
                    }
                }.frame(height: 305)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: model.isError ? "exclamationmark.circle" : (model.isCurrent || model.canUndoReview ? "checkmark.circle" : "text.magnifyingglass")).font(.system(size: 23)).foregroundStyle(Palette.accent)
                    Text(model.isError ? "Review unavailable." : (model.canUndoReview ? "Changes applied." : (model.isCurrent ? "No supported changes." : "Ready when you are."))).font(.system(size: 14, weight: .medium))
                    Text(model.isError ? model.message : (model.canUndoReview ? "Use ⌘Z to restore the original while the text stays unchanged." : (model.isCurrent ? "This checks missing accents and layout mistakes. It does not check grammar." : "Type or paste text, then review the suggested changes.")))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(18).frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            }
            Divider()
            if model.isCurrent && (model.quieterReadingCount > 0 || model.showOtherReadings) {
                Button(model.showOtherReadings ? "Hide other readings" : "Show other readings (\(model.quieterReadingCount))") {
                    model.setShowOtherReadings(!model.showOtherReadings)
                }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(Palette.accent).padding(14)
                Divider()
            }
            Label("\(model.review?.protectedCount ?? 0) kept · links, code, and protected words", systemImage: "hand.raised")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(14)
        }.card()
    }
    private func changeRow(_ change: Change) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 4) {
                Toggle(isOn: Binding(get: { model.decisions.isSelected(change) }, set: { model.setSelected($0, for: change) })) {
                    HStack(spacing: 6) {
                        Text(change.original).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(model.decisions.candidate(for: change)).fontWeight(.semibold)
                    }.font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
                }.toggleStyle(.checkbox).accessibilityLabel("Change \(change.original) to \(model.decisions.candidate(for: change))")
                Spacer(minLength: 0)
                Menu {
                    Button("Always keep “\(change.original)”") { model.keep(change) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                    .accessibilityLabel("Options for \(change.original)")
            }
            if change.candidates.count > 1 {
                Picker("Alternative", selection: Binding(get: { model.decisions.candidate(for: change) }, set: { model.choose(change, $0) })) {
                    ForEach(change.candidates, id: \.self) { Text($0).tag($0) }
                }.controlSize(.small).accessibilityLabel("Alternatives for \(change.original)")
            }
            HStack {
                Label(change.ambiguous ? "Your choice" : "Suggested", systemImage: change.ambiguous ? "questionmark.circle" : "checkmark.circle")
                    .foregroundStyle(change.ambiguous ? Color.orange : Palette.accent)
                Spacer()
                Text(change.languages.map(\.code).joined(separator: " · ")).foregroundStyle(.secondary)
            }.font(.system(size: 10, weight: .medium)).help(change.reason)
            if change.requiresExplicitChoice {
                Text(change.reason).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let context = context(for: change) {
                Text(context).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(2)
            }
        }.padding(14)
    }
    private func context(for change: Change) -> String? {
        guard let review = model.review, review.original.trimmingCharacters(in: .whitespacesAndNewlines) != change.original,
              let range = Range(change.range, in: review.original) else { return nil }
        let text = review.original
        let start = text.index(range.lowerBound, offsetBy: -22, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 22, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end].replacingOccurrences(of: "\n", with: " ") + (end < text.endIndex ? "…" : "")
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if model.applying { ProgressView().controlSize(.mini) }
                else { Image(systemName: model.isError ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(model.isError ? Color.orange : Palette.accent) }
                Text(model.message.isEmpty ? (model.shortcutEnabled ? "Selection shortcut ready · \(model.shortcutChoice.label)" : "Ready · Paste text or import a selection") : model.message)
                    .font(.system(size: 11)).foregroundStyle(model.isError ? Color.orange : .secondary).lineLimit(3)
                Spacer(minLength: 4)
                if model.lastKeptWord != nil { Button("Undo keep") { model.undoKeep() }.font(.system(size: 11)) }
                if model.canUndoReview { Button("Undo correction") { model.undoReview() }.font(.system(size: 11)) }
                else if model.canRedo { Button("Redo correction") { model.redo() }.font(.system(size: 11)) }
            }.padding(.horizontal, 24).padding(.vertical, 12).frame(minHeight: 42)
        }
    }
}

private extension View {
    func card() -> some View { background(Palette.paper, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line)) }
}

struct LocalTextEditor: NSViewRepresentable {
    @Binding var text: String
    let editable: Bool
    let changed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = NSTextView()
        view.isRichText = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false; view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false; view.isAutomaticTextReplacementEnabled = false
        view.isGrammarCheckingEnabled = false; view.isAutomaticTextCompletionEnabled = false
        view.allowsUndo = true; view.drawsBackground = false
        view.font = .systemFont(ofSize: 15); view.textColor = .labelColor
        view.textContainerInset = NSSize(width: 4, height: 4)
        view.autoresizingMask = [.width]; view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.string = text
        view.setAccessibilityLabel("Text to review")
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if !TextIdentity.matches(view.string, text) { view.string = text; view.undoManager?.removeAllActions() }
        view.isEditable = editable
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LocalTextEditor
        init(_ parent: LocalTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string; parent.changed()
        }
    }
}
