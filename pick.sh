#!/bin/bash

# Picks a color with hyprpicker and records it. Service.qml binds this to
# SUPER+PRINT at shell start, replacing Omarchy's default
# `pkill hyprpicker || hyprpicker -a`.

set -o pipefail

HISTORY="${COLOR_HISTORY_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/color-history.tsv}"

# A second press cancels an open picker. The binding this replaces did the same
# thing, and without it SUPER+PRINT would stack a second picker on the first.
pkill hyprpicker && exit 0

# -a keeps autocopy, so the hex still lands on the clipboard exactly as before.
# -b drops the coloured "fancy" output; the grep is the belt to that suspenders,
# pulling the hex out of whatever else hyprpicker decides to print. Cancelling
# with Esc yields no match and therefore no row.
color=$(hyprpicker -a -b 2>/dev/null | grep -oiE '#[0-9a-f]{6}' | tail -n1)
[[ -n $color ]] || exit 0

# The shell parses this file, so nothing unvalidated is written to it. Uppercase
# because the hex string is the identity a color is deduped and starred by.
color=${color^^}
[[ $color =~ ^#[0-9A-F]{6}$ ]] || exit 0

mkdir -p "${HISTORY%/*}" || exit 1

# Append, never rewrite: a sub-4KB append is atomic on Linux, so two picks in
# flight cannot interleave and no lockfile is needed. The shell is the only
# other writer, and it only rewrites while the grid is open — which cannot
# overlap a pick, since hyprpicker owns the screen for the duration.
# ponytail: lost-update race if that ever stops being true; a flock on $HISTORY
# in both writers closes it.
printf '%s\t%s\n' "$(date +%s)" "$color" >>"$HISTORY"
