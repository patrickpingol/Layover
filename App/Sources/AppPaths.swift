import Foundation

/// Where OpenDrop keeps its files, inside the sandbox container.
enum AppPaths {
    private static var supportDirectory: URL {
        // The bundle identifier is defined only in project.yml. It is nil only outside an app bundle
        // (such as a bare command-line run), where this fallback keeps the path stable.
        let bundleID = Bundle.main.bundleIdentifier ?? "OpenDrop"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
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
