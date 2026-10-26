# Layover v1 manual QA checklist

Run this on a release downloaded from GitHub (see [release.md](../release.md)), or on a Debug build for a local pass, launched from `/Applications` where a step says so. Vocabulary follows [GLOSSARY.md](../../GLOSSARY.md). Record the date, build and result next to each item you run.

In the container paths below, `<bundle id>` is `dev.mauipingol.Layover`. `defaults` commands for a sandboxed app act on `~/Library/Containers/dev.mauipingol.Layover/Data/Library/Preferences/dev.mauipingol.Layover.plist`.

## Review Focus

1. Dragging an Item into an app that *copies* (Mail, a browser upload field, Slack) must leave the Item on the Shelf and the original untouched. Only a reported `.move` removes Items.
2. An original file moved to the Trash must count as **deleted**, not "followed to the Trash".
3. A corrupt or newer-version `shelves.json` must not block launch, and must not be silently overwritten.
4. Shaking while dragging something that isn't content (moving a window, selecting text) must not open a Shelf.
5. A Shelf opening on a secondary display (negative coordinates) or at a screen corner must land fully on that screen.

## App shell

- [ ] The tray icon appears in the menu bar and adapts to light and dark appearance. Expected: a template icon, legible in both.
- [ ] There is no Dock icon and no Cmd-Tab entry. Expected: Layover runs as a menu-bar-only app.
- [ ] Open the menu. Expected order: New Shelf (shows the hot key, default ⌃⌥⌘N), Recent Shelves ▸, separator, Check for Updates…, Settings… (⌘,), separator, Quit Layover (⌘Q).
- [ ] With no Recent Shelves, open the Recent Shelves submenu. Expected: only a disabled "Clear Recent Shelves".
- [ ] Quit Layover from the menu. Expected: the app quits.
- [ ] Hand-edit `shelves.json` in the container so Shelves hold one Item, several Items and none, then open Recent Shelves. Expected: labels read "name", "name and N more" and "Empty".
- [ ] Check the key equivalents on a non-US keyboard layout. Expected: the menu displays the correct characters.
- [ ] Put a corrupt `shelves.json` (and, separately, one with a newer `version`) in the container and launch. Expected: Layover launches, starts empty, and does not overwrite the file (Review Focus 3).

## Shelf window

- [ ] Menu → New Shelf. Expected: an empty Shelf opens just below the cursor, on the screen the cursor is on, fully on screen, including near edges and corners (Review Focus 5).
- [ ] Open a Shelf on a secondary display, including one placed left of or above the main display (negative coordinates), and at each screen corner. Expected: the Shelf lands fully on that screen.
- [ ] Click ✕. Expected: the Shelf closes; an empty Shelf does not appear in Recent Shelves.
- [ ] Pin a Shelf, quit, relaunch. Expected: it reappears in the same place with the pin filled. Unpin, quit, relaunch: it does not come back pinned, and it appears under Recent Shelves if it has Items.
- [ ] Drag the Shelf by its background, pin it, relaunch. Expected: it moves with the drag and returns at its new position.
- [ ] Switch apps, change Spaces, and open a full-screen app. Expected: the Shelf floats above other apps, stays visible after switching apps, and appears on all Spaces and over full-screen apps.
- [ ] Click the Shelf. Expected: Layover does not activate; the frontmost app's menu bar stays.
- [ ] Hover the controls and inspect them with VoiceOver. Expected: tooltips and labels read Close Shelf, Pin Shelf / Unpin Shelf, Expand / Collapse.
- [ ] Add several Items. Expected: the compact stack shows up to 3 thumbnails, newest on top.
- [ ] Click the stack, or the expand button, then collapse. Expected: it switches to the 4-column grid and back; the grid scrolls past 560 pt; expanding near a screen edge keeps the Shelf on screen.
- [ ] Reopen a Recent Shelf from the menu. Expected: it reappears where it was last shown.
- [ ] Check both light and dark appearance. Expected: the HUD background and text are legible.

## Drop in

