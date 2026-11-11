#!/bin/bash
# Signs, notarizes and packages the app in dist/ (run ./build.sh first), and prepares the
# update feed for Sparkle (src/native/Updates.swift): SWTOR on Mac's release script, as is, for
# this app (paths below are relative to the repository root).
#
# Releases go out from here. 0.1.0 and 0.1.1 are published, with their feed. As a safety stop,
# every mode that creates or changes a GitHub release (the default, --ci, --dev, --feed) stops
# unless GW2_ON_MAC_PUBLISH=1. A feed needs an app built with GW2_ON_MAC_FEED_URL and GW2_ON_MAC_ED_PUBLIC_KEY (./build.sh
# puts them into Info.plist's SUFeedURL and SUPublicEDKey; without them Sparkle stays off).
#
#   release/<version>/<name>.app                       Developer ID, hardened runtime (<name>: the
#                                                       app's name; <Name>: the same with dashes)
#   release/<version>/<Name>-<version>.dmg             signed, notarized, stapled
#   release/<version>/<Name>-<version>-from-<old>.delta delta updates from older versions
#   release/<version>/appcast.xml                       the feed, with only this version
#   release/updates/                                    DMGs of this and the 5 previous versions
# then creates a draft GitHub release v<version> with the DMG, the deltas and appcast.xml.
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
#   scripts/release.sh --dev         development builds (version X.Y.Z-dev.N, build.sh): sign,
#                                    notarize and staple the DMG, then a GitHub pre-release with
#                                    the DMG only. No feed: releases/latest (the appcast every
#                                    install reads) stays on the last release.
#   scripts/release.sh --dev --no-release   the same without the pre-release
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
# Overrides: IDENTITY, NOTARY_PROFILE, or NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER (an App Store
# Connect API key file instead of the keychain profile, as in CI); RELEASE_DIR (default
# release), DOWNLOAD_URL_PREFIX (where the appcast points, default the version's GitHub
# release), ED_KEY_FILE (a private EdDSA key file instead of the keychain, for test keys),
# RELEASE_NOTES (the notes file).
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"
# (see the header: these modes need GW2_ON_MAC_PUBLISH=1)
case "$MODE:${2:-}" in
  :|--ci:|--dev:|--feed:*)
    [ "${GW2_ON_MAC_PUBLISH:-}" = 1 ] || {
      echo "This mode creates or changes a GitHub release. Set GW2_ON_MAC_PUBLISH=1 to publish, or use --sign-only, --no-notarize or --no-release." >&2
      exit 1; } ;;
esac
DEV_NO_RELEASE=""
if [ "$MODE" = --dev ] && [ "${2:-}" = --no-release ]; then DEV_NO_RELEASE=1; fi
case "$MODE" in
  ""|--sign-only|--no-notarize|--no-release|--ci|--ci-dry-run|--dev) ;;
  --feed) [ -n "${2:-}" ] || { echo "usage: $0 --feed <version>" >&2; exit 2; } ;;
  *) echo "unknown option: $MODE" >&2; exit 2 ;;
esac
IDENTITY="${IDENTITY:-Developer ID Application: Jan Drly (3JT82CY6ZK)}"
PROFILE="${NOTARY_PROFILE:-swgl-notary}"
REPO=jdrly/gw2-on-mac
# The app's name (src/gw2om.sh has the one definition), and as GitHub's asset names have it
APP_NAME="$(sed -n 's/^APP_NAME="\(.*\)"$/\1/p' src/gw2om.sh)"
DASHED="${APP_NAME// /-}"
SRC="dist/$APP_NAME.app"
ENT="$PWD/src/entitlements"
if [ "$MODE" = --feed ]; then
  VERSION="$2"
else
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$SRC/Contents/Info.plist")"
fi
# Development builds never go into a feed or a regular release, and releases are never dev builds.
case "$VERSION:$MODE" in
  *-dev.*:--dev|*-dev.*:--sign-only) ;;
  *-*:*) echo "$VERSION is a development build: use --dev (or --sign-only)" >&2; exit 1 ;;
  *:--dev) echo "$VERSION is not a development build (X.Y.Z-dev.N)" >&2; exit 1 ;;
esac
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
  ""|--ci|--dev)
    gh auth status >/dev/null 2>&1 || { echo "gh is not logged in" >&2; exit 1; }
    ! gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 || { echo "Release v$VERSION already exists" >&2; exit 1; } ;;
  --feed)
    [ "$(gh release view "v$VERSION" --repo "$REPO" --json isDraft --jq .isDraft 2>/dev/null)" = true ] ||
      { echo "No draft release v$VERSION (the CI workflow creates it)" >&2; exit 1; } ;;
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

# Copies, signs and packages the app into $DMG, and notarizes it unless --no-notarize.
package() {
  echo "[release] $VERSION: copying the app"
  rm -rf "$OUT"
  mkdir -p "$OUT"
  ditto "$SRC" "$APP"
  xattr -cr "$APP"

  # Inside out: the process lister and the session's lock (helpers/procpaths, sessionlock), the Mach-O pieces gw2om.sh puts into the
  # engine (DXMT's winemetal.so, the heat ntdll.so and wineserver, winemac.so and win32u.so: Wine
  # loads or runs them itself; every Mach-O of a notarized app is signed; DXMT's PE DLLs and
  # winemac.drv are not Mach-O), Sparkle in its documented order (Autoupdate, Updater.app, the framework, each with
  # the hardened runtime and no --deep; build.sh removed its XPC services), then the app
  # (app.plist: no exceptions). Untested so far: wineserver under the hardened runtime.
  echo "[release] signing nested code"
  local fw stage c
  sign "$APP/Contents/Resources/helpers/procpaths"
  sign "$APP/Contents/Resources/helpers/sessionlock"
  c="$APP/Contents/Resources/components"
  sign "$c/dxmt/x86_64-unix/winemetal.so"
  sign "$c/heat/ntdll.so"
  sign "$c/heat/wineserver"
  sign "$c/winemac/winemac.so"
  sign "$c/winemac/win32u.so"
  fw="$APP/$FW_REL"
  sign "$fw/Versions/B/Autoupdate"
  sign "$fw/Versions/B/Updater.app"
  sign "$fw"
  sign --entitlements "$ENT/app.plist" "$APP"
  codesign --verify --strict --deep "$APP"
  echo "[release] signature verified: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority=Developer ID Application' | cut -d= -f2)"
  [ "$MODE" = --sign-only ] && exit 0

  echo "[release] building the disk image"
  stage="$OUT/dmg"
  mkdir -p "$stage"
  ditto "$APP" "$stage/$APP_NAME.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$stage" -fs HFS+ -format ULMO "$DMG"
  rm -rf "$stage"
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
      --title "$APP_NAME $VERSION (development build)" --notes-file "$NOTES" "$DMG"
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
"$SPARKLE_BIN/generate_appcast" ${ED_KEY_FILE:+--ed-key-file "$ED_KEY_FILE"} \
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
echo "  $OUT/appcast.xml, ${#deltas[@]} delta(s)"

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
    gh release create "v$VERSION" --repo "$REPO" --draft --title "$APP_NAME $VERSION" \
      --notes-file "$NOTES" "$DMG" ${deltas[@]+"${deltas[@]}"} "$OUT/appcast.xml"
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); publish the draft to make the update live" ;;
esac
