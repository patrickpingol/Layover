import AppKit
import Foundation
import Testing
@testable import LayoverUI

// MARK: Targets

@Test func theTargetsAreAirDropMailAndMessagesInThatOrder() {
    #expect(InstantAction.allCases == [.airDrop, .mail, .messages])
    #expect(InstantAction.allCases.map(\.serviceName) == [.sendViaAirDrop, .composeEmail, .composeMessage])
    #expect(Set(InstantAction.allCases.map(\.symbolName)).count == 3)
    // A name that is not a system symbol leaves the target without an icon.
    #expect(InstantAction.allCases.allSatisfy { NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: nil) != nil })
    #expect(InstantAction.allCases.allSatisfy { !$0.title.isEmpty })
}

@Test func anEnabledEmptyShelfOffersEveryAvailableAction() {
    let targets = InstantAction.targets(isEnabled: true, shelfIsEmpty: true, available: InstantAction.allCases)

    #expect(targets == InstantAction.allCases)
}

@Test func aDisabledShelfOffersNoActions() {
    #expect(InstantAction.targets(isEnabled: false, shelfIsEmpty: true, available: InstantAction.allCases).isEmpty)
}

@Test func aShelfWithItemsOffersNoActions() {
    #expect(InstantAction.targets(isEnabled: true, shelfIsEmpty: false, available: InstantAction.allCases).isEmpty)
}

@Test func onlyTheActionsWhoseServiceExistsAreOffered() {
    let targets = InstantAction.targets(isEnabled: true, shelfIsEmpty: true, available: [.mail, .messages])

    #expect(targets == [.mail, .messages])
}

// MARK: Layout

private let shelfBounds = CGRect(x: 0, y: 0, width: 160, height: 184)

@Test func theTargetsFormOneCenteredRowBelowTheHeader() {
    let frames = InstantActionLayout.frames(count: 3, in: shelfBounds)

    #expect(frames.count == 3)
    #expect(frames.allSatisfy { $0.size == InstantActionLayout.targetSize })
    #expect(Set(frames.map(\.minY)).count == 1)
    #expect(frames[0].maxX + InstantActionLayout.spacing == frames[1].minX)
    #expect(frames[1].maxX + InstantActionLayout.spacing == frames[2].minX)
    #expect(abs(frames[0].minX - (shelfBounds.maxX - frames[2].maxX)) < 0.001)
    #expect(frames[0].maxY <= shelfBounds.maxY - InstantActionLayout.headerHeight)
    #expect(frames.allSatisfy { shelfBounds.contains($0) })
}

@Test func thereIsRoomToDropElsewhereBelowTheTargets() {
    let frames = InstantActionLayout.frames(count: 3, in: shelfBounds)
    let clearHeight = frames.map(\.minY).min()!

    #expect(clearHeight >= 40)
    #expect(InstantActionLayout.target(at: CGPoint(x: 80, y: clearHeight / 2), in: shelfBounds, count: 3) == nil)
}

@Test func noTargetsHaveNoFramesAndNoHit() {
    #expect(InstantActionLayout.frames(count: 0, in: shelfBounds).isEmpty)
    #expect(InstantActionLayout.target(at: CGPoint(x: 80, y: 120), in: shelfBounds, count: 0) == nil)
}

@Test func aPointInsideATargetHitsIt() {
    let frames = InstantActionLayout.frames(count: 3, in: shelfBounds)

    for (index, frame) in frames.enumerated() {
        #expect(InstantActionLayout.target(at: CGPoint(x: frame.midX, y: frame.midY), in: shelfBounds, count: 3) == index)
    }
}

@Test func theHitTestIsExactAtTheEdges() {
    let frame = InstantActionLayout.frames(count: 3, in: shelfBounds)[1]
    func hit(_ x: CGFloat, _ y: CGFloat) -> Int? {
        InstantActionLayout.target(at: CGPoint(x: x, y: y), in: shelfBounds, count: 3)
    }

    #expect(hit(frame.minX, frame.midY) == 1)
    #expect(hit(frame.minX - 0.01, frame.midY) == nil)
    #expect(hit(frame.maxX - 0.01, frame.midY) == 1)
    #expect(hit(frame.maxX, frame.midY) == nil)
    #expect(hit(frame.midX, frame.minY) == 1)
    #expect(hit(frame.midX, frame.minY - 0.01) == nil)
    #expect(hit(frame.midX, frame.maxY) == nil)
}

