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
    /// The Drag Modifier key is held. Ignored when no Drag Modifier is set.
    public var isModifierHeld: Bool

    public init(location: CGPoint, time: Date, isOverShelf: Bool, ownerBundleID: String?, isModifierHeld: Bool = false) {
        self.location = location
        self.time = time
        self.isOverShelf = isOverShelf
        self.ownerBundleID = ownerBundleID
        self.isModifierHeld = isModifierHeld
    }
}

/// Decides when a drag should open a Shelf: a Shake was recognized or the Drag Modifier was
/// held, and the drag was seen carrying content during the same drag, in any order. Fires at
/// most once per drag, never over an Ignored App, and never for a drag that started over a Shelf.
public struct ShakeTrigger: Sendable {
    private let ignoredBundleIDs: Set<String>
    private let dragModifier: DragModifier
    private var detector: ShakeDetector?

    private var isDragging = false
    private var isSuppressed = false
    private var hasFired = false
    private var contentDetected = false
    private var modifierSeen = false
    private var lastSample: DragSample?

    public init(sensitivity: ShakeSensitivity, ignoredBundleIDs: Set<String>, dragModifier: DragModifier = .off) {
        self.ignoredBundleIDs = ignoredBundleIDs
        self.dragModifier = dragModifier
        detector = sensitivity.parameters.map(ShakeDetector.init(parameters:))
    }

    /// Returns the location to open a Shelf at, or nil. The modifier is latched once seen, so it need
    /// only be held at some point during the drag, and it works with Shake off.
    public mutating func dragMoved(_ sample: DragSample) -> CGPoint? {
        if !isDragging {
            isDragging = true
            isSuppressed = sample.isOverShelf
            hasFired = false
            contentDetected = false
            modifierSeen = false
            detector?.reset()
        }
        lastSample = sample
        guard !isSuppressed else { return nil }
        detector?.feed(x: sample.location.x, at: sample.time)
        if dragModifier != .off, sample.isModifierHeld { modifierSeen = true }
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
              detector?.isRecognized == true || modifierSeen,
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
