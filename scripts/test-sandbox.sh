#!/bin/bash
# End-to-end test of the backend (Resources/gw2om.sh of a built app) in a sandbox, without the real
# Wine and without touching anything outside the sandbox: GW2_ON_MAC_ROOT puts every path the app
# uses under $SANDBOX, and the engine is a stand-in archive whose bin/wine only pretends (it makes
# a bottle's files for wineboot, "installs" Steam for SteamSetup.exe /S and logs every start with
# its environment). Steam's and ArenaNet's downloads of the game are played by this script
# (Steam's appmanifest, the game folder). Processes for the busy checks are copies of /bin/sleep
# at the engine's paths. The ArenaNet installer is a clone of a file signed by ArenaNet (by
# default the game's own Gw2-64.exe from my development workspace's bottle, only read; without
# one, those checks are skipped).
#
#   scripts/test-sandbox.sh [path/to/the app]
#
# Env: SANDBOX (default work/app-sandbox/test in this repository, removed first), KEEP=1 (leave it
#      for a look), SIGNED_PE (an x86_64 PE signed by ArenaNet; default the game's Gw2-64.exe in
#      $GW2_ON_MAC_WORKSPACE/work/bottles, the workspace defaulting to ../gw2-on-mac)
# Runs under macOS's /bin/bash 3.2.
# Many variables are read only inside the strings that check() evals, which shellcheck can't see.
# shellcheck disable=SC2034
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
# The name the app shows, from gw2om.sh, and its name on disk, written out here: the folders of
# every install before, which a new build must find where they are
APP_NAME="$(sed -n 's/^APP_NAME="\(.*\)"$/\1/p' src/gw2om.sh)"
[ -n "$APP_NAME" ] || { echo "No APP_NAME=\"…\" line in src/gw2om.sh" >&2; exit 1; }
APP_FOLDER="GW2 on Mac arm64"
WS="${GW2_ON_MAC_WORKSPACE:-$ROOT/../gw2-on-mac}"
APP="$(cd "${1:-dist/$APP_FOLDER.app}" && pwd)"
G="$APP/Contents/Resources/gw2om.sh"
[ -f "$G" ] || { echo "no $G; run ./build.sh" >&2; exit 1; }
GW2OM="$G"
SANDBOX="${SANDBOX:-$ROOT/work/app-sandbox/test}"
case "$SANDBOX" in "$ROOT"/work/app-sandbox/*) ;; *) echo "SANDBOX must be under work/app-sandbox/" >&2; exit 1 ;; esac
# (the checks' files after a failure)
FAILED="$SANDBOX.failed"
SIGNED_PE="${SIGNED_PE:-$WS/work/bottles/gw2/drive_c/Program Files (x86)/Steam/steamapps/common/Guild Wars 2/Gw2-64.exe}"
# the stand-in processes (sleepers) and watchers of an earlier run of this sandbox, and of this one
# at its end
end_sandbox_processes() { [ ! -d "$SANDBOX" ] || pkill -f "^$(cd "$SANDBOX" && pwd -P)/" 2>/dev/null || true; pkill -f "^/bin/bash $GW2OM watch-session" 2>/dev/null || true; }
end_sandbox_processes
rm -rf "$SANDBOX" "$FAILED"
mkdir -p "$SANDBOX"
SANDBOX="$(cd "$SANDBOX" && pwd -P)"
H="$SANDBOX/home"
AD="$H/Library/Application Support/$APP_FOLDER"
LOGS="$H/Library/Logs/$APP_FOLDER"
CACHE="$H/Library/Caches/$APP_FOLDER"
ENG="$AD/engine"
BOTTLE="$AD/bottle"
STEAM="$BOTTLE/drive_c/Program Files (x86)/Steam"
# DXMT's caches for the game: my fork's (the default), the engine's DXMT's
DXMT_CACHE="$CACHE/fork/dxmt/Gw2-64.exe"
DXMT_CACHE_ENGINE="$CACHE/dxmt/Gw2-64.exe"
STANDIN_LOG="$SANDBOX/standin.log"
COMP="$APP/Contents/Resources/components"
# The ntdll.so the app puts into the engine by default: mine when the app has a build of it (the
# checks' stand-in), else the engine's own (a dev build without one: the app leaves it in place)
if [ -f "$COMP/ntdll/ntdll.so" ]; then MYWINE=mine; else MYWINE=engine; fi
# the commit of the app's build (its VERSION's commit: line), and the engine's Wine's
MYWINE_COMMIT="$(sed -n 's/^commit: //p' "$COMP/ntdll/VERSION" 2>/dev/null || true)"
ENGINE_WINE=53def89293a
# (MYWINE=mine only: the checks of my file say "skip" without it)
mine() { [ "$MYWINE" = mine ]; }
skip() { echo "  skip   $* (this app has no ntdll.so of mine)"; }
# The same for my Mac driver's winemac.so (components/macdrv), apart from ntdll.so
if [ -f "$COMP/macdrv/winemac.so" ]; then MYDRV=mine; else MYDRV=engine; fi
MYDRV_COMMIT="$(sed -n 's/^commit: //p' "$COMP/macdrv/VERSION" 2>/dev/null || true)"
drv() { [ "$MYDRV" = mine ]; }
# my winemac.so has the mouse-look factor: its VERSION's switches: line names it, or it has no such
# line (the checks' stand-in). A dev build from before the factor lists WINE_MACDRV_SURFACE alone
scale() { drv && { ! grep -q '^switches:' "$COMP/macdrv/VERSION" || in_switches WINE_MACDRV_MOUSE_SCALE; }; }
in_switches() { sed -n 's/^switches://p' "$COMP/macdrv/VERSION" | head -1 | tr ' ' '\n' | grep -qx "$1"; }
skipdrv() { echo "  skip   $* (this app has no winemac.so of mine)"; }
# My FEX (components/fex): in the app or not. The setting fex starts at engine either way, so the
# engine's own FEX is in place until a check sets fex mine
if [ -f "$COMP/fex/aarch64-windows/libarm64ecfex.dll" ]; then MYFEX=yes; else MYFEX=no; fi
MYFEX_COMMIT="$(sed -n 's/^commit: //p' "$COMP/fex/VERSION" 2>/dev/null || true)"
ENGINE_FEX=9d4fa4b46b1
fexb() { [ "$MYFEX" = yes ]; }
skipfex() { echo "  skip   $* (this app has no FEX of mine)"; }
mkdir -p "$H"
# Another DXMT setup's caches in the per-user cache folder, which the app must never touch: a
# stand-in getconf on PATH points DARWIN_USER_CACHE_DIR at the sandbox's usercache/
USERCACHE="$SANDBOX/usercache/"
OTHER_DXMT="${USERCACHE}dxmt/Gw2-64.exe"
mkdir -p "$OTHER_DXMT" "$SANDBOX/bin" && echo "another setup's shaders" >"$OTHER_DXMT/shaders_320.db"
printf '#!/bin/bash\n[ "$1" = DARWIN_USER_CACHE_DIR ] && { echo "%s"; exit 0; }\nexec /usr/bin/getconf "$@"\n' "$USERCACHE" >"$SANDBOX/bin/getconf"
chmod 755 "$SANDBOX/bin/getconf"
export PATH="$SANDBOX/bin:$PATH"
other_dxmt_kept() { has "$OTHER_DXMT/shaders_320.db" "another setup's"; }

pass=0 fail=0
# Each check's commands: what gw2om.sh prints goes to checks/NNNN.txt as well, through G, a wrapper
# that appends it there (GW2OM is the app's own gw2om.sh). checks.txt lists the results, and a
# failed check gets a copy of the state files next to it (NNNN.state). After a failure, the end
# copies the folder to $FAILED with summary.md, which the Checks workflow uploads.
CHECKS="$SANDBOX/checks"
export GW2OM CHECK_OUT="$CHECKS/0001.txt"
G="$SANDBOX/bin/gw2om"
mkdir -p "$CHECKS" "$SANDBOX/bin"
cat >"$G" <<'EOF'
#!/bin/bash
# the app's gw2om.sh, with what it prints appended to the current check's file as well: its stdout
# and stderr through a tee each, by FIFOs the tees remove once open. gw2om.sh gets them as fds 1
# and 2 and nothing else, so its detached processes, which redirect those, hold no tee open. This
# exits with gw2om.sh's status once both tees are done, so its output is all there when it ends.
f="$CHECK_OUT.$$"
mkfifo "$f.1" "$f.2" || exec "$GW2OM" "$@"
echo "\$ gw2om.sh $*" >>"$CHECK_OUT"
{ rm -f "$f.1"; exec tee -a "$CHECK_OUT"; } <"$f.1" & t1=$!
{ rm -f "$f.2"; exec tee -a "$CHECK_OUT" >&2; } <"$f.2" & t2=$!
"$GW2OM" "$@" >"$f.1" 2>"$f.2"; rc=$?
wait "$t1" "$t2"
exit "$rc"
EOF
chmod 755 "$G"
# end_check <ok|FAIL> <what>: its line in checks.txt, the state files after a failure, and the next
# check's file
end_check() {
  local n f
  n=$(printf %04d $((pass + fail)))
  echo "$n $1 $2" >>"$CHECKS/checks.txt"
  if [ "$1" = FAIL ]; then
    mkdir -p "$CHECKS/$n.state"
    for f in "$AD/session" "$AD/session.req" "$AD/settings.conf" "$AD/state" "$AD/compatdb.rules" \
      "$LOGS/install.log" "$LOGS/wine.log" "$LOGS/session.env" "$STANDIN_LOG"; do
      [ ! -f "$f" ] || cp "$f" "$CHECKS/$n.state/"
    done
  fi
  CHECK_OUT="$CHECKS/$(printf %04d $((pass + fail + 1))).txt"
}
ok() { pass=$((pass + 1)); echo "  ok   $*"; end_check ok "$*"; }
bad() { fail=$((fail + 1)); echo "  FAIL $*"; end_check FAIL "$*"; }
check() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
section() { echo; echo "== $*"; }
g() { "$G" "$@"; }
st() { g status | sed -n "s/^$1=//p"; }
sett() { g settings | sed -n "s/^$1=//p"; }
has() { grep -q -- "$2" "$1" 2>/dev/null; }
# play starts Wine detached: wait (up to 5 s) for the stand-in's log of that start
started() { local i=0; while ! grep -q '^wine ' "$STANDIN_LOG" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }
# regsec <key>: that section of user.reg; noreg <key> <name>: the name isn't set in it
regsec() { sed -n "/^\[$1\]/,/^\$/p" "$BOTTLE/user.reg" 2>/dev/null; }
noreg() { ! regsec "$1" | grep -q "^\"$2\"="; }
# reg <key> <name> <value>: user.reg has that value in that section, in any place of it (<key> as
# the checks write it: each of user.reg's doubled backslashes as \\\\)
reg() {
  K="[$(printf '%s' "$1" | sed 's/\\\\/\\/g')]" N="\"$2\"=\"$3\"" awk 'BEGIN { k = ENVIRON["K"]; n = ENVIRON["N"] }
    index($0, "[") == 1 { insec = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ") }
    insec && $0 == n { found = 1 } END { exit !found }' "$BOTTLE/user.reg" 2>/dev/null
}
ALL_MAC='Software\\\\Wine\\\\Mac Driver'
ALL_X11='Software\\\\Wine\\\\X11 Driver'
GW2_X11='Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\X11 Driver'
same() { cmp -s "$1" "$2"; }
# the session's file, and waits (up to 10 s) for its watcher to reach a stage or end
sess() { sed -n "s/^$1=//p" "$AD/session" 2>/dev/null; }
wait_stage() { local i=0; while [ "$(sess stage)" != "$1" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; [ "$(sess stage)" = "$1" ]; }
watcher_runs() { local p; p=$(sess watcher_pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
watch_done() { local i=0; while { watcher_runs || [ "$(sess stage)" != "done" ]; } && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; ! watcher_runs && [ "$(sess stage)" = "done" ]; }

# --- The stand-in engine: the real engine's layout (Mach9's: the loader in an app bundle, bin/wine
# and lib/wine/aarch64-unix/wine links to it, the dxmt tree for arm64), files that only pretend
section "Stand-in engine and downloads"
S="$SANDBOX/standin/wine"
LOADER=lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine
mkdir -p "$S/bin" "$S/lib/wine/aarch64-unix/wine.app/Contents/MacOS" "$S/include" "$S/share/man" "$S/lib/wine/tests" "$S/lib/wine/x86_64-windows"
echo "Wine's tests" >"$S/lib/wine/tests/VERSION" && echo "SDK" >"$S/lib/wine/x86_64-windows/libntdll.a"
for a in aarch64-windows i386-windows aarch64-unix; do
  mkdir -p "$S/lib/wine/dxgi/dxmt/$a"
  for f in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll d3d10.dll; do echo "engine's $a $f" >"$S/lib/wine/dxgi/dxmt/$a/$f"; done
done
# (winemetal.so as the real engine has it: a link to lib/wine/aarch64-unix/winemetal.so)
echo "engine's winemetal.so" >"$S/lib/wine/aarch64-unix/winemetal.so"
rm -f "$S/lib/wine/dxgi/dxmt/aarch64-unix/"*.dll && ln -s ../../../aarch64-unix/winemetal.so "$S/lib/wine/dxgi/dxmt/aarch64-unix/winemetal.so"
echo "engine's ntdll.so" >"$S/lib/wine/aarch64-unix/ntdll.so"
echo "engine's winemac.so" >"$S/lib/wine/aarch64-unix/winemac.so"
# (FEX's x86_64 half: one DLL under two names and its .so; and its i386 half, which the app leaves
# alone)
mkdir -p "$S/lib/wine/aarch64-windows"
echo "engine's libarm64ecfex.dll" >"$S/lib/wine/aarch64-windows/libarm64ecfex.dll"
cp "$S/lib/wine/aarch64-windows/libarm64ecfex.dll" "$S/lib/wine/aarch64-windows/xtajit64.dll"
echo "engine's libarm64ecfex.so" >"$S/lib/wine/aarch64-unix/libarm64ecfex.so"
echo "engine's xtajit.dll" >"$S/lib/wine/aarch64-windows/xtajit.dll"
echo "<plist/>" >"$S/lib/wine/aarch64-unix/wine.app/Contents/Info.plist"
ln -s ../lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine "$S/bin/wine"
ln -s wine.app/Contents/MacOS/wine "$S/lib/wine/aarch64-unix/wine"
cat >"$S/bin/wineserver" <<'EOF'
#!/bin/bash
# stand-in wineserver: nothing runs, so -k and -w have nothing to do
echo "wineserver $*" >>"$STANDIN_LOG"
EOF
cat >"$S/$LOADER" <<'EOF'
#!/bin/bash
# stand-in wine: pretends, and logs each start with the environment the game would get
{ echo "wine $*"; env | grep -E '^(WINE|DXMT_|MTL_)' | sort | sed 's/^/  /'; } >>"$STANDIN_LOG"
case "${1:-}" in
  wineboot)
    mkdir -p "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/users/$(id -un)"
    printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\Machine\n' >"$WINEPREFIX/system.reg"
    printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21\n\n[Software\\\\Wine] 1700000000\n#time=1\n' >"$WINEPREFIX/user.reg"
    cp "$WINEPREFIX/system.reg" "$WINEPREFIX/userdef.reg" ;;
  *SteamSetup.exe)
    mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamapps"
    echo "stand-in steam" >"$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe" ;;
  *steam.exe)
    # -shutdown ends the stand-in Steam (a sleeper whose pid is in steam.pid), unless steam.stubborn
    d=$(dirname "$STANDIN_LOG")
    if [ "${2:-}" = -shutdown ] && [ ! -e "$d/steam.stubborn" ] && [ -f "$d/steam.pid" ]; then kill "$(cat "$d/steam.pid")" 2>/dev/null || true; fi ;;
esac
EOF
chmod 755 "$S/$LOADER" "$S/bin/wineserver"
export STANDIN_LOG
# (the bottle's Windows user, named after the Mac's user as upstream Wine does)
BUSER="$(id -un)"
( cd "$SANDBOX/standin" && tar -cJf ../engine.tar.xz wine )
echo "stand-in SteamSetup.exe" >"$SANDBOX/SteamSetup.exe"
export GW2_ON_MAC_ROOT="$SANDBOX"
export GW2_ON_MAC_ENGINE_URL="file://$SANDBOX/engine.tar.xz"
GW2_ON_MAC_ENGINE_SHA256="$(shasum -a 256 "$SANDBOX/engine.tar.xz" | cut -d' ' -f1)"
GW2_ON_MAC_ENGINE_SIZE="$(stat -f %z "$SANDBOX/engine.tar.xz")"
export GW2_ON_MAC_ENGINE_SHA256 GW2_ON_MAC_ENGINE_SIZE
export GW2_ON_MAC_ENGINE_CHECKS=0
# (the stand-in engine's own DXMT: graphics=yes)
GW2_ON_MAC_ENGINE_D3D11_SHA256="$(shasum -a 256 "$S/lib/wine/dxgi/dxmt/aarch64-windows/d3d11.dll" | cut -d' ' -f1)"
GW2_ON_MAC_ENGINE_WINEMETAL_SHA256="$(shasum -a 256 "$S/lib/wine/dxgi/dxmt/aarch64-unix/winemetal.so" | cut -d' ' -f1)"
export GW2_ON_MAC_ENGINE_D3D11_SHA256 GW2_ON_MAC_ENGINE_WINEMETAL_SHA256
# (and its ntdll.so: what the app moves aside for mine, unix_lib)
GW2_ON_MAC_ENGINE_NTDLL_SHA256="$(shasum -a 256 "$S/lib/wine/aarch64-unix/ntdll.so" | cut -d' ' -f1)"
GW2_ON_MAC_ENGINE_WINEMAC_SHA256="$(shasum -a 256 "$S/lib/wine/aarch64-unix/winemac.so" | cut -d' ' -f1)"
export GW2_ON_MAC_ENGINE_NTDLL_SHA256 GW2_ON_MAC_ENGINE_WINEMAC_SHA256
GW2_ON_MAC_ENGINE_FEX_DLL_SHA256="$(shasum -a 256 "$S/lib/wine/aarch64-windows/libarm64ecfex.dll" | cut -d' ' -f1)"
GW2_ON_MAC_ENGINE_FEX_SO_SHA256="$(shasum -a 256 "$S/lib/wine/aarch64-unix/libarm64ecfex.so" | cut -d' ' -f1)"
export GW2_ON_MAC_ENGINE_FEX_DLL_SHA256 GW2_ON_MAC_ENGINE_FEX_SO_SHA256
export GW2_ON_MAC_STEAMSETUP_URL="file://$SANDBOX/SteamSetup.exe"
unset GW2_ON_MAC_DRY_RUN GW2_ON_MAC_ALLOW_WINE GW2_ON_MAC_SIGNER GW2_ON_MAC_MACOS GW2_ON_MAC_ENGINE_LOADER_SHA256 GW2_ON_MAC_FEX_SWITCHES
# the session's watcher (play starts it), with its times shortened: a 2 s grace, 2 s for Steam to
# quit, a look every 0.2 s (the 15 minutes for the game to appear only in the timeout check)
export GW2_ON_MAC_WATCH_GRACE=2 GW2_ON_MAC_WATCH_QUITWAIT=2 GW2_ON_MAC_WATCH_POLL=0.2 GW2_ON_MAC_WATCH_TIMEOUT=60
# A development build's switches (the rows on once, dev-switches.conf) off for every check but those
# of their own section at the end: the others check the app as a release sets it up, apart from
# Debug logging's default
export GW2_ON_MAC_DEV_SWITCHES=off
ok "stand-in engine ($GW2_ON_MAC_ENGINE_SIZE bytes) and SteamSetup.exe"

# --- Dry runs change nothing
section "Dry runs"
out=$(GW2_ON_MAC_DRY_RUN=1 g install steam 2>&1); rc=$?
check "dry-run install steam exits 0" [ "$rc" = 0 ]
check "dry-run install steam reaches phase 4" has <(echo "$out") "@phase 4"
check "dry-run prints the game's environment" has <(echo "$out") "WINEPREFIX=$BOTTLE"
check "  with my DXMT fork's variables (it goes into the engine)" eval 'echo "$out" | grep -qxF "[dry-run]   DXMT_CACHE_DIR=$CACHE/fork" && echo "$out" | grep -qxF "[dry-run]   DXMT_WARM=all" && echo "$out" | grep -q "^\[dry-run\] my DXMT fork (.*) as the engine.s DXMT tree"'
if mine; then
  check "  with my ntdll.so for the engine" has <(echo "$out") "^\[dry-run\] my ntdll.so (jdrly/wine ${MYWINE_COMMIT:0:11}) in the engine$"
else
  check "  with the engine's own ntdll.so (this app has none of mine)" has <(echo "$out") "^\[dry-run\] the engine's own ntdll.so (athei/wine $ENGINE_WINE) in the engine$"
fi
if drv; then
  check "  with my winemac.so for the engine" has <(echo "$out") "^\[dry-run\] my winemac.so (jdrly/wine ${MYDRV_COMMIT:0:11}) in the engine$"
else
  check "  with the engine's own winemac.so (this app has none of mine)" has <(echo "$out") "^\[dry-run\] the engine's own winemac.so (athei/wine $ENGINE_WINE) in the engine$"
fi
check "  with the engine's own FEX (fex=engine by default)" has <(echo "$out") "^\[dry-run\] the engine's own FEX (athei/FEX $ENGINE_FEX) in the engine$"
check "  with the rules file and no WINE_COMPATDB" eval 'echo "$out" | grep -qxF "[dry-run]   WINE_COMPATDB_FILE=$AD/compatdb.rules" && ! echo "$out" | grep -q "WINE_COMPATDB="'
check "dry-run creates nothing" eval '[ ! -e "$AD" ] && [ ! -e "$CACHE" ]'
check "fresh status: not installed" [ "$(st installed)" = no ]
check "fresh status: no engine" [ "$(st engine_installed)" = no ]
check "fresh status: the engine's pins (Mach9 0.3.1: Wine, FEX, DXMT commits)" \
  [ "$(st engine)/$(st engine_wine)/$(st engine_fex)/$(st engine_dxmt)" = mach9-v0.3.1/53def89293a/9d4fa4b46b1/d903db89036 ]
check "fresh status: gamemode=engine (the engine's loader)" [ "$(st gamemode)" = engine ]
check "fresh status: disk_free is a number" [ "$(st disk_free)" -gt 0 ]
out=$(env -u GW2_ON_MAC_ENGINE_URL -u GW2_ON_MAC_ENGINE_SHA256 -u GW2_ON_MAC_ENGINE_SIZE GW2_ON_MAC_DRY_RUN=1 "$G" install steam 2>&1)
check "dry-run without the stand-in: the real engine, Mach9 0.3.1 from athei/mach9" \
  has <(echo "$out") "^\[dry-run\] download https://github.com/athei/mach9/releases/download/v0.3.1/wine-v0.3.1-macos-arm64.tar.xz (128991668 bytes, sha256 90aff9a897ed0ff9aac44d0e06f0aecd3ee985afb38037f3f915451e51fa974e)"
check "  no WINE_COMPATDB, no WINEDLLPATH" eval '! echo "$out" | grep -q -e WINE_COMPATDB= -e WINEDLLPATH'
check "  and still nothing created" eval '[ ! -e "$AD" ] && [ ! -e "$CACHE" ]'

section "macOS and the engine's checks (nothing is left behind)"
check "status: macOS 26.3 is below the engine's 26.4" [ "$(GW2_ON_MAC_MACOS=26.3 "$G" status | sed -n 's/^macos_ok=//p')/$(st macos_min)" = no/26.4 ]
check "  26.4 and 27.0 are not" [ "$(GW2_ON_MAC_MACOS=26.4 "$G" status | sed -n 's/^macos_ok=//p')/$(GW2_ON_MAC_MACOS=27.0 "$G" status | sed -n 's/^macos_ok=//p')" = yes/yes ]
out=$(GW2_ON_MAC_MACOS=26.3 g install steam 2>&1) && rc=0 || rc=$?
check "install on macOS 26.3: refused, naming both versions, nothing created" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error $APP_NAME needs macOS 26.4 or later for its Wine engine. This Mac has macOS 26.3. Update macOS in System Settings › General › Software Update, then try again." && [ ! -e "$ENG" ] && [ ! -e "$AD/state" ]'
# With the checks on (as outside a sandbox), against the stand-in's own files: the real engine's
# Wine never runs in a sandbox, and these installs stop at the engine
LOADER_SHA=$(shasum -a 256 "$S/$LOADER" | cut -d' ' -f1)
NTDLL_SHA=$(shasum -a 256 "$S/lib/wine/aarch64-unix/ntdll.so" | cut -d' ' -f1)
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_ENGINE_CHECKS=1 GW2_ON_MAC_ENGINE_LOADER_SHA256=$(echo "another loader" | shasum -a 256 | cut -d' ' -f1) \
  GW2_ON_MAC_ENGINE_NTDLL_SHA256="$NTDLL_SHA" "$G" install steam 2>&1) && rc=0 || rc=$?
check "a loader that isn't the expected one: refused, no engine, no Wine started" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The unpacked Wine engine does not match the expected build." && [ ! -e "$ENG" ] && [ ! -e "$ENG.new" ] && [ ! -s "$STANDIN_LOG" ]'
out=$(GW2_ON_MAC_ENGINE_CHECKS=1 GW2_ON_MAC_ENGINE_LOADER_SHA256="$LOADER_SHA" GW2_ON_MAC_ENGINE_NTDLL_SHA256="$NTDLL_SHA" "$G" install steam 2>&1) && rc=0 || rc=$?
check "the expected hashes, but wine.app isn't signed by Mach9's team: refused the same way" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The unpacked Wine engine does not match the expected build." && [ ! -e "$ENG" ] && [ ! -s "$STANDIN_LOG" ]'
check "  nothing left of those installs but the verified download and the log" \
  eval '[ -z "$(ls -A "$AD" 2>/dev/null)" ] && [ "$(ls "$CACHE/downloads")" = engine.tar.xz ]'
rm -rf "$CACHE"

# dxgi_is fork|engine: the engine's DXMT trees as the app leaves them (lib/wine/dxgi). fork: dxmt is
# the stand-in engine's tree with every file of the app's components/dxmt over it (its winemetal.so
# a file of its own, not the engine's link) and the mark, and dxmt.engine the engine's own as it
# ships (its link included). engine: dxmt is the engine's own, and no dxmt.engine.
dxgi_is() {
  local D="$ENG/lib/wine/dxgi" f
  if [ "$1" = engine ]; then
    diff -r "$S/lib/wine/dxgi/dxmt" "$D/dxmt" >/dev/null && [ -L "$D/dxmt/aarch64-unix/winemetal.so" ] && [ ! -e "$D/dxmt.engine" ]
    return
  fi
  diff -r "$S/lib/wine/dxgi/dxmt" "$D/dxmt.engine" >/dev/null && [ -L "$D/dxmt.engine/aarch64-unix/winemetal.so" ] &&
    [ -f "$D/dxmt/.gw2om-dxmt" ] && [ ! -e "$D/dxmt.fork" ] && [ ! -L "$D/dxmt/aarch64-unix/winemetal.so" ] &&
    same "$S/lib/wine/dxgi/dxmt/aarch64-windows/d3d10.dll" "$D/dxmt/aarch64-windows/d3d10.dll" || return 1
  for f in $(cd "$COMP/dxmt" && find . -type f); do same "$COMP/dxmt/$f" "$D/dxmt/$f" || return 1; done
  # (and the engine's own winemetal.so, which the link points at, as it ships)
  same "$S/lib/wine/aarch64-unix/winemetal.so" "$ENG/lib/wine/aarch64-unix/winemetal.so"
}
# wineapp_sums <engine>: every file in wine.app with its sha256
wineapp_sums() { (cd "$1/lib/wine/aarch64-unix/wine.app" && find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort); }
# unix_is <file> <its folder in components/> mine|engine: the engine's <file> as the app leaves
# it. mine: the app's components/<folder>/<file>, the engine's own next to it as <file>.engine.
# engine: the engine's own, nothing next to it. Never an unfinished <file>.new.
NT="$ENG/lib/wine/aarch64-unix"
unix_is() {
  [ ! -e "$NT/$1.new" ] || return 1
  if [ "$3" = engine ]; then
    same "$S/lib/wine/aarch64-unix/$1" "$NT/$1" && [ ! -e "$NT/$1.engine" ]
    return
  fi
  same "$COMP/$2/$1" "$NT/$1" && same "$S/lib/wine/aarch64-unix/$1" "$NT/$1.engine"
}
# ntdll_is and winemac_is mine|engine: my ntdll.so's and my Mac driver's
ntdll_is() { unix_is ntdll.so ntdll "$1"; }
winemac_is() { unix_is winemac.so macdrv "$1"; }
# fex_is mine|engine: FEX's three files as the app leaves them. mine: the app's
# components/fex/aarch64-windows/libarm64ecfex.dll as both DLLs and its libarm64ecfex.so, the
# engine's own next to each as <file>.engine. engine: the engine's own, nothing next to them. Never
# an unfinished <file>.new, and the i386 half as it ships
FW="$ENG/lib/wine"
FEXF="aarch64-windows/xtajit64.dll aarch64-windows/libarm64ecfex.dll aarch64-unix/libarm64ecfex.so"
fex_src_of() { case "$1" in *.dll) echo "$COMP/fex/aarch64-windows/libarm64ecfex.dll" ;; *) echo "$COMP/fex/$1" ;; esac; }
fex_is() {
  local f
  same "$S/lib/wine/aarch64-windows/xtajit.dll" "$FW/aarch64-windows/xtajit.dll" || return 1
  for f in $FEXF; do
    [ ! -e "$FW/$f.new" ] || return 1
    if [ "$1" = engine ]; then
      same "$S/lib/wine/$f" "$FW/$f" && [ ! -e "$FW/$f.engine" ] || return 1
    else
      same "$(fex_src_of "$f")" "$FW/$f" && same "$S/lib/wine/$f" "$FW/$f.engine" || return 1
    fi
  done
}

# --- Steam route
section "Install through Steam"
# (a file in the downloads folder under the engine's name that isn't the engine, as a player may
# put there by hand: named in the window, moved aside, and the engine downloaded)
mkdir -p "$CACHE/downloads" && echo "not the engine" >"$CACHE/downloads/engine.tar.xz"
WRONG_SHA=$(shasum -a 256 "$CACHE/downloads/engine.tar.xz" | cut -d' ' -f1)
ENGINE_BYTES=$(echo "$GW2_ON_MAC_ENGINE_SIZE" | sed -e :a -e 's/^\([0-9]\{1,\}\)\([0-9]\{3\}\)/\1,\2/;ta')   # (with thousands commas)
# (and compatdb variables the app may have inherited, which the install's Wine calls drop)
out=$(WINE_COMPATDB='exe=*;dxgi=wined3d' WINE_COMPATDB_FILE=/tmp/x WINE_LARGE_ADDRESS_AWARE=1 WINE_PROF_SERVICE=1 g install steam 2>&1) && rc=0 || rc=$?
check "install steam exits 0" [ "$rc" = 0 ]
check "the wrong file in the downloads: the window names it, its size and sha256 against the engine's" eval 'echo "$out" | grep -qxF "@warn engine.tar.xz in $CACHE/downloads is not the Wine engine. It has 15 bytes and a sha256 starting ${WRONG_SHA:0:12}, the Wine engine has $ENGINE_BYTES bytes and a sha256 starting ${GW2_ON_MAC_ENGINE_SHA256:0:12}. $APP_NAME renamed your file to engine.tar.xz.wrong and downloads the Wine engine itself."'
check "  moved aside as engine.tar.xz.wrong, then the engine downloaded" eval 'has "$CACHE/downloads/engine.tar.xz.wrong" "not the engine" && echo "$out" | grep -q "^Downloading Wine engine from"'
check "the phases 1-4 in order" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 @phase 4 " ]
check "@progress lines for the engine" has <(echo "$out") "@progress Wine engine"
check "installed=yes" [ "$(st installed)" = yes ]
check "engine_installed=yes" [ "$(st engine_installed)" = yes ]
check "graphics=yes: my DXMT fork, as Settings asks by default" [ "$(st graphics)/$(st dxmt)/$(st dxmt_tree)" = yes/fork/fork ]
check "  status names the fork's build and its release" eval '[ "$(st dxmt_version)" = "$(head -1 "$COMP/dxmt/VERSION")" ] && [ -n "$(st dxmt_commit)" ] && [ -n "$(st dxmt_release)" ] && head -1 "$COMP/dxmt/VERSION" | grep -qF "v$(st dxmt_release)-"'
check "  the install says so" has <(echo "$out") "^DXMT: my DXMT fork ($(head -1 "$COMP/dxmt/VERSION")) draws the game"
check "  the engine's DXMT tree is mine, the engine's own next to it as it ships" dxgi_is fork
if mine; then
  check "my ntdll.so in the engine, the engine's own next to it as ntdll.so.engine" ntdll_is mine
  check "  status names it, its commit and its Wine release" [ "$(st wine)/$(st wine_ready)/$(st wine_file)/$(st wine_commit)/$(st wine_build)/$(st wine_release)" = "mine/yes/mine/$MYWINE_COMMIT/$MYWINE_COMMIT/11.21" ]
  check "  the install says so" has <(echo "$out") "^ntdll.so: my ntdll.so (jdrly/wine ${MYWINE_COMMIT:0:11}) is in the engine, the engine's own kept next to it as ntdll.so.engine$"
else
  check "no ntdll.so of mine in this app: the engine's own stays in place" ntdll_is engine
  check "  status names it and the engine's Wine" [ "$(st wine_ready)/$(st wine_file)/$(st wine_commit)/$(st wine_build)/$(st wine_release)" = "yes/engine/$ENGINE_WINE//" ]
fi
if drv; then
  check "my winemac.so in the engine, the engine's own next to it as winemac.so.engine" winemac_is mine
  check "  status names it, its commit and its Wine release" [ "$(st macdrv)/$(st macdrv_ready)/$(st macdrv_file)/$(st macdrv_commit)/$(st macdrv_build)/$(st macdrv_release)" = "mine/yes/mine/$MYDRV_COMMIT/$MYDRV_COMMIT/11.21" ]
  check "  the install says so" has <(echo "$out") "^winemac.so: my winemac.so (jdrly/wine ${MYDRV_COMMIT:0:11}) is in the engine, the engine's own kept next to it as winemac.so.engine$"
else
  check "no winemac.so of mine in this app: the engine's own stays in place" winemac_is engine
  check "  status names it and the engine's Wine" [ "$(st macdrv_ready)/$(st macdrv_file)/$(st macdrv_commit)/$(st macdrv_build)/$(st macdrv_release)" = "yes/engine/$ENGINE_WINE//" ]
fi
check "the engine's own FEX in place (fex=engine by default), nothing next to it" fex_is engine
check "  status names it and the engine's FEX commit, and my build's commit in this app" \
  [ "$(st fex)/$(st fex_ready)/$(st fex_file)/$(st fex_commit)/$(st fex_build)" = "engine/yes/engine/$ENGINE_FEX/$MYFEX_COMMIT" ]
check "  the install says nothing of FEX (nothing switched)" eval '! echo "$out" | grep -q "^FEX:"'
check "gamemode=engine" [ "$(st gamemode)" = engine ]
check "steam=yes" [ "$(st steam)" = yes ]
check "stage=waiting_game" [ "$(st stage)" = waiting_game ]
check "route=steam" [ "$(st route)" = steam ]
check "game=no yet" [ "$(st game)" = no ]
# (the engine as it ships: every file the stand-in's, minus the SDK, plus the app's record of the
# archive; nothing of the app's in it but its DXMT trees, ntdll.so and winemac.so, which dxgi_is,
# ntdll_is and winemac_is check)
engine_diff() { diff -rq -x dxgi -x 'ntdll.so*' -x 'winemac.so*' "$S" "$ENG" 2>&1 | sed -e "s|$S|S|g" -e "s|$ENG|E|g" | LC_ALL=C sort | tr '\n' '|'; }
SDK_DIFF="Only in E: .gw2om-source|Only in S/lib/wine: tests|Only in S/lib/wine: x86_64-windows|Only in S/share: man|Only in S: include|"
check "the engine is the stand-in as it ships, without its SDK (include, tests, x86_64-windows, man)" [ "$(engine_diff)" = "$SDK_DIFF" ]
check "  wine.app's files have the stand-in's hashes" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
check "  bin/wine and lib/wine/aarch64-unix/wine still link to the loader in wine.app" \
  eval '[ "$(readlink "$ENG/bin/wine")" = ../$LOADER ] && [ "$(readlink "$ENG/lib/wine/aarch64-unix/wine")" = wine.app/Contents/MacOS/wine ]'
check "  no Game Mode bundle (the engine's loader is the Game Mode app)" [ ! -e "$AD/gamemode" ]
check "RetinaMode=y in the bottle" reg "$ALL_MAC" RetinaMode y
check "EmulateModeset=N (0.1.x's behaviour, not Mach9's launcher's Y: #90)" reg "$ALL_X11" EmulateModeset N
check "ShowCrashDialog=dword:0" eval 'regsec "Software\\\\\\\\Wine\\\\\\\\WineDbg" | grep -qx "\"ShowCrashDialog\"=dword:00000000"'
check "  nothing for Gw2-64.exe (AppDefaults) and no raw mouse-look values" sh -c "! grep -q -e AppDefaults -e RawMouse '$BOTTLE/user.reg'"
check "wineboot with WINEMSYNC=1 and winemenubuilder off, nothing else of the app's" \
  eval '[ "$(awk "/^wine wineboot/ { f = 1; next } /^[^ ]/ { f = 0 } f" "$STANDIN_LOG" | sed "s/^  //" | tr "\n" "|")" = "WINEDEBUG=-all|WINEDLLOVERRIDES=winemenubuilder.exe=d|WINEMSYNC=1|WINEPREFIX=$BOTTLE|" ]'
check "  no inherited compatdb variable reached any of the install's Wine starts (Steam's has the app's rules file)" \
  sh -c "! grep -q -e WINE_COMPATDB= -e WINE_LARGE_ADDRESS_AWARE -e WINE_PROF_SERVICE '$STANDIN_LOG' && [ \"\$(grep WINE_COMPATDB_FILE '$STANDIN_LOG')\" = '  WINE_COMPATDB_FILE=$AD/compatdb.rules' ]"
check "Steam started with the install page" has "$STANDIN_LOG" 'wine C:\\Program Files (x86)\\Steam\\steam.exe steam://install/1284210'
check "  without WINEDLLPATH" sh -c "! grep -q WINEDLLPATH '$STANDIN_LOG'"
check "logs/session.env written" has "$LOGS/session.env" "SETTING_warm=on"
check "the manifest" has "$AD/install-manifest.json" '"route": "steam"'
check "install.log" has "$LOGS/install.log" "install steam"
# (the app's own three folders and nothing else in Library, so it never shares one with another
# build of the app, such as 0.1.x)
check "only the app's folders in Library: $APP_FOLDER" eval '[ "$(cd "$H/Library" && ls -d */* | tr "\n" "|")" = "Application Support/$APP_FOLDER|Caches/$APP_FOLDER|Logs/$APP_FOLDER|" ]'
check "  status reads the install from there, the folder of every install before" [ "$(st app_dir)" = "$AD" ]

