#!/bin/bash

# Picks a color with hyprpicker and records it. Service.qml binds this to
# SUPER+PRINT at shell start, replacing Omarchy's default
# `pkill hyprpicker || hyprpicker -a`.

set -o pipefail

HERE=$(dirname "$(readlink -f "$0")")
HISTORY="${COLOR_HISTORY_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/color-history.tsv}"
PLUGIN_ID=io.github.arcanavox.colorhistory

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

# Not `>>`: an ordinary redirection follows a symlink, so anything that plants
# one at this path redirects the append into another of the user's files. The
# helper opens with O_NOFOLLOW and refuses anything that is not a regular file.
python3 "$HERE/safeio.py" append "$HISTORY" "$(date +%s)	$color" || exit 1

# Tell the shell to re-read. Best effort: the history is on disk either way, and
# the panel reloads when it opens.
omarchy-shell -q "$PLUGIN_ID" refresh 2>/dev/null || true
