import Foundation
import Testing
@testable import LayoverUI

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

@Test @MainActor func noticesShowOneAtATimeInOrder() async {
    let view = ShelfNoticeView(duration: .milliseconds(60))
    #expect(view.currentMessage == nil)

    view.show(["first", "second"])
    #expect(view.currentMessage == "first")

    await waitUntil { view.currentMessage == "second" }
    #expect(view.currentMessage == "second")

    await waitUntil { view.currentMessage == nil }
    #expect(view.currentMessage == nil)
}

@Test @MainActor func noticesAddedWhileOneShowsJoinTheQueue() async {
    let view = ShelfNoticeView(duration: .milliseconds(60))
    view.show(["first"])
    view.show(["second"])
    #expect(view.currentMessage == "first")

    await waitUntil { view.currentMessage == "second" }
    #expect(view.currentMessage == "second")
}
