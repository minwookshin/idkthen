import AppKit
import SwiftUI
import IdkthenCore

enum PanelPage {
    case home, languages, apps, appLanguages, settings, words, shortcut, practice, setup, help
    var title: String {
        switch self {
        case .home: "idkthen"
        case .languages: "Default Languages"
        case .apps: "Apps"
        case .appLanguages: "App Languages"
        case .settings: "Settings"
        case .words: "Words to Keep"
        case .shortcut: "Keyboard Shortcuts"
        case .practice: "Try Typing"
        case .setup: "Getting Started"
        case .help: "Help & About"
        }
    }
}

@MainActor final class PanelNavigation: ObservableObject {
    @Published var page: PanelPage = .home
    @Published var appBundle: String?
    @Published var trialAppBundle: String?
}

/// Native grouped forms follow iOS Settings patterns, adapted to a small Mac popover.
struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: PanelNavigation
    @StateObject private var trial = TypingTrial()
    let openReview: () -> Void
    let closePanel: () -> Void
    @State private var actionError: String?
    @State private var setupApp: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch navigation.page {
                case .home: home
                case .languages: Form { languageSection(model.languages) { model.toggleLanguage($0) } }
                case .apps: apps
                case .appLanguages: appLanguages
                case .settings: settings
                case .words: words
                case .shortcut: shortcut
                case .practice: practice
                case .setup: setup
                case .help: ProductHelpView(model: model, support: model.productSupport)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden).font(IdkthenStyle.body).labelStyle(idkthenLabelStyle())
            if let actionError {
                Text(actionError).font(IdkthenStyle.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(16)
            }
        }
        .frame(width: IdkthenStyle.panelWidth, height: panelHeight)
        .background(Color(nsColor: .windowBackgroundColor)).tint(IdkthenStyle.accent)
        .disabled(model.applying)
        .onAppear {
            configureTrial()
            if navigation.page == .setup, model.setupStep == .practice, trial.text.isEmpty { trial.loadExample() }
        }
        .onChange(of: navigation.page) { _, _ in actionError = nil; trial.cancelPending(); configureTrial() }
        .onChange(of: model.languages) { _, _ in configureTrial() }
        .onChange(of: model.appLanguages) { _, _ in configureTrial() }
        .onChange(of: model.liveMode) { _, _ in configureTrial() }
        .onChange(of: model.keepWords) { _, _ in configureTrial() }
        .onChange(of: model.setupStep) { _, step in
            if step == .practice { configureTrial(); if trial.text.isEmpty { trial.loadExample() } }
        }
    }
    private var panelHeight: CGFloat {
        switch navigation.page {
        case .home: (model.permissionGranted && !model.liveApps.isEmpty ? 310 : 358) + (model.canUndo || model.lastRestoredWord != nil ? 112 : 0)
        case .languages: 510
        case .apps: min(460, 230 + CGFloat(model.liveApps.count) * 44)
        case .appLanguages: (navigation.appBundle.flatMap { model.appLanguages[$0] } == nil ? 288 : 594) + (model.liveEnabled ? 70 : 0)
        case .settings: model.permissionGranted ? 610 : 650
        case .help: 550
        case .words: model.learnedWords.isEmpty ? 324 : min(480, 354 + CGFloat(model.learnedWords.count) * 44)
        case .shortcut: model.permissionGranted ? 420 : 470
        case .practice: 486
        case .setup: model.setupStep == .languages ? 610 : (model.setupStep == .practice ? 500 : 490)
        }
    }
    private var parent: PanelPage {
        switch navigation.page {
        case .words, .shortcut, .help: .settings
        case .appLanguages: model.setupStep == .done ? .apps : .setup
        case .practice: navigation.trialAppBundle == nil ? .home : .appLanguages
        default: .home
        }
    }
    private var header: some View {
        HStack {
            if navigation.page == .home {
                Menu {
                    Button("Try Typing") { navigation.trialAppBundle = nil; navigation.page = .practice }
                    Button("Review Text…", action: openReview)
                    if let bundle = model.currentAppBundle, let name = model.liveApps[bundle], model.liveEnabled {
                        Divider()
                        Button(model.pausedApps.contains(bundle) ? "Resume in \(name)" : "Pause \(name) for 10 Minutes") {
                            if model.pausedApps.contains(bundle) { model.resumeApp(bundle) } else { model.pauseApp(bundle) }
                        }
                    }
                    Divider()
                    Button("Getting Started") { trial.resetExercise(); model.startSetup(); navigation.page = .setup }
                    Button("Clear Session") { model.clear(); trial.clear() }
                    Button("Quit idkthen") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { IdkthenStyle.menuIcon("ellipsis.circle").frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.large).fixedSize().accessibilityLabel("More options")
            } else if navigation.page == .setup {
                if model.setupStep != .languages {
                    Button { goBackInSetup() } label: {
                        idkthenSymbol(name: "chevron.left", toolbar: true).frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize)
                    }.buttonStyle(.plain).accessibilityLabel("Previous step")
                } else { Color.clear.frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize) }
            } else {
                Button { navigation.page = parent } label: {
                    idkthenSymbol(name: "chevron.left", toolbar: true).frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize)
                }.buttonStyle(.plain).accessibilityLabel("Back")
            }
            Spacer()
            if navigation.page == .home {
                Button { navigation.page = .settings; model.refreshPermission() } label: {
                    idkthenSymbol(name: "gearshape", toolbar: true).frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize)
                }.buttonStyle(.plain).accessibilityLabel("Settings").help("Settings (⌘,)")
            } else if navigation.page == .setup {
                Button("Later") { model.setSetupStep(.done); navigation.page = .home }
                    .buttonStyle(.plain).font(IdkthenStyle.caption).frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize)
            } else if navigation.page == .appLanguages, let bundle = navigation.appBundle {
                Menu {
                    Button("Try These Languages") { navigation.trialAppBundle = bundle; navigation.page = .practice }
                    Divider()
                    Button("Remove App", role: .destructive) { model.removeLiveApp(bundle); navigation.page = .apps }
                } label: { IdkthenStyle.menuIcon("ellipsis.circle").frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.large).fixedSize().accessibilityLabel("App options")
            } else if navigation.page == .words, model.hasUndoMemory {
                Menu {
                    Button("Reset Learned Words", role: .destructive) { model.forgetAllLearnedWords() }
                } label: { IdkthenStyle.menuIcon("ellipsis.circle").frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.large).fixedSize().accessibilityLabel("Learned word options")
            } else { Color.clear.frame(width: IdkthenStyle.controlSize, height: IdkthenStyle.controlSize) }
        }
        .foregroundStyle(.blue)
        .overlay {
            Text(navigation.page == .setup ? model.setupStep.title : (navigation.page == .appLanguages ? (navigation.appBundle.flatMap { model.liveApps[$0] } ?? "App Languages") : navigation.page.title))
                .font(IdkthenStyle.headline).foregroundStyle(.primary).lineLimit(1).frame(maxWidth: 230).allowsHitTesting(false)
        }.padding(.horizontal, 8).frame(height: IdkthenStyle.headerHeight)
    }
    private var home: some View {
        Form {
            Section {
                switchRow("While You Type", detail: readiness, isOn: Binding(get: { model.liveRequested }, set: { value in perform { model.setLiveEnabled(value) } }))
                    .disabled(!model.liveRequested && (!model.permissionGranted || model.liveApps.isEmpty))
                if !model.permissionGranted { actionRow("Set Up Access", symbol: "lock.open") { navigation.page = .settings } }
                else if model.liveApps.isEmpty { actionRow("Choose an App", symbol: "app") { navigation.page = .apps } }
            } footer: { Text(model.homeStatus).font(IdkthenStyle.caption).accessibilityLabel("Typing status: \(model.homeStatus)") }
            Section {
                navigationRow("Languages", detail: model.languages.codes, symbol: "globe", page: .languages)
                navigationRow("Apps", detail: appSummary, symbol: "app", page: .apps)
            }
            if model.canUndo {
                Section { actionRow("Undo Last Correction", symbol: "arrow.uturn.backward") { perform { model.undo() } } }
                footer: { Text(model.bridge.hasLiveUndo && model.undoShortcutEnabled
                    ? "Try \(model.undoShortcutChoice.label) in the original field, or use this button."
                    : "Restore the most recent idkthen correction.").font(IdkthenStyle.caption) }
            } else if let word = model.lastRestoredWord {
                Section { actionRow("Always Keep “\(word)”", symbol: "hand.raised") { model.keepRestoredSpelling() } }
                footer: { Text("Keep this spelling across apps, including after restart.").font(IdkthenStyle.caption) }
            }
        }
    }
    private func languageSection(_ selection: LanguageSelection, toggle: @escaping (LanguagePair) -> Void) -> some View {
        Section {
            HStack(spacing: IdkthenStyle.rowSpacing) {
                Text("English"); Spacer()
                Text("Always On").font(IdkthenStyle.caption).foregroundStyle(.secondary)
                idkthenSymbol(name: "checkmark").foregroundStyle(.blue)
            }.frame(minHeight: IdkthenStyle.rowHeight).accessibilityElement(children: .combine)
            ForEach(LanguagePair.allCases) { language in
                let selected = selection.contains(language)
                Button { toggle(language) } label: {
                    HStack(spacing: IdkthenStyle.rowSpacing) {
                        Text(language.language); Spacer()
                        Text(language.code).font(IdkthenStyle.caption).foregroundStyle(.secondary)
                        idkthenSymbol(name: "checkmark").foregroundStyle(.blue).opacity(selected ? 1 : 0)
                    }.frame(minHeight: IdkthenStyle.rowHeight).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!selection.canToggle(language))
                    .accessibilityLabel(language.language).accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        } header: { Text("\(selection.count) of 4 selected").font(IdkthenStyle.caption) }
        footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(selection.count == 4 ? "Remove one to add another." : "English plus up to three languages.")
                if selection.contains(.korean) { Text("Korean uses standard two-set keys. Three-set and custom layouts need separate support.") }
                if selection.contains(.russian) { Text("Russian uses PC letter positions, not phonetic typing.") }
                if selection.contains(.ukrainian) { Text("Ukrainian needs a reliable system dictionary; otherwise use text review.") }
            }.font(IdkthenStyle.caption)
        }
    }
    private var apps: some View {
        Form {
            Section {
                if model.liveApps.isEmpty { Text("No apps enabled").foregroundStyle(.secondary) }
                ForEach(model.liveApps.keys.sorted(), id: \.self) { bundle in
                    Button { navigation.appBundle = bundle; navigation.page = .appLanguages } label: {
                        HStack(spacing: IdkthenStyle.rowSpacing) {
                            Text(model.liveApps[bundle] ?? bundle).lineLimit(1); Spacer()
                            Text(model.appLanguages[bundle]?.codes ?? "Default").font(IdkthenStyle.caption).foregroundStyle(.secondary).lineLimit(1)
                            idkthenDisclosure()
                        }.frame(minHeight: IdkthenStyle.rowHeight).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Section {
                Menu {
                    let available = model.availableSourceApps.filter { model.liveApps[$0.bundleIdentifier ?? ""] == nil }
                    if available.isEmpty { Text("Open an app to add it here.") }
                    ForEach(available, id: \.processIdentifier) { app in Button(app.localizedName ?? "App") { model.addLiveApp(app) } }
                    Divider(); Button("Refresh Running Apps") { model.refreshSourceApps() }
                } label: { Label("Add an App…", systemImage: "plus").frame(maxWidth: .infinity, minHeight: IdkthenStyle.rowHeight, alignment: .leading) }
                    .menuStyle(.borderlessButton).foregroundStyle(.blue)
            } footer: { Text("Only enabled apps are checked. Password fields and code editors are skipped.").font(IdkthenStyle.caption) }
        }
    }
    private var appLanguages: some View {
        Form {
            if let bundle = navigation.appBundle, model.liveApps[bundle] != nil {
                Section {
                    switchRow("Use Default Languages", isOn: Binding(get: { model.appLanguages[bundle] == nil }, set: { useDefault in
                        model.setAppLanguages(useDefault ? nil : model.languages, for: bundle)
                    }))
                } footer: {
                    Text(model.appLanguages[bundle] == nil ? "Follows \(model.languages.codes)." : "Used only in this app.").font(IdkthenStyle.caption)
                }
                Section {
                    actionRow("Open \(model.liveApps[bundle] ?? "App")", symbol: "arrow.up.forward.app") {
                        closePanel(); model.openLiveApp(bundle)
                    }
                    if model.liveEnabled {
                        actionRow(model.pausedApps.contains(bundle) ? "Resume in This App" : "Pause for 10 Minutes", symbol: "pause.circle") {
                            if model.pausedApps.contains(bundle) { model.resumeApp(bundle) } else { model.pauseApp(bundle) }
                        }
                    }
                } footer: { if model.liveEnabled { Text(model.connectionStatus(for: bundle).message).font(IdkthenStyle.caption) } }
                if let selection = model.appLanguages[bundle] { languageSection(selection) { model.toggleAppLanguage($0, for: bundle) } }
            }
        }
    }
    private var settings: some View {
        Form {
            LoginSettingsSection(support: model.productSupport)
            Section {
                Picker("Correction", selection: Binding(get: { model.liveMode }, set: model.setLiveMode)) {
                    Text("Automatic").tag(LiveCorrectionMode.automatic)
                    Text("Suggest").tag(LiveCorrectionMode.suggest)
                }.pickerStyle(.segmented)
                switchRow("On-Device Context", isOn: Binding(get: { model.contextEnabled }, set: model.setContextEnabled))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.liveMode == .automatic ? "Clear corrections apply after Space. Valid words and uncertain readings stay your choice." : "Corrections wait for you to apply them.")
                    if model.contextEnabled { Text(model.contextStatus) }
                }.font(IdkthenStyle.caption)
            }
            Section {
                navigationRow("Words to Keep", detail: "\(model.keepWords.count)", symbol: "hand.raised", page: .words)
                navigationRow("Keyboard Shortcuts", detail: model.undoShortcutEnabled ? model.undoShortcutChoice.label : "", symbol: "command", page: .shortcut)
                navigationRow("Help & About", detail: "", symbol: "questionmark.circle", page: .help)
            }
            Section {
                HStack { Text("Accessibility"); Spacer(); Text(model.permissionGranted ? "Allowed" : "Needed").font(IdkthenStyle.caption).foregroundStyle(.secondary) }.frame(minHeight: IdkthenStyle.rowHeight)
                if !model.permissionGranted { actionRow("Allow Access…", symbol: "arrow.up.forward.app") { model.bridge.requestPermission() } }
            } footer: { Text("Text and learned words stay on this Mac.").font(IdkthenStyle.caption) }
        }
    }
    private var words: some View {
        Form {
            Section {
                TextField("Names and terms, separated by commas", text: $model.keepList, axis: .vertical)
                    .labelsHidden().textFieldStyle(.plain).multilineTextAlignment(.leading).lineLimit(2...4).accessibilityLabel("Words to keep")
                    .onChange(of: model.keepList) { _, _ in model.saveKeepWords(); model.analyze() }
            } header: { Text("Always Keep").font(IdkthenStyle.caption) }
            Section {
                switchRow("Learn From Undo", isOn: Binding(get: { model.learningEnabled }, set: model.setLearningEnabled))
            } footer: { Text("Undo the same word in 3 separate corrections to keep it across apps. Saved words remain when learning is off.").font(IdkthenStyle.caption) }
            if !model.learnedWords.isEmpty {
                Section {
                    ForEach(model.learnedWords, id: \.self) { word in
                        HStack {
                            Text(word).lineLimit(2); Spacer()
                            Button("Forget") { model.forgetLearnedWord(word) }.buttonStyle(.borderless).foregroundStyle(.blue)
                                .font(IdkthenStyle.caption).accessibilityLabel("Forget \(word)")
                        }.frame(minHeight: IdkthenStyle.rowHeight)
                    }
                } header: { Text("Learned").font(IdkthenStyle.caption) }
            }
        }
    }
    private var shortcut: some View {
        Form {
            Section {
                switchRow("Undo Recent Correction", isOn: Binding(get: { model.undoShortcutEnabled }, set: model.setUndoShortcutEnabled))
                Picker("Undo shortcut", selection: Binding(get: { model.undoShortcutChoice }, set: model.setUndoShortcut)) {
                    ForEach(UndoShortcutChoice.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).disabled(!model.undoShortcutEnabled)
            } footer: {
                Text("Available for 2 minutes after a live correction. Keeps your next words. If unavailable, an Undo button appears.").font(IdkthenStyle.caption)
            }
            Section {
                switchRow("Review Selected Text", isOn: Binding(get: { model.shortcutEnabled }, set: { _ in perform { model.enableShortcut() } }))
                    .disabled(!model.permissionGranted && !model.shortcutEnabled)
                Picker("Shortcut", selection: Binding(get: { model.shortcutChoice }, set: { value in perform { model.setShortcut(value) } })) {
                    ForEach(ShortcutChoice.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().pickerStyle(.segmented)
            } footer: { Text("Starts off at launch. Choose another shortcut if it conflicts with VoiceOver or an app.").font(IdkthenStyle.caption) }
            if !model.permissionGranted { Section { actionRow("Set Up Access", symbol: "lock.open") { navigation.page = .settings } } }
        }
    }
    private var practice: some View {
        Form {
            Section { PracticeTextEditor(trial: trial).frame(height: 100).accessibilityLabel("Typing test") }
            header: {
                HStack {
                    Text(model.languages(for: navigation.trialAppBundle).codes); Spacer()
                    Text(model.liveMode == .automatic ? "Automatic" : "Suggest")
                }.font(IdkthenStyle.caption)
            } footer: { Text(navigation.trialAppBundle.flatMap { model.liveApps[$0] }.map { "\($0) languages. Type a word, then Space." } ?? "Type a word, then Space.").font(IdkthenStyle.caption) }
            Section {
                Text(trial.status).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                if let pending = trial.pending { Button("Apply “\(pending.change.candidates[0])”") { trial.requestAccept() }.foregroundStyle(.blue) }
                if trial.canUndo { Button("Undo Correction") { trial.requestUndo() }.foregroundStyle(.blue).keyboardShortcut("z", modifiers: [.control, .shift]) }
                HStack {
                    Button("Use Example") { trial.loadExample() }; Spacer()
                    Button("Clear") { trial.clear() }.disabled(trial.text.isEmpty)
                }.buttonStyle(.borderless).font(IdkthenStyle.caption).foregroundStyle(.blue)
                if navigation.page != .setup {
                    actionRow("Review This Text…", symbol: "text.magnifyingglass") {
                        model.reviewLocalText(trial.text, for: navigation.trialAppBundle); openReview()
                    }.disabled(trial.text.isEmpty)
                }
            } footer: { Text("No AI, app access or word learning in this test.").font(IdkthenStyle.caption) }
        }
    }
    private var setup: some View {
        VStack(spacing: 0) {
            Text("\(model.setupStep.number) of 4").font(IdkthenStyle.caption).foregroundStyle(.secondary).padding(.top, 4)
            Group {
                switch model.setupStep {
                case .languages: Form { languageSection(model.languages) { model.toggleLanguage($0) } }
                case .practice: practice
                case .apps:
                    Form {
                        Section {
                            ForEach(model.liveApps.keys.sorted(), id: \.self) { bundle in
                                Button { setupApp = bundle } label: {
                                    HStack {
                                        Text(model.liveApps[bundle] ?? bundle); Spacer()
                                        idkthenSymbol(name: "checkmark").foregroundStyle(.blue).opacity(selectedSetupApp == bundle ? 1 : 0)
                                    }.frame(minHeight: IdkthenStyle.rowHeight).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityValue(selectedSetupApp == bundle ? "Selected for connection test" : "Enabled")
                            }
                            Menu("Add an App…") {
                                ForEach(model.availableSourceApps.filter { model.liveApps[$0.bundleIdentifier ?? ""] == nil }, id: \.processIdentifier) { app in
                                    Button(app.localizedName ?? "App") { model.addLiveApp(app); setupApp = app.bundleIdentifier }
                                }
                                Button("Refresh Running Apps") { model.refreshSourceApps() }
                            }.menuStyle(.borderlessButton).foregroundStyle(.blue)
                        } footer: { Text("Choose an app for the connection test. Only apps in this list can be checked while you type.").font(IdkthenStyle.caption) }
                    }
                case .verify:
                    Form {
                        Section {
                            Label(model.permissionGranted ? "Accessibility allowed" : "Accessibility needed", systemImage: model.permissionGranted ? "checkmark.circle" : "lock")
                            if !model.permissionGranted { Button("Allow Access…") { model.bridge.requestPermission() }.foregroundStyle(.blue) }
                            else if !model.liveEnabled { Button("Turn On While You Type") { perform { model.setLiveEnabled(true) } }.foregroundStyle(.blue) }
                            if let bundle = selectedSetupApp {
                                Button("Open \(model.liveApps[bundle] ?? "App")") { model.openLiveApp(bundle); closePanel() }.foregroundStyle(.blue)
                            }
                        } footer: {
                            Text("In a message or document, type “\(TypingTrial.example(for: model.languages(for: selectedSetupApp)))” and press Space. In Suggest mode, apply it. Return here after it changes.").font(IdkthenStyle.caption)
                        }
                        Section {
                            Label(connectionVerified ? "Correction confirmed in your app" : "Waiting for a correction in your app", systemImage: connectionVerified ? "checkmark.circle.fill" : "circle.dotted")
                                .foregroundStyle(connectionVerified ? .primary : .secondary)
                            if !connectionVerified {
                                Text(model.connectionStatus(for: selectedSetupApp).message).font(IdkthenStyle.caption)
                            }
                            Text(model.undoShortcutEnabled ? "Undo a recent live correction with \(model.undoShortcutChoice.label). You can keep typing first." : "Use the Undo button to restore the original word.").font(IdkthenStyle.caption)
                        }
                    }
                case .done: EmptyView()
                }
            }
            VStack(spacing: 8) {
                if model.setupStep == .practice {
                    Text(trial.didUndo ? "Original restored. Ready to connect an app." : (trial.didCorrect ? "Try Undo Correction before continuing." : "Press Space to try the correction."))
                        .font(IdkthenStyle.caption).foregroundStyle(.secondary)
                }
                Button(model.setupStep == .verify ? "Finish" : "Continue") { advanceSetup() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!canAdvanceSetup)
                    .frame(maxWidth: .infinity)
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
    }
    private var selectedSetupApp: String? { setupApp.flatMap { model.liveApps[$0] == nil ? nil : $0 } ?? model.liveApps.keys.sorted().first }
    private var connectionVerified: Bool { model.verifiedApp != nil && model.verifiedApp == selectedSetupApp }
    private var canAdvanceSetup: Bool {
        switch model.setupStep {
        case .languages: true
        case .practice: trial.didCorrect && trial.didUndo
        case .apps: selectedSetupApp != nil
        case .verify: connectionVerified
        case .done: false
        }
    }
    private func advanceSetup() {
        guard canAdvanceSetup else { return }
        switch model.setupStep {
        case .languages: navigation.trialAppBundle = nil; model.setSetupStep(.practice)
        case .practice: model.refreshSourceApps(); model.setSetupStep(.apps)
        case .apps: model.setSetupStep(.verify)
        case .verify: model.setSetupStep(.done); navigation.page = .home
        case .done: break
        }
    }
    private func goBackInSetup() {
        switch model.setupStep {
        case .practice: model.setSetupStep(.languages)
        case .apps: model.setSetupStep(.practice)
        case .verify: model.setSetupStep(.apps)
        default: break
        }
    }
    private var readiness: String {
        if !model.permissionGranted { return "Accessibility needed" }
        if model.liveApps.isEmpty { return "Choose an app to start" }
        if model.liveRequested && !model.liveEnabled { return "Connection needed" }
        if model.liveEnabled, let bundle = model.currentAppBundle, model.pausedApps.contains(bundle) { return "Paused in \(model.liveApps[bundle] ?? "this app")" }
        return model.liveEnabled ? (model.liveMode == .automatic ? "Automatic" : "Suggestions") : "Paused"
    }
    private var appSummary: String { model.liveApps.isEmpty ? "None" : (model.liveApps.count == 1 ? model.liveApps.values.first! : "\(model.liveApps.count) apps") }
    private func switchRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title); if let detail { Text(detail).font(IdkthenStyle.caption).foregroundStyle(.secondary) }
            }.accessibilityHidden(true)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).tint(.green).controlSize(.regular).accessibilityLabel(title).accessibilityHint(detail ?? "")
        }.frame(minHeight: detail == nil ? IdkthenStyle.rowHeight : IdkthenStyle.detailRowHeight)
    }
    private func navigationRow(_ title: String, detail: String, symbol: String, page: PanelPage) -> some View {
        Button {
            navigation.page = page
            if page == .apps { model.refreshSourceApps() }
        } label: {
            HStack(spacing: IdkthenStyle.rowSpacing) {
                idkthenSymbol(name: symbol).foregroundStyle(.blue)
                Text(title); Spacer(minLength: 4)
                if !detail.isEmpty { Text(detail).font(IdkthenStyle.caption).foregroundStyle(.secondary).lineLimit(1) }
                idkthenDisclosure()
            }.frame(minHeight: IdkthenStyle.rowHeight).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(detail.isEmpty ? title : "\(title), \(detail)")
    }
    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: IdkthenStyle.rowHeight, alignment: .leading).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.blue)
    }
    private func configureTrial() { trial.configure(languages: model.languages(for: navigation.trialAppBundle), mode: model.liveMode, keepWords: model.keepWords) }
    private func perform(_ action: () -> Void) { actionError = nil; action(); if model.isError { actionError = model.message } }
}