- [ ] Drop Finder files onto a Shelf. Expected: they appear as Items.
- [ ] Drop the same file again. Expected: the existing Item bounces (compact: the stack; expanded: the cell) and no duplicate is added.
- [ ] Drop selected text from Safari. Expected: a `.txt` Item named after its first line.
- [ ] Drop a link from a browser address bar or page. Expected: a `.webloc` Item titled from the page title. Safari may deliver the link as a promised `.webloc` file instead; that is acceptable as long as a `.webloc` named after the page appears.
- [ ] Drop an image from a web page. Expected: an image Item (image data wins over the page URL Chrome/Safari also put on the pasteboard).
- [ ] Drop a Mail attachment or another promised file. Expected: it arrives as a `.received` Owned File.
- [ ] Hover a drag over a Shelf. Expected: the accent border and tint appear and clear on exit and on drop; unrelated drags show nothing.
- [ ] Drop onto a pinned and an expanded Shelf, then restart the app. Expected: Owned File Items are still there (saved and not cleaned up).
- [ ] Drop a file from another app, quit, relaunch. Expected: the Item still resolves (security-scoped bookmark, app sandboxed).
- [ ] Drag an Item (grid or Handle) onto its own Shelf. Expected: the Shelf does not highlight and nothing is added.

## Drag out

Record what Finder reports for each of these.

- [ ] Drag the Handle to a Finder folder on the same volume. Expected: the files are moved, the originals are at the destination, and the Shelf closes (with "Close Shelf when emptied" on).
- [ ] Repeat holding Option. Expected: files are copied, the Shelf stays with all Items.
- [ ] Option-drag from the Handle and from a grid Item. Expected: the green + badge shows, the files are copied, the Items stay on the Shelf.
- [ ] Drag one Item into a Mail compose window. Expected: it attaches, the Item stays on the Shelf, the original is untouched (Review Focus 1).
- [ ] Drag an Item into a browser upload field and into Slack. Expected: the same: the Item stays, the original is untouched (Review Focus 1).
- [ ] Drag to another volume. Expected: copied, the Items stay.
- [ ] Command-drag to Finder. Note the operation Finder reports. Expected: no Item is left dangling; an Item whose file went away shows as unavailable (not a ghost), a moved Item is gone, and a file in the Trash counts as deleted (Review Focus 2).
- [ ] Drag an Item onto the Dock Trash. Expected: the Trash shows no drop target (Layover never offers a delete operation) and the Item stays on the Shelf.
- [ ] Drag an Item or the Handle onto another Shelf. Expected: it is copied there and the source Shelf is untouched; an Owned File is copied to a new Owned File of its own on that Shelf.
- [ ] Drag an Owned Item (a dropped text or image) from Shelf A to Shelf B, then move it from A to Finder. Expected: B's Item still opens.
- [ ] In the expanded grid, click, then Cmd-click and Shift-click Items. Expected: click selects (highlight); Cmd/Shift-click multi-selects.
- [ ] Drag a selected Item, then an unselected Item. Expected: a selected Item drags the whole selection; an unselected Item drags just itself.
- [ ] With an Unavailable Item on the Shelf (eject a disk, or move and trash an original), drag the Handle. Expected: the Unavailable Item is left out of the drag; if all are unavailable, no drag starts.
- [ ] Turn "Close Shelf when emptied" off and do a moved drag. Expected: an empty open Shelf remains.
- [ ] Move the last Item out. Expected: the Shelf closes shortly after the drop with no crash or flicker.
- [ ] Look at the drag image. Expected: thumbnails fanned for the stack and the Handle, cell snapshots for the grid.
- [ ] Drag from the stack, from the Handle, and drag a grid Item. Expected: the window does not move.
- [ ] Drop a file on a Shelf, then, without clicking the Shelf first, drag the stack (and in another round the Handle, and a grid Item) to a Finder folder. Expected: the drag starts on the first try.
- [ ] Move an Owned File into a Finder folder that holds a same-name file, wait a few seconds, choose Stop. Expected: the Owned File still exists in the container (`~/Library/Containers/<bundle id>/Data/Library/Application Support/.../<uuid>/`).

## Item actions

