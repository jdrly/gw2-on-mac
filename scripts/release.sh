#!/bin/bash
# Signs, notarizes and packages the app in dist/ (run ./build.sh first), and prepares the
# update feed for Sparkle (src/native/Updates.swift): SWTOR on Mac's release script, as is, for
# this app (paths below are relative to the repository root).
#
# Releases go out from here. 0.1.0 and 0.1.1 are published, with their feed. As a safety stop,
# every mode that creates or changes a GitHub release (the default, --ci, --dev, --adhoc, --feed) stops
# unless GW2_ON_MAC_PUBLISH=1. A feed needs an app built with GW2_ON_MAC_FEED_URL and GW2_ON_MAC_ED_PUBLIC_KEY (./build.sh
# puts them into Info.plist's SUFeedURL and SUPublicEDKey; without them Sparkle stays off).
#
#   release/<version>/<name>.app                       Developer ID, hardened runtime (<name>: the
#                                                       app's name; <Name>: the same with dashes)
#   release/<version>/<Name>-<version>.dmg             signed, notarized, stapled
#   release/<version>/<Name>-<version>-from-<old>.delta delta updates from older versions
#   release/<version>/appcast.xml                       the feed, with only this version
#   release/updates/                                    DMGs of this and the 5 previous versions
# then creates a draft GitHub release v<version> with the DMG, the deltas and appcast.xml, its tag
# on the commit the app was built from: HEAD, as build.sh recorded it in dist/<name>.commit, with no
# changes, and on origin/arm64 (RELEASE_BRANCH).
# Publishing the draft makes the update live: the app reads
# https://github.com/jdrly/gw2-on-mac/releases/latest/download/appcast.xml.
#
# One notarization: submitting the disk image notarizes the app inside it too (Gatekeeper
# looks its ticket up online when the app is first opened); the ticket is stapled to the DMG.
#
# Needs the Developer ID Application identity in the keychain, a notarytool keychain profile
# (default swgl-notary: my App Store Connect API key, the same team as SWGL on Mac and SWTOR on Mac;
# xcrun notarytool store-credentials <name> --key … --key-id … --issuer …), Sparkle's EdDSA
# key in the login keychain (Sparkle's generate_keys, the same key as SWGL on Mac; build.sh
# unpacks the tools into .cache/sparkle-<version>/bin), gh logged in, and release notes in
# Markdown at release-notes/<version>.md (they go into the appcast and the GitHub release).
#
#   scripts/release.sh               sign, notarize, package, feed, draft release
#   scripts/release.sh --sign-only   sign and verify only (for testing the signed app locally)
#   scripts/release.sh --no-notarize sign, package and build the feed, without notarizing or a
#                                    GitHub release (local dry runs and update tests)
#   scripts/release.sh --no-release  sign, notarize, staple and build the feed, without a GitHub
#                                    release (before the repository exists, or to look first)
#   scripts/release.sh --dev         development builds (version X.Y.Z-dev.N, build.sh) and release
#                                    candidates (X.Y.Z-rc.N), published the same way: sign,
#                                    notarize and staple the DMG, then a GitHub pre-release with
#                                    the DMG only. No feed: releases/latest (the appcast every
#                                    install reads) stays on the last release.
#   scripts/release.sh --dev --no-release   the same without the pre-release
#   scripts/release.sh --adhoc       development builds and release candidates from GitHub's
#                                    runners (.github/workflows/devbuild.yml), without my
#                                    Developer ID: the app as build.sh
#                                    signed it (ad hoc, verified, never re-signed), an unsigned DMG,
#                                    no notarization, then a GitHub pre-release with the DMG and the
#                                    build's record. The version may not be lower than build.sh's
#                                    DEV_VERSION.
#                                    The app in the DMG must match the file list build.sh wrote
#                                    (APP_FILES, default dist/<name>.files). BUILD_RECORD is the
#                                    workflow's record of the build; the DMG's sha256 is added to it.
#                                    DXMT_COMMIT, if set, must be the commit the bundled DXMT names,
#                                    WINE_COMMIT and MACDRV_COMMIT, if set, the commit the
#                                    bundled ntdll.so's and winemac.so's VERSION names, with the
#                                    file's sha256 (and win32u.so's when that VERSION names one),
#                                    FEX_COMMIT, if set, the commit my bundled
#                                    FEX's VERSION names, with its DLL's sha256, and KK_COMMIT,
#                                    if set, the commit my bundled KosmicKrisp's VERSION names,
#                                    with its dylib's sha256.
#   scripts/release.sh --adhoc --no-release the same without the pre-release
#   scripts/release.sh --feed-min <appcast.xml>  only what the feed's build does to its item's
#                                    minimum macOS, on that file (the Checks workflow runs it on
#                                    fixture feeds)
#
# Releases from GitHub Actions (SWTOR on Mac's .github/workflows/release.yml; this repository has no
# workflow yet) come in two halves, so
# Sparkle's EdDSA key never leaves my Mac:
#   scripts/release.sh --ci          (CI) sign, package, notarize, and create the draft release
#                                    with the DMG only
#   scripts/release.sh --ci-dry-run  (CI) the same without a release (the workflow keeps the DMG
#                                    as a short-lived artifact)
#   scripts/release.sh --feed <ver>  (Mac) download the notarized DMG from the draft release,
#                                    build and check the feed, and upload appcast.xml and the
#                                    deltas to the draft
#
# Overrides: RELEASE_BRANCH (default arm64), IDENTITY, NOTARY_PROFILE, or NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER (an App Store
# Connect API key file instead of the keychain profile, as in CI); RELEASE_DIR (default
# release), DOWNLOAD_URL_PREFIX (where the appcast points, default the version's GitHub
# release), ED_KEY_FILE (a private EdDSA key file instead of the keychain, for test keys),
# RELEASE_NOTES (the notes file).
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"
# Only the argument lists the header names, before the publish guard, so an extra argument can't
# take a publishing mode past it (#300)
case "$MODE" in
  "") if [ $# != 0 ]; then echo "unknown option: ''" >&2; exit 2; fi ;;
  --sign-only|--no-notarize|--no-release|--ci|--ci-dry-run)
    if [ $# -gt 1 ]; then echo "unknown option: $2" >&2; exit 2; fi ;;
  --dev|--adhoc)
    if [ $# -gt 2 ] || { [ $# = 2 ] && [ "$2" != --no-release ]; }; then
      echo "usage: $0 $MODE [--no-release]" >&2; exit 2
    fi ;;
  --feed) if [ $# != 2 ] || [ -z "$2" ]; then echo "usage: $0 --feed <version>" >&2; exit 2; fi ;;
  --feed-min) if [ $# != 2 ] || [ -z "$2" ]; then echo "usage: $0 --feed-min <appcast.xml>" >&2; exit 2; fi ;;
  *) echo "unknown option: $MODE" >&2; exit 2 ;;
