# Fathom engineering contract

Fathom is a depth-based Alt-Tab overlay plugin for Omarchy Quattro. Read
`docs/SPEC.md` before changing behavior and `docs/PHASE0.md` for status.

> [!CAUTION]
> Hyprland 0.56.2 crashed when Fathom's Lua snippet was loaded a second time
> in one compositor session. Before live binding work, read
> [`docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md`](docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md).

## Never crash the compositor

Fathom runs inside Maarten's working session. These hold without exception:

- `hypr/fathom.lua` starts with its load-once guard, keeps no Hyprland object
  (keybind, hook, rule) in Lua, and never tears one down (`:remove()`,
  `:unbind()`, `:set_enabled()`). `tests/static.test.sh` and the Lua tests
  (whose mock records every teardown, even one a `pcall` would swallow) fail
  otherwise.
- `bin/load-bindings` is the only thing that writes to the running Hyprland:
  no raw `hyprctl eval`, `reload`, `dispatch`, `keyword` or `plugin`, by hand,
  by an agent or in another script (`tests/static.test.sh` holds the scripts
  to it; a local agent hook blocks the commands). It refuses an unsafe
  snippet, records Hyprland's PID before and after, and stops at once when it
  changed.
- Never experiment with Hyprland's Lua API (or any compositor behavior not
  already verified) on the desktop. That belongs in the omakit lab, a
  disposable Omarchy guest with the same Hyprland.
- On any unexpected compositor exit: stop, inspect the core, write it down.
  Never repeat the triggering command to see if it happens again.
- Agents never test on or deploy to Maarten's desktop: it runs his session,
  his apps and his games. Every live test (keys, captures, the bench, the
  bindings, `omakit weigh`) runs in the omakit lab, a disposable Omarchy guest.
  Deploying a lab-proven build is Maarten's own `bash bin/dev-sync`. On the
  desktop an agent only reads (`bin/load-bindings --check`, `omarchy-shell
  fathom state`, read-only `hyprctl`); the local agent hook enforces it.

## Invariants

- v1 is an overlay only. Never move, resize or close a real window. The focus
  request (and the group tab activation before it) is the plugin's only
  compositor write. The Lua snippet, which the user loads into their own
  config, also switches Hyprland to the `fathom` submap while Alt is held and
  back when it is released, and adds one layer rule.
- No network, no daemon, no root. The plugin writes no files and starts no
  programs.
- The exclusive keyboard grab exists only while the field is open, and every
  way of ending a switch (Alt release, Escape, click, watchdog) closes it.
- Captures exist only while the field is open. The last frame of each window
  (a snapshot, to stand in for windows Hyprland cannot render) is kept in
  memory only, never on disk, for at most 24 windows, and goes with its window.
- Every input handler is idempotent: a second release, commit or cancel is a
  no-op.
- Addresses are sanitized to plain hex before they reach a dispatch string.
- Do not touch `~/.config/omarchy` outside this plugin's own directory. Enabling
  the plugin through `omarchy plugin enable` (which adds its entry to
  `shell.json`) is the one sanctioned exception.
- All code, identifiers, comments and user-facing text in English.
- No agent instruction file (`AGENTS.md`, `CLAUDE.md`, `SKILL.md`, `.mcp.json`,
  `.claude/`, `.codex/`) is ever tracked; this contract lives here, and
  `tests/manifest.test.sh` holds that line.

## Layout of the code

- Pure logic lives in `src/*.js` (`.pragma library`): `Recency.js` (focus
  times), `Depth.js` (depth and fog), `Field.js` (filter, navigation,
  workspaces, labels), `Layout.js` (the card stack and the map), `Focus.js`
  (dispatch strings), `Stats.js`. The node tests load the exact same files,
  so keep them free of Quickshell, and never start a line with `.`.
- `src/FieldSurface.qml` is the only file that needs a real layer-shell window;
  the offscreen QML tests swap it for `tests/qml/FieldSurface.qml` and replace
  Quickshell with `tests/qml/stubs`. Keep everything else testable that way.
- Look at a change before you ship it: `bash tests/qml/render.sh` renders the
  field offscreen into `screenshots-local/` (git-ignored) at real screen sizes.

## Checks

- `bash bin/test` must pass before any install or commit.
- `omarchy plugin validate .` must pass.
- New behavior gets a test in `tests/logic.test.js` (pure logic) or
  `tests/qml/tst_fathom.qml` (controller and view).

## The omakit workflow

Fathom follows omakit (`mtolhuys/omakit`, npm `omakit`, local checkout
`~/Projects/omarchy/omakit-public`). Install the CLI and its skills once:

```bash
npm i -g omakit && omakit setup
npx skills add mtolhuys/omakit
```

The skills (`omarchy-plugin-build`, `-check`, `-weigh`, `-submit`,
`-validation-watch`, `-audit`) say when each step applies. For Fathom:

- **Build.** Fathom starts no program and keeps no file of its own.
  `tests/static.test.sh` fails on a bare `Process`, `execDetached`,
  `StdioCollector`, `SplitParser` or `FileView`. If a feature ever needs a
  program, add omakit's Run block (`omakit add run .`, commit the copied
  files, never edit them) and start it through `Run {}`; state goes through
  the Store block (`omakit add store .`). Prefer data Quickshell already has
  over a new process.
- **Check.** After every change, on the committed HEAD:
  `omakit inspect . --json`, `omakit verify . --json` and
  `omakit submit . --category <c> --tags <a,b> --json --offline`. Category and
  tags are Maarten's editorial choice; ask, never invent them. Fix the cause a
  remedy names; never work around a check.
- **Prove.** Every live test runs in the omakit lab, never on the desktop.
  `omakit lab prove` runs omakit's own suites only, so Fathom's scenarios run
  in the same disposable guest through omakit's lab code. Frame times in the
  guest are not the integrated GPU's; they are still compared run to run.
- **Weigh.** `omakit weigh io.github.mtolhuys.fathom` before any submission
  and after any change that adds a timer or a subscription, in the lab guest
  (it restarts the shell it measures). Never on the desktop.
- **Submit and track.** `omakit submit` without `--offline` produces the issue
  text; Maarten posts it. Never open issues, comment or push on his behalf.

## Phases

Finish and report a phase before starting the next. Phase 0 (0.1.0) proved the
mechanics. Phase 1 (0.2.0, `docs/PHASE1.md`) is the card layout, the workspace
map, fog, blur, the wheel, arrows and the filter; mouse parallax is the one
Phase 1 item still open.
