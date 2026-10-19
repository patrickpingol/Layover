import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

@Test func fileItemDisplayNameIsLastPathComponent() {
    let reference = FileReference(
        bookmark: Data(),
        lastKnownPath: "/Users/someone/Documents/report.pdf",
        identity: FileIdentity(volumeUUID: "vol", fileID: 1)
    )
    let item = Item(id: UUID(), content: .file(reference))
    #expect(item.displayName == "report.pdf")
}

@Test func ownedItemDisplayNameIsFilename() {
    let owned = OwnedFile(id: UUID(), filename: "note.txt", kind: .text)
    let item = Item(id: UUID(), content: .owned(owned))
    #expect(item.displayName == "note.txt")
}