esac
# (see the header: these modes need GW2_ON_MAC_PUBLISH=1)
case "$MODE:${2:-}" in
  :|--ci:|--dev:|--adhoc:|--feed:*)
    [ "${GW2_ON_MAC_PUBLISH:-}" = 1 ] || {
      echo "This mode creates or changes a GitHub release. Set GW2_ON_MAC_PUBLISH=1 to publish, or use --sign-only, --no-notarize or --no-release." >&2
      exit 1; } ;;
esac
DEV_NO_RELEASE=""
if { [ "$MODE" = --dev ] || [ "$MODE" = --adhoc ]; } && [ "${2:-}" = --no-release ]; then DEV_NO_RELEASE=1; fi
IDENTITY="${IDENTITY:-Developer ID Application: Jan Drly (3JT82CY6ZK)}"
PROFILE="${NOTARY_PROFILE:-swgl-notary}"
REPO=jdrly/gw2-on-mac
# The app's name and file name (src/gw2om.sh's APP_NAME), and as GitHub's asset names have it:
# 0.1.x's, so the DMG and the deltas go on from GW2-on-Mac-<version>.dmg (ADR 0018).
APP_NAME="$(sed -n 's/^APP_NAME="\(.*\)"$/\1/p' src/gw2om.sh)"
[ -n "$APP_NAME" ] || { echo "No APP_NAME=\"…\" line in src/gw2om.sh" >&2; exit 1; }
# The macOS the engine needs (src/gw2om.sh's MACOS_MIN). The feed's item names it, so Sparkle on an
# older macOS doesn't offer the update. It isn't the app's LSMinimumSystemVersion, the macOS the app
# opens on, which generate_appcast writes into the item: 0.2 is to open on macOS 26.0 and say there
# why it can't run (#295).
MACOS_MIN="$(sed -n 's/^MACOS_MIN=\([0-9][0-9.]*\)$/\1/p' src/gw2om.sh)"
[ -n "$MACOS_MIN" ] || { echo "No MACOS_MIN=… line in src/gw2om.sh" >&2; exit 1; }
feed_min() { # <appcast.xml>: its one item gets sparkle:minimumSystemVersion $MACOS_MIN, or the release
  # stops. A feed that already says it is left as it is, byte for byte. (The appcast is not signed.)
  # The edit stops at the item's description, so release notes that quote the element keep it.
  local f=$1 min="/rss/channel/item/*[local-name()='minimumSystemVersion' and namespace-uri()='http://www.andymatuschak.org/xml-namespaces/sparkle']"
  [ "$(xmllint --xpath 'count(/rss/channel/item)' "$f")" = 1 ] || { echo "$f doesn't have exactly one item" >&2; exit 1; }
  if [ "$(xmllint --xpath "string($min)" "$f")" != "$MACOS_MIN" ]; then
    sed "1,/<description/s|<sparkle:minimumSystemVersion>[^<]*</sparkle:minimumSystemVersion>|<sparkle:minimumSystemVersion>$MACOS_MIN</sparkle:minimumSystemVersion>|" "$f" >"$f.tmp"
    mv "$f.tmp" "$f"
  fi
  [ "$(xmllint --xpath "count($min)" "$f")" = 1 ] && [ "$(xmllint --xpath "string($min)" "$f")" = "$MACOS_MIN" ] ||
    { echo "$f's item doesn't say sparkle:minimumSystemVersion $MACOS_MIN (src/gw2om.sh's MACOS_MIN)" >&2; exit 1; }
}
if [ "$MODE" = --feed-min ]; then
  feed_min "$2"
  echo "[release] $2's item says sparkle:minimumSystemVersion $MACOS_MIN"
  exit 0
fi
DASHED="${APP_NAME// /-}"
SRC="dist/$APP_NAME.app"
ENT="$PWD/src/entitlements"
if [ "$MODE" = --feed ]; then
  VERSION="$2"
