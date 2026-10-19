import AppKit

/// The floating, non-activating window a Shelf lives in: a rounded HUD background that hosts the
/// Shelf's view and stays above other windows on every Space without activating OpenDrop.
@MainActor
final class ShelfPanel: NSPanel {
    static let cornerRadius: CGFloat = 16

    private let content: NSViewController

    init(content: NSViewController, size: CGSize) {
        self.content = content
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        contentView = background

        content.view.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: background.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
    }

    // Borderless panels refuse key status by default; Item actions need keyboard input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Resizes the panel keeping its top-left corner in place, then keeps it fully on its screen.
    func resize(to size: CGSize) {
        let topLeft = CGPoint(x: frame.minX, y: frame.maxY)
        var origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        if let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame {
            origin = ShelfPlacement.clamped(origin, size: size, visibleFrame: visibleFrame)
        }
        setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
        invalidateShadow()
    }

    /// A stretchable rounded rectangle; masking the effect view this way also shapes the window shadow.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
