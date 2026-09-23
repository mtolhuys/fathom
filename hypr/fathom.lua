-- Fathom keybindings for Hyprland 0.56 or newer, configured in Lua.
--
-- Load it from ~/.config/hypr/bindings.lua (README.md shows a block that also
-- falls back to another switcher while Fathom is not installed), or for the
-- current session only with `bash bin/load-bindings` from Fathom's checkout.
-- Do not load it with a raw `hyprctl eval`: bin/load-bindings is the one way
-- that checks Hyprland before and after.
--
-- Loading it twice in one Lua state does nothing the second time. Never
-- tear down what a load set up: removing a keybind from Lua crashed Hyprland
-- 0.56.2 (docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md), and a pcall cannot catch
-- a crash in the compositor. This file keeps no Hyprland object (keybind,
-- hook, rule) in Lua at all, so there is nothing to tear down. To pick up a
-- change, start a fresh Lua state: `hyprctl reload` (bin/load-bindings does it
-- with checks before and after).

if rawget(_G, "__fathom") then
  return
end

local fathom = {}
_G.__fathom = fathom

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
  hl.bind("ALT + TAB", chord("next"), { description = "Fathom: dive one window deeper", repeating = true })
  hl.bind("ALT + SHIFT + TAB", chord("previous"), { description = "Fathom: rise one window", repeating = true })
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

hl.on("input.keyboard.key", function(keycode, _, state)
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
hl.layer_rule({
  name = "fathom",
  match = { namespace = "^fathom$" },
  no_anim = true,
  animation = "none",
  blur = true,
  ignore_alpha = 0.3,
})
