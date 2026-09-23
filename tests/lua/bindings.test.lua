-- Loads hypr/fathom.lua against a recording mock of Hyprland's `hl` table and
-- checks what it binds and what the raw key hook forwards.
--
--   lua tests/lua/bindings.test.lua hypr/fathom.lua

local path = arg[1] or "hypr/fathom.lua"

local calls = { unbind = {}, bind = {}, on = {}, dispatch = {}, layer_rule = {} }

hl = {
  dsp = {
    global = function(name) return { kind = "global", name = name } end,
  },
  unbind = function(keys) table.insert(calls.unbind, keys) end,
  bind = function(keys, dispatcher, options)
    table.insert(calls.bind, { keys = keys, dispatcher = dispatcher, options = options or {} })
  end,
  on = function(event, handler) table.insert(calls.on, { event = event, handler = handler }) end,
  dispatch = function(dispatcher) table.insert(calls.dispatch, dispatcher) end,
  layer_rule = function(rule) table.insert(calls.layer_rule, rule) end,
}

dofile(path)

local failures = 0
local function check(condition, message)
  if condition then
    print("ok - " .. message)
  else
    failures = failures + 1
    print("not ok - " .. message)
  end
end

check(#calls.unbind == 2 and calls.unbind[1] == "ALT + TAB" and calls.unbind[2] == "ALT + SHIFT + TAB",
  "clears both default Alt-Tab chords")

local binds = {}
for _, bind in ipairs(calls.bind) do binds[bind.keys] = bind end
check(binds["ALT + TAB"] and binds["ALT + TAB"].dispatcher.name == "fathom:next", "ALT+TAB sends fathom:next")
check(binds["ALT + SHIFT + TAB"] and binds["ALT + SHIFT + TAB"].dispatcher.name == "fathom:previous",
  "ALT+SHIFT+TAB sends fathom:previous")
check(binds["ALT + TAB"] and binds["ALT + TAB"].options.repeating == true, "holding Tab keeps diving")

check(#calls.on == 1 and calls.on[1].event == "input.keyboard.key", "registers one raw key hook")
local hook = calls.on[1] and calls.on[1].handler or function() end

local RELEASED, PRESSED = 0, 1
hook(64, 0, PRESSED)
check(#calls.dispatch == 0, "pressing Alt forwards nothing")
hook(23, 0, PRESSED)
hook(23, 0, RELEASED)
check(#calls.dispatch == 0, "Tab press and release forward nothing")
hook(64, 0, RELEASED)
check(#calls.dispatch == 1 and calls.dispatch[1].name == "fathom:release", "releasing Alt_L sends fathom:release")
hook(108, 0, RELEASED)
check(#calls.dispatch == 2 and calls.dispatch[2].name == "fathom:release", "releasing Alt_R sends fathom:release")

check(#calls.layer_rule == 1 and calls.layer_rule[1].match.namespace == "^fathom$"
  and calls.layer_rule[1].no_anim == true, "disables the layer fade for the fathom namespace")

if failures > 0 then
  os.exit(1)
end
