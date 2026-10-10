# TinyTiler

A tiny macOS menu-bar window manager. It moves the focused window of whatever app is in front:

| Action | Shortcut |
|---|---|
| Left half | ⌃⌥← |
| Right half | ⌃⌥→ |
| Maximize (fill the visible screen) | ⌃⌥↩ |
| Move to next display, keeping its relative size and position | ⌃⌥⌘→ |

The same actions are in the menu-bar icon's menu.

Pressing ⌃⌥← or ⌃⌥→ again cycles the window width through ½ → ⅔ → ⅓ → ½. A repeated
press advances when the window is still where the last press put it, or already sits at one
of those sizes. Otherwise it starts again at ½. Turn this off with **Cycle ½ → ⅔ → ⅓ on
Repeat** in the menu.

Requires macOS 13+ and Xcode 15+ (or the matching Command Line Tools).

## Run it

```bash
./scripts/bundle.sh
open build/TinyTiler.app
```

On first launch macOS asks for **Accessibility** access. Enable TinyTiler in
System Settings › Privacy & Security › Accessibility. Until you do, the menu shows a
"Grant Accessibility Access…" item.

The bundle is ad-hoc signed, so macOS treats every rebuild as a new app. If shortcuts stop
working after a rebuild, remove TinyTiler from the Accessibility list (the `–` button) and
add it again.

`swift run TinyTiler` also works for quick iteration, but then macOS asks to grant
Accessibility access to your terminal app instead.

## Tests

```bash
swift test
```

The tests cover the geometry in `TilerCore`: coordinate flipping, halves, picking a screen,
and moving between displays. That module is plain Foundation, so the tests also run on Linux.

## How it works

| File | Role |
|---|---|
| `Sources/TilerCore/Layout.swift` | Pure geometry, all in Accessibility coordinates (top-left origin of the primary display, y down). |
| `Sources/TinyTiler/WindowMover.swift` | Accessibility API (`AXUIElement`): finds the frontmost app's focused window, reads its frame, writes the new one. |
| `Sources/TinyTiler/HotKeyCenter.swift` | Global shortcuts through Carbon `RegisterEventHotKey`, which needs no extra permission. |
| `Sources/TinyTiler/AppDelegate.swift` | Menu-bar item, menu, and shortcut wiring. |

Details handled:

- `NSScreen` frames use a bottom-left origin; Accessibility uses top-left. `Layout.flip` converts between them.
- The size is set before and after the position, so windows aren't clamped to the old screen when they cross displays.
- `AXEnhancedUserInterface` is turned off for the duration of a move. When it's on, apps animate frame changes slowly.
- Accessibility calls time out after 1 second, so a hung app can't freeze TinyTiler.
- Full-screen windows are skipped, and the app beeps.

## Not included

Spaces, Stage Manager, and tiling layouts. Spaces have no public API.
