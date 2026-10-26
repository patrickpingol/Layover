import AppKit
import LayoverCore

/// The window of the Notch Drop target for one notch: borderless and transparent, above the menu bar on
/// every Space (full-screen ones too), with a `NotchDropView` exactly over the notch. Around it, the
/// outline (flat against the top of the screen, rounded at the bottom) shows as `highlight` says.
@MainActor
final class NotchDropPanel: NSPanel {
    private let outline = NotchOutlineView()
    private let highlight: NotchDropHighlight
    private let isDragAcceptable: Bool
    private var isTargeted = false {
        didSet { updateHighlight() }
    }

    /// `notch` is in screen coordinates. `isDragAcceptable` is whether the drag in progress carries
    /// something a Shelf accepts, as of now; `onDrop` takes the dragging pasteboard and says if it was used.
    init(notch: CGRect, highlight: NotchDropHighlight, isDragAcceptable: Bool, onDrop: @escaping (NSPasteboard) -> Bool) {
        self.highlight = highlight
        self.isDragAcceptable = isDragAcceptable
        let outlineRect = NotchGeometry.outlineRect(around: notch)
        super.init(
            contentRect: outlineRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        outline.frame = CGRect(origin: .zero, size: outlineRect.size)
        contentView = outline
        let dropView = NotchDropView(frame: CGRect(
            x: notch.minX - outlineRect.minX, y: notch.minY - outlineRect.minY, width: notch.width, height: notch.height
        ))
        dropView.onDrop = onDrop
        dropView.onTargetedChange = { [weak self] in self?.isTargeted = $0 }
        outline.addSubview(dropView)
        updateHighlight()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would otherwise push a window that overlaps the menu bar down below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    private func updateHighlight() {
        outline.isHighlighted = highlight.isVisible(isDragAcceptable: isDragAcceptable, isTargeted: isTargeted)
    }
}

/// The outline around the notch: a tinted fill and an accent border, styled like a Shelf's highlight.
/// The top edge is flush with the screen, so the border runs only down the sides and along the bottom.
@MainActor
private final class NotchOutlineView: NSView {
    private static let cornerRadius: CGFloat = 12

    private let fillLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            fillLayer.isHidden = !isHighlighted
            borderLayer.isHidden = !isHighlighted
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fillLayer.isHidden = true
        borderLayer.isHidden = true
        borderLayer.fillColor = nil
        borderLayer.lineWidth = DropHighlightStyle.borderWidth
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(borderLayer)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        fillLayer.frame = bounds
        borderLayer.frame = bounds
        fillLayer.path = Self.path(in: bounds, closed: true)
        // The border is centered on its path, so keep the path inside the view.
        borderLayer.path = Self.path(in: bounds.insetBy(dx: DropHighlightStyle.borderWidth / 2, dy: DropHighlightStyle.borderWidth / 2), closed: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        fillLayer.fillColor = DropHighlightStyle.fillColor(in: effectiveAppearance)
        borderLayer.strokeColor = DropHighlightStyle.borderColor(in: effectiveAppearance)
    }

    /// Down the left side, along the bottom with rounded corners, and up the right side; `closed` also
    /// joins the two top ends.
    private static func path(in rect: CGRect, closed: Bool) -> CGPath {
        let radius = min(cornerRadius, rect.width / 2, rect.height)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if closed { path.closeSubpath() }
        return path
    }
}
