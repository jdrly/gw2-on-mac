#!/bin/bash
# Stages the components GW2 on Mac's app bundles into prebuilt/ (ignored by git: Wine and DXMT
# binaries stay out of the repository), copied from the builds in the development workspace's
# work/, the ones the live engine runs. Nothing in the workspace is changed. build.sh checks
# prebuilt/ against the records copied here, the way SWTOR on Mac's build.sh checks its prebuilt/.
#
# Only Jan's private development workspace (GW2_ON_MAC_WORKSPACE) builds these binaries today; its
# build scripts are not part of this repository. What they build from is public: the complete
# corresponding source of each LGPL component is its pinned upstream plus this repository's
# patches/ (see THIRD_PARTY_NOTICES.md), and each component's VERSION record names both.
#
#   prebuilt/dxmt/      DXMT, the jdrly/dxmt fork (LGPL-2.1-or-later): x86_64-windows/,
#                       i386-windows/ (d3d11, dxgi, d3d10core, winemetal) and
#                       x86_64-unix/winemetal.so, VERSION, LICENSE, COPYING.LIB
#   prebuilt/heat/      the engine's ntdll.so with patches/ntdll-msync-alert-fd.patch and
#                       patches/ntdll-heat.patch, and its wineserver with
#                       patches/wineserver-msync-unregister.patch (LGPL): ntdll.so, wineserver,
#                       VERSION, WINESERVER.txt, LICENSE, COPYING.LIB
#   prebuilt/winemac/   Wine's Mac driver: the engine's winemac.so with patches/winemac-gw2-launcher.patch
#                       and SWTOR on Mac's keyboard and mouse patches (winemac-physical-keys,
#                       winemac-swgl-relative-mouse, winemac-swgl-input-thread, winemac-swtor-mouse),
#                       its PE sides x86_64-windows/ and i386-windows/winemac.drv (the same build),
#                       and win32u.so with its layered-window drawing at -O2 (LGPL)
#   prebuilt/ui-scale/  the interface-scale addon, version.dll and gw2-ui-scale.ini (GW2 on Mac's
#                       own code, addon/ui-scale; scripts/build-addon.sh builds the same thing)
#
# Sources: GW2_ON_MAC_WORKSPACE (default ../gw2-on-mac, next to this repository) and in it
# (defaults: the live engine's builds on 2026-11-04, DXMT the fork's e02a4d6: DXMT_CACHE_DIR, and the exit-crash fix #139;
# the Mac driver: the workspace's scripts/build-winemac.zsh --km of 2026-11-05):
#   DXMT_INSTALL=work/dxmt-rollback/e02a4d6-install   HEAT_INSTALL=work/heat/install-r7c
#   WINEMAC_INSTALL=work/winemac/install-km           UISCALE_BUILD=work/ui-scale/build
# (relative to the workspace, or absolute)
#
#   scripts/stage-components.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
P="$ROOT/prebuilt"
WS="${GW2_ON_MAC_WORKSPACE:-$ROOT/../gw2-on-mac}"
[ -d "$WS" ] || { echo "stage-components: no workspace at $WS (set GW2_ON_MAC_WORKSPACE)" >&2; exit 1; }
WS="$(cd "$WS" && pwd)"
in_ws() { case "$1" in /*) echo "$1" ;; *) echo "$WS/$1" ;; esac; }
DXMT_INSTALL="$(in_ws "${DXMT_INSTALL:-work/dxmt-rollback/e02a4d6-install}")"
HEAT_INSTALL="$(in_ws "${HEAT_INSTALL:-work/heat/install-r7c}")"
WINEMAC_INSTALL="$(in_ws "${WINEMAC_INSTALL:-work/winemac/install-km}")"
UISCALE_BUILD="$(in_ws "${UISCALE_BUILD:-work/ui-scale/build}")"

die() { echo "stage-components: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
need() { for f in "$@"; do [ -f "$f" ] || die "missing $f"; done; }

# DXMT: the PE DLLs and winemetal.so of one build always go together
need "$DXMT_INSTALL/VERSION" "$DXMT_INSTALL/LICENSE" "$DXMT_INSTALL/COPYING.LIB" "$DXMT_INSTALL/x86_64-unix/winemetal.so"
for a in x86_64-windows i386-windows; do
  for d in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll; do need "$DXMT_INSTALL/$a/$d"; done
done
# heat: the files must be the ones their records name, built from this repository's patches
need "$HEAT_INSTALL/ntdll.so" "$HEAT_INSTALL/wineserver" "$HEAT_INSTALL/VERSION" "$HEAT_INSTALL/WINESERVER.txt" \
  "$HEAT_INSTALL/LICENSE" "$HEAT_INSTALL/COPYING.LIB"
grep -q "^ntdll.so sha256 $(sha "$HEAT_INSTALL/ntdll.so")" "$HEAT_INSTALL/VERSION" ||
  die "$HEAT_INSTALL/ntdll.so is not the file its VERSION names"
grep -q "^wineserver sha256 $(sha "$HEAT_INSTALL/wineserver")" "$HEAT_INSTALL/WINESERVER.txt" ||
  die "$HEAT_INSTALL/wineserver is not the file its WINESERVER.txt names"
for p in ntdll-heat.patch ntdll-msync-alert-fd.patch; do
  grep -q "patches/$p sha256 $(sha "patches/$p")" "$HEAT_INSTALL/VERSION" ||
    die "$HEAT_INSTALL was not built from patches/$p as it is now"
done
# the Mac driver: winemac.so and its PE sides go together (the PE sides start raw mouse-look's
# input thread, which only this winemac.so has)
WINEMAC_FILES="winemac.so x86_64-windows/winemac.drv i386-windows/winemac.drv win32u.so"
WINEMAC_PATCHES="winemac-gw2-launcher.patch winemac-physical-keys.patch winemac-swgl-relative-mouse.patch winemac-swgl-input-thread.patch winemac-swtor-mouse.patch"
for f in $WINEMAC_FILES VERSION LICENSE COPYING.LIB; do need "$WINEMAC_INSTALL/$f"; done
for f in $WINEMAC_FILES; do
  grep -q "sha256 $(sha "$WINEMAC_INSTALL/$f")" "$WINEMAC_INSTALL/VERSION" || die "$WINEMAC_INSTALL/$f is not the file its VERSION names"
done
for p in $WINEMAC_PATCHES; do
  grep -q "patches/$p sha256 $(sha "patches/$p")" "$WINEMAC_INSTALL/VERSION" ||
    die "$WINEMAC_INSTALL was not built from patches/$p as it is now"
done
# the workspace's patches must be this repository's (the same content)
for p in ntdll-heat.patch wineserver-msync-unregister.patch $WINEMAC_PATCHES; do
  [ ! -f "$WS/patches/$p" ] || cmp -s "$WS/patches/$p" "patches/$p" || die "$WS/patches/$p differs from patches/$p"
done
need "$UISCALE_BUILD/version.dll" "$UISCALE_BUILD/gw2-ui-scale.ini"
grep -aq 'gw2-on-mac ui-scale' "$UISCALE_BUILD/version.dll" || die "$UISCALE_BUILD/version.dll is not the ui-scale addon"

rm -rf "$P.new" && mkdir -p "$P.new"
mkdir -p "$P.new/dxmt" && cp -R "$DXMT_INSTALL/x86_64-windows" "$DXMT_INSTALL/i386-windows" "$DXMT_INSTALL/x86_64-unix" \
  "$DXMT_INSTALL/VERSION" "$DXMT_INSTALL/LICENSE" "$DXMT_INSTALL/COPYING.LIB" "$P.new/dxmt/"
mkdir -p "$P.new/heat" && cp "$HEAT_INSTALL"/{ntdll.so,wineserver,VERSION,WINESERVER.txt,LICENSE,COPYING.LIB} "$P.new/heat/"
mkdir -p "$P.new/winemac/x86_64-windows" "$P.new/winemac/i386-windows"
for f in $WINEMAC_FILES VERSION LICENSE COPYING.LIB; do cp "$WINEMAC_INSTALL/$f" "$P.new/winemac/$f"; done
mkdir -p "$P.new/ui-scale" && cp "$UISCALE_BUILD"/{version.dll,gw2-ui-scale.ini} "$P.new/ui-scale/"
# The record names the sources relative to the workspace (no home folder in it)
rel() { echo "${1#"$WS"/}"; }
{ echo "staged $(date '+%F %T') by scripts/stage-components.sh from the development workspace"
  echo "dxmt $(cat "$DXMT_INSTALL/VERSION") from $(rel "$DXMT_INSTALL")"
  echo "heat $(sha "$HEAT_INSTALL/ntdll.so") wineserver $(sha "$HEAT_INSTALL/wineserver") from $(rel "$HEAT_INSTALL")"
  echo "winemac $(sha "$WINEMAC_INSTALL/winemac.so") pe64 $(sha "$WINEMAC_INSTALL/x86_64-windows/winemac.drv") pe32 $(sha "$WINEMAC_INSTALL/i386-windows/winemac.drv") win32u $(sha "$WINEMAC_INSTALL/win32u.so") from $(rel "$WINEMAC_INSTALL")"
  echo "ui-scale $(sha "$UISCALE_BUILD/version.dll") from $(rel "$UISCALE_BUILD")"; } >"$P.new/STAGED"
rm -rf "$P" && mv "$P.new" "$P"
cat "$P/STAGED"
