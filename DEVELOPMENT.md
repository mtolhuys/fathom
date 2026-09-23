# Fathom engineering contract

Fathom is a depth-based Alt-Tab overlay plugin for Omarchy Quattro. Read
`docs/SPEC.md` before changing behavior and `docs/PHASE0.md` for status.

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
- **Prove.** `omakit lab prove` runs omakit's own suites, not a plugin's
  scenarios, so it does not cover Fathom yet. Frame times need the real
  integrated GPU anyway; installing on the desktop (`bin/dev-sync`) is the
  deliberate exception to omakit's lab-first rule and happens only with
  Maarten's go.
- **Weigh.** `omakit weigh io.github.mtolhuys.fathom` before any submission
  and after any change that adds a timer or a subscription. It restarts the
  shell, so ask Maarten first; never pass `--yes` on his behalf.
- **Submit and track.** `omakit submit` without `--offline` produces the issue
  text; Maarten posts it. Never open issues, comment or push on his behalf.

## Phases

Finish and report a phase before starting the next. Phase 0 (0.1.0) proved the
mechanics. Phase 1 (0.2.0, `docs/PHASE1.md`) is the card layout, the workspace
map, fog, blur, the wheel, arrows and the filter; mouse parallax is the one
Phase 1 item still open.
