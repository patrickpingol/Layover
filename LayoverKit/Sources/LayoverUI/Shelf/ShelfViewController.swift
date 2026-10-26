import AppKit
import LayoverCore

/// One Shelf's content: the close, pin and expand buttons above either the compact stack or the grid.
/// It only presents; the coordinator owns the Shelf and applies the button actions.
@MainActor
final class ShelfViewController: NSViewController {
    private static let headerHeight: CGFloat = 28

    var onClose: () -> Void = {}
    var onTogglePin: () -> Void = {}
    /// Called after the Shelf expands, so its Items can be checked against the disk.
    var onExpand: () -> Void = {}
    /// Adds dropped contents to this Shelf and reports what happened to each. Called with no
    /// suspension since the contents were created, which Owned File cleanup relies on.
    var onAdd: ([ItemContent]) -> [Shelf.AddOutcome] = { _ in [] }
    /// Whether the Shelf is still open, so promised files arriving late can be discarded.
    var isShelfOpen: () -> Bool = { false }

    private let importer: ItemImporter
    private let dragSource: ShelfDragSource
    private let actions: ItemActionController
    private var shelf: Shelf
    private var isExpanded = false
    private var unavailableIDs: Set<Item.ID> = []

    private let compactView: ShelfCompactView
    private let noticeView = ShelfNoticeView()
    private let gridController: ShelfGridViewController
    private let closeButton = ShelfViewController.makeButton()
    private let pinButton = ShelfViewController.makeButton()
    private let expandButton = ShelfViewController.makeButton()

    init(shelf: Shelf, thumbnails: ItemThumbnailProvider, importer: ItemImporter, dragSource: ShelfDragSource, actions: ItemActionController) {
        self.shelf = shelf
        self.importer = importer
        self.dragSource = dragSource
        self.actions = actions
        compactView = ShelfCompactView(thumbnails: thumbnails)
        gridController = ShelfGridViewController(thumbnails: thumbnails, dragSource: dragSource, actions: actions)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The panel size for the current look.
    var preferredSize: CGSize {
        guard showsGrid else { return ShelfCompactView.size }
        let height = Self.headerHeight + ShelfGridViewController.contentHeight(itemCount: shelf.items.count)
        return CGSize(
            width: ShelfGridViewController.width,
            height: min(ShelfGridViewController.maxHeight, max(ShelfCompactView.size.height, height))
        )
    }

    /// An empty Shelf can't be expanded: there's nothing to put in the grid.
    private var showsGrid: Bool { isExpanded && !shelf.items.isEmpty }

    override func loadView() {
        let root = ShelfDropView(frame: CGRect(origin: .zero, size: ShelfCompactView.size))
        root.dragSource = dragSource
        root.onDrop = { [weak self] pasteboard in self?.handleDrop(pasteboard) ?? false }
        addChild(gridController)

        closeButton.action = #selector(close)
        pinButton.action = #selector(togglePin)
        expandButton.action = #selector(toggleExpanded)
        compactView.onStackClick = { [weak self] in self?.toggleExpanded() }
        compactView.onMoreActions = { [weak self] button in
            guard let self else { return }
            let menu = actions.menu(for: shelf.items, anchor: button)
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height), in: button)
        }
        compactView.onDragAllItems = { [weak self] event, view in
            guard let self else { return }
            dragSource.beginDrag(of: shelf.items, from: view, with: event)
        }

        let trailingButtons = NSStackView(views: [pinButton, expandButton])
        trailingButtons.spacing = 4
        let content = [compactView, gridController.view]
        for view in [closeButton, trailingButtons] + content {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        for button in [closeButton, pinButton, expandButton] { button.target = self }

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: root.topAnchor, constant: Self.headerHeight / 2),
            trailingButtons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            trailingButtons.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])
        for view in content {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.headerHeight),
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        noticeView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(noticeView)
        NSLayoutConstraint.activate([
            noticeView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            noticeView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            noticeView.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
        render()
    }

    /// Shows `shelf`, with the Items in `unavailableIDs` greyed out.
    func display(_ shelf: Shelf, unavailableIDs: Set<Item.ID> = []) {
        let sizeBefore = preferredSize
        self.shelf = shelf
        self.unavailableIDs = unavailableIDs
        if shelf.items.isEmpty { isExpanded = false }
        render()
        if preferredSize != sizeBefore { (view.window as? ShelfPanel)?.resize(to: preferredSize) }
    }

    /// Tells the user, one at a time, that Items were taken off the Shelf because their files are gone.
    func showRemovedNotices(for names: [String]) {
        noticeView.show(names.map { String(localized: "'\($0)' was removed from disk.") })
    }

    private func render() {
        compactView.display(shelf.items, unavailableIDs: unavailableIDs)
        gridController.display(shelf.items, unavailableIDs: unavailableIDs)
        compactView.isHidden = showsGrid
        gridController.view.isHidden = !showsGrid

        let pinTitle = shelf.isPinned ? String(localized: "Unpin Shelf") : String(localized: "Pin Shelf")
        Self.configure(pinButton, symbol: shelf.isPinned ? "pin.fill" : "pin", label: pinTitle)
        Self.configure(closeButton, symbol: "xmark", label: String(localized: "Close Shelf"))
        Self.configure(
            expandButton,
            symbol: showsGrid ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            label: showsGrid ? String(localized: "Collapse") : String(localized: "Expand")
        )
        expandButton.isEnabled = !shelf.items.isEmpty
    }

    // MARK: Dropping

    private func handleDrop(_ pasteboard: NSPasteboard) -> Bool {
        // Receiving promised files must start now, while the dragging pasteboard is still valid.
        switch importer.droppedContent(from: pasteboard) {
        case let .promises(reception):
            Task { [weak self] in
                await reception.receiveAndLog(
                    shouldAdopt: { self?.isShelfOpen() ?? false },
                    deliver: { self?.add($0) }
                )
            }
            return true
        case let .contents(contents):
            add(contents)
            return true
        case nil:
            return false
        }
    }

    /// Adds `contents` to the Shelf; an Item that was already there bounces instead of being added again.
    private func add(_ contents: [ItemContent]) {
        let outcomes = onAdd(contents)
        let duplicates = outcomes.compactMap { outcome -> Item.ID? in
            if case let .duplicate(id) = outcome { id } else { nil }
        }
        guard !duplicates.isEmpty else { return }
        for id in duplicates {
            if showsGrid { gridController.bounce(id) } else { compactView.bounce(id) }
        }
    }

    // MARK: Actions

    @objc private func close() { onClose() }
    @objc private func togglePin() { onTogglePin() }

    @objc private func toggleExpanded() {
        guard !shelf.items.isEmpty else { return }
        isExpanded.toggle()
        render()
        (view.window as? ShelfPanel)?.resize(to: preferredSize)
        if isExpanded { onExpand() }
    }

    // MARK: Buttons

    /// A borderless symbol button; `configure` gives it its symbol and label.
    private static func makeButton() -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        return button
    }

    private static func configure(_ button: NSButton, symbol: String, label: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }
}
