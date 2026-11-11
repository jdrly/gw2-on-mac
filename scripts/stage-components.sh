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
#   prebuilt/ntdll/     my ntdll.so (jdrly/wine, LGPL-2.1-or-later) built for this line's engine
#                       (#40): ntdll.so, VERSION (its "commit:", "engine:" and "ntdll.so: sha256"
#                       lines name the fork's commit, the engine's tarball and the file as built),
#                       LICENSE and COPYING.LIB, and SHA256SUMS, the record this script writes.
#                       gw2om.sh puts ntdll.so into the engine, the engine's own kept next to it.
#                       Optional: a build without it leaves the engine's own in place.
#   prebuilt/ui-scale/  the interface-scale addon, version.dll and gw2-ui-scale.ini (the app's
#                       own code, addon/ui-scale; scripts/build-addon.sh builds the same thing)
#
# 0.1.x's Wine builds (heat/ and winemac/) are not staged on this line.
#
# Sources: GW2_ON_MAC_WORKSPACE (default ../gw2-on-mac, next to this repository) and in it
# DXMT_BUILD=work/dxmt-arm64/install (the fork's CI artifact, unpacked),
# NTDLL_BUILD=work/ntdll-mach9/install (jdrly/wine's asset ntdll-mach9-<commit>.tar.xz, unpacked;
# without it no ntdll/) and UISCALE_BUILD=work/ui-scale/build (relative to the workspace, or
# absolute). It refuses a DXMT build or an ntdll.so for another engine than src/gw2om.sh's
# ENGINE_SHA256, a winemetal.so or ntdll.so without a valid signature, an ntdll.so that isn't the
# file its VERSION names, and, with DXMT_COMMIT or WINE_COMMIT set, a build of another commit (or,
# for WINE_COMMIT, none). STAGED_FROM replaces "the development workspace" in the first line of
# prebuilt/STAGED (the dev build workflow names the fork's commit and where its files came from).
#
# Without the workspace (GitHub's runners), or with --fetch, it downloads the files instead, each
# checked against its sha256 in prebuilt.lock before anything is unpacked: one archive, a
# pre-release of this repository pinned by tag, file name and sha256, of which only ui-scale/ and
# an arm64 dxmt/ are kept (0.1.x's archives have an x86_64 dxmt/, which isn't), and my ntdll.so's
# archive, pinned by ntdll_url and ntdll_sha256 when prebuilt.lock has them, checked as above.
# --pack <tag> makes that one archive from prebuilt/ as staged, without ntdll/, into
# release/<tag>/, and writes prebuilt.lock for it, keeping its ntdll_ lines; README.md (Building)
# says how I publish it.
#
# --standin adds a stand-in for each of dxmt/ and ntdll/ that prebuilt/ lacks (files in the
# layout of the fork's build that only name themselves), for the checks and the sandbox until
# prebuilt.lock pins the real ones. build.sh takes them; scripts/release.sh refuses them.
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
# My ntdll.so's files (jdrly/wine's archive has them at its root)
NTDLL_FILES="ntdll.so VERSION LICENSE COPYING.LIB"

