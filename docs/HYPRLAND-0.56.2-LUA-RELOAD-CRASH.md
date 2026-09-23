# Hyprland 0.56.2 Lua reload crash

> [!CAUTION]
> Do not restore Fathom's old teardown-and-recreate reload path, and do not
> test a pre-`8f67bae` `fathom.lua` by evaluating it twice in a live Hyprland
> 0.56.2 session. It can take down the compositor and the applications in its
> graphical session.

## Incident

On 2026-09-23 at 22:49:30 CEST, Hyprland 0.56.2 crashed while a development
run loaded the installed Fathom bindings with:

```sh
hyprctl eval 'dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.mtolhuys.fathom/hypr/fathom.lua")'
```

The snippet had already been loaded in the same Hyprland Lua state. Its old
reload path iterated over the objects returned by `hl.bind()` and called
`bind:remove()` inside `pcall`. The second load entered Hyprland's native
`keybindRemove` implementation with an expired keybind object and faulted.
Lua's `pcall` can catch a Lua error; it cannot catch a SIGSEGV in Hyprland's
C++ code.

Hyprland's crash handler reported SIGSEGV and then aborted, so the text crash
report and systemd core use different final signal names. The relevant local
evidence is:

- crash report: `~/.cache/hyprland/hyprlandCrashReport2399.txt`;
- coredump PID: `2399`, command line `Hyprland --watchdog-fd 4`;
- triggering IPC client PID recorded in the core: `1176559`;
- failing source location after symbolization: Hyprland 0.56.2
  `src/config/lua/objects/LuaKeybind.cpp:73`, in `keybindRemove`;
- call path: `keybindRemove` -> Lua `dofile` -> Hyprland `evalRequest`;
- evaluated file: the installed
  `io.github.mtolhuys.fathom/hypr/fathom.lua`.

This was not an out-of-memory event or a GPU reset. Available memory was about
10 GiB and the crashing thread stayed in the Lua keybind removal path.

## Mitigation in Fathom

Commit `8f67bae` made a second load in the same Lua state a no-op:

```lua
if rawget(_G, "__fathom") then
  return
end
```

Do not replace that guard with removal of the previous keybind or hook objects
while Hyprland 0.56.2 is supported. After changing the snippet, start a fresh
Lua state and load it once:

```sh
hyprctl reload
hyprctl eval 'dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.mtolhuys.fathom/hypr/fathom.lua")'
```

If the snippet is loaded persistently from the Hyprland configuration,
`hyprctl reload` performs the fresh load itself; do not follow it with the
manual `eval`.

Upstream Hyprland `main` now locks a weak keybind pointer and returns when it
has expired, but the installed 0.56.2 package does not have that guard. Keep
the Fathom workaround until the installed release is verified to contain the
upstream protection.

## Verification already performed

The fixed installed snippet was evaluated twice consecutively. Both calls
returned `ok`, Hyprland kept PID `1177568`, exactly two default-map and two
`fathom`-submap bindings remained, `hyprctl configerrors` was empty, and no
new Hyprland core or crash report appeared.

The committed source also passed:

- 38 Node logic tests;
- the Lua binding and second-load regression tests;
- 42 QML tests;
- qmllint and ShellCheck;
- `omarchy plugin validate`;
- the omakit marketplace baseline preview.

If a compositor crash leaves the Omarchy shell absent after Hyprland recovers,
restore it with `omarchy restart shell` before continuing live verification.

## Rules for future live work

1. Run `bash bin/test` before installing a development snapshot.
2. Never use a pre-`8f67bae` snippet for live reload testing.
3. Keep at most one manual `dofile` load per fresh Hyprland Lua state.
4. Record the Hyprland PID before a live binding experiment and confirm it is
   unchanged afterward.
5. On an unexpected compositor exit, stop live testing and inspect the core;
   do not immediately repeat the triggering command.

## Guardrails added afterwards

So that no change, person or agent can bring this back:

- `hypr/fathom.lua` keeps no Hyprland object in Lua at all (not the keybinds,
  the key hook or the layer rule), so a later load has nothing it could tear
  down, even by mistake.
- `tests/static.test.sh` fails when the snippet does not start with the
  load-once guard, calls a teardown method (`:remove()`, `:unbind()`,
  `:set_enabled()`), or keeps the result of an `hl.*` constructor; and when any
  script other than `bin/load-bindings` writes to Hyprland.
- The Lua tests' mock records every teardown call before it errors, so a
  teardown inside a `pcall` (exactly the old reload path) still fails the
  test; a second load must make no call into Hyprland at all. Run against the
  snippet from `d19a3ef`, three checks fail and one names `remove()`.
- `bin/load-bindings` is the only way to (re)load the snippet: it refuses an
  unsafe snippet, loads it at most once per Lua state (a persistent setup is
  reloaded with `hyprctl reload`, a fresh state), records Hyprland's PID and
  stops loudly when it changed, and checks `configerrors` and that Alt+Tab is
  Fathom's. `bin/dev-sync` calls it.
- A local Claude Code hook in Fathom's checkout blocks raw `hyprctl eval`,
  `reload`, `dispatch`, `keyword` and `plugin` commands, so an agent cannot
  bypass `bin/load-bindings`.
- `DEVELOPMENT.md` ("Never crash the compositor") makes these rules part of
  the contract, and moves experiments with Hyprland's Lua API to the omakit
  lab.

Verified on the device after these guardrails (HEAD `44b459e`): the persistent
block in `bindings.lua` loaded the snippet on Hyprland's config reload, and
`bash bin/dev-sync` followed by `bin/load-bindings --fresh` reloaded it once
more; Hyprland kept PID 2530, `configerrors` stayed empty, and Alt+Tab is
Fathom's.

