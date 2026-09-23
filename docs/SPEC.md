# Fathom specification

Fathom replaces Alt-Tab with a spatial-temporal switcher for Omarchy Quattro.
Windows are placed on a z-axis by the time since they last had focus: the
window you used most recently is in front, older windows recede into the
distance and the fog. Holding Alt opens the field, Tab (or Down, or the wheel)
dives one window deeper, and releasing Alt focuses the window in front. Below
the depth view, a map shows every workspace with its windows where they
really are.

v1 is an overlay only: no real window moves.

Status: 0.2.0. Phase 0 (0.1.0, see [PHASE0.md](PHASE0.md)) proved the
mechanics; Phase 1 (0.2.0, see [PHASE1.md](PHASE1.md)) is the product: the
card layout, the sounding line, the workspace map, fog, background blur,
last-seen snapshots, the wheel, arrows and the filter. Mouse parallax is still
open.

Rules marked **(kickstart)** come from the original brief. Rules marked
**(decision)** were settled while building and can be revisited. Rules marked
**(owner)** were asked for by Maarten after using Phase 0.

## Terms

- **Field**: the ordered set of windows shown while Fathom is open.
- **The Deep**: the depth view, a stack of cards receding from the camera.
- **Card**: one window in the Deep, drawn from a live capture.
- **The map** (the Surface): one card per workspace, with a minimap of its
  windows.
- **The sounding line**: the depth gauge beside the Deep.
- **Fathom**: the unit of depth; a window `d` fathoms down lost focus
  `30 * (2^d - 1)` seconds ago.
- **Depth**: a window's distance on the z-axis, derived from time since focus.
- **Camera**: the viewer's position in the stack. It sits on the selection.
- **Selection**: the card at the camera. It gets the accent ring.
- **Passed card**: a card in front of the selection (the camera went past it).

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
  - `closewindow>>ADDRESS` removes the window, and drops it from an open
    field at once.
- `lastActiveAt` is the last moment a window **held** focus: when focus moves
  from A to B, A is stamped with the moment it lost focus. The focused window
  is always zero seconds away. **(decision)**
- Seed at startup from Hyprland's client list: the window with
  `focusHistoryID = k` is assumed to have lost focus `k * 30 s` ago. The order
  is Hyprland's and real; the times are a guess, so such a window is marked
  **estimated** and its age reads "earlier" until Fathom sees it lose focus.
  A window with a negative `focusHistoryID` (never focused) sits at maximum
  depth. Events that arrive before the seed completes win over it.
  **(kickstart, step size and labels are decisions)**
- The client list is the JSON `hyprctl clients -j` prints, but Fathom reads it
  from Quickshell: `Hyprland.refreshToplevels()` sends the same `j/clients`
  request over Quickshell's own socket and fills each toplevel's
  `lastIpcObject`. Fathom starts no program. The seed is retried every 500 ms
  until the reply lands, and repeated for unknown windows each time the field
  opens. **(decision)**
- Time is frozen when the field opens; ages do not drift while it is open.

Addresses are stored lowercase without the `0x` prefix. Anything that is not
plain non-zero hex is rejected before it can reach a dispatch string.

## Window set

- Every mapped window on every workspace and every monitor, scratchpads
  (special workspaces) included. **(owner: "all workspaces")**
- Excluded: unmapped windows, and windows without a Wayland toplevel handle
  (they cannot be captured). **(decision)**
- Order, front to back: the focused window, then ascending seconds since
  focus; ties by `focusHistoryID`, then by address. **(decision)**
- The field is frozen while open: a window that closes leaves it (the
  selection moves to the window behind it), a window that opens joins the next
  switch. **(decision)**
- The overlay is shown on the focused monitor only; a surface per output
  would duplicate every capture. **(decision)**

## Depth rules

```
depth    = log2(1 + secondsSinceFocus / 30), clamped to [0, 8]   (kickstart)
fog      = depth * 0.08 alpha                                     (kickstart)
blur     = the compositor blurs what is behind the overlay        (decision)
```

Reference points: 0 s is depth 0, 30 s is 1, 90 s is 2, 210 s is 3, about
2 h 08 min reaches the clamp at 8 (fog 0.64).

The brief also set `scale = 1 / (1 + depth * 0.45)` and
`opacity = 1 - depth * 0.09`. Phase 0 applied them, and in use most windows
were too small and too faint to recognise. **(owner)** Since 0.2 the stack
position is set by a window's place in the order, not its age, and age shows
as fog and as a label. Every card stays readable; an old window still looks
further away. **(decision)**

## The Deep **(decision)**

