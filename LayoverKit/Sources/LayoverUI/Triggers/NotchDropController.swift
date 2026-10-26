import AppKit
import Combine
import LayoverCore

/// Shows the Notch Drop target, one panel per notched screen, for as long as a drag that carries content
/// is in progress, and opens a new Shelf holding whatever is dropped on a notch. There is no window
/// between drags.
@MainActor
public final class NotchDropController {
    /// What the controller needs of a panel, so tests can stand in for the windows.
    typealias PanelFactory = (
        _ notch: CGRect, _ highlight: NotchDropHighlight, _ isDragAcceptable: Bool, _ onDrop: @escaping (NSPasteboard) -> Bool
    ) -> any NotchDropWindow

    /// The global mouse-up that ends a drag can reach `DragMonitor` before the drop reaches the panel, so
    /// the panels outlive the end of the drag by this much.
    static let hideDelay: Duration = .milliseconds(500)

    private let preferences: Preferences
    private let coordinator: ShelfCoordinator
    private let hideDelay: Duration
    private let sleep: (Duration) async -> Void
    private let notchRects: () -> [CGRect]
    private let makePanel: PanelFactory
    private var panels: [any NotchDropWindow] = []
    private(set) var pendingHide: Task<Void, Never>?
    private var notchDropSubscription: AnyCancellable?

    public convenience init(preferences: Preferences, coordinator: ShelfCoordinator) {
        self.init(preferences: preferences, coordinator: coordinator, hideDelay: Self.hideDelay)
    }

    /// `sleep` returns early when its task is cancelled; `notchRects` is the notch of every notched screen,
    /// in screen coordinates. Tests replace all three of those and `makePanel`.
    init(
        preferences: Preferences,
        coordinator: ShelfCoordinator,
        hideDelay: Duration,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        notchRects: @escaping () -> [CGRect] = { NSScreen.screens.compactMap(\.notchRect) },
        makePanel: @escaping PanelFactory = { NotchDropPanel(notch: $0, highlight: $1, isDragAcceptable: $2, onDrop: $3) }
    ) {
        self.preferences = preferences
        self.coordinator = coordinator
        self.hideDelay = hideDelay
        self.sleep = sleep
        self.notchRects = notchRects
        self.makePanel = makePanel
        // Turning Notch Drop off takes the panels away at once; the mouse-up grace is not for this.
        notchDropSubscription = preferences.$notchDropEnabled
            .sink { [weak self] isEnabled in
                if !isEnabled { self?.hideNow() }
            }
    }

    /// A drag carrying content began: puts a panel over the notch of every notched screen.
    public func contentDragBegan() {
        cancelPendingHide()
        closePanels()
        let highlight = preferences.notchDropHighlight
        let isDragAcceptable = ItemImporter.accepts(NSPasteboard(name: .drag))
        panels = notchRects().map { notch in
            makePanel(notch, highlight, isDragAcceptable) { [weak self] pasteboard in
                self?.handleDrop(pasteboard, on: notch) ?? false
            }
        }
        for panel in panels { panel.orderFrontRegardless() }
    }

    /// The drag ended: takes the panels away, after `hideDelay` so a drop that is still arriving lands.
    public func dragEnded() {
        guard !panels.isEmpty else { return }
        cancelPendingHide()
        pendingHide = Task { [weak self, hideDelay, sleep] in
            await sleep(hideDelay)
            guard !Task.isCancelled else { return }
            self?.closePanels()
        }
    }

    private func handleDrop(_ pasteboard: NSPasteboard, on notch: CGRect) -> Bool {
        guard preferences.notchDropEnabled else { return false }
        let taken = coordinator.openNewShelf(at: NotchGeometry.bottomCenter(of: notch), receiving: pasteboard)
        // The drop is done, so the panels go, but not from inside the callback AppKit is still running.
        cancelPendingHide()
        pendingHide = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.closePanels()
        }
        return taken
    }

    private func hideNow() {
        cancelPendingHide()
        closePanels()
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    private func closePanels() {
        for panel in panels { panel.close() }
        panels = []
    }
}

/// The part of a Notch Drop panel the controller drives; `NSWindow` already has both.
@MainActor
protocol NotchDropWindow: AnyObject {
    func orderFrontRegardless()
    func close()
}

extension NotchDropPanel: NotchDropWindow {}