section "Steam downloads the game (played by the test)"
m="$STEAM/steamapps/appmanifest_1284210.acf"
printf '"AppState"\n{\n\t"appid"\t\t"1284210"\n\t"installdir"\t\t"Guild Wars 2"\n\t"StateFlags"\t\t"1026"\n\t"BytesToDownload"\t\t"58900000000"\n\t"BytesDownloaded"\t\t"21400000000"\n}\n' >"$m"
check "game=no while downloading" [ "$(st game)" = no ]
check "game_bytes/game_total from the appmanifest" [ "$(st game_bytes)/$(st game_total)" = 21400000000/58900000000 ]
mkdir -p "$STEAM/steamapps/common/Guild Wars 2"
echo "stand-in game" >"$STEAM/steamapps/common/Guild Wars 2/Gw2-64.exe"
sed -i '' 's/"1026"/"4"/' "$m"
check "game=yes once StateFlags is 4" [ "$(st game)" = yes ]
out=$(g play 2>&1) && rc=0 || rc=$?
check "play refuses before the finishing touches" [ "$rc" != 0 ]
out=$(g finish 2>&1) && rc=0 || rc=$?
check "finish exits 0" [ "$rc" = 0 ]
check "  phase 5" has <(echo "$out") "@phase 5"
check "stage=finished" [ "$(st stage)" = finished ]
check "DXMT's cache folder" [ -d "$DXMT_CACHE" ]

section "Settings"
check "defaults: warm on, fastlocks off, ncpu 8, uiscale off, cinematic dialogue off" \
  [ "$(sett warm)$(sett fastlocks)$(sett ncpu)$(sett uiscale)$(sett uiscale_cinema)" = onoff8offoff ]
check "  settings.conf of a fresh install: settings_version=2, fastlocks off, dxmt fork, wine and macdrv mine, fex engine" \
  eval 'grep -qx settings_version=2 "$AD/settings.conf" && grep -qx fastlocks=off "$AD/settings.conf" && grep -qx dxmt=fork "$AD/settings.conf" && grep -qx wine=mine "$AD/settings.conf" && grep -qx macdrv=mine "$AD/settings.conf" && grep -qx fex=engine "$AD/settings.conf"'

check "default: Steam in the background on" [ "$(sett steambg)" = on ]
check "default: Quit Steam when the game quits on" [ "$(sett quitsteam)" = on ]
check "settings: a state for each of the 26 keys" [ "$(g settings | grep -cE '^[a-z_]+_state=(ok|off:.+)$')" = 26 ]
# (greyed: the ones a later step brings, and those that need a file of mine this app hasn't, in
# SETTING_KEYS' order)
OFF=""
mine || OFF="${OFF}fastlocks "
OFF="${OFF}gamemode "
scale || OFF="${OFF}mousespeed "
mine || OFF="${OFF}wine jobwakes "
drv || OFF="${OFF}macdrv launcherframes "
mine || OFF="${OFF}eventpool "
fexb || OFF="${OFF}fex "
check "  off: gamemode$(mine || echo ", wine and its switches")$(drv || echo ", macdrv and launcherframes")$(scale || echo ", mousespeed")$(fexb || echo ", fex")" \
  [ "$(g settings | sed -n 's/^\([a-z_]*\)_state=off:.*/\1/p' | tr '\n' ' ')" = "$OFF" ]
if mine; then
  check "  wine=mine, jobwakes and eventpool on and fastlocks off by default, all ok" \
    [ "$(sett wine)/$(sett wine_state)/$(sett jobwakes)/$(sett jobwakes_state)/$(sett eventpool)/$(sett eventpool_state)/$(sett fastlocks)/$(sett fastlocks_state)" = mine/ok/on/ok/on/ok/off/ok ]
else
  check "  with their reasons; set wine engine and set jobwakes, eventpool and fastlocks refused" \
    eval '[ "$(sett wine_state)" = "off:This build of the app has no Wine build of mine." ] && [ "$(sett jobwakes_state)" = "off:Needs my Wine build, which this build of the app doesn'"'"'t have." ] && [ "$(sett eventpool_state)" = "$(sett jobwakes_state)" ] && [ "$(sett fastlocks_state)" = "$(sett jobwakes_state)" ] && ! "$G" set wine engine >/dev/null 2>&1 && ! "$G" set jobwakes off >/dev/null 2>&1 && ! "$G" set eventpool off >/dev/null 2>&1 && ! "$G" set fastlocks on >/dev/null 2>&1'
fi
if drv; then
  check "  macdrv=mine and launcherframes=off by default, both ok; mousespeed=1" [ "$(sett macdrv)/$(sett macdrv_state)/$(sett launcherframes)/$(sett launcherframes_state)/$(sett mousespeed)" = mine/ok/off/ok/1 ]
  if scale; then
    check "  mousespeed ok" [ "$(sett mousespeed_state)" = ok ]
  else
    check "  mousespeed greyed: my winemac.so's VERSION doesn't list its switch" \
      [ "$(sett mousespeed_state)" = "off:My Mac driver in this app (jdrly/wine ${MYDRV_COMMIT:0:11}) doesn't have this switch." ]
  fi
else
  check "  with their reasons; set macdrv engine, set launcherframes on and set mousespeed 1.5 refused" \
    eval '[ "$(sett macdrv_state)" = "off:This build of the app has no Mac driver of mine." ] && [ "$(sett launcherframes_state)" = "off:Needs my Mac driver, which this build of the app doesn'"'"'t have." ] && [ "$(sett mousespeed_state)" = "$(sett launcherframes_state)" ] && ! "$G" set macdrv engine >/dev/null 2>&1 && ! "$G" set launcherframes on >/dev/null 2>&1 && ! "$G" set mousespeed 1.5 >/dev/null 2>&1'
fi
# settings.conf's version (SETTINGS_RESETS): a file from before version 1 holds the fastlocks=on
# and coolworkers=3 the arm64 line wrote while both rows were greyed; fastlocks reads off, and
# coolworkers, no longer a key, is read by nothing
cp "$AD/settings.conf" "$SANDBOX/settings.fresh"
sed -i '' -e '/^settings_version=/d' -e 's/^fastlocks=.*/fastlocks=on/' "$AD/settings.conf"
echo coolworkers=3 >>"$AD/settings.conf"
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "a settings.conf without settings_version, fastlocks=on and coolworkers=3: fastlocks reads off" \
  eval '[ "$(sett fastlocks)" = off ] && ! g settings | grep -q coolworkers && ! g rules | grep -q WINE_HEAT_SPIN && ! echo "$out" | grep -q WINE_HEAT_SPIN'
g set hud on >/dev/null; g set hud off >/dev/null
check "  the next write keeps that, writes settings_version=2 and leaves coolworkers out" \
  eval 'grep -qx settings_version=2 "$AD/settings.conf" && grep -qx fastlocks=off "$AD/settings.conf" && ! grep -q coolworkers "$AD/settings.conf"'
sed -i '' -e 's/^settings_version=.*/settings_version=0/' -e 's/^fastlocks=.*/fastlocks=on/' "$AD/settings.conf"
check "  settings_version=0 and fastlocks=on: reads off" [ "$(sett fastlocks)" = off ]
# a file at version 1 with the engine's own DXMT, ntdll.so and winemac.so chosen, from the rows
# version 2 took out of the window: fork, mine and mine, once
cp "$SANDBOX/settings.fresh" "$AD/settings.conf"
sed -i '' -e 's/^settings_version=.*/settings_version=1/' -e 's/^dxmt=.*/dxmt=engine/' -e 's/^wine=.*/wine=engine/' -e 's/^macdrv=.*/macdrv=engine/' "$AD/settings.conf"
echo coolworkers=off >>"$AD/settings.conf"
check "settings_version=1 with dxmt, wine and macdrv engine and a coolworkers line: read fork, mine, mine" \
  [ "$(sett dxmt)/$(sett wine)/$(sett macdrv)/$(st graphics)" = fork/mine/mine/yes ]
g set hud on >/dev/null; g set hud off >/dev/null
check "  the next write keeps them, writes settings_version=2 and leaves coolworkers out" \
  eval 'grep -qx settings_version=2 "$AD/settings.conf" && grep -qx dxmt=fork "$AD/settings.conf" && grep -qx wine=mine "$AD/settings.conf" && grep -qx macdrv=mine "$AD/settings.conf" && ! grep -q coolworkers "$AD/settings.conf"'
sed -i '' 's/^dxmt=.*/dxmt=engine/' "$AD/settings.conf"
g set hud on >/dev/null; g set hud off >/dev/null
check "  only once: dxmt=engine in a file at version 2 stays through later writes" \
  eval '[ "$(sett dxmt)" = engine ] && grep -qx dxmt=engine "$AD/settings.conf" && grep -qx settings_version=2 "$AD/settings.conf"'
cp "$SANDBOX/settings.fresh" "$AD/settings.conf"
if mine; then
  g set fastlocks on >/dev/null; g set hud on >/dev/null; g set hud off >/dev/null
  check "  set fastlocks on in a file with the line: stays on through later writes" \
    eval '[ "$(sett fastlocks)" = on ] && grep -qx fastlocks=on "$AD/settings.conf" && grep -qx settings_version=2 "$AD/settings.conf"'
  g set fastlocks off >/dev/null
fi
check "  rawmouse ok" [ "$(sett rawmouse_state)" = ok ]
g set rawmouse off >/dev/null
check "  rawmouse off: mousespeed greyed, saying so first; set mousespeed 1.5 refused" \
  eval '[ "$(sett mousespeed_state)" = "off:Needs Raw mouse-look, which is off." ] && ! "$G" set mousespeed 1.5 >/dev/null 2>&1'
g set rawmouse on >/dev/null
check "  ok for the ones my DXMT fork brings back: metalfx, warm; dxmt=fork by default" \
  [ "$(sett metalfx_state)/$(sett warm_state)/$(sett dxmt)/$(sett dxmt_state)" = ok/ok/fork/ok ]
check "  the larger interface's settings and arcdps carry a note" \
  [ "$(g settings | sed -n 's/^\([a-z_]*\)_note=.*/\1/p' | tr '\n' ' ')" = "uiscale uiscale_size uiscale_sans uiscale_cinema arcdps " ]
out=$(g set coolworkers 5 2>&1) && rc=0 || rc=$?
check "set coolworkers 5: refused as an unknown setting" eval '[ "$rc" = 2 ] && [ "$out" = "@error Unknown setting: coolworkers=5" ]'
check "set gamemode off: refused" sh -c "! '$G' set gamemode off >/dev/null"
sed -i '' 's/^gamemode=on$/gamemode=off/' "$AD/settings.conf"
g set hud on >/dev/null; g set hud off >/dev/null
check "  a greyed key keeps what settings.conf says (gamemode=off by hand), and does nothing" eval '[ "$(sett gamemode)" = off ] && grep -qx gamemode=off "$AD/settings.conf"'
sed -i '' 's/^gamemode=off$/gamemode=on/' "$AD/settings.conf"
check "warm on: DXMT_WARM=all; off: none" sh -c "'$G' env | grep -qx DXMT_WARM=all && '$G' set warm off >/dev/null && ! '$G' env | grep -q DXMT_WARM && '$G' set warm on >/dev/null"
check "set metalfx on: DXMT_SUBSAMPLE_METALFX=1" sh -c "'$G' set metalfx on >/dev/null && '$G' env | grep -qx DXMT_SUBSAMPLE_METALFX=1 && '$G' set metalfx off >/dev/null && ! '$G' env | grep -q DXMT_SUBSAMPLE"
# the engine's own DXMT, and back (nothing runs: the tree swaps at once)
out=$(g set dxmt engine 2>&1) && rc=0 || rc=$?
check "set dxmt engine: the engine's own tree is the active one, mine waits next to it" \
  eval '[ "$rc" = 0 ] && dxgi_is engine && [ -f "$ENG/lib/wine/dxgi/dxmt.fork/.gw2om-dxmt" ] && [ "$(st graphics)/$(st dxmt_tree)" = yes/engine ] && ! echo "$out" | grep -q Repair'
check "  it says which" has <(echo "$out") "^DXMT: the engine's own DXMT (athei/dxmt d903db89036) draws the game"
check "  warming and MetalFX greyed with the reason; set warm refused" \
  eval '[ "$(sett warm_state)" = "off:Needs my DXMT fork, and the engine'"'"'s own DXMT is chosen." ] && [ "$(sett metalfx_state)" = "$(sett warm_state)" ] && ! "$G" set warm off >/dev/null 2>&1'
check "  none of the fork's variables in the environment" sh -c "! '$G' env | grep -qE 'DXMT_(CACHE_DIR|WARM|DEPENDENCY_COMPRESSION|SUBSAMPLE|STATS)'"
# (after the heat entries exactly FEX's that Debug logging adds: FEX_PROFILESTATS only with my
# ntdll.so in place, FEX_SILENTLOG with either, neither with Debug logging off)
fex_tail=""
if [ "$(sett debug)" = on ]; then ! ntdll_is mine || fex_tail=";env=FEX_PROFILESTATS=1"; fex_tail="$fex_tail;env=FEX_SILENTLOG=0"; fi
check "  the game's shader cache: the engine's DXMT's own" has <(g rules) "^exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=$DXMT_CACHE_ENGINE\(;env=WINE_HEAT_[^;]*\)*$fex_tail$"
check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
out=$(g set dxmt fork 2>&1) && rc=0 || rc=$?
check "set dxmt fork: mine again, the engine's own kept as it ships" eval '[ "$rc" = 0 ] && dxgi_is fork && [ "$(st graphics)/$(st dxmt_tree)" = yes/fork ] && ! echo "$out" | grep -q Repair'
check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
# A swap cut short (the Mac off, a kill): between its two renames there is no active tree, and
# during the copy an unfinished dxmt.fork.new; the next call puts the asked-for tree in
DX="$ENG/lib/wine/dxgi"
mv "$DX/dxmt" "$DX/dxmt.fork" && sed -i '' 's/^dxmt=.*/dxmt=engine/' "$AD/settings.conf"
check "cut short on the way to the engine's own (no active tree): graphics=switch" [ "$(st graphics)/$(st dxmt_tree)" = switch/none ]
check "  the next set dxmt engine puts it in" eval 'g set dxmt engine >/dev/null && dxgi_is engine && [ "$(st graphics)" = yes ]'
mv "$DX/dxmt" "$DX/dxmt.engine" && sed -i '' 's/^dxmt=.*/dxmt=fork/' "$AD/settings.conf"
check "cut short on the way to mine (no active tree): graphics=switch" [ "$(st graphics)/$(st dxmt_tree)" = switch/none ]
check "  the next set dxmt fork puts it in" eval 'g set dxmt fork >/dev/null && dxgi_is fork && [ "$(st graphics)" = yes ]'
g set dxmt engine >/dev/null && rm -rf "$DX/dxmt.fork" && mkdir -p "$DX/dxmt.fork.new/aarch64-windows" && echo half >"$DX/dxmt.fork.new/aarch64-windows/d3d11.dll"
check "cut short while making my tree (an unfinished dxmt.fork.new): set dxmt fork makes it again" \
  eval 'g set dxmt fork >/dev/null && dxgi_is fork && [ ! -e "$DX/dxmt.fork.new" ] && [ "$(st graphics)" = yes ]'
check "  the engine's own tree, its link's target and wine.app as they ship through all of it" \
  eval 'diff -r "$S/lib/wine/dxgi/dxmt" "$DX/dxmt.engine" >/dev/null && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
# My ntdll.so and the engine's own, and back (nothing runs: the file switches at once)
if mine; then
  out=$(g set wine engine 2>&1) && rc=0 || rc=$?
  check "set wine engine: the engine's own ntdll.so in place, nothing next to it" \
    eval '[ "$rc" = 0 ] && ntdll_is engine && [ "$(st wine_ready)/$(st wine_file)/$(st wine_commit)" = "yes/engine/$ENGINE_WINE" ] && ! echo "$out" | grep -q Repair'
  check "  it says which" has <(echo "$out") "^ntdll.so: the engine's own ntdll.so (athei/wine $ENGINE_WINE) is in the engine$"
  check "  job wakes greyed with the reason; set jobwakes refused" \
    eval '[ "$(sett jobwakes_state)" = "off:Needs my Wine build, and the engine'"'"'s own ntdll.so is chosen." ] && ! "$G" set jobwakes off >/dev/null 2>&1'
  check "  wine.app and the DXMT trees untouched" eval '[ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ] && dxgi_is fork'
  out=$(g set wine mine 2>&1) && rc=0 || rc=$?
  check "set wine mine: mine again, the engine's own next to it as it ships" \
    eval '[ "$rc" = 0 ] && ntdll_is mine && [ "$(st wine_ready)/$(st wine_file)/$(st wine_commit)" = "yes/mine/$MYWINE_COMMIT" ] && [ "$(sett jobwakes_state)" = ok ]'
  check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
  # A switch cut short: between the two renames on the way to mine no ntdll.so is there; an
  # unfinished copy (ntdll.so.new) may be left; an earlier build of mine may be in place
  mv "$NT/ntdll.so" "$NT/ntdll.so.new"
  check "cut short between the renames (no ntdll.so): wine_ready=switch" [ "$(st wine_ready)/$(st wine_file)" = switch/none ]
  check "  the next set wine mine puts it in" eval 'g set wine mine >/dev/null && ntdll_is mine && [ "$(st wine_ready)" = yes ]'
  g set wine engine >/dev/null && mv "$NT/ntdll.so" "$NT/ntdll.so.engine" && echo half >"$NT/ntdll.so.new"
  sed -i '' 's/^wine=.*/wine=mine/' "$AD/settings.conf"
  check "cut short with an unfinished ntdll.so.new: set wine mine copies it again" \
    eval 'g set wine mine >/dev/null && ntdll_is mine && [ "$(st wine_ready)" = yes ]'
  echo "an earlier build of mine" >"$NT/ntdll.so"
  check "an earlier build of mine in place: wine_ready=switch, wine_file=other" [ "$(st wine_ready)/$(st wine_file)/$(st wine_commit)" = switch/other/ ]
  check "  set wine engine puts the engine's own back, set wine mine this build's" \
    eval 'g set wine engine >/dev/null && ntdll_is engine && g set wine mine >/dev/null && ntdll_is mine'
  check "  the engine's own ntdll.so and wine.app as they ship through all of it" \
    eval 'same "$S/lib/wine/aarch64-unix/ntdll.so" "$NT/ntdll.so.engine" && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
else
  skip "set wine engine and mine, and the switches cut short"
fi
# My winemac.so and the engine's own, and back, apart from ntdll.so (nothing runs: it switches at
# once)
if drv; then
  out=$(g set macdrv engine 2>&1) && rc=0 || rc=$?
  check "set macdrv engine: the engine's own winemac.so in place, nothing next to it, ntdll.so as it was" \
    eval '[ "$rc" = 0 ] && winemac_is engine && ntdll_is $MYWINE && [ "$(st macdrv_ready)/$(st macdrv_file)/$(st macdrv_commit)/$(st wine_file)" = "yes/engine/$ENGINE_WINE/$MYWINE" ] && ! echo "$out" | grep -q Repair'
  check "  it says which" has <(echo "$out") "^winemac.so: the engine's own winemac.so (athei/wine $ENGINE_WINE) is in the engine$"
  check "  launcher frames greyed with the reason; set launcherframes refused" \
    eval '[ "$(sett launcherframes_state)" = "off:Needs my Mac driver, and the engine'"'"'s own winemac.so is chosen." ] && ! "$G" set launcherframes on >/dev/null 2>&1'
  out=$(g set macdrv mine 2>&1) && rc=0 || rc=$?
  check "set macdrv mine: mine again, the engine's own next to it as it ships, ntdll.so as it was" \
    eval '[ "$rc" = 0 ] && winemac_is mine && ntdll_is $MYWINE && [ "$(st macdrv_ready)/$(st macdrv_file)/$(st macdrv_commit)" = "yes/mine/$MYDRV_COMMIT" ] && [ "$(sett launcherframes_state)" = ok ]'
  if mine; then
    check "set wine engine and back: my winemac.so stays through both" \
      eval 'g set wine engine >/dev/null && ntdll_is engine && winemac_is mine && g set wine mine >/dev/null && ntdll_is mine && winemac_is mine'
  fi
  mv "$NT/winemac.so" "$NT/winemac.so.new"
  check "cut short between the renames (no winemac.so): macdrv_ready=switch" [ "$(st macdrv_ready)/$(st macdrv_file)" = switch/none ]
  check "  the next set macdrv mine puts it in" eval 'g set macdrv mine >/dev/null && winemac_is mine && [ "$(st macdrv_ready)" = yes ]'
  echo "an earlier build of mine" >"$NT/winemac.so"
  check "an earlier build of mine in place: macdrv_ready=switch, macdrv_file=other" [ "$(st macdrv_ready)/$(st macdrv_file)/$(st macdrv_commit)" = switch/other/ ]
  check "  set macdrv engine puts the engine's own back, set macdrv mine this build's" \
    eval 'g set macdrv engine >/dev/null && winemac_is engine && g set macdrv mine >/dev/null && winemac_is mine'
  check "  the engine's own winemac.so and wine.app as they ship through all of it" \
    eval 'same "$S/lib/wine/aarch64-unix/winemac.so" "$NT/winemac.so.engine" && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
else
  skipdrv "set macdrv engine and mine, and the switches cut short"
fi
# My FEX and the engine's own, and back (nothing runs: the three files switch at once). The way
# there is three copies, then six renames; the way back three renames
FEXLEFT() { find "$FW" \( -name 'xtajit64.dll.*' -o -name 'libarm64ecfex.*.*' \) | LC_ALL=C sort; }
if fexb; then
  out=$(g set fex mine 2>&1) && rc=0 || rc=$?
  check "set fex mine: my FEX's three files in the engine, the engine's own next to each as <file>.engine" \
    eval '[ "$rc" = 0 ] && fex_is mine && [ "$(st fex)/$(st fex_ready)/$(st fex_file)/$(st fex_commit)/$(st fex_build)" = "mine/yes/mine/$MYFEX_COMMIT/$MYFEX_COMMIT" ] && ! echo "$out" | grep -q Repair'
  check "  it says so" has <(echo "$out") "^FEX: my FEX (jdrly/FEX ${MYFEX_COMMIT:0:11}) is in the engine, the engine's own kept next to each of its three files as <file>.engine$"
  check "  ntdll.so, winemac.so, the DXMT trees and wine.app as they were" \
    eval 'ntdll_is $MYWINE && winemac_is $MYDRV && dxgi_is fork && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
  out=$(g set fex engine 2>&1) && rc=0 || rc=$?
  check "set fex engine: the engine's own three files with the pinned hashes, nothing left over" \
    eval '[ "$rc" = 0 ] && fex_is engine && [ -z "$(FEXLEFT)" ] && [ "$(st fex_ready)/$(st fex_file)/$(st fex_commit)" = "yes/engine/$ENGINE_FEX" ] &&
      [ "$(shasum -a 256 "$FW/aarch64-windows/xtajit64.dll" "$FW/aarch64-windows/libarm64ecfex.dll" "$FW/aarch64-unix/libarm64ecfex.so" | cut -d" " -f1 | tr "\n" " ")" = "$GW2_ON_MAC_ENGINE_FEX_DLL_SHA256 $GW2_ON_MAC_ENGINE_FEX_DLL_SHA256 $GW2_ON_MAC_ENGINE_FEX_SO_SHA256 " ]'
  check "  it says which" has <(echo "$out") "^FEX: the engine's own FEX (athei/FEX $ENGINE_FEX) is in the engine$"
  # A switch cut short (a kill, the Mac off) after any of its renames, done here by hand in the
  # switch's order, with the setting already saved: the next switch finishes it. fex_cut <to> <n>:
  # the way to <to> from the other, cut after its first <n> renames (to mine after the copies)
  fex_cut() {
    local f i=0
    sed -i '' "s/^fex=.*/fex=$1/" "$AD/settings.conf"
    if [ "$1" = mine ]; then
      for f in $FEXF; do cp -p "$(fex_src_of "$f")" "$FW/$f.new"; done
      for f in $FEXF; do
        [ $i -lt "$2" ] || return 0; mv "$FW/$f" "$FW/$f.engine"; i=$((i + 1))
        [ $i -lt "$2" ] || return 0; mv "$FW/$f.new" "$FW/$f"; i=$((i + 1))
      done
    else
      for f in $FEXF; do [ $i -lt "$2" ] || return 0; mv -f "$FW/$f.engine" "$FW/$f"; i=$((i + 1)); done
    fi
  }
  for n in 0 1 2 3 4 5; do
    fex_cut mine $n
    want=mix; [ $n != 0 ] || want=engine
    check "cut short on the way to mine after $n of 6 renames: fex_file=$want, fex_ready=switch; set fex mine finishes it$([ $n = 0 ] || echo ", saying so")" \
      eval '[ "$(st fex_file)/$(st fex_ready)" = "$want/switch" ] && out=$(g set fex mine 2>&1) && fex_is mine && [ -z "$(FEXLEFT | grep "\.new$")" ] && { [ $n = 0 ] || echo "$out" | grep -q "^FEX: the engine.s FEX files are a mix of my FEX and the engine.s own, a switch cut short; finishing the switch to my FEX"; }'
    g set fex engine >/dev/null
  done
  # the other way after a cut on the way to mine: set fex engine puts the engine's own back and
  # removes the copies that switch made
  for n in 0 1 2 3 4 5; do
    fex_cut mine $n
    check "cut short on the way to mine after $n of 6 renames, then set fex engine: the engine's own, nothing left over" \
      eval 'g set fex engine >/dev/null && fex_is engine && [ -z "$(FEXLEFT)" ]'
  done
  for n in 1 2; do
    g set fex mine >/dev/null
    fex_cut engine $n
    check "cut short on the way back after $n of 3 renames: a mix; set fex engine finishes it, nothing left over" \
      eval '[ "$(st fex_file)/$(st fex_ready)" = "mix/switch" ] && g set fex engine >/dev/null && fex_is engine && [ -z "$(FEXLEFT)" ]'
  done
  # an earlier build of mine (an older version of the app's) in place of all three
  g set fex mine >/dev/null
  for f in $FEXF; do echo "an earlier build of mine" >"$FW/$f"; done
  check "an earlier build of my FEX in place: fex_file=other, fex_ready=switch; set fex mine puts this build's in" \
    eval '[ "$(st fex_file)/$(st fex_ready)/$(st fex_commit)" = other/switch/ ] && g set fex mine >/dev/null && fex_is mine'
  g set fex engine >/dev/null
  check "  the engine's own FEX and wine.app as they ship through all of it" eval 'fex_is engine && [ -z "$(FEXLEFT)" ] && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
