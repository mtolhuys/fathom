-- Loads hypr/fathom.lua against a recording mock of Hyprland's `hl` table and
-- checks what it binds, the submap it holds while Alt is down, what the raw
-- key hook forwards (following XKB options that move Alt), that the overlay
-- closing always leaves the submap, that a disabled Fathom takes nothing, and
-- that a second load in the same Lua state is a no-op.
--
--   lua tests/lua/bindings.test.lua hypr/fathom.lua

local path = arg[1] or "hypr/fathom.lua"

local function fresh()
  return { submap = "", binds = {}, hooks = {}, unbind = {}, dispatch = {}, layer_rule = {}, calls = 0, config = {} }
end
local state = fresh()

-- shell.json as the snippet reads it: nil for a missing file.
local shell_json = '{ "plugins": [ { "id": "io.github.mtolhuys.fathom" } ] }'
local real_open = io.open
io.open = function(file, mode)
  if tostring(file):match("/%.config/omarchy/shell%.json$") then
    if shell_json == nil then return nil end
    local text = shell_json
    return { read = function() return text end, close = function() end }
  end
  return real_open(file, mode)
end

-- Hyprland 0.56.2 crashes (SIGSEGV in keybindRemove) when Lua removes a
-- keybind it created earlier; see docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md.
-- Every object the mock hands out refuses teardown the same hard way, so a
-- snippet that ever tries it fails here instead of on a desktop.
local function crashes(what)
  return function()
    -- Recorded first: a pcall in the snippet may swallow the error, but a
    -- real crash is never swallowed.
    state.teardown = what
    error(what .. " would crash Hyprland 0.56.2 (docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md)", 2)
  end
end

local function object(list, item)
  item.active = true
  item.remove = crashes("remove()")
  item.unbind = crashes("unbind()")
  item.set_enabled = crashes("set_enabled()")
  table.insert(list, item)
  return item
end

local defining = nil

local api = {
  dsp = {
    global = function(name) return { kind = "global", name = name } end,
    submap = function(name) return { kind = "submap", name = name } end,
  },
  unbind = function(keys)
    table.insert(state.unbind, keys)
    for _, bind in ipairs(state.binds) do
      if bind.keys == keys and bind.submap == "" then bind.active = false end
    end
  end,
  bind = function(keys, dispatcher, options)
    return object(state.binds, { keys = keys, dispatcher = dispatcher, options = options or {}, submap = defining or "" })
  end,
  define_submap = function(name, body)
    defining = name
    body()
    defining = nil
  end,
  get_current_submap = function() return state.submap end,
  get_config = function(key) return state.config[key] end,
  on = function(event, handler)
    return object(state.hooks, { event = event, handler = handler })
  end,
  dispatch = function(dispatcher)
    table.insert(state.dispatch, dispatcher)
    if dispatcher.kind == "submap" then state.submap = dispatcher.name == "reset" and "" or dispatcher.name end
  end,
  layer_rule = function(rule)
    return object(state.layer_rule, rule)
  end,
}

-- `hl` counts every call the snippet makes, so a second load can be held to
-- making none at all.
local function counted(table_)
  return setmetatable({}, {
    __index = function(_, key)
      local value = table_[key]
      if type(value) == "function" then
        return function(...)
          state.calls = state.calls + 1
          return value(...)
        end
      elseif type(value) == "table" then
        return counted(value)
      end
      return value
    end,
    __newindex = function(_, key, value) table_[key] = value end,
  })
end
hl = counted(api)

local failures = 0
local function check(condition, message)
  if condition then
    print("ok - " .. message)
  else
    failures = failures + 1
    print("not ok - " .. message)
  end
end

local function active(submap)
  local found = {}
  for _, bind in ipairs(state.binds) do
    if bind.active and bind.submap == submap then found[bind.keys] = bind end
  end
  return found
end

local function count(map)
  local n = 0
  for _ in pairs(map) do n = n + 1 end
  return n
end

local function sent(names)
  local list = {}
  for _, dispatcher in ipairs(state.dispatch) do
    if dispatcher.kind == "global" then table.insert(list, dispatcher.name) end
  end
  return table.concat(list, " ") == table.concat(names, " ")
