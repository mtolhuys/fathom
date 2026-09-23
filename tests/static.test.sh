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

echo "ok - static source rules"