else
  out=$(g set fex mine 2>&1) && rc=0 || rc=$?
  check "no FEX of mine in this app: set fex mine refused, saying so; the engine's files untouched" \
    eval '[ "$rc" != 0 ] && [ "$out" = "@error This build carries no FEX of mine." ] && [ "$(sett fex_state)" = "off:This build carries no FEX of mine." ] && fex_is engine'
  sed -i '' 's/^fex=.*/fex=mine/' "$AD/settings.conf"
  g set dxmt engine >/dev/null; g set dxmt fork >/dev/null
  check "  fex=mine in settings.conf by hand: the engine's own stays through the engine's switches" eval 'fex_is engine && [ "$(st fex_ready)/$(st fex_file)" = yes/engine ]'
  sed -i '' 's/^fex=.*/fex=engine/' "$AD/settings.conf"
fi
check "set ncpu all: no WINENCPU" sh -c "'$G' set ncpu all >/dev/null && ! '$G' env | grep -q WINENCPU"
MAXC=$(sysctl -n hw.logicalcpu)
# (GitHub's runners have 3 CPUs, too few for the checks of 6 and 8)
if [ "$MAXC" -ge 6 ]; then check "set ncpu 6: WINENCPU=6" sh -c "'$G' set ncpu 6 >/dev/null && '$G' env | grep -qx WINENCPU=6"; else echo "  skip   set ncpu 6 (this Mac has $MAXC CPUs)"; fi
check "settings: cpus=$MAXC (the Mac's logical CPUs)" [ "$(sett cpus)" = "$MAXC" ]
check "set ncpu 2 (the fewest): WINENCPU=2" sh -c "'$G' set ncpu 2 >/dev/null && '$G' env | grep -qx WINENCPU=2"
check "set ncpu 7 (steps of 1)" sh -c "[ $MAXC -lt 7 ] || '$G' set ncpu 7 >/dev/null"
check "set ncpu $MAXC (every CPU, by number): WINENCPU=$MAXC" sh -c "'$G' set ncpu $MAXC >/dev/null && '$G' env | grep -qx WINENCPU=$MAXC"
check "ncpu 1 refused" sh -c "'$G' set ncpu 1 >/dev/null; [ \$? = 2 ]"
check "ncpu $((MAXC + 1)) (more than the Mac has) refused" sh -c "'$G' set ncpu $((MAXC + 1)) >/dev/null; [ \$? = 2 ]"
if [ "$MAXC" -ge 8 ]; then check "ncpu 8 again" g set ncpu 8; else echo "  skip   ncpu 8 again (this Mac has $MAXC CPUs)"; fi
check "set fpscap 60: dxmt.conf caps at 60" sh -c "'$G' set fpscap 60 >/dev/null && grep -q 'd3d11.preferredMaxFrameRate = 60' '$AD/dxmt.conf'"
check "set fpscap off: no cap" sh -c "'$G' set fpscap off >/dev/null && ! grep -q preferredMaxFrameRate '$AD/dxmt.conf'"
# (and with my winemac.so, its channel for Gw2-64.exe)
WINEDEBUG_ON="err+all,fixme-all$(! drv || echo ,Gw2-64.exe:+macsurface)"
check "set debug on: DXMT_LOG_LEVEL=debug, DXMT_STATS=1 and Wine's errors$(! drv || echo ", and my Mac driver's macsurface for Gw2-64.exe")" sh -c "'$G' set debug on >/dev/null && '$G' env | grep -qx DXMT_LOG_LEVEL=debug && '$G' env | grep -qx DXMT_STATS=1 && [ \"\$('$G' env | grep ^WINEDEBUG=)\" = WINEDEBUG=$WINEDEBUG_ON ]"
if drv; then
  check "  with macdrv engine: Wine's errors only" sh -c "'$G' set macdrv engine >/dev/null && [ \"\$('$G' env | grep ^WINEDEBUG=)\" = WINEDEBUG=err+all,fixme-all ] && '$G' set macdrv mine >/dev/null"
fi
check "set debug off: none of them" sh -c "'$G' set debug off >/dev/null && ! '$G' env | grep -q -e DXMT_LOG_LEVEL -e DXMT_STATS && [ \"\$('$G' env | grep ^WINEDEBUG=)\" = WINEDEBUG=-all ]"
g set retina off >/dev/null; check "set retina off: RetinaMode=n" reg "$ALL_MAC" RetinaMode n
g set retina on >/dev/null; check "set retina on: RetinaMode=y" reg "$ALL_MAC" RetinaMode y
check "  one value (not added twice)" [ "$(grep -c '^"RetinaMode"=' "$BOTTLE/user.reg")" = 1 ]
check "status: gamemode=engine (nothing to switch)" [ "$(st gamemode)" = engine ]
check "settings: rawmouse=on, mousespeed=1 by default" [ "$(sett rawmouse)/$(sett mousespeed)" = on/1 ]
check "  no physkeys setting (refused, exit 2; not in the settings)" sh -c "'$G' set physkeys on >/dev/null; [ \$? = 2 ] && ! '$G' settings | grep -q '^physkeys='"
check "  nothing of the mouse in the registry (this engine reads the mouse itself)" sh -c "! grep -q RawMouse '$BOTTLE/user.reg'"
check "mousespeed 4 refused (exit 2)" sh -c "'$G' set mousespeed 4 >/dev/null; [ \$? = 2 ]"
# A Play holds the session's lock from before it starts Wine (and its watcher for the session): a
# setting saved meanwhile leaves user.reg alone, and a Play can't start while a registry write
# holds the lock (the same flock, one holder at a time)
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 30 & hp=$!
i=0; until "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock" || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
check "set retina off while a Play holds the session's lock: saved" sh -c "'$G' set retina off | grep -q '@done' && [ \"\$('$G' settings | sed -n 's/^retina=//p')\" = off ]"
check "  but the registry is left alone" reg "$ALL_MAC" RetinaMode y
check "  and the lock is still the Play's" "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock"
kill $hp 2>/dev/null; wait $hp 2>/dev/null
check "  once it's free, a setting writes the registry and lets the lock go" sh -c "'$G' set retina off >/dev/null && ! '$APP/Contents/Resources/helpers/sessionlock' held '$AD/.session.lock'"
check "  RetinaMode=n" reg "$ALL_MAC" RetinaMode n
g set retina on >/dev/null
check "set launchopts -maploadinfo" g set launchopts "-maploadinfo"
check "launchopts with a ; refused" sh -c "! '$G' set launchopts '-x; rm -rf /' >/dev/null"
check "unknown value refused (exit 2)" sh -c "'$G' set fpscap 45 >/dev/null; [ \$? = 2 ]"
check "unknown key refused" sh -c "! '$G' set colour red >/dev/null"
check "settings.conf has every key and settings_version" [ "$(grep -c '=' "$AD/settings.conf")" = 27 ]

section "The larger interface (addon)"
GD="$STEAM/steamapps/common/Guild Wars 2"
check "uiscale_addon=off by default" [ "$(sett uiscale_addon)" = off ]
check "set uiscale on" g set uiscale on
check "  version.dll in the game folder" same "$COMP/ui-scale/version.dll" "$GD/version.dll"
check "  the ini: scale 1.75, sans cronos, cinema 0 (off on this line)" sh -c "grep -qx 'scale=1.75' '$GD/gw2-ui-scale.ini' && grep -qx 'sans=cronos' '$GD/gw2-ui-scale.ini' && grep -qx 'cinema=0' '$GD/gw2-ui-scale.ini'"
check "  no registry override for it (the game's compatdb rules carry that on this line)" sh -c "! grep -q AppDefaults '$BOTTLE/user.reg'"
check "  uiscale_addon=on" [ "$(sett uiscale_addon)" = on ]
check "set uiscale_size 2.0 and sans off: the ini follows" sh -c "'$G' set uiscale_size 2.0 >/dev/null && '$G' set uiscale_sans off >/dev/null && grep -qx 'scale=2.0' '$GD/gw2-ui-scale.ini' && grep -qx 'sans=keep' '$GD/gw2-ui-scale.ini'"
echo "addon log" >"$GD/gw2-ui-scale.log"
check "set uiscale off: dll and ini gone, the log moved to Logs" sh -c "'$G' set uiscale off >/dev/null && [ ! -e '$GD/version.dll' ] && [ ! -e '$GD/gw2-ui-scale.ini' ] && [ ! -e '$GD/gw2-ui-scale.log' ] && ls '$LOGS'/gw2-ui-scale-*.log >/dev/null"
echo "another addon" >"$GD/version.dll"
check "another version.dll: uiscale_addon=foreign" [ "$(sett uiscale_addon)" = foreign ]
g set uiscale on >/dev/null 2>&1 || true
check "  turning it on leaves the other dll alone" has "$GD/version.dll" "another addon"
g set uiscale off >/dev/null 2>&1 || true
check "  turning it off leaves it alone too" has "$GD/version.dll" "another addon"
rm -f "$GD/version.dll"

section "arcdps (Settings › Interface)"
# Stand-in PEs (an x86_64 DLL whose export directory holds the given names; a fixture, not a
# loadable DLL): arcdps exports its extension API (addextension2) and names itself; another addon
# can carry those words elsewhere and is still not arcdps
le32w() { printf "\\x$(printf %02x $(($1 & 255)))\\x$(printf %02x $((($1 >> 8) & 255)))\\x$(printf %02x $((($1 >> 16) & 255)))\\x$(printf %02x $((($1 >> 24) & 255)))"; }
le16w() { printf "\\x$(printf %02x $(($1 & 255)))\\x$(printf %02x $((($1 >> 8) & 255)))"; }
make_pe() {   # <out> <export names...>
  local out=$1 strs n size
  shift
  strs="d3d11.dll"; for n in "$@"; do strs="$strs $n"; done
  size=$((40 + $(printf '%s\n' $strs | wc -c)))
  {
    printf 'MZ'; head -c 58 /dev/zero; le32w 64
    printf 'PE\0\0'; le16w 34404; le16w 1; head -c 12 /dev/zero; le16w 240; le16w 8226
    le16w 523; head -c 106 /dev/zero; le32w 16; le32w 4096; le32w "$size"; head -c 120 /dev/zero
    printf '.edata\0\0'; le32w 512; le32w 4096; le32w 512; le32w 512; head -c 16 /dev/zero
    head -c 144 /dev/zero
    head -c 12 /dev/zero; le32w 4136; le32w 1; head -c 20 /dev/zero
    for n in $strs; do printf '%s\0' "$n"; done
    head -c $((512 - size)) /dev/zero
  } >"$out"
}
ARCSRV="$SANDBOX/deltaconnected"
mkdir -p "$ARCSRV" "$SANDBOX/pe"
make_pe "$SANDBOX/pe/arcdps.dll" CreateDXGIFactory D3D11CreateDevice addextension2 listextension removeextension2
printf 'arcdps build 20261023 (stand-in)\n' >>"$SANDBOX/pe/arcdps.dll"
make_pe "$SANDBOX/pe/nexus.dll" CreateDXGIFactory D3D11CreateDevice
printf 'GetProcAddress addextension2 for arcdps\n' >>"$SANDBOX/pe/nexus.dll"
cp "$SANDBOX/pe/arcdps.dll" "$ARCSRV/d3d11.dll"
echo "$(md5 -q "$ARCSRV/d3d11.dll")  d3d11.dll" >"$ARCSRV/d3d11.dll.md5sum"
export GW2_ON_MAC_ARCDPS_URL="file://$ARCSRV"
arcst() { g status | sed -n "s/^arcdps_state=//p"; }
check "arcdps off by default: status arcdps=off, arcdps_state=off" [ "$(st arcdps)/$(arcst)" = off/off ]
check "  settings say so too, and settings.conf has no arcdps key" eval '[ "$(sett arcdps)/$(sett arcdps_state)" = off/off ] && ! grep -q "^arcdps=" "$AD/settings.conf"'
out=$(g set arcdps on 2>&1) && rc=0 || rc=$?
check "set arcdps on: downloads it (with progress) and says so" eval '[ "$rc" = 0 ] && echo "$out" | grep -q "^@progress arcdps " && echo "$out" | grep -q "^@done arcdps is in the game folder"'
check "  d3d11.dll next to Gw2-64.exe is the published file" same "$ARCSRV/d3d11.dll" "$GD/d3d11.dll"
check "  arcdps=on, arcdps_state=on" [ "$(st arcdps)/$(arcst)" = on/on ]
check "  nothing left in the downloads, no temporary file in the game folder" eval '[ ! -e "$CACHE/downloads/arcdps" ] && ! ls -a "$GD" | grep -q gw2om-new'
check "set arcdps on again: already there" sh -c "'$G' set arcdps on | grep -q 'already in the game folder'"
# arcdps updates itself: a newer arcdps (another hash) still counts as arcdps
printf 'self-updated\n' >>"$GD/d3d11.dll"
mkdir -p "$GD/addons/arcdps" && echo "[session]" >"$GD/addons/arcdps/arcdps.ini"
check "an arcdps that updated itself (another hash) is still on" [ "$(arcst)" = on ]
check "set arcdps off: d3d11.dll removed" sh -c "'$G' set arcdps off | grep -q '^@done arcdps is off' && [ ! -e '$GD/d3d11.dll' ]"
check "  its settings (addons/arcdps) stay" has "$GD/addons/arcdps/arcdps.ini" session
check "  arcdps_state=off" [ "$(arcst)" = off ]
check "arcdps x maybe refused (exit 2)" sh -c "'$G' set arcdps maybe >/dev/null; [ \$? = 2 ]"
# as dxgi.dll it counts too, and off removes it there
cp "$SANDBOX/pe/arcdps.dll" "$GD/dxgi.dll"
check "arcdps as dxgi.dll: on" [ "$(st arcdps)/$(arcst)" = on/on ]
g set arcdps off >/dev/null 2>&1
check "  off removes that dxgi.dll" [ ! -e "$GD/dxgi.dll" ]
# another addon's d3d11.dll (Nexus): foreign, never touched
cp "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"
check "another addon's d3d11.dll (with arcdps's words outside its exports): arcdps_state=foreign, arcdps=off" [ "$(arcst)/$(st arcdps)" = foreign/off ]
check "  arcdps_foreign names it" [ "$(st arcdps_foreign)" = d3d11.dll ]
out=$(g set arcdps on 2>&1) && rc=0 || rc=$?
check "  set arcdps on refused, saying why, the file left alone" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "^@error The game folder has another d3d11.dll" && same "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"'
check "  set arcdps off leaves it alone too" sh -c "'$G' set arcdps off | grep -q 'stays as it is' && cmp -s '$SANDBOX/pe/nexus.dll' '$GD/d3d11.dll'"
mv "$GD/d3d11.dll" "$GD/dxgi.dll"
check "  another addon's dxgi.dll: foreign as well" eval '[ "$(arcst)" = foreign ] && ! "$G" set arcdps on >/dev/null 2>&1 && same "$SANDBOX/pe/nexus.dll" "$GD/dxgi.dll"'
rm -f "$GD/dxgi.dll"
# a real PE DLL with other exports (the app's own interface addon) is not arcdps either
cp "$COMP/ui-scale/version.dll" "$GD/d3d11.dll"
check "a real d3d11.dll that isn't arcdps (the interface addon): foreign" [ "$(arcst)" = foreign ]
rm -f "$GD/d3d11.dll"
# the real arcdps, if my development workspace has a copy (only read)
ARCDPS_REAL="${ARCDPS_REAL:-$WS/work/arcdps/2026-11-08/d3d11.dll}"
if [ -f "$ARCDPS_REAL" ]; then
  cp "$ARCDPS_REAL" "$GD/d3d11.dll"
  check "the real arcdps (deltaconnected's d3d11.dll): on" [ "$(arcst)" = on ]
  rm -f "$GD/d3d11.dll"
else
  echo "  skip   the real arcdps (no $ARCDPS_REAL)"
fi
# a download that isn't the published file, a checksum that isn't one, no server
echo "something on the way" >>"$ARCSRV/d3d11.dll"
out=$(g set arcdps on 2>&1) && rc=0 || rc=$?
check "a download that doesn't match the published md5: refused, nothing placed" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "^@error The arcdps download is not the file deltaconnected.com publishes" && [ ! -e "$GD/d3d11.dll" ] && [ ! -e "$CACHE/downloads/arcdps" ]'
cp "$SANDBOX/pe/nexus.dll" "$ARCSRV/d3d11.dll"; echo "$(md5 -q "$ARCSRV/d3d11.dll")  d3d11.dll" >"$ARCSRV/d3d11.dll.md5sum"
check "  a matching file that isn't arcdps: refused" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "is not arcdps" && [ ! -e "$GD/d3d11.dll" ]'
echo "<html>portal</html>" >"$ARCSRV/d3d11.dll.md5sum"
check "  a checksum that is a web page: refused" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "is not a checksum" && [ ! -e "$GD/d3d11.dll" ]'
check "  no server: refused, saying so" sh -c "! GW2_ON_MAC_ARCDPS_URL='file://$SANDBOX/nowhere' '$G' set arcdps on >'$SANDBOX/arc.txt' 2>&1 && grep -q 'Check your internet connection' '$SANDBOX/arc.txt' && [ ! -e '$GD/d3d11.dll' ]"
cp "$SANDBOX/pe/arcdps.dll" "$ARCSRV/d3d11.dll"; echo "$(md5 -q "$ARCSRV/d3d11.dll")  d3d11.dll" >"$ARCSRV/d3d11.dll.md5sum"
check "the base address can be changed only in a sandbox" sh -c "grep -q '^\[ -z \"\$ROOT\" \] || ARCDPS_URL=' '$GW2OM'"
check "dry run: says what it would download, places nothing" sh -c "GW2_ON_MAC_DRY_RUN=1 '$G' set arcdps on | grep -q 'dry-run.*deltaconnected\|dry-run.*d3d11.dll.md5sum' && [ ! -e '$GD/d3d11.dll' ]"
# while a Play holds the session's lock, nothing changes in the game folder
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 30 & hp=$!
i=0; until "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock" || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
check "set arcdps on while a Play holds the session's lock: refused, nothing placed" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "session is starting" && [ ! -e "$GD/d3d11.dll" ]'
kill $hp 2>/dev/null; wait $hp 2>/dev/null
rm -rf "$GD/addons"

section "The game's compatdb rules (compatdb.rules)"
# The texts are pinned in scripts/compatdb-check/rules, which CI reads with Mach9 0.3.1's
# compatdb-core; there the sandbox's home is /Users/me
FIX="$ROOT/scripts/compatdb-check/rules"
rules_are() { g rules | sed "s|$H|/Users/me|g" | cmp -s - "$FIX/$1.rules"; }
# (the engine's own ntdll.so, so no WINE_HEAT_* entry, until the checks of my ntdll.so's switches below)
! mine || g set wine engine >/dev/null
check "everything off: the cache path for the game, taken away from CefHost.exe" rules_are off
g set hud on >/dev/null
check "the HUD on: metal_hud=true for the game, false for CefHost.exe" rules_are hud
g set hud off >/dev/null; g set uiscale on >/dev/null
check "the larger interface on: version native first" rules_are addon
g set hud on >/dev/null; cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"
check "the HUD and the larger interface on, arcdps in the game folder: d3d11 and dxgi native first too" rules_are hud-addon-arcdps
rm -f "$GD/version.dll"
check "  the addon's version.dll missing: the override stays (n,b loads Wine's own)" rules_are hud-addon-arcdps
cp "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"
check "  another addon's d3d11.dll (Nexus): native first as well" eval 'g rules | grep "^exe=Gw2-64.exe;metal_hud=true;dll_overrides=d3d11,dxgi=n,b;" >/dev/null'
g set hud off >/dev/null; g set uiscale off >/dev/null; rm -f "$GD/d3d11.dll"
check "  all off again" rules_are off
g set rawmouse off >/dev/null
check "raw mouse-look off: gcmouse=false for the game, nothing for CefHost.exe" \
  eval '[ "$(g rules | head -1)" = "exe=Gw2-64.exe;gcmouse=false;env=DXMT_SHADER_CACHE_PATH=$DXMT_CACHE" ] && [ "$(g rules | tail -1)" = "exe=CefHost.exe;env=DXMT_SHADER_CACHE_PATH=" ]'
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "  a dry run of Play prints the game's rule with it" eval 'echo "$out" | grep -qxF "[dry-run] rule $(g rules | head -1)"'
g set hud on >/dev/null
check "  and the HUD on: after exe, before metal_hud (Key::ALL's order)" rules_are rawmouse-off-hud
g set hud off >/dev/null; g set rawmouse on >/dev/null
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "raw mouse-look on: the rules as before, and the dry run's rule has no gcmouse" \
  eval 'rules_are off && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=" && ! echo "$out" | grep -q gcmouse'
g set dxmt engine >/dev/null
check "the engine's own DXMT: the game's shader cache is that DXMT's own" rules_are engine-dxmt
g set dxmt fork >/dev/null
g set debug on >/dev/null
check "Debug logging with the engine's ntdll.so: FEX_SILENTLOG=0 for the game, unset for CefHost.exe, and no FEX_PROFILESTATS (my ntdll.so reads the counters)" \
  rules_are debug-engine
