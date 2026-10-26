import AppKit

/// A system sharing service offered on an empty Shelf: dropping content on its target runs the service
/// on the content, and no Items are added. Cases are in the order their targets are laid out.
enum InstantAction: CaseIterable {
    case airDrop
    case mail
    case messages

    var title: String {
        switch self {
        case .airDrop: String(localized: "AirDrop")
        case .mail: String(localized: "Mail")
        case .messages: String(localized: "Messages")
        }
    }

    var symbolName: String {
        switch self {
        case .airDrop: "dot.radiowaves.left.and.right"
        case .mail: "envelope"
        case .messages: "message"
        }
    }

    var serviceName: NSSharingService.Name {
        switch self {
        case .airDrop: .sendViaAirDrop
        case .mail: .composeEmail
        case .messages: .composeMessage
        }
    }

    /// The actions whose service exists on this Mac.
    static var available: [InstantAction] {
        allCases.filter { NSSharingService(named: $0.serviceName) != nil }
    }

    /// The actions a Shelf offers: none when Instant Actions are off or the Shelf has Items.
    static func targets(isEnabled: Bool, shelfIsEmpty: Bool, available: [InstantAction] = available) -> [InstantAction] {
        isEnabled && shelfIsEmpty ? available : []
    }
}

/// Runs an Instant Action on sharing items; `onEnd` runs once the service is done. Returns whether it
/// started. `ItemActions.runInstantAction` is the real one; tests substitute their own.
typealias InstantActionRunner = @MainActor (InstantAction, [Any], @escaping () -> Void) -> Bool

/// Where the Instant Action targets sit in a Shelf's drop view: one row of equal targets, centered
/// below the Header. The drop view is not flipped, so frames are in y-up coordinates and the row is
/// measured down from the top. Everything below the row stays clear of targets, so a drop there still
/// adds Items. All the numbers are here so the look can be tuned in one place.
enum InstantActionLayout {
    static let headerHeight = ShelfViewController.headerHeight
    static let targetSize = CGSize(width: 50, height: 56)
    static let spacing: CGFloat = 3
    /// The gap between the Header and the row.
    static let topInset: CGFloat = 8

    /// How far below the Header the row ends: where the area left for dropping Items to keep starts.
    static let rowBottomInset = topInset + targetSize.height

    /// The frame of each of `count` targets, left to right, within `bounds`.
    static func frames(count: Int, in bounds: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        let rowWidth = CGFloat(count) * targetSize.width + CGFloat(count - 1) * spacing
        let originX = bounds.midX - rowWidth / 2
        let originY = bounds.maxY - headerHeight - topInset - targetSize.height
        return (0..<count).map { index in
            CGRect(
                x: originX + CGFloat(index) * (targetSize.width + spacing), y: originY,
                width: targetSize.width, height: targetSize.height
            )
        }
    }

    /// The index of the target (of `count`) under `point`, or nil when it is over none of them.
    static func target(at point: CGPoint, in bounds: CGRect, count: Int) -> Int? {
        frames(count: count, in: bounds).firstIndex { $0.contains(point) }
    }
}
