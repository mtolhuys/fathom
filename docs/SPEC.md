# Fathom specification

Fathom replaces Alt-Tab with a spatial-temporal switcher for Omarchy Quattro.
Windows are placed on a z-axis by the time since they last had focus: the
window you used most recently is in front, sharp and large; older windows
recede into fog, smaller, blurred and dimmer. Holding Alt opens the field, Tab
dives one window deeper, the scroll wheel dives freely, the mouse parallaxes
the field, and releasing Alt focuses the window in front.

v1 is an overlay only: no real window moves.

Status: Phase 0 implemented (see [PHASE0.md](PHASE0.md)). Phase 1 not started.

Rules marked **(kickstart)** come from the original brief and are fixed. Rules
marked **(decision)** were settled while building Phase 0 and can be revisited.

## Terms

- **Field**: the ordered set of windows shown while Fathom is open.
- **Plane**: one window in the field, drawn from a live capture.
- **Depth**: a plane's distance on the z-axis, derived from time since focus.
- **Camera**: the viewer's position on the z-axis. It sits on the selection.
- **Selection**: the plane nearest the camera plane. It gets an outline.
- **Passed plane**: a plane in front of the selection (the camera went past it).

## Recency model

Hyprland keeps a focus order (`focusHistoryID`) but no timestamps, so Fathom
keeps its own map `address -> lastActiveAt` inside the plugin. **(kickstart)**

- Source: the Hyprland socket2 event stream, read through Quickshell's
  `Hyprland.rawEvent`. **(kickstart)**
  - `activewindowv2>>ADDRESS` is used instead of `activewindow`, because
    `activewindow` carries only class and title, no address. An empty address
    (a layer surface took focus, for example Fathom itself) changes nothing.
    **(decision)**
  - `openwindow>>ADDRESS,...` records the open time for a window the map does
    not know yet. A new window counts as recent even if it never takes focus.
    **(decision)**
  - `closewindow>>ADDRESS` removes the window.
- `lastActiveAt` is the last moment a window **held** focus: when focus moves
  from A to B, A is stamped with the moment it lost focus. The focused window
  is always zero seconds away. A window used for ten minutes and left five
  seconds ago is five seconds deep, not ten minutes. **(decision)**
- Seed at startup from Hyprland's client list: the window with
  `focusHistoryID = k` is assumed to have lost focus `k * 30 s` ago (one depth
  unit per step). A window with a negative `focusHistoryID` (never focused)
  stays unknown and sits at maximum depth. Events that arrive before the seed
  completes win over it. **(kickstart, step size is a decision)**
- The client list is the JSON `hyprctl clients -j` prints, but Fathom reads it
  from Quickshell: `Hyprland.refreshToplevels()` sends the same `j/clients`
  request over Quickshell's own socket and fills each toplevel's
  `lastIpcObject`. Fathom therefore starts no program at all, which is what
  omakit's build job asks of a plugin before anything else (a program it did
  start would have to go through omakit's Run block). The seed is retried
  every 500 ms until the reply has landed, and repeated for unknown windows
  each time the field opens. **(decision)**
- Time is frozen when the field opens; depths do not drift while it is open.

Addresses are stored lowercase without the `0x` prefix (socket2 and Quickshell
omit it, hyprctl prints it). Anything that is not plain non-zero hex is
rejected before it can reach a dispatch string.

## Window set

- Every mapped window on every regular workspace and every monitor.
- Excluded: special workspaces (scratchpads), unmapped windows, and windows
  without a Wayland toplevel handle (they cannot be captured). **(decision)**
- Order, front to back: the focused window, then ascending seconds since
  focus; ties by `focusHistoryID`, then by address. **(decision)**
- The overlay is shown on the focused monitor only; a surface per output
  would duplicate every capture. **(decision)**

## Depth rules **(kickstart)**

```
depth    = log2(1 + secondsSinceFocus / 30), clamped to [0, 8]
scale    = 1 / (1 + depth * 0.45)
opacity  = 1 - depth * 0.09
blur     = depth * 6 px            (Phase 1)
fog      = depth * 0.08 alpha      (Phase 1)
```

Reference points: 0 s is depth 0, 30 s is 1, 90 s is 2, 210 s is 3, about 2 h
08 min reaches the clamp at 8 (scale 0.217, opacity 0.28).

Planes are drawn as seen from the camera: the formulas take
`relativeDepth = depth - cameraDepth`, clamped at 0, for the selection and
every plane behind it. The selection is therefore always full size and fully
opaque. **(decision)**

Passed planes fade out over half a window step and grow by up to 30%, so they
read as flying past the viewer. Scale and opacity are continuous where the
camera meets a plane. **(decision)**

## Layout

Phase 0 **(decision, placeholder)**: the plane at the camera is centered and
fitted, at its window's aspect ratio, into a box of 56% of the screen. Planes
recede toward a vanishing point at (92%, 10%) of the screen: a plane at scale
`s` sits `(1 - s)` of the way from the center to that point. Because the point
lies outside the front plane, every smaller plane shows past the plane in front
of it. Planes at equal depth (for example several at the clamp) are separated
by a small per-step nudge up and to the right.

Phase 1 **(kickstart)**: perspective layout; front window centered; each deeper
window offset along a slight diagonal so they never fully occlude each other.

## Camera and input

- Alt+Tab opens the field with the camera on the second window (the one used
  before the current one), so a quick Alt+Tab switches back. Alt+Shift+Tab
  opens it at the far end. **(decision)**
- Tab moves the camera one window deeper, Shift+Tab one shallower. **(kickstart)**
  Both wrap around at the ends. **(decision)**