die() { echo "stage-components: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
need() { for f in "$@"; do [ -f "$f" ] || die "missing $f"; done; }
lock_get() { sed -n "s/^$1=//p" "$LOCK"; }
# The engine gw2om.sh installs: the DXMT and ntdll.so builds name its tarball's sha256
engine_sha="$(sed -n 's/^ENGINE_SHA256=\([0-9a-f]*\).*/\1/p' "$ROOT/src/gw2om.sh")"
[ -n "$engine_sha" ] || die "no ENGINE_SHA256 in src/gw2om.sh"
# record <dir>: <dir>/SHA256SUMS, every file's sha256 (shasum -c reads it)
record() {
  (cd "$1" && find . -type f ! -name 'SHA256SUMS*' | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do
    echo "$(sha "$f")  $f"
  done) >"$1/SHA256SUMS.new"
  mv "$1/SHA256SUMS.new" "$1/SHA256SUMS"
}
# check_ntdll <dir>: my ntdll.so build in <dir> is for this engine, of WINE_COMMIT if that is set,
# the file its VERSION names, and has a valid signature (the linker's: nothing signs it again before
# the engine loads it)
check_ntdll() {
  local f
  for f in $NTDLL_FILES; do need "$1/$f"; done
  grep -q "^engine: .*sha256 $engine_sha" "$1/VERSION" || die "$1/VERSION names another engine than ENGINE_SHA256 ($engine_sha)"
  [ -z "${WINE_COMMIT:-}" ] || grep -qx "commit: $WINE_COMMIT" "$1/VERSION" || die "$1/VERSION is not commit $WINE_COMMIT"
  grep -qx "ntdll.so: sha256 $(sha "$1/ntdll.so")" "$1/VERSION" || die "$1/ntdll.so is not the file its VERSION names"
  codesign --verify "$1/ntdll.so" || die "$1/ntdll.so has no valid signature"
}
# copy_ntdll <from> <to>: its files and their record
copy_ntdll() {
  local f
  mkdir -p "$2"
  for f in $NTDLL_FILES; do cp "$1/$f" "$2/$f"; done
  record "$2"
}
# fetch_pinned <url> <sha256>: the download, from .cache/<sha256>/ if it is there, checked against
# the sha256 before anything uses it; prints its path
fetch_pinned() {
  local file="$ROOT/.cache/$2/${1##*/}"
  if [ ! -f "$file" ]; then
    echo "stage-components: fetching $1" >&2
    mkdir -p "${file%/*}"
    curl -fL --retry 3 --progress-bar -o "$file.part" "$1"
    [ "$(sha "$file.part")" = "$2" ] || { rm -f "$file.part"; die "$1 does not match the sha256 in prebuilt.lock"; }
    mv "$file.part" "$file"
  fi
  [ "$(sha "$file")" = "$2" ] || die "$file does not match the sha256 in prebuilt.lock; delete it to fetch it again"
  echo "$file"
}

if [ "${1:-}" = --pack ]; then
  tag="${2:-}"
  case "$tag" in components-*) ;; *) die "usage: scripts/stage-components.sh --pack components-<date>" ;; esac
  [ -f "$P/STAGED" ] || die "no $P/ to pack; stage it from the workspace first"
  ! grep -q '^stand-in' "$P/dxmt/VERSION" 2>/dev/null || die "$P/dxmt is the stand-in; stage the real one first"
  file="gw2-on-mac-$tag.tar.xz"
  mkdir -p "$ROOT/release/$tag"
  # (my ntdll.so is its own download: the ntdll_ lines stay)
  ntdll_lines="$(grep '^ntdll_' "$LOCK" 2>/dev/null || true)"
  COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname wheel \
    --exclude ./ntdll -cJf "$ROOT/release/$tag/$file" -C "$P" .
  { sed -n '/^#/p' "$LOCK" 2>/dev/null || true
    echo "tag=$tag"
    echo "file=$file"
    echo "sha256=$(sha "$ROOT/release/$tag/$file")"
    [ -z "$ntdll_lines" ] || echo "$ntdll_lines"; } >"$LOCK.new"
  mv "$LOCK.new" "$LOCK"
  echo "release/$tag/$file ($(du -h "$ROOT/release/$tag/$file" | cut -f1)), prebuilt.lock:"
  cat "$LOCK"
  exit 0
fi

