import AppKit
import SwiftUI

/// One native metric set for the menu and its settings pages. Symbol glyphs keep
/// their SF Symbols proportions; their alignment and hit areas are consistent.
enum IdkthenStyle {
    static let accent = Color.blue
    static let body = Font.system(size: 17)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let caption = Font.system(size: 13)
    static let rowSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 24 // Grouped Form supplies the row insets.
    static let detailRowHeight: CGFloat = 48
    static let iconSize: CGFloat = 22
    static let controlSize: CGFloat = 44
    static let headerHeight: CGFloat = 52
    static let panelWidth: CGFloat = 360
    static func menuIcon(_ name: String) -> Image {
        // AppKit-backed Menu labels do not retain SwiftUI's symbol font size.
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))!
        image.size = NSSize(width: 18, height: 18)
        return Image(nsImage: image).renderingMode(.template)
    }
}

struct idkthenSymbol: View {
    let name: String
    var toolbar = false
    var body: some View {
        Image(systemName: name)
            .font(.system(size: toolbar ? 18 : 16, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .frame(width: IdkthenStyle.iconSize, height: IdkthenStyle.iconSize)
            .accessibilityHidden(true)
    }
}

struct idkthenLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: IdkthenStyle.rowSpacing) {
            configuration.icon.font(.system(size: 16, weight: .regular))
                .frame(width: IdkthenStyle.iconSize, height: IdkthenStyle.iconSize)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

struct idkthenDisclosure: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: IdkthenStyle.iconSize)
            .accessibilityHidden(true)
    }
}