g set debug off >/dev/null
check "  Debug logging off: neither" rules_are off
# FEX's switches (FEX_SWITCHES, empty in the app): the sandbox's table has a fork row and an any
# row, on two settings that are on by default and write nothing else into the rules. Their entries
# come after everything else, taken away from CefHost.exe again: the any row's always, the fork
# row's only with my FEX in place and its variable on my VERSION's switches: line (the four
# combinations; the staged VERSION back after)
FEXROWS="updates FEX_TESTFORK=1 fork
quitsteam FEX_TESTANY=1 any"
fexrules_are() { GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" rules_are "$1"; }
fex_named() { # yes|no: my FEX's VERSION names FEX_TESTFORK on its switches: line
  { grep -v '^switches:' "$SANDBOX/fex-VERSION.keep"; if [ "$1" = yes ]; then echo "switches: FEX_TESTFORK"; else echo "switches:"; fi; } >"$COMP/fex/VERSION"
}
if fexb; then cp "$COMP/fex/VERSION" "$SANDBOX/fex-VERSION.keep"; fi
check "FEX's switches, the engine's own FEX in place: the any row's entry alone" fexrules_are fex-any
if fexb; then
  fex_named yes
  check "  with my VERSION naming the fork row's variable: still the any row's alone" fexrules_are fex-any
  check "  the fork row's setting greyed with the reason, set refused" \
    eval '[ "$(GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" "$G" settings | sed -n "s/^updates_state=//p")" = "off:Needs my FEX, and the engine'"'"'s own is chosen." ] && ! GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" "$G" set updates on >/dev/null 2>&1'
  g set fex mine >/dev/null
  check "my FEX in place, its VERSION naming the variable: the fork row's entry, then the any row's" fexrules_are fex-fork-any
  check "  a dry run of Play prints the game's rule with them" \
    eval '[ "$(GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" GW2_ON_MAC_DRY_RUN=1 "$G" play 2>&1 | sed -n "s/^\[dry-run\] rule \(exe=Gw2-64\.exe;.*\)/\1/p")" = "$(head -1 "$FIX/fex-fork-any.rules" | sed "s|/Users/me|$H|")" ]'
  fex_named no
  check "my FEX in place, its VERSION not naming it: the any row's alone" fexrules_are fex-any
  check "  the fork row's setting greyed, saying so" \
    eval '[ "$(GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" "$G" settings | sed -n "s/^updates_state=//p")" = "off:My FEX in this app (jdrly/FEX ${MYFEX_COMMIT:0:11}) doesn'"'"'t have this switch." ]'
  fex_named yes
  GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" "$G" set quitsteam off >/dev/null
  check "  the any row's setting off: the fork row's entry alone" eval 'GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" g rules | head -1 | grep -q ";env=DXMT_SHADER_CACHE_PATH=[^;]*;env=FEX_TESTFORK=1$"'
  g set quitsteam on >/dev/null; g set fex engine >/dev/null
  cp "$SANDBOX/fex-VERSION.keep" "$COMP/fex/VERSION"
else
  check "  the fork row's setting greyed: no FEX of mine in this app" \
    eval '[ "$(GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" "$G" settings | sed -n "s/^updates_state=//p")" = "off:Needs my FEX, which this build of the app doesn'"'"'t have." ]'
fi
check "  without the sandbox's table (the app's, empty): no FEX_* entry" eval 'rules_are off && GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" g rules | grep -q FEX_TESTANY'
# My ntdll.so's switches (HEAT_SWITCHES): after the cache path, taken away from CefHost.exe again
if mine; then
  # dry_rule: the game's rule a dry run of Play prints, which has to be the rules' first line
  dry_rule() { GW2_ON_MAC_DRY_RUN=1 g play 2>&1 | sed -n 's/^\[dry-run\] rule \(exe=Gw2-64\.exe;.*\)/\1/p'; }
  g set wine mine >/dev/null; g set jobwakes off >/dev/null; g set eventpool off >/dev/null
  check "my ntdll.so, every switch off: WINE_HEAT_MSYNC_UNREG=1 alone, unset for CefHost.exe" rules_are heat-off
  check "  a dry run of Play prints the game's rule with it" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
  # (with my FEX in place too: the FEX my ntdll.so's sampler may read, from my FEX's VERSION, after
  # WINE_HEAT_MSYNC_UNREG=1, only for an ntdll.so whose VERSION names it on its switches: line; no
  # line, an empty one or one without it is no. The staged VERSION back after)
  if fexb; then
    FEXID=$(sed -n 's/^libarm64ecfex\.dll: build id \([0-9a-f]\{32\}\) age \([0-9]\{1,\}\), SizeOfImage \(0x[0-9a-f]\{1,\}\)$/\1:\2:\3/p' "$COMP/fex/VERSION")
    cp "$COMP/ntdll/VERSION" "$SANDBOX/ntdll-VERSION.prof"
    nt_switches() { { grep -v '^switches:' "$SANDBOX/ntdll-VERSION.prof"; [ "$1" = none ] || echo "switches:${1#-}"; } >"$COMP/ntdll/VERSION"; }
    g set fex mine >/dev/null
    nt_switches " WINE_HEAT_MSYNC_UNREG WINE_HEAT_PROF_FEX"
    check "  and my FEX in place, my ntdll.so's VERSION naming it: WINE_HEAT_PROF_FEX=<build id>:<age>:<SizeOfImage> after it, unset for CefHost.exe" \
      eval '[ -n "$FEXID" ] && [ "$(g rules | sed "s|$H|/Users/me|g" | tr "\n" "|")" = "$(head -1 "$FIX/heat-off.rules");env=WINE_HEAT_PROF_FEX=$FEXID|$(tail -1 "$FIX/heat-off.rules");env=WINE_HEAT_PROF_FEX=|" ]'
    for sw in none - " WINE_HEAT_MSYNC_UNREG"; do
      nt_switches "$sw"
      check "  an ntdll.so VERSION with $([ "$sw" = none ] && echo "no switches: line" || { [ "$sw" = - ] && echo "an empty switches: line" || echo "a switches: line without it"; }): no WINE_HEAT_PROF_FEX" \
        eval '! g rules | grep -q WINE_HEAT_PROF_FEX'
    done
    nt_switches " WINE_HEAT_MSYNC_UNREG WINE_HEAT_PROF_FEX"
    g set wine engine >/dev/null
    check "  my FEX with the engine's own ntdll.so: no WINE_HEAT_PROF_FEX" eval '! g rules | grep -q WINE_HEAT_PROF_FEX'
    g set wine mine >/dev/null; g set fex engine >/dev/null
    check "  the engine's own FEX with my ntdll.so: none either" rules_are heat-off
    cp "$SANDBOX/ntdll-VERSION.prof" "$COMP/ntdll/VERSION"
  fi
  g set jobwakes on >/dev/null
  check "job wakes on: WINE_HEAT_WAKE=one,skip for the game, unset for CefHost.exe" rules_are jobwakes
  check "  a dry run of Play prints the game's rule with it" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
  g set debug on >/dev/null
  check "  with Debug logging: the counters too, written to the logs folder, and FEX's counters and messages" rules_are jobwakes-debug
  g set debug off >/dev/null
  check "  Debug logging off again: neither of FEX's variables" eval 'rules_are jobwakes && ! g rules | grep -q FEX_'
  g set jobwakes off >/dev/null; g set eventpool on >/dev/null
  check "event pool on: WINE_HEAT_EVPOOL=1 for the game, unset for CefHost.exe" rules_are eventpool
  check "  a dry run of Play prints the game's rule with it" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
  g set eventpool off >/dev/null; g set fastlocks on >/dev/null
  check "fast locks on: WINE_HEAT_SPIN=lock=20:game,event=30:game for the game, unset for CefHost.exe" rules_are fastlocks
  check "  a dry run of Play prints the game's rule with it" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
  g set jobwakes on >/dev/null; g set eventpool on >/dev/null
  check "all three on: each entry, in the table's order" rules_are heat-all
  check "  a dry run of Play prints the game's rule with them" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
  # A VERSION with a switches: line (switch_in_file): an entry whose variable it doesn't name stays
  # out, and its row is greyed. The app reads the first switches: line, so the narrowed line
  # replaces any the VERSION has. Twice: from the staged VERSION as it is (a pull request's ntdll.so
  # has no switches: line), and from that VERSION with the full line of my d831f80 build added
  # (the dev build's ntdll.so has one). The staged VERSION back after
  cp "$COMP/ntdll/VERSION" "$SANDBOX/ntdll-VERSION.keep"
  for from in "the staged VERSION" "a VERSION with every switch"; do
    cp "$SANDBOX/ntdll-VERSION.keep" "$SANDBOX/ntdll-VERSION.from"
    [ "$from" = "the staged VERSION" ] ||
      echo "switches: WINE_HEAT_COUNT WINE_HEAT_EVPOOL WINE_HEAT_EXE WINE_HEAT_LOG WINE_HEAT_MSYNC_UNREG WINE_HEAT_PROF WINE_HEAT_PROF_HZ WINE_HEAT_PROF_THREADS WINE_HEAT_SPIN WINE_HEAT_SPIN_PAUSE WINE_HEAT_WAKE" >>"$SANDBOX/ntdll-VERSION.from"
    { grep -v '^switches:' "$SANDBOX/ntdll-VERSION.from"
      echo "switches: WINE_HEAT_COUNT WINE_HEAT_EXE WINE_HEAT_LOG WINE_HEAT_MSYNC_UNREG WINE_HEAT_WAKE"; } >"$COMP/ntdll/VERSION"
    check "from $from, a VERSION that lists WINE_HEAT_WAKE and WINE_HEAT_MSYNC_UNREG only: event pool and fast locks stay out" rules_are jobwakes
    check "  event pool and fast locks greyed, saying so; set refused" \
      eval '[ "$(sett jobwakes_state)" = ok ] && [ "$(sett eventpool_state)" = "off:My Wine build in this app (jdrly/wine ${MYWINE_COMMIT:0:11}) doesn'"'"'t have this switch." ] && [ "$(sett fastlocks_state)" = "$(sett eventpool_state)" ] && ! "$G" set fastlocks off >/dev/null 2>&1'
    cp "$SANDBOX/ntdll-VERSION.from" "$COMP/ntdll/VERSION"
    check "  $from again: all three" rules_are heat-all
  done
  cp "$SANDBOX/ntdll-VERSION.keep" "$COMP/ntdll/VERSION"
  g set debug on >/dev/null; g set wine engine >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "wine engine, every switch and Debug logging on: no WINE_HEAT_* nor FEX_PROFILESTATS in the rules or in a dry run of Play, FEX_SILENTLOG=0 alone" \
    eval 'rules_are debug-engine && ! echo "$out" | grep -qE "WINE_HEAT_|FEX_PROFILESTATS" && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=[^;]*;env=FEX_SILENTLOG=0$"'
  g set debug off >/dev/null; g set wine mine >/dev/null; g set jobwakes off >/dev/null; g set eventpool off >/dev/null; g set fastlocks off >/dev/null
else
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "no ntdll.so of mine, job wakes on by default: no WINE_HEAT_* in the rules or in a dry run of Play" \
    eval 'rules_are off && ! echo "$out" | grep -q WINE_HEAT_'
fi
# My Mac driver's switch (a row of HEAT_SWITCHES too): the same place, by its own file (with the
# engine's own ntdll.so, but where a check needs mine)
! mine || g set wine engine >/dev/null
if drv; then
  g set launcherframes on >/dev/null
  check "launcher frames on: WINE_MACDRV_SURFACE=copy,skip for the game, unset for CefHost.exe" rules_are launcherframes
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "  a dry run of Play prints the game's rule with it" eval 'echo "$out" | grep -qxF "[dry-run] rule $(g rules | head -1)" && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;.*;env=WINE_MACDRV_SURFACE=copy,skip$"'
  if mine; then
    g set wine mine >/dev/null; g set jobwakes on >/dev/null; g set debug on >/dev/null
    check "  with my ntdll.so, job wakes and Debug logging: both files' switches in the table's order, then the counters" rules_are launcherframes-jobwakes-debug
    g set debug off >/dev/null; g set jobwakes off >/dev/null; g set wine engine >/dev/null
  fi
  g set launcherframes off >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "launcher frames off: no WINE_MACDRV_* in the rules or in a dry run of Play" eval 'rules_are off && ! echo "$out" | grep -q WINE_MACDRV_'
  # Mouse-look speed: a factor other than 1 is an entry with the value, after launcher frames'. With
  # a VERSION whose switches: line names it (switch_in_file), as the staged driver may be a build from
  # before it; the staged VERSION back at the end
  cp "$COMP/macdrv/VERSION" "$SANDBOX/macdrv-VERSION.keep"
  drv_switches() { { grep -v '^switches:' "$SANDBOX/macdrv-VERSION.keep"; echo "switches: $*"; } >"$COMP/macdrv/VERSION"; }
  drv_switches WINE_MACDRV_MOUSE_SCALE WINE_MACDRV_SURFACE
  g set mousespeed 1.5 >/dev/null
  check "mouse-look speed 1.5: WINE_MACDRV_MOUSE_SCALE=1.5 for the game, unset for CefHost.exe" rules_are mousespeed
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "  a dry run of Play prints the game's rule with it" eval 'echo "$out" | grep -qxF "[dry-run] rule $(g rules | head -1)" && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;.*;env=WINE_MACDRV_MOUSE_SCALE=1.5$"'
  g set launcherframes on >/dev/null
  check "  with launcher frames on: after WINE_MACDRV_SURFACE, in the table's order" eval 'g rules | head -1 | grep -q ";env=WINE_MACDRV_SURFACE=copy,skip;env=WINE_MACDRV_MOUSE_SCALE=1.5$"'
  g set launcherframes off >/dev/null; g set rawmouse off >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "  raw mouse-look off: no WINE_MACDRV_* in the rules or in a dry run of Play" eval '! g rules | grep -q WINE_MACDRV_ && ! echo "$out" | grep -q WINE_MACDRV_'
  g set rawmouse on >/dev/null
  # A build from before the factor names WINE_MACDRV_SURFACE alone
  drv_switches WINE_MACDRV_SURFACE
  check "a VERSION that lists WINE_MACDRV_SURFACE only: mouse-look speed greyed, saying so, set refused, its entry out" \
    eval '[ "$(sett mousespeed_state)" = "off:My Mac driver in this app (jdrly/wine ${MYDRV_COMMIT:0:11}) doesn'"'"'t have this switch." ] && [ "$(sett launcherframes_state)" = ok ] && ! "$G" set mousespeed 2 >/dev/null 2>&1 && rules_are off'
  drv_switches WINE_MACDRV_MOUSE_SCALE WINE_MACDRV_SURFACE
  check "  one that lists WINE_MACDRV_MOUSE_SCALE too: ok, and the entry back" eval '[ "$(sett mousespeed_state)" = ok ] && rules_are mousespeed'
  g set mousespeed 1 >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "mouse-look speed 1: no WINE_MACDRV_* in the rules or in a dry run of Play" \
    eval 'rules_are off && ! echo "$out" | grep -q WINE_MACDRV_ && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=[^;]*$"'
  g set launcherframes on >/dev/null; g set mousespeed 1.5 >/dev/null; g set macdrv engine >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "macdrv engine with launcher frames on and mouse-look speed 1.5: no WINE_MACDRV_* in the rules or in a dry run of Play" \
    eval 'rules_are off && ! echo "$out" | grep -q WINE_MACDRV_ && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=[^;]*$"'
  check "  mouse-look speed greyed with launcher frames' reason" eval '[ "$(sett mousespeed_state)" = "off:Needs my Mac driver, and the engine'"'"'s own winemac.so is chosen." ] && [ "$(sett launcherframes_state)" = "$(sett mousespeed_state)" ]'
  if mine; then
    g set wine mine >/dev/null; g set jobwakes on >/dev/null
    check "  and my ntdll.so's switches stay, apart from it" rules_are jobwakes
    g set jobwakes off >/dev/null; g set wine engine >/dev/null
  fi
  g set macdrv mine >/dev/null; g set launcherframes off >/dev/null; g set mousespeed 1 >/dev/null
  cp "$SANDBOX/macdrv-VERSION.keep" "$COMP/macdrv/VERSION"
else
  sed -i '' -e 's/^launcherframes=.*/launcherframes=on/' -e 's/^mousespeed=.*/mousespeed=1.5/' "$AD/settings.conf"
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "no winemac.so of mine, launcher frames on and mouse-look speed 1.5 in settings.conf: no WINE_MACDRV_* in the rules or in a dry run of Play" \
    eval 'rules_are off && ! echo "$out" | grep -q WINE_MACDRV_'
  sed -i '' -e 's/^launcherframes=.*/launcherframes=off/' -e 's/^mousespeed=.*/mousespeed=1/' "$AD/settings.conf"
fi
! mine || g set wine mine >/dev/null
# A home with odd characters, in a fresh root: its settings.conf (the engine's ntdll.so, Debug logging off,
# at settings_version 2 so wine=engine isn't reset) is all there is in it
ODD="$SANDBOX/a%b;c$(printf '\t')d é"
ODD_CONF="$ODD/home/Library/Application Support/$APP_FOLDER/settings.conf"
mkdir -p "${ODD_CONF%/*}" && printf 'settings_version=2\nwine=engine\ndebug=off\n' >"$ODD_CONF"
odd_rules_are() { GW2_ON_MAC_ROOT="$ODD" "$G" rules | sed "s|$SANDBOX/a%25b%3Bc%09d é/home|/Users/a%25b%3Bc%09d é|g" | cmp -s - "$FIX/$1.rules"; }
odd_only_conf() { [ "$(cd "$ODD" && find . | LC_ALL=C sort | tr '\n' '|')" = ".|./home|./home/Library|./home/Library/Application Support|./home/Library/Application Support/$APP_FOLDER|./home/Library/Application Support/$APP_FOLDER/settings.conf|" ]; }
check "a home with %, ; and a tab: escaped as %XX, the é as it is" eval 'odd_rules_are escaped && odd_only_conf'
if mine; then
  printf 'jobwakes=on\neventpool=off\ndebug=on\n' >"$ODD_CONF"
  check "  with job wakes and Debug logging on: the logs folder escaped the same way" eval 'odd_rules_are escaped-heat && odd_only_conf'
fi
rm -rf "$ODD"
printf 'exe=Gw2-64.exe;env=FEX_HOSTFEATURES=disableavx\n' >"$AD/compatdb.local"
check "compatdb.local is appended as it is" eval '[ "$(g rules | tail -1)" = "exe=Gw2-64.exe;env=FEX_HOSTFEATURES=disableavx" ] && [ "$(g rules | wc -l | tr -d " ")" = 3 ]'
# a dry run of play with every setting of 0.1.x's environment on in settings.conf
cp "$AD/settings.conf" "$SANDBOX/settings.keep"
sed -i '' -e 's/^metalfx=.*/metalfx=on/' -e 's/^hud=.*/hud=on/' -e 's/^debug=.*/debug=on/' "$AD/settings.conf"
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "dry-run play: the engine's variables, the app's files, my DXMT fork's switches and the CPUs, nothing else" \
  eval '[ "$(echo "$out" | sed -n "s/^\[dry-run\]   //p" | grep -v ^WINENCPU= | tr "\n" "|")" = "WINEPREFIX=$BOTTLE|WINEDEBUG=$WINEDEBUG_ON|WINEDLLOVERRIDES=winemenubuilder.exe=d|WINEMSYNC=1|DXMT_CONFIG_FILE=$AD/dxmt.conf|DXMT_LOG_PATH=$LOGS|WINE_COMPATDB_FILE=$AD/compatdb.rules|DXMT_CACHE_DIR=$CACHE/fork|DXMT_DEPENDENCY_COMPRESSION=1|DXMT_WARM=all|DXMT_SUBSAMPLE_METALFX=1|DXMT_LOG_LEVEL=debug|DXMT_STATS=1|" ] && echo "$out" | grep -q "^\[dry-run\]   WINENCPU="'
check "  none of 0.1.x's Wine variables in the environment (my ntdll.so's switches are in the rules)" \
  eval '! echo "$out" | sed -n "s/^\[dry-run\]   //p" | grep -qE "WINE_HEAT_|ROSETTA_X87_PATH|WINEDLLPATH|WINE_COMPATDB=|MTL_HUD"'
cp "$SANDBOX/settings.keep" "$AD/settings.conf"
# (job wakes and the event pool on again, their defaults, for the sessions below)
! mine || { g set jobwakes on >/dev/null; g set eventpool on >/dev/null; }

section "Play"
: >"$STANDIN_LOG"
out=$(g play 2>&1) && rc=0 || rc=$?
started
check "play exits 0" [ "$rc" = 0 ]
check "Steam -applaunch 1284210 with the launch options" has "$STANDIN_LOG" 'steam.exe -applaunch 1284210 -maploadinfo'
check "  with DXMT's config file and the rules file" eval 'has "$STANDIN_LOG" "DXMT_CONFIG_FILE=$AD/dxmt.conf" && grep -qxF "  WINE_COMPATDB_FILE=$AD/compatdb.rules" "$STANDIN_LOG"'
check "  play wrote compatdb.rules before it: the rules and compatdb.local" eval '[ "$(cat "$AD/compatdb.rules")" = "$(g rules)" ] && grep -q FEX_HOSTFEATURES "$AD/compatdb.rules"'
check "  session.env records the engine, its commits, the settings, the environment and the rules" \
  eval 'has "$LOGS/session.env" "^ENGINE=mach9-v0.3.1$" && has "$LOGS/session.env" "^ENGINE_FEX=" && has "$LOGS/session.env" "^SETTING_hud=off$" && has "$LOGS/session.env" "^WINE_COMPATDB_FILE=" && [ "$(sed -n "s/^RULE=//p" "$LOGS/session.env")" = "$(cat "$AD/compatdb.rules")" ]'
check "  and which DXMT the session loads: my fork, its build" \
  eval 'has "$LOGS/session.env" "^DXMT_TREE=fork$" && [ "$(sed -n "s/^DXMT_FORK=//p" "$LOGS/session.env")" = "$(head -1 "$COMP/dxmt/VERSION")" ] && has "$LOGS/session.env" "^SETTING_dxmt=fork$"'
if mine; then
  check "  and which ntdll.so: mine, its commit and the sha256 of the file in the engine; its switches in the game's rule" \
    eval '[ "$(sed -n "s/^LIB_wine=//p" "$LOGS/session.env")" = "ntdll.so mine $MYWINE_COMMIT $(shasum -a 256 "$COMP/ntdll/ntdll.so" | cut -d" " -f1)" ] && grep -q "^RULE=exe=Gw2-64.exe;.*;env=WINE_HEAT_WAKE=one,skip;env=WINE_HEAT_EVPOOL=1;env=WINE_HEAT_MSYNC_UNREG=1$" "$LOGS/session.env"'
else
  check "  and which ntdll.so: the engine's own, no WINE_HEAT_* in the rules" \
    eval '[ "$(sed -n "s/^LIB_wine=//p" "$LOGS/session.env")" = "ntdll.so engine $ENGINE_WINE $GW2_ON_MAC_ENGINE_NTDLL_SHA256" ] && ! grep -q WINE_HEAT_ "$LOGS/session.env"'
fi
if drv; then
  check "  and which winemac.so: mine, its commit and the sha256 of the file in the engine" \
    eval '[ "$(sed -n "s/^LIB_macdrv=//p" "$LOGS/session.env")" = "winemac.so mine $MYDRV_COMMIT $(shasum -a 256 "$COMP/macdrv/winemac.so" | cut -d" " -f1)" ]'
else
  check "  and which winemac.so: the engine's own, no WINE_MACDRV_* in the rules" \
    eval '[ "$(sed -n "s/^LIB_macdrv=//p" "$LOGS/session.env")" = "winemac.so engine $ENGINE_WINE $GW2_ON_MAC_ENGINE_WINEMAC_SHA256" ] && ! grep -q WINE_MACDRV_ "$LOGS/session.env"'
fi
check "  and which FEX: the engine's own (fex=engine by default)" eval '[ "$(sed -n "s/^LIB_fex=//p" "$LOGS/session.env")" = engine ]'

section "Collect Logs (redaction and the leak check)"
mkdir -p "$STEAM/config" "$STEAM/logs" "$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2"
printf '"users"\n{\n\t"76561198000000042"\n\t{\n\t\t"AccountName"\t\t"zz_acct_name"\n\t\t"PersonaName"\t\t"Zz Persona Q"\n\t}\n}\n' >"$STEAM/config/loginusers.vdf"
printf '[2026-11-04] AppID 1284210 update started : download 0/58900000000\nUser zz_acct_name (76561198000000042) [U:1:39734314] logged in, path %s\n' "$HOME/Library" >"$STEAM/logs/content_log.txt"
printf 'Crash\nName: ZZ-MACHINE\nIpAddr: 192.168.77.5\nLogin: zz.person@example.com\nException: c0000005\n' >"$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2/ArenaNet.log"
printf 'started by %s from %s/Library, mail zz.person@example.com, token=abcDEF123secret\n' "$(id -un)" "$HOME" >>"$LOGS/wine.log"
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\ninfo:  STATS fps=60.0 ms=16.7/24.8 cb=1.1 rp=31.7(+0.0 merged) encode=0.23+1.03/10.3\ninfo:  HITCH frame=52 ms=120.0 dxmt(ms/calls): create=4.0/37 flush=3.5/1\n' >"$LOGS/Gw2-64_d3d11.log"
mkdir -p "$GD/addons/arcdps" && printf 'crash\nself: Zz Charname Q, zz_arc_acct.1234\n' >"$GD/addons/arcdps/arcdps_lastcrash.log"
echo "info: build" >"$GD/addons/arcdps/arcdps.log"; cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"
# (the heat counters of 4 games in the logs folder, whose name has spaces, each with its server
# requests, older than session.env so the session report leaves them alone, and a profile)
n=0
for pid in 9101 9202 9303 9404; do
  n=$((n + 1))
  echo "heat pid $pid" >"$LOGS/heat-$pid.log"; echo "requests pid $pid" >"$LOGS/heat-requests-$pid.log"
  touch -t "20250101000$n" "$LOGS/heat-$pid.log" "$LOGS/heat-requests-$pid.log"
done
echo "profile" >"$LOGS/heat-prof-9404.log"
# (a stand-in for macOS's vmmap, $ROOT/bin/vmmap: it notes the pid it was given and prints an
# excerpt of the first 0.2 session's, with FEX's three code buffers among other regions)
# (with the file vmmap.hang it hangs instead)
{ printf '#!/bin/bash\necho "$1" >>"%s/vmmap.args"\n[ ! -e "%s/vmmap.hang" ] || exec sleep 60\ncat <<'"'"'MAP'"'"'\n' "$SANDBOX" "$SANDBOX"; cat <<'EOF'; echo MAP; } >"$SANDBOX/bin/vmmap"
Process:         Gw2-64.exe [70549]
Path:            /Users/*/Library/Application Support/GW2 on Mac arm64/*/wine.app/Contents/MacOS/wine
Load Address:    0x104508000
Identifier:      wine
Version:         11.21 (0)
Code Type:       ARM64
Platform:        macOS
Parent Process:  launchd [1]
Target Type:     live task (Roots Present)

Date/Time:       2026-11-11 18:29:37.635 +0100
Launch Time:     2026-11-11 18:22:04.591 +0100
OS Version:      macOS 27.2 (26B123)
Report Version:  7
Analysis Tool:   /usr/bin/vmmap

Physical footprint:         8.4G
Physical footprint (peak):  9.0G
Idle exit:                  untracked
----

Virtual Memory Map of process 70549 (Gw2-64.exe)
Output report format:  2.4  -- 64-bit process
VM page size:  16384 bytes
Collected with PhysFootprint mode enabled

==== regions for process 70549  (non-writable and writable regions are interleaved)
REGION TYPE                    START - END         [ VSIZE  RSDNT  DIRTY   SWAP] PRT/MAX SHRMOD PURGE    REGION DETAIL
mapped file                     10000-12000        [    8K     8K     0K     0K] r--/r-x SM=ALI          /Users/USER/Library/Application Support/GW2 o
Untagged                        12000-22000        [   64K     0K     0K     0K] ---/rwx SM=NUL
Untagged                 7fe9dbbf1000-7fe9dbff1000 [ 4096K     0K     0K    16K] rw-/rwx SM=COW
Untagged                 7fe9dbff1000-7fe9dbff2000 [    4K     0K     0K     0K] ---/rwx SM=NUL
Untagged                 7fe9dc000000-7fe9dffff000 [ 64.0M  25.4M  25.4M   224K] rwx/rwx SM=PRV
Untagged                 7fe9dffff000-7fe9e0000000 [    4K     0K     0K     0K] ---/rwx SM=PRV
Untagged                 7fea90b90000-7fea91b90000 [ 16.0M     0K     0K   112K] rw-/rwx SM=COW
Untagged                 7fea91b90000-7fea93b8f000 [ 32.0M  24.8M  24.8M  7392K] rwx/rwx SM=PRV
Untagged                 7fea93b8f000-7fea93b90000 [    4K     4K     4K     0K] ---/rwx SM=PRV
Untagged                 7feffdb30000-7feffdb31000 [    4K     4K     4K     0K] rw-/rwx SM=COW
Untagged                 7feffdb40000-7feffeb3f000 [ 16.0M  9280K  9280K  7100K] rwx/rwx SM=PRV
Untagged                 7feffeb3f000-7feffeb40000 [    4K     0K     0K     4K] ---/rwx SM=PRV
owned unmapped (graphics)    unmapped-unmapped     [  352K   352K   352K     0K] rw-/rw- SM=PRV PURGE=N  owned physical footprint (unmapped) (graphics
page table in kernel           kernel-kernel       [ 21.8M  21.8M  21.8M     0K] rw-/rw- SM=PRV          charged to process physical footprint

==== Legend
SM=sharing mode:
        COW=copy_on_write PRV=private NUL=empty ALI=aliased
        SHM=shared ZER=zero_filled S/A=shared_alias
PURGE=purgeable mode:
        V=volatile N=nonvolatile E=empty   otherwise is unpurgeable

==== Summary for process 70549
ReadOnly portion of Libraries: Total=3.0G resident=898.2M(29%) swapped_out_or_unallocated=2.1G(71%)
Writable regions: Total=268.0G written=5.0G(2%) resident=6.2G(2%) swapped_out=1.2G(0%) unallocated=260.6G(97%)

                                VIRTUAL RESIDENT    DIRTY  SWAPPED VOLATILE   NONVOL    EMPTY   REGION
REGION TYPE                        SIZE     SIZE     SIZE     SIZE     SIZE     SIZE     SIZE    COUNT (non-coalesced)
===========                     ======= ========    =====  ======= ========   ======    =====  =======
Accelerate Framework               128K      32K      32K      96K       0K      32K       0K        1
Activity Tracing                   256K      24K      48K       0K       0K      24K       0K        1
page table in kernel              21.8M    21.8M    21.8M       0K       0K       0K       0K        1
shared memory                     13.7M    12.8M    12.8M       0K       0K      12K       0K       46
unused but dirty shlib __DATA      420K     243K     243K     177K       0K       0K       0K      353
===========                     ======= ========    =====  ======= ========   ======    =====  =======
TOTAL                              1.0T     7.3G     6.7G     1.4G      68K   514.4M    11.5M    52825
TOTAL, minus reserved VM space   745.6G     7.3G     6.7G     1.4G      68K   514.4M    11.5M    52825
EOF
chmod 755 "$SANDBOX/bin/vmmap"
rm -f "$SANDBOX/vmmap.args"
mkdir -p "$SANDBOX/zip"
zip=$("$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip" 2>"$SANDBOX/collect.err" | tail -1)
check "collect-logs makes a zip" [ -f "$zip" ]
rm -rf "$SANDBOX/unzipped" && mkdir -p "$SANDBOX/unzipped" && (cd "$SANDBOX/unzipped" && unzip -q "$zip")
Z="$SANDBOX/unzipped/$(basename "$zip" .zip)"
check "  no game running: no vmmap taken, and no vmmap file in the logs folder or the zip" \
  eval '[ ! -e "$SANDBOX/vmmap.args" ] && ! ls "$LOGS" "$Z/logs" | grep -q "^vmmap-"'
for f in logs/install.log logs/wine.log logs/Gw2-64_d3d11.log settings.conf compatdb.rules compatdb.local install-manifest.json session-report.txt system-info.txt gpu-errors.txt game-logs/ArenaNet.log game-logs/steam/content_log.txt; do
  check "  has $f" [ -f "$Z/$f" ]
done
for pid in 9202 9303 9404; do
  check "  has the heat log of game $pid and its server requests" sh -c "[ -f '$Z/logs/heat-$pid.log' ] && [ -f '$Z/logs/heat-requests-$pid.log' ]"
done
check "  but not the 4th newest game's, nor the profile" \
  sh -c "[ ! -e '$Z/logs/heat-9101.log' ] && [ ! -e '$Z/logs/heat-requests-9101.log' ] && [ ! -e '$Z/logs/heat-prof-9404.log' ]"
for pid in 9101 9202 9303 9404; do rm -f "$LOGS/heat-$pid.log" "$LOGS/heat-requests-$pid.log"; done
rm -f "$LOGS/heat-prof-9404.log"
check "  the session report read DXMT's log" has "$Z/session-report.txt" "Frame rate: median 60.0"
check "  and says which DXMT ran: my fork, its build" has "$Z/session-report.txt" "^DXMT that ran: my DXMT fork, $(head -1 "$COMP/dxmt/VERSION" | cut -c1-20)"
check "  and which mouse the game had: GameController's (raw mouse-look on)" has "$Z/session-report.txt" "^Mouse the game had: the mouse's own counts from GameController"
if mine; then
  check "  and which ntdll.so ran, with its switches" \
    eval 'has "$Z/session-report.txt" "^ntdll.so that ran: my Wine build, jdrly/wine ${MYWINE_COMMIT:0:11} (sha256 " && has "$Z/session-report.txt" "^Its switches: WINE_HEAT_WAKE=one,skip WINE_HEAT_EVPOOL=1 WINE_HEAT_MSYNC_UNREG=1$"'
  # (a heat log of the session: three threads, the game thread the one with the most releases)
  printf 'heat pid 4242 exe Gw2-64.exe mode count one skip seconds 10.0 threads 3\ntotal release 520000 wake_skipped 410000 wake_one 1 wake_none 3\nthread 0024 release 20000 wake_skipped 1000 wake_one 19000 wake_none 0 server_ms 0.5\nthread 00a4 release 490000 wake_skipped 410000 wake_one 80000 wake_none 3 server 70 server_ms 0.2\nthread 00b0 release 10000 wake_skipped 0 wake_one 1 wake_none 0 server_ms 0.1\n' >"$LOGS/heat-4242.log"
  touch -t 202601010000 "$LOGS/session.env"
  out=$("$APP/Contents/Resources/session-report.sh" 2>&1)
  check "  the session's heat log: the game thread's row, a second" \
    has <(echo "$out") "^Heat log heat-4242.log (10 s): the game thread, thread 00a4 (the most releases), a second: release 49000, wake_skipped 41000, wake_one 8000, wake_none 0, server 7$"
  check "  no requests file: no request table" eval '! echo "$out" | grep -q "^Server requests"'
  # (its requests file, in jdrly/wine#15's format: two blocks of the game thread inside the heat
  # log's 10 s, one of another thread, and one of the game thread after them, which don't count)
  cat >"$LOGS/heat-requests-4242.log" <<'EOF'
requests thread 00a4 from 0.0 to 5.0 time 1762912345
req set_cursor 1000 20.000
req get_message 200 0.400
req set_queue_mask 50 0.100
set_cursor handle 1000 repeat 990 count 0 pos 0 clip 0 noclip 0
get_message internal 100 other 100 none 0
message 0x80001ff1 100
message 0x8001 100
message unlisted 0
set_queue_mask poll 50 nopoll 0
requests thread 0024 from 0.0 to 5.0 time 1762912345
req set_cursor 7777 9.000
set_cursor handle 7777 repeat 7777 count 0 pos 0 clip 0 noclip 0
get_message internal 0 other 0 none 0
message unlisted 0
set_queue_mask poll 0 nopoll 0
requests thread 00a4 from 5.0 to 10.0 time 1762912350
req get_message 300 0.600
req set_cursor 10 0.200
req select 5 0.050
set_cursor handle 10 repeat 10 count 0 pos 0 clip 0 noclip 0
get_message internal 0 other 300 none 97
message 0x8001 200
message unlisted 3
set_queue_mask poll 0 nopoll 0
requests thread 00a4 from 10.0 to 15.0 time 1762912355
req set_cursor 5555 50.000
set_cursor handle 5555 repeat 0 count 0 pos 0 clip 0 noclip 0
get_message internal 0 other 0 none 0
message 0x8001 4444
message unlisted 0
set_queue_mask poll 0 nopoll 0
EOF
  table() { "$APP/Contents/Resources/session-report.sh" "$@" 2>&1 | awk '/^Server requests/ { p = 1; print; next } p && /^  / { print; next } { p = 0 }'; }
  cat >"$SANDBOX/requests.want" <<'EOF'
Server requests of thread 00a4, the game thread, in heat-requests-4242.log from 0.0 to 10.0 s: blocks wholly inside 2, covering 10.0 s; each count, then a second in brackets
  set_cursor 1010 (101.0), 20.200 ms (2.020)
  get_message 500 (50.0), 1.000 ms (0.100)
  set_queue_mask 50 (5.0), 0.100 ms (0.010)
  select 5 (0.5), 0.050 ms (0.005)
  set_cursor: handle 1010 (101.0), repeat 1000 (100.0), count 0 (0.0), pos 0 (0.0), clip 0 (0.0), noclip 0 (0.0)
  get_message: internal 100 (10.0), other 400 (40.0), none 97 (9.7)
  message: 0x8001 300 (30.0), 0x80001ff1 100 (10.0), unlisted 3 (0.3)
  set_queue_mask: poll 50 (5.0), nopoll 0 (0.0)
EOF
  check "  its requests file: the game thread's blocks in the heat log's run summed, a second too" diff "$SANDBOX/requests.want" <(table)
  check "  --from 2 --to 12: only the block wholly inside, and the 5 s it covers" \
    [ "$(table --from 2 --to 12 | head -2 | tr '\n' '|')" = "Server requests of thread 00a4, the game thread, in heat-requests-4242.log from 2.0 to 12.0 s: blocks wholly inside 1, covering 5.0 s; each count, then a second in brackets|  get_message 300 (60.0), 0.600 ms (0.120)|" ]
  check "  a log of this format: no game thread table, workers line or other thread's requests" \
    eval '[ "$("$APP/Contents/Resources/session-report.sh" 2>&1 | grep -cE "^(The game thread|The workers|Server requests)")" = 1 ]'
  check "  no fex lines in the blocks, no FEX_SILENTLOG=0 in the rule: no FEX counters or memory ordering line (FEX that ran, from the record, stays)" \
    eval '! "$APP/Contents/Resources/session-report.sh" 2>&1 | grep -qE "^(FEX.s counters|FEX didn.t say|Memory ordering)"'
  # (the same blocks with FEX's counters, in the line my ntdll.so writes per jdrly/gw2-on-mac#111;
  # no real session has them yet. The game thread compiles 2.5 s in its first block and little in
  # the next two, with #117's four counts in the second; the other thread got no slot)
  fexl() { printf 'fex jit_ms %s jit %s miss %s rlock_ms 1.000 wlock_ms 0.500 smc 0 sigbus 0 float 2 signal_ms 0.100 dcache_hit 0 dcache_miss 0 dcache_ms 0.000%s\n' "$@"; }
  awk -v a="$(fexl 2500.000 30000 9000 '')" -v b="$(fexl 20.000 100 500 ' tso_switches 4 native_exits 120 code_buffer_moves 1 l1_resizes 0')" \
      -v c="$(fexl 900.000 8000 2000 '')" '
    { print }
    /^requests thread 00a4 / { n++; print (n == 1 ? a : n == 2 ? b : c) }
    /^requests thread 0024 / { print "fex has no slot of 36" }' "$LOGS/heat-requests-4242.log" >"$SANDBOX/requests.fex"
  mv -f "$SANDBOX/requests.fex" "$LOGS/heat-requests-4242.log"
  cat >"$SANDBOX/fex.want" <<'EOF'
FEX's counters of thread 00a4, the game thread, in heat-requests-4242.log from 0.0 to 10.0 s: 2 blocks, covering 10.0 s
  In all: compiling 2520.000 ms, 30100 blocks; lookup cache misses 9500, its lock 2.000 ms read, 1.000 ms write; SMC 0; signals 0.200 ms
  A second, the median and the highest 5 s: compiling 252.000 and 500.000 ms, lookup cache misses 950 and 1800
  Compile bursts, compiling over 10% of the time: at 0.0 s for 5.0 s, 30000 blocks
  Also, in all: sigbus 0, float 4, dcache_hit 0, dcache_miss 0, dcache_ms 0.000, tso_switches 4, native_exits 120, code_buffer_moves 1, l1_resizes 0
FEX's counters of thread 0024, another thread: none, FEX had no slot left for it (36 in use). Its stats have room for about 36 threads and can't grow on macOS.
EOF
  fex() { "$APP/Contents/Resources/session-report.sh" "$@" 2>&1 | awk '/^FEX.s counters/ { p = 1; print; next } p && /^  / { print; next } { p = 0 }'; }
  check "  with fex lines: the request table as before" diff "$SANDBOX/requests.want" <(table)
  check "  FEX's counters of the game thread in the heat log's run, the names the report doesn't know as they are, and the thread without a slot" \
    diff "$SANDBOX/fex.want" <(fex)
  check "  --to 15: three blocks, and a second burst" \
    has <(fex --from 0 --to 15) "^  Compile bursts, compiling over 10% of the time: at 0.0 s for 5.0 s, 30000 blocks; at 10.0 s for 5.0 s, 8000 blocks$"
  # (the game thread's second block without counters, between its two bursts, and a header my
  # ntdll.so can't read for the other thread)
  sed -i '' -e 's/^fex jit_ms 20\.000 .*/fex stats version 3 slot 96/' -e 's/^fex has no slot of 36$/fex stats version 3 slot 96/' "$LOGS/heat-requests-4242.log"
  out=$(fex --from 0 --to 15)
  check "  a block without counters ends a burst, and its line stays in sight, whole" \
    eval 'has <(echo "$out") "^  Compile bursts, compiling over 10% of the time: at 0.0 s for 5.0 s, 30000 blocks; at 10.0 s for 5.0 s, 8000 blocks$" &&
      has <(echo "$out") "^  1 of its blocks had no counters, the last with: fex stats version 3 slot 96$"'
  check "  a thread with only such a line: printed whole" \
    has <(echo "$out") "^FEX's counters of thread 0024, another thread: my ntdll.so can't read them: fex stats version 3 slot 96$"
  # (FEX_SILENTLOG=0 in the rule: FEX's lines in wine.log, "<level> <thread id> <message>", the log's
  # last line a minute after Play)
  cp -p "$LOGS/session.env" "$SANDBOX/session.env.keep"; cp "$LOGS/wine.log" "$SANDBOX/wine.log.fex"
  sed -i '' 's/^\(RULE=exe=Gw2-64\.exe;.*\)$/\1;env=FEX_SILENTLOG=0/' "$LOGS/session.env"; touch -t 202601010000 "$LOGS/session.env"
  printf '0024:err:module:import_dll x\nI 01A4 FEX: Using hardware TSO\nE 01A4 FEX: a failure\nD 01B0 something\n' >"$LOGS/wine.log"
  touch -t 202601010001 "$LOGS/wine.log"
  check "  FEX said it uses hardware TSO: the line, and FEX's lines, a second over the session, and errors" \
    has <("$APP/Contents/Resources/session-report.sh" 2>&1) "^Memory ordering: hardware TSO (FEX said so); FEX wrote 3 lines to wine.log, 0.05 a second over the 1.0 min from Play to its last line, 1 of them errors$"
  printf '0024:err:module:import_dll x\n' >"$LOGS/wine.log"
  touch -t 202601010001 "$LOGS/wine.log"
  check "  FEX said nothing: it says so" \
    has <("$APP/Contents/Resources/session-report.sh" 2>&1) "^FEX didn't say it uses hardware TSO; FEX wrote 0 lines to wine.log, 0.00 a second over the 1.0 min from Play to its last line$"
  mv -f "$SANDBOX/session.env.keep" "$LOGS/session.env"; mv -f "$SANDBOX/wine.log.fex" "$LOGS/wine.log"
  rm -f "$LOGS/heat-4242.log" "$LOGS/heat-requests-4242.log" "$SANDBOX/requests.want" "$SANDBOX/fex.want"
  # (a heat log in jdrly/gw2-on-mac#99's format: timers, sleeps by length, rows that end in their
  # start address and name; the game thread lacks evpool_hit and spin_scoped. Three workers, a
  # thread with less than half their wakes, two more threads)
  cat >"$LOGS/heat-4343.log" <<'EOF'
heat pid 4343 exe Gw2-64.exe mode count seconds 10.0 threads 7
total release 500000
thread 00a4 release 490000 wake_skipped 0 wake_one 0 wake_none 3000 woken 100 spurious 0 server 700 lock_sleep 1000 lock_5us 400 lock_20us 300 lock_100us 200 lock_1ms 90 lock_long 10 wait_sleep 200 wait_5us 100 wait_20us 50 wait_100us 30 wait_1ms 15 wait_long 5 alert 50 alert_wake 20 event_set 600 event_wake 30 event_wake_none 570 wait 900 wait_timed 100 wait_poll 600 lspin_hit 0 lspin_miss 0 espin_hit 0 espin_miss 0 sspin_hit 0 sspin_miss 0 qpc 5000 yield 10 server_ms 7.000 lock_ms 252.000 wait_ms 60.000 wake_ms 3.000 alert_ms 0.600 start 0x140001000 name -
thread 00b0 release 3000 woken 1000 spurious 400 lock_sleep 2000 sspin_hit 10 sspin_miss 90 lock_ms 30.000 start 0x140002000 name Worker
thread 00b4 release 2000 woken 900 spurious 300 lock_sleep 1000 sspin_hit 20 sspin_miss 80 lock_ms 20.000 start 0x140002000 name Worker
thread 00b8 release 1000 woken 600 spurious 200 lock_sleep 1000 sspin_hit 30 sspin_miss 70 lock_ms 10.000 start 0x140002000 name Worker
thread 00c0 release 0 woken 400 spurious 0 lock_sleep 5 sspin_hit 0 sspin_miss 0 lock_ms 0.100 start 0x140003000 name Timer
thread 00c8 release 0 woken 10 spurious 0 lock_sleep 0 sspin_hit 0 sspin_miss 0 lock_ms 0.000 start 0x140004000 name AsyncIo
thread 00cc release 0 woken 5 spurious 0 lock_sleep 0 sspin_hit 0 sspin_miss 0 lock_ms 0.000 start 0x140005000 name Audio_Mixer
EOF
  # (its requests: the game thread's two blocks with their counters lines, AsyncIo in both,
  # Audio_Mixer in the first, and in the second a thread with the least server time, which the
  # heat log lacks. Audio_Mixer has the most server_ms, though its one req line has less time
  # than AsyncIo's: the dumper prints only the twelve busiest requests)
  blk() {
    printf 'requests thread %s from %s to %s time 1762912345\ncounters %s\n' "$1" "$2" "$3" "$4"; shift 4
    printf '%s\n' "$@" 'set_cursor handle 0 repeat 0 count 0 pos 0 clip 0 noclip 0' 'get_message internal 0 other 0 none 0' \
      'message unlisted 0' 'set_queue_mask poll 0 nopoll 0'
  }
  {
    blk 00a4 0.0 5.0 'release 290000 server 400 lock_sleep 600 lock_5us 240 lock_20us 180 lock_100us 120 lock_1ms 54 lock_long 6 lock_ms 162.000 wait_sleep 100 wait_ms 30.000 wake_ms 1.000 qpc 2500' \
      'req select 300 3.000' 'req create_event 100 1.000'
    blk 00c8 0.0 5.0 'server 400 server_ms 6.000' 'req remove_completion 400 8.000'
    blk 00cc 0.0 5.0 'server 400 server_ms 20.000' 'req ioctl 100 2.000'
    blk 00a4 5.0 10.0 'release 200000 server 300 lock_sleep 400 lock_5us 160 lock_20us 120 lock_100us 80 lock_1ms 36 lock_long 4 lock_ms 90.000 wait_sleep 100 wait_ms 30.000 wake_ms 2.000 qpc 2500' \
      'req select 250 2.500' 'req create_event 50 0.500'
    blk 00c8 5.0 10.0 'server 200 server_ms 3.000' 'req remove_completion 200 4.000'
    blk 0e0e 5.0 10.0 'server 50 server_ms 0.500' 'req send_socket 50 0.500'
  } >"$LOGS/heat-requests-4343.log"
  # (DXMT's log has no GPU lines yet: the frames are the game thread's select requests)
  out=$("$APP/Contents/Resources/session-report.sh" 2>&1)
  check "  a heat log of #99's format, no DXMT frames: the table from the totals, frames by the socket poll" \
    has <(echo "$out") "^The game thread, thread 00a4 (no name, start 0x140001000), from the heat log totals, which include loading: 10.0 s, 550 frames by the game's socket poll$"
  cp "$LOGS/Gw2-64_d3d11.log" "$SANDBOX/d3d11.keep"
  printf 'info:  GPU gpuspan=7.06/16.7 gpugap=0.51/1.1 frames=%s incomplete=0 buffers=3.1 missing=0\n' 250 350 >>"$LOGS/Gw2-64_d3d11.log"
  out=$("$APP/Contents/Resources/session-report.sh" 2>&1)
  check "  with DXMT's GPU lines: their frames" \
    has <(echo "$out") "^The game thread, thread 00a4 (no name, start 0x140001000), from the heat log totals, which include loading: 10.0 s, 600 frames counted by DXMT$"
  check "  the game thread's lock sleeps and lock_ms, a second and a frame: 252 ms in 600 frames" \
    has <(echo "$out") '^  lock_sleep, lock_ms  *100.0  *1.67  *0.420$'
  check "  a timer alone: wake_ms a frame" has <(echo "$out") '^  wake_ms  *0.005$'
  check "  the counters the row lacks are left out" eval '! echo "$out" | grep -qE "^  (evpool_hit|spin_scoped) "'
  check "  the lock sleeps by length, as shares of them" \
    has <(echo "$out") '^  lock sleeps by length: under 5 us 40.0%, 5 to 20 us 30.0%, 20 to 100 us 20.0%, 0.1 to 1 ms 9.0%, 1 ms or more 1.0%$'
  check "  the workers in one line: the three rows with at least half the most wakes" \
    has <(echo "$out") "^The workers, 3 threads whose woken is at least half the busiest other thread's, from the heat log totals, a second (a frame): lock_sleep 400 (6.67), lock_ms 6.0 (0.100), woken 250 (4.17), spurious 90 (1.50), sspin_hit 6 (0.10), sspin_miss 24 (0.40)$"
  check "  the requests of the game thread and of the two others with the most server time, by name" \
    [ "$(echo "$out" | grep '^Server requests' | sed 's/, covering .*//' | tr '\n' '|')" = "Server requests of thread 00a4, the game thread, in heat-requests-4343.log from 0.0 to 10.0 s: blocks wholly inside 2|Server requests of thread 00cc, named Audio_Mixer, start 0x140005000, in heat-requests-4343.log from 0.0 to 10.0 s: blocks wholly inside 1|Server requests of thread 00c8, named AsyncIo, start 0x140004000, in heat-requests-4343.log from 0.0 to 10.0 s: blocks wholly inside 2|" ]
  out=$("$APP/Contents/Resources/session-report.sh" --from 5 --to 10 2>&1)
  check "  --from 5 --to 10: the table from that block's counters line, the frames its select requests" \
    eval 'has <(echo "$out") "^The game thread, thread 00a4 (no name, start 0x140001000), from the counters lines of its blocks wholly inside 5.0 to 10.0 s: 5.0 s, 250 frames by the game.s socket poll$" && has <(echo "$out") "^  lock_sleep, lock_ms  *80.0  *1.60  *0.360$"'
  check "  and the two other threads of that interval" \
    [ "$(echo "$out" | grep '^Server requests of thread' | cut -d, -f1 | tr '\n' '|')" = "Server requests of thread 00a4|Server requests of thread 00c8|Server requests of thread 0e0e|" ]
  rm -f "$LOGS/heat-requests-4343.log"
  check "  --from 5 --to 10 without the requests log: no table, and it says why" \
    eval '[ "$("$APP/Contents/Resources/session-report.sh" --from 5 --to 10 2>&1 | grep -E "^(The game thread|  lock_sleep)")" = "The game thread, thread 00a4 (no name, start 0x140001000): no server requests log, so no table for --from and --to" ]'
  mv -f "$SANDBOX/d3d11.keep" "$LOGS/Gw2-64_d3d11.log"
  rm -f "$LOGS/heat-4343.log" "$LOGS/heat-requests-4343.log"
else
  check "  and which ntdll.so ran: the engine's own, no switches" \
    eval 'has "$Z/session-report.txt" "^ntdll.so that ran: the engine.s own, athei/wine $ENGINE_WINE$" && has "$Z/session-report.txt" "^Its switches: none$"'
fi
# (the line after which winemac.so ran is its switches: launcher frames is off by default)
if drv; then
  check "  and which winemac.so ran, with its switches: none" \
    eval '[ "$(grep -A1 "^winemac.so that ran: " "$Z/session-report.txt" | tr "\n" "|")" = "winemac.so that ran: my Mac driver, jdrly/wine ${MYDRV_COMMIT:0:11} (sha256 $(shasum -a 256 "$COMP/macdrv/winemac.so" | cut -c1-12))|Its switches: none|" ]'
  # (my Mac driver's lines in wine.log, as on 0.1.x: two windows of Gw2-64.exe, the launcher's the
  # one with the most flushes)
  cp "$LOGS/wine.log" "$SANDBOX/wine.log.keep"
  printf '0124:trace:macsurface:macdrv_surface_flush hwnd 0x10062 1152x1024: 600 flushes, 400 unchanged\n0130:trace:macsurface:macdrv_surface_flush hwnd 0x20044 2560x1440: 600 flushes, 0 unchanged\n0124:trace:macsurface:macdrv_surface_flush hwnd 0x10062 1152x1024: 1200 flushes, 810 unchanged\n' >>"$LOGS/wine.log"
  out=$("$APP/Contents/Resources/session-report.sh" 2>&1)
  check "  the launcher's last macsurface line, from wine.log" \
    has <(echo "$out") "^Its last macsurface line, the window with the most flushes (the launcher): hwnd 0x10062 1152x1024: 1200 flushes, 810 unchanged$"
  mv -f "$SANDBOX/wine.log.keep" "$LOGS/wine.log"
else
  check "  and which winemac.so ran: the engine's own, no switches" \
    eval '[ "$(grep -A1 "^winemac.so that ran: " "$Z/session-report.txt" | tr "\n" "|")" = "winemac.so that ran: the engine'"'"'s own, athei/wine $ENGINE_WINE|Its switches: none|" ]'
fi
# (compatdb.local's FEX_HOSTFEATURES is in the game's rule: a FEX switch the session ran)
check "  and which FEX ran: the engine's own, with compatdb.local's switch" \
  eval '[ "$(grep -A1 "^FEX that ran: " "$Z/session-report.txt" | tr "\n" "|")" = "FEX that ran: the engine'"'"'s own, athei/FEX $ENGINE_FEX|Its switches: FEX_HOSTFEATURES=disableavx|" ]'
check "  system-info names my FEX build in the app (or none) and FEX's files in the engine" \
  eval 'has "$Z/system-info.txt" "^Versions: .* fex $(fexb && echo "$MYFEX_COMMIT" || echo none) " && has "$Z/system-info.txt" "^  FEX xtajit64.dll: ${GW2_ON_MAC_ENGINE_FEX_DLL_SHA256:0:12} (the engine.s own " && [ -f "$Z/VERSIONS" ] && grep -q "^fex " "$Z/VERSIONS"'
# (DXMT's wait field is count, the window's total and its longest: two windows with waits and one
# without, which adds nothing)
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60
info:  COMPILE variants=10 air=0/0 pso=1/15 built=2 failed=0 build=shader:0/0.0 pipeline:2/30.0 queue=0/0 threads=2 wait=13x 109.6/21.1 slow=0
info:  COMPILE variants=5 air=0/0 pso=1/15 built=1 failed=0 build=shader:0/0.0 pipeline:1/9.0 queue=0/0 threads=2 wait=0x 0.0/0.0 slow=0
info:  COMPILE variants=3 air=0/0 pso=1/15 built=1 failed=0 build=shader:0/0.0 pipeline:1/12.0 queue=0/0 threads=2 wait=3x 31.4/18.9 slow=0
' >"$SANDBOX/compile_d3d11.log"
out=$("$APP/Contents/Resources/session-report.sh" "$SANDBOX/compile_d3d11.log" 2>&1)
check "the session report adds up DXMT's compile waits as its log gives them, and the longest" \
  has <(echo "$out") "^Compiles: 18 shader variants, 4 pipelines built, 0 failed; DXMT's encode thread waited 16 times, about 141 ms in all, the longest 21.1 ms$"
out=$("$APP/Contents/Resources/session-report.sh" --compare "$SANDBOX/compile_d3d11.log" "$SANDBOX/compile_d3d11.log" 2>&1 |
  awk '/^compile_wait/ { print $1, $2, $3 }' | tr '\n' '|')
check "  and --compare prints the same three numbers for both sessions" \
  [ "$out" = "compile_waits 16 16|compile_wait_ms 141 141|compile_wait_max 21.1 21.1|" ]
rm -f "$SANDBOX/compile_d3d11.log"
cp "$LOGS/session.env" "$SANDBOX/session.env.keep"
sed -i '' -e 's/^DXMT_TREE=.*/DXMT_TREE=engine/' -e 's/^RULE=exe=Gw2-64.exe;/&gcmouse=false;/' "$LOGS/session.env"
echo "info:  Using feature level D3D_FEATURE_LEVEL_11_1" >"$LOGS/engine-only_d3d11.log"
out=$("$APP/Contents/Resources/session-report.sh" "$LOGS/engine-only_d3d11.log" 2>&1)
check "the session report of the engine's DXMT: says which, and that it writes no STATS lines" \
  eval 'echo "$out" | grep -q "^DXMT that ran: the engine.s own DXMT, athei/dxmt d903db89036$" && echo "$out" | grep -q "writes no STATS lines"'
check "  a session with raw mouse-look off: the pointer's movement" has <(echo "$out") "^Mouse the game had: the pointer's movement, as Wine does it (gcmouse=false)$"
mv -f "$SANDBOX/session.env.keep" "$LOGS/session.env"; rm -f "$LOGS/engine-only_d3d11.log"
check "  the Steam account name is gone" sh -c "! grep -rq zz_acct_name '$Z'"
check "  the persona name is gone" sh -c "! grep -rqi 'Zz Persona Q' '$Z'"
check "  the Steam ID is gone" sh -c "! grep -rqE '7656119[0-9]{10}|U:1:39734314' '$Z'"
check "  the e-mail address is gone" sh -c "! grep -rq zz.person@example.com '$Z'"
check "  the crash log's machine and address are gone" sh -c "! grep -rqE 'ZZ-MACHINE|192\.168\.77\.5' '$Z'"
check "  the token value is gone" sh -c "! grep -rq abcDEF123secret '$Z'"
check "  the home folder is gone" sh -c "! grep -rqF '$HOME/' '$Z'"
check "  never Local.dat or Steam's config" sh -c "! find '$Z' -name Local.dat -o -name loginusers.vdf | grep -q ."
check "  the crash log kept its exception" has "$Z/game-logs/ArenaNet.log" "Exception: c0000005"
check "  no arcdps log (its crash log may hold character names)" sh -c "! find '$Z' -iname 'arcdps*' | grep -q . && ! grep -rq 'Zz Charname Q' '$Z'"
check "  system-info names the d3d11.dll addon: arcdps" has "$Z/system-info.txt" "d3d11.dll addon: arcdps"
rm -rf "$GD/addons" "$GD/d3d11.dll" "$AD/compatdb.local"

section "Steam in the background after the first login"
LU="$STEAM/config/loginusers.vdf"
# the command play started (the stand-in's log of it)
play_cmd() { : >"$STANDIN_LOG"; g play >/dev/null 2>&1; started; grep -m1 '^wine ' "$STANDIN_LOG"; }
rm -f "$LU"
check "no login yet (no loginusers.vdf): Steam with its window" sh -c "'$G' settings | grep -qx steam_login=no"
c=$(play_cmd); check "  steam.exe -applaunch 1284210, no -silent" eval '[[ "$c" == *"steam.exe -applaunch 1284210 -maploadinfo" ]]'
printf '"users"\n{\n\t"76561198000000042"\n\t{\n\t\t"AccountName"\t\t"zz_acct_name"\n\t\t"RememberPassword"\t\t"0"\n\t\t"MostRecent"\t\t"1"\n\t}\n}\n' >"$LU"
c=$(play_cmd); check "a user who isn't remembered: still no -silent" eval '[[ "$c" != *-silent* ]]'
sed -i '' 's/"RememberPassword"\([[:space:]]*\)"0"/"RememberPassword"\1"1"/' "$LU"
check "a remembered login: steam_login=yes" sh -c "'$G' settings | grep -qx steam_login=yes"
c=$(play_cmd); check "  Play: steam.exe -silent -applaunch 1284210 with the launch options" eval '[[ "$c" == *"steam.exe -silent -applaunch 1284210 -maploadinfo" ]]'
check "set steambg off" g set steambg off
c=$(play_cmd); check "  Steam's window again (no -silent)" eval '[[ "$c" == *"steam.exe -applaunch 1284210 -maploadinfo" ]]'
g set steambg on >/dev/null

section "Busy checks (a sleeper at the engine's paths)"
watch_done   # the watchers of the Plays above have given up (no Steam came)
# (macOS kills copies of /bin/sleep: an ad-hoc signed program of my own keeps its signature)
printf '#include <unistd.h>\n#include <stdlib.h>\nint main(int c, char **v) { sleep(c > 1 ? atoi(v[1]) : 60); return 0; }\n' >"$SANDBOX/sleeper.c"
clang -O2 -o "$SANDBOX/sleeper" "$SANDBOX/sleeper.c"
cp "$SANDBOX/sleeper" "$ENG/bin/leftover"
"$ENG/bin/leftover" 60 & lp=$!
sleep 0.3
check "busy=leftovers with an engine process and no wineserver" [ "$(st busy)" = leftovers ]
check "end-leftovers ends it" sh -c "'$G' end-leftovers | grep -q '@done'"
sleep 0.3
check "  gone" sh -c "! kill -0 $lp 2>/dev/null"
mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
"$ENG/bin/wineserver" 60 & sp=$!
sleep 0.3
check "busy=session with the engine's wineserver" [ "$(st busy)" = session ]
check "uninstall refused while it runs" sh -c "! '$G' uninstall >/dev/null 2>&1"
check "repair refused while it runs" sh -c "! '$G' repair >/dev/null 2>&1"
# (a bottle from an earlier 0.2 build: EmulateModeset=Y, and a value of mine for Gw2-64.exe only)
sed -i '' 's/^"EmulateModeset"="N"$/"EmulateModeset"="Y"/' "$BOTTLE/user.reg"
printf '\n[Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\X11 Driver] 1700000000\n"EmulateModeset"="Y"\n' >>"$BOTTLE/user.reg"
check "set retina off while it runs: saved" sh -c "'$G' set retina off | grep -q 'after Steam has quit' && [ \"\$('$G' settings | sed -n 's/^retina=//p')\" = off ]"
check "  but the registry waits (Wine reads it at the session's start)" reg "$ALL_MAC" RetinaMode y
check "  and EmulateModeset=Y from an earlier 0.2 build stays until then, as Gw2-64.exe's own does" \
  eval 'reg "$ALL_X11" EmulateModeset Y && reg "$GW2_X11" EmulateModeset Y'
check "set dxmt engine while it runs: saved, and the tree waits (the session's processes have it loaded)" \
  eval '"$G" set dxmt engine | grep -q "after Steam has quit" && [ "$(sett dxmt)" = engine ] && dxgi_is fork && [ "$(st graphics)" = switch ]'
check "set rawmouse off while it runs: saved, for the next game start with Steam still open (the rules are written at each)" \
  eval '[ "$("$G" set rawmouse off)" = "@done rawmouse=off. It takes effect the next time the game starts." ] && [ "$(sett rawmouse)" = off ] && g set rawmouse on >/dev/null'
check "set arcdps on while it runs: refused, nothing placed" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "Quit Guild Wars 2 and Steam first" && [ ! -e "$STEAM/steamapps/common/Guild Wars 2/d3d11.dll" ]'
kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
check "  once it has ended, the switch goes through" eval 'g set dxmt engine >/dev/null && dxgi_is engine && g set dxmt fork >/dev/null && dxgi_is fork'
: >"$STANDIN_LOG"; g play >/dev/null 2>&1; started
check "  the next Play writes EmulateModeset=N" reg "$ALL_X11" EmulateModeset N
check "    and leaves Gw2-64.exe's own Y alone (two values in all)" \
  eval 'reg "$GW2_X11" EmulateModeset Y && [ "$(grep -c "^\"EmulateModeset\"=" "$BOTTLE/user.reg")" = 2 ]'
watch_done
if mine; then
  mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
  "$ENG/bin/wineserver" 60 & sp=$!
  sleep 0.3
  check "set wine engine while a session runs: saved, and my ntdll.so stays (every process of the session has it loaded)" \
    eval '"$G" set wine engine | grep -q "after Steam has quit" && [ "$(sett wine)" = engine ] && ntdll_is mine && [ "$(st wine_ready)" = switch ]'
  kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
  mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
  : >"$STANDIN_LOG"; out=$(g play 2>&1); started
  check "  once it has ended, the next Play puts the engine's own in before Wine starts" \
    eval 'ntdll_is engine && has "$LOGS/session.env" "^LIB_wine=ntdll.so engine $ENGINE_WINE "'
  watch_done
  g set wine mine >/dev/null
else
  skip "set wine engine while a session runs"
fi
if drv; then
  mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
  "$ENG/bin/wineserver" 60 & sp=$!
  sleep 0.3
  check "set macdrv engine while a session runs: saved, and my winemac.so stays" \
    eval '"$G" set macdrv engine | grep -q "after Steam has quit" && [ "$(sett macdrv)" = engine ] && winemac_is mine && [ "$(st macdrv_ready)" = switch ]'
  kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
  mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
  : >"$STANDIN_LOG"; out=$(g play 2>&1); started
  check "  once it has ended, the next Play puts the engine's own in before Wine starts" \
    eval 'winemac_is engine && has "$LOGS/session.env" "^LIB_macdrv=winemac.so engine $ENGINE_WINE "'
  watch_done
  g set macdrv mine >/dev/null
else
  skipdrv "set macdrv engine while a session runs"
fi
if fexb; then
  mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
  "$ENG/bin/wineserver" 60 & sp=$!
  sleep 0.3
  check "set fex mine while a session runs: saved, and the engine's own FEX stays (the session's processes have it loaded)" \
    eval '"$G" set fex mine | grep -q "after Steam has quit" && [ "$(sett fex)" = mine ] && fex_is engine && [ "$(st fex_ready)" = switch ]'
  kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
  mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
  : >"$STANDIN_LOG"; out=$(g play 2>&1); started
  check "  once it has ended, the next Play puts my FEX in before Wine starts, and says so" \
    eval 'fex_is mine && echo "$out" | grep -q "^FEX: my FEX (jdrly/FEX ${MYFEX_COMMIT:0:11}) is in the engine, the engine.s own kept next to each" && has "$STANDIN_LOG" "^wine "'
  check "  the session's record: LIB_fex=mine, its commit and the sha256 of xtajit64.dll in the engine" \
    eval '[ "$(sed -n "s/^LIB_fex=//p" "$LOGS/session.env")" = "mine $MYFEX_COMMIT $(shasum -a 256 "$COMP/fex/aarch64-windows/libarm64ecfex.dll" | cut -d" " -f1)" ]'
  printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\n' >"$LOGS/Gw2-64_d3d11.log"
  out=$("$APP/Contents/Resources/session-report.sh" 2>&1)
  check "  the session report's FEX that ran names my commit, as the record does" \
    has <(echo "$out") "^FEX that ran: my FEX, jdrly/FEX ${MYFEX_COMMIT:0:11} (xtajit64.dll sha256 $(shasum -a 256 "$COMP/fex/aarch64-windows/libarm64ecfex.dll" | cut -c1-12))$"
  rm -f "$LOGS/Gw2-64_d3d11.log"
  watch_done
  # a mix that can't be finished (the engine's own xtajit64.dll gone, mine in its place, the other
  # two the engine's): Play refuses before anything starts
  g set fex engine >/dev/null
  cp "$(fex_src_of aarch64-windows/xtajit64.dll)" "$FW/aarch64-windows/xtajit64.dll"
  : >"$STANDIN_LOG"; out=$(g play 2>&1) && rc=0 || rc=$?
  check "a mix of my FEX and the engine's own with one of its files gone: fex_ready=other, Play refuses and starts nothing" \
    eval '[ "$(st fex_ready)/$(st fex_file)" = other/mix ] && [ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The engine'"'"'s FEX files are a mix of mine and its own. Click Repair." && ! has "$STANDIN_LOG" "^wine "'
  out=$(g repair 2>&1) && rc=0 || rc=$?
  check "  repair unpacks the engine again and puts the engine's own FEX in, as fex=engine asks" \
    eval '[ "$rc" = 0 ] && echo "$out" | grep -q "unpacking the engine again" && fex_is engine && [ "$(st fex_ready)" = yes ] && [ "$(engine_diff)" = "$SDK_DIFF" ]'
  watch_done
else
  skipfex "set fex mine while a session runs, and a mix Play refuses"
fi
cp "$SANDBOX/sleeper" "$ENG/bin/Gw2-64.exe"
"$ENG/bin/Gw2-64.exe" 60 & gp=$!
sleep 0.3
check "busy=game with a Gw2-64.exe of the engine running, game_pid its pid" eval '[ "$(st busy)/$(st game_pid)" = "game/$gp" ]'
check "play brings it up instead of starting another" sh -c "'$G' play | grep -q 'already running'"
check "reset-shaders refused while the game runs" sh -c "! '$G' reset-shaders >/dev/null 2>&1"
rm -f "$SANDBOX/vmmap.args"
out=$(g vmmap 2>&1)
vf=${out#@done }
check "vmmap while the game runs: one vmmap of the game's pid, into the logs folder" \
  eval '[ "$(cat "$SANDBOX/vmmap.args" 2>/dev/null)" = "$gp" ] && [ "$(dirname "$vf")" = "$LOGS" ] && [ -f "$vf" ] && case "${vf##*/}" in vmmap-*.txt) ;; *) false ;; esac'
check "  its first line: the pid, the seconds since the game started, how long vmmap took" \
  eval 'head -1 "$vf" | grep -qE "^Gw2-64\.exe pid $gp, running [0-9]+ s, vmmap took [0-9.]+ s \(the game stood still for at most that long\)$"'
check "  then the header through the peak, the three rwx/rwx regions, and the summary to its end" \
  eval '[ "$(sed -n 2p "$vf")" = "Process:         Gw2-64.exe [70549]" ] && grep -q "^Physical footprint (peak):  9.0G$" "$vf" &&
    [ "$(grep -c " rwx/rwx " "$vf")" = 3 ] && [ "$(tail -1 "$vf" | cut -c1-30)" = "TOTAL, minus reserved VM space" ]'
check "  and no other region, nor the legend" eval '! grep -qE "(r--|rw-|---)/r|^Idle exit|^==== (regions|Legend)" "$vf"'
cp -p "$LOGS/session.env" "$SANDBOX/session.env.keep"
touch -t 202601010000 "$LOGS/session.env"
[ -f "$LOGS/Gw2-64_d3d11.log" ] || printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\n' >"$LOGS/Gw2-64_d3d11.log"
check "  the session report: the footprint, three buffers by size, two discards" \
  has <("$APP/Contents/Resources/session-report.sh" 2>&1) "^vmmap at [0-9.]* min (${vf##*/}): footprint 8.4G, peak 9.0G; code buffers 16M full, 32M full, 64M 25.4M resident; FEX has thrown its code away 2 times$"
rm -f "$vf" "$SANDBOX/vmmap.args"
zip=$("$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip" 2>>"$SANDBOX/collect.err" | tail -1)
rm -rf "$SANDBOX/unzipped" && mkdir -p "$SANDBOX/unzipped" && (cd "$SANDBOX/unzipped" && unzip -q "$zip")
Z="$SANDBOX/unzipped/$(basename "$zip" .zip)"
check "Collect Logs while the game runs: a vmmap of the game, in the logs folder and in the zip, and its line in the report" \
  eval '[ "$(cat "$SANDBOX/vmmap.args" 2>/dev/null)" = "$gp" ] && vf=$(ls "$LOGS"/vmmap-*.txt) && [ -f "$Z/logs/${vf##*/}" ] &&
    has "$Z/session-report.txt" "^vmmap at .*; FEX has thrown its code away 2 times$"'
rm -f "$LOGS"/vmmap-*.txt "$SANDBOX/vmmap.args"
: >"$SANDBOX/vmmap.hang"
t0=$(date +%s)
out=$(GW2_ON_MAC_VMMAP_TIMEOUT=1 g vmmap 2>&1) && rc=0 || rc=$?
t1=$(date +%s)
vf=$(ls "$LOGS"/vmmap-*.txt 2>/dev/null | head -1)
check "a vmmap that hangs: ended after the deadline, the command fails and the file says why" \
  eval '[ "$rc" != 0 ] && [ $((t1 - t0)) -lt 10 ] && echo "$out" | grep -q "^@error vmmap hadn.t finished after 1 s" &&
    [ "$(sed -n 2p "$vf")" = "vmmap failed: it hadn'"'"'t finished after 1 s, so it was ended" ]'
check "  the hanging stand-in is gone" sh -c "! ps -axww -o args= | grep -q '^sleep 60$'"
rm -f "$LOGS"/vmmap-*.txt "$SANDBOX/vmmap.args" "$SANDBOX/vmmap.hang"
mv -f "$SANDBOX/session.env.keep" "$LOGS/session.env"
kill $gp 2>/dev/null || true; wait $gp 2>/dev/null || true
rm -f "$ENG/bin/Gw2-64.exe"
check "busy=none again" [ "$(st busy)" = none ]
# another app's Guild Wars 2 (0.1.x's, a Mach9.app's): a Gw2-64.exe outside this engine
mkdir -p "$SANDBOX/other" && cp "$SANDBOX/sleeper" "$SANDBOX/other/Gw2-64.exe"
"$SANDBOX/other/Gw2-64.exe" 60 & op=$!
sleep 0.3
: >"$STANDIN_LOG"
out=$(g play 2>&1) && rc=0 || rc=$?
check "a Gw2-64.exe of another app running: play refuses, starts nothing" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error Guild Wars 2 is running in another app. Quit it first." && [ ! -s "$STANDIN_LOG" ] && [ "$(st busy)/$(st game_pid)" = none/ ]'
check "  vmmap leaves it alone: it isn't this app's game" \
  eval '[ "$(g vmmap)" = "@done Guild Wars 2 isn'"'"'t running, so there is no vmmap to take." ] && [ ! -e "$SANDBOX/vmmap.args" ] && ! ls "$LOGS" | grep -q "^vmmap-"'
kill $op 2>/dev/null || true; wait $op 2>/dev/null || true

section "Steam quits after the game (watch-session)"
# stand-in Steam and game: sleepers at the engine's paths (proc_list: steam, game), started apart
# from this shell (launchd reaps them), the Steam's pid in steam.pid for the stand-in wine
SP="$SANDBOX/steam.pid"
cp "$SANDBOX/sleeper" "$ENG/bin/steam.exe" && cp "$SANDBOX/sleeper" "$ENG/bin/Gw2-64.exe"
steam_up() { ( "$ENG/bin/steam.exe" 120 & echo $! >"$SP" ); sleep 0.2; }
steam_runs() { kill -0 "$(cat "$SP")" 2>/dev/null; }
steam_down() { kill "$(cat "$SP")" 2>/dev/null; rm -f "$SP"; sleep 0.2; }
game_up() { ( "$ENG/bin/Gw2-64.exe" 120 & echo $! >"$SANDBOX/game.pid" ); }
game_down() { kill "$(cat "$SANDBOX/game.pid")" 2>/dev/null; }
# a session: the game starts, runs, quits
game_session() { game_up; wait_stage playing && game_down && wait_stage grace; }
# Play, then (up to 2 s) its watcher has written its pid
watcher_up() { local i=0; until watcher_runs || [ $i -ge 20 ]; do sleep 0.1; i=$((i + 1)); done; }
splay() { : >"$STANDIN_LOG"; g play >/dev/null 2>&1; started; watcher_up; }
watch_done
check "the Steam in the background is on, with a remembered login" [ "$(sett steambg)/$(sett steam_login)/$(sett quitsteam)" = on/yes/on ]

splay; steam_up
check "Play starts Steam in the background: session started_steam=yes steam_window=hidden quit_steam=yes" [ "$(sess route)/$(sess started_steam)/$(sess steam_window)/$(sess quit_steam)" = steam/yes/hidden/yes ]
check "  stage=waiting_game, the watcher's pid" eval '[ "$(sess stage)" = waiting_game ] && kill -0 "$(sess watcher_pid)"'
check "  stage=playing once Gw2-64.exe runs, grace once it quits" game_session
check "  the watcher ends with result=quit" eval 'watch_done && [ "$(sess result)" = quit ]'
check "  steam.exe -shutdown through the engine's Wine, in the bottle" eval 'has "$STANDIN_LOG" "^wine C:.*steam.exe -shutdown" && has "$STANDIN_LOG" "WINEPREFIX=$BOTTLE"'
check "  Steam is gone, with no wineserver -k" eval '! steam_runs && ! has "$STANDIN_LOG" "wineserver -k"'
check "  the timestamps" eval '[ -n "$(sess started)" ] && [ -n "$(sess game_started)" ] && [ -n "$(sess game_ended)" ] && [ -n "$(sess updated)" ]'
check "  install.log: the session under ---- session" eval 'has "$LOGS/install.log" " ---- session " && has "$LOGS/install.log" "session: Steam quit"'

splay; steam_up
game_session
game_up
check "a new Gw2-64.exe within the grace: playing again" wait_stage playing
check "  Steam still runs, no -shutdown yet" eval 'steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
game_down
check "  then it quits for good: Steam quits" eval 'watch_done && [ "$(sess result)" = quit ] && ! steam_runs'

steam_up; splay
check "Steam already running before Play: started_steam=no quit_steam=no" [ "$(sess started_steam)/$(sess quit_steam)" = no/no ]
game_session
check "  after the game: Steam left running, no -shutdown" eval 'watch_done && [ "$(sess result)" = left_running ] && steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
check "  and the log says why" has "$LOGS/install.log" "Steam stays open: Steam already ran before Play"
steam_down

g set quitsteam off >/dev/null
splay; steam_up
check "Quit Steam when the game quits off: quit_steam=no" [ "$(sess started_steam)/$(sess quit_steam)" = yes/no ]
game_session
check "  Steam left running" eval 'watch_done && [ "$(sess result)" = left_running ] && steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
steam_down
g set quitsteam on >/dev/null

g set steambg off >/dev/null
splay; steam_up
check "Steam's window shown (background off): steam_window=shown quit_steam=no" [ "$(sess steam_window)/$(sess quit_steam)" = shown/no ]
game_session
check "  Steam left running" eval 'watch_done && [ "$(sess result)" = left_running ] && steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
steam_down
g set steambg on >/dev/null

: >"$STANDIN_LOG"; GW2_ON_MAC_WATCH_TIMEOUT=2 "$G" play >/dev/null 2>&1; started; steam_up
check "Guild Wars 2 never appears (timeout): Steam left running" eval 'watch_done && [ "$(sess result)" = timeout ] && steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
check "  and the log says so" has "$LOGS/install.log" "Guild Wars 2 did not start within"
steam_down
splay
check "Steam never comes (closed before the game): result=steam_gone" eval 'watch_done && [ "$(sess result)" = steam_gone ]'

splay; steam_up
wp=$(sess watcher_pid)
splay
check "a second Play joins the session and keeps its watcher" [ "$(sess watcher_pid)/$(sess started_steam)/$(sess quit_steam)/$(sess replay)" = "$wp/yes/yes/1" ]
# (the watcher's own subshells carry its command line: only those whose parent isn't one count)
watchers() {
  ps -axo pid=,ppid=,command= | awk -v c="/bin/bash $GW2OM watch-session" '
    { x = $0; sub(/^ *[0-9]+ +[0-9]+ /, "", x) }
    index(x, c) == 1 { w[$1] = $2 }
    END { for (p in w) if (!(w[p] in w)) n++; print n + 0 }'
}
check "  one watcher runs" [ "$(watchers)" = 1 ]
check "  watch-session by hand: another watcher follows the session" sh -c "'$G' watch-session | grep -q '@done Another watcher follows this session'"
game_session
check "  Steam quits once" eval 'watch_done && [ "$(sess result)" = quit ] && [ "$(grep -c "steam.exe -shutdown" "$STANDIN_LOG")" = 1 ]'
check "watch-session by hand with no session: nothing to follow" sh -c "'$G' watch-session | grep -q '@done No session to follow'"

# Raw mouse-look switched between two game starts with Steam still open: the Play that joins the
# session records its own rules in session.env (the session report names the mouse from them), and
# keeps the rest of the session's record
rules_recorded() { [ "$(sed -n 's/^RULE=//p' "$LOGS/session.env")" = "$(cat "$AD/compatdb.rules")" ]; }
splay; steam_up
t0=$(sed -n 's/^STARTED=//p' "$LOGS/session.env")
g set rawmouse off >/dev/null; splay
check "rawmouse off, then a Play that joins the session: its rule with gcmouse=false in session.env" \
  eval '[ "$(sess replay)" = 1 ] && rules_recorded && has "$LOGS/session.env" "^RULE=exe=Gw2-64.exe;gcmouse=false;"'
check "  the rest as the session started (STARTED, SETTING_rawmouse=on)" \
  eval '[ "$(sed -n "s/^STARTED=//p" "$LOGS/session.env")" = "$t0" ] && has "$LOGS/session.env" "^SETTING_rawmouse=on$"'
g set rawmouse on >/dev/null; splay
check "  rawmouse on again, another Play: the rule without it" eval 'rules_recorded && ! grep -q gcmouse "$LOGS/session.env"'
g set rawmouse off >/dev/null; : >"$STANDIN_LOG"
check "  rawmouse off, then Show Steam (no game start): the record keeps the running game's rule" \
  eval 'g show-steam >/dev/null && started && has "$STANDIN_LOG" "steam.exe steam://open/main" && ! grep -q gcmouse "$LOGS/session.env"'
g set rawmouse on >/dev/null
game_session
check "  Steam left open after the game (its window was shown)" eval 'watch_done && [ "$(sess result)" = left_running ] && steam_runs'
steam_down

# Steam restarts itself while it starts (an update): a new steam.exe without a request stays the
# session's (the bottle's Steam starts only through Play)
splay; steam_up
steam_down; steam_up
game_session
check "Steam restarting itself before the game (a new pid, no request) stays the session's: it quits" eval 'watch_done && [ "$(sess result)" = quit ] && ! steam_runs'

# Show Steam (lane B) asks the watcher: Steam's window shown, so Steam stays open
splay; steam_up
echo shown >>"$AD/session.req"
check "a shown request: applied by the watcher (requests=1, steam_window=shown, quit_steam=no)" eval 'i=0; while [ "$(sess requests)" != 1 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; [ "$(sess steam_window)/$(sess quit_steam)" = shown/no ]'
game_session
check "  Steam left open after the game" eval 'watch_done && [ "$(sess result)" = left_running ] && steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
steam_down

# Steam quits during the game; Play in the grace starts it again: that Play's Steam (a 4 s grace)
: >"$STANDIN_LOG"; GW2_ON_MAC_WATCH_GRACE=4 "$G" play >/dev/null 2>&1; started; watcher_up; steam_up
game_up; wait_stage playing
steam_down; game_down; wait_stage grace
# (Steam once the watcher has the join, not once the Play returns: the grace runs from the join,
# and the Play still has its checks to do)
: >"$STANDIN_LOG"; "$G" play >/dev/null 2>&1 & jp=$!
i=0; until [ "$(sess replay)" = 1 ] || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done; steam_up; wait $jp
check "Play in the grace after Steam quit: joins (replay=1), its own Steam (started_steam=yes quit_steam=yes)" eval '[ "$(sess replay)/$(sess started_steam)/$(sess quit_steam)" = 1/yes/yes ] && wait_stage waiting_game'
game_session
check "  its game quits: that Steam quits" eval 'watch_done && [ "$(sess result)" = quit ] && ! steam_runs'

# Play in the grace, and its game only after the grace: the watcher waits for that Play's game
# instead of quitting Steam. The grace is 6 s, at least 5 s as the watcher counts whole seconds.
# The Play starts as soon as the grace does and returns once the watcher has its join. On my
# runners, a settings change and a joining Play with its checks took 1.9 s at most.
: >"$STANDIN_LOG"; GW2_ON_MAC_WATCH_GRACE=6 "$G" play >/dev/null 2>&1; started; watcher_up; steam_up
game_session
check "Play in the grace: joins (replay=1)" eval 'g play >/dev/null 2>&1 && [ "$(sess replay)" = 1 ]'
check "  past the grace, the watcher waits for the game again: no -shutdown, Steam runs" eval 'wait_stage waiting_game && steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
game_session
check "  then that game quits: Steam quits" eval 'watch_done && [ "$(sess result)" = quit ] && ! steam_runs'

# Play in the grace, and its game starts within the grace: once it quits, Steam quits
: >"$STANDIN_LOG"; GW2_ON_MAC_WATCH_GRACE=4 "$G" play >/dev/null 2>&1; started; watcher_up; steam_up
game_session; splay
game_session
check "Play and its game within the grace: after that game, Steam quits" eval 'watch_done && [ "$(sess result)" = quit ] && [ "$(sess replay)" = 1 ] && ! steam_runs'

# My fork's build is 44 MB, and the stand-in's files are a few bytes: with 44 MB of random bytes
# added to the component (and the engine's tree made from it again), one Play and one status each
# compare the engine's tree with the component once (a cmp on PATH counts the files compared), and
# two Plays at once (below) still meet: the joining one waits about 3.6 s for the first one's
# watcher (join_session)
BIG="$COMP/dxmt/real-size.bin"
head -c 46137344 /dev/urandom >"$BIG"
g set dxmt fork >/dev/null
mkdir -p "$SANDBOX/cmp-bin"
printf '#!/bin/bash\necho "$3" >>"%s/cmp.log"\nexec /usr/bin/cmp "$@"\n' "$SANDBOX" >"$SANDBOX/cmp-bin/cmp"
chmod 755 "$SANDBOX/cmp-bin/cmp"
# compared <gw2om.sh's arguments>: the files that command compared in the engine's active tree, and
# once is every file of the component
compared() { : >"$SANDBOX/cmp.log"; PATH="$SANDBOX/cmp-bin:$PATH" "$G" "$@" >/dev/null 2>&1; grep -cF "$ENG/lib/wine/dxgi/dxmt/" "$SANDBOX/cmp.log"; }
once=$(find "$COMP/dxmt" -type f | wc -l | tr -d ' ')
: >"$STANDIN_LOG"; n=$(compared play); started; watcher_up; steam_up
check "my DXMT at its real size (44 MB): Play compares the engine's tree with it once" [ "$n" = "$once" ]
game_session; watch_done
check "  status once" [ "$(compared status)" = "$once" ]

# two Plays at once: one watcher, the other joins. The Play that joins compares the engine's tree
# with my DXMT after its join, while the watcher's grace for Steam already runs: on the dev build's
# runner, with my real build and the file above (88 MB), it returned 2 s after its join. Here a cmp
# on PATH, only for these two Plays, makes the joined Play's comparison (replay=1 in the session)
# take 4 s longer on any runner. So the stand-in Steam comes once the first Play's watcher runs,
# not once both Plays have returned. The watcher looks every second here (WATCH_POLL=1): the
# joining Play looks for the first one's watcher (WATCH_POLL * 3 + 3) * 10 times, 0.1 s apart
# (join_session), 36 times at the suite's 0.2 s and 60 at 1 s, and the first Play took 3 s to its
# watcher on the dev build's runner.
mkdir -p "$SANDBOX/slow-bin"
printf '#!/bin/bash\ncase "$3" in */real-size.bin) ! grep -qx replay=1 "%s/session" || sleep 4 ;; esac\nexec /usr/bin/cmp "$@"\n' "$AD" >"$SANDBOX/slow-bin/cmp"
chmod 755 "$SANDBOX/slow-bin/cmp"
: >"$STANDIN_LOG"
PATH="$SANDBOX/slow-bin:$PATH" GW2_ON_MAC_WATCH_POLL=1 "$G" play >/dev/null 2>&1 & p1=$!
PATH="$SANDBOX/slow-bin:$PATH" GW2_ON_MAC_WATCH_POLL=1 "$G" play >/dev/null 2>&1 & p2=$!
started; watcher_up; steam_up; wait $p1 $p2
check "two Plays at once: one watcher, the other joined" eval '[ "$(watchers)" = 1 ] && watcher_runs && [ "$(sess replay)" = 1 ]'
game_session
check "  Steam quits once" eval 'watch_done && [ "$(sess result)" = quit ] && [ "$(grep -c "steam.exe -shutdown" "$STANDIN_LOG")" = 1 ]'
# (a tree with a file more than the component still counts as mine: the file goes from both)
rm -f "$BIG" "$ENG/lib/wine/dxgi/dxmt/real-size.bin"; rm -rf "$SANDBOX/slow-bin"
check "the usual build again, in the component and the engine's tree" eval 'dxgi_is fork && [ "$(st dxmt_tree)" = fork ]'

# the lock is the kernel's (flock): a lock file a dead watcher left holds nothing
echo "left behind" >"$AD/.session.lock"
splay
check "a lock file left behind doesn't block: a new session (replay=0)" eval 'watcher_runs && [ "$(sess replay)" = 0 ]'
watch_done

# the lock held, but no watcher answers (a stuck holder): Play doesn't start the game (fails closed)
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 30 & hp=$!
sleep 0.3
: >"$STANDIN_LOG"
"$G" play >"$SANDBOX/stuck.txt" 2>&1 && rc=0 || rc=$?
check "the session's lock held without an answer: Play refuses and starts nothing" eval '[ "$rc" != 0 ] && has "$SANDBOX/stuck.txt" "@error $APP_NAME.s last session did not answer" && ! has "$STANDIN_LOG" "^wine "'
kill $hp 2>/dev/null; wait $hp 2>/dev/null

# the lock's helper: bundled and signed; without it, the game starts, with no watcher (Steam stays open)
LK="$APP/Contents/Resources/helpers/sessionlock"
check "helpers/sessionlock is bundled and signed" eval '[ -x "$LK" ] && codesign --verify "$LK" 2>/dev/null'
watch_done
g set retina on >/dev/null   # (off since the Busy checks; back off below)
mv "$LK" "$SANDBOX/sessionlock.aside"
: >"$STANDIN_LOG"; wp=$(sess watcher_pid)
"$G" play >"$SANDBOX/nolock.txt" 2>&1; started
check "  without it: Play warns, starts the game, no watcher" eval 'has "$SANDBOX/nolock.txt" "^@warn .*session helper is missing" && has "$SANDBOX/nolock.txt" "^@done" && has "$STANDIN_LOG" "^wine " && [ "$(sess watcher_pid)" = "$wp" ] && [ "$(watchers)" = 0 ]'
# (that Play starts Wine without the lock, so registry writes can't be kept apart from it: they wait)
"$G" set retina off >"$SANDBOX/nolock-set.txt" 2>&1
check "  a setting is saved, its registry write waits for the helper" eval 'has "$SANDBOX/nolock-set.txt" "^@done" && [ "$(sett retina)" = off ] && reg "$ALL_MAC" RetinaMode y && has "$SANDBOX/nolock-set.txt" "registry settings wait for it"'
mv "$SANDBOX/sessionlock.aside" "$LK"
check "  with it back, the next write applies it" eval '"$G" set retina off >/dev/null && reg "$ALL_MAC" RetinaMode n'

# a Steam that ignores -shutdown: wineserver -k (a stand-in wineserver that ends it)
touch "$SANDBOX/steam.stubborn"
mv "$ENG/bin/wineserver" "$SANDBOX/wineserver.heat"
printf '#!/bin/bash\necho "wineserver $*" >>"$STANDIN_LOG"\n[ "$1" != -k ] || kill "$(cat "%s")" 2>/dev/null\nexit 0\n' "$SP" >"$ENG/bin/wineserver" && chmod 755 "$ENG/bin/wineserver"
splay; steam_up
game_session
wait_stage closing_steam; "$G" play >"$SANDBOX/closing.txt" 2>&1
check "Play while Steam is quitting is refused" has "$SANDBOX/closing.txt" "@error Steam is quitting"
check "Steam ignores -shutdown: wineserver -k for the bottle after the wait" eval 'watch_done && [ "$(sess result)" = killed ] && has "$STANDIN_LOG" "steam.exe -shutdown" && has "$STANDIN_LOG" "^wineserver -k" && ! steam_runs'
mv -f "$SANDBOX/wineserver.heat" "$ENG/bin/wineserver"
rm -f "$SANDBOX/steam.stubborn" "$ENG/bin/steam.exe" "$ENG/bin/Gw2-64.exe"
check "busy=none after the sessions" [ "$(st busy)" = none ]

section "The session's stages (session-status: stand-in processes, fixture logs)"
# Steam's and the game's processes are sleepers at the engine's paths; the watcher is a sleeper
# named gw2om.sh holding the session's lock (as watch-session does), its session file written
# here; Steam's logs carry a made-up account that must never show up in the output
ss() { g session-status | sed -n "s/^$1=//p"; }
at() { date -r "$1" '+%Y-%m-%d %H:%M:%S'; }
now=$(date +%s) T0=$((now - 60))
SL="$STEAM/logs"
mkdir -p "$SL"
OLD="[$(at $((now - 3600)))]" NEW="[$(at $((now - 30)))]"
session_file() { { echo "route=steam"; echo "started_steam=yes"; [ -z "${SW-hidden}" ] || echo "steam_window=${SW-hidden}"; echo "quit_steam=${QS:-yes}"
  echo "watcher_pid=$wp"; echo "stage=$1"; echo "started=$T0"; echo "replay=0"; echo "game_started=${GS:-}"
  echo "requests=${RQ:-0}"; echo "updated=$now"; } >"$AD/session"; }
# (the session's lock is a file with a kernel flock: the app's helper holds it; the stand-in
# watcher's command line is "gw2om.sh watch-session", as watcher_proc looks for)
rm -rf "$AD/.session.lock" && mkdir -p "$SANDBOX/watcher" && : >"$AD/session.req"
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 120 & lp=$!
printf '#!/bin/bash\nsleep 120 & wait\n' >"$SANDBOX/watcher/gw2om.sh" && chmod 755 "$SANDBOX/watcher/gw2om.sh"
"$SANDBOX/watcher/gw2om.sh" watch-session & wp=$!
sleep 0.3
# answer <accept|refuse>: the stand-in watcher's next look, once a request is in session.req: it
# counts it, and leaves Steam open (accept) or has started quitting it (refuse)
answer() {
  local i=0
  while [ "$(grep -c . "$AD/session.req" 2>/dev/null)" -lt 1 ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  if [ "$1" = accept ]; then SW=shown QS=no RQ=1 session_file waiting_game; else RQ=1 session_file closing_steam; fi
}
cp "$SANDBOX/sleeper" "$ENG/bin/steam.exe" && cp "$SANDBOX/sleeper" "$ENG/bin/steamwebhelper.exe"
: >"$SL/bootstrap_log.txt"; : >"$SL/content_log.txt"; : >"$SL/connection_log.txt"
rm -f "$LOGS/Gw2-64_d3d11.log"
# (no session file, no watcher: the last Play's session.env is recent, so a start is under way)
rm -f "$AD/session"
check "after play, nothing up yet, no watcher: starting_steam (from session.env)" [ "$(ss stage)" = starting_steam ]
session_file waiting_game
check "the watcher waits for the game, no Steam yet: starting_steam, steam=none" eval '[ "$(ss stage)/$(ss steam)" = starting_steam/none ]'
check "  elapsed since the session's start" eval 'e=$(ss elapsed); [ "$e" -ge 60 ] && [ "$e" -le 65 ]'
check "  status: session=live (the window picks it up when it opens)" [ "$(st session)" = live ]
check "  a Play that joined the session (--since its time): elapsed from then" eval 'e=$(g session-status --since $((now - 5)) | sed -n "s/^elapsed=//p"); [ "$e" -ge 5 ] && [ "$e" -le 10 ]'
check "  an earlier --since than the session's start: from the start" eval 'e=$(g session-status --since $((now - 900)) | sed -n "s/^elapsed=//p"); [ "$e" -ge 60 ] && [ "$e" -le 65 ]'
session_file "done"
check "  the watcher's session done: session=none, stage=none" eval '[ "$(st session)/$(ss stage)" = none/none ]'
session_file waiting_game
"$ENG/bin/steam.exe" 120 & sp=$!
sleep 0.3
{ echo "$NEW Startup - Steam Client launched with: \"C:\\Program Files (x86)\\Steam\\steam.exe\" -silent -applaunch 1284210"
  echo "$NEW Verifying installation..."; echo "$NEW Verifying all executable checksums"; } >"$SL/bootstrap_log.txt"
check "Steam verifies itself: updating_steam, 'Steam checks its own files'" eval '[ "$(ss stage)" = updating_steam ] && [ "$(ss detail)" = "Steam checks its own files" ]'
echo "$NEW Package file strings_all.zip.vz.0123abcd_4567 missing or incorrect size" >>"$SL/bootstrap_log.txt"
check "  a package it finds damaged: still updating_steam" [ "$(ss stage)" = updating_steam ]
echo "$NEW Verification complete" >>"$SL/bootstrap_log.txt"
check "  verification complete: no longer updating" [ "$(ss stage)" = starting_steam ]
{ echo "$OLD Downloading update (100 of 200 KB)..."
  echo "$NEW Startup - Steam Client launched with: \"C:\\Program Files (x86)\\Steam\\steam.exe\" -silent -applaunch 1284210"
  echo "$NEW Verification complete"
  echo "$NEW Downloading update (49,612 of 241,937 KB)..."; } >"$SL/bootstrap_log.txt"
check "Steam downloads its update: updating_steam, 20%" eval '[ "$(ss stage)/$(ss progress)" = updating_steam/20 ] && [ "$(ss detail)" = "Steam updates itself · 20%" ]'
check "  steam=bg (the watcher's steam_window=hidden)" [ "$(ss steam)" = bg ]
echo "$NEW Installing update..." >>"$SL/bootstrap_log.txt"
check "  installing it: still updating_steam" [ "$(ss stage)" = updating_steam ]
{ echo "$NEW Update complete, launching Steam..."; echo "$NEW Shutdown"
  echo "$NEW Startup - Steam Client launched with: \"C:\\Program Files (x86)\\Steam\\steam.exe\" -applaunch 1284210"
  echo "$NEW Verification complete"; } >>"$SL/bootstrap_log.txt"
check "update done, no web helper, not signed in: starting_steam" [ "$(ss stage)" = starting_steam ]
"$ENG/bin/steamwebhelper.exe" 120 & hp=$!
sleep 0.3
{ echo "$OLD [Logged On, 0, 0] [U:1:39734314] RecvMsgClientLogOnResponse() : processing complete"
  echo "$NEW [Connecting, 0, 0] [U:1:39734314] Connect() starting connection"
  echo "$NEW [Logging On, 0, 0] [U:1:39734314] Logging on zz_acct_name 76561198000000042"; } >"$SL/connection_log.txt"
check "the web helper up, not logged on since the start: signing_in (an older logon doesn't count)" [ "$(ss stage)" = signing_in ]
SW="" session_file waiting_game
check "  no steam_window in the session: from Steam's last start line (no -silent): steam=window" [ "$(ss steam)" = window ]
session_file waiting_game
echo "$NEW [Logged On, 0, 0] [U:1:39734314] RecvMsgClientLogOnResponse() : processing complete" >>"$SL/connection_log.txt"
check "logged on, no content check, no game yet: starting_game" [ "$(ss stage)" = starting_game ]
{ echo "$OLD AppID 1284210 state changed : Fully Installed,Validating,"
  echo "$NEW AppID 1284210 state changed : Fully Installed,"; } >"$SL/content_log.txt"
check "  an older check doesn't count" [ "$(ss stage)" = starting_game ]
{ echo "$NEW AppID 1284210 update changed : Running Update,Validating,"
  echo "$NEW User zz_acct_name (76561198000000042) [U:1:39734314] logged in"; } >>"$SL/content_log.txt"
check "Steam validates the game: checking_files, 'Steam verifies Guild Wars 2'" eval '[ "$(ss stage)" = checking_files ] && [ "$(ss detail)" = "Steam verifies Guild Wars 2" ] && [ -z "$(ss progress)" ]'
M="$STEAM/steamapps/appmanifest_1284210.acf"
cp "$M" "$SANDBOX/acf.keep"
# (while Steam updates the game its appmanifest isn't "fully installed": StateFlags 1026)
{ grep -v -e BytesToDownload -e BytesDownloaded "$SANDBOX/acf.keep" | sed '$d; s/"StateFlags"\([[:space:]]*\)"4"/"StateFlags"\1"1026"/'
  printf '\t"BytesToDownload"\t\t"4000"\n\t"BytesDownloaded"\t\t"1000"\n}\n'; } >"$M"
echo "$NEW AppID 1284210 update changed : Running Update,Downloading," >>"$SL/content_log.txt"
check "Steam updates the game: checking_files with the appmanifest's progress (25%)" eval '[ "$(ss stage)/$(ss progress)" = checking_files/25 ] && [ "$(ss detail)" = "Steam updates Guild Wars 2 · 25%" ]'
check "  status meanwhile: game=no (not fully installed), stage=finished, busy=steam, session=live (the window's model keeps the session)" eval '[ "$(st game)/$(st stage)/$(st busy)/$(st session)" = no/finished/steam/live ]'
cp "$SANDBOX/acf.keep" "$M"
echo "$NEW AppID 1284210 finished update (BytesDownloaded=1000, BytesStaged=0)" >>"$SL/content_log.txt"
check "  update finished: starting_game" [ "$(ss stage)" = starting_game ]
out=$(g session-status)
check "no account name, Steam ID or log line in the output" eval '! printf "%s" "$out" | grep -qE "zz_acct_name|7656119|U:1:|Logged|AppID|steamapps"'
cp "$SANDBOX/sleeper" "$ENG/bin/Gw2-64.exe"
"$ENG/bin/Gw2-64.exe" 120 & gp=$!
sleep 0.3
check "Gw2-64.exe up, no DXMT log yet: starting_game, game=yes" eval '[ "$(ss stage)/$(ss game)" = starting_game/yes ]'
printf 'info:  Found config file: x\ninfo:  Using feature level D3D_FEATURE_LEVEL_11_1\n' >"$LOGS/Gw2-64_d3d11.log"
touch -t "$(date -r $((T0 - 600)) '+%Y%m%d%H%M.%S')" "$LOGS/Gw2-64_d3d11.log"
check "  a DXMT log from before the session doesn't count" [ "$(ss stage)" = starting_game ]
touch "$LOGS/Gw2-64_d3d11.log"
check "DXMT's device is there (the engine's DXMT logs nothing per frame): playing, with the game's pid" eval '[ "$(ss stage)/$(ss game_pid)" = "playing/$gp" ]'
check "  game_elapsed from the game process (the watcher hasn't seen it yet)" eval 'e=$(ss game_elapsed); [ -n "$e" ] && [ "$e" -le 5 ]'
GS=$(($(date +%s) - 72)) session_file playing
check "  game_elapsed from the watcher's game_started" eval 'e=$(ss game_elapsed); [ "$e" -ge 72 ] && [ "$e" -le 75 ]'
check "  quit_steam=yes from the watcher, closing=no while the game runs" eval '[ "$(ss quit_steam)/$(ss closing)" = yes/no ]'
kill $gp 2>/dev/null; wait $gp 2>/dev/null
session_file grace
check "the game quit, the watcher's grace: stage=none, closing=yes" eval '[ "$(ss stage)/$(ss closing)/$(ss game)" = none/yes/no ]'
check "  status: session=live while Steam runs" [ "$(st session)" = live ]
session_file closing_steam
check "  closing_steam: closing=yes" [ "$(ss closing)" = yes ]
QS=no session_file closing_steam
check "  quit_steam=no (Steam's window, or the setting off): closing=no" [ "$(ss closing)" = no ]
QS=no session_file grace
check "a restart's grace with Steam staying: stage=none, closing=no, but watching=yes" eval '[ "$(ss stage)/$(ss closing)/$(ss watching)" = none/no/yes ]'
"$ENG/bin/Gw2-64.exe" 120 & gp=$!
sleep 0.3
check "  the game back within the grace: playing again" eval '[ "$(ss stage)/$(ss game)" = playing/yes ]'
kill $gp 2>/dev/null; wait $gp 2>/dev/null
rm -f "$ENG/bin/Gw2-64.exe"
session_file closing_steam
check "show-steam while the watcher quits Steam: refused, no request, nothing started" eval ': >"$STANDIN_LOG"; ! g show-steam >/dev/null 2>&1 && ! has "$STANDIN_LOG" "steam://open/main" && [ ! -s "$AD/session.req" ]'
session_file waiting_game
: >"$STANDIN_LOG"
answer accept & ap=$!
out=$(g show-steam 2>&1); wait $ap
check "show-steam during the start: a 'shown' request, never a write of the session" eval '[ "$(cat "$AD/session.req")" = shown ]'
check "  the watcher accepts: Steam's window opens" eval 'has <(echo "$out") "^@done" && started && has "$STANDIN_LOG" "steam.exe steam://open/main"'
check "  session-status: steam=window, quit_steam=no" eval '[ "$(ss steam)/$(ss quit_steam)" = window/no ]'
: >"$AD/session.req"; : >"$STANDIN_LOG"
session_file waiting_game
answer refuse & ap=$!
out=$(g show-steam 2>&1) && rc=0 || rc=$?; wait $ap
check "  the watcher refuses (it started quitting Steam): no window" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error Steam is quitting" && ! has "$STANDIN_LOG" "steam://open/main"'
: >"$AD/session.req"; : >"$STANDIN_LOG"
session_file waiting_game
out=$(GW2_ON_MAC_WATCH_POLL=0 g show-steam 2>&1) && rc=0 || rc=$?
check "  the watcher doesn't answer: refused, no window (it might still quit that Steam)" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error .*didn.t answer" && ! has "$STANDIN_LOG" "steam://open/main" && has "$LOGS/install.log" "Steam.s window stays shut"'
: >"$AD/session.req"
# (the lock held, the session not naming a running watcher yet: a Play handing the session over)
wk=$wp; wp=$$; session_file waiting_game; wp=$wk
out=$(GW2_ON_MAC_WATCH_POLL=0 g show-steam 2>&1) && rc=0 || rc=$?
check "  the lock held, no watcher named yet (a Play handing over): refused, no request, no window" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error .*handing the session over" && [ ! -s "$AD/session.req" ] && ! has "$STANDIN_LOG" "steam://open/main"'
: >"$AD/session.req"
session_file waiting_game
kill $wp 2>/dev/null; wait $wp 2>/dev/null
check "a dead watcher's unfinished session is over: Steam on its own is stage=none" eval '[ "$(ss stage)/$(ss closing)/$(ss quit_steam)/$(ss watching)" = none/no/no/no ]'
check "  status: session=none (busy=steam)" [ "$(st session)/$(st busy)" = none/steam ]
kill $lp 2>/dev/null; wait $lp 2>/dev/null
: >"$STANDIN_LOG"
check "show-steam with Steam running, no watcher: steam.exe steam://open/main through the engine" eval 'g show-steam | grep -q "^@done" && started && has "$STANDIN_LOG" "steam.exe steam://open/main"'
kill $sp $hp 2>/dev/null; wait $sp $hp 2>/dev/null
check "show-steam without Steam: refused" eval '! g show-steam >/dev/null 2>&1 && has <(g show-steam) "@error Steam isn.t running"'
rm -rf "$AD/session" "$AD/session.req" "$AD/.session.lock" "$ENG/bin/steam.exe" "$ENG/bin/steamwebhelper.exe" "$LOGS/Gw2-64_d3d11.log"

section "The frame-limiter hint (the game's GFXSettings, only read)"
GFX="$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2/GFXSettings.Gw2-64.exe.xml"
mkdir -p "$(dirname "$GFX")"
gfx() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<GSA_SDK Version="2.1.18431650.0">\n    <GAMESETTINGS>\n        <OPTION Name="frameLimit" Registered="True" Type="Enum" Value="%s">\n            <ENUM EnumValue="unlimited"/>\n            <ENUM EnumValue="60"/>\n        </OPTION>\n        <OPTION Name="charModelLimit" Registered="True" Type="Enum" Value="highest">\n        </OPTION>\n        <OPTION Name="verticalSync" Registered="True" Type="Bool" Value="%s"/>\n    </GAMESETTINGS>\n</GSA_SDK>\n' "$1" "$2" >"$GFX"; }
gfx 60 true
check "Frame Limiter 60 with vsync: limiter_hint=yes, limiter_value=60" eval '[ "$(ss limiter_hint)/$(ss limiter_value)" = yes/60 ]'
gfx 120 true
check "  120 with vsync: yes (120)" eval '[ "$(ss limiter_hint)/$(ss limiter_value)" = yes/120 ]'
gfx unlimited true
check "  Unlimited with vsync: no" [ "$(ss limiter_hint)" = no ]
gfx 60 false
check "  60 without vsync: no" [ "$(ss limiter_hint)" = no ]
sum=$(shasum "$GFX")
g session-status >/dev/null
check "  the file is only read" [ "$(shasum "$GFX")" = "$sum" ]
rm -f "$GFX"
check "  no settings file: no" [ "$(ss limiter_hint)" = no ]

section "Repair and Troubleshooting"
T="$ENG/lib/wine/dxgi/dxmt"
echo "something else" >"$T/aarch64-windows/d3d11.dll"
check "another build of my DXMT in the engine (an earlier version's): graphics=switch" [ "$(st graphics)/$(st dxmt_tree)" = switch/oldfork ]
: >"$STANDIN_LOG"; out=$(g play 2>&1); started
check "  Play puts this version's in before Wine starts, and says so" eval 'dxgi_is fork && echo "$out" | grep -q "^DXMT: my DXMT fork" && has "$LOGS/session.env" "^DXMT_TREE=fork$"'
watch_done
rm "$T/.gw2om-dxmt"; echo "something else" >"$T/aarch64-windows/d3d11.dll"
check "graphics=other: a DXMT tree that is neither the engine's own nor mine" [ "$(st graphics)" = other ]
: >"$STANDIN_LOG"; out=$(g play 2>&1); started
check "  Play says Repair and leaves the engine as it is" eval 'echo "$out" | grep -q "^@warn .*Click Repair" && has "$T/aarch64-windows/d3d11.dll" "something else"'
watch_done
out=$(g repair 2>&1) && rc=0 || rc=$?
check "repair exits 0, unpacking the engine again" eval '[ "$rc" = 0 ] && echo "$out" | grep -q "unpacking the engine again"'
check "graphics=yes after repair, the engine as it ships with my DXMT in its tree" eval '[ "$(st graphics)" = yes ] && [ "$(engine_diff)" = "$SDK_DIFF" ] && dxgi_is fork'
check "  repair says which DXMT draws the game" eval 'echo "$out" | grep -q "^@done Repaired: .* The game draws with my DXMT fork ("'
check "  the Retina setting saved during the session is in the registry" reg "$ALL_MAC" RetinaMode n
g set retina on >/dev/null
g set dxmt engine >/dev/null
rm "$T/aarch64-unix/winemetal.so" && echo "something else" >"$T/aarch64-unix/winemetal.so"
check "graphics=other with another winemetal.so in the engine's own tree" [ "$(st graphics)" = other ]
out=$(g set dxmt fork 2>&1)
check "  set dxmt says Repair" eval 'echo "$out" | grep -q "^@warn .*Click Repair" && has "$T/aarch64-unix/winemetal.so" "something else"'
g set dxmt engine >/dev/null
g repair >/dev/null 2>&1
check "  repair puts the engine's own back" eval 'dxgi_is engine && [ "$(st graphics)" = yes ]'
g set dxmt fork >/dev/null
# An ntdll.so that is neither the engine's own nor mine, and no engine's own next to it
echo "something else" >"$NT/ntdll.so" && rm -f "$NT/ntdll.so.engine"
check "wine_ready=other: an ntdll.so that is neither the engine's own nor mine, and none next to it" [ "$(st wine_ready)/$(st wine_file)" = other/other ]
: >"$STANDIN_LOG"; out=$(g play 2>&1); started
check "  Play says Repair and leaves it as it is" eval 'echo "$out" | grep -q "^@warn The engine.s ntdll.so is neither its own nor mine. Click Repair." && has "$NT/ntdll.so" "something else"'
watch_done
if mine; then
  out=$(g set wine engine 2>&1)
  check "  set wine says Repair too, and changes nothing" eval 'echo "$out" | grep -q "^@warn .*ntdll.so .*Click Repair" && has "$NT/ntdll.so" "something else"'
  g set wine mine >/dev/null
fi
out=$(g repair 2>&1) && rc=0 || rc=$?
check "  repair unpacks the engine again and puts the ntdll.so Settings asks for in: $MYWINE" \
  eval '[ "$rc" = 0 ] && echo "$out" | grep -q "unpacking the engine again" && ntdll_is $MYWINE && [ "$(st wine_ready)" = yes ] && [ "$(engine_diff)" = "$SDK_DIFF" ]'
check "  and says which ntdll.so, winemac.so and FEX are in the engine" has <(echo "$out") "^@done Repaired: .*, with $([ "$MYWINE" = mine ] && echo "my ntdll.so (jdrly/wine ${MYWINE_COMMIT:0:11})" || echo "the engine's own ntdll.so (athei/wine $ENGINE_WINE)"), with $(drv && echo "my winemac.so (jdrly/wine ${MYDRV_COMMIT:0:11})" || echo "the engine's own winemac.so (athei/wine $ENGINE_WINE)"), and runs on the engine's own FEX (athei/FEX $ENGINE_FEX)\.$"
check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
# A winemac.so that is neither the engine's own nor mine, and no engine's own next to it
echo "something else" >"$NT/winemac.so" && rm -f "$NT/winemac.so.engine"
check "macdrv_ready=other: a winemac.so that is neither the engine's own nor mine, and none next to it" [ "$(st macdrv_ready)/$(st macdrv_file)" = other/other ]
out=$(g repair 2>&1) && rc=0 || rc=$?
check "  repair unpacks the engine again and puts the winemac.so Settings asks for in: $MYDRV, and the ntdll.so: $MYWINE" \
  eval '[ "$rc" = 0 ] && echo "$out" | grep -q "unpacking the engine again" && winemac_is $MYDRV && ntdll_is $MYWINE && [ "$(st macdrv_ready)" = yes ] && [ "$(engine_diff)" = "$SDK_DIFF" ]'
check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
check "the game and the settings stay" [ "$(st game)/$(sett launchopts)" = yes/-maploadinfo ]

MF="$AD/install-manifest.json"
PAUSE="$SANDBOX/pause"
wait_at() { local i=0; until [ -e "$PAUSE.at" ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$PAUSE.at" ]; }
watch_done
# the install lock: one left by a process that is gone is taken over by exactly one contender (the
# claim, a kernel lock), and a live owner's lock is never removed by anyone else
( exit 0 ) & dp=$!; wait $dp
mkdir "$AD/.lock" && echo "$dp" >"$AD/.lock/pid"
touch "$PAUSE"; rm -f "$PAUSE.at"
GW2_ON_MAC_TEST_PAUSE="$PAUSE" GW2_ON_MAC_TEST_PAUSE_AT=lock-stale-checked "$G" set launchopts -contenderA >"$SANDBOX/contA.txt" 2>&1 & ca=$!
check "a lock left by a gone process: the first contender has the claim (paused after its check)" eval 'wait_at && "$APP/Contents/Resources/helpers/sessionlock" held "$LOGS/.lock-claim"'
out=$(GW2_ON_MAC_LOCK_WAIT=1 "$G" repair 2>&1) && rc=0 || rc=$?
check "  a second contender is refused meanwhile and leaves the lock alone" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "Another $APP_NAME" && [ "$(cat "$AD/.lock/pid")" = "$dp" ]'
out=$(GW2_ON_MAC_LOCK_WAIT=1 "$G" set launchopts -contenderB 2>&1) && rc=0 || rc=$?
check "  so does a third (a settings change)" eval '[ "$rc" != 0 ] && [ "$(cat "$AD/.lock/pid")" = "$dp" ]'
rm -f "$PAUSE"; wait $ca; rc=$?
check "  the first one takes it over, does its work and removes its own lock" eval '[ "$rc" = 0 ] && [ "$(sett launchopts)" = -contenderA ] && [ ! -e "$AD/.lock" ] && has "$LOGS/install.log" "taking over the install lock"'
"$SANDBOX/sleeper" 30 & lp=$!
mkdir "$AD/.lock" && echo "$lp" >"$AD/.lock/pid"
out=$(g set launchopts -x 2>&1) && rc=0 || rc=$?
check "a live owner's lock: refused, and the lock stays the owner's" eval '[ "$rc" != 0 ] && [ "$(cat "$AD/.lock/pid")" = "$lp" ] && [ "$(sett launchopts)" = -contenderA ]'
kill $lp 2>/dev/null; wait $lp 2>/dev/null; rm -rf "$AD/.lock"
g set launchopts -maploadinfo >/dev/null
# a fresh acquisition can't slip in between a contender's reading of the owner and its check:
# owner A holds the lock; contender B reads A's pid under the claim and pauses; A finishes, but
# unlocking needs the claim too, so A waits; a fresh contender C waits for the claim and is
# refused; B then finds A still running and is refused; A unlocks
wait_file() { local i=0; until [ -e "$1" ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]; }
P1="$SANDBOX/pauseA" P2="$SANDBOX/pauseB"
touch "$P1" "$P2"; rm -f "$P1.at" "$P2.at"
# (A's pid is the lock's: the app's gw2om.sh itself, not the wrapper)
GW2_ON_MAC_TEST_PAUSE="$P1" GW2_ON_MAC_TEST_PAUSE_AT=locked "$GW2OM" set launchopts -ownerA >"$SANDBOX/ownA.txt" 2>&1 & oa=$!
wait_file "$P1.at"
GW2_ON_MAC_TEST_PAUSE="$P2" GW2_ON_MAC_TEST_PAUSE_AT=lock-owner-read "$G" set launchopts -contenderB >"$SANDBOX/contB.txt" 2>&1 & ob=$!
check "owner A holds the lock; contender B has read A's pid under the claim (paused)" eval 'wait_file "$P2.at" && [ "$(cat "$AD/.lock/pid")" = "$oa" ] && "$APP/Contents/Resources/helpers/sessionlock" held "$LOGS/.lock-claim"'
rm -f "$P1"; sleep 0.5
check "  A, done, waits for the claim to unlock: the lock is still A's" eval 'kill -0 $oa 2>/dev/null && [ "$(cat "$AD/.lock/pid")" = "$oa" ]'
out=$(GW2_ON_MAC_LOCK_WAIT=1 "$G" set launchopts -freshC 2>&1) && rc=0 || rc=$?
check "  a fresh acquisition (C) waits for the claim and is refused: the lock still A's, nothing of C's" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "Another $APP_NAME" && [ "$(cat "$AD/.lock/pid")" = "$oa" ] && [ "$(sett launchopts)" != -freshC ]'
rm -f "$P2"; wait $ob; rb=$?; wait $oa; ra=$?
check "  B, resumed, finds A still there and is refused; A unlocks and ends: its setting, no lock left" eval '[ "$rb" != 0 ] && has "$SANDBOX/contB.txt" "Another $APP_NAME" && [ "$ra" = 0 ] && [ "$(sett launchopts)" = -ownerA ] && [ ! -e "$AD/.lock" ]'
g set launchopts -maploadinfo >/dev/null
# an earlier version's manifest: the next Play brings it to this version
sed -i '' -e 's/"version": "[^"]*"/"version": "0.2.0-dev.0"/' "$MF"
out=$(g play 2>&1); started
check "an earlier version's manifest: Play brings it to this version" [ "$(plutil -extract version raw -o - "$MF")" = "$(st version)" ]
check "  the manifest names the engine's build" eval '[ "$(plutil -extract engine raw -o - "$MF")/$(plutil -extract engine_dxmt raw -o - "$MF")" = mach9-v0.3.1/d903db89036 ]'
watch_done
echo "shader" >"$DXMT_CACHE/shaders_320.db"
mkdir -p "$DXMT_CACHE_ENGINE" && echo "shader" >"$DXMT_CACHE_ENGINE/shaders_320.db"
check "reset-shaders empties DXMT's caches, my fork's and the engine's DXMT's" sh -c "'$G' reset-shaders | grep -q '@done' && [ -d '$DXMT_CACHE' ] && [ ! -e '$DXMT_CACHE/shaders_320.db' ] && [ ! -e '$DXMT_CACHE_ENGINE' ]"
check "  and leaves the per-user cache folder's dxmt/ alone" other_dxmt_kept
# The engine's archive from a browser, put into the downloads folder by hand: quarantined, and tar
# copies the attribute onto every file it unpacks; the app takes it off the whole engine
QA="$CACHE/downloads/engine.tar.xz"
xattr -w com.apple.quarantine "0083;6731f0a1;Safari;" "$QA"
mkdir -p "$SANDBOX/tar-check" && tar -xJf "$QA" -C "$SANDBOX/tar-check"
check "a quarantined archive: tar alone copies the attribute onto what it unpacks" sh -c "xattr -r '$SANDBOX/tar-check' | grep -q com.apple.quarantine"
# An app copied out of a DMG downloaded in a browser (a dev build: ad hoc signed, not notarized):
# its components are quarantined too, and the DXMT tree and version.dll are copied from them
qc() { find "$COMP/dxmt" -type f; [ ! -d "$COMP/ntdll" ] || find "$COMP/ntdll" -type f; [ ! -d "$COMP/macdrv" ] || find "$COMP/macdrv" -type f; [ ! -d "$COMP/fex" ] || find "$COMP/fex" -type f; echo "$COMP/ui-scale/version.dll"; }
qc | while IFS= read -r f; do xattr -w com.apple.quarantine "0083;6731f0a1;Safari;" "$f"; done
cp -p "$COMP/ui-scale/version.dll" "$SANDBOX/cp-check"
check "quarantined components: cp -p alone copies the attribute" sh -c "xattr '$SANDBOX/cp-check' | grep -q com.apple.quarantine"
out=$(g reinstall-engine 2>&1) && rc=0 || rc=$?
check "reinstall-engine from it: the verified download, unpacked again" eval '[ "$rc" = 0 ] && echo "$out" | grep -q "^@done" && echo "$out" | grep -q "using the verified download"'
check "  no file of the engine has the quarantine attribute (my DXMT tree, ntdll.so and winemac.so, copied from the components, included)" sh -c "! xattr -r '$ENG' | grep -q com.apple.quarantine"
check "  graphics=yes after it, the engine as it ships with my DXMT in its tree, the ntdll.so and winemac.so Settings asks for and the engine's own FEX" \
  eval '[ "$(st graphics)" = yes ] && [ "$(engine_diff)" = "$SDK_DIFF" ] && dxgi_is fork && ntdll_is $MYWINE && winemac_is $MYDRV && fex_is engine'
if fexb; then
  check "  set fex mine from quarantined components: none of FEX's files in the engine has the attribute" \
    eval 'g set fex mine >/dev/null && fex_is mine && ! xattr -r "$FW" | grep -q com.apple.quarantine && g set fex engine >/dev/null && fex_is engine'
fi
check "  wine.app untouched through all of it" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
check "set uiscale on: the game folder's version.dll has no quarantine attribute" eval 'g set uiscale on >/dev/null && [ -f "$GD/version.dll" ] && ! xattr "$GD/version.dll" | grep -q com.apple.quarantine'
g set uiscale off >/dev/null
qc | while IFS= read -r f; do xattr -d com.apple.quarantine "$f"; done
rm -f "$SANDBOX/cp-check"
rm -rf "$SANDBOX/tar-check"
mkdir "$AD/.lock"
check "a second operation is refused while one runs (lock)" sh -c "'$G' repair 2>&1 | grep -q 'Another $APP_NAME'"
rmdir "$AD/.lock"
GW2_ON_MAC_ENGINE_CHECKS=1 "$G" play >"$SANDBOX/realwine.txt" 2>&1 || true
check "the real engine's Wine never runs in a sandbox" has "$SANDBOX/realwine.txt" "Refusing to run the real Wine"

section "Uninstall"
GW2_ON_MAC_WATCH_GRACE=60 "$G" play >/dev/null 2>&1; started; watcher_up
wp=$(sess watcher_pid)
check "a session's watcher waits for the game" kill -0 "$wp"
mkdir -p "$CACHE/downloads" && echo x >"$CACHE/downloads/x"
out=$(g uninstall 2>&1) && rc=0 || rc=$?
check "uninstall exits 0" [ "$rc" = 0 ]
check "the phases 1-3" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 " ]
check "the app's folder is gone (engine, bottle with the game, settings, the session)" [ ! -e "$AD" ]
check "  the session's watcher stopped" sh -c "! kill -0 $wp 2>/dev/null"
check "its caches are gone" eval '[ ! -e "$CACHE" ] && [ ! -e "$DXMT_CACHE" ]'
check "the per-user cache folder's dxmt/ stays (another setup's)" other_dxmt_kept
check "the logs stay" [ -f "$LOGS/install.log" ]
check "status: not installed" [ "$(st installed)/$(st engine_installed)" = no/no ]

section "ArenaNet route"
if [ -f "$SIGNED_PE" ]; then
  cp -c "$SIGNED_PE" "$SANDBOX/Gw2Setup-64.exe"
  check "check-setup accepts a file signed by ArenaNet" sh -c "'$G' check-setup '$SANDBOX/Gw2Setup-64.exe' | grep -q '@done Gw2Setup-64.exe · signed by ArenaNet'"
  cp "$SANDBOX/Gw2Setup-64.exe" "$SANDBOX/changed.exe" && printf X | dd of="$SANDBOX/changed.exe" bs=1 seek=5000 conv=notrunc 2>/dev/null
  check "check-setup refuses a changed file" sh -c "'$G' check-setup '$SANDBOX/changed.exe' | grep -q 'changed after it was signed'"
  check "check-setup refuses a non-PE" sh -c "'$G' check-setup '$APP/Contents/Info.plist' | grep -q 'not a Windows program'"
  check "install arenanet with the changed file refused, nothing created" sh -c "! '$G' install arenanet '$SANDBOX/changed.exe' >/dev/null && [ ! -e '$AD/engine' ]"
  check "  and says why" sh -c "'$G' install arenanet '$SANDBOX/changed.exe' | grep -q '@error This file was changed'"
  : >"$STANDIN_LOG"
  out=$(g install arenanet "$SANDBOX/Gw2Setup-64.exe" 2>&1) && rc=0 || rc=$?
  check "install arenanet exits 0" [ "$rc" = 0 ]
  check "route=arenanet, stage=waiting_game, no Steam" [ "$(st route)$(st stage)$(st steam)" = arenanetwaiting_gameno ]
  check "ArenaNet's installer started in the bottle" has "$STANDIN_LOG" "Gw2Setup-64.exe"
  GD2="$BOTTLE/drive_c/Program Files/Guild Wars 2"
  mkdir -p "$GD2" && echo "stand-in game" >"$GD2/Gw2-64.exe" && mkfile -n 2g "$GD2/Gw2.dat"
  check "game=yes once Gw2.dat has data" [ "$(st game)" = yes ]
  check "finish" sh -c "'$G' finish | grep -q '@done'"
  : >"$STANDIN_LOG"
  g set launchopts -maploadinfo >/dev/null
  g play >/dev/null 2>&1
  started
  check "play starts the game's own launcher with the launch options" has "$STANDIN_LOG" 'wine C:\\Program Files\\Guild Wars 2\\Gw2-64.exe -maploadinfo'
  check "uninstall" sh -c "'$G' uninstall | grep -q '@done'"
else
  echo "  skip (no $SIGNED_PE)"
fi

section "A failed first install leaves nothing behind"
GW2_ON_MAC_STEAMSETUP_URL="file://$SANDBOX/missing.exe" "$G" install steam >"$SANDBOX/failed.txt" 2>&1 && rc=0 || rc=$?
check "install fails at Steam's download" eval '[ "$rc" != 0 ] && has "$SANDBOX/failed.txt" "@error The download of SteamSetup.exe"'
check "the engine, bottle, settings, state and manifest it made are gone" sh -c "[ ! -e '$AD/engine' ] && [ ! -e '$AD/bottle' ] && [ ! -e '$AD/settings.conf' ] && [ ! -e '$AD/state' ] && [ ! -e '$AD/install-manifest.json' ]"
check "no lock left" [ ! -e "$AD/.lock" ]

section "Stop waiting keeps the engine and the bottle"
g install steam >/dev/null 2>&1
check "stop-waiting" sh -c "'$G' stop-waiting | grep -q '@done'"
check "  stage=none, engine and bottle stay" [ "$(st stage)/$(st installed)" = none/yes ]
g uninstall >/dev/null 2>&1

section "Use existing game files (other Wine apps' installs)"
# GW2 on Mac 0.1's own bottle (a Steam install with arcdps, my own addon and the game's settings;
# DXMT's caches in its cache folder), CrossOver (a Steam install, with my own addon, another
# program's d3d11.dll, another addon and the game's settings), Whisky and a Sikarugir wrapper
# (ArenaNet installs), a broken one (Gw2.dat too small). Gw2.dat is sparse.
O1="$H/Library/Application Support/GW2 on Mac"
O1C="$O1/bottle/drive_c"
O1G="$O1C/Program Files (x86)/Steam/steamapps/common/Guild Wars 2"
O1S="$O1C/users/$BUSER/AppData/Roaming/Guild Wars 2"
O1X="$H/Library/Caches/GW2 on Mac/dxmt/Gw2-64.exe"
mkdir -p "$O1G/addons/arcdps" "$O1S" "$O1X"
echo "stand-in game" >"$O1G/Gw2-64.exe" && mkfile -n 1100m "$O1G/Gw2.dat"
cp "$SANDBOX/pe/arcdps.dll" "$O1G/d3d11.dll" && echo "[session]" >"$O1G/addons/arcdps/arcdps.ini"
cp "$COMP/ui-scale/version.dll" "$O1G/version.dll" && echo "scale=1.5" >"$O1G/gw2-ui-scale.ini"
printf '"AppState"\n{\n\t"appid"\t\t"1284210"\n\t"installdir"\t\t"Guild Wars 2"\n\t"StateFlags"\t\t"4"\n}\n' >"$O1C/Program Files (x86)/Steam/steamapps/appmanifest_1284210.acf"
echo "stand-in steam" >"$O1C/Program Files (x86)/Steam/steam.exe"
echo "0.1 local.dat" >"$O1S/Local.dat" && echo "<GSA_SDK 0.1/>" >"$O1S/GFXSettings.Gw2-64.exe.xml"
echo "shaders" >"$O1X/shaders.bin"
# a checksum of every file of 0.1's folders, by content
o1sum() { (cd "$H/Library" && find "Application Support/GW2 on Mac" "Caches/GW2 on Mac" -type f -print0 | sort -z | xargs -0 shasum -a 256) | shasum -a 256; }
O1SUM=$(o1sum)
CX="$H/Library/Application Support/CrossOver/Bottles/Steam GW2/drive_c"
CXG="$CX/Program Files (x86)/Steam/steamapps/common/Guild Wars 2"
CXS="$CX/users/crossover/AppData/Roaming/Guild Wars 2"
mkdir -p "$CXG/bin64" "$CXS"
echo "stand-in game" >"$CXG/Gw2-64.exe" && mkfile -n 2g "$CXG/Gw2.dat" && echo "bin" >"$CXG/bin64/CoherentUI64.dll"
cp "$COMP/ui-scale/version.dll" "$CXG/version.dll" && echo "scale=1.75" >"$CXG/gw2-ui-scale.ini" && echo "arcdps" >"$CXG/d3d11.dll"
cp "$SANDBOX/pe/nexus.dll" "$CXG/dxgi.dll"
printf '"AppState"\n{\n\t"appid"\t\t"1284210"\n\t"installdir"\t\t"Guild Wars 2"\n\t"StateFlags"\t\t"4"\n}\n' >"$CX/Program Files (x86)/Steam/steamapps/appmanifest_1284210.acf"
echo "cx local.dat" >"$CXS/Local.dat" && echo "<GSA_SDK cx/>" >"$CXS/GFXSettings.Gw2-64.exe.xml"
WB="$H/Library/Containers/com.isaacmarovitz.Whisky/Bottles/5F0C2A9E-0000-4000-8000-00000000AA01"
WHG="$WB/drive_c/Program Files/Guild Wars 2"
mkdir -p "$WHG" "$WB/drive_c/users/crossover/AppData/Roaming/Guild Wars 2"
echo "stand-in game" >"$WHG/Gw2-64.exe" && mkfile -n 1100m "$WHG/Gw2.dat"
echo "wh local.dat" >"$WB/drive_c/users/crossover/AppData/Roaming/Guild Wars 2/Local.dat"
plutil -create xml1 "$WB/Metadata.plist" && plutil -insert name -string "GW2 Whisky" "$WB/Metadata.plist"
WRAP="$H/Applications/Sikarugir/Guild Wars 2.app"
WRC="$WRAP/Contents/SharedSupport/prefix/drive_c"
WRS="$WRC/users/crossover/AppData/Roaming/Guild Wars 2"
mkdir -p "$WRC/Program Files/Guild Wars 2" "$WRS"
echo "stand-in game" >"$WRC/Program Files/Guild Wars 2/Gw2-64.exe" && mkfile -n 2g "$WRC/Program Files/Guild Wars 2/Gw2.dat"
echo "wrapper local.dat" >"$WRS/Local.dat"
BR="$H/Library/Application Support/CrossOver/Bottles/Broken/drive_c/Program Files/Guild Wars 2"
mkdir -p "$BR" && echo "stand-in game" >"$BR/Gw2-64.exe" && mkfile -n 10m "$BR/Gw2.dat"
# every file and folder of the sources (size, mtime, mode): they must never change
snap() { find "$O1" "$H/Library/Caches/GW2 on Mac" "$H/Library/Application Support/CrossOver" "$H/Library/Containers" "$H/Applications" -exec stat -f '%N %z %m %p' {} + | sort; }
snap >"$SANDBOX/sources-before.txt"
sources_unchanged() { snap | cmp -s - "$SANDBOX/sources-before.txt"; }
BS="$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2"

out=$(g scan)
line_of() { echo "$out" | awk -F'\t' -v s="$1" '$2 == s'; }
fields() { line_of "$1" | cut -f3,5,6 | tr '\t' ' '; }
check "scan finds 0.1's, CrossOver's, Whisky's and the wrapper's, not the broken one" [ "$(echo "$out" | grep -c '^game')" = 4 ]
check "  0.1's: GW2 on Mac 0.1, the Steam route, the same disk, settings" [ "$(fields 'GW2 on Mac 0.1')" = "steam yes yes" ]
check "  CrossOver's: the Steam route, the same disk, settings" [ "$(fields 'CrossOver · Steam GW2')" = "steam yes yes" ]
check "  its size: the folder's files (over 2 GB)" [ "$(line_of 'CrossOver · Steam GW2' | cut -f4)" -gt 2147483648 ]
check "  its path" [ "$(line_of 'CrossOver · Steam GW2' | cut -f7)" = "$CXG" ]
check "  Whisky's, by its bottle's name: ArenaNet" [ "$(fields 'Whisky · GW2 Whisky')" = "arenanet yes yes" ]
check "  the wrapper's: ArenaNet" [ "$(fields 'Wrapper · Guild Wars 2')" = "arenanet yes yes" ]
check "check-game: a folder without the game" sh -c "'$G' check-game '$SANDBOX/standin' | grep -q '^@error This folder has no Guild Wars 2'"
check "check-game: Gw2.dat under 1 GB is not the game" sh -c "'$G' check-game '$BR' | grep -q '^@error'"
check "check-game: the wrapper app itself finds the game in it" sh -c "'$G' check-game '$WRAP' | grep -q \"\$(printf 'game\tWrapper · Guild Wars 2\tarenanet')\""
check "check-game: a bottle's folder finds its Steam install" sh -c "'$G' check-game '$(dirname "$CX")' | grep -q \"\$(printf '\tsteam\t')\""

# a Guild Wars 2 that runs (in another app): its files may change, so nothing is copied
mkdir -p "$SANDBOX/elsewhere" && cp "$SANDBOX/sleeper" "$SANDBOX/elsewhere/Gw2-64.exe"
"$SANDBOX/elsewhere/Gw2-64.exe" 60 & ep=$!
sleep 0.3
out=$(g install import "$CXG" 2>&1) && rc=0 || rc=$?
check "install import refused while Guild Wars 2 runs elsewhere, nothing created" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error Guild Wars 2 is running" && [ ! -e "$AD/engine" ]'
out=$(g install import "$O1G" 2>&1) && rc=0 || rc=$?
check "  0.1's too" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error Guild Wars 2 is running" && [ ! -e "$AD/engine" ]'
kill $ep 2>/dev/null || true; wait $ep 2>/dev/null || true

out=$(GW2_ON_MAC_DRY_RUN=1 g install import "$CXG" 2>&1) && rc=0 || rc=$?
check "dry-run install import: exits 0, would clone, creates nothing" eval '[ "$rc" = 0 ] && has <(echo "$out") "\[dry-run\] clone" && [ ! -e "$AD" ]'

: >"$STANDIN_LOG"
out=$(g install import "$CXG" 2>&1) && rc=0 || rc=$?
GDI="$STEAM/steamapps/common/Guild Wars 2"
check "install import (CrossOver's Steam install) exits 0" [ "$rc" = 0 ]
check "  the phases 1-5 (engine, bottle, Steam, the files, finishing)" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 @phase 4 @phase 5 " ]
check "  cloned: the same disk, no extra space" has <(echo "$out") "Cloning the game's files"
check "  route=steam origin=import stage=finished game=yes" [ "$(st route) $(st origin) $(st stage) $(st game)" = "steam import finished yes" ]
check "  the game's files in the bottle's Steam library" eval '[ -f "$GDI/Gw2-64.exe" ] && [ "$(stat -f %z "$GDI/Gw2.dat")" = 2147483648 ] && has "$GDI/bin64/CoherentUI64.dll" bin'
check "  Steam's record of them, as it was" same "$CX/Program Files (x86)/Steam/steamapps/appmanifest_1284210.acf" "$STEAM/steamapps/appmanifest_1284210.acf"
check "  Steam installed, not started for an install" eval '[ "$(st steam)" = yes ] && ! grep -q "steam://install" "$STANDIN_LOG"'
check "  our own addon left out (version.dll, gw2-ui-scale.ini)" eval '[ ! -e "$GDI/version.dll" ] && [ ! -e "$GDI/gw2-ui-scale.ini" ]'
check "  another program's d3d11.dll left out, and the summary says so" eval '[ ! -e "$GDI/d3d11.dll" ] && has <(echo "$out") "^@done .*Another program.s d3d11.dll stayed behind\."'
check "  another addon (not arcdps) came along, and the summary names it" eval 'same "$CXG/dxgi.dll" "$GDI/dxgi.dll" && has <(echo "$out") "^@done .*Addons that came along: dxgi.dll"'
check "  the game's settings in the bottle" eval 'same "$CXS/Local.dat" "$BS/Local.dat" && same "$CXS/GFXSettings.Gw2-64.exe.xml" "$BS/GFXSettings.Gw2-64.exe.xml"'
check "  the summary: cloned, with the settings" has <(echo "$out") "^@done Guild Wars 2 is ready: its files were cloned from CrossOver · Steam GW2 (no extra space), with your game settings"
check "  the source is unchanged" sources_unchanged
c=$(play_cmd); check "  Play: Steam (no login in this bottle yet: its window)" eval '[[ "$c" == *"steam.exe -applaunch 1284210"* && "$c" != *-silent* ]]'
check "  uninstall" sh -c "'$G' uninstall | grep -q '@done'"
check "  the source is still unchanged" sources_unchanged

# GW2 on Mac 0.1's: arcdps stays behind (addons aren't cleared for this engine yet), DXMT's caches too
out=$(g install import "$O1G" 2>&1) && rc=0 || rc=$?
check "install import (GW2 on Mac 0.1's Steam install) exits 0, cloned" eval '[ "$rc" = 0 ] && has <(echo "$out") "Cloning the game" && [ "$(st route) $(st game)" = "steam yes" ]'
check "  arcdps, version.dll and gw2-ui-scale.ini left out; arcdps's settings came along" eval '[ ! -e "$GDI/d3d11.dll" ] && [ ! -e "$GDI/version.dll" ] && [ ! -e "$GDI/gw2-ui-scale.ini" ] && has "$GDI/addons/arcdps/arcdps.ini" session'
check "  the summary names what stayed behind" has <(echo "$out") "^@done Guild Wars 2 is ready: its files were cloned from GW2 on Mac 0.1 (no extra space), with your game settings\..* The larger interface's version.dll stayed behind: this app has its own\. arcdps stayed behind\. Turn it on in Settings once it is cleared for this engine\. Steam may"
check "  the game's settings in the bottle" eval 'same "$O1S/Local.dat" "$BS/Local.dat" && same "$O1S/GFXSettings.Gw2-64.exe.xml" "$BS/GFXSettings.Gw2-64.exe.xml"'
check "  no DXMT cache came along" eval '[ -z "$(find "$CACHE" -type f -path "*dxmt*" 2>/dev/null)" ]'
check "  0.1's folders: the same checksum" [ "$(o1sum)" = "$O1SUM" ]
g uninstall >/dev/null 2>&1

# into an earlier run's bottle, whose own settings go to a backup folder
g install steam >/dev/null 2>&1; g stop-waiting >/dev/null
mkdir -p "$BS" && echo "the bottle's own" >"$BS/Local.dat"
backup_kept() { local f; for f in "$BS"/"$APP_FOLDER backup "*/Local.dat; do has "$f" "the bottle's own" && return 0; done; return 1; }
: >"$STANDIN_LOG"
out=$(g install import "$WRAP" 2>&1) && rc=0 || rc=$?
check "install import of the wrapper's (ArenaNet) into the earlier bottle exits 0" [ "$rc" = 0 ]
check "  the phases 1-4 (engine, bottle, the files, finishing)" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 @phase 4 " ]
check "  route=arenanet origin=import game=yes, in Program Files" eval '[ "$(st route) $(st origin) $(st game)" = "arenanet import yes" ] && [ "$(st game_dir)" = "$BOTTLE/drive_c/Program Files/Guild Wars 2" ]'
check "  its settings in the bottle" same "$WRS/Local.dat" "$BS/Local.dat"
check "  the bottle's own kept in a backup folder" backup_kept
g play >/dev/null 2>&1; started
check "  Play starts the game's own launcher" has "$STANDIN_LOG" 'wine C:\\Program Files\\Guild Wars 2\\Gw2-64.exe'
g uninstall >/dev/null 2>&1

out=$(g install import "$WHG" --no-settings 2>&1) && rc=0 || rc=$?
check "install import --no-settings (Whisky's) exits 0" [ "$rc" = 0 ]
check "  no game settings brought" eval '[ ! -e "$BS/Local.dat" ] && ! has <(echo "$out") "with your game settings"'
g uninstall >/dev/null 2>&1

# another disk: a real copy, with progress (an attached disk image when possible; the copy is also
# forced on the same disk, GW2_ON_MAC_IMPORT_COPY)
VOL="$SANDBOX/othervol"
if hdiutil create -quiet -size 200m -type SPARSE -fs APFS -volname gw2om-test "$SANDBOX/other" >/dev/null 2>&1 &&
  mkdir -p "$VOL" && hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$VOL" "$SANDBOX/other.sparseimage" >/dev/null 2>&1; then
  trap 'hdiutil detach -quiet -force "$VOL" 2>/dev/null' EXIT
  OG="$VOL/Bottles/Other/drive_c/Program Files/Guild Wars 2"
  mkdir -p "$OG" && echo "stand-in game" >"$OG/Gw2-64.exe" && mkfile -n 1100m "$OG/Gw2.dat"
  check "check-game on another disk: not the same disk" eval '[ "$(g check-game "$OG" | grep "^game" | cut -f5)" = no ]'
  out=$(g install import "$OG" 2>&1) && rc=0 || rc=$?
  check "install import from another disk exits 0: copied, with progress" eval '[ "$rc" = 0 ] && has <(echo "$out") "Copying the game" && has <(echo "$out") "^@progress Guild Wars 2 " && has <(echo "$out") "^@done .*copied from"'
  check "  the copy is complete" eval '[ "$(st game)" = yes ] && [ "$(stat -f %z "$BOTTLE/drive_c/Program Files/Guild Wars 2/Gw2.dat")" = "$(stat -f %z "$OG/Gw2.dat")" ]'
  g uninstall >/dev/null 2>&1
  hdiutil detach -quiet -force "$VOL" >/dev/null 2>&1; trap - EXIT
else
  echo "  skip the disk image (hdiutil could not attach one); the forced copy below covers the copy"
fi
out=$(GW2_ON_MAC_IMPORT_COPY=1 g install import "$WHG" 2>&1) && rc=0 || rc=$?
check "install import, copy forced: exits 0, copied with progress" eval '[ "$rc" = 0 ] && has <(echo "$out") "Copying the game" && has <(echo "$out") "^@progress Guild Wars 2 "'
check "  the copy is complete" eval '[ "$(st game)" = yes ] && [ "$(stat -f %z "$BOTTLE/drive_c/Program Files/Guild Wars 2/Gw2.dat")" = 1153433600 ]'
g uninstall >/dev/null 2>&1
out=$(GW2_ON_MAC_IMPORT_COPY=1 GW2_ON_MAC_FREE_KB=3020000 g install import "$CXG" 2>&1) && rc=0 || rc=$?
check "a copy without the free space is refused" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error Not enough free disk space to copy the game"'
check "  and leaves nothing behind" eval '[ ! -e "$AD/engine" ] && [ ! -e "$AD/bottle" ] && [ ! -e "$AD/state" ] && [ ! -e "$AD/.lock" ]'
check "the sources never changed" sources_unchanged
check "0.1's folders: still the same checksum" [ "$(o1sum)" = "$O1SUM" ]

section "A development build's switches (dev-switches.conf)"
# Two copies of the app's Resources, each entry a link to the app's, but gw2om.sh (a copy: its
# folder is what it reads as the app's) and app.properties: DEVR's says channel=dev, a development
# build; RELR's has no channel line, a release. A root of their own: DROOT for a development
# build's fresh install, RROOT for a release's install, which the development build then updates.
res_copy() { # <dir> [<channel line>]
  local f
  mkdir -p "$1"
  for f in "$APP/Contents/Resources"/*; do ln -s "$f" "$1/${f##*/}"; done
  rm -f "$1/gw2om.sh" "$1/app.properties"
  cp "$APP/Contents/Resources/gw2om.sh" "$1/gw2om.sh"
  { grep -v '^channel=' "$APP/Contents/Resources/app.properties"; [ -z "${2:-}" ] || echo "$2"; } >"$1/app.properties"
}
DEVR="$SANDBOX/res-dev" RELR="$SANDBOX/res-release" DROOT="$SANDBOX/devroot" RROOT="$SANDBOX/relroot"
res_copy "$DEVR" channel=dev
res_copy "$RELR"
dg() { GW2OM="$DEVR/gw2om.sh" GW2_ON_MAC_ROOT="$DROOT" GW2_ON_MAC_DEV_SWITCHES='' "$G" "$@"; }
rg() { GW2OM="$RELR/gw2om.sh" GW2_ON_MAC_ROOT="$RROOT" GW2_ON_MAC_DEV_SWITCHES='' "$G" "$@"; }
dgr() { GW2OM="$DEVR/gw2om.sh" GW2_ON_MAC_ROOT="$RROOT" GW2_ON_MAC_DEV_SWITCHES='' "$G" "$@"; }
DAD="$DROOT/home/Library/Application Support/$APP_FOLDER" DLOGS="$DROOT/home/Library/Logs/$APP_FOLDER"
RAD="$RROOT/home/Library/Application Support/$APP_FOLDER"
DEVF="$DAD/dev-switches.conf" RDEVF="$RAD/dev-switches.conf"
# The table's rows, "<piece> <NAME=value>", and its version, read from gw2om.sh
DEVTABLE=$(sed -n '/^DEV_SWITCHES="$/,/^"$/p' "$APP/Contents/Resources/gw2om.sh" | awk 'NF > 4 { print $2, $5 }')
DEVVER=$(sed -n '/^DEV_SWITCHES="$/,/^"$/p' "$APP/Contents/Resources/gw2om.sh" | awk 'NF > 4 && $1 > v { v = $1 } END { print v + 0 }')
table_pieces() { local p; [ "$DEVVER" -ge 1 ] || return 1; for p in wine macdrv win32u fex fexany dxmt; do printf '%s\n' "$DEVTABLE" | grep -q "^$p " || return 1; done; }
check "the table has switches of each piece" table_pieces
# The components' records, narrowed: my ntdll.so names WINE_HEAT_SPIN, my winemac.so
# WINE_MACDRV_VIEW of the Mac driver's four, my FEX FEX_INITIALCODEBUFFERMB of its two (the staged
# VERSIONs back at the end). My DXMT fork has no record: the names in its DLLs, read here with grep
DEVKEEP="$SANDBOX/dev-versions"
mkdir -p "$DEVKEEP"
dev_switches_line() { # <component> <names...>
  local k=$1
  shift
  [ -f "$COMP/$k/VERSION" ] || return 0
  [ -f "$DEVKEEP/$k" ] || cp "$COMP/$k/VERSION" "$DEVKEEP/$k"
  { grep -v '^switches:' "$DEVKEEP/$k"; echo "switches: $*"; } >"$COMP/$k/VERSION"
}
dev_switches_line ntdll WINE_HEAT_COUNT WINE_HEAT_EVPOOL WINE_HEAT_LOG WINE_HEAT_MSYNC_UNREG WINE_HEAT_SPIN WINE_HEAT_WAKE
dev_switches_line macdrv WINE_MACDRV_SURFACE WINE_MACDRV_VIEW
dev_switches_line fex FEX_INITIALCODEBUFFERMB
DXNAMES=$(find "$COMP/dxmt/aarch64-windows" -type f -name '*.dll' -exec grep -aoh 'DXMT_[A-Z0-9_]*' {} + 2>/dev/null | LC_ALL=C sort -u)
# dev_expect: the table's lines the game's rule should have with those records, in the table's order
dev_expect() {
  local piece e n
  printf '%s\n' "$DEVTABLE" | while read -r piece e; do
    n=${e%%=*}
    case "$piece" in
      wine) mine || continue ;;
      macdrv) drv && [ "$n" = WINE_MACDRV_VIEW ] || continue ;;
      win32u) continue ;;
      fex) fexb && [ "$n" = FEX_INITIALCODEBUFFERMB ] || continue ;;
      dxmt) printf '%s\n' "$DXNAMES" | grep -qx "$n" || continue ;;
    esac
    echo "$e"
  done
}
# game_tail, cef_tail: the end the game's rule and CefHost.exe's have for dev_expect's lines
game_tail() { dev_expect | sed 's/^/;env=/' | tr -d '\n'; }
cef_tail() { dev_expect | sed 's/=.*/=/; s/^/;env=/' | tr -d '\n'; }
rows_on() { # <settings.conf>: the rows of a development build on, once (dev_version=1)
  local k
  for k in dev_version=1 jobwakes=on eventpool=on fastlocks=on launcherframes=on warm=on metalfx=on rawmouse=on fex=mine; do
    grep -qx "$k" "$1" || return 1
  done
}
ends_with() { case "$1" in *"$2") return 0 ;; esac; return 1; }
# comments_ok <file>: each switch line under a comment that names its piece and its issue and says
# played or unplayed
comments_ok() {
  awk '/^[A-Z]/ { n++; if (prev !~ /^# .* \(.*\), (played|unplayed): /) bad = 1 } { prev = $0 } END { exit bad || !n }' "$1"
}
# no_dxmt_lines: none of the table's DXMT_* lines in the rules
no_dxmt_lines() {
  local piece e r
  r=$(dg rules)
  printf '%s\n' "$DEVTABLE" | while read -r piece e; do
    [ "$piece" != dxmt ] || ! printf '%s\n' "$r" | grep -q "env=${e%%=*}=" || exit 1
  done
}

