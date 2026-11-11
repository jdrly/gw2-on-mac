#!/bin/bash
# Builds "dist/<the app's name>.app": a small SwiftUI app that sets up Guild Wars 2 on its own Wine
# engine with DXMT (see README.md). Unlike SWTOR on Mac it changes no existing install: it
# creates its own engine and bottle and installs the game into them, through Steam or ArenaNet's
# own installer. The app bundles only its own pieces:
#   Contents/MacOS/GW2onMac            the window, menus, Settings and updates (src/native), arm64
#   Contents/Frameworks/Sparkle.framework  app updates (Sparkle 2, pinned below; off without a feed)
#   Contents/Resources/gw2om.sh        install/status/play/settings/uninstall logic (src/gw2om.sh)
#   Contents/Resources/collect-logs.sh "Collect Logs…" (src/collect-logs.sh)
#   Contents/Resources/session-report.sh  a game session in short (scripts/session-report.sh)
#   Contents/Resources/components/     what gw2om.sh puts into its engine and bottle, staged in
#                                      prebuilt/ by scripts/stage-components.sh from the
#                                      development workspace's builds: dxmt/ (the jdrly/dxmt fork), heat/ (ntdll.so and
#                                      wineserver), winemac/ (winemac.so and its PE sides
#                                      x86_64-windows/, i386-windows/winemac.drv, win32u.so), ui-scale/
#                                      (the interface addon)
#   Contents/Resources/helpers/procpaths  every process's real executable (gw2om.sh's process
#                                      check; src/helpers/procpaths.c)
#   Contents/Resources/helpers/sessionlock  the game session's kernel lock (gw2om.sh's watcher;
#                                      src/helpers/sessionlock.c)
#   Contents/Resources/Fonts/, Art/    the design's typefaces (SIL OFL) and artwork
#   Contents/Resources/Licenses/       licences of the app and everything bundled
# The Wine engine is not bundled: gw2om.sh downloads it at install time from my jdrly/wine-engine
# release, the same file athei built and published before (CrossOver 26.3, the engine SWTOR on
# Mac uses; pinned URL, size and sha256 in src/gw2om.sh). Steam and the game come from Valve or
# ArenaNet.
#
# Built with the macOS 27 SDK (Xcode 27) for macOS 26.0 and later.
#
#   ./build.sh                   build into dist/, ad-hoc signed
#
# Signing for distribution (Developer ID, hardened runtime, notarization) is scripts/release.sh,
# which re-signs a copy of dist/ inside out. GW2_ON_MAC_VERSION=X.Y.Z[-dev.N] sets the version;
# GW2_ON_MAC_FEED_URL and GW2_ON_MAC_ED_PUBLIC_KEY turn updates on; a build without them has them off.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

# GW2_ON_MAC_VERSION overrides the version for test builds.
APP_VERSION=${GW2_ON_MAC_VERSION:-0.2.0-dev.1}

# Development builds: X.Y.Z-dev.N, as SWTOR on Mac's. CFBundleShortVersionString is the version as
# is; CFBundleVersion (what Sparkle compares) is numeric and sorts above the previous release and
# below X.Y.Z: 0.1.1-dev.N -> 0.1.0.(1000+N), 0.2.0-dev.N -> 0.1.9999.(1000+N). Releases:
# CFBundleVersion = the version.
bundle_version() {
  local v=$1 core n x y z
  case "$v" in
    *-dev.*) core=${v%%-*}; n=${v##*-dev.} ;;
    *-*) echo "Unsupported version $v (X.Y.Z or X.Y.Z-dev.N)" >&2; return 1 ;;
    *) echo "$v"; return ;;
  esac
  IFS=. read -r x y z <<<"$core"
  case "$x$y$z$n" in *[!0-9]*|'') echo "Unsupported version $v" >&2; return 1 ;; esac
  if [ "$z" -gt 0 ]; then echo "$x.$y.$((z - 1)).$((1000 + n))"
  elif [ "$y" -gt 0 ]; then echo "$x.$((y - 1)).9999.$((1000 + n))"
  else echo "$((x - 1)).9999.9999.$((1000 + n))"; fi
}
BUNDLE_VERSION=$(bundle_version "$APP_VERSION")
case "$APP_VERSION" in *-*) CHANNEL=dev ;; *) CHANNEL=release ;; esac
APP_AUTHOR="Jan Drlý"
GITHUB_URL=https://github.com/jdrly
REPO_URL=https://github.com/jdrly/gw2-on-mac
MACOS_MIN=26.0
CACHE="$ROOT/.cache"
# The app's name (gw2om.sh has the one definition) and bundle id: the 0.2 development build
# has its own, so it installs next to 0.1.x and keeps its own defaults
APP_NAME="$(sed -n 's/^APP_NAME="\(.*\)"$/\1/p' src/gw2om.sh)"
[ -n "$APP_NAME" ] || { echo "No APP_NAME=\"…\" line in src/gw2om.sh" >&2; exit 1; }
APP_ID=cz.jandrly.gw2onmac.arm64
APP="$ROOT/dist/$APP_NAME.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Pinned dependencies. Bump the version and sha256 together.
SPARKLE_VERSION=2.10.0
SPARKLE_URL=https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c

