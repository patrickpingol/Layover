import AppKit
import Testing
@testable import OpenDropUI

@Test @MainActor func aShowingWithNoHostWindowEndsAtOnce() {
    var endCount = 0

    QuickLookPresenter.shared.show([URL(fileURLWithPath: "/tmp/a.txt")], from: nil) { endCount += 1 }

    #expect(endCount == 1)
    #expect(!QuickLookPresenter.shared.isShowing)
}

@Test @MainActor func aWindowThatHostsNoShowingDoesNotAcceptControl() {
    let window = NSWindow()

    #expect(!QuickLookPresenter.shared.accepts(control: window))
    // Ending control it never had changes nothing.
    QuickLookPresenter.shared.end(control: window)
}