- The camera animates between windows in 180 ms (OutCubic). Depth and position
  animate together. **(decision)**
- Releasing Alt focuses the selection. Escape closes without focusing.
  **(kickstart)** Enter also commits; a click on a plane commits that plane; a
  click on empty space closes without focusing. **(decision)**
- The scroll wheel moves the camera continuously; the plane nearest the camera
  plane is the selection. **(kickstart, Phase 1)**
- Two modes **(decision)**:
  - *hold*: opened by the Alt chord (or `omarchy-shell fathom hold 1`, or a
    shell summon carrying `{"step": 1}`). Releasing Alt commits. A chord step
    arms hold mode even when the field was opened for browsing.
  - *browse*: opened without a step (`omarchy-shell fathom open`, a plain
    summon). Alt release does nothing; Enter, a click or Escape end it.
- Hold mode needs at least two windows; browse needs one.
- Watchdog: in hold mode, 15 s without input closes the field without
  focusing, in case an Alt release is ever missed. **(decision)**

### How input reaches the plugin

Omarchy Quattro's plugin manifest has no keybinding support, so the binding is
a Hyprland Lua snippet (`hypr/fathom.lua`) that sends Hyprland global shortcuts
to the shell: `fathom:next`, `fathom:previous` and `fathom:release`. Global
shortcut events reach the shell in order over one Wayland connection, so a
release can never overtake the open it belongs to.

A release bind on a bare modifier only fires when the modifier was tapped on
its own, so the release comes from a raw `input.keyboard.key` hook for keycodes
64 (Alt_L) and 108 (Alt_R), as in the altswitch plugin. The overlay also sees
the Alt release itself once it holds exclusive keyboard focus. Every handler is
idempotent, so two releases focus once.

## Focusing **(kickstart, adapted)**

- After the overlay surface is gone (100 ms), Fathom dispatches one focus
  request through Quickshell's `Hyprland.dispatch`, which writes to the same
  socket `hyprctl dispatch` uses.
- Omarchy Quattro runs Hyprland 0.56+ with a Lua config, where dispatchers are
  Lua expressions: `hl.dsp.focus({ window = "address:0x..." })`. This is what
  the kickstart's `focuswindow address:<addr>` becomes under a Lua config; the
  classic `focuswindow address:0x...` is still sent when Hyprland reports a
  hyprlang config. Focusing a window on another workspace switches to it.
- A window in a Hyprland group has its tab activated first
  (`hl.dsp.group.active`), because `hl.dsp.focus` ignores hidden group tabs.
- Waiting for the surface to unmap matters: releasing the exclusive keyboard
  grab makes Hyprland restore focus to the previous window, which would undo an
  earlier focus request.

## Mouse parallax **(kickstart, Phase 1)**

Horizontal and vertical offset proportional to depth, max 24 px at depth 8.

Open question: the brief says both "deep windows move less" and "max 24 px at
depth 8", which contradict each other. Proposed reading: the selection is
pinned (the thing you are about to pick never jitters) and planes behind it
shift by `24 px * relativeDepth / 8` against the pointer, like a camera
orbiting the selection. To confirm before Phase 1.

## Performance **(kickstart)**

- 60 fps target on integrated graphics.
- Degrade blur before dropping frames. Proposed Phase 1 policy, to confirm:
  when the frame probe's p95 exceeds 16.7 ms over 30 frames, halve the blur
  radius; if it still does, drop blur beyond depth 4; then drop blur entirely.
  Scale, opacity and fog are never degraded.
- Captures exist only while the field is open (`captureSource` is null when
  closed) and are rebuilt per open.
- The frame probe (a `FrameAnimation` plus the window's `frameSwapped` count)
  runs only when asked for, because it keeps the overlay rendering every vsync.

## Safety **(kickstart)**

- Never move, resize or close real windows in v1. The focus request (plus the
  group tab activation) is the only compositor write.
- No network, no daemon, no root. The plugin writes no files and starts no
  programs (`tests/static.test.sh` holds that line; if it ever has to change,
  processes go through omakit's Run block and files through its Store block).
- The exclusive keyboard grab lasts only while the field is open, and Escape,
  a click, the Alt release and the watchdog all close it.
- All code and identifiers in English.

## IPC

`omarchy-shell fathom <method>`:

| Method | Effect |
| --- | --- |
| `open` | Open in browse mode |
| `hold <1\|-1>` | Same as the Alt chord: open in hold mode or step |
| `step <1\|-1>` | Step while open |
| `release` | Same as releasing Alt |
| `commit` / `cancel` | Focus the selection / close without focusing |
| `state` | JSON: build identity, open state, mode, tracked windows, Lua config |
| `field` | JSON: the field with seconds, depth, scale and opacity per window |
| `captures` | JSON: per plane, whether a frame arrived and whether its workspace is on screen |
| `bench <seconds>` | Open, dive every 250 ms with the frame probe on, close |
| `stats` | JSON: last bench's frame times and time to first frame |

The shell's own `omarchy-shell shell summon|hide|toggle io.github.mtolhuys.fathom`
also work; a summon payload `{"step": 1}` behaves like the chord.

## Open questions

1. Parallax wording (see above).
2. Wrap at the ends, or stop? Phase 0 wraps, like classic Alt-Tab.
3. Show the field only after a short delay (about 80 ms) in hold mode, so a
   quick Alt+Tab switches without flashing the overlay?
4. Persist the recency map across shell restarts? Phase 0 does not (the plugin
   writes no files); a restart falls back to the focusHistoryID seed.
