import AppKit

/// The row of Instant Action targets shown over an empty Shelf while a drag hovers over it. It only
/// draws what `ShelfDropView` tracks: each target sits exactly at `InstantActionLayout.frames`, where
/// the drop view hit-tests drops, and the one under the cursor takes the drop highlight.
///
/// It is passive: it never registers for dragged types, since entering it would send the Shelf's drop
/// view `draggingExited`, and it never takes a hit, so the drop view stays the drag destination.
@MainActor
final class InstantActionsView: NSView {
    private var targetViews: [InstantActionTargetView] = []

    /// The Instant Actions shown, left to right.
    private(set) var targets: [InstantAction] = []
    /// The target under the cursor.
    private(set) var highlightedAction: InstantAction?

    /// Where each target is drawn, in this view's coordinates.
    var targetFrames: [CGRect] { targetViews.map(\.frame) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `targets` with `highlighted` under the cursor; the view hides itself when there are none.
    func display(_ targets: [InstantAction], highlighted: InstantAction?) {
        if targets != self.targets {
            self.targets = targets
            while targetViews.count < targets.count {
                let view = InstantActionTargetView()
                addSubview(view)
                targetViews.append(view)
            }
            while targetViews.count > targets.count {
                targetViews.removeLast().removeFromSuperview()
            }
            for (view, action) in zip(targetViews, targets) { view.show(action) }
            needsLayout = true
        }
        highlightedAction = highlighted
        for (view, action) in zip(targetViews, targets) { view.isHighlighted = action == highlighted }
        isHidden = targets.isEmpty
    }

    override func layout() {
        super.layout()
        for (view, frame) in zip(targetViews, InstantActionLayout.frames(count: targets.count, in: bounds)) {
            view.frame = frame
        }
    }

    // Drags and clicks belong to the drop view underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// One target: an SF Symbol above its title on a rounded fill, which takes the drop highlight
/// while it is under the cursor.
@MainActor
private final class InstantActionTargetView: NSView {
    private static let cornerRadius: CGFloat = 10
    private static let symbolPointSize: CGFloat = 20
    private static let labelBottomInset: CGFloat = 6
    private static let labelCellInset: CGFloat = 2

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            needsDisplay = true
            applyColors()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .regular)
        iconView.imageScaling = .scaleProportionallyDown
        titleLabel.font = .systemFont(ofSize: 9, weight: .regular)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.allowsDefaultTighteningForTruncation = true
        for view in [iconView, titleLabel] as [NSView] {
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ action: InstantAction) {
        iconView.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
        titleLabel.stringValue = action.title
        setAccessibilityLabel(action.title)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Self.cornerRadius
        layer.borderWidth = isHighlighted ? DropHighlightStyle.borderWidth : 0
        layer.borderColor = DropHighlightStyle.borderColor(in: effectiveAppearance)
        layer.backgroundColor = isHighlighted
            ? DropHighlightStyle.fillColor(in: effectiveAppearance)
            : Self.restingFill(in: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// A faint system fill, so a target reads as a drop zone without competing with the highlight.
    private static func restingFill(in appearance: NSAppearance) -> CGColor {
        var resolved: CGColor?
        appearance.performAsCurrentDrawingAppearance { resolved = NSColor.quaternaryLabelColor.cgColor }
        return resolved ?? NSColor.quaternaryLabelColor.cgColor
    }

    private func applyColors() {
        iconView.contentTintColor = isHighlighted ? .controlAccentColor : .labelColor
        titleLabel.textColor = isHighlighted ? .labelColor : .secondaryLabelColor
    }

    override func layout() {
        super.layout()
        let labelHeight = titleLabel.intrinsicContentSize.height
        // The label's cell insets its text by a couple of points a side, so it is made as much wider.
        titleLabel.frame = CGRect(
            x: -Self.labelCellInset, y: Self.labelBottomInset,
            width: bounds.width + 2 * Self.labelCellInset, height: labelHeight
        )
        let iconTop = titleLabel.frame.maxY
        iconView.frame = CGRect(x: 0, y: iconTop, width: bounds.width, height: bounds.height - iconTop)
    }
}