: >"$STANDIN_LOG"
out=$(dg install steam 2>&1) && rc=0 || rc=$?
check "a development build's fresh install: dev-switches.conf, version= first, every switch of the table on, in its order" \
  eval '[ "$rc" = 0 ] && [ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(grep "^[A-Z]" "$DEVF" | grep -v "^version=")" = "$(printf "%s\n" "$DEVTABLE" | cut -d" " -f2)" ]'
check "  each under a comment that names its piece and its issue and says played or unplayed" comments_ok "$DEVF"
check "  the rows on, once: settings.conf at dev_version=1" rows_on "$DAD/settings.conf"
check "  and the install said both" eval 'echo "$out" | grep -q "^Development build: the switch rows on, once: jobwakes=on " && echo "$out" | grep -q "^dev-switches.conf: version $DEVVER, switched on: "'
if mine; then
  check "  Faster locks greyed while the file's WINE_HEAT_SPIN line sets it, set refused" \
    eval '[ "$(dg settings | sed -n "s/^fastlocks_state=//p")" = "off:Set in dev-switches.conf (WINE_HEAT_SPIN). Take its line out there to use this row." ] && ! dg set fastlocks off >/dev/null 2>&1'
  sed -i '' 's/^WINE_HEAT_SPIN=/#WINE_HEAT_SPIN=/' "$DEVF"
  check "  that line commented out: the row works again" eval '[ "$(dg settings | sed -n "s/^fastlocks_state=//p")" = ok ]'
  sed -i '' 's/^#WINE_HEAT_SPIN=/WINE_HEAT_SPIN=/' "$DEVF"
