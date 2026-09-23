#!/bin/bash
# Renders the field offscreen for design review (tests/qml/render/): the real
# src/ files against the stub Quickshell modules. PNGs land in
# screenshots-local/ (git-ignored). Not part of bin/test.

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
readonly project_root
readonly out="$project_root/screenshots-local"

runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || { echo "qmltestrunner not found (install qt6-declarative)" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src" "$work/tests" "$out"
cp "$project_root"/src/*.qml "$project_root"/src/*.js "$work/src/"
cp "$project_root/tests/qml/FieldSurface.qml" "$work/src/FieldSurface.qml"
sed "s|@OUT@|$out|" "$project_root/tests/qml/render/tst_render.qml" > "$work/tests/tst_render.qml"

QT_QPA_PLATFORM=offscreen "$runner" -import "$project_root/tests/qml/stubs" -input "$work/tests" "$@"
printf 'Renders in %s\n' "$out"
