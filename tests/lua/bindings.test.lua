-- Loads hypr/fathom.lua against a recording mock of Hyprland's `hl` table and
-- checks what it binds, the submap it holds while Alt is down, what the raw
-- key hook forwards, and that a second load in the same Lua state is a no-op.
--
--   lua tests/lua/bindings.test.lua hypr/fathom.lua

local path = arg[1] or "hypr/fathom.lua"

local state = { submap = "", binds = {}, hooks = {}, unbind = {}, dispatch = {}, layer_rule = {}, calls = 0 }

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

local function hook()
  for _, item in ipairs(state.hooks) do
    if item.active then return item.handler end
  end
  return function() end
end

dofile(path)

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
state = { submap = "", binds = {}, hooks = {}, unbind = {}, dispatch = {}, layer_rule = {}, calls = 0 }
api.define_submap = function() error("cannot define") end
dofile(path)
press("ALT + TAB")
check(sent({ "fathom:next" }) and state.submap == "", "without a submap Alt+Tab still opens and holds no submap")

if failures > 0 then
  os.exit(1)
end
