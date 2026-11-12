#!/bin/bash
# Builds "dist/<the app's name>.app": a small SwiftUI app that sets up Guild Wars 2 on its own Wine
# engine (see README.md). Unlike SWTOR on Mac it changes no existing install: it creates its own
# engine and bottle and installs the game into them, through Steam or ArenaNet's own installer.
# The app bundles only its own pieces:
#   Contents/MacOS/GW2onMac            the window, menus, Settings and updates (src/native), arm64
#   Contents/Frameworks/Sparkle.framework  app updates (Sparkle 2, pinned below; off without a feed)
#   Contents/Resources/gw2om.sh        install/status/play/settings/uninstall logic (src/gw2om.sh)
#   Contents/Resources/collect-logs.sh "Collect Logs…" (src/collect-logs.sh)
#   Contents/Resources/session-report.sh  a game session in short (scripts/session-report.sh)
#   Contents/Resources/components/     dxmt/ (my DXMT fork, jdrly/dxmt, built for the engine),
#                                      which gw2om.sh puts into the engine's DXMT tree, ntdll/ (my
#                                      ntdll.so, jdrly/wine, built for the engine; only if staged)
#                                      and macdrv/ (my Mac driver's winemac.so, the same; only if
#                                      staged), which it puts into the engine next to the engine's
#                                      own, and
#                                      ui-scale/ (the interface addon), which it puts into the game
#                                      folder, staged in prebuilt/ by scripts/stage-components.sh
#   Contents/Resources/helpers/procpaths  every process's real executable (gw2om.sh's process
#                                      check; src/helpers/procpaths.c)
#   Contents/Resources/helpers/sessionlock  the game session's kernel lock (gw2om.sh's watcher;
#                                      src/helpers/sessionlock.c)
#   Contents/Resources/Fonts/, Art/    the design's typefaces (SIL OFL) and artwork
#   Contents/Resources/Licenses/       licences of the app and everything bundled
# The Wine engine is not bundled: gw2om.sh downloads athei's Mach9 release at install time (an arm64
# Wine with FEX and his DXMT build; pinned URL, size and sha256 in src/gw2om.sh) and uses it as it
# ships, but for its DXMT tree, its ntdll.so and its winemac.so (mine, the engine's own kept next
# to each). Steam and the game come from Valve or ArenaNet.
#
# Built with the macOS 27 SDK (Xcode 27) for macOS 26.4 and later (the engine's loader needs it).
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
APP_VERSION=${GW2_ON_MAC_VERSION:-0.2.0-dev.5}

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
MACOS_MIN=26.4
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

# The bundled components (scripts/stage-components.sh): my DXMT fork for the engine and, if staged,
# my ntdll.so and my Mac driver's winemac.so, each checked against the record staging wrote
# (SHA256SUMS: every file, and nothing else), and the interface addon. 0.1.x's Wine builds
# (prebuilt/heat, winemac) aren't used on this line. A build without prebuilt/ntdll or
# prebuilt/macdrv leaves the engine's own file in place.
P=prebuilt
# check_record <dir>: its files are the ones its SHA256SUMS names, with those hashes
check_record() {
  (cd "$1" && shasum -a 256 -c --quiet SHA256SUMS >&2) || { echo "$1 does not match its record (SHA256SUMS); stage it again" >&2; exit 1; }
  [ "$(cd "$1" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort)" = "$(sed 's/^[0-9a-f]*  //' "$1/SHA256SUMS")" ] ||
    { echo "$1 has files its record (SHA256SUMS) doesn't name; stage it again" >&2; exit 1; }
}
[ -f "$P/STAGED" ] || { echo "No $P/; run scripts/stage-components.sh" >&2; exit 1; }
for f in ui-scale/version.dll ui-scale/gw2-ui-scale.ini dxmt/SHA256SUMS dxmt/VERSION dxmt/LICENSE dxmt/COPYING.LIB \
  dxmt/aarch64-unix/winemetal.so; do
  [ -f "$P/$f" ] || { echo "Missing $P/$f; run scripts/stage-components.sh" >&2; exit 1; }
done
for a in aarch64-windows i386-windows; do for d in d3d11 dxgi d3d10core winemetal; do
  [ -f "$P/dxmt/$a/$d.dll" ] || { echo "Missing $P/dxmt/$a/$d.dll; run scripts/stage-components.sh" >&2; exit 1; }
