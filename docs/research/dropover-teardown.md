# Dropover 5.1.3 — teardown for OpenDrop

Target: `/Applications/Dropover.app` (`me.damir.dropover-mac`, build 569, Mac App Store, universal arm64/x86_64, min macOS 13, built with Xcode 26 / macOS 26 SDK).

Purpose: understand *behavior and architecture* so OpenDrop can be a clean-room re-implementation. Nothing here should be copied verbatim (code, strings, icons, videos, nibs). Third-party pieces Dropover embeds are open source and can be used directly under their own licenses.

Evidence legend: **[O]** observed in the shipped artifact (plist, symbols, strings, decompiled code). **[I]** inferred from observations. **[?]** unresolved.

---

## 1. Bundle layout [O]

```
Dropover.app/Contents
├── MacOS/Dropover                 9.7 MB (25 MB fat) — main app, Swift + AppKit (+ some SwiftUI)
├── Frameworks/
│   ├── DropoverCore               UI kit, bookmark store, zip, logging (SwiftyBeaver), search, thumbnails
│   ├── DropoverFileOperations     file "actions": rename, zip, image resize/convert/compress, PDF, OCR, redact, user scripts
│   ├── DropoverCloud              their own "Dropover Cloud" upload service client
│   ├── DropoverAWS                S3 (and S3-compatible) uploader / deleter
│   ├── GoogleDrive                upload + share link
│   └── MicrosoftOneDrive          upload + share link
├── PlugIns/
│   ├── DropoverShareExtension     com.apple.share-services — "Share → Dropover"
│   └── RecentShelvesWidgetExtension  WidgetKit widget listing recent shelves
└── Resources/  Main.storyboard, nibs, Assets.car, intro_*.mov, Alfred workflow, Metadata.appintents
```

Dropbox support is compiled into the main binary (SwiftyDropbox + Alamofire + OAuthSwift are statically linked).

## 2. Info.plist / entitlements highlights [O]

| Key | Value | Why it matters |
|---|---|---|
| `LSUIElement` | true | Menu-bar agent, no Dock icon (optional "Show in Dock" toggle switches activation policy at runtime) |
| `NSPrincipalClass` | `DropoverApplication` | NSApplication subclass |
| `NSServices` | "Add to Dropover" (`addToDropoverService`) | Services menu entry, accepts string/RTF/RTFD/URL/file contents |
| `CFBundleURLTypes` | `dropover://` + OAuth callback schemes (Dropbox, Google, OneDrive) | URL-scheme automation + OAuth redirects |
| `CFBundleDocumentTypes` | `public.data`, rank None | Lets you drop files on the app icon / "Open With" |
| `NSUserActivityTypes` | `AddToShelfIntent`, `CreateCloudSessionIntent`, `GetFilesFromShelfIntent`, `OpenRecentShelfIntent` | App Intents / Shortcuts |
| `NSUbiquitousContainers` | `iCloud.me.damir.dropover-mac` | "Copy iCloud Link" uploads into iCloud Drive |
| Sandbox | `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `network.client`, app group, keychain group | **No Accessibility, no Input Monitoring** — everything is done with sandbox-safe APIs |

## 3. Core mechanism: how a shelf appears

### 3.1 Detecting a drag anywhere on screen [O]

`DragRecognizer` (plain Swift class) is set up in its initializer (`sub_100221878`):

1. Creates a `PasteboardWatchDog` on **`NSPasteboard(name: .drag)`**.
2. Installs `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged)` and `.leftMouseUp`.

Global *mouse* monitors work inside the sandbox without Accessibility permission. That is why the app needs no TCC prompt.

On each `leftMouseDragged` (`sub_100221d04`):
- If the watchdog isn't already polling, it records the drag pasteboard's `changeCount` and starts a repeating `NSTimer` → `checkForChangesInPasteboard`. A real drag-and-drop (as opposed to selecting text or moving a window) writes to the drag pasteboard, so a `changeCount` bump means "the user is dragging content".
- It checks whether the event's `windowNumber` belongs to one of Dropover's own shelves (`isDockSession`). Dragging *out of* a shelf must not spawn a new shelf.
- It routes to one of two paths. If shake is enabled and the configured modifier isn't held, it goes to the **shake path** (`sub_100221f90`). Otherwise it goes to the **modifier path** (`sub_10022222c`), which fires as soon as the modifier flag is present.
- Both paths look up the **owner app of the window under the cursor**, using `CGWindowListCopyWindowInfo` → `kCGWindowOwnerName` with a cache (`EventWindowOwnerNameCache`). If that app is in **Ignored Applications**, no shelf is created.

On `leftMouseUp` (`sub_1002224ec`), polling stops, the timer is invalidated, and the gesture state is reset after a short `asyncAfter` (`sub_100223c00`).

The pasteboard watchdog's update handler (`sub_100221be0`) sets `didUpdatePasteboardContent = true`. If the shake has *already* been recognized, it fires the shelf at `NSEvent.mouseLocation`. So the order doesn't matter: shake-then-pasteboard and pasteboard-then-shake both work.

### 3.2 Shake-gesture algorithm [O] (decompiled `sub_100222850`)

Default parameters, read from the `__const` pool at `0x1006c8030` and the initializer:

| Parameter | Value |
|---|---|
| required direction reversals | **4** (recognized when count **> 4**) |
| minimum horizontal travel per stroke | **20 pt** |
| max gap between drag events | **0.2 s** |
| whole-gesture window | **1.0 s** |

Only the **x-axis** is used. Re-expressed as Swift:

```swift
struct ShakeDetector {
    var requiredReversals = 4
    var minStroke: CGFloat = 20
    var maxEventGap: TimeInterval = 0.2
    var window: TimeInterval = 1.0

