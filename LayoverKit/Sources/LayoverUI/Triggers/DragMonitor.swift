import AppKit
import Combine
import LayoverCore

/// Watches mouse drags anywhere on screen and calls `onNewShelf` when a drag is shaken, or the Drag Modifier
/// is held, while carrying content, as `ShakeTrigger` decides. A drag carries content once the drag
/// pasteboard changes or a drag image is on screen. The Drag Modifier is read from the drag events' own
/// modifier flags, so there is no key-event monitor, and global mouse monitors need no permission.
@MainActor
public final class DragMonitor {
    /// The windows are looked up at most this often during a drag; samples in between reuse them.
    private static let windowLookupInterval: TimeInterval = 0.1

    private let isShelfWindow: (Int) -> Bool
    private let windowsAt: (CGPoint) -> WindowsAtPoint
    private let onNewShelf: (CGPoint) -> Void
    private let makeWatcher: (@escaping () -> Void) -> any DragPasteboardWatching
    private lazy var watcher = makeWatcher { [weak self] in self?.handlePasteboardChange() }

    private var trigger = ShakeTrigger(sensitivity: .off, ignoredBundleIDs: [])
    /// The Drag Modifier `trigger` was built with, which the drag events' flags are read against.
    private var triggerDragModifier = DragModifier.off
    /// The latest preferences. They reach `trigger` only between drags, so a change mid-drag cannot reset
    /// what the drag in progress has already fired.
    private var settings = Settings(sensitivity: .off, ignoredBundleIDs: [], dragModifier: .off)
    private var isTriggerStale = false
    private var isStarted = false
    // Only touched on the main actor, and in deinit once nothing else can reach the monitor.
    nonisolated(unsafe) private var eventMonitor: Any?
    private var isDragging = false
    private var lastWindows: (time: Date, windows: WindowsAtPoint)?
    private var preferenceSubscription: AnyCancellable?

    private struct Settings {
        let sensitivity: ShakeSensitivity
        let ignoredBundleIDs: Set<String>
        let dragModifier: DragModifier
    }

    public convenience init(preferences: Preferences, isShelfWindow: @escaping (Int) -> Bool, onNewShelf: @escaping (CGPoint) -> Void) {
        self.init(
            preferences: preferences,
            isShelfWindow: isShelfWindow,
            windowsAt: WindowOwnerLookup.windows(at:),
            makeWatcher: { DragPasteboardWatcher(onChange: $0) },
            onNewShelf: onNewShelf
        )
    }

    init(
        preferences: Preferences,
        isShelfWindow: @escaping (Int) -> Bool,
        windowsAt: @escaping (CGPoint) -> WindowsAtPoint,
        makeWatcher: @escaping (@escaping () -> Void) -> any DragPasteboardWatching,
        onNewShelf: @escaping (CGPoint) -> Void
    ) {
        self.isShelfWindow = isShelfWindow
        self.windowsAt = windowsAt
        self.makeWatcher = makeWatcher
        self.onNewShelf = onNewShelf
        // @Published emits before the property changes, so the new values come from the publishers.
        preferenceSubscription = preferences.$shakeSensitivity
            .combineLatest(preferences.$ignoredBundleIDs, preferences.$dragModifier)
            .sink { [weak self] sensitivity, ignoredBundleIDs, dragModifier in
                self?.rebuildTrigger(sensitivity: sensitivity, ignoredBundleIDs: Set(ignoredBundleIDs), dragModifier: dragModifier)
            }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    /// Starts watching drags, unless both Shake and the Drag Modifier are off; it starts by itself when
    /// either is turned back on.
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

    func handleDrag(location: CGPoint, time: Date, windowNumber: Int, modifiers: NSEvent.ModifierFlags = []) {
        if !isDragging {
            isDragging = true
            watcher.begin()
        }
        // A drag that starts on a Shelf never triggers a Shake because global monitors never receive this app's
        // own events. `isOverShelf` is a seam for tests and a belt-and-braces check, not the guarantee.
        let windows = windows(at: location, time: time)
        let sample = DragSample(
            location: location,
            time: time,
            isOverShelf: isShelfWindow(windowNumber),
            ownerBundleID: windows.ownerBundleID,
            isModifierHeld: isModifierHeld(in: modifiers)
        )
        if let point = trigger.dragMoved(sample) {
            onNewShelf(point)
        } else if windows.showsDragImage, let point = trigger.contentDragDetected() {
            onNewShelf(point)
        }
    }

    func handleMouseUp() {
        isDragging = false
        lastWindows = nil
        watcher.end()
        trigger.mouseUp()
        rebuildTriggerIfIdle()
    }

    func handlePasteboardChange() {
        if let point = trigger.contentDragDetected() { onNewShelf(point) }
    }

    // MARK: Private

    private func rebuildTrigger(sensitivity: ShakeSensitivity, ignoredBundleIDs: Set<String>, dragModifier: DragModifier) {
        settings = Settings(sensitivity: sensitivity, ignoredBundleIDs: ignoredBundleIDs, dragModifier: dragModifier)
        isTriggerStale = true
        updateMonitoring()
        rebuildTriggerIfIdle()
    }

    /// Applies the latest settings once no drag is in progress; a drag in progress keeps its trigger.
    private func rebuildTriggerIfIdle() {
        guard isTriggerStale, !isDragging else { return }
        isTriggerStale = false
        triggerDragModifier = settings.dragModifier
        trigger = ShakeTrigger(sensitivity: settings.sensitivity, ignoredBundleIDs: settings.ignoredBundleIDs, dragModifier: settings.dragModifier)
    }

    private func isModifierHeld(in modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let flag = triggerDragModifier.flag else { return false }
        return modifiers.intersection(.deviceIndependentFlagsMask).contains(flag)
    }

    private func updateMonitoring() {
        let shouldMonitor = isStarted && (settings.sensitivity != .off || settings.dragModifier != .off)
        if shouldMonitor, eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let isDrag = event.type == .leftMouseDragged
                let windowNumber = event.windowNumber
                let modifiers = event.modifierFlags
                // Global monitors are called on the main thread.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if isDrag {
                        self.handleDrag(location: NSEvent.mouseLocation, time: .now, windowNumber: windowNumber, modifiers: modifiers)
                    } else {
                        self.handleMouseUp()
                    }
                }
            }
        } else if !shouldMonitor, let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        // No mouse-up arrives once monitoring stops, so end a drag in progress here.
        if !shouldMonitor, isDragging {
            handleMouseUp()
        }
    }

    private func windows(at location: CGPoint, time: Date) -> WindowsAtPoint {
        if let lastWindows, time.timeIntervalSince(lastWindows.time) < Self.windowLookupInterval {
            return lastWindows.windows
        }
        let windows = windowsAt(location)
        lastWindows = (time, windows)
        return windows
    }
}

private extension DragModifier {
    /// The event flag that means the key is held; nil when there is no Drag Modifier.
    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .off: nil
        case .command: .command
        case .control: .control
        case .shift: .shift
        }
    }
}
