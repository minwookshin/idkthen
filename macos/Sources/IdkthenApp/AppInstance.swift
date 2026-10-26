import AppKit

@MainActor enum AppInstance {
    static let conflictMessage = "Another idkthen or PairType copy is running. Quit the other copy to resume here."
    static var hasOtherCopy: Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // PairType retains this identity during migration, including old builds
        // that do not know how to coordinate with idkthen.
        return NSRunningApplication.runningApplications(withBundleIdentifier: "dev.pairtype.preview")
            .contains { $0.processIdentifier != ownPID && !$0.isTerminated }
    }
}