fetch() { # url sha256 -> prints path of the verified download (from the cache of a SWTOR on Mac
  # checkout next to this one, ../swtor-on-mac, if it has it)
  local url=$1 sha=$2 dir="$CACHE/$2" file sibling
  file="$dir/$(basename "$url")"
  sibling="$ROOT/../swtor-on-mac/.cache/$2/$(basename "$url")"
  if [ ! -f "$file" ]; then
    mkdir -p "$dir"
    if [ -f "$sibling" ]; then
      cp "$sibling" "$file"
    else
      echo "Downloading $url" >&2
      curl -fL --progress-bar -o "$file.part" "$url"
      mv "$file.part" "$file"
    fi
  fi
  echo "$sha  $file" | shasum -a 256 -c --quiet >&2
  echo "$file"
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

sdk="$(xcrun --sdk macosx --show-sdk-version)"
case "$sdk" in 2[7-9]*|[3-9]*) ;; *) echo "Needs the macOS 27 SDK (Xcode 27); found $sdk" >&2; exit 1 ;; esac

# The bundled components (scripts/stage-components.sh), checked against their records and against
# this repo's patches as they are now
P=prebuilt
[ -f "$P/STAGED" ] || { echo "No $P/; run scripts/stage-components.sh" >&2; exit 1; }
for f in dxmt/VERSION dxmt/LICENSE dxmt/COPYING.LIB dxmt/x86_64-unix/winemetal.so \
  heat/ntdll.so heat/wineserver heat/VERSION heat/WINESERVER.txt heat/LICENSE heat/COPYING.LIB \
  winemac/winemac.so winemac/x86_64-windows/winemac.drv winemac/i386-windows/winemac.drv winemac/win32u.so \
  winemac/VERSION winemac/LICENSE winemac/COPYING.LIB \
  ui-scale/version.dll ui-scale/gw2-ui-scale.ini; do
  [ -f "$P/$f" ] || { echo "Missing $P/$f; run scripts/stage-components.sh" >&2; exit 1; }
done
for a in x86_64-windows i386-windows; do for d in d3d11 dxgi d3d10core winemetal; do
  [ -f "$P/dxmt/$a/$d.dll" ] || { echo "Missing $P/dxmt/$a/$d.dll" >&2; exit 1; }
done; done
grep -q "^ntdll.so sha256 $(sha "$P/heat/ntdll.so")" "$P/heat/VERSION" || { echo "$P/heat/ntdll.so does not match its VERSION" >&2; exit 1; }
grep -q "^wineserver sha256 $(sha "$P/heat/wineserver")" "$P/heat/WINESERVER.txt" || { echo "$P/heat/wineserver does not match its record" >&2; exit 1; }
for p in ntdll-heat.patch ntdll-msync-alert-fd.patch; do
  grep -q "patches/$p sha256 $(sha "patches/$p")" "$P/heat/VERSION" ||
    { echo "$P/heat was not built from patches/$p as it is now; rebuild and restage" >&2; exit 1; }
