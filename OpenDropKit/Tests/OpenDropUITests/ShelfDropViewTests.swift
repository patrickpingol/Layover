import AppKit
import Testing
@testable import OpenDropUI

@Test @MainActor func aDragFromTheShelfsOwnDragSourceIsItsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let dragSource = NSObject()
    view.dragSource = dragSource

    #expect(view.isOwnDrag(from: dragSource))
}

@Test @MainActor func aDragFromAViewInsideTheShelfIsItsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let nested = NSView()
    let container = NSView()
    container.addSubview(nested)
    view.addSubview(container)

    #expect(view.isOwnDrag(from: nested))
}

@Test @MainActor func aDragFromAnotherShelfOrAnotherAppIsNotItsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let dragSource = NSObject()
    view.dragSource = dragSource
    let otherShelf = ShelfDropView(frame: .zero)
    let inOtherShelf = NSView()
    otherShelf.addSubview(inOtherShelf)

    #expect(!view.isOwnDrag(from: NSObject()))
    #expect(!view.isOwnDrag(from: inOtherShelf))
    #expect(!view.isOwnDrag(from: nil))
    withExtendedLifetime(dragSource) {}
}
