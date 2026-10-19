import Foundation

/// Identifies a file on disk independent of its path: the volume it lives on plus its file ID.
/// A hard link has the same identity as the original; a copy does not.
public struct FileIdentity: Codable, Hashable, Sendable {
    public var volumeUUID: String
    public var fileID: UInt64

    public init(volumeUUID: String, fileID: UInt64) {
        self.volumeUUID = volumeUUID
        self.fileID = fileID
    }

    /// Reads the identity of the file at `url`. Some network volumes report no volume UUID or file
    /// identifier, so the volume's URL stands in for the UUID and `stat()`'s inode for the file ID.
    /// Throws if the file doesn't exist or even the fallbacks can't be read.
    public init(of url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeUUIDStringKey, .fileIdentifierKey, .volumeURLKey])
        try self.init(
            volumeUUIDString: values.volumeUUIDString,
            fileIdentifier: (values.fileIdentifier as? NSNumber)?.uint64Value,
            volumeURL: values.volume,
            path: url.path
        )
    }

    /// The resource values are injected so the fallbacks can be tested without a network volume.
    init(volumeUUIDString: String?, fileIdentifier: UInt64?, volumeURL: URL?, path: String) throws {
        guard let volumeUUID = volumeUUIDString ?? volumeURL?.absoluteString else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: path])
        }
        var fileID = fileIdentifier
        if fileID == nil {
            var info = stat()
            if stat(path, &info) == 0 { fileID = UInt64(info.st_ino) }
        }
        guard let fileID else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: path])
        }
        self.init(volumeUUID: volumeUUID, fileID: fileID)
    }
}
