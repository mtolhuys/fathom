# Phase 0

Goal: an overlay that opens on Alt+Tab with live thumbnails of every window,
depth from recency applied to scale and opacity, Tab/Shift+Tab selection, and
focus on Alt release. Stop when it works.

## Built

| Piece | File |
| --- | --- |
| Controller: field, camera, modes, focus, IPC, global shortcuts | `src/Fathom.qml` |
| Layer-shell window (overlay layer, exclusive keyboard while open) | `src/FieldSurface.qml` |
| Field contents: planes, caption, keys, frame probe | `src/FieldView.qml` |
| One window: live `ScreencopyView`, depth-driven scale and opacity | `src/WindowPlane.qml` |
| socket2 recency tracker, seeded from Hyprland's client list through Quickshell (no process) | `src/RecencyTracker.qml`, `src/Recency.js` |
| Depth rules and Phase 0 placement | `src/Depth.js` |
| Focus dispatch strings (Lua and hyprlang) | `src/Focus.js` |
| Frame probe and statistics | `src/FrameProbe.qml`, `src/Stats.js` |
| Hyprland bindings and Alt release hook | `hypr/fathom.lua` |

Prior art studied before writing the capture and input code: Exposé
(`expose.window-overview`), Stage (`zzwong.stage`), Omascape
(`se.mindfulstack.omascape`), altswitch (`io.github.pablo-merino.altswitch`)
and hyprland-alttab (`vbrosseau.alttab`). Fathom uses a plain Quickshell
`PanelWindow` on the overlay layer: neither the current omakit
(`mtolhuys/omakit`, blocks Run and Store) nor the archived runtime
(BarPanelPlugin, CommandTask, PluginStore) has an overlay base.

Omakit's workflow applies to Fathom as follows (see `AGENTS.md`):

| Job | For Fathom |
| --- | --- |
| Build | Fathom starts no program and keeps no file, so neither block is added; `tests/static.test.sh` fails if a bare `Process`, `execDetached` or `FileView` appears |
| Check | `omakit inspect`, `omakit verify` and `omakit submit --offline` on every committed change |
| Prove | `omakit lab prove` runs omakit's own suites only, not a plugin's scenarios; Fathom's keyboard and capture behavior is checked on the desktop |
| Weigh | `omakit weigh io.github.mtolhuys.fathom`, with Maarten's consent: Fathom is keepLoaded and follows socket2 all session |

## Verified without a session

`bin/test` runs all of these; they pass.

- Manifest invariants, and the upstream `omarchy-plugin-validate` rules.
- Logic tests (node): depth, scale and opacity formulas, passed planes,
  recency events and seeding, field order and filtering, selection, focus
  dispatch strings, frame statistics.
- Binding tests (Lua, mocked `hl`): unbinds and binds, raw key hook forwards
  only Alt releases.
- QML tests (qmltestrunner, offscreen, stub Quickshell modules): the real
  controller, view, planes, probe and tracker. Alt+Tab opens on the previous
  window, Tab/Shift+Tab/Backtab step, Alt release and Enter commit, Escape and
  empty clicks cancel, a click on a plane focuses it, two releases focus once,
  browse mode ignores Alt release, the summon payload works, hyprlang fallback,
  grouped windows, socket2 events reorder the field, unusable windows are left
  out, planes apply depth to scale and opacity and recede without full
  occlusion, capture report, bench and stats.
- Static source rules: no program started, no file kept, no network.
- qmllint against the stubs, ShellCheck on the scripts.

## Not yet verified (needs the live session)

- The omakit check loop (`inspect`, `verify`, `submit --offline`) and
  `omakit weigh`; the omakit CLI runs on the desktop, not here.
- That Quickshell's `lastIpcObject` carries `focusHistoryID` on this machine
  (`omarchy-shell fathom state` reports `seeded: true`).
- The Hyprland Lua API calls in `hypr/fathom.lua` (`hl.dsp.global`,
  `hl.dispatch`, `hl.on("input.keyboard.key")`) on this machine's Hyprland.
- Exclusive keyboard focus on the layer surface, and whether Hyprland still
  fires the Alt+Tab bind while Fathom holds it (both paths are handled).
- Live captures, frame times and first-frame latency on real hardware.
- Toplevel capture for windows on workspaces that are not on screen. Prior
  art (Omascape on Quickshell 0.3.1 / Hyprland 0.56.2) reports that it works;
  `omarchy-shell fathom captures` answers it for this machine.

## Measurement protocol

1. `bash bin/dev-sync` installs and enables the working tree.
2. `hyprctl eval 'dofile("<plugin dir>/hypr/fathom.lua")'` loads the bindings
   for this session only.
3. For each N in 3, 10, 25: open N windows (for example `foot` with a
   distinctive app id), spread over at least three workspaces, with some on
   workspaces that are not on screen. Then:
   - `omarchy-shell fathom bench 10`, wait 11 s;
   - `omarchy-shell fathom stats` and `omarchy-shell fathom captures`;
   - take a screenshot while the field is open (`omarchy-shell fathom open`,
     `grim`, `omarchy-shell fathom cancel`) to confirm off-screen thumbnails
     are real pixels, not black: `hasContent` only says a buffer arrived.
4. Manual: Alt+Tab quick tap, Alt+Tab+Tab, Alt+Shift+Tab, Escape, click.

## Results

To be filled on the device.

omakit inspect (processes, writes, hosts, patterns):

omakit verify (baseline outcome, verbatim):

omakit submit --offline (outcome, refused or advisory checks):

omakit weigh (CPU and child processes against the baseline spread):

| Windows | p50 ms | p95 ms | p99 ms | max ms | late frames | swapped fps | first frame ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 3 | | | | | | | |
| 10 | | | | | | | |
| 25 | | | | | | | |

GPU / display:

Capture on workspaces not on screen:

Keyboard and focus behavior:
