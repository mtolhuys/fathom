#!/bin/bash
# Runs the offscreen QML tests: the real src/ files, with FieldSurface.qml
# swapped for a plain-item host and Quickshell replaced by tests/qml/stubs.

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
readonly project_root

runner=""
for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib/qt6/qmltestrunner "$(command -v qmltestrunner6 || true)"; do
  if [[ -n $candidate && -x $candidate ]]; then
    runner=$candidate
    break
  fi
done
if [[ -z $runner ]]; then
  echo "skip - QML tests (Qt 6 qmltestrunner not found; install qt6-declarative)"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src" "$work/tests"
cp "$project_root"/src/*.qml "$project_root"/src/*.js "$work/src/"
cp "$project_root/tests/qml/FieldSurface.qml" "$work/src/FieldSurface.qml"
cp "$project_root/tests/qml/tst_fathom.qml" "$work/tests/"

QT_QPA_PLATFORM=offscreen "$runner" \
  -import "$project_root/tests/qml/stubs" \
  -input "$work/tests"
