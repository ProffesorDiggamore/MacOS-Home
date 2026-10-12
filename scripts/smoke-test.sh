#!/usr/bin/env bash
# Launches the built app, checks it stays running, and captures screenshots in a few styles.
# Used by CI; you can run it locally too (it will rearrange your widget styles temporarily).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Home Widgets.app"
DOMAIN="com.github.proffesordiggamore.homewidgets"
OUT="build/screenshots"
mkdir -p "$OUT"

launch() {
  open "$APP"
  sleep "${1:-10}"
  if ! pgrep -x HomeWidgets >/dev/null; then
    echo "✗ HomeWidgets is not running (crashed?)"
    ls -1t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i homewidgets | head -1 | while read -r report; do
      head -80 ~/Library/Logs/DiagnosticReports/"$report"
    done
    exit 1
  fi
}

quit() {
  pkill -x HomeWidgets || true
  sleep 2
}

# 1. First launch: default widgets + the Widget Gallery window.
launch 14
screencapture -x "$OUT/1-first-launch.png"
quit

# 2–5. Relaunch with different looks (saved layout means no gallery window).
shot() {
  local name="$1"; shift
  for setting in "$@"; do
    defaults write "$DOMAIN" ${setting}
  done
  launch 8
  screencapture -x "$OUT/$name.png"
  quit
}

shot 2-glass "style glass" "scheme system"
shot 3-solid-light "style solid" "scheme light"
shot 4-tinted "style tinted" "scheme system" "accent purple"
shot 5-liquid-dark "style liquidGlass" "scheme dark" "accent system"

defaults delete "$DOMAIN" >/dev/null 2>&1 || true
echo "✓ Smoke test passed; screenshots in $OUT"
