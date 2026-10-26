import AppKit
import IdkthenCore

private final class SuggestionWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A nonactivating native panel: clicking Apply does not move typing focus to idkthen.
@MainActor final class LiveSuggestionPanel: NSObject {
    var onAccept: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onUndo: (() -> Void)?
    private let window: NSPanel
    private let titleLabel = NSTextField(labelWithString: "idkthen")
    private let wordLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "Apply", target: nil, action: nil)
    private var undoMode = false

    override init() {
        window = SuggestionWindow(contentRect: NSRect(x: 0, y: 0, width: 338, height: 88),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.title = "idkthen Live Suggestion"
        window.isFloatingPanel = true; window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
        window.level = .floating; window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let material = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 338, height: 88))
        material.material = .popover; material.state = .active; material.blendingMode = .behindWindow
        material.wantsLayer = true; material.layer?.cornerRadius = 13; material.layer?.masksToBounds = true
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium); titleLabel.textColor = .secondaryLabelColor
        wordLabel.font = .systemFont(ofSize: 16, weight: .medium); wordLabel.lineBreakMode = .byTruncatingMiddle
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss suggestion")!, target: self, action: #selector(dismissAction))
        close.bezelStyle = .inline; close.isBordered = false; close.setAccessibilityLabel("Dismiss suggestion")
        close.focusRingType = .none
        actionButton.target = self; actionButton.action = #selector(applyAction); actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small; actionButton.focusRingType = .none
        let top = NSStackView(views: [titleLabel, NSView(), close]); top.orientation = .horizontal
        let bottom = NSStackView(views: [wordLabel, actionButton]); bottom.orientation = .horizontal; bottom.spacing = 14
        let stack = NSStackView(views: [top, bottom]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false; material.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: material.centerYAnchor),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor), bottom.widthAnchor.constraint(equalTo: stack.widthAnchor),
            close.widthAnchor.constraint(equalToConstant: 18), close.heightAnchor.constraint(equalToConstant: 18)
        ])
        wordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        window.contentView = material
    }
    func show(original: String, replacement: String, languages: LanguageSelection, near bounds: CGRect) {
        undoMode = false
        titleLabel.stringValue = "IDKTHEN · \(languages.codes) · SUGGESTION"
        wordLabel.stringValue = "\(original) → \(replacement)"
        actionButton.title = "Apply"; actionButton.setAccessibilityLabel("Apply \(replacement)")
        position(near: bounds)
    }
    func showUndo(replacement: String, near bounds: CGRect, automatic: Bool = false) {
        undoMode = true; titleLabel.stringValue = automatic ? "IDKTHEN · AUTO-CORRECTED" : "IDKTHEN · APPLIED"
        wordLabel.stringValue = replacement
        actionButton.title = "Undo"; actionButton.setAccessibilityLabel("Undo live correction")
        position(near: bounds)
    }
    func hide() { window.orderOut(nil) }
    private func position(near rect: CGRect) {
        guard let primary = NSScreen.screens.first else { return }
        let anchor = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: max(rect.width, 1), height: rect.height)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchor) }) else { hide(); return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let width = window.frame.width, height = window.frame.height
        let x = min(max(anchor.minX, visible.minX), visible.maxX - width)
        let below = anchor.minY - height - 7
        let y = below >= visible.minY ? below : min(anchor.maxY + 7, visible.maxY - height)
        window.setFrameOrigin(NSPoint(x: x, y: y)); window.orderFrontRegardless()
    }
    @objc private func applyAction() { if undoMode { onUndo?() } else { onAccept?() } }
    @objc private func dismissAction() { onDismiss?() }
}
