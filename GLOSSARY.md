# Layover

Layover is a macOS menu-bar utility for temporarily collecting dragged content in floating windows, then moving or sharing it elsewhere.

## Language

**Shelf**:
A floating window that temporarily holds Items gathered by drag and drop.
_Avoid_: Drag session, stash, stack, tray, window

**Item**:
One thing held on a Shelf. For a dropped file it is a reference to the original file in place, not a copy. For dropped text, links or images that aren't files, it is a file Layover owns.
_Avoid_: Draggable, clip, entry

**Owned File**:
A file Layover creates to hold dropped content that wasn't already a file: text, a link, an image, or a file another app only promised (such as a Mail attachment). It is deleted once no Shelf or Recent Shelf refers to it.
_Avoid_: Temp file, generated file

**Handle**:
The part of a Shelf you grab to drag all its Items out at once.
_Avoid_: Grabber, stack

**Header**:
The strip along the top of a Shelf that holds its close, pin and expand buttons.
_Avoid_: Title bar, toolbar, Shelf edge

**Shake**:
A rapid side-to-side cursor movement during a drag that opens a new Shelf at the cursor.
_Avoid_: Wiggle, jiggle, gesture

**Drag Modifier**:
A modifier key (⌘, ⌃ or ⇧) chosen by the user that, pressed during a drag, opens a new Shelf at the cursor as an alternative to a Shake.
_Avoid_: Trigger key, hot key, shortcut

**Notch Drop**:
Dropping content on the notch of a Mac that has one, which opens a new Shelf holding it.
_Avoid_: Notch shelf, notch trigger, notch drag

**Ignored App**:
An app over whose windows a Shake or Drag Modifier is ignored.
_Avoid_: Excluded app, blacklisted app

**Unavailable Item**:
An Item whose original file can't currently be reached, such as one on an ejected disk. It stays on the Shelf, greyed out.
_Avoid_: Broken item, missing item

## Shelf lifecycle

**Recent Shelf**:
A closed, non-empty Shelf that can be reopened. Only the most recent ones are kept.
_Avoid_: History, previous shelf, closed shelf

**Pinned Shelf**:
A Shelf that stays open until explicitly closed and reappears after Layover relaunches.
_Avoid_: Sticky shelf, saved shelf

## Shelf placement

**Docked Shelf**:
A Shelf attached to the left or right edge of a screen, sitting flush against it until moved away. Several Docked Shelves on one edge sit one above another along it without overlapping.
_Avoid_: Snapped shelf, edge shelf, parked shelf

**Retracted Shelf**:
A Docked Shelf slid mostly off screen past its edge, leaving only a sliver visible. It is still a Docked Shelf.
_Avoid_: Hidden shelf, collapsed shelf, minimized shelf
