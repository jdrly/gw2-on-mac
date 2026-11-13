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
#   prebuilt/macdrv/    my Mac driver's winemac.so (jdrly/wine, LGPL-2.1-or-later) built for this
#                       line's engine (#57), from the same commit's run: the same files with
#                       "winemac.so: sha256" in its VERSION, and win32u.so with its own "win32u.so:
#                       sha256" line when the build has one (jdrly/wine#61). gw2om.sh puts the two
#                       into the engine as one set, the engine's own kept next to each. Optional, as
#                       ntdll/ is.
#   prebuilt/fex/       my FEX (jdrly/FEX, MIT, with the notices of what it links) built for
#                       this line's engine (#110), its ARM64EC half in the engine's layout:
#                       aarch64-windows/libarm64ecfex.dll and aarch64-unix/libarm64ecfex.so, with
#                       VERSION (its "commit:", "base:", "engine:" and "<file>: sha256" lines name
#                       the fork's commit, the engine's FEX commit it starts from, the engine's
#                       tarball and the files as built; "switches:" the FEX_* options my commits
#                       add), LICENSE and NOTICES, and SHA256SUMS, the record this script writes.
#                       gw2om.sh puts it into the engine after `set fex mine`, the engine's own
#                       kept next to it. Its WoW64 half is not staged. Optional, as ntdll/ is.
#   prebuilt/ui-scale/  the interface-scale addon, version.dll and gw2-ui-scale.ini (the app's
#                       own code, addon/ui-scale; scripts/build-addon.sh builds the same thing)
#
# 0.1.x's Wine builds (heat/ and winemac/) are not staged on this line.
#
# Sources: GW2_ON_MAC_WORKSPACE (default ../gw2-on-mac, next to this repository) and in it
# DXMT_BUILD=work/dxmt-arm64/install (the fork's CI artifact, unpacked),
# NTDLL_BUILD=work/ntdll-arm64/install (jdrly/wine's asset ntdll-arm64-<commit>.tar.xz, unpacked;
# without it no ntdll/), MACDRV_BUILD=work/macdrv-arm64/install (its asset
# macdrv-arm64-<commit>.tar.xz, unpacked; without it no macdrv/) and
# FEX_BUILD=work/fex-arm64/install (jdrly/FEX's asset fex-arm64-<commit>.tar.xz, unpacked; without
# it no fex/) and UISCALE_BUILD=work/ui-scale/build (relative to the workspace, or absolute). It
# refuses a DXMT build, a Wine build or a FEX build of mine for another engine than
# src/gw2om.sh's ENGINE_SHA256, a Wine build on another base than its ENGINE_WINE, a FEX build on
# another base than its ENGINE_FEX, a winemetal.so, ntdll.so, winemac.so or libarm64ecfex.so
# without a valid signature, an ntdll.so, winemac.so or FEX file that isn't the file its VERSION
# names, and, with DXMT_COMMIT, WINE_COMMIT (ntdll.so), MACDRV_COMMIT (winemac.so) or FEX_COMMIT
# set, a build of another commit (or, for the Wine and FEX ones, none). STAGED_FROM replaces "the development workspace" in the first line of
# prebuilt/STAGED (the dev build workflow names the fork's commit and where its files came from).
#
# Without the workspace (GitHub's runners), or with --fetch, it downloads the files instead, each
# checked against its sha256 in prebuilt.lock before anything is unpacked: one archive, a
# pre-release of this repository pinned by tag, file name and sha256, of which only ui-scale/ and
# an arm64 dxmt/ are kept (0.1.x's archives have an x86_64 dxmt/, which isn't), and the archives of
# my ntdll.so, my Mac driver and my FEX, pinned by ntdll_url and ntdll_sha256, macdrv_url and
# macdrv_sha256, fex_url and fex_sha256 when prebuilt.lock has them, checked as above. --pack <tag>
# makes that one archive from prebuilt/ as staged, without ntdll/, macdrv/ and fex/, into
# release/<tag>/, and writes prebuilt.lock for it, keeping its ntdll_, macdrv_ and fex_ lines;
# README.md (Building) says how I publish it.
#
# --standin adds a stand-in for each of dxmt/, ntdll/, macdrv/ and fex/ that prebuilt/ lacks (files
# in the layout of the fork's build that only name themselves), for the checks and the sandbox
# until prebuilt.lock pins the real ones. build.sh takes them; scripts/release.sh refuses them.
# Their VERSIONs' switches: lines are the real builds' (jdrly/wine 472d7774368, jdrly/FEX
# c2e25accebc), so a pull request's sandbox reads the switches a dev build's does: when a build
# drops or adds one, these lines change with it.
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
# My Wine builds, each an archive of jdrly/wine with its files at the root: ntdll (ntdll.so) and
# macdrv (my Mac driver, winemac.so, and win32u.so when its build has one)
WINE_KINDS="ntdll macdrv"
# wine_kind <kind>: WK_FILE, the library; WK_COMMIT, the commit asked for (WINE_COMMIT or
# MACDRV_COMMIT, or none); WK_BUILD, the unpacked build in the workspace
wine_kind() {
  case "$1" in
    ntdll) WK_FILE=ntdll.so WK_COMMIT="${WINE_COMMIT:-}" WK_BUILD="${NTDLL_BUILD:-work/ntdll-arm64/install}" ;;
    macdrv) WK_FILE=winemac.so WK_COMMIT="${MACDRV_COMMIT:-}" WK_BUILD="${MACDRV_BUILD:-work/macdrv-arm64/install}" ;;
  esac
}

