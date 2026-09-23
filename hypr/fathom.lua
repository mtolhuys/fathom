-- Fathom keybindings for Hyprland 0.56 or newer, configured in Lua.
--
-- Persistent: add this line to ~/.config/hypr/bindings.lua, then `hyprctl reload`:
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.mtolhuys.fathom/hypr/fathom.lua")
--
-- Temporary, until the next reload (handy while developing):
--
--   hyprctl eval 'dofile(os.getenv("HOME") .. "/Projects/plugins/fathom/hypr/fathom.lua")'
--
-- Loading it again replaces what the previous load set up.
--
-- The shell plugin owns all state. This file forwards three events to it as
-- Hyprland global shortcuts (fathom:next, fathom:previous, fathom:release),
-- which reach the shell in order over one Wayland connection.
--
-- While Alt is held after Alt+Tab, Hyprland is in a `fathom` submap where only
-- Fathom's two chords are bound. Every other Alt chord (Alt+Left, Alt+Up,
-- Alt+1, Alt+letters) then reaches the overlay, which uses them to move
-- through the field, instead of whatever that chord does elsewhere (Omarchy's
-- text navigation, another switcher). Releasing Alt leaves the submap.

local fathom = rawget(_G, "__fathom") or {}
_G.__fathom = fathom

-- A second load first removes what the first one added.
for _, bind in ipairs(fathom.binds or {}) do
  pcall(function() bind:remove() end)
end
if fathom.hook then
  pcall(function() fathom.hook:remove() end)
end
fathom.binds = {}

local function remember(bind)
  table.insert(fathom.binds, bind)
  return bind
end

local function send(name)
  hl.dispatch(hl.dsp.global("fathom:" .. name))
end

-- Alt+Tab and Alt+Shift+Tab: tell the shell, then hold the keyboard's Alt
-- chords for Fathom until Alt is released.
local function chord(name)
  return function()
    send(name)
    if hl.get_current_submap() ~= "fathom" then
      hl.dispatch(hl.dsp.submap("fathom"))
    end
  end
end

local function bind_chords()
  remember(hl.bind("ALT + TAB", chord("next"), { description = "Fathom: dive one window deeper", repeating = true }))
  remember(hl.bind("ALT + SHIFT + TAB", chord("previous"), { description = "Fathom: rise one window", repeating = true }))
end

-- Omarchy binds ALT+TAB several times by default (cyclenext and bring_to_top,
-- both directions); unbinding the chords clears all of them.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
bind_chords()
hl.define_submap("fathom", bind_chords)

-- Releasing Alt commits the selection. A release bind on a bare modifier only
-- fires when that modifier was tapped on its own, so the raw key stream is
-- read instead (the approach of the altswitch plugin). The release is also
-- seen when Alt is let go before the overlay has keyboard focus.
--
-- 64 is Alt_L and 108 is Alt_R. This runs for every key event, so outside a
-- switch it stays at a table lookup and a string comparison.
local FATHOM_ALT_KEYCODES = { [64] = true, [108] = true }

fathom.hook = hl.on("input.keyboard.key", function(keycode, _, state)
  if state == 0 and FATHOM_ALT_KEYCODES[keycode] and hl.get_current_submap() == "fathom" then
    hl.dispatch(hl.dsp.submap("reset"))
    send("release")
  end
end)

-- Show the field at once instead of fading the layer in, and frost what is
-- behind it. Created once per session: a layer rule cannot be removed.
if not fathom.layer_rule then
  fathom.layer_rule = hl.layer_rule({
    name = "fathom",
    match = { namespace = "^fathom$" },
    no_anim = true,
    animation = "none",
    blur = true,
    ignore_alpha = 0.3,
  })
end
