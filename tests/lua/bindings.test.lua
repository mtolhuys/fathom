-- Loads hypr/fathom.lua against a recording mock of Hyprland's `hl` table and
-- checks what it binds, the submap it holds while Alt is down, what the raw
-- key hook forwards, and that a second load in the same Lua state is a no-op.
--
--   lua tests/lua/bindings.test.lua hypr/fathom.lua

local path = arg[1] or "hypr/fathom.lua"

local state = { submap = "", binds = {}, hooks = {}, unbind = {}, dispatch = {}, layer_rule = {} }

local function removable(list, item)
  item.active = true
  item.remove = function(self)
    self.active = false
  end
  table.insert(list, item)
  return item
end

local defining = nil

hl = {
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
    return removable(state.binds, { keys = keys, dispatcher = dispatcher, options = options or {}, submap = defining or "" })
  end,
  define_submap = function(name, body)
    defining = name
    body()
    defining = nil
  end,
  get_current_submap = function() return state.submap end,
  on = function(event, handler)
    return removable(state.hooks, { event = event, handler = handler })
  end,
  dispatch = function(dispatcher)
    table.insert(state.dispatch, dispatcher)
    if dispatcher.kind == "submap" then state.submap = dispatcher.name == "reset" and "" or dispatcher.name end
  end,
  layer_rule = function(rule)
    table.insert(state.layer_rule, rule)
    return rule
  end,
}

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

-- Loading the file a second time in the same Lua state does nothing: no
-- keybind or hook is torn down (that crashed Hyprland 0.56.2) or added twice.
local binds_before, hooks_before, rules_before = #state.binds, #state.hooks, #state.layer_rule
dofile(path)
local removed = 0
for _, item in ipairs(state.binds) do if not item.active then removed = removed + 1 end end
for _, item in ipairs(state.hooks) do if not item.active then removed = removed + 1 end end
check(#state.binds == binds_before and #state.hooks == hooks_before and #state.layer_rule == rules_before
  and removed == 0, "a second load in the same Lua state changes nothing")

-- A fresh Lua state (hyprctl reload) loads it again; a submap Hyprland refuses
-- to define leaves Alt+Tab working without one.
_G.__fathom = nil
state = { submap = "", binds = {}, hooks = {}, unbind = {}, dispatch = {}, layer_rule = {} }
hl.define_submap = function() error("cannot define") end
dofile(path)
press("ALT + TAB")
check(sent({ "fathom:next" }) and state.submap == "", "without a submap Alt+Tab still opens and holds no submap")

if failures > 0 then
  os.exit(1)
end