done
for l in winemac.so x86_64-windows/winemac.drv i386-windows/winemac.drv win32u.so; do
  grep -q "sha256 $(sha "$P/winemac/$l")" "$P/winemac/VERSION" || { echo "$P/winemac/$l does not match its VERSION" >&2; exit 1; }
done
WINEMAC_PATCHES="winemac-gw2-launcher.patch winemac-physical-keys.patch winemac-swgl-relative-mouse.patch winemac-swgl-input-thread.patch winemac-swtor-mouse.patch"
for p in $WINEMAC_PATCHES; do
  grep -q "patches/$p sha256 $(sha "patches/$p")" "$P/winemac/VERSION" ||
    { echo "$P/winemac was not built from patches/$p as it is now; rebuild and restage" >&2; exit 1; }
done
grep -aq 'gw2-on-mac ui-scale' "$P/ui-scale/version.dll" || { echo "$P/ui-scale/version.dll is not the addon" >&2; exit 1; }
DXMT_VERSION="$(cat "$P/dxmt/VERSION")"
DXMT_COMMIT="${DXMT_VERSION##*-g}"
# the athei/wine commit the Wine pieces were built from, as their record names it
WINE_COMMIT="$(sed -n 's/^sources: athei\/wine \([0-9a-f]\{40\}\).*/\1/p' "$P/heat/VERSION")"
[ -n "$WINE_COMMIT" ] || { echo "$P/heat/VERSION names no athei/wine commit" >&2; exit 1; }

# Sparkle (app updates, as in SWTOR on Mac): the framework goes into the app, its tools are used
# from here by scripts/release.sh.
SPARKLE="$CACHE/sparkle-$SPARKLE_VERSION"
if [ ! -d "$SPARKLE/Sparkle.framework" ]; then
  sparkle_txz=$(fetch "$SPARKLE_URL" "$SPARKLE_SHA256")
  rm -rf "$SPARKLE.part" && mkdir -p "$SPARKLE.part"
  tar -xJf "$sparkle_txz" -C "$SPARKLE.part"
  rm -rf "$SPARKLE" && mv "$SPARKLE.part" "$SPARKLE"
fi

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
R="$APP/Contents/Resources"
sed -e "s/@NAME@/$APP_NAME/g" -e "s/@BUNDLE_ID@/$APP_ID/g" -e "s/@VERSION@/$APP_VERSION/g" -e "s/@BUILD@/$BUNDLE_VERSION/g" -e "s/@CHANNEL@/$CHANNEL/g" \
  src/Info.plist >"$APP/Contents/Info.plist"
# Updates: off without a feed. GW2_ON_MAC_FEED_URL and GW2_ON_MAC_ED_PUBLIC_KEY (Sparkle's
# EdDSA public key, generate_keys) turn them on for a release build (scripts/release.sh).
if [ -n "${GW2_ON_MAC_FEED_URL:-}" ]; then
  [ -n "${GW2_ON_MAC_ED_PUBLIC_KEY:-}" ] || { echo "GW2_ON_MAC_FEED_URL needs GW2_ON_MAC_ED_PUBLIC_KEY" >&2; exit 1; }
  plutil -replace SUFeedURL -string "$GW2_ON_MAC_FEED_URL" "$APP/Contents/Info.plist"
  plutil -replace SUPublicEDKey -string "$GW2_ON_MAC_ED_PUBLIC_KEY" "$APP/Contents/Info.plist"
  [ "$CHANNEL" != release ] || plutil -replace SUEnableAutomaticChecks -bool YES "$APP/Contents/Info.plist"
fi
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' >"$APP/Contents/PkgInfo"

# Development builds compile their dev-only UI (badge, About line) in with GW2_DEV.
dev_flags=(); [ "$CHANNEL" = release ] || dev_flags=(-D GW2_DEV)
swiftc -parse-as-library -O ${dev_flags[@]+"${dev_flags[@]}"} -target "arm64-apple-macos$MACOS_MIN" -F "$SPARKLE" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/GW2onMac" src/native/*.swift
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/XPCServices" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

