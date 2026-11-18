#!/bin/bash
# Regenerates the images in docs/ from the running app (demo text only, no personal content).
# Captures just the app's own windows by window ID, never the whole screen.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=/Applications/Dictate.app
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
swiftc -o "$TMP/winid" scripts/window-id.swift

capture() {  # capture <name> <window-title-or-width> <seconds-to-wait> <app args...>
  local out="$1" match="$2" wait="$3"; shift 3
  pkill -f "Dictate --" 2>/dev/null || true
  open -n "$APP" --args "$@"
  sleep "$wait"
  local id; id="$("$TMP/winid" "$match" | head -1)"
  [ -n "$id" ] && screencapture -x -o -l "$id" "docs/$out.png" || echo "no window for $out"
  pkill -f "Dictate --" 2>/dev/null || true
}

capture overlay 480 11 --demo
for tab in general voice filters permissions; do capture "settings-$tab" "Dictate Settings" 6 "--settings=$tab"; done
ls docs