else
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$SRC/Contents/Info.plist")"
fi
# Development builds and release candidates never go into a feed or a regular release, and releases
# are never either. A release candidate is a pre-release as a development build is; only its name
# differs (KIND, in the release's title).
case "$VERSION:$MODE" in
  *-dev.*:--dev|*-dev.*:--adhoc|*-dev.*:--sign-only|*-rc.*:--dev|*-rc.*:--adhoc|*-rc.*:--sign-only) ;;
  *-*:*) echo "$VERSION is a development build or release candidate: use --dev (or --sign-only)" >&2; exit 1 ;;
  *:--dev|*:--adhoc) echo "$VERSION is not a development build (X.Y.Z-dev.N) or release candidate (X.Y.Z-rc.N)" >&2; exit 1 ;;
esac
case "$VERSION" in *-rc.*) KIND="release candidate" ;; *) KIND="development build" ;; esac
APP_ID="$(sed -n 's/^APP_ID=//p' build.sh)"
if [ "$MODE" = --adhoc ]; then
  # Never below build.sh's DEV_VERSION, so a dev number isn't used twice (sort -V puts X.Y.Z-dev.N
  # before X.Y.Z-rc.N)
  base="$(sed -n 's/^DEV_VERSION=//p' build.sh)"
  [ -n "$base" ] && [ -n "$APP_ID" ] || { echo "No DEV_VERSION or APP_ID line in build.sh" >&2; exit 1; }
  [ "$(printf '%s\n' "$base" "$VERSION" | sort -V | head -1)" = "$base" ] ||
    { echo "$VERSION is lower than build.sh's DEV_VERSION $base" >&2; exit 1; }
  APP_FILES="${APP_FILES:-dist/$APP_NAME.files}"
  [ -f "$APP_FILES" ] || { echo "Missing $APP_FILES, the file list build.sh writes" >&2; exit 1; }
  [ -f "${BUILD_RECORD:-}" ] || { echo "Missing BUILD_RECORD, the build's record" >&2; exit 1; }
fi
RELEASE_DIR="${RELEASE_DIR:-release}"
OUT="$RELEASE_DIR/$VERSION"
UPDATES="$RELEASE_DIR/updates"
APP="$OUT/$APP_NAME.app"
DMG="$OUT/$DASHED-$VERSION.dmg"
NOTES="${RELEASE_NOTES:-release-notes/$VERSION.md}"
URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"
FW_REL="Contents/Frameworks/Sparkle.framework"
SPARKLE_BIN="$PWD/.cache/sparkle-$(sed -n 's/^SPARKLE_VERSION=//p' build.sh)/bin"
if [ -n "${NOTARY_KEY:-}" ]; then
  notary_auth=(--key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER:?}")
else
  notary_auth=(--keychain-profile "$PROFILE")
fi

case "$MODE" in
  ""|--no-notarize|--no-release|--feed)
    [ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Missing $SPARKLE_BIN; run ./build.sh" >&2; exit 1; }
    [ -n "$(plutil -extract SUPublicEDKey raw "$SRC/Contents/Info.plist" 2>/dev/null || true)" ] &&
      [ -n "$(plutil -extract SUFeedURL raw "$SRC/Contents/Info.plist" 2>/dev/null || true)" ] ||
      { echo "Updates are off in this build (no SUFeedURL or SUPublicEDKey): build with GW2_ON_MAC_FEED_URL and GW2_ON_MAC_ED_PUBLIC_KEY for a feed, or use --sign-only" >&2; exit 1; } ;;
esac
if [ "$MODE" != --sign-only ] && [ "$MODE" != --ci-dry-run ]; then
  if [ ! -f "$NOTES" ]; then
    [ "$MODE" = --no-notarize ] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
    echo "[release] note: no release notes ($NOTES)"
  fi
fi
case "$MODE$DEV_NO_RELEASE" in
  ""|--ci|--dev|--adhoc)
    gh auth status >/dev/null 2>&1 || { echo "gh is not logged in" >&2; exit 1; }
    ! gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 || { echo "Release v$VERSION already exists" >&2; exit 1; }
    if [ -z "$MODE" ]; then
      # The release's tag goes on the commit the app in dist/ was built from (build.sh's record), not
      # on the default branch main, which is 0.1.x. That is HEAD, with no changes, and it is on
      # origin's RELEASE_BRANCH (default arm64, the 0.2 line). Checked before signing.
      head=$(git rev-parse HEAD)
      built="$(cat "dist/$APP_NAME.commit" 2>/dev/null || true)"
      [ "$built" = "$head" ] ||
        { echo "The app in dist/ wasn't built from HEAD $head as committed (dist/$APP_NAME.commit: ${built:-missing}); commit or remove what git status shows, then run ./build.sh again" >&2; exit 1; }
      git merge-base --is-ancestor "$head" "origin/${RELEASE_BRANCH:-arm64}" ||
        { echo "$head is not on origin/${RELEASE_BRANCH:-arm64}: push it there first (git fetch if it is)" >&2; exit 1; }
    fi
    if [ "$MODE" = --adhoc ] || [ -z "$MODE" ]; then
      # A tag without a release would become this release's tag, on another commit
      if out="$(gh api "repos/$REPO/git/ref/tags/v$VERSION" 2>&1)"; then
        echo "Tag v$VERSION already exists" >&2; exit 1
      elif ! grep -q 'HTTP 404' <<<"$out"; then
        echo "Could not ask GitHub for the tag v$VERSION: $out" >&2; exit 1
      fi
    fi ;;
  --feed)
    [ "$(gh release view "v$VERSION" --repo "$REPO" --json isDraft --jq .isDraft 2>/dev/null)" = true ] ||
      { echo "No draft release v$VERSION (the CI workflow creates it)" >&2; exit 1; } ;;
