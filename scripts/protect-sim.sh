#!/bin/bash
# Keep the working iPhone sim on screen. NEVER xcodebuild / actool / uninstall.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.0.app/Contents/Developer}"
UDID="${KONUMUM_UDID:-F96AF066-CC44-46B1-8426-26786006AEA4}"
SIMAPP="$DEVELOPER_DIR/Applications/Simulator.app"
PRESERVE="$(cd "$(dirname "$0")/.." && pwd)/.preserve/Lumen.app"

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
open -a "$SIMAPP"
if ! pgrep -f '/Lumen.app/Lumen' >/dev/null; then
  if [ -d "$PRESERVE" ]; then
    xcrun simctl install "$UDID" "$PRESERVE" || true
  fi
  xcrun simctl launch "$UDID" com.lumen.focus || true
fi
osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1 || true
echo "iPhone sim korunuyor: $UDID"
