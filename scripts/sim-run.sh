#!/bin/bash
# Build konumumyemek without actool, install onto the named iPhone sim, launch.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.0.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${KONUMUM_UDID:-F96AF066-CC44-46B1-8426-26786006AEA4}"
APP="$ROOT/.build/ios/Build/Products/Debug-iphonesimulator/Lumen.app"
SIMAPP="$DEVELOPER_DIR/Applications/Simulator.app"

cd "$ROOT"
xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ROOT/.build/ios" \
  EXCLUDED_SOURCE_FILE_NAMES=Assets.xcassets \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  ONLY_ACTIVE_ARCH=YES \
  build

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
open -a "$SIMAPP"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.lumen.focus
echo "konumumyemek launched on $UDID"
