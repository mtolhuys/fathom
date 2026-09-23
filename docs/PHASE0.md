# Phase 0

Goal: an overlay that opens on Alt+Tab with live thumbnails of every window,
depth from recency applied to scale and opacity, Tab/Shift+Tab selection, and
focus on Alt release. Stop when it works.

Status: done (0.1.0, commit `16dbeeb`). It worked on the device, and using it
showed what Phase 1 had to fix: most windows were too small and faint to see,
the arrow keys did nothing, there was no wheel and no overview of the
workspaces. [PHASE1.md](PHASE1.md) is the answer; this page records Phase 0
as it was.

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

Omakit's workflow applies to Fathom as follows (see `DEVELOPMENT.md`):

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

Written before the device run; the results below answer each item.


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

Measured on 2026-09-23 on the device: Omarchy 4.0.4, Hyprland 0.56.2 with a
Lua config, Quickshell 0.3.1, Qt 6.11.2.

omakit inspect (processes, writes, hosts, patterns), omakit 0.6.9 on
`16dbeeb`: 106 processes, all in `bin/dev-sync`, `bin/test` and `tests/`, none
in QML; no hosts; 8 writes, all in the development scripts (`~/.cache/fathom`,
the test runner's `mktemp` directory); 4 timers (focus 100 ms one-shot,
watchdog 15 s one-shot, bench 250 ms only during a bench, seed retry 500 ms at
most 20 times). Two review classes observed, both in the development scripts
only: file-and-state-boundary (4 `mkdir` without a mode, 15 % of review
findings) and environment-trust (tools resolved from PATH, 7 %). Size score
7.76.

omakit verify (baseline outcome, verbatim): `"outcome": "passed"`,
`"disposition": "clear"`, `"blocksApproval": false`, `"findings": []`,
`"capabilities": []` (pin `b7b2965`, baseline 3, enforcement selective). The
first run did not invoke the baseline at all (`"skipReason": "no declared
GitHub repository URL"`): omakit reads the URL from a github.com `origin`
remote, so `git@github.com:mtolhuys/fathom.git` was added locally (nothing was
created or pushed).

omakit submit --offline (outcome, refused or advisory checks), category
Desktop, tags Hyprland, Quickshell, Workspaces: `ready`, nothing blocking.
One advisory, `tree.agent-control` (an `AGENTS.md` in the installable tree),
fixed in `16dbeeb` by moving the contract to `DEVELOPMENT.md`. Skipped
offline: `submission.validation-commit`, `submission.issue-repository-url`.

omakit weigh (CPU and child processes against the baseline spread): not run.
Maarten agreed to it, then asked for testing to move to the omakit lab. The lab
runs only omakit's own suites (`lab prove run|store|weigh|weigh-evidence`),
not a plugin's; a driver that ran Fathom's suite and `omakit weigh --yes`
inside a lab guest through omakit's own lab code was stopped by the session's
permission check. Pending Maarten's decision.

Frame times from `omarchy-shell fathom bench 10` (0.1.0). The field always held
Maarten's own 7 windows too, so the test windows (foot, one app id each, on
three workspaces that were not on screen) come on top of those; the 25-window
run was not done because testing moved to the lab.

| Test windows (field) | p50 ms | p95 ms | p99 ms | max ms | late frames | swapped fps | first frame ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 3 (10) | 5.01 | 5.46 | 5.70 | 9.08 | 1 | 178.8 | 38 |
| 10 (17) | 5.01 | 5.77 | 5.91 | 9.76 | 1 | 179.4 | 29 |
| 25 | | | | | | | |

GPU / display: AMD Strix Halo (Radeon 8060S, amdgpu), eDP-1 2560x1600 at
180 Hz, scale 1.6. The overlay kept up with the 180 Hz panel (5.56 ms per
frame) with room to spare.

Capture on workspaces not on screen: yes. Windows on hidden workspaces
delivered real pixels (confirmed in a screenshot with the field open, not only
by `hasContent`). The exception is a scrolling layout: windows it parks beside
the screen get no frame, on the visible workspace and on hidden ones alike,
because Hyprland does not render them. 0.2 shows their app icon instead.

Keyboard and focus behavior: the bindings loaded (`hyprctl eval` answered
`ok`, `hyprctl configerrors` was empty), `hyprctl globalshortcuts` listed
`fathom:next`, `fathom:previous` and `fathom:release`, and
`omarchy-shell fathom state` reported `seeded: true`. Keys were not injected:
`wtype` cannot send a raw Alt keycode (the release hook reads keycodes 64 and
108), `ydotool` is not installed, and the lab run was stopped. In Maarten's own
use Alt+Tab worked and the arrow keys did nothing: on this machine Alt+Left
and Alt+Right are bound to text navigation and Alt+Up and Alt+Down to the
altswitch plugin, and Hyprland handles a bound chord before the overlay sees
it. 0.2 holds a `fathom` submap while Alt is down.

## Where the platform differed from the spec

- `hyprctl binds -j` shows a Lua bind's dispatcher as `__lua` with a
  reference number, not `global fathom:next`; the description is what
  identifies it.
- Hyprland claims a bound Alt chord before a layer surface with exclusive
  keyboard focus sees it (see above).
- Qt 6.11's `qmllint` dropped `--type` (now `--unresolved-type`), and an
  installed Quickshell wins over stub modules on the import path unless
  `--bare` is given; it also flags a `property var state` on an Item as
  overriding `Item.state`.
- `omakit verify` needs a github.com `origin` remote to run the baseline.
- `npx skills add mtolhuys/omakit` replaced the `~/.claude/skills` symlinks
  with copies, leaving older copies of three skills in `~/.agents/skills`.
- `omakit lab prove` has no way to run a plugin's own scenarios (as its
  contract, `docs/LAB.md`, says).
