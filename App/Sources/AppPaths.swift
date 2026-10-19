import Foundation

/// Where OpenDrop keeps its files, inside the sandbox container.
enum AppPaths {
    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.opendrop.OpenDrop", isDirectory: true)
    }

    /// The saved Shelves.
    static var shelvesFile: URL {
        supportDirectory.appendingPathComponent("shelves.json")
    }

    /// Where Owned Files live.
    static var ownedFilesDirectory: URL {
        supportDirectory.appendingPathComponent("OwnedFiles", isDirectory: true)
    }
}
