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
-- Loading it twice in one Lua state does nothing the second time: tearing a
-- keybind or an event hook down from Lua crashed Hyprland 0.56.2 (SIGABRT
-- inside its Lua API). To pick up a change, run `hyprctl reload`, which starts
-- a fresh Lua state.

if rawget(_G, "__fathom") then
  return
end

local fathom = {}
_G.__fathom = fathom
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
    if fathom.submap and hl.get_current_submap() ~= "fathom" then
      hl.dispatch(hl.dsp.submap("fathom"))
    end
  end
end

local function bind_chords()
  remember(hl.bind("ALT + TAB", chord("next"), { description = "Fathom: dive one window deeper", repeating = true }))
  remember(hl.bind("ALT + SHIFT + TAB", chord("previous"), { description = "Fathom: rise one window", repeating = true }))
end

-- Releasing Alt commits the selection. A release bind on a bare modifier only
-- fires when that modifier was tapped on its own, so the raw key stream is
-- read instead (the approach of the altswitch plugin). The release is also
-- seen when Alt is let go before the overlay has keyboard focus.
--
-- 64 is Alt_L and 108 is Alt_R. This runs for every key event, so outside a
-- switch it stays at a table lookup and a string comparison. It is set up
-- before anything that could fail.
local FATHOM_ALT_KEYCODES = { [64] = true, [108] = true }

fathom.hook = hl.on("input.keyboard.key", function(keycode, _, state)
  if state == 0 and FATHOM_ALT_KEYCODES[keycode] and hl.get_current_submap() == "fathom" then
    hl.dispatch(hl.dsp.submap("reset"))
    send("release")
  end
end)

-- Omarchy binds ALT+TAB several times by default (cyclenext and bring_to_top,
-- both directions); unbinding the chords clears all of them.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
bind_chords()

-- The submap is optional: when it cannot be defined, Alt+Tab still works and
-- simply does not hold the other Alt chords. The release hook above is
-- already in place either way, so the submap can never be left behind.
fathom.submap = pcall(hl.define_submap, "fathom", bind_chords)

-- Show the field at once instead of fading the layer in, and frost what is
-- behind it.
fathom.layer_rule = hl.layer_rule({
  name = "fathom",
  match = { namespace = "^fathom$" },
  no_anim = true,
  animation = "none",
  blur = true,
  ignore_alpha = 0.3,
})
