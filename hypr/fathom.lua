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
-- The shell plugin owns all state. This file only forwards three events to it
-- as Hyprland global shortcuts (fathom:next, fathom:previous, fathom:release),
-- which reach the shell in order over one Wayland connection.

-- Omarchy binds ALT+TAB several times by default (cyclenext and bring_to_top,
-- both directions); unbinding the chords clears all of them.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
hl.bind("ALT + TAB", hl.dsp.global("fathom:next"), { description = "Fathom: dive one window deeper", repeating = true })
hl.bind("ALT + SHIFT + TAB", hl.dsp.global("fathom:previous"), { description = "Fathom: rise one window", repeating = true })

-- Releasing ALT commits the selection. A release bind on a bare modifier only
-- fires when that modifier was tapped on its own, so the raw key stream is
-- read instead (the approach of the altswitch plugin). The release is also
-- seen when ALT is let go before the overlay has keyboard focus.
--
-- 64 is Alt_L and 108 is Alt_R. This runs for every key event, so it stays at
-- two comparisons unless ALT itself is released; the shell ignores a release
-- while Fathom is closed.
local FATHOM_ALT_KEYCODES = { [64] = true, [108] = true }

hl.on("input.keyboard.key", function(keycode, _, state)
  if state == 0 and FATHOM_ALT_KEYCODES[keycode] then
    hl.dispatch(hl.dsp.global("fathom:release"))
  end
end)

-- Show the field at once instead of fading the layer in.
hl.layer_rule({ match = { namespace = "^fathom$" }, no_anim = true, animation = "none" })
