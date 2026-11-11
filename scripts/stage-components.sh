#!/bin/bash
# Stages the component the app bundles into prebuilt/ (ignored by git: binaries stay out of the
# repository), copied from the build in my development workspace's work/. Nothing in the workspace
# is changed. build.sh checks prebuilt/.
#
#   prebuilt/ui-scale/  the interface-scale addon, version.dll and gw2-ui-scale.ini (the app's
#                       own code, addon/ui-scale; scripts/build-addon.sh builds the same thing)
#
# This line runs Mach9's engine as it ships, so my DXMT fork and Wine builds (0.1.x's dxmt/, heat/
# and winemac/) are not staged.
#
# Sources: GW2_ON_MAC_WORKSPACE (default ../gw2-on-mac, next to this repository) and in it
# UISCALE_BUILD=work/ui-scale/build (relative to the workspace, or absolute).
#
# Without the workspace (GitHub's runners), or with --fetch, it downloads the files as one archive
# instead: a pre-release of this repository, pinned in prebuilt.lock by tag, file name and sha256,
# and checked against that sha256 before anything is unpacked. The archive is 0.1.x's and holds
# its other components too; only ui-scale/ is kept. --pack <tag> makes that archive from prebuilt/
# as staged, into release/<tag>/, and writes prebuilt.lock for it; README.md (Building) says how I
# publish it.
#
#   scripts/stage-components.sh [--fetch | --pack <tag>]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
P="$ROOT/prebuilt"
LOCK="$ROOT/prebuilt.lock"
WS="${GW2_ON_MAC_WORKSPACE:-$ROOT/../gw2-on-mac}"

die() { echo "stage-components: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

if [ "${1:-}" = --pack ]; then
  tag="${2:-}"
  case "$tag" in components-*) ;; *) die "usage: scripts/stage-components.sh --pack components-<date>" ;; esac
  [ -f "$P/STAGED" ] || die "no $P/ to pack; stage it from the workspace first"
  file="gw2-on-mac-$tag.tar.xz"
  mkdir -p "$ROOT/release/$tag"
  COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname wheel \
    -cJf "$ROOT/release/$tag/$file" -C "$P" .
  { echo "# The components build.sh bundles (prebuilt/), for a checkout without my development workspace:"
    echo "# https://github.com/jdrly/gw2-on-mac/releases/download/<tag>/<file>, a pre-release, made by"
    echo "# scripts/stage-components.sh --pack and fetched and checked by scripts/stage-components.sh."
    echo "tag=$tag"
    echo "file=$file"
    echo "sha256=$(sha "$ROOT/release/$tag/$file")"; } >"$LOCK"
  echo "release/$tag/$file ($(du -h "$ROOT/release/$tag/$file" | cut -f1)), prebuilt.lock:"
  cat "$LOCK"
  exit 0
fi

if [ "${1:-}" = --fetch ] || [ ! -d "$WS" ]; then
  [ -f "$LOCK" ] || die "no workspace at $WS and no prebuilt.lock"
  tag="$(sed -n 's/^tag=//p' "$LOCK")" file="$(sed -n 's/^file=//p' "$LOCK")" want="$(sed -n 's/^sha256=//p' "$LOCK")"
  [ -n "$tag" ] && [ -n "$file" ] && [ -n "$want" ] || die "prebuilt.lock needs tag=, file= and sha256="
  url="https://github.com/jdrly/gw2-on-mac/releases/download/$tag/$file"
  archive="$ROOT/.cache/$want/$file"
  if [ ! -f "$archive" ]; then
    echo "stage-components: fetching $url" >&2
    mkdir -p "${archive%/*}"
    curl -fL --retry 3 --progress-bar -o "$archive.part" "$url"
    [ "$(sha "$archive.part")" = "$want" ] || { rm -f "$archive.part"; die "$url does not match the sha256 in prebuilt.lock"; }
    mv "$archive.part" "$archive"
  fi
  [ "$(sha "$archive")" = "$want" ] || die "$archive does not match the sha256 in prebuilt.lock; delete it to fetch it again"
  rm -rf "$P.new" && mkdir -p "$P.new"
  tar -xJf "$archive" -C "$P.new" ./ui-scale
  echo "fetched $file ($want) by scripts/stage-components.sh" >>"$P.new/STAGED"
  rm -rf "$P" && mv "$P.new" "$P"
  cat "$P/STAGED"
  exit 0
fi

WS="$(cd "$WS" && pwd)"
in_ws() { case "$1" in /*) echo "$1" ;; *) echo "$WS/$1" ;; esac; }
UISCALE_BUILD="$(in_ws "${UISCALE_BUILD:-work/ui-scale/build}")"

need() { for f in "$@"; do [ -f "$f" ] || die "missing $f"; done; }
need "$UISCALE_BUILD/version.dll" "$UISCALE_BUILD/gw2-ui-scale.ini"
grep -aq 'gw2-on-mac ui-scale' "$UISCALE_BUILD/version.dll" || die "$UISCALE_BUILD/version.dll is not the ui-scale addon"

rm -rf "$P.new" && mkdir -p "$P.new"
mkdir -p "$P.new/ui-scale" && cp "$UISCALE_BUILD"/{version.dll,gw2-ui-scale.ini} "$P.new/ui-scale/"
# The record names the source relative to the workspace (no home folder in it)
rel() { echo "${1#"$WS"/}"; }
{ echo "staged $(date '+%F %T') by scripts/stage-components.sh from the development workspace"
  echo "ui-scale $(sha "$UISCALE_BUILD/version.dll") from $(rel "$UISCALE_BUILD")"; } >"$P.new/STAGED"
rm -rf "$P" && mv "$P.new" "$P"
cat "$P/STAGED"