done; done
check_record "$P/dxmt"
DXMT_VERSION="$(head -1 "$P/dxmt/VERSION")"
DXMT_COMMIT="$(printf '%s\n' "$DXMT_VERSION" | grep -oE '[0-9a-f]{7,40}' | tail -1 || true)"
[ -n "$DXMT_COMMIT" ] || { echo "$P/dxmt/VERSION names no commit on its first line ($DXMT_VERSION)" >&2; exit 1; }
grep -aq 'gw2-on-mac ui-scale' "$P/ui-scale/version.dll" || { echo "$P/ui-scale/version.dll is not the addon" >&2; exit 1; }
# My Wine builds, each optional: its VERSION names the fork's commit ("commit: <full sha>").
# wine_build <dir> <file>: "<commit> <the file's sha256>", or nothing without <dir>
wine_build() {
  local f commit
  [ -d "$P/$1" ] || return 0
  for f in "$2" VERSION LICENSE COPYING.LIB SHA256SUMS; do
    [ -f "$P/$1/$f" ] || { echo "Missing $P/$1/$f; run scripts/stage-components.sh" >&2; exit 1; }
  done
  check_record "$P/$1"
  commit="$(sed -n 's/^commit: \([0-9a-f]\{40\}\)$/\1/p' "$P/$1/VERSION")"
  [ -n "$commit" ] || { echo "$P/$1/VERSION names no commit (a line commit: <full sha>)" >&2; exit 1; }
  echo "$commit $(sha "$P/$1/$2")"
}
NTDLL_BUILD="$(wine_build ntdll ntdll.so)"
MACDRV_BUILD="$(wine_build macdrv winemac.so)"
NTDLL_COMMIT="${NTDLL_BUILD%% *}" MACDRV_COMMIT="${MACDRV_BUILD%% *}"
# The engine gw2om.sh downloads, for the licences and VERSIONS
engine_pin() { sed -n "s/^$1=\([^ ]*\).*/\1/p" src/gw2om.sh; }
ENGINE_NAME="$(engine_pin ENGINE_NAME)" ENGINE_URL="$(engine_pin ENGINE_URL)"
[ -n "$ENGINE_NAME" ] && [ -n "$ENGINE_URL" ] || { echo "No ENGINE_NAME or ENGINE_URL in src/gw2om.sh" >&2; exit 1; }

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
cp -R "$P/ui-scale" "$C/"
mkdir -p "$C/dxmt"
(cd "$P/dxmt" && find . -type f ! -name SHA256SUMS | while read -r f; do mkdir -p "$C/dxmt/$(dirname "$f")"; cp "$f" "$C/dxmt/$f"; done)
chmod 644 "$C"/dxmt/*-windows/*.dll "$C"/dxmt/VERSION "$C"/dxmt/LICENSE "$C"/dxmt/COPYING.LIB
chmod 755 "$C/dxmt/aarch64-unix/winemetal.so"
if [ -n "$NTDLL_COMMIT" ]; then
  mkdir -p "$C/ntdll"
  cp "$P/ntdll/ntdll.so" "$P/ntdll/VERSION" "$P/ntdll/LICENSE" "$P/ntdll/COPYING.LIB" "$C/ntdll/"
  chmod 644 "$C/ntdll/VERSION" "$C/ntdll/LICENSE" "$C/ntdll/COPYING.LIB"
  chmod 755 "$C/ntdll/ntdll.so"
fi
if [ -n "$MACDRV_COMMIT" ]; then
  mkdir -p "$C/macdrv"
  cp "$P/macdrv/winemac.so" "$P/macdrv/VERSION" "$P/macdrv/LICENSE" "$P/macdrv/COPYING.LIB" "$C/macdrv/"
  chmod 644 "$C/macdrv/VERSION" "$C/macdrv/LICENSE" "$C/macdrv/COPYING.LIB"
  chmod 755 "$C/macdrv/winemac.so"
fi

# The process lister gw2om.sh tells its own Wine processes by (proc_pidpath)
mkdir -p "$R/helpers"
clang -O2 -arch arm64 -mmacosx-version-min=$MACOS_MIN -o "$R/helpers/procpaths" src/helpers/procpaths.c
# The session's lock (flock on an inherited descriptor: one watcher per game session)
clang -O2 -arch arm64 -mmacosx-version-min=$MACOS_MIN -o "$R/helpers/sessionlock" src/helpers/sessionlock.c

# Licences: the app's own (zlib), the overview of what is bundled and what is downloaded
# (THIRD_PARTY_NOTICES.md), and each component's
L="$R/Licenses"
mkdir -p "$L/dxmt" "$L/sparkle" "$L/fonts" "$L/lucide"
cp LICENSE "$L/GW2-on-Mac-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$L/THIRD_PARTY_NOTICES.md"
cp "$P/dxmt/LICENSE" "$P/dxmt/COPYING.LIB" "$P/dxmt/VERSION" "$L/dxmt/"
NTDLL_NOTE="This build has no ntdll.so of mine: the engine's own stays in place."
if [ -n "$NTDLL_COMMIT" ]; then
  mkdir -p "$L/wine"
  cp "$P/ntdll/LICENSE" "$P/ntdll/COPYING.LIB" "$P/ntdll/VERSION" "$L/wine/"
  NTDLL_NOTE="components/ntdll: ntdll.so, built from my Wine fork jdrly/wine (a fork of athei/wine)
for the engine below, https://github.com/jdrly/wine/tree/$NTDLL_COMMIT: LGPL-2.1-or-later
(wine/COPYING.LIB, wine/LICENSE). Its complete source is that commit of the fork."
fi
MACDRV_NOTE="This build has no winemac.so of mine: the engine's own stays in place."
if [ -n "$MACDRV_COMMIT" ]; then
  mkdir -p "$L/macdrv"
  cp "$P/macdrv/LICENSE" "$P/macdrv/COPYING.LIB" "$P/macdrv/VERSION" "$L/macdrv/"
  MACDRV_NOTE="components/macdrv: winemac.so, Wine's Mac driver, built from my Wine fork jdrly/wine (a fork
of athei/wine) for the engine below, https://github.com/jdrly/wine/tree/$MACDRV_COMMIT:
LGPL-2.1-or-later (macdrv/COPYING.LIB, macdrv/LICENSE). Its complete source is that commit of the
fork."
fi
cp "$SPARKLE/LICENSE" "$L/sparkle/LICENSE"
cp src/fonts/*-OFL.txt "$L/fonts/"
cp src/icons/LICENSE.txt "$L/lucide/LICENSE.txt"
cat >"$L/README.txt" <<EOF
$APP_NAME $APP_VERSION - licences

GW2 on Mac's own code (the app, gw2om.sh, collect-logs.sh, session-report.sh, the interface
addon in components/ui-scale): zlib licence, see GW2-on-Mac-LICENSE.txt. What the app bundles and
what it downloads at install time: THIRD_PARTY_NOTICES.md.

components/dxmt: DXMT ($DXMT_VERSION), the jdrly/dxmt fork of 3Shain/dxmt, built for the
engine below, https://github.com/jdrly/dxmt/tree/$DXMT_COMMIT: LGPL-2.1-or-later (dxmt/COPYING.LIB,
dxmt/LICENSE). Its complete source is that commit of the fork.

$NTDLL_NOTE

$MACDRV_NOTE

Sparkle $SPARKLE_VERSION (app updates), https://sparkle-project.org: MIT-style licence, see
sparkle/LICENSE.

Fonts/: Cinzel (https://github.com/NDISCOVER/Cinzel), Marcellus (Astigmatic) and Alegreya Sans
(Huerta Tipográfica), from Google Fonts, unmodified: SIL Open Font License 1.1, see fonts/.

Icons: Lucide (lucide-static 0.460.0, https://lucide.dev), drawn from their path data: ISC
licence, see lucide/LICENSE.txt.

Not included in this app: the Wine engine, athei's Mach9 ($ENGINE_NAME: Wine with his patches,
FEX, DXMT, Mesa, vkd3d-proton, GStreamer and the rest its release page lists, each under its own
licence), is downloaded at install time from $ENGINE_URL
and used as it ships, but for its DXMT tree, its ntdll.so and its winemac.so: components/dxmt,
components/ntdll and components/macdrv go there, the engine's own next to each. Its sources and
that list: https://github.com/athei/mach9/releases.
Steam comes from Valve, Guild Wars 2 from Valve (Steam) or ArenaNet.
EOF

# channel: release, or dev (development build; gw2om.sh and the app read it)
printf 'version=%s\nbuild=%s\nchannel=%s\nauthor=%s\ngithub=%s\nrepo=%s\nfeed=%s\n' "$APP_VERSION" "$BUNDLE_VERSION" \
  "$CHANNEL" "$APP_AUTHOR" "$GITHUB_URL" "$REPO_URL" "$(plutil -extract SUFeedURL raw "$APP/Contents/Info.plist" 2>/dev/null || true)" >"$R/app.properties"
# (ntdll and macdrv: my ntdll.so's and my winemac.so's commit and sha256 as built, or none)
printf 'app %s\ndxmt %s %s\nntdll %s\nmacdrv %s\nengine %s wine %s fex %s dxmt %s\nui-scale %s\nsparkle %s\nsdk %s\n' \
  "$APP_VERSION" "$DXMT_COMMIT" "$DXMT_VERSION" "${NTDLL_BUILD:-none}" "${MACDRV_BUILD:-none}" \
  "$ENGINE_NAME" "$(engine_pin ENGINE_WINE)" "$(engine_pin ENGINE_FEX)" "$(engine_pin ENGINE_DXMT)" \
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
# Every file's sha256, what scripts/release.sh --adhoc compares the app in its DMG with
scripts/app-files.sh "$APP" >"$ROOT/dist/$APP_NAME.files"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