Every window is a card of the monitor's shape, with a header strip (app icon,
title, age) and the window fitted inside it, so the stack steps evenly
whatever the windows' own shapes are.

- The selection's card sits in the front box, as large as the Deep allows
  (at most half the screen's width).
- Each card behind it is scaled by 0.82 per step, and its top-right corner
  moves up and to the right by a step that shrinks by 0.86 per step. Every
  card therefore shows its whole header above the card in front of it and a
  band of its content to the right. The stack (front card plus five behind
  it) is centered in the space above the caption. Cards further back fade
  out; the map shows them.
- Fog darkens the capture of every card behind the camera, by its age and a
  little by its distance, never the header.
- Passed cards grow and slide out to the lower left, fading within 0.6
  steps.
- The camera animates between cards in 220 ms (OutCubic).
- Captures run only for cards near the camera (from one step passed to the
  last visible card) and only while the field is open.
- Hyprland renders a window for capture only while it lies within its
  monitor's area, so windows a scrolling layout parks beside the screen never
  deliver a frame (seen on the device; not a matter of minimizing, which
  Hyprland does not have). Each card therefore keeps the last frame it saw
  while the field was open: a snapshot of what the card drew, 400 ms after the
  first frame, at most 640 px wide, not taken again while younger than 30 s.
  When no live frame comes, the card shows its snapshot with a "last seen
  12 min ago" badge; a window never seen shows its app icon and name and says
  "off screen · no live preview". **(owner, decision)**
- Snapshots live in the shell's memory only, never on disk: at most 24
  windows, oldest dropped first, and a window's snapshot goes when the window
  does (on `closewindow`, or when it leaves Hyprland's toplevel list, because
  Hyprland reuses addresses). **(decision)**
- Urgent windows (Hyprland's urgent flag) get a red ring and dot.

## The sounding line **(owner: "earn the name", decision)**

A fathom is a unit of water depth, and depth is what Fathom measures. The
sounding line reads it the way a lead line reads water.

- A vertical gauge left of the Deep, from the surface (depth 0, "now", marked
  with ≈) down to 8 fathoms ("2h+"), with a mark per fathom labelled with the
  time it stands for: now, 30s, 1m, 3m, 7m, 15m, 31m, 1h, 2h+.
- Every window shown is a dot at its depth; windows at nearly the same depth
  sit side by side, and a row that does not fit ends in "+N". A window whose
  time is only an estimate (seeded at startup) is a hollow dot.
- The sounding lead (an accent diamond on an accent line from the surface)
  hangs at the selection's depth and descends as you dive, animated in
  260 ms.
- A click, or a drag, along the gauge selects the visible window nearest that
  depth: scrubbing through time.
- The light fades as you dive: a soft light from the top of the screen dims
  and the whole scene darkens (3.5 % per fathom) with the selection's depth.
- The caption reads the depth ("2.3 fathoms"; "at the surface" when just
  used; nothing for the focused window or an estimate).
- Shown when the screen is at least 1000 px wide; the Deep is laid out to its
  right.

## The map **(owner, decision)**

A row of cards along the bottom, one per workspace that has windows, plus the
workspace on screen even when it is empty; regular workspaces by number, then
named ones, then scratchpads.

- Each card shows the workspace's name, its window count ("2 of 5" while
  filtering), whether it is on screen, and the monitor's name when there is
  more than one.
- The minimap draws the monitor's screen area and every window at its real
  position and size, showing the last frame the field saw of it (the card's
  snapshot, when the tile is at least 36 by 24 units) or else its app icon,
  and its title where the tile has room (84 by 46 units). A scrolling
  layout's whole strip is shown, compressed; windows parked beside the screen
  are dimmer. The tabs of a group split their rectangle. Unknown geometry
  falls back to a grid.
- Positions follow Hyprland's client list, which is refreshed when the field
  opens, so the minimap is never older than the field.
- The selection is filled with the accent, the focused window has a bright
  outline, urgent windows a red one; windows filtered out fade.
- Card widths follow each minimap's shape and shrink together when the row is
  full.

## Camera and input

| Input | Hold mode (Alt held) | Browse mode |
| --- | --- | --- |
| Tab / Shift+Tab | one deeper / shallower, wrapping **(kickstart)** | same |
| Down / Up, wheel down / up | one deeper / shallower, stopping at the ends | same |
| Right / Left, sideways wheel | the most recent window of the next / previous workspace | same |
| Home / End, PageDown / PageUp | front / back, five deeper / shallower | same |
| 1 to 9 | the most recent window of that workspace | same, until a filter is typed |
| letters, digits after a letter | filter | filter |
| Backspace, Ctrl+Backspace | edit, clear the filter | same |
| Space | a space in the filter; with no filter, keep the field open after Alt (switch to browse) | a space in the filter |
| click or drag on the sounding line | the window at that depth | same |
| Enter, a click on a card, the caption or a map window | focus it | same |
| Escape | clear the filter, else close without focusing | same |
| click on empty space | close without focusing | same |
| release Alt | focus the selection (close when nothing matches) **(kickstart)** | nothing |

- Alt+Tab opens the field with the camera on the second window (the one used
  before the current one), so a quick Alt+Tab switches back. Alt+Shift+Tab
  opens it at the far end. **(decision)**
- Hold mode draws the field only after 90 ms: a quick Alt+Tab switches without
  flashing the overlay. The surface and its keyboard grab exist from the first
  moment, so no key reaches the window underneath. **(decision)**
- The filter matches every space-separated token against the app name, app
  id, title and workspace name, case-insensitively. A new query selects its
  most recent match. **(decision)**
- Hovering a window on the map selects it, but only after the pointer really
  moves: a pointer resting where the field opens selects nothing. Hovering a
  card in the Deep only highlights it, because the Deep moves under the
  pointer. **(decision)**
- Wheel notches step one window; touchpad pixels add up (60 px per window).
- Hold mode needs at least two windows; browse needs one.
- Watchdog: in hold mode, 15 s without input (any key, the wheel, pointer
  movement) closes the field without focusing, in case an Alt release is ever
  missed.

### How input reaches the plugin

Omarchy Quattro's plugin manifest has no keybinding support, so the binding is
a Hyprland Lua snippet (`hypr/fathom.lua`) that sends Hyprland global shortcuts
to the shell: `fathom:next`, `fathom:previous` and `fathom:release`. Global
shortcut events reach the shell in order over one Wayland connection, so a
release can never overtake the open it belongs to.

While Alt is held after Alt+Tab, Hyprland is in a `fathom` submap in which
only Fathom's two chords are bound. Every other Alt chord (Omarchy's
Alt+Left text navigation, another switcher's Alt+Up) then reaches the
overlay, which holds exclusive keyboard focus, instead of its usual binding.
Releasing Alt leaves the submap. **(decision)**

A release bind on a bare modifier only fires when the modifier was tapped on
its own, so the release comes from a raw `input.keyboard.key` hook, as in the
altswitch plugin. It acts only while a switch is held (set by the chord, with
or without the submap), for the keys that make Alt: keycodes 64 (Alt_L) and
108 (Alt_R), moved by the XKB options that move Alt (`altwin:swap_alt_win`,
`swap_lalt_lwin`, `swap_ralt_rwin`, `ctrl_alt_win`, `alt_win`,
`ctrl:swap_lalt_lctl`, `swap_ralt_rctl`, `swap_lalt_lctl_lwin`), read from
`input:kb_options` once per switch. A right Alt that types AltGr
(`lv3:ralt_switch`, an `intl` or `altgr` variant) does not commit. The
overlay also sees the Alt release itself, and when the `fathom` layer closes
for any reason a `layer.closed` hook leaves the submap, so the user's other
shortcuts can never be left held. Every handler is idempotent, so two
releases focus once.

The snippet binds nothing while the shell does not list Fathom in
`shell.json` (`omarchy plugin disable` and `remove` take it out), and returns
whether it took Alt+Tab, so a caller can fall back to another switcher. It
reads `shell.json` at each config load.

A second load in the same Lua state does nothing: tearing a keybind or an
event hook down from Lua crashed Hyprland 0.56.2 (see PHASE1.md). Changes to
the snippet take effect on `hyprctl reload`, which starts a fresh Lua state.
The hooks are set up before anything that could fail, the submap is optional,
so Alt+Tab works even where the submap cannot be defined, and the cosmetic
layer rule sits in a `pcall`.

## Focusing **(kickstart, adapted)**

- Fathom dispatches one focus request through Quickshell's
  `Hyprland.dispatch`, which writes to the same socket `hyprctl dispatch`
  uses: `hl.dsp.focus({ window = "address:0x..." })` under Hyprland's Lua
  config, `focuswindow address:0x...` under hyprlang. Focusing a window on
  another workspace switches to it.
- A window in a Hyprland group has its tab activated first
  (`hl.dsp.group.active`), because `hl.dsp.focus` ignores hidden group tabs.
- The request waits until the overlay's keyboard grab is gone: releasing it
  makes Hyprland restore focus to the previous window, which would undo an
  earlier request. Hyprland announces the restore (`activewindowv2` with the
  previous window's address) and the request goes out on that event; 120 ms
  is the fallback.
- A window that closed in the meantime gets no request.

## Mouse parallax **(kickstart, open)**

Horizontal and vertical offset proportional to depth, max 24 px at depth 8.

Open question: the brief says both "deep windows move less" and "max 24 px at
depth 8", which contradict each other. Proposed reading: the selection is
pinned and cards behind it shift by `24 px * relativeDepth / 8` against the
pointer. To confirm.

## Performance **(kickstart)**

- 60 fps target on integrated graphics.
- Captures exist only while the field is open, and only for cards near the
  camera; the map reuses the cards' snapshots (the same image and texture),
  never a capture of its own. Snapshots are grabbed at most once per window
  per 30 s, including the card one step behind the camera (the window you
  were on), which is captured anyway so stepping back is instant.
- App icons load only while shown.
- Per-card blur (the brief's `blur = depth * 6 px`) is not used: the fog
  carries depth, and the compositor's layer blur frosts the background once.
- The frame probe (a `FrameAnimation` plus the window's `frameSwapped` count)
  runs only when asked for, because it keeps the overlay rendering every vsync.

## Safety **(kickstart)**

- Never move, resize or close real windows in v1. The focus request (plus the
  group tab activation) is the only write to windows. The Lua snippet also
  switches Hyprland's submap while Alt is held, and adds one layer rule.
- No network, no daemon, no root. The plugin writes no files and starts no
  programs (`tests/static.test.sh` holds that line). The only window content
  that outlives a switch is the snapshots, in memory.
- The exclusive keyboard grab lasts only while the field is open, and Escape,
  a click, the Alt release and the watchdog all close it.
- All code and identifiers in English.

## Look **(decision)**

Colors come from Omarchy's theme (`qs.Commons`: foreground, background,
accent, urgent), derived by `src/Palette.js` and re-derived when the theme
changes; text from `Style.font.family` and Omarchy's text size. Corner radii
scale with the screen and with a card's depth.

- A theme is light when its background is lighter than its text. Dark: glass
  cards lit from above, fog into the dark, the scene darkening as you dive.
  Light: paper cards above a pale veil, a white light from the surface, a
  haze (fog at 70 %), the scene dimming toward the text color as you dive.
- Text tiers are mixed from the theme's text toward its background and held
  to floors: secondary 5.5:1 on the background and 4.5:1 on the lightest
  card, tertiary 4.5:1. `muted` is not used: it is a pale border tone on light
  themes and nearly the background on some dark ones. The accent is deepened
  (or lifted) to 3:1 for rings and marks and 4.5:1 as text.
- The backdrop is the theme background at 80 to 92 % (dark) or 86 to 95 %
  (light) from top to bottom, over a compositor blur (`hl.layer_rule` with
  `blur = true`), dense enough that text holds over a bright page behind a
  dark theme or a dark game behind a light one.
- The node tests hold every theme Omarchy ships to these floors
  (`tests/fixtures/omarchy-themes.json`).

## IPC

`omarchy-shell fathom <method>`:

| Method | Effect |
| --- | --- |
| `open` | Open in browse mode |
| `hold <1\|-1>` | Same as the Alt chord: open in hold mode or step |
| `step <1\|-1>` | Tab or Shift+Tab while open |
| `move <n>` | Move `n` windows, stopping at the ends |
| `workspace <1\|-1>` | The next or previous workspace's most recent window |
| `filter <text>` | Set the filter |
| `pin` | Keep the field open after Alt (switch to browse) |
| `release` | Same as releasing Alt |
| `commit` / `cancel` | Focus the selection / close without focusing |
| `state` | JSON: build identity, open, revealed, mode, counts, filter, snapshots kept, Lua config |
| `field` | JSON: every window with app, workspace, age, depth and fog |
| `captures` | JSON: per card, whether it captures, whether a frame arrived, whether it shows a snapshot, whether it is parked off screen, whether its workspace is on screen |
| `bench <seconds>` | Open, dive every 250 ms with the frame probe on, close |
| `stats` | JSON: last bench's frame times and time to first frame |

The shell's own `omarchy-shell shell summon|hide|toggle io.github.mtolhuys.fathom`
also work; a summon payload `{"step": 1}` behaves like the chord.

## Open questions

1. Parallax wording (see above).
2. Persist the recency map across shell restarts? The plugin writes no files;
   a restart falls back to the focusHistoryID seed, whose ages read
   "earlier". Persisting would need omakit's Store block.
3. Focusing a window on a hidden scratchpad: Hyprland's focus dispatcher is
   expected to show the scratchpad; not yet confirmed on a device.
4. A default binding for browse mode (an overview key) is not shipped; any
   bind can call `omarchy-shell fathom open`.