esac
# Below the engine's macOS the app's popup downloads the last 0.1.x's DMG (its gw2om.sh's
# LAST_01_DMG), so that DMG has to be a published release asset (docs/adr/0021). (--feed publishes
# the DMG that --ci checked.)
case "$MODE$DEV_NO_RELEASE" in
  ""|--ci|--dev|--adhoc)
    g="$SRC/Contents/Resources/gw2om.sh"
    last01="$(sed -n 's/^LAST_01=//p' "$g" 2>/dev/null)"
    last01_dmg="$(sed -n 's/^LAST_01_DMG="\(.*\)"$/\1/p' "$g" 2>/dev/null)"
    last01_dmg="${last01_dmg//\$LAST_01/$last01}"
    [ -n "$last01" ] && [ -n "$last01_dmg" ] && curl -fsIL --retry 2 -o /dev/null "$last01_dmg" || {
      echo "The DMG of the last 0.1.x, ${last01:-?} (${last01_dmg:-no LAST_01_DMG in $g}), isn't a published release asset. The app below the engine's macOS sends players there: publish it, or set LAST_01 in src/gw2om.sh and build again." >&2
      exit 1; } ;;
esac

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# Submits $1 and polls Apple until it is processed (retrying through network errors, up to
# 3 hours); prints Apple's log and fails unless it was accepted.
notarize() {
  local id status="" deadline=$((SECONDS + 3 * 3600))
  id="$(xcrun notarytool submit "$1" "${notary_auth[@]}" --output-format json | plutil -extract id raw -)"
  echo "  submission $id"
  while [ "$SECONDS" -lt "$deadline" ]; do
    status="$(xcrun notarytool info "$id" "${notary_auth[@]}" --output-format json 2>/dev/null |
      plutil -extract status raw - 2>/dev/null || true)"
    case "$status" in Accepted|Invalid|Rejected) break ;; esac
    sleep 30
  done
  echo "  status: ${status:-unknown}"
  if [ "$status" != Accepted ]; then
    xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true
    exit 1
  fi
}

# Mounts disk image $1 read-only at directory $2.
attach() {
  # diskutil image (macOS 27) replaces the deprecated hdiutil attach.
  if diskutil image attach --readOnly --nobrowse --mountPoint "$2" "$1" >/dev/null 2>&1; then :
  else hdiutil attach -quiet -readonly -nobrowse -noverify -mountpoint "$2" "$1"; fi
}
detach() { hdiutil detach -quiet "$1" || hdiutil detach -quiet -force "$1"; }
# make_dmg <folder>: $DMG from <folder>, saying what hdiutil said when it fails (-quiet would close
# its output). GitHub's macOS runners sometimes fail it with "Resource busy", the temporary image
# still attached as hdiutil detaches it: that one is tried again, 3 times in all, 15 s apart. Any
# other failure stops at once.
make_dmg() {
  local try out
  for try in 1 2 3; do
    [ "$try" = 1 ] || rm -f "$DMG"
    out=$(hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$1" -fs HFS+ -format ULMO "$DMG" 2>&1) && return 0
    printf '%s\n' "$out" >&2
    case "$out" in
      *"Resource busy"*) echo "[release] hdiutil create: Resource busy (try $try of 3)" >&2 ;;
      *) echo "[release] hdiutil create failed" >&2; return 1 ;;
    esac
    [ "$try" = 3 ] || sleep 15
  done
  echo "[release] hdiutil create failed with Resource busy 3 times" >&2
  return 1
}

