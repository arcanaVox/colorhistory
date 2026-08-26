#!/bin/bash

# Exercises pick.sh against a stubbed hyprpicker. Run: ./test.sh

set -o pipefail

cd "$(dirname "$0")" || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

export COLOR_HISTORY_FILE="$TMP/state/color-history.tsv"
export PATH="$TMP/bin:$PATH"
mkdir -p "$TMP/bin"

# pkill must find nothing, or every run would exit early as a "cancel".
cat >"$TMP/bin/pkill" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$TMP/bin/pkill"

stub_picker() {
  printf '#!/bin/bash\n%s\n' "$1" >"$TMP/bin/hyprpicker"
  chmod +x "$TMP/bin/hyprpicker"
}

failures=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ $expected == "$actual" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "       expected: $(printf '%q' "$expected")"
    echo "       actual:   $(printf '%q' "$actual")"
    failures=$((failures + 1))
  fi
}

colors() { cut -f2 "$COLOR_HISTORY_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }

stub_picker 'echo "#ff0044"'
./pick.sh
check "records a pick, uppercased" "#FF0044" "$(colors)"

stub_picker 'echo ""'
./pick.sh
check "Esc records nothing" "#FF0044" "$(colors)"

stub_picker 'echo "this is not a color"'
./pick.sh
check "garbage records nothing" "#FF0044" "$(colors)"

stub_picker 'echo "some log line"; printf "\033[38;2;34;204;136m#22CC88\033[0m\n"'
./pick.sh
check "extracts the hex out of noisy output" "#FF0044 #22CC88" "$(colors)"

stub_picker 'exit 1'
./pick.sh
check "a failed picker records nothing" "#FF0044 #22CC88" "$(colors)"

stub_picker 'echo "#ff0044"'
./pick.sh
check "a repeat pick appends a second row" "#FF0044 #22CC88 #FF0044" "$(colors)"

check "timestamps are epoch seconds" "3" "$(cut -f1 "$COLOR_HISTORY_FILE" | grep -cE '^1[0-9]{9}$')"
check "unstarred rows have no third column" "0" "$(awk -F'\t' 'NF>2' "$COLOR_HISTORY_FILE" | wc -l)"

cat >"$TMP/bin/pkill" <<'STUB'
#!/bin/bash
exit 0
STUB
./pick.sh
check "a second press cancels instead of picking" "#FF0044 #22CC88 #FF0044" "$(colors)"

if (( failures )); then
  echo "$failures failing"
  exit 1
fi
echo "all pick.sh checks passed"
