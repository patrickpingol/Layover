import Foundation
import Testing
@testable import OpenDropCore

private struct FixedVolumes: MountedVolumes {
    let mounted: Bool
    func isMounted(volumeUUID: String) -> Bool { mounted }
}

/// Creates a fresh temp directory, runs `body`, and removes the directory afterwards.
private func withTempDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

private func makeFile(in dir: URL, named name: String = "a.txt") throws -> URL {
    let url = dir.appendingPathComponent(name)
    try Data("hello".utf8).write(to: url)
    return url
}

/// Compares paths after resolving symlinks (`/var` vs `/private/var`).
private func samePath(_ a: URL, _ b: URL) -> Bool {
    a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
}

@Test func resolveFollowsRename() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir)
        let reference = try FileReference.make(for: url, securityScoped: false)
        let renamed = dir.appendingPathComponent("b.txt")
        try FileManager.default.moveItem(at: url, to: renamed)

        let resolution = reference.resolve(volumes: FixedVolumes(mounted: true), securityScoped: false)

        guard case let .available(resolved, updated) = resolution else {
            Issue.record("expected .available, got \(resolution)")
            return
        }
        #expect(samePath(resolved, renamed))
        #expect(updated != nil)
        if let updated {
            #expect(samePath(URL(fileURLWithPath: updated.lastKnownPath), renamed))
            #expect(updated.identity == reference.identity)
        }
    }
}

@Test func resolveUnchangedFileHasNoUpdate() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir)
        let reference = try FileReference.make(for: url, securityScoped: false)

        let resolution = reference.resolve(volumes: FixedVolumes(mounted: true), securityScoped: false)

        guard case let .available(resolved, updated) = resolution else {
            Issue.record("expected .available, got \(resolution)")
            return
        }
        #expect(samePath(resolved, url))
        #expect(updated == nil)
    }
}

@Test func resolveDeletedFileOnMountedVolume() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir)
        let reference = try FileReference.make(for: url, securityScoped: false)
        try FileManager.default.removeItem(at: url)

        #expect(reference.resolve(volumes: FixedVolumes(mounted: true), securityScoped: false) == .deleted)
    }
}

@Test func resolveMissingVolumeIsUnavailable() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir)
        let reference = try FileReference.make(for: url, securityScoped: false)
        try FileManager.default.removeItem(at: url)

        #expect(reference.resolve(volumes: FixedVolumes(mounted: false), securityScoped: false) == .unavailable)
    }
}

@Test func resolveTreatsTrashAsDeleted() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir, named: "x.txt")
        let reference = try FileReference.make(for: url, securityScoped: false)
        let trash = dir.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent("x.txt"))

        // Unmounted volumes make a failed resolution `.unavailable`, so `.deleted` proves the Trash check ran.
        #expect(reference.resolve(volumes: FixedVolumes(mounted: false), securityScoped: false) == .deleted)
    }
}

@Test func referenceRoundTripsThroughJSON() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir)
        let reference = try FileReference.make(for: url, securityScoped: false)

        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(FileReference.self, from: data)

        #expect(decoded == reference)
    }
}

@Test func identityIsStableForSameFileAndDiffersForCopies() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir)
        let copy = dir.appendingPathComponent("copy.txt")
        try FileManager.default.copyItem(at: url, to: copy)

        #expect(try FileIdentity(of: url) == FileIdentity(of: url))
        #expect(try FileIdentity(of: url) != FileIdentity(of: copy))
    }
}

@Test func identityOfMissingFileThrows() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(throws: (any Error).self) { try FileIdentity(of: missing) }
}

@Test func systemMountedVolumesKnowsBootVolumeAndNotUnknown() throws {
    let identity = try FileIdentity(of: URL(fileURLWithPath: "/"))
    let volumes = SystemMountedVolumes()
    #expect(volumes.isMounted(volumeUUID: identity.volumeUUID))
    #expect(!volumes.isMounted(volumeUUID: UUID().uuidString))
}

@Test func identityFallsBackToVolumeURLAndInode() throws {
    try withTempDirectory { dir in
        let url = try makeFile(in: dir)
        let real = try FileIdentity(of: url)
        let volumeURL = URL(string: "smb://server/share/")!

        let fallback = try FileIdentity(volumeUUIDString: nil, fileIdentifier: nil, volumeURL: volumeURL, path: url.path)

        #expect(fallback.volumeUUID == "smb://server/share/")
        #expect(fallback.fileID == real.fileID)
    }
}

@Test func identityPrefersReportedValuesOverFallbacks() throws {
    let identity = try FileIdentity(volumeUUIDString: "UUID", fileIdentifier: 7, volumeURL: URL(string: "smb://x/")!, path: "/nonexistent")
    #expect(identity == FileIdentity(volumeUUID: "UUID", fileID: 7))
}

@Test func identityThrowsWhenFallbacksUnavailable() {
    #expect(throws: (any Error).self) {
        try FileIdentity(volumeUUIDString: nil, fileIdentifier: 1, volumeURL: nil, path: "/")
    }
    #expect(throws: (any Error).self) {
        try FileIdentity(volumeUUIDString: "UUID", fileIdentifier: nil, volumeURL: nil, path: "/nonexistent/\(UUID().uuidString)")
    }
}

@Test func systemMountedVolumesRecognisesVolumeURLFallback() {
    let volumes = SystemMountedVolumes()
    #expect(volumes.isMounted(volumeUUID: "file:///"))
    #expect(!volumes.isMounted(volumeUUID: "smb://nowhere/\(UUID().uuidString)/"))
}