fi
if fexb; then
  check "  my FEX in the engine (fex=mine)" eval '[ "$(dg status | sed -n "s/^fex_file=//p")" = mine ]'
fi
check "the game's rule: the lines whose file has the switch, after the rows' entries; unset for CefHost.exe" \
  eval 'ends_with "$(dg rules | head -1)" "$(game_tail)" && ends_with "$(dg rules | sed -n 2p)" "$(cef_tail)"'
if mine; then
  check "  the rows' WINE_HEAT_SPIN first, then the file's" eval 'dg rules | head -1 | grep -q ";env=WINE_HEAT_SPIN=lock=20:game,event=30:game;.*;env=WINE_HEAT_SPIN=lock=20:game,event=30:game,sem=5:game"'
fi
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "  a dry run of Play prints that rule, and each line it leaves out with why" \
  eval 'echo "$out" | grep -qxF "[dry-run] rule $(dg rules | head -1)" && echo "$out" | grep -qxF "[dry-run] dev-switches.conf leaves out WINE_WIN32U_SETCURSOR=shm (my win32u.so isn'"'"'t in the engine)" && { ! drv || echo "$out" | grep -qxF "[dry-run] dev-switches.conf leaves out WINE_MACDRV_CLIP=changes (my winemac.so doesn'"'"'t have it)"; }'