- [ ] Use each context-menu item on one Item and on a multi-selection (grid context menu; the compact "⋯" menu acts on all Items). Expected: each works.
- [ ] Use Share…. Expected: it lists AirDrop, Mail and Messages.
- [ ] Share an in-place file (in `~/Documents` or on an external volume) via AirDrop and via Mail. Expected: the file arrives.
- [ ] Choose Remove from Shelf. Expected: the file stays in Finder; removing the last Item leaves the Shelf open and collapsed.
- [ ] Press Space with Items selected, again to close. Expected: Quick Look opens and closes, shows the content of a file in place, and Esc works.
- [ ] Dismiss Quick Look by Esc, the close button and Space (from the grid, and while the Quick Look panel is key). Expected: access is released and Console shows no "-[QLPreviewPanel setDataSource:] called while the panel has no controller" message. Also try Quick Look from the compact "⋯" menu, and from a second Shelf while the first one's panel is up.
- [ ] Double-click an Item; press ⌘C then paste in Finder; press ⌫ on a selection. Expected: the Item opens, the files paste, the selection is removed, all without Layover activating.
- [ ] Repeat Double-click, Space, ⌫, forward delete and ⌘C with Caps Lock on and another app frontmost. Expected: all work.
- [ ] Right-click an unselected Item, then right-click inside a multi-selection. Expected: the first selects and acts on that Item; the second acts on the whole selection.

## Availability

- [ ] Rename a file in Finder. Expected: its Item shows the new name after re-showing the Shelf (also after expanding it or switching back to the app).
- [ ] Delete a file, or move it to the Trash. Expected: the Item disappears and the notice "'name' was removed from disk." shows for 3 s; several deletions queue one after another; an emptied Shelf stays open.
- [ ] Put an Item from a USB drive on a Shelf and eject the drive. Expected: the Item greys out (40%) in the stack and the grid, cannot be dragged (Handle or grid), and its menu offers only Remove from Shelf (in a mixed selection, other actions apply to the available Items).
- [ ] Remount the drive. Expected: the Item is normal again.
- [ ] Reopen a Recent Shelf whose file was deleted meanwhile. Expected: the Item is removed with the notice.
- [ ] Look at the notice over the compact stack and the grid. Expected: it is legible and centered vertically.
- [ ] Select a Shelf with only an unreachable Item (ejected disk). Expected: only Remove from Shelf is enabled.

## Shake & hotkey

- [ ] Shake while dragging a Finder file. Expected: a Shelf opens under the cursor, you can drop the file into it, and the drag is not interrupted.
- [ ] Open a folder stack in the Dock (for example Downloads), drag a file out of it and shake. Expected: a Shelf opens under the cursor, as for a Finder file.
- [ ] Shake while moving a window. Expected: nothing happens (Review Focus 4).
- [ ] Shake while selecting text. Expected: nothing happens (Review Focus 4).
- [ ] Shake while dragging an Item out of a Shelf. Expected: no new Shelf opens.
- [ ] Add Finder to Ignored Apps (`defaults write … ignoredBundleIDs -array com.apple.finder`, then relaunch). Expected: a Shake while dragging in a Finder window or a Desktop icon opens nothing; a Shake while dragging a Finder file over another app's window (for example Safari) opens a Shelf. Remove the setting afterwards with `defaults delete … ignoredBundleIDs`.
- [ ] Set the Drag Modifier to ⌘ in Settings. Start dragging a Finder file, then press and hold ⌘ during the drag. Expected: one Shelf opens under the cursor, you can drop the file into it, and keeping ⌘ held opens no second Shelf. Repeat for ⌃ and ⇧.
- [ ] Set the Drag Modifier to ⌘ in Settings. Start dragging a Finder file, press and hold ⌘, and drop the file onto the new Shelf from the item above. Then start a second drag of a Finder file and press and hold ⌘ again. Expected: a second Shelf opens under the cursor, separate from the first.
- [ ] Start dragging a Finder file and hold the cursor still, then press ⌘. Expected: nothing opens while the cursor is still. Move the cursor: one Shelf opens under the cursor. A still cursor is not a bug, because drag events arrive only when the mouse moves.
- [ ] Hold ⌃ before pressing the mouse button, then drag a Finder file (Drag Modifier set to ⌃). Expected: record, not pass/fail. Note whether a Shelf opens and whether the click opens a context menu in the app under the cursor.
- [ ] Start moving a window, press the Drag Modifier during the move, then repeat while selecting text. Expected: nothing happens.
- [ ] Start dragging an Item out of a Shelf, then press the Drag Modifier during the drag. Expected: no new Shelf opens.
- [ ] With Finder in Ignored Apps, start dragging a Finder file in a Finder window or on the Desktop, press ⌘ during the drag, then move the cursor over Safari while still holding ⌘. Expected: nothing opens while the cursor is over Finder; a Shelf opens at the cursor as soon as it is over Safari.
- [ ] With Finder in Ignored Apps, press the Drag Modifier (⌘) over a Finder window while dragging a Finder file, release ⌘ while still over Finder, then move the cursor over Safari without holding ⌘. Expected: nothing opens over Finder; a Shelf still opens at the cursor once it is over Safari (the key latched during the drag).
- [ ] Set the Drag Modifier to Off (the default), then press ⌘, ⌃ and ⇧ in turn during a drag of a Finder file. Expected: the key does nothing; Shake alone still works.
- [ ] Press ⌃⌥⌘N. Expected: a Shelf opens at the cursor, and the menu's New Shelf item shows that shortcut.
- [ ] Exercise Shake, the Drag Modifier and the hot key. Expected: no permission prompt (Accessibility, Input Monitoring or Screen Recording).
- [ ] Optional, first-launch conflict rule: assign ⌃⌥⌘N to a system shortcut in System Settings → Keyboard → Keyboard Shortcuts, delete the `hasCheckedHotKeyConflict` (and `newShelfHotKey`) preference, relaunch. Expected: the hot key is unassigned and the menu item shows no shortcut.
- [ ] Register ⌃⌥⌘N in another app first, then launch Layover. Expected: the New Shelf menu item shows no shortcut.

