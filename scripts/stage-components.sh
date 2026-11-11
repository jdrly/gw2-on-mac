#!/bin/bash
# Stages the components the app bundles into prebuilt/ (ignored by git: binaries stay out of the
# repository), copied from the builds in my development workspace's work/. Nothing in the
# workspace is changed. build.sh checks prebuilt/ against the records copied here.
#
#   prebuilt/dxmt/      my DXMT fork (jdrly/dxmt, LGPL-2.1-or-later) built for this line's engine
#                       (jdrly/dxmt#182), in the engine's layout: aarch64-windows/ and i386-windows/
#                       (d3d11, dxgi, d3d10core, winemetal.dll) and aarch64-unix/winemetal.so, with
#                       VERSION (its first line names the commit), LICENSE and COPYING.LIB.
#                       SHA256SUMS is the record this script writes: every file's sha256, which
#                       build.sh checks. gw2om.sh puts it into the engine's DXMT tree.
#   prebuilt/ui-scale/  the interface-scale addon, version.dll and gw2-ui-scale.ini (the app's
#                       own code, addon/ui-scale; scripts/build-addon.sh builds the same thing)
#
# 0.1.x's Wine builds (heat/ and winemac/) are not staged on this line.
#
# Sources: GW2_ON_MAC_WORKSPACE (default ../gw2-on-mac, next to this repository) and in it
# DXMT_BUILD=work/dxmt-arm64/install (the fork's CI artifact, unpacked) and
# UISCALE_BUILD=work/ui-scale/build (relative to the workspace, or absolute). It refuses a DXMT build
# for another engine than src/gw2om.sh's ENGINE_SHA256, a winemetal.so without a valid signature,
# and, with DXMT_COMMIT set, a build of another commit. STAGED_FROM replaces "the development
# workspace" in the first line of prebuilt/STAGED (the dev build workflow names the fork's commit
# and where its files came from).
#
# Without the workspace (GitHub's runners), or with --fetch, it downloads the files as one archive
# instead: a pre-release of this repository, pinned in prebuilt.lock by tag, file name and sha256,
# and checked against that sha256 before anything is unpacked. Only ui-scale/ and an arm64 dxmt/
# are kept (0.1.x's archives have an x86_64 dxmt/, which isn't). --pack <tag> makes that archive
# from prebuilt/ as staged, into release/<tag>/, and writes prebuilt.lock for it; README.md
# (Building) says how I publish it.
#
# --standin adds a stand-in dxmt/ to prebuilt/ (files in the fork's layout that only name
# themselves), for the checks and the sandbox until prebuilt.lock pins an archive with the real
# one. build.sh takes it; scripts/release.sh refuses it.
#
#   scripts/stage-components.sh [--fetch | --pack <tag> | --standin]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
P="$ROOT/prebuilt"
LOCK="$ROOT/prebuilt.lock"
WS="${GW2_ON_MAC_WORKSPACE:-$ROOT/../gw2-on-mac}"
# The fork's files for this engine, in the engine's layout (lib/wine/dxgi/dxmt)
DXMT_FILES="aarch64-windows/d3d11.dll aarch64-windows/dxgi.dll aarch64-windows/d3d10core.dll aarch64-windows/winemetal.dll
i386-windows/d3d11.dll i386-windows/dxgi.dll i386-windows/d3d10core.dll i386-windows/winemetal.dll
aarch64-unix/winemetal.so VERSION LICENSE COPYING.LIB"

die() { echo "stage-components: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
# dxmt_record <dir>: <dir>/SHA256SUMS, every file's sha256 (shasum -c reads it)
dxmt_record() {
  (cd "$1" && find . -type f ! -name 'SHA256SUMS*' | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do
    echo "$(sha "$f")  $f"
  done) >"$1/SHA256SUMS.new"
  mv "$1/SHA256SUMS.new" "$1/SHA256SUMS"
}

if [ "${1:-}" = --pack ]; then
  tag="${2:-}"
  case "$tag" in components-*) ;; *) die "usage: scripts/stage-components.sh --pack components-<date>" ;; esac
  [ -f "$P/STAGED" ] || die "no $P/ to pack; stage it from the workspace first"
  ! grep -q '^stand-in' "$P/dxmt/VERSION" 2>/dev/null || die "$P/dxmt is the stand-in; stage the real one first"
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

