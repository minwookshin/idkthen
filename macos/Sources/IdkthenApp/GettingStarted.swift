import Foundation

enum SetupStep: String, CaseIterable {
    case languages, practice, apps, verify, done
    var title: String {
        switch self {
        case .languages: "Choose Your Languages"
        case .practice: "Try a Correction"
        case .apps: "Choose Your Apps"
        case .verify: "Connect an App"
        case .done: "idkthen"
        }
    }
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}
