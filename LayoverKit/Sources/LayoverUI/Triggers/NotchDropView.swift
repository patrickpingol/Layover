import AppKit

/// The notch-sized view of the Notch Drop target: the only part of it that takes a drop, so the drop area
/// is exactly the notch. It reports whether a drag it would accept is over it; the panel draws the highlight.
/// A drag of Items out of a Shelf is not accepted: it would only copy them into a new Shelf.
@MainActor
final class NotchDropView: NSView {
    /// Called with the dragging pasteboard when something is dropped; returns whether it was taken.
    var onDrop: (NSPasteboard) -> Bool = { _ in false }
    /// Called when a drag this view accepts enters it (true) or leaves it (false).
    var onTargetedChange: (Bool) -> Void = { _ in }

    private var isTargeted = false {
        didSet {
            guard isTargeted != oldValue else { return }
            onTargetedChange(isTargeted)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(ItemImporter.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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
        return !ShelfDropView.isShelfDrag(from: sender.draggingSource) && onDrop(sender.draggingPasteboard)
    }

    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        !ShelfDropView.isShelfDrag(from: sender.draggingSource)
            && ItemImporter.accepts(sender.draggingPasteboard)
    }
}