if [ "${1:-}" = --standin ]; then
  [ -f "$P/STAGED" ] || die "no $P/; stage or fetch it first"
  if [ ! -d "$P/dxmt" ]; then
    rm -rf "$P/dxmt.new" && mkdir -p "$P/dxmt.new"
    for f in $DXMT_FILES; do
      mkdir -p "$P/dxmt.new/$(dirname "$f")"
      echo "stand-in $f" >"$P/dxmt.new/$f"
    done
    echo "stand-in v0.80-0-g0000000 (not a build: scripts/stage-components.sh --standin)" >"$P/dxmt.new/VERSION"
    record "$P/dxmt.new"
    mv "$P/dxmt.new" "$P/dxmt"
    echo "dxmt stand-in by scripts/stage-components.sh --standin" >>"$P/STAGED"
  fi
  if [ ! -d "$P/ntdll" ]; then
    rm -rf "$P/ntdll.new" && mkdir -p "$P/ntdll.new"
    for f in $NTDLL_FILES; do echo "stand-in $f" >"$P/ntdll.new/$f"; done
    { echo "stand-in wine-11.21-0-g0000000 (not a build: scripts/stage-components.sh --standin)"
      echo "commit: 0000000000000000000000000000000000000000"
      echo "ntdll.so: sha256 $(sha "$P/ntdll.new/ntdll.so")"; } >"$P/ntdll.new/VERSION"
    record "$P/ntdll.new"
    mv "$P/ntdll.new" "$P/ntdll"
    echo "ntdll stand-in by scripts/stage-components.sh --standin" >>"$P/STAGED"
  fi
  cat "$P/STAGED"
  exit 0
fi

if [ "${1:-}" = --fetch ] || [ ! -d "$WS" ]; then
  [ -f "$LOCK" ] || die "no workspace at $WS and no prebuilt.lock"
  tag="$(lock_get tag)" file="$(lock_get file)" want="$(lock_get sha256)"
  [ -n "$tag" ] && [ -n "$file" ] && [ -n "$want" ] || die "prebuilt.lock needs tag=, file= and sha256="
  ntdll_url="$(lock_get ntdll_url)" ntdll_want="$(lock_get ntdll_sha256)"
  { [ -z "$ntdll_url" ] && [ -z "$ntdll_want" ]; } || { [ -n "$ntdll_url" ] && [ -n "$ntdll_want" ]; } ||
    die "prebuilt.lock needs ntdll_url= and ntdll_sha256= together"
  archive="$(fetch_pinned "https://github.com/jdrly/gw2-on-mac/releases/download/$tag/$file" "$want")"
  ntdll_archive=""
  [ -z "$ntdll_url" ] || ntdll_archive="$(fetch_pinned "$ntdll_url" "$ntdll_want")"
  rm -rf "$P.new" "$P.all" "$P.ntdll" && mkdir -p "$P.new" "$P.all"
  tar -xJf "$archive" -C "$P.all"
  mv "$P.all/ui-scale" "$P.new/"
  if [ -d "$P.all/dxmt/aarch64-windows" ]; then mv "$P.all/dxmt" "$P.new/"; fi
  rm -rf "$P.all"
  echo "fetched $file ($want) by scripts/stage-components.sh" >>"$P.new/STAGED"
  if [ -n "$ntdll_archive" ]; then
    mkdir -p "$P.ntdll"
    tar -xJf "$ntdll_archive" -C "$P.ntdll"
    check_ntdll "$P.ntdll"
    copy_ntdll "$P.ntdll" "$P.new/ntdll"
    echo "ntdll $(sed -n 's/^commit: //p' "$P.ntdll/VERSION") ntdll.so $(sha "$P.ntdll/ntdll.so"), fetched ${ntdll_url##*/} ($ntdll_want)" >>"$P.new/STAGED"
    rm -rf "$P.ntdll"
  fi
  rm -rf "$P" && mv "$P.new" "$P"
  cat "$P/STAGED"
  [ -d "$P/dxmt" ] || echo "stage-components: $file has no arm64 DXMT; scripts/stage-components.sh --standin adds a stand-in" >&2
  [ -d "$P/ntdll" ] || echo "stage-components: prebuilt.lock pins no ntdll.so; scripts/stage-components.sh --standin adds a stand-in" >&2
  exit 0
fi

