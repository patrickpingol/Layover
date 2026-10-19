import AppKit
import OpenDropCore

/// What a finished drag out of a Shelf does to the Shelf.
public enum DragOutcome {
    /// Removes the dragged Items when the destination moved them. Anything else (a copy, a share, a
    /// cancelled drag) keeps everything. Returns true when the Shelf should close.
    public static func apply(
        operation: NSDragOperation, draggedIDs: Set<Item.ID>, to shelf: inout Shelf, closeWhenEmptied: Bool
    ) -> Bool {
        guard operation == .move else { return false }
        shelf.remove(draggedIDs)
        return closeWhenEmptied && shelf.items.isEmpty
    }
}
