#!/bin/bash
# Writes tests/fixtures/xkb-alt-keys.txt: which of the keys that can make Alt
# are Alt (in Mod1) under every XKB option that changes it, alone and in every
# pair, as xkbcli compiles them on the us layout. tests/lua/bindings.test.lua
# holds hypr/fathom.lua's ALT_OPTIONS to it. Run it again when
# xkeyboard-config adds or changes such an option, then follow in ALT_OPTIONS.
#
#   bash tests/fixtures/xkb-alt-keys.sh

set -euo pipefail

fixtures=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly fixtures
readonly rules=/usr/share/X11/xkb/rules/evdev.lst

command -v xkbcli >/dev/null || { echo "xkbcli not found (install libxkbcommon)" >&2; exit 1; }
[[ -r $rules ]] || { echo "$rules not found (install xkeyboard-config)" >&2; exit 1; }

# The Alt keys under the options in $1, comma-separated ("-" for none), out of
# Ctrl (37, 105), Alt (64, 108) and Super (133, 134). Fails when XKB cannot
# compile the options.
alt_keys() {
  local keymap mod1 key keys=()
  keymap=$(xkbcli compile-keymap --layout us --options "$1" 2>/dev/null) || return 1
  mod1=$(grep -E '^[[:space:]]*modifier_map Mod1 ' <<<"$keymap" || true)
  for key in LCTL:37 LALT:64 RCTL:105 RALT:108 LWIN:133 RWIN:134; do
    [[ $mod1 == *"<${key%:*}>"* ]] && keys+=("${key#*:}")
  done
  local IFS=,
  printf '%s\n' "${keys[*]:--}"
}

default=$(alt_keys "")
options=()
while read -r option; do
  found=$(alt_keys "$option") || continue
  [[ $found == "$default" ]] || options+=("$option")
done < <(awk '/^! option/ { f = 1; next } /^!/ { f = 0 } f && $1 ~ /:/ { print $1 }' "$rules")

out="$fixtures/xkb-alt-keys.txt"
{
  printf '# Which keys are Alt under the XKB options that change it, on the us layout:\n'
  printf '# <options> <Alt keycodes>, "-" for none. Written by tests/fixtures/xkb-alt-keys.sh\n'
  printf '# from %s and %s.\n' "$(pacman -Q libxkbcommon 2>/dev/null || echo libxkbcommon)" \
    "$(pacman -Q xkeyboard-config 2>/dev/null || echo xkeyboard-config)"
  printf -- '- %s\n' "$default"
  for option in "${options[@]}"; do
    printf '%s %s\n' "$option" "$(alt_keys "$option")"
  done
  # Each pair once: XKB gives both orders the same result, checked here.
  for ((i = 0; i < ${#options[@]}; i++)); do
    for ((j = i + 1; j < ${#options[@]}; j++)); do
      a=${options[i]}
      b=${options[j]}
      ab=$(alt_keys "$a,$b")
      ba=$(alt_keys "$b,$a")
      [[ $ab == "$ba" ]] || { echo "XKB gives $a,$b and $b,$a different Alt keys: $ab, $ba" >&2; exit 1; }
      printf '%s,%s %s\n' "$a" "$b" "$ab"
    done
  done
} > "$out.new"
mv -- "$out.new" "$out"
printf '%s: %d options, %d lines\n' "$out" "${#options[@]}" "$(grep -vc '^#' "$out")"