    private var origin: CGPoint?
    private var last: CGPoint?
    private var movingLeft: Bool?
    private var windowStart = Date()
    private var lastEvent: Date?
    private var stroke: CGFloat = 0
    private var reversals = 0
    private(set) var recognized = false

    mutating func feed(_ p: CGPoint, now: Date = .now) {
        guard let o = origin else { origin = p; windowStart = now; return }
        guard let l = last else { last = p; return }
        guard let dirLeft = movingLeft else { movingLeft = o.x > p.x; return }

        let nowLeft = l.x > p.x
        if now.timeIntervalSince(windowStart) > window { reversals = 0; stroke = 0; windowStart = now }
        if let le = lastEvent, !recognized, now.timeIntervalSince(le) > maxEventGap { reversals = 0; stroke = 0 }
        lastEvent = now

        if nowLeft != dirLeft {
            if stroke >= minStroke { reversals += 1 }
            stroke = 0
        } else {
            stroke += abs(l.x - p.x)
        }
        movingLeft = nowLeft
        recognized = reversals > requiredReversals
        last = p
    }
}
```

**[?]** The three sensitivity levels (`normal`, `high`, `ludicrous`) and how they change these numbers weren't found: no other threshold pair exists in the constant pool, so they're probably immediate values in a setter that wasn't decompiled. A reasonable OpenDrop choice is to lower `requiredReversals` and `minStroke` as sensitivity goes up.

### 3.3 Other ways to open a shelf [O]

| Trigger | Implementation evidence |
|---|---|
| Modifier key while dragging (⌘ / ⌃ / ⇧) | `shelfTriggerModifierKey[Enabled]`, `modifierFlags` ivar |
| Drop onto the MacBook **notch** | `NotchDragController`, `NotchDragObserver` (global `.leftMouseDragged` + `.leftMouseUp` monitors), `NotchWindow`, `NotchShapeLayer`; highlight modes: always / on hover / never |
| Global hotkeys | Carbon `RegisterEventHotKey` / `InstallEventHandler`, `CopySymbolicHotKeys` (to detect clashes with system shortcuts). Default hotkeys: show/hide shelf, new clipboard shelf |
| Shelf-local hotkeys | Active only while the cursor hovers a shelf (`DragSessionHotKeyResponder`, `GlobalDragSessionHotKeyController` with a timeout: "Drag session hotkeys are activated for too long, deactivating them now") |
| Drag onto the menu-bar icon | `NSStatusBarButton+Dragging.swift` |
| Services menu, Share extension, `dropover://` URL, App Intents, Alfred/Raycast | see §2 |
| Screenshot shelf | `UserScreenshotObserver`: watches the user's screenshot folder (security-scoped bookmark + `DispatchSource` file-system object source + throttler); setup wizard asks you to disable the system floating thumbnail |
| Folder Monitoring | `DirectoryObserver`, `SubdirectoryObserver`, `FileSystemChangeObserver`, `ObservedDirectoryStore`; per-folder rules (name/kind criteria, AND/OR, case-sensitivity), optional "new shelf per file" |
| Clipboard | `PasteboardWatchDog` reused on the general pasteboard; "New Shelf From Clipboard", "Add From Clipboard" |