install -m 755 src/gw2om.sh "$R/gw2om.sh"
install -m 755 src/collect-logs.sh "$R/collect-logs.sh"
install -m 755 scripts/session-report.sh "$R/session-report.sh"
mkdir -p "$R/Fonts" "$R/Art"
install -m 644 src/fonts/*.ttf "$R/Fonts/"
install -m 644 src/art/* "$R/Art/"

C="$R/components"
mkdir -p "$C"
cp -R "$P/dxmt" "$P/heat" "$P/winemac" "$P/ui-scale" "$C/"
chmod 755 "$C/dxmt/x86_64-unix/winemetal.so" "$C/heat/ntdll.so" "$C/heat/wineserver" "$C/winemac/winemac.so" "$C/winemac/win32u.so"
# The components as staged, before scripts/release.sh signs their Mach-O files: gw2om.sh counts an
# engine file with one of these hashes as this version's too (graphics_state), so an engine set up
# from the same build unsigned (a development install) needs no update
(cd "$C" && find . -type f ! -name INVENTORY | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do
  echo "$(shasum -a 256 "$f" | cut -d' ' -f1)  $f"
done) >"$C/INVENTORY"

# The process lister gw2om.sh tells its own Wine processes by (proc_pidpath)
mkdir -p "$R/helpers"
clang -O2 -arch arm64 -mmacosx-version-min=$MACOS_MIN -o "$R/helpers/procpaths" src/helpers/procpaths.c
# The session's lock (flock on an inherited descriptor: one watcher per game session)
clang -O2 -arch arm64 -mmacosx-version-min=$MACOS_MIN -o "$R/helpers/sessionlock" src/helpers/sessionlock.c

# Licences: the app's own (zlib), the overview of what is bundled and what is downloaded
# (THIRD_PARTY_NOTICES.md), and each component's
L="$R/Licenses"
mkdir -p "$L/dxmt" "$L/wine" "$L/sparkle" "$L/fonts" "$L/lucide"
cp LICENSE "$L/GW2-on-Mac-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$L/THIRD_PARTY_NOTICES.md"
cp "$P/dxmt/LICENSE" "$P/dxmt/COPYING.LIB" "$P/dxmt/VERSION" "$L/dxmt/"
cp "$P/heat/COPYING.LIB" "$P/heat/LICENSE" "$L/wine/"
cp "$P/heat/VERSION" "$L/wine/ntdll-VERSION.txt"
cp "$P/heat/WINESERVER.txt" "$L/wine/wineserver-VERSION.txt"
cp "$P/winemac/VERSION" "$L/wine/winemac-win32u-VERSION.txt"
for p in ntdll-msync-alert-fd.patch ntdll-heat.patch wineserver-msync-unregister.patch $WINEMAC_PATCHES; do
  cp "patches/$p" "$L/wine/"
done
cp "$SPARKLE/LICENSE" "$L/sparkle/LICENSE"
cp src/fonts/*-OFL.txt "$L/fonts/"
cp src/icons/LICENSE.txt "$L/lucide/LICENSE.txt"
cat >"$L/README.txt" <<EOF
$APP_NAME $APP_VERSION - licences

GW2 on Mac's own code (the app, gw2om.sh, collect-logs.sh, session-report.sh, the interface
addon in components/ui-scale): zlib licence, see GW2-on-Mac-LICENSE.txt. What the app bundles and
what it downloads at install time: THIRD_PARTY_NOTICES.md.

components/dxmt: DXMT ($DXMT_VERSION), the jdrly/dxmt fork of 3Shain/dxmt,
https://github.com/jdrly/dxmt/tree/$DXMT_COMMIT: LGPL-2.1-or-later (dxmt/COPYING.LIB, dxmt/LICENSE).
Its complete source is that commit of the fork.

components/heat, components/winemac: Wine's ntdll.so, wineserver, winemac.so and win32u.so
(x86_64 unix sides) and winemac.drv (the Mac driver's x86_64 and i386 PE sides) from the sources of the app's Wine engine (CodeWeavers' CrossOver 26.3 with
athei's patches, athei/wine $WINE_COMMIT), with the patches in wine/ (applied as their records,
wine/*-VERSION.txt, say): LGPL-2.1-or-later, see wine/COPYING.LIB and wine/LICENSE. Their
complete source is https://github.com/athei/wine/tree/$WINE_COMMIT, also as an archive in
https://github.com/jdrly/wine-engine/releases/tag/$(sed -n 's/^ENGINE_NAME=//p' src/gw2om.sh)
(CodeWeavers' CrossOver sources: https://www.codeweavers.com/crossover/source), plus those
patches, which are also in $REPO_URL/tree/v$APP_VERSION/patches. They are configured as the
engine (athei/wine-build's build-wine.sh) and built at the optimisation the records name.

Sparkle $SPARKLE_VERSION (app updates), https://sparkle-project.org: MIT-style licence, see
sparkle/LICENSE.

Fonts/: Cinzel (https://github.com/NDISCOVER/Cinzel), Marcellus (Astigmatic) and Alegreya Sans
(Huerta Tipográfica), from Google Fonts, unmodified: SIL Open Font License 1.1, see fonts/.

Icons: Lucide (lucide-static 0.460.0, https://lucide.dev), drawn from their path data: ISC
licence, see lucide/LICENSE.txt.

Not included in this app: the Wine engine (CodeWeavers' CrossOver 26.3 sources with athei's
patches, Wine 11.0, LGPL-2.1-or-later; built by athei) is downloaded at install time from
https://github.com/jdrly/wine-engine/releases/tag/$(sed -n 's/^ENGINE_NAME=//p' src/gw2om.sh),
with its source.
Steam comes from Valve, Guild Wars 2 from Valve (Steam) or ArenaNet.
EOF

# channel: release, or dev (development build; gw2om.sh and the app read it)
printf 'version=%s\nbuild=%s\nchannel=%s\nauthor=%s\ngithub=%s\nrepo=%s\nfeed=%s\n' "$APP_VERSION" "$BUNDLE_VERSION" \
  "$CHANNEL" "$APP_AUTHOR" "$GITHUB_URL" "$REPO_URL" "$(plutil -extract SUFeedURL raw "$APP/Contents/Info.plist" 2>/dev/null || true)" >"$R/app.properties"
printf 'app %s\ndxmt %s %s\nengine %s\nheat %s wineserver %s\nwinemac %s win32u %s\nui-scale %s\nsparkle %s\nsdk %s\n' \
  "$APP_VERSION" "$DXMT_COMMIT" "$DXMT_VERSION" "$(sed -n 's/^ENGINE_NAME=//p' src/gw2om.sh)" \
  "$(sha "$P/heat/ntdll.so" | cut -c1-12)" "$(sha "$P/heat/wineserver" | cut -c1-12)" \
  "$(sha "$P/winemac/winemac.so" | cut -c1-12)" "$(sha "$P/winemac/win32u.so" | cut -c1-12)" \
  "$(sha "$P/ui-scale/version.dll" | cut -c1-12)" "$SPARKLE_VERSION" "$sdk" >"$R/VERSIONS"

# The Liquid Glass icon from Icon Composer's document (Assets.car, CFBundleIconName), plus the
# .icns actool makes from it (CFBundleIconFile, the fallback). actool needs absolute paths.
icon="$CACHE/AppIcon"
rm -rf "$icon"
mkdir -p "$icon"
xcrun actool "$ROOT/src/AppIcon.icon" --compile "$icon" --platform macosx \
  --minimum-deployment-target "$(plutil -extract LSMinimumSystemVersion raw src/Info.plist)" \
  --app-icon AppIcon --output-partial-info-plist "$icon/partial.plist" >"$icon/actool.txt"
[ -f "$icon/Assets.car" ] && [ -f "$icon/AppIcon.icns" ] || { cat "$icon/actool.txt" >&2; exit 1; }
cp "$icon/Assets.car" "$icon/AppIcon.icns" "$R/"

xattr -cr "$APP"
# Ad-hoc signatures (Developer ID: scripts/release.sh). Sparkle without its XPC services no longer
# matches its own signature (release.sh signs it for real, in the same order).
fw="$APP/Contents/Frameworks/Sparkle.framework"
for f in "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do codesign --force --sign - "$f"; done
codesign --force --sign - "$R/helpers/procpaths"
codesign --force --sign - "$R/helpers/sessionlock"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