# Copies, signs and packages the app into $DMG, and notarizes it unless --no-notarize. --adhoc
# keeps build.sh's ad hoc signatures and checks the app in the DMG instead.
package() {
  echo "[release] $VERSION: copying the app"
  rm -rf "$OUT"
  mkdir -p "$OUT"
  ditto "$SRC" "$APP"
  xattr -cr "$APP"

  local fw stage fex pinned low
  ! grep -q '^stand-in' "$APP/Contents/Resources/components/dxmt/VERSION" ||
    { echo "The app bundles the stand-in DXMT (scripts/stage-components.sh --standin); stage the real one" >&2; exit 1; }
  ! grep -q '^stand-in' "$APP/Contents/Resources/components/ntdll/VERSION" 2>/dev/null ||
    { echo "The app bundles the stand-in ntdll.so (scripts/stage-components.sh --standin); stage the real one or none" >&2; exit 1; }
  ! grep -q '^stand-in' "$APP/Contents/Resources/components/macdrv/VERSION" 2>/dev/null ||
    { echo "The app bundles the stand-in winemac.so (scripts/stage-components.sh --standin); stage the real one or none" >&2; exit 1; }
  ! grep -q '^stand-in' "$APP/Contents/Resources/components/fex/VERSION" 2>/dev/null ||
    { echo "The app bundles the stand-in FEX (scripts/stage-components.sh --standin); stage the real one or none" >&2; exit 1; }
  # From 0.2.2 on a release starts on my FEX (docs/adr/0025), so it has to carry it, of the commit
  # prebuilt.lock pins. Development builds and release candidates may go without.
  case "$VERSION" in
    *-*) ;;
    *) low="$(printf '%s\n' 0.2.2 "$VERSION" | sort -V | head -1)"
       [ -n "$low" ] || { echo "Could not compare $VERSION with 0.2.2" >&2; exit 1; }
       if [ "$low" = 0.2.2 ]; then
         fex="$APP/Contents/Resources/components/fex"
         pinned="$(sed -n 's|^fex_url=.*/fex-arm64-\([0-9a-f]\{40\}\)\.tar\.xz$|\1|p' prebuilt.lock)"
         [ -n "$pinned" ] || { echo "prebuilt.lock pins no FEX of mine (fex_url=…/fex-arm64-<commit>.tar.xz), which a release from 0.2.2 on carries" >&2; exit 1; }
         [ -f "$fex/aarch64-windows/libarm64ecfex.dll" ] && [ -f "$fex/aarch64-unix/libarm64ecfex.so" ] ||
           { echo "$VERSION is a release from 0.2.2 on, which starts on my FEX, and the app bundles none: unpack jdrly/FEX's fex-arm64-$pinned.tar.xz (prebuilt.lock's fex_url) into the workspace's work/fex-arm64/install, then run scripts/stage-components.sh and ./build.sh again" >&2; exit 1; }
         grep -qx "commit: $pinned" "$fex/VERSION" ||
           { echo "The app bundles my FEX of another commit than prebuilt.lock's $pinned: unpack fex-arm64-$pinned.tar.xz (prebuilt.lock's fex_url) into the workspace's work/fex-arm64/install, then run scripts/stage-components.sh and ./build.sh again, or pin this one" >&2; exit 1; }
       fi ;;
  esac
  ! grep -q '^stand-in' "$APP/Contents/Resources/components/kosmickrisp/VERSION" 2>/dev/null ||
    { echo "The app bundles the stand-in KosmicKrisp (scripts/stage-components.sh --standin); stage the real one or none" >&2; exit 1; }
  if [ "$MODE" = --adhoc ]; then
    # build.sh's ad hoc signatures, verified and kept: nothing is signed again
    codesign --verify --strict --deep "$APP"
    [ "$(codesign -dv "$APP" 2>&1 | sed -n 's/^Signature=//p')" = adhoc ] || { echo "$SRC is not signed ad hoc" >&2; exit 1; }
    echo "[release] ad hoc signature verified"
  else
    # Inside out: the process lister and the session's lock (helpers/procpaths, sessionlock), my
    # DXMT fork's winemetal.so (gw2om.sh puts it into the engine's DXMT tree, where Wine loads it;
    # every Mach-O of a notarized app is signed; the PE DLLs are not Mach-O), my ntdll.so,
    # winemac.so, win32u.so, FEX's libarm64ecfex.so and my KosmicKrisp if the app has them (the engine's loader has
    # library validation off, so it loads them with my signature too; the app tells each from the
    # engine's own by its bytes, not by the fork's hash), Sparkle in its
    # documented order (Autoupdate, Updater.app, the framework, each with the hardened runtime and
    # no --deep; build.sh removed its XPC services), then the app (app.plist: no exceptions). The
    # engine is downloaded at install time, signed by its author, and nothing goes inside wine.app.
    echo "[release] signing nested code"
    sign "$APP/Contents/Resources/helpers/procpaths"
    sign "$APP/Contents/Resources/helpers/sessionlock"
    sign "$APP/Contents/Resources/components/dxmt/aarch64-unix/winemetal.so"
    [ ! -f "$APP/Contents/Resources/components/ntdll/ntdll.so" ] || sign "$APP/Contents/Resources/components/ntdll/ntdll.so"
    [ ! -f "$APP/Contents/Resources/components/macdrv/winemac.so" ] || sign "$APP/Contents/Resources/components/macdrv/winemac.so"
    [ ! -f "$APP/Contents/Resources/components/macdrv/win32u.so" ] || sign "$APP/Contents/Resources/components/macdrv/win32u.so"
    [ ! -f "$APP/Contents/Resources/components/fex/aarch64-unix/libarm64ecfex.so" ] || sign "$APP/Contents/Resources/components/fex/aarch64-unix/libarm64ecfex.so"
    [ ! -f "$APP/Contents/Resources/components/kosmickrisp/libvulkan_kosmickrisp.dylib" ] || sign "$APP/Contents/Resources/components/kosmickrisp/libvulkan_kosmickrisp.dylib"
    fw="$APP/$FW_REL"
    sign "$fw/Versions/B/Autoupdate"
    sign "$fw/Versions/B/Updater.app"
    sign "$fw"
    sign --entitlements "$ENT/app.plist" "$APP"
    codesign --verify --strict --deep "$APP"
    echo "[release] signature verified: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority=Developer ID Application' | cut -d= -f2)"
  fi
  [ "$MODE" = --sign-only ] && exit 0

  echo "[release] building the disk image"
  stage="$OUT/dmg"
  mkdir -p "$stage"
  ditto "$APP" "$stage/$APP_NAME.app"
  ln -s /Applications "$stage/Applications"
  make_dmg "$stage"
  rm -rf "$stage"
  if [ "$MODE" = --adhoc ]; then check_dmg; return; fi
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [ "$MODE" = --no-notarize ]; then
    echo "[release] not notarized (--no-notarize)"
  else
    echo "[release] notarizing the disk image"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
  fi
}