## 4. The shelf window [O]/[I]

- `DragSessionWindow` (borderless floating panel) + `DragSessionWindowController` + `DragSessionView` with grid (`NSCollectionView`) and list/outline (`NSOutlineView`) modes.
- Default placement for shelves not created by shaking: near cursor / center / one of the 4 corners.
- **Snapping & docking**: `DragSessionDockController` tracks drag velocity (`lastDragVelocity[Y]`) to fling a shelf to a screen edge. `EdgeDockDistributionController` stacks multiple docked shelves along an edge. Hold ⌘ to disable snapping. Docked shelves undock when screens change.
- **Retract**: `DragSessionWindowRetractor` slides the shelf aside after the first drop, using an event monitor that waits for the cursor to leave.
- Double-click on a shelf edge → dock / retract / nothing.
- Per-shelf settings: name, color label, pin, "keep in own Space" (`collectionBehavior`), always show indicator.
- **Detail view** (new in 5.1): `ShelfPanelCoordinator` expands the shelf into a panel and closes it on outside clicks via a global monitor (mask `0x4000014` = left/right mouse down + scroll).
- **Instant Actions**: when you drag onto an *empty* shelf, action targets (AirDrop, Mail, Messages, cloud upload, scripts…) appear; dropping onto one runs it (`InstantActionController`, `InstantActionButton` uses a global `.leftMouseDragged` monitor for hover).
- Command bar / action search (`SearchController`, keyword list such as "compress", "pasteboard", "trash").
- Dragging *out*: moves by default, or copies if that preference is set. `DraggablePromise` handles file promises (e.g., images from browsers, Mail messages).

## 5. Data model & persistence [O]

**Draggable types:** `DraggableFile` (URL + security-scoped bookmark, access counting), `DraggableText`, `DraggableWebImage`, `DraggableWeblocation`, `DraggablePromise`.

**Shelves** are saved as `PersistentDragSession`, written by `PersistentDragSessionStore` (throttled saves, max item count) to a JSON file in the app-group container (`.drag_sessions`):

```json
[{ "identifier": "UUID", "date": "ISO-8601",
   "bookmarks": ["<base64 security-scoped bookmark>"],
   "order": ["…"],
   "label": { "color": {"id": "…"}, "userDefined": false,
              "keepInOwnSpace": false, "pinned": false, "colorVisibility": "…" } }]
```

Thumbnails are cached as 360×360 PNGs named by UUID in `.files-snapshot-default/` (`FilesSnapshotController`, with a purge strategy).

**Preferences** live in `UserDefaults` behind a `Preferences` class with lazy, typed properties. Key names seen: `ShakeGestureDisabled`, `ShakeGestureSensitivity`, `ShelfTriggerModifierKey[Enabled]`, `NotchDragEnabled`, `NotchDragHighlightBehavior`, `AutomaticWindowSnappingEnabled`, `ShelfRetractionEnabled`, `DoubleClickAction`, `DoubleClickEdgeAction`, `DefaultShelfLocation`, `IgnoredApplications`, `ShowHideHotKeyCombo`, `ShowHideClipboardHotKeyCombo`, `ShelfHotkeysEnabled`, `ShelfLabelsEnabled`, `InstantActionsEnabled`, `ScreenshotObservationEnabled`, `CloudLinkType`, `CloudLinkExpiration`, `OnlineFeaturesDisabled`, `LastOutlineDisplayMode`, `FileLoggingEnabled`, …

Secrets (OAuth tokens, S3 keys) go in the Keychain (`DropoverKeychain`, `KeychainCredentialsStore`, `SecureDiskPersistence`).

## 6. File actions (DropoverFileOperations) [O]

Built in: Rename, Batch Rename (find/replace or a template using `#counter`, `#date`, `#original`), Create ZIP (optional password), Copy/Move to folder, Copy Path, Open With, Reveal in Finder, Move to Trash, Get Info, Copy Text Content, Set Desktop Picture.

Images: Resize (percent or max px), Convert format, Compress (bundled **optipng** binary for PNG), Remove metadata, Stitch, Create PDF, Extract Text (Vision OCR), Redact text (auto-detects text and draws boxes over it).

