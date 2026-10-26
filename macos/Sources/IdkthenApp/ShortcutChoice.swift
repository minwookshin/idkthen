import Carbon

enum ShortcutChoice: String, CaseIterable, Identifiable {
    case controlOptionSpace, controlShiftSpace, commandShiftJ
    var id: String { rawValue }
    var label: String {
        switch self {
        case .controlOptionSpace: "⌃⌥Space"
        case .controlShiftSpace: "⌃⇧Space"
        case .commandShiftJ: "⌘⇧J"
        }
    }
    var keyCode: UInt32 { UInt32(self == .commandShiftJ ? kVK_ANSI_J : kVK_Space) }
    var modifiers: UInt32 {
        switch self {
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .controlShiftSpace: UInt32(controlKey | shiftKey)
        case .commandShiftJ: UInt32(cmdKey | shiftKey)
        }
    }
}

enum UndoShortcutChoice: String, CaseIterable, Identifiable {
    case controlShiftZ, commandOptionZ, controlOptionZ
    var id: String { rawValue }
    var label: String {
        switch self { case .controlShiftZ: "⌃⇧Z"; case .commandOptionZ: "⌘⌥Z"; case .controlOptionZ: "⌃⌥Z" }
    }
    var modifiers: UInt32 {
        switch self {
        case .controlShiftZ: UInt32(controlKey | shiftKey)
        case .commandOptionZ: UInt32(cmdKey | optionKey)
        case .controlOptionZ: UInt32(controlKey | optionKey)
        }
    }
}