# --adhoc: the app in the finished DMG is the one build.sh made, file for file, with a valid
# signature, and it is a dev build of this app: its bundle id, the dev channel, no feed. With
# DXMT_COMMIT, WINE_COMMIT, MACDRV_COMMIT, FEX_COMMIT and KK_COMMIT, it bundles those commits' DXMT,
# ntdll.so, winemac.so, FEX and KosmicKrisp.
check_dmg() {
  local mnt a n err=""
  echo "[release] checking the app in the disk image"
  mnt="$(mktemp -d)"
  attach "$DMG" "$mnt"
  a="$mnt/$APP_NAME.app"
  scripts/app-files.sh "$a" >"$OUT/dmg.files" || err="Could not list the files of the DMG's app"
  [ -n "$err" ] || diff "$APP_FILES" "$OUT/dmg.files" >&2 || err="The DMG's app differs from $APP_FILES"
  [ -n "$err" ] || codesign --verify --strict --deep "$a" || err="The DMG's app has no valid signature"
  [ -n "$err" ] || [ "$(plutil -extract CFBundleIdentifier raw "$a/Contents/Info.plist")" = "$APP_ID" ] || err="The DMG's app is not $APP_ID"
  [ -n "$err" ] || [ "$(plutil -extract GW2Channel raw "$a/Contents/Info.plist")" = dev ] || err="The DMG's app is not on the dev channel"
  [ -n "$err" ] || [ -z "$(plutil -extract SUFeedURL raw "$a/Contents/Info.plist" 2>/dev/null || true)" ] || err="The DMG's app has a feed"
  [ -n "$err" ] || ! plutil -extract SUPublicEDKey raw "$a/Contents/Info.plist" >/dev/null 2>&1 || err="The DMG's app has an SUPublicEDKey"
  [ -n "$err" ] || [ -z "${DXMT_COMMIT:-}" ] || grep -qx "commit: $DXMT_COMMIT" "$a/Contents/Resources/components/dxmt/VERSION" ||
    err="The DMG's app bundles another DXMT than commit $DXMT_COMMIT"
  n="$a/Contents/Resources/components/ntdll"
  [ -n "$err" ] || [ -z "${WINE_COMMIT:-}" ] ||
    { grep -qx "commit: $WINE_COMMIT" "$n/VERSION" 2>/dev/null && [ -f "$n/ntdll.so" ] &&
      grep -qx "ntdll.so: sha256 $(shasum -a 256 "$n/ntdll.so" | cut -d' ' -f1)" "$n/VERSION"; } ||
    err="The DMG's app bundles no ntdll.so of commit $WINE_COMMIT with the sha256 its VERSION names"
  n="$a/Contents/Resources/components/macdrv"
  [ -n "$err" ] || [ -z "${MACDRV_COMMIT:-}" ] ||
    { grep -qx "commit: $MACDRV_COMMIT" "$n/VERSION" 2>/dev/null && [ -f "$n/winemac.so" ] &&
      grep -qx "winemac.so: sha256 $(shasum -a 256 "$n/winemac.so" | cut -d' ' -f1)" "$n/VERSION"; } ||
    err="The DMG's app bundles no winemac.so of commit $MACDRV_COMMIT with the sha256 its VERSION names"
  # (and win32u.so, when that build's VERSION names one)
  [ -n "$err" ] || [ -z "${MACDRV_COMMIT:-}" ] || ! grep -q '^win32u\.so: sha256 ' "$n/VERSION" ||
    { [ -f "$n/win32u.so" ] && grep -qx "win32u.so: sha256 $(shasum -a 256 "$n/win32u.so" | cut -d' ' -f1)" "$n/VERSION"; } ||
    err="The DMG's app bundles no win32u.so with the sha256 its VERSION names"
  n="$a/Contents/Resources/components/fex"
  [ -n "$err" ] || [ -z "${FEX_COMMIT:-}" ] ||
    { grep -qx "commit: $FEX_COMMIT" "$n/VERSION" 2>/dev/null && [ -f "$n/aarch64-windows/libarm64ecfex.dll" ] &&
      grep -qx "aarch64-windows/libarm64ecfex.dll: sha256 $(shasum -a 256 "$n/aarch64-windows/libarm64ecfex.dll" | cut -d' ' -f1)" "$n/VERSION"; } ||
    err="The DMG's app bundles no FEX of commit $FEX_COMMIT with the sha256 its VERSION names"
  n="$a/Contents/Resources/components/kosmickrisp"
  [ -n "$err" ] || [ -z "${KK_COMMIT:-}" ] ||
    { grep -qx "commit: $KK_COMMIT" "$n/VERSION" 2>/dev/null && [ -f "$n/libvulkan_kosmickrisp.dylib" ] &&
      grep -qx "libvulkan_kosmickrisp.dylib: sha256 $(shasum -a 256 "$n/libvulkan_kosmickrisp.dylib" | cut -d' ' -f1)" "$n/VERSION"; } ||
    err="The DMG's app bundles no KosmicKrisp of commit $KK_COMMIT with the sha256 its VERSION names"
  detach "$mnt"
  rmdir "$mnt"
  [ -z "$err" ] || { echo "$err" >&2; exit 1; }
  echo "[release] the DMG's app matches $APP_FILES ($(wc -l <"$APP_FILES" | tr -d ' ') files and links), signature valid"
}