die() { echo "stage-components: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
need() { for f in "$@"; do [ -f "$f" ] || die "missing $f"; done; }
lock_get() { sed -n "s/^$1=//p" "$LOCK"; }
# The engine gw2om.sh installs: the DXMT and Wine builds name its tarball's sha256
engine_sha="$(sed -n 's/^ENGINE_SHA256=\([0-9a-f]*\).*/\1/p' "$ROOT/src/gw2om.sh")"
[ -n "$engine_sha" ] || die "no ENGINE_SHA256 in src/gw2om.sh"
# and the commit of athei/wine it was built from, which my Wine builds' VERSION names as their base
engine_wine="$(sed -n 's/^ENGINE_WINE=\([0-9a-f]*\).*/\1/p' "$ROOT/src/gw2om.sh")"
[ -n "$engine_wine" ] || die "no ENGINE_WINE in src/gw2om.sh"
# record <dir>: <dir>/SHA256SUMS, every file's sha256 (shasum -c reads it)
record() {
  (cd "$1" && find . -type f ! -name 'SHA256SUMS*' | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do
    echo "$(sha "$f")  $f"
  done) >"$1/SHA256SUMS.new"
  mv "$1/SHA256SUMS.new" "$1/SHA256SUMS"
}
# wine_libs <kind> <dir>: the libraries of my Wine build in <dir>: WK_FILE, and for my Mac driver
# win32u.so too when the build has it or its VERSION names it (need refuses it missing)
wine_libs() {
  wine_kind "$1"
  echo "$WK_FILE"
  [ "$1" = macdrv ] || return 0
  if [ -e "$2/win32u.so" ] || grep -q '^win32u\.so: sha256 ' "$2/VERSION" 2>/dev/null; then echo win32u.so; fi
}
# check_wine <kind> <dir>: my Wine build in <dir> is for this engine and on its Wine, of the commit
# asked for if one is, its libraries the files its VERSION names, each with a valid signature (the
# linker's: nothing signs it again before the engine loads it)
check_wine() {
  local f libs
  wine_kind "$1"
  libs=$(wine_libs "$1" "$2")
  for f in $libs VERSION LICENSE COPYING.LIB; do need "$2/$f"; done
  grep -q "^engine: .*sha256 $engine_sha" "$2/VERSION" || die "$2/VERSION names another engine than ENGINE_SHA256 ($engine_sha)"
  grep -q "^base: $engine_wine" "$2/VERSION" || die "$2/VERSION names another base than ENGINE_WINE ($engine_wine)"
  [ -z "$WK_COMMIT" ] || grep -qx "commit: $WK_COMMIT" "$2/VERSION" || die "$2/VERSION is not commit $WK_COMMIT"
  for f in $libs; do
    grep -qx "$f: sha256 $(sha "$2/$f")" "$2/VERSION" || die "$2/$f is not the file its VERSION names"
    codesign --verify "$2/$f" || die "$2/$f has no valid signature"
  done
}
# copy_wine <kind> <from> <to>: its files and their record
copy_wine() {
  local f
  mkdir -p "$3"
  for f in $(wine_libs "$1" "$2") VERSION LICENSE COPYING.LIB; do cp "$2/$f" "$3/$f"; done
  record "$3"
}
# wine_line <kind> <dir>: its line in STAGED, without the source: "<kind> <commit> <file> <sha256>
# ..." for each library
wine_line() {
  local f line
  line="$1 $(sed -n 's/^commit: //p' "$2/VERSION")"
  for f in $(wine_libs "$1" "$2"); do line="$line $f $(sha "$2/$f")"; done
  echo "$line"
}
# My FEX: its ARM64EC half from jdrly/FEX's archive (the WoW64 half isn't staged), and the record
FEX_FILES="aarch64-windows/libarm64ecfex.dll aarch64-unix/libarm64ecfex.so"
FEX_META="VERSION LICENSE NOTICES"
engine_fex="$(sed -n 's/^ENGINE_FEX=\([0-9a-f]*\).*/\1/p' "$ROOT/src/gw2om.sh")"
[ -n "$engine_fex" ] || die "no ENGINE_FEX in src/gw2om.sh"
# check_fex <dir>: my FEX build in <dir> (jdrly/FEX's archive, unpacked) is for this engine and on
# its FEX, of FEX_COMMIT if that is set, its files are the ones its VERSION names, and its .so has a
# valid signature (the linker's: nothing signs it again before the engine loads it)
check_fex() {
  local f
  for f in $FEX_FILES $FEX_META; do need "$1/$f"; done
  grep -q "^engine: .*sha256 $engine_sha" "$1/VERSION" || die "$1/VERSION names another engine than ENGINE_SHA256 ($engine_sha)"
  grep -q "^base: $engine_fex" "$1/VERSION" || die "$1/VERSION names another base than ENGINE_FEX ($engine_fex)"
  [ -z "${FEX_COMMIT:-}" ] || grep -qx "commit: $FEX_COMMIT" "$1/VERSION" || die "$1/VERSION is not commit $FEX_COMMIT"
  for f in $FEX_FILES; do
    grep -qx "$f: sha256 $(sha "$1/$f")" "$1/VERSION" || die "$1/$f is not the file its VERSION names"
  done
  codesign --verify "$1/aarch64-unix/libarm64ecfex.so" || die "$1/aarch64-unix/libarm64ecfex.so has no valid signature"
}
# copy_fex <from> <to>: its files and their record
copy_fex() {
  local f
  for f in $FEX_FILES $FEX_META; do mkdir -p "$2/$(dirname "$f")" && cp "$1/$f" "$2/$f"; done
  record "$2"
}
# fex_line <dir>: its line in STAGED
fex_line() { echo "fex $(sed -n 's/^commit: //p' "$1/VERSION") libarm64ecfex.dll $(sha "$1/aarch64-windows/libarm64ecfex.dll")"; }
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
  # (my Wine builds and my FEX are downloads of their own: the ntdll_, macdrv_ and fex_ lines stay)
  wine_lines="$(grep -E '^(ntdll|macdrv|fex)_' "$LOCK" 2>/dev/null || true)"
  COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname wheel \
    --exclude ./ntdll --exclude ./macdrv --exclude ./fex -cJf "$ROOT/release/$tag/$file" -C "$P" .
  { sed -n '/^#/p' "$LOCK" 2>/dev/null || true
    echo "tag=$tag"
    echo "file=$file"
    echo "sha256=$(sha "$ROOT/release/$tag/$file")"
    [ -z "$wine_lines" ] || echo "$wine_lines"; } >"$LOCK.new"
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
  for k in $WINE_KINDS; do
    [ ! -d "$P/$k" ] || continue
    wine_kind "$k"
    rm -rf "$P/$k.new" && mkdir -p "$P/$k.new"
    for f in $WK_FILE VERSION LICENSE COPYING.LIB; do echo "stand-in $f" >"$P/$k.new/$f"; done
    { echo "stand-in wine-11.21-0-g0000000 (not a build: scripts/stage-components.sh --standin)"
      echo "commit: 0000000000000000000000000000000000000000"
      case "$k" in
        ntdll) echo "switches: WINE_HEAT_COUNT WINE_HEAT_EVPOOL WINE_HEAT_EXE WINE_HEAT_LOG WINE_HEAT_PROF WINE_HEAT_PROF_FEX WINE_HEAT_PROF_HZ WINE_HEAT_PROF_THREADS WINE_HEAT_SPIN WINE_HEAT_SPIN_PAUSE WINE_HEAT_WAKE" ;;
        macdrv) echo "switches: WINE_MACDRV_CALL WINE_MACDRV_CLIP WINE_MACDRV_DRAIN WINE_MACDRV_MOUSE_SCALE WINE_MACDRV_SURFACE WINE_MACDRV_VIEW WINE_WIN32U_PEEK_YIELD WINE_WIN32U_SETCURSOR" ;;
      esac
      echo "$WK_FILE: sha256 $(sha "$P/$k.new/$WK_FILE")"; } >"$P/$k.new/VERSION"
    record "$P/$k.new"
    mv "$P/$k.new" "$P/$k"
    echo "$k stand-in by scripts/stage-components.sh --standin" >>"$P/STAGED"
  done
  if [ ! -d "$P/fex" ]; then
    rm -rf "$P/fex.new" && mkdir -p "$P/fex.new"
    for f in $FEX_FILES $FEX_META; do mkdir -p "$P/fex.new/$(dirname "$f")" && echo "stand-in $f" >"$P/fex.new/$f"; done
    { echo "stand-in FEX-2610-0-g0000000 (not a build: scripts/stage-components.sh --standin)"
      echo "commit: 0000000000000000000000000000000000000000"
      echo "switches: FEX_DISPATCHERL1LOOKUP FEX_ENTRYHEADERLOOKUP FEX_HARDWARETSOSYSCALLS FEX_INITIALCODEBUFFERMB"
      for f in $FEX_FILES; do echo "$f: sha256 $(sha "$P/fex.new/$f")"; done
      echo "libarm64ecfex.dll: build id 0123456789abcdef0123456789abcdef age 1, SizeOfImage 0x426000"; } >"$P/fex.new/VERSION"
    record "$P/fex.new"
    mv "$P/fex.new" "$P/fex"
    echo "fex stand-in by scripts/stage-components.sh --standin" >>"$P/STAGED"
  fi
  cat "$P/STAGED"
  exit 0