WS="$(cd "$WS" && pwd)"
in_ws() { case "$1" in /*) echo "$1" ;; *) echo "$WS/$1" ;; esac; }
DXMT_BUILD="$(in_ws "${DXMT_BUILD:-work/dxmt-arm64/install}")"
NTDLL_BUILD="$(in_ws "${NTDLL_BUILD:-work/ntdll-mach9/install}")"
UISCALE_BUILD="$(in_ws "${UISCALE_BUILD:-work/ui-scale/build}")"

# DXMT: the PE DLLs and winemetal.so of one build always go together
for f in $DXMT_FILES; do need "$DXMT_BUILD/$f"; done
# Built for the engine gw2om.sh installs (VERSION's engine: line names its tarball's sha256), from
# the commit asked for (DXMT_COMMIT, a full sha; the dev build sets it), and a winemetal.so with a
# valid signature (the linker's: nothing signs it again before the engine loads it)
grep -q "^engine: .*sha256 $engine_sha" "$DXMT_BUILD/VERSION" || die "$DXMT_BUILD/VERSION names another engine than ENGINE_SHA256 ($engine_sha)"
[ -z "${DXMT_COMMIT:-}" ] || grep -qx "commit: $DXMT_COMMIT" "$DXMT_BUILD/VERSION" || die "$DXMT_BUILD/VERSION is not commit $DXMT_COMMIT"
codesign --verify "$DXMT_BUILD/aarch64-unix/winemetal.so" || die "$DXMT_BUILD/aarch64-unix/winemetal.so has no valid signature"
need "$UISCALE_BUILD/version.dll" "$UISCALE_BUILD/gw2-ui-scale.ini"
grep -aq 'gw2-on-mac ui-scale' "$UISCALE_BUILD/version.dll" || die "$UISCALE_BUILD/version.dll is not the ui-scale addon"
# My ntdll.so, if there is a build of it (WINE_COMMIT asks for one)
if [ -e "$NTDLL_BUILD" ]; then check_ntdll "$NTDLL_BUILD"
elif [ -n "${WINE_COMMIT:-}" ]; then die "no ntdll.so build at $NTDLL_BUILD for WINE_COMMIT $WINE_COMMIT"
fi

rm -rf "$P.new" && mkdir -p "$P.new/dxmt"
for f in $DXMT_FILES; do mkdir -p "$P.new/dxmt/$(dirname "$f")" && cp "$DXMT_BUILD/$f" "$P.new/dxmt/$f"; done
record "$P.new/dxmt"
[ ! -e "$NTDLL_BUILD" ] || copy_ntdll "$NTDLL_BUILD" "$P.new/ntdll"
mkdir -p "$P.new/ui-scale" && cp "$UISCALE_BUILD"/{version.dll,gw2-ui-scale.ini} "$P.new/ui-scale/"
# The record names the sources relative to the workspace (no home folder in it)
rel() { echo "${1#"$WS"/}"; }
{ echo "staged $(date '+%F %T') by scripts/stage-components.sh from ${STAGED_FROM:-the development workspace}"
  echo "dxmt $(head -1 "$DXMT_BUILD/VERSION") d3d11 $(sha "$DXMT_BUILD/aarch64-windows/d3d11.dll") winemetal.so $(sha "$DXMT_BUILD/aarch64-unix/winemetal.so") from $(rel "$DXMT_BUILD")"
  if [ -e "$NTDLL_BUILD" ]; then
    echo "ntdll $(sed -n 's/^commit: //p' "$NTDLL_BUILD/VERSION") ntdll.so $(sha "$NTDLL_BUILD/ntdll.so") from $(rel "$NTDLL_BUILD")"
  else
    echo "ntdll none (no $(rel "$NTDLL_BUILD")): the app leaves the engine's own ntdll.so in place"
  fi
  echo "ui-scale $(sha "$UISCALE_BUILD/version.dll") from $(rel "$UISCALE_BUILD")"; } >"$P.new/STAGED"
rm -rf "$P" && mv "$P.new" "$P"
cat "$P/STAGED"
