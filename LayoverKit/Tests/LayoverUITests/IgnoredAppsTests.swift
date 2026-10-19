import Testing
@testable import LayoverUI

@Test func newBundleIDsAreAppendedInOrder() {
    #expect(IgnoredApps.adding(["com.b", "com.c"], to: ["com.a"]) == ["com.a", "com.b", "com.c"])
}

@Test func anAlreadyIgnoredAppIsNotAddedAgain() {
    #expect(IgnoredApps.adding(["com.a", "com.b"], to: ["com.a"]) == ["com.a", "com.b"])
}

@Test func theSameAppChosenTwiceIsAddedOnce() {
    #expect(IgnoredApps.adding(["com.b", "com.b"], to: []) == ["com.b"])
}

@Test func anAppWithoutABundleIDIsSkipped() {
    #expect(IgnoredApps.adding([nil, "com.b", nil], to: ["com.a"]) == ["com.a", "com.b"])
}

@Test func addingNothingChangesNothing() {
    #expect(IgnoredApps.adding([], to: ["com.a"]) == ["com.a"])
    #expect(IgnoredApps.adding([nil], to: []) == [])
}