if [ "${1:-}" = --standin ]; then
  [ -f "$P/STAGED" ] || die "no $P/; stage or fetch it first"
  rm -rf "$P/dxmt" "$P/dxmt.new" && mkdir -p "$P/dxmt.new"
  for f in $DXMT_FILES; do
    mkdir -p "$P/dxmt.new/$(dirname "$f")"
    echo "stand-in $f" >"$P/dxmt.new/$f"
  done
  echo "stand-in v0.80-0-g0000000 (not a build: scripts/stage-components.sh --standin)" >"$P/dxmt.new/VERSION"
  dxmt_record "$P/dxmt.new"
  mv "$P/dxmt.new" "$P/dxmt"
  echo "dxmt stand-in by scripts/stage-components.sh --standin" >>"$P/STAGED"
  cat "$P/STAGED"
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
  rm -rf "$P.new" "$P.all" && mkdir -p "$P.new" "$P.all"
  tar -xJf "$archive" -C "$P.all"
  mv "$P.all/ui-scale" "$P.new/"
  if [ -d "$P.all/dxmt/aarch64-windows" ]; then mv "$P.all/dxmt" "$P.new/"; fi
  rm -rf "$P.all"
  echo "fetched $file ($want) by scripts/stage-components.sh" >>"$P.new/STAGED"
  rm -rf "$P" && mv "$P.new" "$P"
  cat "$P/STAGED"
  [ -d "$P/dxmt" ] || echo "stage-components: $file has no arm64 DXMT; scripts/stage-components.sh --standin adds a stand-in" >&2
  exit 0
fi

WS="$(cd "$WS" && pwd)"
in_ws() { case "$1" in /*) echo "$1" ;; *) echo "$WS/$1" ;; esac; }
DXMT_BUILD="$(in_ws "${DXMT_BUILD:-work/dxmt-arm64/install}")"
UISCALE_BUILD="$(in_ws "${UISCALE_BUILD:-work/ui-scale/build}")"

need() { for f in "$@"; do [ -f "$f" ] || die "missing $f"; done; }
# DXMT: the PE DLLs and winemetal.so of one build always go together
for f in $DXMT_FILES; do need "$DXMT_BUILD/$f"; done
# Built for the engine gw2om.sh installs (VERSION's engine: line names its tarball's sha256), from
# the commit asked for (DXMT_COMMIT, a full sha; the dev build sets it), and a winemetal.so with a
# valid signature (the linker's: nothing signs it again before the engine loads it)
engine_sha="$(sed -n 's/^ENGINE_SHA256=\([0-9a-f]*\).*/\1/p' "$ROOT/src/gw2om.sh")"
[ -n "$engine_sha" ] || die "no ENGINE_SHA256 in src/gw2om.sh"
grep -q "^engine: .*sha256 $engine_sha" "$DXMT_BUILD/VERSION" || die "$DXMT_BUILD/VERSION names another engine than ENGINE_SHA256 ($engine_sha)"
[ -z "${DXMT_COMMIT:-}" ] || grep -qx "commit: $DXMT_COMMIT" "$DXMT_BUILD/VERSION" || die "$DXMT_BUILD/VERSION is not commit $DXMT_COMMIT"
codesign --verify "$DXMT_BUILD/aarch64-unix/winemetal.so" || die "$DXMT_BUILD/aarch64-unix/winemetal.so has no valid signature"
need "$UISCALE_BUILD/version.dll" "$UISCALE_BUILD/gw2-ui-scale.ini"
grep -aq 'gw2-on-mac ui-scale' "$UISCALE_BUILD/version.dll" || die "$UISCALE_BUILD/version.dll is not the ui-scale addon"

rm -rf "$P.new" && mkdir -p "$P.new/dxmt"
for f in $DXMT_FILES; do mkdir -p "$P.new/dxmt/$(dirname "$f")" && cp "$DXMT_BUILD/$f" "$P.new/dxmt/$f"; done
dxmt_record "$P.new/dxmt"
mkdir -p "$P.new/ui-scale" && cp "$UISCALE_BUILD"/{version.dll,gw2-ui-scale.ini} "$P.new/ui-scale/"
# The record names the sources relative to the workspace (no home folder in it)
rel() { echo "${1#"$WS"/}"; }
{ echo "staged $(date '+%F %T') by scripts/stage-components.sh from ${STAGED_FROM:-the development workspace}"
  echo "dxmt $(head -1 "$DXMT_BUILD/VERSION") d3d11 $(sha "$DXMT_BUILD/aarch64-windows/d3d11.dll") winemetal.so $(sha "$DXMT_BUILD/aarch64-unix/winemetal.so") from $(rel "$DXMT_BUILD")"
  echo "ui-scale $(sha "$UISCALE_BUILD/version.dll") from $(rel "$UISCALE_BUILD")"; } >"$P.new/STAGED"
rm -rf "$P" && mv "$P.new" "$P"
cat "$P/STAGED"