end

local function press(keys)
  local bind = active(state.submap)[keys]
  if bind then bind.dispatcher() end
  return bind ~= nil
end

local function hook(event)
  for _, item in ipairs(state.hooks) do
    if item.active and item.event == (event or "input.keyboard.key") then return item.handler end
  end
  return function() end
end

check(dofile(path) == true, "a load that binds says so")

check(#state.unbind == 2 and state.unbind[1] == "ALT + TAB" and state.unbind[2] == "ALT + SHIFT + TAB",
  "clears both default Alt-Tab chords")

local default = active("")
check(count(default) == 2 and default["ALT + TAB"] and default["ALT + SHIFT + TAB"], "binds ALT+TAB and ALT+SHIFT+TAB")
check(default["ALT + TAB"].options.repeating == true, "holding Tab keeps diving")

local submap = active("fathom")
check(count(submap) == 2 and submap["ALT + TAB"] and submap["ALT + SHIFT + TAB"],
  "the fathom submap binds only the two chords, so other Alt chords reach the overlay")

local RELEASED, PRESSED = 0, 1
hook()(64, 0, PRESSED)
hook()(64, 0, RELEASED)
check(#state.dispatch == 0, "an Alt tap outside a switch forwards nothing")

press("ALT + TAB")
check(sent({ "fathom:next" }) and state.submap == "fathom", "ALT+TAB sends fathom:next and enters the fathom submap")
local entered = #state.dispatch
press("ALT + TAB")
check(sent({ "fathom:next", "fathom:next" }) and #state.dispatch == entered + 1,
  "a second Tab in the submap sends fathom:next without re-entering it")
press("ALT + SHIFT + TAB")
check(sent({ "fathom:next", "fathom:next", "fathom:previous" }), "ALT+SHIFT+TAB sends fathom:previous")
hook()(23, 0, RELEASED)
check(state.submap == "fathom", "releasing Tab keeps the submap")
hook()(64, 0, RELEASED)
check(sent({ "fathom:next", "fathom:next", "fathom:previous", "fathom:release" }) and state.submap == "",
  "releasing Alt_L leaves the submap and sends fathom:release")

press("ALT + TAB")
hook()(108, 0, RELEASED)
check(state.submap == "" and state.dispatch[#state.dispatch].name == "fathom:release",
  "releasing Alt_R does the same")

check(#state.layer_rule == 1 and state.layer_rule[1].match.namespace == "^fathom$"
  and state.layer_rule[1].no_anim == true and state.layer_rule[1].blur == true,
  "the fathom layer shows at once, over a blurred background")

-- Loading the file a second time in the same Lua state does nothing: not one
-- call into Hyprland, so nothing is torn down (that crashed Hyprland 0.56.2)
-- or added twice.
local calls_before = state.calls
dofile(path)
check(state.calls == calls_before, "a second load in the same Lua state makes no call into Hyprland")
check(rawget(_G, "__fathom") ~= nil and next(_G.__fathom) ~= nil and _G.__fathom.submap ~= nil
  and _G.__fathom.hook == nil and _G.__fathom.binds == nil and _G.__fathom.layer_rule == nil,
  "the snippet keeps no Hyprland object that a later load could tear down")

check(state.teardown == nil, "no load ever tears down a Hyprland object"
  .. (state.teardown and " (it called " .. state.teardown .. ")" or ""))

-- A fresh Lua state (hyprctl reload) loads it again; a submap Hyprland refuses
-- to define leaves Alt+Tab working without one.
_G.__fathom = nil
state = fresh()
local define_submap = api.define_submap
api.define_submap = function() error("cannot define") end
dofile(path)
press("ALT + TAB")
check(sent({ "fathom:next" }) and state.submap == "", "without a submap Alt+Tab still opens and holds no submap")
hook()(64, 0, RELEASED)
check(sent({ "fathom:next", "fathom:release" }), "and releasing Alt still commits")
api.define_submap = define_submap

-- The overlay closing on its own (Escape, a click, the watchdog, a release
-- only the overlay saw) always leaves the submap, and forwards nothing.
local function reload()
  _G.__fathom = nil
  state = fresh()
  return dofile(path)
end
reload()
press("ALT + TAB")
hook("layer.closed")({ namespace = "other" })
check(state.submap == "fathom", "another layer closing changes nothing")
hook("layer.closed")({ namespace = "fathom" })
check(state.submap == "" and sent({ "fathom:next" }), "the overlay closing leaves the submap and forwards nothing")
hook()(64, 0, RELEASED)
check(sent({ "fathom:next" }), "a release after the overlay closed is ignored")
hook()(64, 0, PRESSED)
hook()(64, 0, RELEASED)
check(sent({ "fathom:next" }), "and so is the next Alt tap")

-- XKB options that move Alt move the release with it.
reload()
state.config["input.kb_options"] = "compose:caps, altwin:swap_alt_win"
press("ALT + TAB")
hook()(64, 0, RELEASED)
check(state.submap == "fathom", "with Alt and Super swapped, the physical Alt key (now Super) does not commit")
hook()(133, 0, RELEASED)
check(state.submap == "" and sent({ "fathom:next", "fathom:release" }), "the physical Super key (now Alt) does")
state.config["input.kb_options"] = "ctrl:swap_lalt_lctl"
press("ALT + TAB")
hook()(37, 0, RELEASED)
check(state.submap == "", "with Alt and Ctrl swapped, the physical Ctrl key commits")
state.config["input.kb_options"] = "grp:alts_toggle"
state.config["input.kb_variant"] = "intl"
press("ALT + TAB")
hook()(108, 0, RELEASED)
check(state.submap == "fathom", "on an intl layout, letting go of AltGr does not commit")
hook()(64, 0, RELEASED)
check(state.submap == "", "the left Alt still does")
state.config["input.kb_variant"] = nil
-- Two options that move Alt: the later one wins, as in XKB, every time.
state.config["input.kb_variant"] = nil
for _, pair in ipairs({
  { "altwin:swap_alt_win,ctrl:swap_lalt_lctl", 37, 133 },
  { "ctrl:swap_lalt_lctl,altwin:swap_alt_win", 133, 37 },
}) do
  state.config["input.kb_options"] = pair[1]
  press("ALT + TAB")
  hook()(pair[3], 0, RELEASED)
  check(state.submap == "fathom", pair[1] .. ": the earlier option's key does not commit")
  hook()(pair[2], 0, RELEASED)
  check(state.submap == "", pair[1] .. ": the later option's key does")
end
state.config["input.kb_options"] = { "not a string" }
press("ALT + TAB")
hook()(64, 0, RELEASED)
check(state.submap == "", "odd settings fall back to the Alt keys")

-- kb_options set for one keyboard (hl.device) do not show in the global
-- setting: the key held as the chord fires is the one whose release commits.
state.config["input.kb_options"] = "altwin:swap_alt_win"
hook()(64, 0, PRESSED)
press("ALT + TAB")
hook()(133, 0, RELEASED)
check(state.submap == "", "the keys the global setting names still commit")
hook()(64, 0, RELEASED)
press("ALT + TAB")
hook()(64, 0, RELEASED)
check(state.submap == "fathom", "a key let go before the chord is not held")
hook()(133, 0, RELEASED)
hook()(64, 0, PRESSED)
press("ALT + TAB")
hook()(64, 0, RELEASED)
check(state.submap == "" and state.dispatch[#state.dispatch].name == "fathom:release",
  "on a keyboard of its own without the swap, the Alt key held for the chord commits")
state.config["input.kb_options"] = nil

-- A disabled or removed Fathom takes nothing: Omarchy's Alt+Tab stays.
shell_json = '{ "plugins": [ { "id": "someone.else" } ] }'
check(reload() == false and state.calls == 0 and rawget(_G, "__fathom") == nil,
  "without Fathom in shell.json the snippet makes no call and says so")
shell_json = nil
check(reload() == true and active("")["ALT + TAB"] ~= nil, "a shell.json that cannot be read counts as enabled")

if failures > 0 then
  os.exit(1)
end