## Settings

- [ ] Set Shake sensitivity to Off, then Normal, High and Highest. Expected: Off stops Shake immediately; the others change the thresholds with no relaunch.
- [ ] Open Settings on a fresh install, then pick ⌘, ⌃, ⇧ and Off in turn for "Modifier key to open a Shelf", also with Shake set to Off. Expected: the picker starts at Off, each change applies at once with no relaunch, and the key works with Shake Off.
- [ ] Record a new shortcut (for example ⌃⌥⌘K). Expected: it works at once, the menu item shows it, and the old combo no longer opens a Shelf.
- [ ] While recording, press the current combo, then Esc, then Backspace. Expected: the current combo is recorded rather than opening a Shelf; Esc restores the old one; Backspace clears it (the menu item loses its key).
- [ ] While recording, press ⌘C, then ⌘⇧K. Expected: "Use ⌃ or ⌥ in the shortcut." shows, recording continues and the current shortcut is unchanged.
- [ ] Record a combo macOS uses (for example one listed in Keyboard Shortcuts), then one held by another app. Expected: "This shortcut is already used by macOS." and "…used by another app." respectively, and the preference is kept.
- [ ] In Ignored Apps, use + and −. Expected: + picks apps from `/Applications` (multi-select), duplicates are skipped, rows show icon and name; − removes the selection; a Shake over an ignored app is ignored live.
- [ ] Toggle "Close Shelf when emptied". Expected: behavior changes live.
- [ ] Turn "Show in menu bar" off. Expected: the icon hides immediately; opening Layover again (from Finder) brings up Settings.
- [ ] Toggle Launch at login on and off, from `/Applications` (properly signed). Expected: it registers; if macOS needs approval, the caption and "Open System Settings" button appear and the toggle state refreshes on return. An ad-hoc build outside `/Applications` may show an inline error (expected).
- [ ] Reset first launch (`defaults delete dev.mauipingol.Layover hasAskedLaunchAtLogin`, in the container) and launch. Expected: the alert "Launch Layover at login?" appears once, with the buttons "Launch at Login" and "Not Now".

## Updates

- [ ] Choose Check for Updates… in the menu. Expected: Sparkle's UI appears. Before the first GitHub Release exists, a feed error is expected.
- [ ] Run `codesign -d --entitlements - Layover.app`. Expected: `app-sandbox`, `network.client` and the two `mach-lookup` exceptions (`dev.mauipingol.Layover-spks`, `-spki`) are present.
- [ ] Run `codesign -dv Layover.app`. Expected: the flags include `runtime`.
- [ ] Once two releases exist, check for an update from the older one. Expected: the update is found, verified, installed and the app relaunches.
