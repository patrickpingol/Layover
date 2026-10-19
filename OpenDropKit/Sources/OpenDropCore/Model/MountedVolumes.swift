import Foundation

/// Answers whether a volume is currently mounted, so a missing file can be told apart
/// from one on an ejected disk.
public protocol MountedVolumes: Sendable {
    func isMounted(volumeUUID: String) -> Bool
}

/// The volumes mounted on this Mac right now.
public struct SystemMountedVolumes: MountedVolumes {
    public init() {}

    public func isMounted(volumeUUID: String) -> Bool {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []
        return urls.contains { (try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString == volumeUUID }
    }
}
