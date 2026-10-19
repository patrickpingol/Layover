import AppKit
import OpenDropCore

/// A Shelf's compact look: a stack of up to three thumbnails, the Item count and the Handle,
/// or "Drop files here" when the Shelf is empty.
@MainActor
final class ShelfCompactView: NSView {
    static let size = CGSize(width: 132, height: 152)

    /// Called when the stack is clicked (not dragged).
    var onStackClick: () -> Void = {}

    private let thumbnails: ItemThumbnailProvider
    private let stack = ThumbnailStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: String(localized: "Drop files here"))
    private let handle = NSView()

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

        handle.wantsLayer = true
        handle.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        handle.layer?.cornerRadius = 2.5

        for view in [stack, countLabel, emptyLabel, handle] as [NSView] {
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
            handle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func display(_ items: [Item]) {
        let isEmpty = items.isEmpty
        emptyLabel.isHidden = !isEmpty
        stack.isHidden = isEmpty
        countLabel.isHidden = isEmpty
        handle.isHidden = isEmpty
        countLabel.stringValue = String(localized: "\(items.count) items")
        stack.display(items, using: thumbnails)
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

    func display(_ items: [Item], using provider: ItemThumbnailProvider) {
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
