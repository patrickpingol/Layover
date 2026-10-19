import AppKit
import OpenDropCore

/// A Shelf's expanded look: a scrolling four-column grid of Item icons and names.
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
    private let collectionView = NSCollectionView()
    private var items: [Item] = []

    init(thumbnails: ItemThumbnailProvider, dragSource: ShelfDragSource) {
        self.thumbnails = thumbnails
        self.dragSource = dragSource
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
        true
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
