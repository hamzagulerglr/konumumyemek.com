#!/bin/bash
# Copy the running iPhone app binary into .preserve. Do NOT boot, install, launch, or xcodebuild.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.preserve/Lumen.app"
LIVE="$(pgrep -lf '/Lumen.app/Lumen' | sed -n 's#.* \(/.*Lumen\.app\)/Lumen#\1#p' | head -1)"
if [ -z "$LIVE" ] || [ ! -d "$LIVE" ]; then
  echo "Çalışan Lumen.app bulunamadı; mevcut yedek duruyor: $DEST"
  exit 0
fi
mkdir -p "$DEST"
rsync -a "$LIVE/" "$DEST/"
echo "iPhone sim yedeklendi (simctl yok): $DEST"
ls -lh "$DEST/Lumen"