fi

if [ "${1:-}" = --fetch ] || [ ! -d "$WS" ]; then
  [ -f "$LOCK" ] || die "no workspace at $WS and no prebuilt.lock"
  tag="$(lock_get tag)" file="$(lock_get file)" want="$(lock_get sha256)"
  [ -n "$tag" ] && [ -n "$file" ] && [ -n "$want" ] || die "prebuilt.lock needs tag=, file= and sha256="
  for k in $WINE_KINDS fex; do
    url="$(lock_get "${k}_url")" sum="$(lock_get "${k}_sha256")"
    { [ -z "$url" ] && [ -z "$sum" ]; } || { [ -n "$url" ] && [ -n "$sum" ]; } ||
      die "prebuilt.lock needs ${k}_url= and ${k}_sha256= together"
  done
  archive="$(fetch_pinned "https://github.com/jdrly/gw2-on-mac/releases/download/$tag/$file" "$want")"
  rm -rf "$P.new" "$P.all" "$P.wine" && mkdir -p "$P.new" "$P.all"
  tar -xJf "$archive" -C "$P.all"
  mv "$P.all/ui-scale" "$P.new/"
  if [ -d "$P.all/dxmt/aarch64-windows" ]; then mv "$P.all/dxmt" "$P.new/"; fi
  rm -rf "$P.all"
  echo "fetched $file ($want) by scripts/stage-components.sh" >>"$P.new/STAGED"
  for k in $WINE_KINDS; do
    url="$(lock_get "${k}_url")" sum="$(lock_get "${k}_sha256")"
    [ -n "$url" ] || continue
    wine_archive="$(fetch_pinned "$url" "$sum")"
    wine_kind "$k"
    mkdir -p "$P.wine"
    tar -xJf "$wine_archive" -C "$P.wine"
    check_wine "$k" "$P.wine"
    copy_wine "$k" "$P.wine" "$P.new/$k"
    echo "$(wine_line "$k" "$P.wine"), fetched ${url##*/} ($sum)" >>"$P.new/STAGED"
    rm -rf "$P.wine"
  done
  url="$(lock_get fex_url)" sum="$(lock_get fex_sha256)"
  if [ -n "$url" ]; then
    fex_archive="$(fetch_pinned "$url" "$sum")"
    rm -rf "$P.fex" && mkdir -p "$P.fex"
    tar -xJf "$fex_archive" -C "$P.fex"
    check_fex "$P.fex"
    copy_fex "$P.fex" "$P.new/fex"
    echo "$(fex_line "$P.fex"), fetched ${url##*/} ($sum)" >>"$P.new/STAGED"
    rm -rf "$P.fex"
  fi
  rm -rf "$P" && mv "$P.new" "$P"
  cat "$P/STAGED"
  [ -d "$P/dxmt" ] || echo "stage-components: $file has no arm64 DXMT; scripts/stage-components.sh --standin adds a stand-in" >&2
  for k in $WINE_KINDS; do
    wine_kind "$k"
    [ -d "$P/$k" ] || echo "stage-components: prebuilt.lock pins no $WK_FILE; scripts/stage-components.sh --standin adds a stand-in" >&2
  done
  [ -d "$P/fex" ] || echo "stage-components: prebuilt.lock pins no FEX of mine; scripts/stage-components.sh --standin adds a stand-in" >&2
  exit 0