@Test func theGapsBetweenTargetsAndTheHeaderAreNotTargets() {
    let frames = InstantActionLayout.frames(count: 3, in: shelfBounds)
    let gap = CGPoint(x: (frames[0].maxX + frames[1].minX) / 2, y: frames[0].midY)
    let header = CGPoint(x: frames[0].midX, y: shelfBounds.maxY - 1)

    #expect(InstantActionLayout.target(at: gap, in: shelfBounds, count: 3) == nil)
    #expect(InstantActionLayout.target(at: header, in: shelfBounds, count: 3) == nil)
}

@Test func fewerTargetsLeaveTheRestOfTheRowClear() {
    let three = InstantActionLayout.frames(count: 3, in: shelfBounds)

    #expect(InstantActionLayout.target(at: CGPoint(x: three[2].midX, y: three[2].midY), in: shelfBounds, count: 2) == nil)
}

// MARK: Content

@MainActor
private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
    let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
    pasteboard.clearContents()
    defer { pasteboard.releaseGlobally() }
    try body(pasteboard)
}

private func pngData() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

@Test @MainActor func fileURLsAreSharedAsTheyAre() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("a.txt")
    try Data("a".utf8).write(to: url)

    try withPasteboard { pasteboard in
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString("ignored", forType: .string)

        let items = InstantActionContent.items(from: pasteboard)

        #expect(items.compactMap { $0 as? URL }.map(\.path) == [url.path])
        #expect(items.count == 1)
    }
}

@Test @MainActor func imageDataIsSharedAsAnImageBeforeTheItsURLOrText() {
    withPasteboard { pasteboard in
        pasteboard.declareTypes([.png, .URL, .string], owner: nil)
        pasteboard.setData(pngData(), forType: .png)
        pasteboard.setString("https://example.com/a.png", forType: .URL)
        pasteboard.setString("a.png", forType: .string)

        let items = InstantActionContent.items(from: pasteboard)

        #expect(items.count == 1)
        #expect(items.first is NSImage)
    }
}

@Test @MainActor func tiffDataIsSharedAsAnImage() {
    withPasteboard { pasteboard in
        let tiff = NSBitmapImageRep(data: pngData())!.tiffRepresentation!
        pasteboard.declareTypes([.tiff], owner: nil)
        pasteboard.setData(tiff, forType: .tiff)

        #expect(InstantActionContent.items(from: pasteboard).first is NSImage)
    }
}

@Test @MainActor func aWebURLIsSharedAsAURLBeforeText() {
    withPasteboard { pasteboard in
        pasteboard.declareTypes([.URL, .string], owner: nil)
        pasteboard.setString("https://example.com/page", forType: .URL)
        pasteboard.setString("A page", forType: .string)

        let items = InstantActionContent.items(from: pasteboard)

        #expect(items.compactMap { $0 as? URL } == [URL(string: "https://example.com/page")!])
        #expect(items.count == 1)
    }
}

@Test @MainActor func aNonWebURLFallsBackToText() {
    withPasteboard { pasteboard in
        pasteboard.declareTypes([.URL, .string], owner: nil)
        pasteboard.setString("ftp://example.com/x", forType: .URL)
        pasteboard.setString("hello", forType: .string)

        #expect(InstantActionContent.items(from: pasteboard).compactMap { $0 as? String } == ["hello"])
    }
}

@Test @MainActor func textIsSharedAsAString() {
    withPasteboard { pasteboard in
        pasteboard.setString("hello", forType: .string)

        #expect(InstantActionContent.items(from: pasteboard).compactMap { $0 as? String } == ["hello"])
    }
}

@Test @MainActor func nothingAcceptedMeansNothingToShare() {
    withPasteboard { pasteboard in
        pasteboard.setString("", forType: .string)
        #expect(InstantActionContent.items(from: pasteboard).isEmpty)
    }
    withPasteboard { pasteboard in
        let type = NSPasteboard.PasteboardType("com.example.unknown")
        pasteboard.declareTypes([type], owner: nil)
        pasteboard.setString("x", forType: type)
        #expect(InstantActionContent.items(from: pasteboard).isEmpty)
    }
}