check "  and doesn't write the file again" eval '! echo "$out" | grep -q "dev-switches.conf: version"'
check "status lists the lines in the rule, and those left out" \
  eval '[ "$(dg status | sed -n "s/^dev_switches=//p")" = "$(dev_expect | tr "\n" " " | sed "s/ \$//")" ] && dg status | sed -n "s/^dev_switches_out=//p" | grep -q "WINE_WIN32U_PEEK_YIELD=off (my win32u.so isn'"'"'t in the engine)"'
check "the install's start of Steam: session.env names the lines in the rule, install.log those left out" \
  eval '[ "$(sed -n "s/^DEV_SWITCHES=//p" "$DLOGS/session.env")" = "$(dev_expect | tr "\n" " " | sed "s/ \$//")" ] && grep -q "dev-switches.conf: left out WINE_WIN32U_SETCURSOR=shm (my win32u.so isn'"'"'t in the engine)" "$DLOGS/install.log"'
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\n' >"$DLOGS/Gw2-64_d3d11.log"
# (the report to a file first: a grep -q on its pipe would end it with a broken pipe, which
# pipefail counts as the check's failure)
GW2_ON_MAC_ROOT="$DROOT" "$APP/Contents/Resources/session-report.sh" >"$CHECKS/devreport.txt" 2>&1
check "  the session report's header prints them" \
  eval 'grep -qxF "Dev switches that were on (dev-switches.conf): $(dev_expect | tr "\n" " " | sed "s/ \$//")" "$CHECKS/devreport.txt"'
