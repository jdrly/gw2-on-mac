#!/bin/bash
# Renders GW2 on Mac's windows headlessly (app/scripts/ui-render.swift: no window is shown, the app
# never activates) into work/app-renders/, with compare-*.png next to the design's exports.
# Uses the built app's Resources (fonts, art): run app/build.sh first.
#
#   app/scripts/ui-render.sh [<out dir>]
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(cd .. && pwd)"
OUT="${1:-$REPO/work/app-renders}"
APP="$PWD/dist/GW2 on Mac.app"
[ -d "$APP" ] || { echo "No $APP; run app/build.sh" >&2; exit 1; }
SPARKLE="$PWD/.cache/sparkle-2.10.0"
BIN="$PWD/.cache/ui-render"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc -parse-as-library -D GW2_RENDER -O -target arm64-apple-macos26.0 -F "$SPARKLE" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$SPARKLE" -o "$BIN" src/native/*.swift scripts/ui-render.swift
mkdir -p "$OUT"
GW2OM_RESOURCES="$APP/Contents/Resources" GW2OM_RENDER=1 "$BIN" "$OUT" "$REPO/docs/design/exports"
