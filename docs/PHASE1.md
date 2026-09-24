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
| The sounding line (depth gauge in fathoms) | `src/SoundingLine.qml` |
| Last-seen snapshots, in memory | `src/Fathom.qml`, `src/WindowPlane.qml` |
| App icons with a lettered fallback, loaded only while shown | `src/AppIcon.qml` |
| Every color, from the theme, light or dark | `src/Palette.js` |
| Bindings: the `fathom` submap, the Alt release hook, load once, blur | `hypr/fathom.lua` |
| The one way to load them into a running Hyprland, with checks before and after | `bin/load-bindings` |
| Offscreen renders for design review | `tests/qml/render.sh`, `tests/qml/render/tst_render.qml` |

## Design, in short

- **Cards, not shrinking windows.** Every window is a card of the monitor's
  shape with a header (icon, title, age). The stack steps evenly up and to the
  right, so every card shows its whole header and a band of its content.
  Age shows as fog and in the header. [SPEC.md](SPEC.md#the-deep-decision)
  has the numbers.
- **A map of every workspace.** One card per workspace with a minimap of its
  windows at their real positions, including the windows a scrolling layout
  parks beside the screen, and the scratchpads. Each shows the last frame the
  field saw of it, reused from its card, and its title where there is room.
- **Any theme.** Light themes get paper cards over a pale veil; every text
  tier holds its contrast in all 22 Omarchy themes.
- **Keys that make sense while Alt is held.** Up and Down (and the wheel) dive,
  Left and Right move between workspaces, digits jump to one, letters filter,
  Space keeps the field open. A Hyprland submap keeps the user's own Alt
  chords out of the way only while a switch is in progress.
- **The sounding line.** The name's instrument: a gauge in fathoms (now at the
  surface, two hours at eight fathoms) with a dot per window and the sounding
  lead at the selection; dragging along it scrubs through time. The light
  fades as you dive.
- **No blank cards.** Hyprland does not render windows outside their
  monitor's area (a scrolling layout parks them there), so they never
  deliver a frame. Cards show the last frame Fathom saw of them, with its age,
  or say they are off screen.
- **No flash, no lag.** A quick Alt+Tab never draws the field; the focus
  request goes out the moment Hyprland gives focus back after the grab.
- **Honest.** Ages seeded from Hyprland's focus order read "earlier"; windows
  that cannot be captured show their app, not an empty frame; closed windows
  leave the field.

## Verified without a session

`bin/test` runs all of these; they pass.

- Logic (node, 38 tests): fog; recency with estimated ages; the field's
  filter, visible order, stepping (Tab wraps, arrows stop), reselection,
  workspace groups and neighbors, digits, wheel steps, labels; the card
  stack (every card shows a header strip of at least 24 px and a band on
  the right, the stack is centered and stays on screen, the camera is
  continuous, the stage leaves room for the gauge); fitting; minimaps (whole
  scrolling strips, tab groups, grid fallback); off-screen detection; map
  card widths, never wider than the screen; the sounding line (depth to y,
  side-by-side marks, "+N", nearest visible mark, fathom labels).
- Bindings (Lua, mocked `hl` with submaps): the chords, the submap holding only
  those chords, entering it once, leaving it and sending the release on either
  Alt, the blurred layer rule, a second load changing nothing, and Alt+Tab
  working where the submap cannot be defined.
- QML (qmltestrunner, 42 tests): everything Phase 0 covered, plus arrows with
  and without Alt, Home, End, PageDown, workspace left and right, digits,
  typing to filter (digits join a filter, Enter with no match does nothing,
  the first Escape clears), Alt+letters filtering while holding, releasing
  with no match, Space keeping the field open, wheel notches and touchpad
  pixels, a window closing mid-switch (by event and by the toplevel list), no
  focus request for a window gone before it, no drawing on a quick Alt+Tab,
  map hover selecting only after the pointer moves, the map's groups, focus on
  Hyprland's restore event, caption and filter pill clicks, snapshots (kept,
  shown with the parked state, not retaken while fresh, dropped with their
  window, also without an event), Space between filter words, clicks before
  the field is drawn, and picking on the sounding line with the lead
  following.
