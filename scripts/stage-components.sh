#!/bin/bash
# Stages the components GW2 on Mac's app bundles into app/prebuilt/ (ignored by git: Wine and DXMT
# binaries stay out of the repository), copied from the builds this repo's scripts made in work/,
# the ones the live engine runs. Nothing in work/ is changed. app/build.sh checks prebuilt/
# against the records copied here, the way SWTOR on Mac's build.sh checks its prebuilt/.
#
#   prebuilt/dxmt/      DXMT, the jdrly/dxmt fork (scripts/build-dxmt.zsh; LGPL-2.1-or-later):
#                       x86_64-windows/, i386-windows/ (d3d11, dxgi, d3d10core, winemetal) and
#                       x86_64-unix/winemetal.so, VERSION, LICENSE, COPYING.LIB
#   prebuilt/heat/      the engine's ntdll.so with the msync fix and the heat patch, and its
#                       wineserver with the msync unregister fix (scripts/build-ntdll-heat.zsh;
#                       LGPL): ntdll.so, wineserver, VERSION, WINESERVER.txt, LICENSE, COPYING.LIB
#   prebuilt/winemac/   the engine's winemac.so with the launcher fix and win32u.so with its
#                       layered-window drawing at -O2 (scripts/build-winemac.zsh; LGPL)
#   prebuilt/ui-scale/  the interface-scale addon, version.dll and gw2-ui-scale.ini
#                       (scripts/build-ui-scale.zsh; GW2 on Mac's own code)
#
# Sources (defaults: what the live engine runs on 2026-11-04):
#   DXMT_INSTALL=work/dxmt-rollback/684f428-install   HEAT_INSTALL=work/heat/install-r7b
#   WINEMAC_INSTALL=work/winemac/install              UISCALE_BUILD=work/ui-scale/build
#
#   app/scripts/stage-components.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO="$PWD"
P="$REPO/app/prebuilt"
DXMT_INSTALL="${DXMT_INSTALL:-work/dxmt-rollback/684f428-install}"
HEAT_INSTALL="${HEAT_INSTALL:-work/heat/install-r7b}"
WINEMAC_INSTALL="${WINEMAC_INSTALL:-work/winemac/install}"
UISCALE_BUILD="${UISCALE_BUILD:-work/ui-scale/build}"

die() { echo "stage-components: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
need() { for f in "$@"; do [ -f "$f" ] || die "missing $f"; done; }

# DXMT: the PE DLLs and winemetal.so of one build always go together
need "$DXMT_INSTALL/VERSION" "$DXMT_INSTALL/LICENSE" "$DXMT_INSTALL/COPYING.LIB" "$DXMT_INSTALL/x86_64-unix/winemetal.so"
for a in x86_64-windows i386-windows; do
  for d in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll; do need "$DXMT_INSTALL/$a/$d"; done
done
# heat: the files must be the ones their records name
need "$HEAT_INSTALL/ntdll.so" "$HEAT_INSTALL/wineserver" "$HEAT_INSTALL/VERSION" "$HEAT_INSTALL/WINESERVER.txt" \
  "$HEAT_INSTALL/LICENSE" "$HEAT_INSTALL/COPYING.LIB"
grep -q "^ntdll.so sha256 $(sha "$HEAT_INSTALL/ntdll.so")" "$HEAT_INSTALL/VERSION" ||
  die "$HEAT_INSTALL/ntdll.so is not the file its VERSION names"
grep -q "^wineserver sha256 $(sha "$HEAT_INSTALL/wineserver")" "$HEAT_INSTALL/WINESERVER.txt" ||
  die "$HEAT_INSTALL/wineserver is not the file its WINESERVER.txt names"
grep -q "patches/ntdll-heat.patch sha256 $(sha patches/ntdll-heat.patch)" "$HEAT_INSTALL/VERSION" ||
  die "$HEAT_INSTALL was not built from patches/ntdll-heat.patch as it is now"
need "$WINEMAC_INSTALL/winemac.so" "$WINEMAC_INSTALL/win32u.so" "$WINEMAC_INSTALL/VERSION" \
  "$WINEMAC_INSTALL/LICENSE" "$WINEMAC_INSTALL/COPYING.LIB"
for l in winemac.so win32u.so; do
  grep -q "sha256 $(sha "$WINEMAC_INSTALL/$l")" "$WINEMAC_INSTALL/VERSION" || die "$WINEMAC_INSTALL/$l is not the file its VERSION names"
done
grep -q "patches/winemac-gw2-launcher.patch sha256 $(sha patches/winemac-gw2-launcher.patch)" "$WINEMAC_INSTALL/VERSION" ||
  die "$WINEMAC_INSTALL was not built from patches/winemac-gw2-launcher.patch as it is now"
need "$UISCALE_BUILD/version.dll" "$UISCALE_BUILD/gw2-ui-scale.ini"
grep -aq 'gw2-on-mac ui-scale' "$UISCALE_BUILD/version.dll" || die "$UISCALE_BUILD/version.dll is not the ui-scale addon"

rm -rf "$P.new" && mkdir -p "$P.new"
mkdir -p "$P.new/dxmt" && cp -R "$DXMT_INSTALL/x86_64-windows" "$DXMT_INSTALL/i386-windows" "$DXMT_INSTALL/x86_64-unix" \
  "$DXMT_INSTALL/VERSION" "$DXMT_INSTALL/LICENSE" "$DXMT_INSTALL/COPYING.LIB" "$P.new/dxmt/"
mkdir -p "$P.new/heat" && cp "$HEAT_INSTALL"/{ntdll.so,wineserver,VERSION,WINESERVER.txt,LICENSE,COPYING.LIB} "$P.new/heat/"
mkdir -p "$P.new/winemac" && cp "$WINEMAC_INSTALL"/{winemac.so,win32u.so,VERSION,LICENSE,COPYING.LIB} "$P.new/winemac/"
mkdir -p "$P.new/ui-scale" && cp "$UISCALE_BUILD"/{version.dll,gw2-ui-scale.ini} "$P.new/ui-scale/"
{ echo "staged $(date '+%F %T') by app/scripts/stage-components.sh"
  echo "dxmt $(cat "$DXMT_INSTALL/VERSION") from $DXMT_INSTALL"
  echo "heat $(sha "$HEAT_INSTALL/ntdll.so") wineserver $(sha "$HEAT_INSTALL/wineserver") from $HEAT_INSTALL"
  echo "winemac $(sha "$WINEMAC_INSTALL/winemac.so") win32u $(sha "$WINEMAC_INSTALL/win32u.so") from $WINEMAC_INSTALL"
  echo "ui-scale $(sha "$UISCALE_BUILD/version.dll") from $UISCALE_BUILD"; } >"$P.new/STAGED"
rm -rf "$P" && mv "$P.new" "$P"
cat "$P/STAGED"
