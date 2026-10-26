# Layover

Layover is a macOS menu-bar utility for temporarily collecting dragged content. Shake while dragging, hold an optional modifier key (chosen in Settings) during a drag, or press a hot key, and a floating Shelf appears at the cursor. Drop files, text, links and images onto it, then drag everything out again when you reach the destination. Files stay where they are and are referenced in place. Layover is sandboxed and asks for no Accessibility, Input Monitoring or Screen Recording permission.

## Install

Download `Layover-<version>.dmg` from the [latest release](https://github.com/patrickpingol/Layover/releases/latest), open it, drag `Layover.app` onto the Applications shortcut, then eject the disk image. Layover is signed with its own certificate rather than an Apple Developer ID, so on first launch macOS says it can't verify the developer. Open System Settings → Privacy & Security and click **Open Anyway** next to the Layover message. Layover updates itself after that, through Check for Updates… in its menu.

## Requirements

- macOS 14 or later
- Xcode 26 or later (tested with 27.1)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```sh
brew install xcodegen
xcodegen generate
open Layover.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed. The first build resolves the Sparkle package, which needs network access.

## Tests

```sh
swift test --package-path LayoverKit
```

With only the Command Line Tools installed (no full Xcode selected), add the testing plugin path:

```sh
swift test --package-path LayoverKit \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## Troubleshooting

Layover keeps its data in its sandbox container, at `~/Library/Containers/dev.mauipingol.Layover/Data/Library/Application Support/dev.mauipingol.Layover/`:

- `shelves.json`: the saved Shelves.
- `OwnedFiles/`: the Owned Files (dropped text, links, images and promised files), one folder per file.

A `shelves.json.unreadable-<timestamp>` file next to `shelves.json` means Layover found a save it could not read (damaged, or written by a newer version) and set it aside rather than overwrite it. While such a file exists, Owned File cleanup is paused, because the set-aside save may refer to Owned Files the current Shelves don't. Remove the file (after recovering anything you need from it) and cleanup resumes on the next save.

## Docs

- [GLOSSARY.md](GLOSSARY.md): the project's vocabulary (Shelf, Item, Handle, Shake, ...)
- [docs/adr](docs/adr): architecture decision records
- [docs/research](docs/research/dropover-teardown.md): teardown of a comparable app
- [docs/qa](docs/qa/v1-checklist.md): the v1 manual QA checklist
- [docs/release.md](docs/release.md): releasing, signing and Sparkle updates

## License

MIT. See [LICENSE](LICENSE).
