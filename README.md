# Fathom

A depth-based Alt-Tab for [Omarchy](https://omarchy.org/) Quattro.

Windows are placed on a z-axis by how long ago you last used them. The window
you used most recently is in front, sharp and large; older windows recede,
smaller and dimmer. Hold `Alt`, dive with `Tab`, release `Alt` to focus the
window in front.

Fathom is an overlay only: it never moves, resizes or closes a window. Focusing
the one you pick is the only thing it asks the compositor to do.

> Status: Phase 0 (0.1.0, unreleased). Live thumbnails, depth applied to scale
> and opacity, Tab and Shift+Tab, focus on release. Blur, fog, parallax, the
> perspective layout and scroll dive come in Phase 1. See
> [docs/SPEC.md](docs/SPEC.md) and [docs/PHASE0.md](docs/PHASE0.md).

## Keys

| Keys | Action |
| --- | --- |
| `Alt`+`Tab` | Open the field on the window you used before this one |
| `Tab` again, `Alt` held | Dive one window deeper |
| `Alt`+`Shift`+`Tab` | Open at the far end, or rise one window |
| Release `Alt` | Focus the window in front |
| `Escape` | Close without focusing |
| `Enter` or a click on a window | Focus that window |
| Click on empty space | Close without focusing |

Depth follows `log2(1 + seconds since focus / 30)`, clamped to 8: a window you
left 30 seconds ago is one unit deep, two minutes ago about 2.3, an hour ago
about 7.

## Requirements

- Omarchy Quattro (the Quickshell shell and its plugin system)
- Hyprland 0.56 or newer, configured in Lua (Omarchy's default)

## Install (development)

```bash
bash bin/dev-sync
```

This runs the tests, installs the working tree as a plugin through `omarchy
plugin add`, enables it, and waits for it to answer on IPC.

Then load the keybindings. For the current session only:

```bash
hyprctl eval 'dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.mtolhuys.fathom/hypr/fathom.lua")'
```

To keep them, add this line to `~/.config/hypr/bindings.lua` and run
`hyprctl reload`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.mtolhuys.fathom/hypr/fathom.lua")
```

The snippet unbinds Omarchy's default `Alt`+`Tab` chords, binds them to
Fathom, and adds a raw key hook that reports the `Alt` release. Load it after
any other Alt-Tab plugin's bindings, or instead of them.

Without the Lua snippet, any Hyprland bind can drive Fathom through IPC:
`omarchy-shell fathom hold 1` behaves like `Alt`+`Tab`, and
`omarchy-shell fathom release` like releasing `Alt`.

## IPC

```bash
omarchy-shell fathom state      # build identity, open state, tracked windows
omarchy-shell fathom field      # every window with seconds, depth, scale, opacity
omarchy-shell fathom open       # open for browsing (Enter or click to focus)
omarchy-shell fathom bench 10   # dive through the field for 10 s with the frame probe on
omarchy-shell fathom stats      # frame times of the last bench
omarchy-shell fathom captures   # which thumbnails received a frame, and whether their workspace is on screen
```

The full list is in [docs/SPEC.md](docs/SPEC.md#ipc).

## Remove

Remove the `dofile` line (if you added it), then:

```bash
hyprctl reload
omarchy plugin remove io.github.mtolhuys.fathom
```

## Development

```bash
bash bin/test       # manifest, logic, Lua binding, offscreen QML tests, qmllint,
                    # ShellCheck, and `omarchy plugin validate` when available
bash bin/dev-sync   # install and enable the working tree in this session
```

The offscreen QML tests need the Qt 6 `qmltestrunner` (package
`qt6-declarative`). They run the real controller and view against stub
Quickshell modules in `tests/qml/stubs`.

Fathom follows the [omakit](https://github.com/mtolhuys/omakit) workflow. On a
committed change:

```bash
omakit inspect .                                   # what the tree does, file and line
omakit verify .                                    # the marketplace's own security baseline
omakit submit . --category <c> --tags <a,b> --offline
omakit weigh io.github.mtolhuys.fathom             # restarts the shell; asks first
```

Fathom starts no program and keeps no file of its own, so it carries neither
of omakit's blocks; `AGENTS.md` says what happens if that ever changes.

## Known limitations (Phase 0)

- The layout is a simple vanishing-point placeholder, not the Phase 1
  perspective layout.
- A very quick `Alt`+`Tab` shows the overlay for a moment before switching.
- The recency map starts over when the shell restarts; it is seeded from
  Hyprland's focus order.
- Special workspaces (scratchpads) are not included.

## License

[MIT](LICENSE)
