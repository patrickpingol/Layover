import AppKit

/// Something that reports changes to the drag pasteboard between `begin` and `end`.
@MainActor
protocol DragPasteboardWatching: AnyObject {
    func begin()
    func end()
}

/// Polls the drag pasteboard during a drag. A real drag and drop writes to it; moving a window or
/// selecting text doesn't, so a change tells a content drag apart from other mouse drags.
@MainActor
public final class DragPasteboardWatcher: DragPasteboardWatching {
    private let interval: TimeInterval
    private let onChange: () -> Void
    private let pasteboard = NSPasteboard(name: .drag)
    private var timer: Timer?
    private var lastChangeCount = 0

    public init(interval: TimeInterval = 0.05, onChange: @escaping () -> Void) {
        self.interval = interval
        self.onChange = onChange
    }

    /// Notes the pasteboard's current state and starts polling it. Does nothing while already polling.
    public func begin() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // A timer on the main run loop fires on the main thread.
            MainActor.assumeIsolated { self?.checkForChange() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops polling.
    public func end() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChange() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        onChange()
    }
}