# --feed: the notarized DMG from the draft release, checked, and the app inside it.
fetch_draft() {
  echo "[release] $VERSION: downloading the DMG from the draft release"
  rm -rf "$OUT"
  mkdir -p "$OUT"
  gh release download "v$VERSION" --repo "$REPO" --pattern "${DMG##*/}" --dir "$OUT"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  local mnt
  mnt="$(mktemp -d)"
  attach "$DMG" "$mnt"
  ditto "$mnt/$APP_NAME.app" "$APP"
  detach "$mnt"
  rm -rf "$mnt"
  spctl --assess --type execute --verbose=2 "$APP"
  [ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = "$VERSION" ] ||
    { echo "The DMG's app is not version $VERSION" >&2; exit 1; }
}

if [ "$MODE" = --feed ]; then
  fetch_draft
else
  package
fi

case "$MODE" in
  --ci-dry-run)
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); no GitHub release (--ci-dry-run)"
    exit 0 ;;
  --adhoc)
    # The record with the DMG's sha256, and the notes with how to install a build that isn't
    # notarized, before the Support section that ends them
    record="$OUT/$DASHED-$VERSION.build.txt"
    { cat "$BUILD_RECORD"; echo "dmg $(shasum -a 256 "$DMG" | cut -d' ' -f1)  ${DMG##*/}"; } >"$record"
    {
      echo "### Installing it"
      echo "This build is signed ad hoc and not notarized, so macOS opens it only without the quarantine"
      echo "attribute a browser download gets. GitHub's command line sets none:"
      echo
      echo '```sh'
      echo "gh release download v$VERSION -R $REPO -p '*.dmg' -D ~/Downloads"
      echo '```'
      echo
      echo "Then open the DMG and drag *$APP_NAME* to Applications. After a download in a browser, run"
      echo "\`xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\"\` once before the first start."
    } >"$OUT/install.md"
    awk -v ins="$OUT/install.md" '
      function insert(l) { while ((getline l < ins) > 0) print l; close(ins) }
      /^### Support/ && !done { insert(); print ""; done = 1 }
      { print }
      END { if (!done) { print ""; insert() } }' "$NOTES" >"$OUT/notes.md"
    if [ -n "$DEV_NO_RELEASE" ]; then
      echo "[release] $DMG ($(du -h "$DMG" | cut -f1)), $record; no GitHub pre-release (--no-release)"
      exit 0
    fi
    head=$(git rev-parse HEAD)
    git branch -r --contains "$head" | grep -q . || { echo "Push $head first" >&2; exit 1; }
    # A pre-release is never releases/latest, the feed every 0.1.x install reads; check it anyway
    latest="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
    echo "[release] creating the GitHub pre-release v$VERSION (DMG and record, no feed; releases/latest is $latest)"
    gh release create "v$VERSION" --repo "$REPO" --prerelease --latest=false --target "$head" \
      --title "$APP_NAME $VERSION ($KIND)" --notes-file "$OUT/notes.md" "$DMG" "$record"
    now="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
    [ "$now" = "$latest" ] || { echo "releases/latest moved from $latest to $now" >&2; exit 1; }
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); pre-release v$VERSION; releases/latest still $latest"
    exit 0 ;;
  --dev)
    if [ -n "$DEV_NO_RELEASE" ]; then
      echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); no GitHub pre-release (--no-release)"
      exit 0
    fi
    # A pre-release never becomes releases/latest. The tag also starts the Release workflow,
    # which stops at its version check for dev versions (release.yml); cancel the run anyway.
    echo "[release] creating the GitHub pre-release v$VERSION (DMG only, no feed)"
    # the tag goes on the commit this was built from (the dev branch), which must be pushed
    head=$(git rev-parse HEAD)
    git branch -r --contains "$head" | grep -q . || { echo "Push $head first" >&2; exit 1; }
    gh release create "v$VERSION" --repo "$REPO" --prerelease --target "$head" \
      --title "$APP_NAME $VERSION ($KIND)" --notes-file "$NOTES" "$DMG"
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); pre-release v$VERSION"
    exit 0 ;;
  --ci)
    echo "[release] creating the draft GitHub release v$VERSION (DMG only)"
    gh release create "v$VERSION" --repo "$REPO" --draft --title "$APP_NAME $VERSION" \
      --notes-file "$NOTES" "$DMG"
    echo "[release] draft v$VERSION created; on the Mac, run scripts/release.sh --feed $VERSION"
    exit 0 ;;
esac

# The update feed. release/updates keeps the DMGs of this and the 5 previous versions, the
# bases of the delta updates. generate_appcast runs on a copy of them, so the feed starts
# afresh every time and holds only this version (it would rewrite older entries' URLs to
# this release's).
echo "[release] building the update feed"
# The feed names this checkout's MACOS_MIN, so it has to be the one in the app it offers (--feed
# takes the app from the draft's DMG, which may come from another commit)
[ "$(sed -n 's/^MACOS_MIN=\([0-9][0-9.]*\)$/\1/p' "$APP/Contents/Resources/gw2om.sh")" = "$MACOS_MIN" ] ||
  { echo "The app's gw2om.sh doesn't say MACOS_MIN=$MACOS_MIN, as src/gw2om.sh does" >&2; exit 1; }