sed -i '' 's/^FEX_DYNAMICL1CACHE=/#FEX_DYNAMICL1CACHE=/' "$DEVF"
echo "MY_OWN_SWITCH=1" >>"$DEVF"
check "a line commented out is gone from the rule and status; a line I added is in, after the others" \
  eval '! dg rules | grep -q FEX_DYNAMICL1CACHE && ! dg status | grep "^dev_switches=" | grep -q FEX_DYNAMICL1CACHE && dg rules | head -1 | grep -q ";env=MY_OWN_SWITCH=1\$"'
dg set dxmt engine >/dev/null
check "  the engine's own DXMT: no DXMT_* line in the rule, each left out saying so" \
  eval 'no_dxmt_lines && dg status | sed -n "s/^dev_switches_out=//p" | grep -q "DXMT_PRESENT_QUEUE=pace (my DXMT fork isn'"'"'t in the engine)"'
dg set dxmt fork >/dev/null
# My DXMT fork's tree in the engine is what's read, not this app's build: it can be an earlier
# build while Steam runs with it. Its DLLs replaced by one without a name, then by one with only
# DXMT_PRESENT_QUEUE (the tree back after)
DTREE="$DAD/engine/lib/wine/dxgi/dxmt/aarch64-windows"
rm -rf "$SANDBOX/dtree.keep" && cp -Rp "$DTREE" "$SANDBOX/dtree.keep"
for f in "$DTREE"/*.dll; do echo "an earlier build" >"$f"; done
check "an earlier build of my DXMT fork in the engine: its DXMT_* lines out, saying so" \
  eval '! dg status | grep "^dev_switches=" | grep -q DXMT_ && dg status | sed -n "s/^dev_switches_out=//p" | grep -q "DXMT_PRESENT_QUEUE=pace (my DXMT fork doesn'"'"'t have it)"'
printf 'x\0DXMT_PRESENT_QUEUE\0' >"$DTREE/d3d11.dll"
check "  one that has DXMT_PRESENT_QUEUE: that line in, the others out" \
  eval 'dg status | grep "^dev_switches=" | grep -q DXMT_PRESENT_QUEUE=pace && dg status | sed -n "s/^dev_switches_out=//p" | grep -q "DXMT_PRESENTER_FREE=1 (my DXMT fork doesn'"'"'t have it)"'
rm -rf "$DTREE" && cp -Rp "$SANDBOX/dtree.keep" "$DTREE"
if mine; then
  # (a VERSION without a switches: line names nothing for a development build's lines)
  grep -v '^switches:' "$DEVKEEP/ntdll" >"$COMP/ntdll/VERSION"
  check "my ntdll.so's VERSION without a switches: line: WINE_HEAT_SPIN's line out, saying so" \
    eval 'dg status | sed -n "s/^dev_switches_out=//p" | grep -q "WINE_HEAT_SPIN=lock=20:game,event=30:game,sem=5:game (my ntdll.so doesn'"'"'t have it)"'
  dev_switches_line ntdll WINE_HEAT_COUNT WINE_HEAT_EVPOOL WINE_HEAT_LOG WINE_HEAT_MSYNC_UNREG WINE_HEAT_SPIN WINE_HEAT_WAKE
fi
cp "$DEVF" "$SANDBOX/devf.keep"
cp "$DAD/settings.conf" "$SANDBOX/devsettings.keep"
out=$(dg repair 2>&1)
check "a second start (Repair) changes neither file and adds nothing" \
  eval 'same "$DEVF" "$SANDBOX/devf.keep" && same "$DAD/settings.conf" "$SANDBOX/devsettings.keep" && ! echo "$out" | grep -q -e "switched on" -e "rows on"'
# An update: the file one version older (version=0 stands for it), with the commented-out line, my
# own line, and DXMT_COMPILE_DEMAND and its comment deleted (a switch newer than the file)
sed -i '' -e 's/^version=.*/version=0/' -e '/DXMT_COMPILE_DEMAND/d' -e '/compile service.s declared policy/d' "$DEVF"
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "Play with the file older than the table: it would write the file (dry run)" \
  eval 'echo "$out" | grep -qxF "[dry-run] write $DEVF" && echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: DXMT_COMPILE_DEMAND=1"'
dg repair >/dev/null 2>&1
check "  updated: the newer switch at the end, on, under its comment; the commented-out line and mine kept" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(tail -1 "$DEVF")" = DXMT_COMPILE_DEMAND=1 ] && tail -2 "$DEVF" | head -1 | grep -q "^# my DXMT fork " && grep -qx "#FEX_DYNAMICL1CACHE=0" "$DEVF" && ! grep -qx "FEX_DYNAMICL1CACHE=0" "$DEVF" && grep -qx MY_OWN_SWITCH=1 "$DEVF"'
dg set metalfx off >/dev/null
dg repair >/dev/null 2>&1
check "a row I turn off stays off through the next update" eval 'grep -qx metalfx=off "$DAD/settings.conf" && grep -qx dev_version=1 "$DAD/settings.conf"'

# A release: no file, its defaults; a file there anyway changes nothing
out=$(rg install steam 2>&1) && rc=0 || rc=$?
check "a release's install: no dev-switches.conf, the rows at their defaults, no dev_version" \
  eval '[ "$rc" = 0 ] && [ ! -e "$RDEVF" ] && grep -qx fastlocks=off "$RAD/settings.conf" && grep -qx launcherframes=off "$RAD/settings.conf" && grep -qx fex=engine "$RAD/settings.conf" && ! grep -q "^dev_version=" "$RAD/settings.conf"'
rules_before=$(rg rules)
cp "$DEVF" "$RDEVF"
check "  dev-switches.conf there by hand: the rules, status and a dry run of Play don't read it" \
  eval '[ "$(rg rules)" = "$rules_before" ] && [ -z "$(rg status | sed -n "s/^dev_switches=//p")" ] && ! GW2_ON_MAC_DRY_RUN=1 rg play 2>&1 | grep -q -e MY_OWN_SWITCH -e "dev-switches.conf"'
rm -f "$RDEVF"
# The release's install, rows off and no file, updated by a development build
rg set rawmouse off >/dev/null
out=$(dgr repair 2>&1)
check "a development build over it: the rows on once (raw mouse-look too), the file written" \
  eval 'rows_on "$RAD/settings.conf" && [ "$(head -1 "$RDEVF")" = "version=$DEVVER" ] && echo "$out" | grep -q "^Development build: the switch rows on, once: "'
cp "$RDEVF" "$SANDBOX/rdevf.keep"
cp "$RAD/settings.conf" "$SANDBOX/rsettings.keep"
out=$(dgr repair 2>&1)
check "  a second start changes nothing" eval 'same "$RDEVF" "$SANDBOX/rdevf.keep" && same "$RAD/settings.conf" "$SANDBOX/rsettings.keep" && ! echo "$out" | grep -q -e "switched on" -e "rows on"'
dgr set rawmouse off >/dev/null
dgr repair >/dev/null 2>&1
check "  raw mouse-look off afterwards stays off" eval 'grep -qx rawmouse=off "$RAD/settings.conf"'
mkdir -p "$SANDBOX/relzip"
zip=$(GW2_ON_MAC_ROOT="$RROOT" "$RELR/collect-logs.sh" "$SANDBOX/relzip" 2>/dev/null | tail -1)
unzip -l "$zip" >"$SANDBOX/relzip.txt" 2>&1
check "a release's Collect Logs leaves out the dev-switches.conf a development build left" \
  eval '[ -f "$RDEVF" ] && [ -f "$zip" ] && grep -q settings.conf "$SANDBOX/relzip.txt" && ! grep -q dev-switches.conf "$SANDBOX/relzip.txt"'
for k in ntdll macdrv fex; do [ ! -f "$DEVKEEP/$k" ] || cp "$DEVKEEP/$k" "$COMP/$k/VERSION"; done
rm -rf "$DROOT" "$RROOT" "$DEVR" "$RELR"

echo
echo "$pass passed, $fail failed"
end_sandbox_processes
if [ "$fail" != 0 ]; then
  first=$(grep -m1 '^[0-9]* FAIL ' "$CHECKS/checks.txt")
  { echo "First failed check: ${first#* FAIL }"; echo
    echo "The last 40 lines of its commands' output (checks/${first%% *}.txt; its state files in checks/${first%% *}.state):"; echo
    echo '```'; tail -n 40 "$CHECKS/${first%% *}.txt" 2>/dev/null; echo '```'; } >"$CHECKS/summary.md"
  cp -R "$CHECKS" "$FAILED"
  echo "The checks' files: $FAILED"
fi
[ -n "${KEEP:-}" ] || rm -rf "$SANDBOX"
[ "$fail" = 0 ]
