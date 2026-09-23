# Fathom

A depth-based Alt-Tab for [Omarchy](https://omarchy.org/) Quattro.

Windows are placed on a z-axis by how long ago you last used them. The window
you used most recently is in front; older ones recede into the distance and
the fog. Hold `Alt`, dive with `Tab`, the arrows or the wheel, release `Alt` to
focus the window in front. Below the stack, a map shows every workspace with
its windows where they really are.

Fathom is an overlay only: it never moves, resizes or closes a window. Focusing
the one you pick is the only thing it asks the compositor to do.

> Status: 0.2.0 (unreleased). See [docs/SPEC.md](docs/SPEC.md),
> [docs/PHASE0.md](docs/PHASE0.md) and [docs/PHASE1.md](docs/PHASE1.md).

## What you see

- **The Deep.** The window you are about to switch to is a large live card in
  front. Every window behind it is a card too, stepping back up and to the
  right, each with its app icon, title and how long ago you used it. Older
  windows sink into the fog.
- **The map.** A card per workspace (scratchpads included) with a minimap of
  its windows at their real positions, each with its app icon. You see which
  workspace is on screen, which window is focused, which one wants your
  attention, and what a scrolling layout has parked beside the screen.
- **The sounding line.** A depth gauge beside the stack, marked in fathoms from
  "now" at the surface to two hours down. Every window is a dot at its depth,
  and the sounding lead hangs at the one you are on, descending as you dive;
  the light fades with it. Click or drag along the line to pick a window by
  how long ago you used it.
- **The caption.** The selection's title, app, workspace, age and depth.

A window your scrolling layout parks beside the screen cannot be captured
(Hyprland does not render it). Fathom shows the last frame it saw of that
window, marked "last seen", or says it is off screen. Those frames stay in
memory only.

## Keys

Hold `Alt` while you use these; release `Alt` to focus the selection.

| Keys | Action |
| --- | --- |
| `Alt`+`Tab` | Open on the window you used before this one |
| `Tab` / `Shift`+`Tab` | One window deeper / shallower (wraps) |
| `↓` / `↑`, wheel | One window deeper / shallower |
| `→` / `←`, sideways wheel | The most recent window of the next / previous workspace |
| `1` to `9` | The most recent window on that workspace |
| `Home` / `End`, `PageDown` / `PageUp` | Front / back, five windows |
| Type letters | Filter by app, title or workspace (`Space` between words) |
| `Space` | Keep the field open after you release `Alt` |
| Click or drag on the sounding line | The window at that depth |
| `Enter`, a click on a window or the caption | Focus it |
| `Escape` | Clear the filter, or close without focusing |
| Click on empty space | Close without focusing |

A quick `Alt`+`Tab` switches back without drawing the overlay at all.

While you hold `Alt` after `Alt`+`Tab`, Fathom's bindings put Hyprland in a
`fathom` submap, so your own `Alt` shortcuts (Omarchy's `Alt`+`←` text
navigation, another switcher's `Alt`+`↑`) do not get in the way. They are back
the moment you release `Alt`.

Depth follows `log2(1 + seconds since focus / 30)`, clamped to 8: a window you
left 30 seconds ago is one unit deep, two minutes ago about 2.3, an hour ago
about 7. Right after the shell starts, Fathom knows the order of your windows
but not when you used them; those say "earlier" until you switch.

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
Fathom, adds a raw key hook that reports the `Alt` release, and frosts the
background behind the overlay. Load it after any other Alt-Tab plugin's
bindings, or instead of them. Loading it again replaces the previous load.

Without the Lua snippet, any Hyprland bind can drive Fathom through IPC:
`omarchy-shell fathom hold 1` behaves like `Alt`+`Tab`,
`omarchy-shell fathom release` like releasing `Alt`, and
`omarchy-shell fathom open` opens the overview to browse with the keyboard.

## IPC

```bash
omarchy-shell fathom open       # open for browsing (Enter or click to focus)
omarchy-shell fathom state      # build identity, open state, counts, filter
omarchy-shell fathom field      # every window with app, workspace, age, depth, fog
omarchy-shell fathom bench 10   # dive through the field for 10 s with the frame probe on
omarchy-shell fathom stats      # frame times of the last bench
omarchy-shell fathom captures   # which cards capture and which received a frame
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
bash bin/test              # manifest, logic, Lua bindings, offscreen QML tests,
                           # qmllint, ShellCheck, `omarchy plugin validate`
bash tests/qml/render.sh   # render the field offscreen into screenshots-local/
bash bin/dev-sync          # install and enable the working tree in this session
```

The offscreen QML tests and renders need the Qt 6 `qmltestrunner` (package
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
of omakit's blocks; `DEVELOPMENT.md` says what happens if that ever changes.

## Known limitations

- Windows opened while the field is open join the next switch.
- A scrolling layout's windows parked beside the screen cannot be captured
  live (Hyprland does not render them); they show their last seen frame, or
  their app icon until Fathom has seen them.
- The recency map starts over when the shell restarts (Fathom writes no
  files); it is seeded from Hyprland's focus order.
- Mouse parallax is not built yet.

## License

[MIT](LICENSE)
