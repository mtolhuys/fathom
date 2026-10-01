-- Fathom keybindings for Hyprland 0.56 or newer, configured in Lua.
--
-- Load it from ~/.config/hypr/bindings.lua with the block in README.md, or
-- for the current session only with `bash bin/load-bindings` from Fathom's
-- checkout. Do not load it with a raw `hyprctl eval`: bin/load-bindings is
-- the one way that checks Hyprland before and after.
--
-- It returns true when Fathom holds Alt+Tab, and false when the shell does
-- not have Fathom enabled (then Omarchy's own Alt+Tab, or the caller's
-- fallback, stays in place).
--
-- Loading it twice in one Lua state does nothing the second time. Never
-- tear down what a load set up: removing a keybind from Lua crashed Hyprland
-- 0.56.2 (docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md), and a pcall cannot catch
-- a crash in the compositor. This file keeps no Hyprland object (keybind,
-- hook, rule) in Lua at all, so there is nothing to tear down. To pick up a
-- change, start a fresh Lua state: `hyprctl reload` (bin/load-bindings does it
-- with checks before and after).

if rawget(_G, "__fathom") then
  return true
end

-- Fathom takes Alt+Tab only while the shell has it enabled: `omarchy plugin
-- disable` and `remove` take its entry out of shell.json. Read at every config
-- load; a shell.json that cannot be read counts as enabled.
local function enabled()
  local file = io.open((os.getenv("HOME") or "") .. "/.config/omarchy/shell.json", "r")
  if not file then
    return true
  end
  local text = file:read("a") or ""
  file:close()
  return text:find('"io.github.mtolhuys.fathom"', 1, true) ~= nil
end

if not enabled() then
  return false
end

local fathom = { holding = false, alt = {}, down = {} }
_G.__fathom = fathom

local function send(name)
  hl.dispatch(hl.dsp.global("fathom:" .. name))
end

-- The physical keys that make Alt. The key hook below sees key codes, not what
-- the layout makes of them, and XKB options can move Alt: to the Windows keys,
-- to Ctrl, or turn the right Alt into AltGr. Key codes: 64 and 108 are Alt,
-- 133 and 134 Super, 37 and 105 Control (left and right).
local ALT_MOVED = {
  ["altwin:swap_alt_win"] = { 133, 134 },
  ["altwin:swap_lalt_lwin"] = { 133, 108 },
  ["altwin:swap_ralt_rwin"] = { 64, 134 },
  ["altwin:ctrl_alt_win"] = { 37, 105 },
  ["ctrl:swap_lalt_lctl"] = { 37, 108 },
  ["ctrl:swap_ralt_rctl"] = { 64, 105 },
  ["ctrl:swap_lalt_lctl_lwin"] = { 133, 108 },
}

-- Every physical key the options above can turn into Alt.
local MAY_BE_ALT = { [37] = true, [64] = true, [105] = true, [108] = true, [133] = true, [134] = true }

local function setting(key)
  local ok, value = pcall(hl.get_config, key)
  return ok and type(value) == "string" and value or ""
end

local function alt_keycodes()
  local options = "," .. setting("input.kb_options"):gsub("%s", "") .. ","
  local codes = { 64, 108 }
  -- In the order written: XKB applies options left to right, so when two of
  -- them move Alt the later one wins (pairs() would pick one at random).
  for option in options:gmatch("[^,]+") do
    codes = ALT_MOVED[option] or codes
  end
  local keys = {}
  for _, code in ipairs(codes) do
    keys[code] = true
  end
  if options:find(",altwin:alt_win,", 1, true) then
    keys[133], keys[134] = true, true
  end
  -- A right Alt that types AltGr is not Alt: letting it go must not commit.
  local variant = setting("input.kb_variant")
  if options:find(",lv3:ralt_switch", 1, true) or variant:find("intl", 1, true) or variant:find("altgr", 1, true) then
    keys[108] = nil
  end
  return keys
end

-- The end of a switch, however it ends: Alt let go, or the overlay closing on
-- its own (Escape, a click, the watchdog, or a release only the overlay saw).
-- Leaves the submap in every case, so the user's other shortcuts can never be
-- left held; forwards the release only when Alt was let go. Idempotent.
local function finish(release)
  if not fathom.holding then
    return
  end
  fathom.holding = false
  if hl.get_current_submap() == "fathom" then
    hl.dispatch(hl.dsp.submap("reset"))
  end
  if release then
    send("release")
  end
end

-- Alt+Tab and Alt+Shift+Tab: tell the shell, then hold the keyboard's Alt
-- chords for Fathom until Alt is released.
local function chord(name)
  return function()
    if not fathom.holding then
      fathom.holding = true
      fathom.alt = alt_keycodes()
      -- kb_options can also be set per keyboard (hl.device), which the global
      -- setting above does not show. Whichever of these keys is down as the
      -- chord fires is what makes Alt on the keyboard in use, so its release
      -- commits as well.
      for code in pairs(fathom.down) do
        fathom.alt[code] = true
      end
    end
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
-- This runs for every key event, so outside a switch it stays at one table
-- lookup and one boolean. The hooks are set up before anything that could fail.
hl.on("input.keyboard.key", function(keycode, _, state)
  if MAY_BE_ALT[keycode] then
    fathom.down[keycode] = state ~= 0 or nil
  end
  if state == 0 and fathom.holding and fathom.alt[keycode] then
    finish(true)
  end
end)

hl.on("layer.closed", function(layer)
  if layer and layer.namespace == "fathom" then
    finish(false)
  end
end)

-- Omarchy binds ALT+TAB several times by default (cyclenext and bring_to_top,
-- both directions); unbinding the chords clears all of them.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
bind_chords()

-- The submap is optional: when it cannot be defined, Alt+Tab still works and
-- simply does not hold the other Alt chords. The hooks above are in place
-- either way, so the submap can never be left behind.
fathom.submap = pcall(hl.define_submap, "fathom", bind_chords)

-- Show the field at once instead of fading the layer in, and frost what is
-- behind it. Cosmetic: a Hyprland that renames a field here must not cost
-- the bindings above.
pcall(hl.layer_rule, {
  name = "fathom",
  match = { namespace = "^fathom$" },
  no_anim = true,
  animation = "none",
  blur = true,
  ignore_alpha = 0.3,
})

return true
