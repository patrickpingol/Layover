import AppKit
import LayoverCore

/// A Shelf's compact look: a stack of up to three thumbnails, the Item count and the Handle,
/// or "Drop files here" when the Shelf is empty.
@MainActor
final class ShelfCompactView: NSView {
    static let size = CGSize(width: 132, height: 152)

    /// Called when the stack is clicked (not dragged).
    var onStackClick: () -> Void = {}

    /// Called when the "⋯" button is clicked, with the button to show the Item actions menu from.
    var onMoreActions: (NSButton) -> Void = { _ in }

    /// Called when the Handle is dragged, with the mouse-down event and the Handle to drag from.
    var onHandleDrag: (NSEvent, NSView) -> Void {
        get { handle.onDrag }
        set { handle.onDrag = newValue }
    }

    private let thumbnails: ItemThumbnailProvider
    private let stack = ThumbnailStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: String(localized: "Drop files here"))
    private let handle = HandleView()
    private let moreButton = NSButton()

    init(thumbnails: ItemThumbnailProvider) {
        self.thumbnails = thumbnails
        super.init(frame: .zero)
        stack.onClick = { [weak self] in self?.onStackClick() }

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .center

        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let moreTitle = String(localized: "Item Actions")
        moreButton.isBordered = false
        moreButton.imagePosition = .imageOnly
        moreButton.contentTintColor = .secondaryLabelColor
        moreButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: moreTitle)
        moreButton.toolTip = moreTitle
        moreButton.setAccessibilityLabel(moreTitle)
        moreButton.target = self
        moreButton.action = #selector(showMoreActions)

        for view in [stack, countLabel, emptyLabel, handle, moreButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.widthAnchor.constraint(equalToConstant: 100),
            stack.heightAnchor.constraint(equalToConstant: 80),

            countLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 2),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            emptyLabel.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            handle.centerXAnchor.constraint(equalTo: centerXAnchor),
            handle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            handle.widthAnchor.constraint(equalToConstant: HandleView.size.width),
            handle.heightAnchor.constraint(equalToConstant: HandleView.size.height),

            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            moreButton.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 18),
            moreButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func display(_ items: [Item], unavailableIDs: Set<Item.ID> = []) {
        let isEmpty = items.isEmpty
        emptyLabel.isHidden = !isEmpty
        stack.isHidden = isEmpty
        countLabel.isHidden = isEmpty
        handle.isHidden = isEmpty
        moreButton.isHidden = isEmpty
        countLabel.stringValue = String(localized: "\(items.count) items")
        stack.display(items, unavailableIDs: unavailableIDs, using: thumbnails)
    }

    @objc private func showMoreActions() {
        onMoreActions(moreButton)
    }

    /// Bounces the thumbnail of the Item with `id`, or the whole stack when that Item is not one of
    /// the (at most three) newest Items it shows.
    func bounce(_ id: Item.ID) {
        stack.bounceThumbnail(of: id)
    }
}

/// Up to three thumbnails fanned out, the newest Item on top. A click toggles the Shelf's look;
/// a drag still moves the window.
@MainActor
private final class ThumbnailStackView: NSView {
    private static let maxCount = 3
    /// Horizontal offset and rotation (degrees) for the back, middle and front thumbnail.
    private static let fan: [(dx: CGFloat, angle: CGFloat)] = [(-12, 8), (12, -8), (0, 0)]

    var onClick: () -> Void = {}

    private var views: [ItemThumbnailView] = []
    private var shownIDs: [Item.ID] = []
    private var mouseDownEvent: NSEvent?

    func display(_ items: [Item], unavailableIDs: Set<Item.ID>, using provider: ItemThumbnailProvider) {
        let shown = Array(items.suffix(Self.maxCount))
        shownIDs = shown.map(\.id)
        while views.count < shown.count {
            let view = ItemThumbnailView()
            view.imageScaling = .scaleProportionallyUpOrDown
            addSubview(view)
            views.append(view)
        }
        while views.count > shown.count {
            views.removeLast().removeFromSuperview()
        }
        for (view, item) in zip(views, shown) {
            view.show(item, using: provider)
            view.alphaValue = unavailableIDs.contains(item.id) ? ItemAvailabilityStyle.unavailableAlpha : 1
        }
        needsLayout = true
    }

    func bounceThumbnail(of id: Item.ID) {
        if let index = shownIDs.firstIndex(of: id), index < views.count {
            views[index].bounce()
        } else {
            bounce()
        }
    }

    override func layout() {
        super.layout()
        // Fan positions are taken from the end of `fan`, so a single thumbnail sits straight in the middle.
        let positions = Self.fan.suffix(views.count)
        let side = ItemThumbnailProvider.side
        for (view, position) in zip(views, positions) {
            view.frameCenterRotation = 0
            view.frame = CGRect(
                x: bounds.midX - side / 2 + position.dx,
                y: bounds.midY - side / 2,
                width: side,
                height: side
            )
            view.frameCenterRotation = position.angle
        }
    }

    // Clicks on the thumbnails belong to the stack, not to the image views.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent else { return }
        self.mouseDownEvent = nil
        window?.performDrag(with: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// The Handle: a small pill, in a larger area to grab, that drags all the Shelf's Items out.
/// It doesn't move the window.
@MainActor
private final class HandleView: NSView {
    static let size = CGSize(width: 84, height: 22)
    private static let pill = CGSize(width: 36, height: 5)

    var onDrag: (NSEvent, NSView) -> Void = { _, _ in }

    private var mouseDownEvent: NSEvent?

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let pill = CGRect(
            x: bounds.midX - Self.pill.width / 2, y: bounds.midY - Self.pill.height / 2,
            width: Self.pill.width, height: Self.pill.height
        )
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: Self.pill.height / 2, yRadius: Self.pill.height / 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent else { return }
        self.mouseDownEvent = nil
        onDrag(mouseDownEvent, self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }
}
