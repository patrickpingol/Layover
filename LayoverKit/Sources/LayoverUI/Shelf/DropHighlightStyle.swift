import AppKit

/// How a drop target looks while a drag it would accept is over it, shared by the Shelf and the notch.
@MainActor
enum DropHighlightStyle {
    static let borderWidth: CGFloat = 2
    static let fillAlpha: CGFloat = 0.15

    /// The accent color, resolved for `appearance`.
    static func borderColor(in appearance: NSAppearance) -> CGColor {
        resolve(in: appearance) { NSColor.controlAccentColor }
    }

    static func fillColor(in appearance: NSAppearance) -> CGColor {
        resolve(in: appearance) { NSColor.controlAccentColor.withAlphaComponent(fillAlpha) }
    }

    private static func resolve(in appearance: NSAppearance, _ color: () -> NSColor) -> CGColor {
        var resolved: CGColor?
        appearance.performAsCurrentDrawingAppearance { resolved = color().cgColor }
        return resolved ?? color().cgColor
    }
}
