import Foundation

/// Ephemeral, content-free feedback. Never stores field text or writes preferences.
enum ConnectionStatus {
    case waitingForField, observing, unsupported, replacementFailed, corrected, unsupportedLayout, undoFailed

    var summary: String {
        switch self {
        case .waitingForField: "click a writable text area"
        case .observing, .corrected: "connected · finish a word with Space"
        case .unsupported: "this field is review-only"
        case .replacementFailed: "change not confirmed · check your text"
        case .unsupportedLayout: "layout recovery paused · check Languages"
        case .undoFailed: "Undo not confirmed · check the original field"
        }
    }

    var message: String {
        switch self {
        case .waitingForField: "Open this app and click a writable document. Then type a word and Space."
        case .observing: "Text updates connected. A correction still needs to be confirmed."
        case .unsupported: "The last field did not provide a supported editable interface. Try a plain document, or paste into Review Text."
        case .replacementFailed: "The last correction was not confirmed. Check the original field. Use Review Text and copy the result if this continues."
        case .corrected: "A correction was confirmed in this app during this session."
        case .unsupportedLayout: "This input source does not match the supported US QWERTY, two-set Korean, or standard Russian/Ukrainian mapping. Layout recovery is paused. Accent review remains available; three-set and custom layouts are not supported."
        case .undoFailed: "The last Undo was not confirmed. Return to the original field and check its text. If you edited that word or switched fields, idkthen will refuse to overwrite it."
        }
    }
}
