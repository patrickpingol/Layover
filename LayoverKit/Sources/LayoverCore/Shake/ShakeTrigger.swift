import CoreGraphics
import Foundation

/// One cursor position during a drag, with what is under it.
public struct DragSample: Sendable {
    public var location: CGPoint
    public var time: Date
    /// The cursor is over one of our own Shelves.
    public var isOverShelf: Bool
    /// Bundle ID of the app owning the window under the cursor, if known.
    public var ownerBundleID: String?

    public init(location: CGPoint, time: Date, isOverShelf: Bool, ownerBundleID: String?) {
        self.location = location
        self.time = time
        self.isOverShelf = isOverShelf
        self.ownerBundleID = ownerBundleID
    }
}

/// Decides when a drag should open a Shelf: a Shake was recognized and the drag was
/// seen carrying content during the same drag, in either order. Fires at most once
/// per drag, never over an Ignored App, and never for a drag that started over a Shelf.
public struct ShakeTrigger: Sendable {
    private let ignoredBundleIDs: Set<String>
    private var detector: ShakeDetector?

    private var isDragging = false
    private var isSuppressed = false
    private var hasFired = false
    private var contentDetected = false
    private var lastSample: DragSample?

    public init(sensitivity: ShakeSensitivity, ignoredBundleIDs: Set<String>) {
        self.ignoredBundleIDs = ignoredBundleIDs
        detector = sensitivity.parameters.map(ShakeDetector.init(parameters:))
    }

    /// Returns the location to open a Shelf at, or nil.
    public mutating func dragMoved(_ sample: DragSample) -> CGPoint? {
        guard var detector else { return nil }
        if !isDragging {
            isDragging = true
            isSuppressed = sample.isOverShelf
            hasFired = false
            contentDetected = false
            detector.reset()
        }
        lastSample = sample
        guard !isSuppressed else {
            self.detector = detector
            return nil
        }
        detector.feed(x: sample.location.x, at: sample.time)
        self.detector = detector
        return firePointIfReady()
    }

    /// The drag carries content: the drag pasteboard changed or a drag image is on screen. Returns the
    /// last drag location to open a Shelf at, or nil.
    public mutating func contentDragDetected() -> CGPoint? {
        guard isDragging else { return nil }
        contentDetected = true
        return firePointIfReady()
    }

    /// Ends the drag; the next `dragMoved` starts a new one.
    public mutating func mouseUp() {
        isDragging = false
        lastSample = nil
    }

    private mutating func firePointIfReady() -> CGPoint? {
        guard !isSuppressed, !hasFired, contentDetected,
              detector?.isRecognized == true,
              let sample = lastSample,
              !isIgnored(sample.ownerBundleID)
        else { return nil }
        hasFired = true
        return sample.location
    }

    private func isIgnored(_ bundleID: String?) -> Bool {
        bundleID.map(ignoredBundleIDs.contains) ?? false
    }
}