mkdir -p "$UPDATES"
rm -f "$UPDATES/${DMG##*/}"
cp -c "$DMG" "$UPDATES/"
kept=()
while IFS= read -r v; do kept+=("$v"); done < <(ls "$UPDATES" | sed -n "s/^$DASHED-\\(.*\\)\\.dmg\$/\\1/p" | sort -V)
for ((i = 0; i < ${#kept[@]} - 6; i++)); do rm -f "$UPDATES/$DASHED-${kept[i]}.dmg"; done
feed="$OUT/feed"
rm -rf "$feed"
mkdir -p "$feed"
cp -c "$UPDATES/$DASHED"-*.dmg "$feed/"
[ -f "$NOTES" ] && cp "$NOTES" "$feed/$DASHED-$VERSION.md"
# (--versions: an item for this version only. generate_appcast keeps the newest version of every
# minimum macOS, so 0.1.x's DMGs, for 26.0, would get an item of their own beside 0.2's for 26.5.
# The older DMGs stay the bases of the deltas.)
"$SPARKLE_BIN/generate_appcast" ${ED_KEY_FILE:+--ed-key-file "$ED_KEY_FILE"} \
  --versions "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" \
  --maximum-versions 1 --maximum-deltas 5 --embed-release-notes \
  --download-url-prefix "$URL_PREFIX" "$feed"
# Deltas are named "<name><new>-<old>.delta"; GitHub replaces spaces in asset names, so
# rename them and their URLs. (The appcast itself is not signed, so it may be edited.)
cp "$feed/appcast.xml" "$OUT/appcast.xml"
deltas=()
for d in "$feed"/*.delta; do
  [ -e "$d" ] || continue
  pair="${d##*/$APP_NAME}"; pair="${pair%.delta}"   # <new>-<old>
  new="${pair%%-*}"; old="${pair#*-}"
  name="$DASHED-$new-from-$old.delta"
  mv "$d" "$OUT/$name"
  sed -i '' "s|${APP_NAME// /%20}$new-$old\.delta\"|$name\"|" "$OUT/appcast.xml"
  deltas+=("$OUT/$name")
done
rm -rf "$feed"
xmllint --noout "$OUT/appcast.xml"
! grep -q "${APP_NAME// /%20}" "$OUT/appcast.xml" || { echo "appcast.xml still names unrenamed deltas" >&2; exit 1; }
# One item, and it names the macOS the engine needs, not the app's LSMinimumSystemVersion
# (feed_min): 0.1.x runs on 26.0, 0.2 needs 26.5
feed_min "$OUT/appcast.xml"
echo "  $OUT/appcast.xml, ${#deltas[@]} delta(s)"
# generate_appcast skips a delta it couldn't make or that isn't smaller than the DMG, without a word
# in its summary: name each older DMG it made none from (the update from it downloads the DMG)
for v in ${kept[@]+"${kept[@]}"}; do
  [ "$v" != "$VERSION" ] && [ -f "$UPDATES/$DASHED-$v.dmg" ] || continue
  [ -e "$OUT/$DASHED-$VERSION-from-$v.delta" ] || echo "  no delta from $v: generate_appcast made none (too large, or it failed); $v downloads the DMG"
done

# Check the feed as Sparkle will: lengths and EdDSA signatures against the app's public key.
echo "[release] checking the update feed"
swift scripts/check-appcast.swift "$OUT/appcast.xml" "$OUT" \
  "$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist")"
# Apply every delta to the app of its old version, which must give this version's app with
# a valid signature (BinaryDelta checks the result against the hash in the delta).
for d in ${deltas[@]+"${deltas[@]}"}; do
  old="${d##*-from-}"; old="${old%.delta}"
  mnt="$(mktemp -d)"; tmp="$(mktemp -d "$OUT/delta-check.XXXXXX")"
  attach "$UPDATES/$DASHED-$old.dmg" "$mnt"
  ok=1
  "$SPARKLE_BIN/BinaryDelta" apply "$mnt/$APP_NAME.app" "$tmp/$APP_NAME.app" "$d" >/dev/null &&
    codesign --verify --strict --deep "$tmp/$APP_NAME.app" &&
    [ "$(plutil -extract CFBundleShortVersionString raw "$tmp/$APP_NAME.app/Contents/Info.plist")" = "$VERSION" ] || ok=0
  detach "$mnt"
  rm -rf "$tmp" "$mnt"
  [ "$ok" = 1 ] || { echo "Delta ${d##*/} does not apply to $old" >&2; exit 1; }
  echo "  ${d##*/}: applies to $old, signature valid"
done

case "$MODE" in
  --no-notarize|--no-release)
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); no GitHub release ($MODE)" ;;
  --feed)
    echo "[release] adding the feed to the draft release v$VERSION"
    gh release upload "v$VERSION" --repo "$REPO" --clobber "$OUT/appcast.xml" ${deltas[@]+"${deltas[@]}"}
    echo "[release] draft v$VERSION complete; publish it to make the update live" ;;
  *)
    echo "[release] creating the draft GitHub release v$VERSION"
    gh release create "v$VERSION" --repo "$REPO" --draft --target "$head" --title "$APP_NAME $VERSION" \
      --notes-file "$NOTES" "$DMG" ${deltas[@]+"${deltas[@]}"} "$OUT/appcast.xml"
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); publish the draft to make the update live" ;;
esac
