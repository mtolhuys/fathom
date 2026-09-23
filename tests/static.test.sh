#!/bin/bash
# Source rules that follow from Fathom's contract and from omakit's build job
# (skills/omarchy-plugin-build in mtolhuys/omakit): the plugin starts no
# program and keeps no file of its own. If it ever has to, the program goes
# through omakit's Run block and the file through its Store block (added with
# `omakit add run|store .`), never through the primitives listed below.

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly project_root

fail() {
  echo "not ok - $*" >&2
  exit 1
}

# Word-boundary matches on the QML and JS the shell loads.
forbidden='(^|[^A-Za-z])(Process[[:space:]]*\{|execDetached|StdioCollector|SplitParser|FileView|Quickshell\.execDetached)'
if matches=$(grep -nE "$forbidden" "$project_root"/src/*.qml "$project_root"/src/*.js); then
  fail "the plugin must not start programs or keep files directly (use omakit's Run or Store block):
$matches"
fi

# Nothing the shell loads may reach the network.
if matches=$(grep -nE '(XMLHttpRequest|fetch\(|https?://)' "$project_root"/src/*.qml "$project_root"/src/*.js); then
  fail "the plugin must not reach the network:
$matches"
fi

# The Hyprland snippet (docs/HYPRLAND-0.56.2-LUA-RELOAD-CRASH.md): its first
# statement is the load-once guard, it keeps no Hyprland object, and it never
# tears one down. Removing a keybind from Lua crashed Hyprland 0.56.2.
snippet="$project_root/hypr/fathom.lua"
first_code=$(grep -vE '^[[:space:]]*(--|$)' "$snippet" | head -n 1)
[[ $first_code == 'if rawget(_G, "__fathom") then' ]] \
  || fail "hypr/fathom.lua must start with the load-once guard, not: $first_code"
# hl.unbind("KEYS") unbinds by key, once per Lua state; teardown means a
# method on an object Hyprland handed out (bind:remove(), hook:remove(), ...).
if matches=$(grep -nE '(:(remove|unbind|set_enabled)|\.(remove|set_enabled))[[:space:]]*\(' "$snippet"); then
  fail "hypr/fathom.lua must never tear down a Hyprland object (it crashed Hyprland 0.56.2):
$matches"
fi
if matches=$(grep -nE '=[[:space:]]*hl\.(bind|on|layer_rule|window_rule|workspace_rule|timer|define_submap)[[:space:]]*\(' "$snippet"); then
  fail "hypr/fathom.lua must not keep a Hyprland object (nothing to tear down later):
$matches"
fi

# Only bin/load-bindings writes to the running compositor, and it checks
# Hyprland before and after.
writers=$(grep -lE 'hyprctl[^|;&]*[[:space:]](eval|reload|dispatch|keyword|plugin)\b' \
  "$project_root"/bin/* "$project_root"/tests/*.sh "$project_root"/tests/qml/*.sh 2>/dev/null \
  | grep -vE '/(bin/load-bindings|tests/static\.test\.sh)$' || true)
[[ -z $writers ]] || fail "only bin/load-bindings may write to Hyprland (hyprctl eval, reload, dispatch, keyword):
$writers"

echo "ok - static source rules"
