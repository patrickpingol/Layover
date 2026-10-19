# Sandboxed from day one

OpenDrop ships as a direct download, which doesn't require the App Sandbox. We still enable it, along with hardened runtime and notarization, from the first commit. Retrofitting the sandbox later would invalidate every saved Item reference and move user-script and screenshot-folder locations, and we want a future App Store release to stay possible.

## Consequences

- Every Item that refers to a file stores a security-scoped bookmark, and access to it is started and stopped explicitly.
- User scripts must live in `~/Library/Application Scripts/<bundle-id>`.
- Watching folders (such as the screenshot folder) requires the user to pick the folder once.
- Shelf detection must use sandbox-safe APIs only: global NSEvent mouse monitors and the drag pasteboard, with no Accessibility or event taps.
