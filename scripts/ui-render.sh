#!/bin/bash
# Renders the app's windows headlessly (scripts/ui-render.swift: no window is shown, the app
# never activates) into work/app-renders/, with compare-*.png next to the approved design's
# exports when there are any (DESIGN_EXPORTS, default the development workspace's
# docs/design/exports; the design file is not in this repository).
# Uses the built app's Resources (fonts, art): run ./build.sh first.
#
#   scripts/ui-render.sh [<out dir>]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/work/app-renders}"
DESIGN_EXPORTS="${DESIGN_EXPORTS:-${GW2_ON_MAC_WORKSPACE:-$PWD/../gw2-on-mac}/docs/design/exports}"
APP_FOLDER="$(sed -n 's/^APP_FOLDER="\(.*\)"$/\1/p' src/gw2om.sh)"
[ -n "$APP_FOLDER" ] || { echo "No APP_FOLDER=\"…\" line in src/gw2om.sh" >&2; exit 1; }
APP="$PWD/dist/$APP_FOLDER.app"
[ -d "$APP" ] || { echo "No $APP; run ./build.sh" >&2; exit 1; }
SPARKLE="$PWD/.cache/sparkle-2.10.0"
BIN="$PWD/.cache/ui-render"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc -parse-as-library -D GW2_RENDER -O -target arm64-apple-macos26.0 -F "$SPARKLE" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$SPARKLE" -o "$BIN" src/native/*.swift scripts/ui-render.swift
mkdir -p "$OUT"
exports=(); [ ! -d "$DESIGN_EXPORTS" ] || exports=("$DESIGN_EXPORTS")
GW2OM_RESOURCES="$APP/Contents/Resources" GW2OM_RENDER=1 "$BIN" "$OUT" ${exports[@]+"${exports[@]}"}