- `qmllint` against the stubs, with no warnings; ShellCheck; `omarchy plugin
  validate`.
- Offscreen renders (`bash tests/qml/render.sh`) of 3, 10, 15, 40 windows, a
  filter, no match, an uncapturable selection, a 1366x768 screen, the
  scrolling layout of the machine it was designed on, a snapshot and a window
  never seen, reviewed by eye.
- A review of everything since Phase 0 (`/code-review high`) found ten issues,
  all fixed: a Lua reload that could leave the submap behind, snapshots
  retaken on every open, snapshots outliving windows gone without an event,
  Space pinning mid-filter, the map row overflowing, hidden gauge marks being
  pickable, clicks landing before the field was drawn, no-op keys not
  counting for the watchdog, grabbing a hidden effect source, and these docs.

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

- Loading the 0.2 snippet a second time in the same session (`hyprctl eval`
  of `dofile`) crashed Hyprland 0.56.2 (SIGABRT inside its Lua API, called
  from a `pcall` while the reload removed the first load's keybinds and hook
  and redefined the submap); Hyprland's watchdog restarted it in safe mode.
  The mocked `hl` of the Lua tests could not show it. Since `8f67bae`, a second
  load in one Lua state does nothing and changes need `hyprctl reload`.
  Which of the three calls crashes is not known without Hyprland's symbols.

- After the crash (`44b459e`), on a fresh Hyprland session: the persistent
  block in `~/.config/hypr/bindings.lua` (altswitch as the fallback) loaded
  the snippet on Hyprland's own config reload, and `bash bin/dev-sync`
  installed HEAD and ran `bin/load-bindings --fresh`, which reloaded the
  config once. Hyprland kept PID 2530 through both, `hyprctl configerrors`
  stayed empty, Alt+Tab and Alt+Shift+Tab are Fathom's in the default and the
  `fathom` submap, altswitch's other Alt chords are gone, and the installed
  tree is HEAD.

## Verified in the omakit lab (0.2.1)

On 2026-09-25, in omakit's disposable Omarchy 4.0.4 guest (Hyprland 0.56.2,
Quickshell 0.3.1, QEMU's keyboard and tablet), driven with real keys over
QMP, on 58b0dc6; the run records, documents and screenshots are under
`~/.local/state/omakit/lab/runs/` (`20260925-002657-fathom-0.2.1`,
`20260925-005118-fathom-0.2.1`, and the 0.2.0 runs beside them):

- The README block loads the snippet through the installed
  `bin/load-bindings`, and a config reload (`--fresh`, twice: a device
  override added and removed) loads it again in a fresh Lua state, with
  Hyprland's PID unchanged and `configerrors` empty each time.
- Keys: a quick Alt+Tab, Alt held with Tab and Shift+Tab, Down and Up, Left,
  a digit, the wheel, a two-token filter typed, Space then Enter, Escape. A
  chord over a filter that matches nothing closes after the 15 s watchdog;
  `kb_options` set for the keyboard alone (`hl.device`) commits on the key
  held for the chord at 60, 20 and 5 ms taps. Both reproduced as bugs on
  0.2.0 (6e032d0) in the same guest.
- The field, the sounding line and the map's last-seen frames render
  (screenshots in the run directories).
- `omakit weigh` (three runs): no measurable CPU against a 0.07% floor, no
  child process, memory within the shell's own startup variance; 0.2.0 the
  same.
- `omarchy-shell fathom bench 5` with 3 windows: p50 13.0 ms, p95 18.5 ms,
  p99 20.6 ms (0.2.0: 13.0, 18.3, 22.6), on the guest's virtio-vga.

## Not yet verified

- Frame times on the device with 10 and 25 windows.
- A click on a card, the caption and the map, and a touchpad, by hand.
- A sideways wheel (the guest's tablet delivers none; the multi-step fling
  is held by the QML test).
- That the focus request really goes out on Hyprland's restore event (the
  120 ms fallback covers it either way).
- Focusing a window on a hidden scratchpad.

## Check loop

On the committed HEAD: `omakit inspect`, `omakit verify` and `omakit submit
--offline --category Desktop --tags Hyprland,Quickshell,Workspaces`; the
results are in the commit that records them.
