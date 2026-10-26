import SwiftUI

struct ProductHelpView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var support: ProductSupport

    var body: some View {
        Form {
            Section {
                LabeledContent("idkthen", value: support.version)
                Text("Preview · check the website for release status.")
                    .font(IdkthenStyle.caption).foregroundStyle(.secondary)
            }
            Section("If Typing Does Not Change") {
                Text("1. Allow Accessibility in System Settings.\n2. Add the app under Apps and turn on While You Type.\n3. Type in a multiline text area and finish with Space.")
                    .font(IdkthenStyle.caption).fixedSize(horizontal: false, vertical: true)
                Text("Password fields, search bars, single-line fields and protected editors are skipped. Some apps do not expose editable text. Use Review Text from More when needed.")
                    .font(IdkthenStyle.caption).foregroundStyle(.secondary)
            }
            Section {
                Link("Help & Release Status", destination: URL(string: "https://pairtype-preview.yeyen17.chatgpt.site/help.html")!)
                Link("Contact Support…", destination: URL(string: "mailto:im.minwookshin@gmail.com?subject=idkthen%20support")!)
                Button("Save Diagnostic Report…") { support.saveDiagnostics(model.supportReport) }.foregroundStyle(.blue)
            } footer: {
                Text("Only version, permission status and setting counts. No typed text, learned words, app names or account details. You choose whether to share the file.")
                    .font(IdkthenStyle.caption)
            }
            Section("Privacy & Removal") {
                Text("Correction runs on this Mac. Language choices, enabled apps and kept words are stored locally. There is no account or background upload.")
                Text("To stop using idkthen, turn off Settings → Open at Login, quit from the menu bar, remove it from Applications and revoke Accessibility. Forget learned words in Settings → Words to Keep.")
            }.font(IdkthenStyle.caption)
            if let message = support.message { Section { Text(message).font(IdkthenStyle.caption) } }
        }.onAppear { support.refresh(); model.refreshPermission() }
    }
}

struct LoginSettingsSection: View {
    @ObservedObject var support: ProductSupport

    var body: some View {
        Section {
            Toggle("Open at Login", isOn: Binding(get: { support.loginEnabled }, set: support.setLoginEnabled))
                .toggleStyle(.switch).tint(.green).controlSize(.regular)
                .frame(minHeight: IdkthenStyle.rowHeight)
                .disabled(!support.installed && !support.loginEnabled)
            if support.loginStatus == .requiresApproval {
                Button("Open Login Items…", action: support.openLoginSettings).foregroundStyle(.blue)
            }
        } footer: {
            Text(support.loginMessage ?? support.loginDescription).font(IdkthenStyle.caption)
        }.onAppear { support.refresh() }
    }
}
