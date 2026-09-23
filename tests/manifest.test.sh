#!/bin/bash
# Checks the manifest invariants Fathom relies on. `omarchy plugin validate`
# is the authority (bin/test runs it when available); this also works on a
# machine without Omarchy.

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly project_root
readonly manifest="$project_root/manifest.json"

fail() {
  echo "not ok - $*" >&2
  exit 1
}

jq -e . "$manifest" >/dev/null || fail "manifest.json is not valid JSON"
jq -e '.schemaVersion == 1' "$manifest" >/dev/null || fail "schemaVersion must be the number 1"
jq -e '.id == "io.github.mtolhuys.fathom"' "$manifest" >/dev/null || fail "unexpected plugin id"
jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$manifest" >/dev/null || fail "version is not semver"
jq -e '.kinds == ["overlay"]' "$manifest" >/dev/null || fail "Fathom is a single overlay plugin"
# The recency tracker and the global shortcuts must live for the whole session.
jq -e '.keepLoaded == true' "$manifest" >/dev/null || fail "keepLoaded must be true"

entry=$(jq -r '.entryPoints.overlay // ""' "$manifest")
[[ -n $entry && $entry != /* && $entry != *..* ]] || fail "entryPoints.overlay must be a safe relative path"
[[ -f $project_root/$entry ]] || fail "entry point $entry does not exist"

link=$(find "$project_root" -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || fail "symlinks are not allowed inside a plugin folder: $link"

# The build identity the IPC reports must match the manifest version.
version=$(jq -r '.version' "$manifest")
grep -q "readonly property string buildIdentity: \"$version-" "$project_root/$entry" \
  || fail "buildIdentity in $entry does not start with $version"

echo "ok - manifest"
