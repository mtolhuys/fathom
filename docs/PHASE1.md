# Phase 1 (0.2.0)

Goal, from using Phase 0: see every window, see what is on every workspace,
move with the arrows and the wheel, and make it something a person finds
beautiful and handy. Mouse parallax, the brief's last Phase 1 item, is still
open (see the open question in [SPEC.md](SPEC.md)).

## Built

| Piece | File |
| --- | --- |
| Controller: frozen field and visible order, keys, wheel, filter, workspaces, pinning, reveal delay, live closes, focus on restore, IPC | `src/Fathom.qml` |
| Field logic: filter, stepping, reselection, workspace groups and neighbors, wheel steps, labels | `src/Field.js` |
| Geometry: the card stack, the stage, minimap bounds and items, map card widths | `src/Layout.js` |
| Depth and fog from time | `src/Depth.js` |
| Recency, with estimated (seeded) ages | `src/Recency.js`, `src/RecencyTracker.qml` |
| The view: backdrop, the Deep, caption, filter, hints, keys, wheel, pointer gate | `src/FieldView.qml` |
| One card: header, fitted capture, fog, rings, placeholder | `src/WindowPlane.qml` |
| The map and its workspace cards with minimaps | `src/WorkspaceMap.qml`, `src/WorkspaceCard.qml` |
| App icons with a lettered fallback | `src/AppIcon.qml` |
| Bindings: the `fathom` submap, the Alt release hook, reload, blur | `hypr/fathom.lua` |
| Offscreen renders for design review | `tests/qml/render.sh`, `tests/qml/render/tst_render.qml` |

## Design, in short

- **Cards, not shrinking windows.** Every window is a card of the monitor's
  shape with a header (icon, title, age). The stack steps evenly up and to the
  right, so every card shows its whole header and a band of its content.
  Age shows as fog and in the header. [SPEC.md](SPEC.md#the-deep-decision)
  has the numbers.
- **A map of every workspace.** One card per workspace with a minimap of its
  windows at their real positions, including the windows a scrolling layout
  parks beside the screen, and the scratchpads.
- **Keys that make sense while Alt is held.** Up and Down (and the wheel) dive,
  Left and Right move between workspaces, digits jump to one, letters filter,
  Space keeps the field open. A Hyprland submap keeps the user's own Alt
  chords out of the way only while a switch is in progress.
- **No flash, no lag.** A quick Alt+Tab never draws the field; the focus
  request goes out the moment Hyprland gives focus back after the grab.
- **Honest.** Ages seeded from Hyprland's focus order read "earlier"; windows
  that cannot be captured show their app, not an empty frame; closed windows
  leave the field.

## Verified without a session

`bin/test` runs all of these; they pass.

- Logic (node, 33 tests): fog; recency with estimated ages; the field's
  filter, visible order, stepping (Tab wraps, arrows stop), reselection,
  workspace groups and neighbors, digits, wheel steps, labels; the card
  stack (every card shows a header strip of at least 24 px and a band on
  the right, the stack is centered and stays on screen, the camera is
  continuous); fitting; minimaps (whole scrolling strips, tab groups, grid
  fallback); map card widths.
- Bindings (Lua, mocked `hl` with submaps): the chords, the submap holding only
  those chords, entering it once, leaving it and sending the release on either
  Alt, the blurred layer rule, and a second load replacing the first.
- QML (qmltestrunner, 37 tests): everything Phase 0 covered, plus arrows with
  and without Alt, Home, End, PageDown, workspace left and right, digits,
  typing to filter (digits join a filter, Enter with no match does nothing,
  the first Escape clears), Alt+letters filtering while holding, releasing
  with no match, Space keeping the field open, wheel notches and touchpad
  pixels, a window closing mid-switch (by event and by the toplevel list), no
  focus request for a window gone before it, no drawing on a quick Alt+Tab,
  map hover selecting only after the pointer moves, the map's groups, focus on
  Hyprland's restore event, and caption and filter pill clicks.
- `qmllint` against the stubs, with no warnings; ShellCheck; `omarchy plugin
  validate`.
- Offscreen renders (`bash tests/qml/render.sh`) of 3, 10, 15, 40 windows, a
  filter, no match, an uncapturable selection, a 1366x768 screen and the
  scrolling layout of the machine it was designed on, reviewed by eye.

## Verified on the device

Installed with `bin/dev-sync` and the bindings loaded with `hyprctl eval`
on 2026-09-23 (Omarchy 4.0.4, Hyprland 0.56.2, Quickshell 0.3.1).

- The plugin loaded without a warning in the shell's log; `state` reported
  `0.2.0-deep`.
- `hyprctl binds -j` shows Alt+Tab and Alt+Shift+Tab in the default and the
  `fathom` submap; `hyprctl configerrors` is empty; entering the `fathom`
  submap and `hl.dsp.submap("reset")` both work (`hyprctl submap`).
- With the field open over real windows: app icons resolve from the desktop
  entries, the compositor blurs the background, the theme's accent and font
  apply, captures arrive for windows on hidden workspaces, and windows parked
  beside the screen show their icon. The same screenshot showed the map
  drawing a window parked several screens away outside its card; fixed
  (`5c36874`) and covered by a test.

## Not yet verified

- Frame times of 0.2 on the device (cards with rounded clipping, shadows and
  the layer blur): `omarchy-shell fathom bench 10` with 3, 10 and 25 windows.
- Keys by hand on the device: Alt+Tab quick tap, Alt+Tab+Tab, Alt+Shift+Tab,
  Alt+arrows, Alt+digits, Alt+letters, Space, Escape, a click, the wheel and a
  touchpad.
- That the focus request really goes out on Hyprland's restore event (the
  120 ms fallback covers it either way).
- Focusing a window on a hidden scratchpad.
- `omakit weigh io.github.mtolhuys.fathom`.

## Check loop

On the committed HEAD: `omakit inspect`, `omakit verify` and `omakit submit
--offline --category Desktop --tags Hyprland,Quickshell,Workspaces`; the
results are in the commit that records them.
