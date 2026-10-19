import AppKit
import OpenDropCore
import os

/// One Shelf's content: the close, pin and expand buttons above either the compact stack or the grid.
/// It only presents; the coordinator owns the Shelf and applies the button actions.
@MainActor
final class ShelfViewController: NSViewController {
    private static let headerHeight: CGFloat = 28
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OpenDrop", category: "Drops")

    var onClose: () -> Void = {}
    var onTogglePin: () -> Void = {}
    /// Adds dropped contents to this Shelf and reports what happened to each. Called with no
    /// suspension since the contents were created, which Owned File cleanup relies on.
    var onAdd: ([ItemContent]) -> [Shelf.AddOutcome] = { _ in [] }

    private let importer: ItemImporter
    private var shelf: Shelf
    private var isExpanded = false

    private let compactView: ShelfCompactView
    private let gridController: ShelfGridViewController
    private let closeButton = ShelfViewController.makeButton()
    private let pinButton = ShelfViewController.makeButton()
    private let expandButton = ShelfViewController.makeButton()

    init(shelf: Shelf, thumbnails: ItemThumbnailProvider, importer: ItemImporter) {
        self.shelf = shelf
        self.importer = importer
        compactView = ShelfCompactView(thumbnails: thumbnails)
        gridController = ShelfGridViewController(thumbnails: thumbnails)
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
        root.onDrop = { [weak self] pasteboard in self?.handleDrop(pasteboard) ?? false }
        addChild(gridController)

        closeButton.action = #selector(close)
        pinButton.action = #selector(togglePin)
        expandButton.action = #selector(toggleExpanded)
        compactView.onStackClick = { [weak self] in self?.toggleExpanded() }

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
        view = root
        render()
    }

    func display(_ shelf: Shelf) {
        let sizeBefore = preferredSize
        self.shelf = shelf
        if shelf.items.isEmpty { isExpanded = false }
        render()
        if preferredSize != sizeBefore { (view.window as? ShelfPanel)?.resize(to: preferredSize) }
    }

    private func render() {
        compactView.display(shelf.items)
        gridController.display(shelf.items)
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
        if let reception = importer.beginReceivingPromises(from: pasteboard) {
            Task { [weak self] in
                do {
                    try await reception.receive { self?.add($0) }
                } catch {
                    Self.logger.error("Could not receive promised files: \(String(describing: error), privacy: .public)")
                }
            }
            return true
        }
        do {
            let contents = try importer.contents(from: pasteboard)
            guard !contents.isEmpty else { return false }
            add(contents)
            return true
        } catch {
            Self.logger.error("Could not import the dropped content: \(String(describing: error), privacy: .public)")
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
        if showsGrid {
            for id in duplicates { gridController.bounce(id) }
        } else {
            compactView.bounceStack()
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