fi

WS="$(cd "$WS" && pwd)"
in_ws() { case "$1" in /*) echo "$1" ;; *) echo "$WS/$1" ;; esac; }
DXMT_BUILD="$(in_ws "${DXMT_BUILD:-work/dxmt-arm64/install}")"
UISCALE_BUILD="$(in_ws "${UISCALE_BUILD:-work/ui-scale/build}")"
FEX_BUILD="$(in_ws "${FEX_BUILD:-work/fex-arm64/install}")"

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
# My ntdll.so and my Mac driver, each if there is a build of it (WINE_COMMIT and MACDRV_COMMIT ask
# for one)
for k in $WINE_KINDS; do
  wine_kind "$k"
  b="$(in_ws "$WK_BUILD")"
  if [ -e "$b" ]; then check_wine "$k" "$b"
  elif [ -n "$WK_COMMIT" ]; then die "no $WK_FILE build at $b for commit $WK_COMMIT"
  fi
done
# My FEX, if there is a build of it (FEX_COMMIT asks for one)
if [ -e "$FEX_BUILD" ]; then check_fex "$FEX_BUILD"
elif [ -n "${FEX_COMMIT:-}" ]; then die "no FEX build at $FEX_BUILD for commit $FEX_COMMIT"
fi

rm -rf "$P.new" && mkdir -p "$P.new/dxmt"
for f in $DXMT_FILES; do mkdir -p "$P.new/dxmt/$(dirname "$f")" && cp "$DXMT_BUILD/$f" "$P.new/dxmt/$f"; done
record "$P.new/dxmt"
for k in $WINE_KINDS; do
  wine_kind "$k"
  b="$(in_ws "$WK_BUILD")"
  [ ! -e "$b" ] || copy_wine "$k" "$b" "$P.new/$k"
done
[ ! -e "$FEX_BUILD" ] || copy_fex "$FEX_BUILD" "$P.new/fex"
mkdir -p "$P.new/ui-scale" && cp "$UISCALE_BUILD"/{version.dll,gw2-ui-scale.ini} "$P.new/ui-scale/"
# The record names the sources relative to the workspace (no home folder in it)
rel() { echo "${1#"$WS"/}"; }
{ echo "staged $(date '+%F %T') by scripts/stage-components.sh from ${STAGED_FROM:-the development workspace}"
  echo "dxmt $(head -1 "$DXMT_BUILD/VERSION") d3d11 $(sha "$DXMT_BUILD/aarch64-windows/d3d11.dll") winemetal.so $(sha "$DXMT_BUILD/aarch64-unix/winemetal.so") from $(rel "$DXMT_BUILD")"
  for k in $WINE_KINDS; do
    wine_kind "$k"
    b="$(in_ws "$WK_BUILD")"
    if [ -e "$b" ]; then
      echo "$(wine_line "$k" "$b") from $(rel "$b")"
    else
      echo "$k none (no $(rel "$b")): the app leaves the engine's own $WK_FILE in place"
    fi
  done
  if [ -e "$FEX_BUILD" ]; then echo "$(fex_line "$FEX_BUILD") from $(rel "$FEX_BUILD")"
  else echo "fex none (no $(rel "$FEX_BUILD")): the app leaves the engine's own FEX in place"
  fi
  echo "ui-scale $(sha "$UISCALE_BUILD/version.dll") from $(rel "$UISCALE_BUILD")"; } >"$P.new/STAGED"
rm -rf "$P" && mv "$P.new" "$P"
cat "$P/STAGED"
