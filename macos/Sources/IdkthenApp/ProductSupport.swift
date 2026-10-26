import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// User-initiated product utilities. No polling, network requests or automatic registration.
@MainActor final class ProductSupport: ObservableObject {
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var message: String?
    @Published private(set) var loginMessage: String?

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "Development") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }
    var loginEnabled: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    var installed: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
    var loginDescription: String {
        if !installed { return "Move idkthen to Applications before enabling this." }
        switch loginStatus {
        case .enabled: return "Opens quietly in the menu bar when you log in."
        case .requiresApproval: return "Approve idkthen in System Settings → Login Items."
        case .notFound: return "macOS could not find this app. Reopen it from Applications."
        case .notRegistered: return "Off. idkthen opens only when you launch it."
        @unknown default: return "Check Login Items in System Settings."
        }
    }
    func refresh() { loginStatus = SMAppService.mainApp.status }
    func setLoginEnabled(_ enabled: Bool) {
        loginMessage = nil
        guard installed || !enabled else { loginMessage = loginDescription; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { loginMessage = "macOS could not change this setting. Check Login Items and try again." }
        refresh()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func saveDiagnostics(_ report: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "idkthen-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.message = "Contains version, permissions and setting counts. No typed text, words, app names or account details. Nothing is sent."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try report.write(to: url, atomically: true, encoding: .utf8); self?.message = "Report saved. Nothing was sent." }
            catch { self?.message = "Could not save the report. Choose another location." }
        }
    }
}

/// Explicit allowlist: never accept a text buffer, bundle ID list or word collection here.
struct SupportReport {
    let version: String
    let system: String
    let architecture: String
    let installed: Bool
    let accessibility: Bool
    let liveEnabled: Bool
    let automatic: Bool
    let contextEnabled: Bool
    let languageCodes: String
    let appCount: Int
    let customProfileCount: Int
    let keptWordCount: Int
    let learnedWordCount: Int

    var text: String {
        """
        idkthen diagnostics
        Version: \(version)
        macOS: \(system)
        Architecture: \(architecture)
        In Applications: \(installed)
        Accessibility trusted: \(accessibility)
        While You Type: \(liveEnabled)
        Correction: \(automatic ? "Automatic" : "Suggest")
        On-device context setting: \(contextEnabled)
        Languages: \(languageCodes)
        Enabled app count: \(appCount)
        Custom language profile count: \(customProfileCount)
        Kept word count: \(keptWordCount)
        Learned word count: \(learnedWordCount)

        This report contains no typed text, learned words, app names, paths, user identifiers or clipboard content.
        No report is sent automatically. Review this file before sharing it.
        Local diagnostics do not certify external app compatibility or distribution signing.
        """
    }
}
