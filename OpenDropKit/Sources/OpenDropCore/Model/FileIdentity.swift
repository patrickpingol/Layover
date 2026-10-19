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

    /// Reads the identity of the file at `url`. Throws if the file doesn't exist or either value is unavailable.
    public init(of url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeUUIDStringKey, .fileIdentifierKey])
        guard let volumeUUID = values.volumeUUIDString,
              let fileID = (values.fileIdentifier as? NSNumber)?.uint64Value
        else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: url])
        }
        self.init(volumeUUID: volumeUUID, fileID: fileID)
    }
}