PDF: Stitch PDFs, Protect with password.

**Custom Actions** = saved presets of the operations above with parameters (`UserOperation`). **Custom Scripts** = UNIX or Automator scripts placed in `~/Library/Application Scripts/<bundle-id>`, run via `NSUserUnixTask`. The sandbox requires that folder. Output can go to Finder, the current shelf, or a new shelf. Generated files land in an "Action Generated Files" folder.

## 7. Sharing / cloud [O]

| Service | Notes |
|---|---|
| Dropover Cloud | Their own backend (`a.dropoverapp.com`); title, expiration, password, link types (direct download / direct link → auto-zip multiple files) |
| iCloud | Copy into the iCloud Drive ubiquity container, then fetch a share link |
| Dropbox | SwiftyDropbox SDK, app-folder scope |
| Google Drive | OAuth via OAuthSwift; public link (no expiration) or email invite |
| OneDrive | OAuth; folder-name validation |
| Amazon S3 / S3-compatible | Access key + secret, ACL, expiration (presigned URLs), "smoke test" on setup, delete & revoke |
| Imgur | Token brokered through their server |
| System | `NSSharingService` (AirDrop, Mail, Messages) |

"Recent Uploads" history menu (`ShareHistoryStore`) offers copy / open / delete & revoke. A link shortener is also available.

## 8. Monetization & telemetry [O]

- StoreKit one-time "Dropover Pro" purchase; the free version is a trial, then time-limited.
- Rating prompt, What's New window, onboarding pager with videos.
- Sentry crash reporting (`io.sentry` folder in the container). SwiftyBeaver logging with optional file logging.

## 9. Third-party libraries embedded [O]

SwiftyDropbox, Alamofire, OAuthSwift, SwiftyBeaver, a Zip library, optipng, Sentry. Use the open-source originals, or skip them.

---

## 10. Suggested OpenDrop architecture (design choices, not observations)

Native Swift + AppKit is the only realistic stack: global NSEvent monitors, drag-pasteboard polling, borderless `NSPanel`s, Carbon hotkeys. Electron/Tauri can't do this cleanly.

```
OpenDrop (LSUIElement agent)
├── App/            AppDelegate, StatusItem menu, Settings (SwiftUI)
├── Activation/     DragMonitor (global monitors + drag-pasteboard watchdog)
│                   ShakeDetector (§3.2), ModifierTrigger, NotchTrigger, HotKeys (Carbon)
│                   IgnoredApps (CGWindowList owner lookup)
├── Shelf/          ShelfPanel (NSPanel .nonactivatingPanel, .floating, canJoinAllSpaces)
│                   ShelfViewController (NSCollectionView grid/list), drag-in/out, promises
│                   Snap/Dock/Retract controllers
├── Model/          ShelfItem enum (file+bookmark | text | url | image | promise), Shelf
│                   ShelfStore (Codable JSON in Application Support, throttled writes)
├── Actions/        Action protocol; Open/Reveal/Copy/Move/Zip/Rename/Trash; Image ops (ImageIO/CoreImage); OCR (Vision); PDF (PDFKit)
└── Sharing/        NSSharingService first; cloud providers later behind a protocol
```

Suggested MVP order:
1. Menu-bar agent, plus a "New Shelf" hotkey that opens an empty floating shelf that accepts drops and lets items be dragged out.
2. Global drag detection: drag pasteboard `changeCount` + shake detector → open a shelf at the cursor.
3. Persistence of shelves (bookmarks) and a Recent Shelves menu.
4. Modifier trigger, ignored apps, snapping/docking.
5. Actions menu (open, reveal, zip, AirDrop/share), then image actions.
6. Optional: notch drop, folder/screenshot watching, cloud links, Shortcuts intents, share extension.

Decide early whether to ship sandboxed (App Store-compatible, like Dropover) or not. Sandboxing forces security-scoped bookmarks for every file on a shelf and the Application Scripts folder for user scripts. Both are proven workable, as shown above.

## 11. Open questions

- [?] Exact sensitivity → threshold mapping (§3.2).
- [?] `PasteboardWatchDog` timer interval: it's passed in a register and wasn't resolved.
- [?] Notch hit-testing geometry (uses `NSScreen.auxiliaryTopLeftArea`/`RightArea`? not verified).
- [?] Snap/dock physics (velocity thresholds) — not decompiled.
