# TinyTiler

A tiny macOS menu-bar window manager. It moves the focused window of whatever app is in front.

Hold **Caps Lock** (⇪) and press a key with the same hand:

| Action | Shortcut |
|---|---|
| Top half | ⇪W |
| Left half | ⇪A |
| Bottom half | ⇪S |
| Right half | ⇪D |
| Top-left quarter | ⇪Q |
| Top-right quarter | ⇪E |
| Bottom-left quarter | ⇪Z |
| Bottom-right quarter | ⇪X |
| Maximize (fill the visible screen) | ⇪F |
| Center, keeping the window's size (shrunk only if it doesn't fit) | ⇪C |
| Move to next display, keeping its relative size and position | ⇪Space |

```
Q  W  E        ↖  ↑  ↗
 A  S  D        ←  ↓  →
  Z  X  C       ↙  ↘  center
```

The same actions, with their shortcuts, are also in the menu-bar icon's menu.

Repeated presses cycle sizes:

- **Halves:** ½ → ⅔ → ⅓ → ½ of the screen (width for left/right, height for top/bottom).
- **Quarters:** the width cycles ½ → ⅔ → ⅓ the same way; the height stays half the screen.
- **Center:** the first press centers the window at its own size. The second resizes it to ⅔
  of the screen's width and height. Further presses keep it at ⅔.

A repeated press advances when the window is still where the last press put it, or already
sits at one of those sizes. Otherwise it starts again at the first step. Turn this off with
**Cycle Sizes on Repeated Presses** in the menu.

### About Caps Lock

While TinyTiler runs, Caps Lock no longer toggles capitals. Other keys pressed while holding
Caps Lock type normally. The bound keys are matched by physical position, so they stay under
your left hand on any keyboard layout.

Quitting TinyTiler gives Caps Lock back and restores any Caps Lock remap you had before. If
TinyTiler crashes, Caps Lock stays remapped until you relaunch it, log out, or run:

```bash
hidutil property --set '{"UserKeyMapping":[]}'   # also clears any other hidutil remaps
```

Requires macOS 13+ and Xcode 15+ (or the matching Command Line Tools).

## Run it

```bash
./scripts/bundle.sh
open build/TinyTiler.app
```

On first launch macOS asks for **Accessibility** access. Enable TinyTiler in
System Settings › Privacy & Security › Accessibility. Until you do, the menu shows a
"Grant Accessibility Access…" item. The ⇪ shortcuts start by themselves a couple of seconds
after you grant it.

The bundle is ad-hoc signed, so macOS treats every rebuild as a new app. If shortcuts stop
working after a rebuild, remove TinyTiler from the Accessibility list (the `–` button) and
add it again.

`swift run TinyTiler` also works for quick iteration, but then macOS asks to grant
Accessibility access to your terminal app instead.

### Launch at login

Install the app into `/Applications`, open it from there, and tick **Launch at Login** in the
menu (off by default):

```bash
./scripts/bundle.sh --install
open /Applications/TinyTiler.app
```

The setting lives in macOS, and also appears under System Settings › General › Login Items.
If you switch it off there, the menu shows the checkbox as mixed (–); clicking it opens that
settings page. Use `--install` for later rebuilds too, so the login item keeps pointing at
the current build. It quits the running copy first, which restores Caps Lock. Each rebuild
still needs the Accessibility permission re-added.

## Tests

```bash
swift test
```

The tests cover `TilerCore`: coordinate flipping, halves, size cycling, picking a screen,
moving between displays, ⇪ key bindings, and the `hidutil` remap handling. That module is
plain Foundation, so the tests also run on Linux.

## How it works

| File | Role |
|---|---|
| `Sources/TilerCore/Layout.swift` | Pure geometry, all in Accessibility coordinates (top-left origin of the primary display, y down). |
| `Sources/TilerCore/Cycle.swift` | Picks the next size for repeated presses (halves, quarters, and center). It compares against the frame the app actually accepted, because apps like Terminal round sizes. |
| `Sources/TinyTiler/WindowMover.swift` | Accessibility API (`AXUIElement`): finds the frontmost app's focused window, reads its frame, writes the new one. |
| `Sources/TilerCore/HyperKey.swift` | Hyper-key bindings, plus reading, merging, and writing `hidutil` key remaps. |
| `Sources/TinyTiler/HyperKeyController.swift` | Remaps Caps Lock to F18 with `hidutil`. A keyboard event tap tracks F18 being held and swallows the bound keys. Caps Lock alone can't do this, because it only reports on/off toggles. |
| `Sources/TinyTiler/LoginItem.swift` | Launch at login through `SMAppService.mainApp`. |
| `Sources/TinyTiler/AppDelegate.swift` | Menu-bar item, menu, and shortcut wiring. |

Details handled:

- `NSScreen` frames use a bottom-left origin; Accessibility uses top-left. `Layout.flip` converts between them.
- The size is set before and after the position, so windows aren't clamped to the old screen when they cross displays.
- `AXEnhancedUserInterface` is turned off for the duration of a move. When it's on, apps animate frame changes slowly.
- Accessibility calls time out after 1 second, so a hung app can't freeze TinyTiler.
- Full-screen windows are skipped, and the app beeps.

## Not included

Spaces, Stage Manager, and tiling layouts. Spaces have no public API.
