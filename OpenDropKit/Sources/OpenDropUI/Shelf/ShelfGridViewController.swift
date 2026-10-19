import AppKit
import OpenDropCore

/// A Shelf's expanded look: a scrolling four-column grid of Item icons and names.
///
/// The grid acts on its Items: a double-click opens one, a context menu offers the Item actions, and
/// with the selection Space shows Quick Look, ⌘C copies and ⌫ removes from the Shelf.
@MainActor
final class ShelfGridViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 480

    private static let columns = 4
    private static let inset: CGFloat = 10
    private static let spacing: CGFloat = 8
    private static let itemHeight: CGFloat = 96

    private let thumbnails: ItemThumbnailProvider
    private let dragSource: ShelfDragSource
    private let actions: ItemActionController
    private let collectionView = ShelfCollectionView()
    private var items: [Item] = []

    init(thumbnails: ItemThumbnailProvider, dragSource: ShelfDragSource, actions: ItemActionController) {
        self.thumbnails = thumbnails
        self.dragSource = dragSource
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The height the grid's content needs for `itemCount` Items, before the Shelf caps it.
    static func contentHeight(itemCount: Int) -> CGFloat {
        let rows = max(1, (itemCount + columns - 1) / columns)
        return inset * 2 + CGFloat(rows) * itemHeight + CGFloat(rows - 1) * spacing
    }

    override func loadView() {
        let layout = NSCollectionViewFlowLayout()
        let itemWidth = (Self.width - Self.inset * 2 - Self.spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        layout.itemSize = CGSize(width: itemWidth.rounded(.down), height: Self.itemHeight)
        layout.minimumInteritemSpacing = Self.spacing
        layout.minimumLineSpacing = Self.spacing
        layout.sectionInset = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)

        collectionView.collectionViewLayout = layout
        collectionView.autoresizingMask = [.width]
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        // Inside the app an Item can only be copied (onto another Shelf); elsewhere it can also be moved.
        collectionView.setDraggingSourceOperationMask(dragSource.sourceOperationMask(for: .withinApplication), forLocal: true)
        collectionView.setDraggingSourceOperationMask(dragSource.sourceOperationMask(for: .outsideApplication), forLocal: false)
        collectionView.register(ShelfGridItem.self, forItemWithIdentifier: ShelfGridItem.identifier)
        collectionView.onContextMenu = { [weak self] event in self?.contextMenu(for: event) }
        collectionView.onDoubleClick = { [weak self] indexPath in self?.open(at: indexPath) }
        collectionView.onKeyAction = { [weak self] action in self?.perform(action) ?? false }

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        view = scrollView
    }

    func display(_ items: [Item]) {
        self.items = items
        collectionView.reloadData()
    }

    /// Bounces the cell of the Item with `id`, if it is on screen.
    func bounce(_ id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        collectionView.item(at: IndexPath(item: index, section: 0))?.view.bounce()
    }

    // MARK: Item actions

    private var selectedItems: [Item] {
        collectionView.selectionIndexPaths.sorted().compactMap { items.indices.contains($0.item) ? items[$0.item] : nil }
    }

    /// The menu for the Item under the mouse, or for the whole selection when that Item is part of it.
    private func contextMenu(for event: NSEvent) -> NSMenu? {
        let point = collectionView.convert(event.locationInWindow, from: nil)
        guard let indexPath = collectionView.indexPathForItem(at: point), items.indices.contains(indexPath.item) else { return nil }
        if !collectionView.selectionIndexPaths.contains(indexPath) {
            collectionView.selectionIndexPaths = [indexPath]
        }
        return actions.menu(for: selectedItems, anchor: collectionView.item(at: indexPath)?.view ?? collectionView)
    }

    private func open(at indexPath: IndexPath) {
        guard items.indices.contains(indexPath.item) else { return }
        actions.perform(.open, on: [items[indexPath.item]], anchor: collectionView)
    }

    /// Performs a keyboard action on the selection. Returns false when there is nothing to act on.
    private func perform(_ action: ItemAction) -> Bool {
        let selected = selectedItems
        if action == .quickLook {
            // Space also closes a Quick Look panel that is up, whatever is selected.
            actions.toggleQuickLook(for: selected, anchor: collectionView)
            return true
        }
        guard !selected.isEmpty else { return false }
        actions.perform(action, on: selected, anchor: collectionView)
        return true
    }

    // MARK: NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: ShelfGridItem.identifier, for: indexPath)
        (cell as? ShelfGridItem)?.show(items[indexPath.item], using: thumbnails)
        return cell
    }

    // MARK: NSCollectionViewDelegate (dragging out)

    // Dragging an Item drags the selection when the Item is part of it, and just that Item otherwise;
    // the collection view works that out and asks for a writer per Item.

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        // A drag of only Unavailable Items never starts, so it leaves no access open.
        indexPaths.contains { items.indices.contains($0.item) && dragSource.canDrag(items[$0.item]) }
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard items.indices.contains(indexPath.item) else { return nil }
        return dragSource.entry(for: items[indexPath.item]).map { $0.url as NSURL }
    }

    func collectionView(
        _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>
    ) {
        dragSource.sessionWillBegin(dragging: Set(indexPaths.filter { items.indices.contains($0.item) }.map { items[$0.item].id }))
    }

    func collectionView(
        _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation
    ) {
        dragSource.finish(operation: operation)
    }
}

/// The grid's collection view, with the mouse and keyboard handling for the Item actions.
@MainActor
private final class ShelfCollectionView: NSCollectionView {
    var onContextMenu: (NSEvent) -> NSMenu? = { _ in nil }
    var onDoubleClick: (IndexPath) -> Void = { _ in }
    /// Called for Space (Quick Look), ⌘C (Copy) and ⌫ (Remove from Shelf); returns whether it acted.
    var onKeyAction: (ItemAction) -> Bool = { _ in false }

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        guard event.clickCount == 2, ItemShortcut.relevantModifiers(of: event.modifierFlags).isEmpty,
              let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        else { return }
        onDoubleClick(indexPath)
    }

    override func keyDown(with event: NSEvent) {
        let action = ItemShortcut.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
        guard let action, action != .copy, onKeyAction(action) else { return super.keyDown(with: event) }
    }

    // OpenDrop has no Edit menu, so ⌘C reaches the grid as a key equivalent.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let action = ItemShortcut.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
        guard !isHiddenOrHasHiddenAncestor, action == .copy else { return super.performKeyEquivalent(with: event) }
        return onKeyAction(.copy)
    }
}

/// One grid cell: the Item's thumbnail above its name.
@MainActor
private final class ShelfGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShelfGridItem")

    private let thumbnailView = ItemThumbnailView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        for subview in [thumbnailView, nameLabel] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            thumbnailView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: ItemThumbnailProvider.side),
            thumbnailView.heightAnchor.constraint(equalToConstant: ItemThumbnailProvider.side),

            nameLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
        ])
        view = container
        imageView = thumbnailView
        textField = nameLabel
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor : nil
    }

    func show(_ item: Item, using thumbnails: ItemThumbnailProvider) {
        thumbnailView.show(item, using: thumbnails)
        nameLabel.stringValue = item.displayName
        nameLabel.toolTip = item.displayName
    }
}
