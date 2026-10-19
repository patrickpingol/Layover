import AppKit
import Combine
import LayoverCore

/// Watches mouse drags anywhere on screen and calls `onShake` when a drag is shaken while
/// carrying content, as `ShakeTrigger` decides. Global mouse monitors need no permission.
@MainActor
public final class DragMonitor {
    /// The window owner is looked up at most this often during a drag; samples in between reuse it.
    private static let ownerLookupInterval: TimeInterval = 0.1

    private let isShelfWindow: (Int) -> Bool
    private let ownerBundleID: (CGPoint) -> String?
    private let onShake: (CGPoint) -> Void
    private let makeWatcher: (@escaping () -> Void) -> any DragPasteboardWatching
    private lazy var watcher = makeWatcher { [weak self] in self?.handlePasteboardChange() }

    private var trigger = ShakeTrigger(sensitivity: .off, ignoredBundleIDs: [])
    private var sensitivity = ShakeSensitivity.off
    private var isStarted = false
    // Only touched on the main actor, and in deinit once nothing else can reach the monitor.
    nonisolated(unsafe) private var eventMonitor: Any?
    private var isDragging = false
    private var lastOwner: (time: Date, bundleID: String?)?
    private var preferenceSubscription: AnyCancellable?

    public convenience init(preferences: Preferences, isShelfWindow: @escaping (Int) -> Bool, onShake: @escaping (CGPoint) -> Void) {
        self.init(
            preferences: preferences,
            isShelfWindow: isShelfWindow,
            ownerBundleID: WindowOwnerLookup.bundleID(at:),
            makeWatcher: { DragPasteboardWatcher(onChange: $0) },
            onShake: onShake
        )
    }

    init(
        preferences: Preferences,
        isShelfWindow: @escaping (Int) -> Bool,
        ownerBundleID: @escaping (CGPoint) -> String?,
        makeWatcher: @escaping (@escaping () -> Void) -> any DragPasteboardWatching,
        onShake: @escaping (CGPoint) -> Void
    ) {
        self.isShelfWindow = isShelfWindow
        self.ownerBundleID = ownerBundleID
        self.makeWatcher = makeWatcher
        self.onShake = onShake
        // @Published emits before the property changes, so the new values come from the publishers.
        preferenceSubscription = preferences.$shakeSensitivity
            .combineLatest(preferences.$ignoredBundleIDs)
            .sink { [weak self] sensitivity, ignoredBundleIDs in
                self?.rebuildTrigger(sensitivity: sensitivity, ignoredBundleIDs: Set(ignoredBundleIDs))
            }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    /// Starts watching drags, unless Shake is off; it starts by itself when Shake is turned back on.
    public func start() {
        isStarted = true
        updateMonitoring()
    }

    public func stop() {
        isStarted = false
        updateMonitoring()
    }

    var isMonitoring: Bool { eventMonitor != nil }

    // MARK: Events

    func handleDrag(location: CGPoint, time: Date, windowNumber: Int) {
        if !isDragging {
            isDragging = true
            watcher.begin()
        }
        // A drag that starts on a Shelf never triggers a Shake because global monitors never receive this app's
        // own events. `isOverShelf` is a seam for tests and a belt-and-braces check, not the guarantee.
        let sample = DragSample(
            location: location,
            time: time,
            isOverShelf: isShelfWindow(windowNumber),
            ownerBundleID: owner(at: location, time: time)
        )
        if let point = trigger.dragMoved(sample) { onShake(point) }
    }

    func handleMouseUp() {
        isDragging = false
        lastOwner = nil
        watcher.end()
        trigger.mouseUp()
    }

    func handlePasteboardChange() {
        if let point = trigger.dragPasteboardChanged() { onShake(point) }
    }

    // MARK: Private

    private func rebuildTrigger(sensitivity: ShakeSensitivity, ignoredBundleIDs: Set<String>) {
        self.sensitivity = sensitivity
        trigger = ShakeTrigger(sensitivity: sensitivity, ignoredBundleIDs: ignoredBundleIDs)
        updateMonitoring()
    }

    private func updateMonitoring() {
        let shouldMonitor = isStarted && sensitivity != .off
        if shouldMonitor, eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let isDrag = event.type == .leftMouseDragged
                let windowNumber = event.windowNumber
                // Global monitors are called on the main thread.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if isDrag {
                        self.handleDrag(location: NSEvent.mouseLocation, time: .now, windowNumber: windowNumber)
                    } else {
                        self.handleMouseUp()
                    }
                }
            }
        } else if !shouldMonitor, let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
            handleMouseUp()
        }
    }

    private func owner(at location: CGPoint, time: Date) -> String? {
        if let lastOwner, time.timeIntervalSince(lastOwner.time) < Self.ownerLookupInterval {
            return lastOwner.bundleID
        }
        let bundleID = ownerBundleID(location)
        lastOwner = (time, bundleID)
        return bundleID
    }
}
