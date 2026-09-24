# Changelog

## 0.2.1 (2026-09-25)

- The `Alt` release also follows `kb_options` set per keyboard (`hl.device`),
  which the global setting does not show: the key held as the chord fires is
  the one whose release commits, whatever that keyboard's options say. Found
  and fixed by nixfred (#1).
- A sideways fling crosses as many workspaces as it is worth, the way a dive
  of several windows already did, and a chord always arms the watchdog when it
  switches to hold mode, also over a filter that matches nothing. By nixfred
  (#2).
- Main stays frozen while a marketplace submission is open:
  `bin/submission-guard`, installed as the pre-push hook, refuses a push to
  main while a submission or an update request for the listed plugin is open
  (`FATHOM_PUSH_DURING_REVIEW=1` lets a fix the review asks for through), and
  `bash bin/revalidate` then renders the submission's issue body
  again by omakit's retry edit protocol and, with `--edit`, watches until the
  marketplace has validated the new commit.

## 0.2.0 (2026-09-24)

Phase 1: the product.

- Every window is a card of the monitor's shape with its icon, title and age;
  the stack steps back evenly so every window stays readable. Age shows as fog
  (the brief's `depth * 0.08`), no longer as shrinking and fading.
- A map of every workspace, scratchpads included: a minimap per workspace with
  its windows at their real positions and app icons, what is on screen, the
  focused and urgent windows, and what a scrolling layout parks beside the
  screen.
- Arrows (up and down dive, left and right change workspace), Home, End,
  PageUp, PageDown, digits for a workspace, type to filter, Space to keep the
  field open, the wheel and the touchpad; clicks on cards, the caption and the
  map.
- The bindings hold a `fathom` submap while Alt is down, so the user's own Alt
  chords do not swallow Fathom's keys, and can be loaded twice. The overlay's
  background is blurred.
- A quick Alt+Tab no longer draws the overlay; the focus request goes out as
  soon as Hyprland gives focus back; windows that close mid-switch leave the
  field; ages seeded at startup read "earlier"; text follows Omarchy's text
  size.
- The sounding line: a depth gauge in fathoms beside the stack, a dot per
  window, the sounding lead at the selection; click or drag it to pick a
  window by time. The light fades as you dive; the caption reads the depth.
- Windows Hyprland cannot render (parked beside the screen by a scrolling
  layout) show the last frame Fathom saw of them, kept in memory only, or say
  they are off screen.
- Light themes: every color is derived from the theme's foreground,
  background, accent and urgent (`src/Palette.js`) and follows a theme switch
  live. A light theme gets paper cards above a pale veil, a white light from
  the surface and a haze instead of dark fog. Text tiers are mixed from the
  theme's own text and background and held to contrast floors in all 22
  Omarchy themes, also over a busy desktop; a theme's `muted` (pale on light
  themes, nearly the background on some dark ones) is no longer used for
  text, and an accent too faint to read is deepened. The veil is denser, so a
  bright page behind a dark theme (or a dark game behind a light one) no
  longer shows through the text.
- The map shows the last frame seen of each window, reusing the cards'
  snapshots (no capture of its own), and titles where the tiles have room. The
  window you were on keeps a frame too.
- App icons load only while shown, decoded at a few fixed sizes so a moving
  card never reloads its icon. Map tiles fade from icon to frame when the
  first frame is kept, and only a tile with a frame pays for a rounded clip.
- Other people's keyboards and setups: the `Alt` release follows XKB options
  that move `Alt` (to the Windows or Ctrl keys) and ignores an `AltGr`; it
  works without the submap too; and the overlay closing for any reason always
  leaves the submap, so no shortcut can be left held. The snippet binds
  nothing while Fathom is not enabled, returns whether it took `Alt`+`Tab`
  (for a fallback switcher), and cannot stop the rest of a config from
  loading. The README covers installing from GitHub, updating, removing, a
  `hyprland.conf`, and troubleshooting, and states the real minimums.
- The artwork (marketplace preview, README banner, demo) is rendered from the
  plugin's own QML by `bin/make-art`.
- `bin/dev-sync` stamps each install with the working tree's identity and
  waits for exactly that build to answer; `bin/dev-status` (read-only) says
  whether the running Fathom is the working tree.
- `tests/qml/render.sh` renders the field offscreen for design review, in
  dark and light themes, over a stand-in desktop.
- Never crash the compositor: the snippet loads once per Lua state and keeps
  no Hyprland object; `bin/load-bindings` is the one way to load it into a
  running Hyprland (checks before and after, stops if Hyprland's PID
  changed), and `bin/dev-sync` uses it so a changed snippet always takes
  effect. See docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md.

## 0.1.0 (not released)

Phase 0.

- Overlay on Alt+Tab with live thumbnails of every window on every regular
  workspace, on the focused monitor.
- Depth from focus recency, applied to scale and opacity; recency from the
  Hyprland socket2 stream, seeded from Hyprland's client list through
  Quickshell; the plugin starts no program.
- Tab and Shift+Tab move the camera, Alt release focuses, Escape cancels.
- IPC for state, field, captures, a frame-time bench and its statistics.
