import AppKit

/// The root view of a Shelf: accepts drops of files, links, images and text and tints itself
/// while a drag it would accept hovers over it.
///
/// It is the Shelf's only drag destination. While a drag hovers over an empty Shelf it also tracks
/// which Instant Action target, laid out by `InstantActionLayout`, is under the cursor, and a drop on
/// one goes to `onInstantAction` instead of `onDrop`. The targets are drawn by a view that observes
/// `onInstantActionsChange`; it must not register for drags, or entering it would end the drag here.
@MainActor
final class ShelfDropView: NSView {
    /// Called with the dragging pasteboard when something is dropped; returns whether it was taken.
    var onDrop: (NSPasteboard) -> Bool = { _ in false }

    /// Whether this Shelf offers Instant Actions right now: they are on and the Shelf has no Items.
    /// Read when a drag enters, so a change applies from the next drag.
    var showsInstantActions: () -> Bool = { false }

    /// Called when something is dropped on an Instant Action target, with the dragging pasteboard;
    /// returns whether the action was started.
    var onInstantAction: (InstantAction, NSPasteboard) -> Bool = { _, _ in false }

    /// Called when `instantActionTargets` or `highlightedAction` changes.
    var onInstantActionsChange: () -> Void = {}

    /// The Instant Actions whose service exists on this Mac.
    var availableInstantActions = InstantAction.available

    /// The targets shown, left to right, for as long as an accepted drag hovers over an empty Shelf.
    private(set) var instantActionTargets: [InstantAction] = [] {
        didSet {
            guard instantActionTargets != oldValue else { return }
            onInstantActionsChange()
        }
    }

    var isShowingInstantActions: Bool { !instantActionTargets.isEmpty }

    /// The target under the cursor.
    private(set) var highlightedAction: InstantAction? {
        didSet {
            guard highlightedAction != oldValue else { return }
            onInstantActionsChange()
        }
    }

    /// The drag source this Shelf starts its own drags with (the Handle's). Drags started from views
    /// inside this view (the grid) are recognized without it.
    weak var dragSource: AnyObject?

    private var isTargeted = false {
        didSet {
            guard isTargeted != oldValue else { return }
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes(ItemImporter.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = ShelfPanel.cornerRadius
        layer.borderWidth = isTargeted ? DropHighlightStyle.borderWidth : 0
        layer.borderColor = DropHighlightStyle.borderColor(in: effectiveAppearance)
        layer.backgroundColor = isTargeted ? DropHighlightStyle.fillColor(in: effectiveAppearance) : nil
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isTargeted = accepts(sender)
        instantActionTargets = isTargeted && showsInstantActions() ? availableInstantActions : []
        highlightedAction = instantAction(at: sender)
        return isTargeted ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        highlightedAction = instantAction(at: sender)
        return isTargeted ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        endTargeting()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        endTargeting()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let action = instantAction(at: sender)
        endTargeting()
        guard !isOwnDrag(from: sender.draggingSource) else { return false }
        if let action { return onInstantAction(action, sender.draggingPasteboard) }
        return onDrop(sender.draggingPasteboard)
    }

    private func endTargeting() {
        isTargeted = false
        instantActionTargets = []
        highlightedAction = nil
    }

    /// The target shown under the drag's location, if any.
    private func instantAction(at sender: any NSDraggingInfo) -> InstantAction? {
        let location = convert(sender.draggingLocation, from: nil)
        return InstantActionLayout.target(at: location, in: bounds, count: instantActionTargets.count)
            .map { instantActionTargets[$0] }
    }

    /// Whether a drag from `source` (`NSDraggingInfo.draggingSource`) started in this Shelf. Dropping
    /// a Shelf's Items back on it would only copy them, so it takes no such drop.
    func isOwnDrag(from source: Any?) -> Bool {
        if let dragSource, let source = source as AnyObject?, source === dragSource { return true }
        return (source as? NSView)?.isDescendant(of: self) == true
    }

    /// Whether a drag from `source` (`NSDraggingInfo.draggingSource`) started in some Shelf: from a
    /// Shelf's drag source (the Handle) or from a view inside a Shelf's window (the grid).
    static func isShelfDrag(from source: Any?) -> Bool {
        source is ShelfDragSource || (source as? NSView)?.window is ShelfPanel
    }

    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        !isOwnDrag(from: sender.draggingSource)
            && ItemImporter.accepts(sender.draggingPasteboard)
    }
}
