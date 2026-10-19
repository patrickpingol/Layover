import AppKit

/// The root view of a Shelf: accepts drops of files, links, images and text and tints itself
/// while a drag it would accept hovers over it.
@MainActor
final class ShelfDropView: NSView {
    /// Called with the dragging pasteboard when something is dropped; returns whether it was taken.
    var onDrop: (NSPasteboard) -> Bool = { _ in false }

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
        layer.borderWidth = isTargeted ? 2 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.borderColor = NSColor.controlAccentColor.cgColor
            layer.backgroundColor = isTargeted ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor : nil
        }
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isTargeted = accepts(sender)
        return isTargeted ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isTargeted ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isTargeted = false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isTargeted = false
        return !isOwnDrag(from: sender.draggingSource) && onDrop(sender.draggingPasteboard)
    }

    /// Whether a drag from `source` (`NSDraggingInfo.draggingSource`) started in this Shelf. Dropping
    /// a Shelf's Items back on it would only copy them, so it takes no such drop.
    func isOwnDrag(from source: Any?) -> Bool {
        if let dragSource, let source = source as AnyObject?, source === dragSource { return true }
        return (source as? NSView)?.isDescendant(of: self) == true
    }

    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        !isOwnDrag(from: sender.draggingSource)
            && sender.draggingPasteboard.availableType(from: ItemImporter.acceptedTypes) != nil
    }
}
