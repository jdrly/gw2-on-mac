#!/bin/bash
# End-to-end test of the backend (Resources/gw2om.sh of a built app) in a sandbox, without the real
# Wine and without touching anything outside the sandbox: GW2_ON_MAC_ROOT puts every path the app
# uses under $SANDBOX, and the engine is a stand-in archive whose bin/wine only pretends (it makes
# a bottle's files for wineboot, "installs" Steam for SteamSetup.exe /S and logs every start with
# its environment). Steam's and ArenaNet's downloads of the game are played by this script
# (Steam's appmanifest, the game folder). Processes for the busy checks are copies of /bin/sleep
# at the engine's paths. The ArenaNet installer is a clone of a file signed by ArenaNet (by
# default the game's own Gw2-64.exe from the development workspace's bottle, only read; without
# one, those checks are skipped).
#
#   scripts/test-sandbox.sh [path/to/GW2 on Mac.app]
#
# Env: SANDBOX (default work/app-sandbox/test in this repository, removed first), KEEP=1 (leave it
#      for a look), SIGNED_PE (an x86_64 PE signed by ArenaNet; default the game's Gw2-64.exe in
#      $GW2_ON_MAC_WORKSPACE/work/bottles, the workspace defaulting to ../gw2-on-mac)
# Runs under macOS's /bin/bash 3.2.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="${GW2_ON_MAC_WORKSPACE:-$ROOT/../gw2-on-mac}"
APP="$(cd "${1:-dist/GW2 on Mac.app}" && pwd)"
G="$APP/Contents/Resources/gw2om.sh"
[ -f "$G" ] || { echo "no $G; run ./build.sh" >&2; exit 1; }
SANDBOX="${SANDBOX:-$ROOT/work/app-sandbox/test}"
case "$SANDBOX" in "$ROOT"/work/app-sandbox/*) ;; *) echo "SANDBOX must be under work/app-sandbox/" >&2; exit 1 ;; esac
SIGNED_PE="${SIGNED_PE:-$WS/work/bottles/gw2/drive_c/Program Files (x86)/Steam/steamapps/common/Guild Wars 2/Gw2-64.exe}"
# the stand-in processes (sleepers) and watchers of an earlier run of this sandbox, and of this one
# at its end
end_sandbox_processes() { [ ! -d "$SANDBOX" ] || pkill -f "^$(cd "$SANDBOX" && pwd -P)/" 2>/dev/null || true; pkill -f "^/bin/bash $G watch-session" 2>/dev/null || true; }
end_sandbox_processes
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
SANDBOX="$(cd "$SANDBOX" && pwd -P)"
H="$SANDBOX/home"
AD="$H/Library/Application Support/GW2 on Mac"
LOGS="$H/Library/Logs/GW2 on Mac"
CACHE="$H/Library/Caches/GW2 on Mac"
ENG="$AD/engine"
BOTTLE="$AD/bottle"
STEAM="$BOTTLE/drive_c/Program Files (x86)/Steam"
DXMT_CACHE="$CACHE/dxmt/Gw2-64.exe"
STANDIN_LOG="$SANDBOX/standin.log"
COMP="$APP/Contents/Resources/components"
mkdir -p "$H" "$SANDBOX/usertmp"
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
ok() { pass=$((pass + 1)); echo "  ok   $*"; }
bad() { fail=$((fail + 1)); echo "  FAIL $*"; }
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
GW2_MAC='Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\Mac Driver'
ALL_MAC='Software\\\\Wine\\\\Mac Driver'
same() { cmp -s "$1" "$2"; }
# the session's file, and waits (up to 10 s) for its watcher to reach a stage or end
sess() { sed -n "s/^$1=//p" "$AD/session" 2>/dev/null; }
wait_stage() { local i=0; while [ "$(sess stage)" != "$1" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; [ "$(sess stage)" = "$1" ]; }
watcher_runs() { local p; p=$(sess watcher_pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
watch_done() { local i=0; while { watcher_runs || [ "$(sess stage)" != done ]; } && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; ! watcher_runs && [ "$(sess stage)" = done ]; }

# --- The stand-in engine: the real engine's layout, files that only pretend
section "Stand-in engine and downloads"
S="$SANDBOX/standin/wine"
mkdir -p "$S/bin" "$S/lib/wine/x86_64-unix" "$S/include" "$S/share/man"
for a in x86_64-windows i386-windows x86_64-unix; do
  mkdir -p "$S/lib/wine/dxgi/dxmt/$a"
  for f in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll d3d10.dll; do echo "engine's $f" >"$S/lib/wine/dxgi/dxmt/$a/$f"; done
done
rm -f "$S/lib/wine/dxgi/dxmt/x86_64-unix/"*.dll && echo "engine's winemetal.so" >"$S/lib/wine/dxgi/dxmt/x86_64-unix/winemetal.so"
for f in ntdll.so winemac.so win32u.so; do echo "engine's $f" >"$S/lib/wine/x86_64-unix/$f"; done
for a in x86_64-windows i386-windows; do mkdir -p "$S/lib/wine/$a" && echo "engine's $a winemac.drv" >"$S/lib/wine/$a/winemac.drv"; done
cp /usr/bin/true "$S/lib/wine/x86_64-unix/wine"
cat >"$S/bin/wineserver" <<'EOF'
#!/bin/bash
# stand-in wineserver: nothing runs, so -k and -w have nothing to do
echo "wineserver $*" >>"$STANDIN_LOG"
EOF
cat >"$S/bin/wine" <<'EOF'
#!/bin/bash
# stand-in wine: pretends, and logs each start with the environment the game would get
{ echo "wine $*"; env | grep -E '^(WINE|DXMT_|MTL_|ROSETTA_)' | grep -v '^WINE_COMPATDB' | sort | sed 's/^/  /'; } >>"$STANDIN_LOG"
case "${1:-}" in
  wineboot)
    mkdir -p "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/users/crossover"
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
chmod 755 "$S/bin/wine" "$S/bin/wineserver"
export STANDIN_LOG
( cd "$SANDBOX/standin" && tar -cJf ../engine.tar.xz wine )
echo "stand-in SteamSetup.exe" >"$SANDBOX/SteamSetup.exe"
export GW2_ON_MAC_ROOT="$SANDBOX"
export GW2_ON_MAC_ENGINE_URL="file://$SANDBOX/engine.tar.xz"
export GW2_ON_MAC_ENGINE_SHA256="$(shasum -a 256 "$SANDBOX/engine.tar.xz" | cut -d' ' -f1)"
export GW2_ON_MAC_ENGINE_SIZE="$(stat -f %z "$SANDBOX/engine.tar.xz")"
export GW2_ON_MAC_ENGINE_CHECKS=0
# (the stand-in engine's own winemac.drv, below)
export GW2_ON_MAC_WINEMAC_PE64_STOCK="$(echo "engine's x86_64-windows winemac.drv" | shasum -a 256 | cut -d' ' -f1)"
export GW2_ON_MAC_WINEMAC_PE32_STOCK="$(echo "engine's i386-windows winemac.drv" | shasum -a 256 | cut -d' ' -f1)"
# (stand-ins for an earlier version's files, see "An update of the app")
export GW2_ON_MAC_OLD_COMPONENTS="$SANDBOX/old-components" OLDC="$SANDBOX/old-components"
: >"$OLDC"
export GW2_ON_MAC_STEAMSETUP_URL="file://$SANDBOX/SteamSetup.exe"
unset GW2_ON_MAC_DRY_RUN GW2_ON_MAC_ALLOW_WINE GW2_ON_MAC_SIGNER
# the session's watcher (play starts it), with its times shortened: a 2 s grace, 2 s for Steam to
# quit, a look every 0.2 s (the 15 minutes for the game to appear only in the timeout check)
export GW2_ON_MAC_WATCH_GRACE=2 GW2_ON_MAC_WATCH_QUITWAIT=2 GW2_ON_MAC_WATCH_POLL=0.2 GW2_ON_MAC_WATCH_TIMEOUT=60
ok "stand-in engine ($GW2_ON_MAC_ENGINE_SIZE bytes) and SteamSetup.exe"

# --- Dry runs change nothing
section "Dry runs"
out=$(GW2_ON_MAC_DRY_RUN=1 g install steam 2>&1); rc=$?
check "dry-run install steam exits 0" [ "$rc" = 0 ]
check "dry-run install steam reaches phase 4" has <(echo "$out") "@phase 4"
check "dry-run prints the game's environment" has <(echo "$out") "WINE_HEAT_EVPOOL=1"
check "dry-run creates nothing" eval '[ ! -e "$AD" ] && [ ! -e "$CACHE" ]'
check "fresh status: not installed" [ "$(st installed)" = no ]
check "fresh status: no engine" [ "$(st engine_installed)" = no ]
check "fresh status: rosetta answered" [ -n "$(st rosetta)" ]
check "fresh status: disk_free is a number" [ "$(st disk_free)" -gt 0 ]

# --- Steam route
section "Install through Steam"
out=$(g install steam 2>&1) && rc=0 || rc=$?
check "install steam exits 0" [ "$rc" = 0 ]
check "the phases 1-4 in order" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 @phase 4 " ]
check "@progress lines for the engine" has <(echo "$out") "@progress Wine engine"
check "installed=yes" [ "$(st installed)" = yes ]
check "engine_installed=yes" [ "$(st engine_installed)" = yes ]
check "graphics=yes (DXMT and the Wine pieces in place)" [ "$(st graphics)" = yes ]
check "gamemode=yes" [ "$(st gamemode)" = yes ]
check "steam=yes" [ "$(st steam)" = yes ]
check "stage=waiting_game" [ "$(st stage)" = waiting_game ]
check "route=steam" [ "$(st route)" = steam ]
check "game=no yet" [ "$(st game)" = no ]
check "DXMT's d3d11.dll in the engine's dxmt tree" same "$COMP/dxmt/x86_64-windows/d3d11.dll" "$ENG/lib/wine/dxgi/dxmt/x86_64-windows/d3d11.dll"
check "DXMT's winemetal.so in the tree" same "$COMP/dxmt/x86_64-unix/winemetal.so" "$ENG/lib/wine/dxgi/dxmt/x86_64-unix/winemetal.so"
check "the engine's own d3d10.dll stays in the tree" has "$ENG/lib/wine/dxgi/dxmt/x86_64-windows/d3d10.dll" "engine's"
check "heat ntdll.so in, the engine's kept as .stock" eval 'same "$COMP/heat/ntdll.so" "$ENG/lib/wine/x86_64-unix/ntdll.so" && has "$ENG/lib/wine/x86_64-unix/ntdll.so.stock" "engine"'
check "wineserver in, the stand-in kept as .stock" eval 'same "$COMP/heat/wineserver" "$ENG/bin/wineserver" && [ -f "$ENG/bin/wineserver.stock" ]'
check "winemac.so and win32u.so in" eval 'same "$COMP/winemac/winemac.so" "$ENG/lib/wine/x86_64-unix/winemac.so" && same "$COMP/winemac/win32u.so" "$ENG/lib/wine/x86_64-unix/win32u.so"'
for a in x86_64-windows i386-windows; do
  check "the Mac driver's $a/winemac.drv in (goes with that winemac.so), the engine's kept as .stock" \
    eval 'same "$COMP/winemac/$a/winemac.drv" "$ENG/lib/wine/$a/winemac.drv" && has "$ENG/lib/wine/$a/winemac.drv.stock" "engine"'
done
check "the engine's SDK removed" eval '[ ! -e "$ENG/include" ] && [ ! -e "$ENG/share/man" ]'
check "RetinaMode=y in the bottle" reg 'Software\\\\Wine\\\\Mac Driver' RetinaMode y
check "Gw2-64.exe's Mac driver: RawMouseWhenCursorHidden=y (raw mouse-look on)" reg "$GW2_MAC" RawMouseWhenCursorHidden y
check "  RawMouseGameControllerScale=1 (mouse-look speed 1x)" reg "$GW2_MAC" RawMouseGameControllerScale 1
check "  no PhysicalKeyboard (the driver's game keys by keyboard position stay inert)" noreg "$GW2_MAC" PhysicalKeyboard
check "  none of them for every program (Wine's Mac Driver key)" eval 'noreg "$ALL_MAC" RawMouseWhenCursorHidden && noreg "$ALL_MAC" RawMouseGameControllerScale && noreg "$ALL_MAC" PhysicalKeyboard'
check "Game Mode bundle with LSSupportsGameMode" has "$AD/gamemode/GW2.app/Contents/Info.plist" LSSupportsGameMode
check "Game Mode bundle's ntdll.so link resolves" [ -f "$AD/gamemode/GW2.app/Contents/MacOS/ntdll.so" ]
check "Steam started with the install page" has "$STANDIN_LOG" 'wine C:\\Program Files (x86)\\Steam\\steam.exe steam://install/1284210'
check "  with the heat event pool" has "$STANDIN_LOG" "WINE_HEAT_EVPOOL=1"
check "  with shader warming by use" has "$STANDIN_LOG" "DXMT_WARM=all"
check "  with 3 cooler workers" has "$STANDIN_LOG" "WINE_HEAT_QOS=1=utility:3"
check "  with WINEDLLPATH (Game Mode)" has "$STANDIN_LOG" "WINEDLLPATH=$ENG/lib/wine"
check "  with x87sidecar off" has "$STANDIN_LOG" "ROSETTA_X87_PATH="
check "the Game Mode link in the sandbox's temp folder" sh -c "ls '$SANDBOX/usertmp/'winetemp-*/Gw2-64.exe >/dev/null 2>&1"
check "logs/session.env written" has "$LOGS/session.env" "SETTING_warm=on"
check "the manifest" has "$AD/install-manifest.json" '"route": "steam"'
check "install.log" has "$LOGS/install.log" "install steam"

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
check "defaults: warm on, coolworkers 3, fastlocks on, ncpu 8, uiscale off" \
  [ "$(sett warm)$(sett coolworkers)$(sett fastlocks)$(sett ncpu)$(sett uiscale)" = on3on8off ]
check "default: Steam in the background on" [ "$(sett steambg)" = on ]
check "default: Quit Steam when the game quits on" [ "$(sett quitsteam)" = on ]
check "set coolworkers 5" g set coolworkers 5
check "  WINE_HEAT_QOS=1=utility:5 in the environment" has <(g env) "WINE_HEAT_QOS=1=utility:5"
check "set coolworkers off: no WINE_HEAT_QOS" sh -c "'$G' set coolworkers off >/dev/null && ! '$G' env | grep -q WINE_HEAT_QOS"
check "set fastlocks off: no WINE_HEAT_SPIN" sh -c "'$G' set fastlocks off >/dev/null && ! '$G' env | grep -q WINE_HEAT_SPIN"
check "set warm off: no DXMT_WARM" sh -c "'$G' set warm off >/dev/null && ! '$G' env | grep -q DXMT_WARM"
check "set ncpu all: no WINENCPU" sh -c "'$G' set ncpu all >/dev/null && ! '$G' env | grep -q WINENCPU"
check "set ncpu 6: WINENCPU=6" sh -c "'$G' set ncpu 6 >/dev/null && '$G' env | grep -qx WINENCPU=6"
MAXC=$(sysctl -n hw.logicalcpu)
check "settings: cpus=$MAXC (the Mac's logical CPUs)" [ "$(sett cpus)" = "$MAXC" ]
check "set ncpu 2 (the fewest): WINENCPU=2" sh -c "'$G' set ncpu 2 >/dev/null && '$G' env | grep -qx WINENCPU=2"
check "set ncpu 7 (steps of 1)" sh -c "[ $MAXC -lt 7 ] || '$G' set ncpu 7 >/dev/null"
check "set ncpu $MAXC (every CPU, by number): WINENCPU=$MAXC" sh -c "'$G' set ncpu $MAXC >/dev/null && '$G' env | grep -qx WINENCPU=$MAXC"
check "ncpu 1 refused" sh -c "'$G' set ncpu 1 >/dev/null; [ \$? = 2 ]"
check "ncpu $((MAXC + 1)) (more than the Mac has) refused" sh -c "'$G' set ncpu $((MAXC + 1)) >/dev/null; [ \$? = 2 ]"
check "ncpu 8 again" g set ncpu 8
check "set fpscap 60: dxmt.conf caps at 60" sh -c "'$G' set fpscap 60 >/dev/null && grep -q 'd3d11.preferredMaxFrameRate = 60' '$AD/dxmt.conf'"
check "set fpscap off: no cap" sh -c "'$G' set fpscap off >/dev/null && ! grep -q preferredMaxFrameRate '$AD/dxmt.conf'"
check "set metalfx on: DXMT_SUBSAMPLE_METALFX=1" sh -c "'$G' set metalfx on >/dev/null && '$G' env | grep -qx DXMT_SUBSAMPLE_METALFX=1"
check "set hud on: WINE_HEAT_METAL_HUD=1, no MTL_HUD_ENABLED in Steam's environment" sh -c "'$G' set hud on >/dev/null && '$G' env | grep -qx WINE_HEAT_METAL_HUD=1 && ! '$G' env | grep -q MTL_HUD_ENABLED"
check "set hud off: no WINE_HEAT_METAL_HUD" sh -c "'$G' set hud off >/dev/null && ! '$G' env | grep -q WINE_HEAT_METAL_HUD"
check "set debug on: DXMT_LOG_LEVEL=debug and the heat counters" sh -c "'$G' set debug on >/dev/null && '$G' env | grep -qx DXMT_LOG_LEVEL=debug && '$G' env | grep -qx WINE_HEAT_COUNT=1"
g set retina off >/dev/null; check "set retina off: RetinaMode=n" reg 'Software\\\\Wine\\\\Mac Driver' RetinaMode n
g set retina on >/dev/null; check "set retina on: RetinaMode=y" reg 'Software\\\\Wine\\\\Mac Driver' RetinaMode y
check "  d3d11 addons (arcdps) load first for Gw2-64.exe" reg 'Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\DllOverrides' d3d11 native,builtin
check "  so do dxgi.dll addons" reg 'Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\DllOverrides' dxgi native,builtin
check "  the default order for every other program" noreg 'Software\\\\Wine\\\\DllOverrides' d3d11
check "set gamemode off: no WINEDLLPATH" sh -c "'$G' set gamemode off >/dev/null && ! '$G' env | grep -q WINEDLLPATH && [ \"\$('$G' status | sed -n 's/^gamemode=//p')\" = off ]"
g set gamemode on >/dev/null
check "settings: rawmouse=on, mousespeed=1 by default" [ "$(sett rawmouse)/$(sett mousespeed)" = on/1 ]
check "  no physkeys setting (refused, exit 2; not in the settings)" sh -c "'$G' set physkeys on >/dev/null; [ \$? = 2 ] && ! '$G' settings | grep -q '^physkeys='"
g set rawmouse off >/dev/null; check "set rawmouse off: RawMouseWhenCursorHidden=n" reg "$GW2_MAC" RawMouseWhenCursorHidden n
g set mousespeed 2.5 >/dev/null; check "set mousespeed 2.5: RawMouseGameControllerScale=2.5" reg "$GW2_MAC" RawMouseGameControllerScale 2.5
check "  one value each (not added twice)" [ "$(grep -c '^"RawMouseWhenCursorHidden"=' "$BOTTLE/user.reg")/$(grep -c '^"RawMouseGameControllerScale"=' "$BOTTLE/user.reg")" = 1/1 ]
check "mousespeed 4 refused (exit 2)" sh -c "'$G' set mousespeed 4 >/dev/null; [ \$? = 2 ]"
check "rawmouse maybe refused (exit 2)" sh -c "'$G' set rawmouse maybe >/dev/null; [ \$? = 2 ]"
check "  the registry keeps 2.5" reg "$GW2_MAC" RawMouseGameControllerScale 2.5
check "the mouse settings are not in the game's environment" sh -c "! '$G' env | grep -qiE 'physical|rawmouse|mousespeed'"
g set rawmouse on >/dev/null; g set mousespeed 1 >/dev/null
check "  back to on, 1, and still no PhysicalKeyboard" eval 'reg "$GW2_MAC" RawMouseWhenCursorHidden y && reg "$GW2_MAC" RawMouseGameControllerScale 1 && noreg "$GW2_MAC" PhysicalKeyboard'
# A Play holds the session's lock from before it starts Wine (and its watcher for the session): a
# setting saved meanwhile leaves user.reg alone, and a Play can't start while a registry write
# holds the lock (the same flock, one holder at a time)
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 30 & hp=$!
i=0; until "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock" || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
check "set rawmouse off while a Play holds the session's lock: saved" sh -c "'$G' set rawmouse off | grep -q '@done' && [ \"\$('$G' settings | sed -n 's/^rawmouse=//p')\" = off ]"
check "  but the registry is left alone" reg "$GW2_MAC" RawMouseWhenCursorHidden y
check "  and the lock is still the Play's" "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock"
kill $hp 2>/dev/null; wait $hp 2>/dev/null
check "  once it's free, a setting writes the registry and lets the lock go" sh -c "'$G' set mousespeed 1 >/dev/null && ! '$APP/Contents/Resources/helpers/sessionlock' held '$AD/.session.lock'"
check "  RawMouseWhenCursorHidden=n" reg "$GW2_MAC" RawMouseWhenCursorHidden n
g set rawmouse on >/dev/null
check "set launchopts -maploadinfo" g set launchopts "-maploadinfo"
check "launchopts with a ; refused" sh -c "! '$G' set launchopts '-x; rm -rf /' >/dev/null"
check "unknown value refused (exit 2)" sh -c "'$G' set fpscap 45 >/dev/null; [ \$? = 2 ]"
check "unknown key refused" sh -c "! '$G' set colour red >/dev/null"
check "settings.conf has every key" [ "$(grep -c '=' "$AD/settings.conf")" = 20 ]

section "The larger interface (addon)"
GD="$STEAM/steamapps/common/Guild Wars 2"
check "uiscale_state=off by default" [ "$(sett uiscale_state)" = off ]
check "set uiscale on" g set uiscale on
check "  version.dll in the game folder" same "$COMP/ui-scale/version.dll" "$GD/version.dll"
check "  the ini: scale 1.75, sans cronos, cinema 1" sh -c "grep -qx 'scale=1.75' '$GD/gw2-ui-scale.ini' && grep -qx 'sans=cronos' '$GD/gw2-ui-scale.ini' && grep -qx 'cinema=1' '$GD/gw2-ui-scale.ini'"
check "  the override for Gw2-64.exe" reg 'Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\DllOverrides' version native,builtin
check "  uiscale_state=on" [ "$(sett uiscale_state)" = on ]
check "set uiscale_size 2.0 and sans off: the ini follows" sh -c "'$G' set uiscale_size 2.0 >/dev/null && '$G' set uiscale_sans off >/dev/null && grep -qx 'scale=2.0' '$GD/gw2-ui-scale.ini' && grep -qx 'sans=keep' '$GD/gw2-ui-scale.ini'"
echo "addon log" >"$GD/gw2-ui-scale.log"
check "set uiscale off: dll, ini and override gone, the log moved to Logs" sh -c "'$G' set uiscale off >/dev/null && [ ! -e '$GD/version.dll' ] && [ ! -e '$GD/gw2-ui-scale.ini' ] && [ ! -e '$GD/gw2-ui-scale.log' ] && ls '$LOGS'/gw2-ui-scale-*.log >/dev/null"
check "  the override removed" sh -c "! grep -q '^\"version\"=' '$BOTTLE/user.reg'"
check "  the d3d11 addon order stays" reg 'Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\DllOverrides' d3d11 native,builtin
echo "another addon" >"$GD/version.dll"
check "another version.dll: uiscale_state=foreign" [ "$(sett uiscale_state)" = foreign ]
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
check "  the d3d11 addon order is set for Gw2-64.exe" reg 'Software\\\\Wine\\\\AppDefaults\\\\Gw2-64.exe\\\\DllOverrides' d3d11 native,builtin
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
# DXMT's own d3d11.dll (a real PE, other exports) is not arcdps either
cp "$COMP/dxmt/x86_64-windows/d3d11.dll" "$GD/d3d11.dll"
check "a real d3d11.dll that isn't arcdps (DXMT's): foreign" [ "$(arcst)" = foreign ]
rm -f "$GD/d3d11.dll"
# the real arcdps, if the development workspace has a copy (only read)
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
check "the base address can be changed only in a sandbox" sh -c "grep -q '^\[ -z \"\$ROOT\" \] || ARCDPS_URL=' '$G'"
check "dry run: says what it would download, places nothing" sh -c "GW2_ON_MAC_DRY_RUN=1 '$G' set arcdps on | grep -q 'dry-run.*deltaconnected\|dry-run.*d3d11.dll.md5sum' && [ ! -e '$GD/d3d11.dll' ]"
# while a Play holds the session's lock, nothing changes in the game folder
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 30 & hp=$!
i=0; until "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock" || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
check "set arcdps on while a Play holds the session's lock: refused, nothing placed" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "session is starting" && [ ! -e "$GD/d3d11.dll" ]'
kill $hp 2>/dev/null; wait $hp 2>/dev/null
rm -rf "$GD/addons"

section "Play"
: >"$STANDIN_LOG"
out=$(g play 2>&1) && rc=0 || rc=$?
started
check "play exits 0" [ "$rc" = 0 ]
check "Steam -applaunch 1284210 with the launch options" has "$STANDIN_LOG" 'steam.exe -applaunch 1284210 -maploadinfo'
check "  with DXMT's config file" has "$STANDIN_LOG" "DXMT_CONFIG_FILE=$AD/dxmt.conf"
check "  with DXMT's caches in the app's cache folder (DXMT_CACHE_DIR)" grep -qxF "  DXMT_CACHE_DIR=$CACHE" "$STANDIN_LOG"
check "  env has DXMT_CACHE_DIR too" sh -c "'$G' env | grep -qxF 'DXMT_CACHE_DIR=$CACHE'"

section "Collect Logs (redaction and the leak check)"
mkdir -p "$STEAM/config" "$STEAM/logs" "$BOTTLE/drive_c/users/crossover/AppData/Roaming/Guild Wars 2"
printf '"users"\n{\n\t"76561198000000042"\n\t{\n\t\t"AccountName"\t\t"zz_acct_name"\n\t\t"PersonaName"\t\t"Zz Persona Q"\n\t}\n}\n' >"$STEAM/config/loginusers.vdf"
printf '[2026-11-04] AppID 1284210 update started : download 0/58900000000\nUser zz_acct_name (76561198000000042) [U:1:39734314] logged in, path %s\n' "$HOME/Library" >"$STEAM/logs/content_log.txt"
printf 'Crash\nName: ZZ-MACHINE\nIpAddr: 192.168.77.5\nLogin: zz.person@example.com\nException: c0000005\n' >"$BOTTLE/drive_c/users/crossover/AppData/Roaming/Guild Wars 2/ArenaNet.log"
printf 'started by %s from %s/Library, mail zz.person@example.com, token=abcDEF123secret\n' "$(id -un)" "$HOME" >>"$LOGS/wine.log"
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\ninfo:  STATS fps=60.0 ms=16.7/24.8 cb=1.1 rp=31.7(+0.0 merged) encode=0.23+1.03/10.3\ninfo:  HITCH frame=52 ms=120.0 dxmt(ms/calls): create=4.0/37 flush=3.5/1\n' >"$LOGS/Gw2-64_d3d11.log"
mkdir -p "$GD/addons/arcdps" && printf 'crash\nself: Zz Charname Q, zz_arc_acct.1234\n' >"$GD/addons/arcdps/arcdps_lastcrash.log"
echo "info: build" >"$GD/addons/arcdps/arcdps.log"; cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"
mkdir -p "$SANDBOX/zip"
zip=$("$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip" 2>"$SANDBOX/collect.err" | tail -1)
check "collect-logs makes a zip" [ -f "$zip" ]
rm -rf "$SANDBOX/unzipped" && mkdir -p "$SANDBOX/unzipped" && (cd "$SANDBOX/unzipped" && unzip -q "$zip")
Z="$SANDBOX/unzipped/$(basename "$zip" .zip)"
for f in logs/install.log logs/wine.log logs/Gw2-64_d3d11.log settings.conf install-manifest.json session-report.txt system-info.txt gpu-errors.txt game-logs/ArenaNet.log game-logs/steam/content_log.txt; do
  check "  has $f" [ -f "$Z/$f" ]
done
check "  the session report read DXMT's log" has "$Z/session-report.txt" "Frame rate: median 60.0"
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
rm -rf "$GD/addons" "$GD/d3d11.dll"

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
# (macOS kills copies of /bin/sleep: an ad-hoc signed program of our own keeps its signature)
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
check "set rawmouse off while it runs: saved" sh -c "'$G' set rawmouse off | grep -q 'after Steam has quit' && [ \"\$('$G' settings | sed -n 's/^rawmouse=//p')\" = off ]"
check "  but the registry waits (Wine reads it at the session's start)" reg "$GW2_MAC" RawMouseWhenCursorHidden y
check "set arcdps on while it runs: refused, nothing placed" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "Quit Guild Wars 2 and Steam first" && [ ! -e "$STEAM/steamapps/common/Guild Wars 2/d3d11.dll" ]'
kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
mv "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe" "$SANDBOX/gw2-loader-copy"
cp "$SANDBOX/sleeper" "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe"
"$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe" 60 & gp=$!
sleep 0.3
check "busy=game with the Game Mode bundle's Gw2-64.exe running" [ "$(st busy)" = game ]
check "play brings it up instead of starting another" sh -c "'$G' play | grep -q 'already running'"
check "reset-shaders refused while the game runs" sh -c "! '$G' reset-shaders >/dev/null 2>&1"
kill $gp 2>/dev/null || true; wait $gp 2>/dev/null || true
mv -f "$SANDBOX/gw2-loader-copy" "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe"
check "busy=none again" [ "$(st busy)" = none ]

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
  ps -axo pid=,ppid=,command= | awk -v c="/bin/bash $G watch-session" '
    { x = $0; sub(/^ *[0-9]+ +[0-9]+ /, "", x) }
    index(x, c) == 1 { w[$1] = $2 }
    END { for (p in w) if (!(w[p] in w)) n++; print n + 0 }'
}
check "  one watcher runs" [ "$(watchers)" = 1 ]
check "  watch-session by hand: another watcher follows the session" sh -c "'$G' watch-session | grep -q '@done Another watcher follows this session'"
game_session
check "  Steam quits once" eval 'watch_done && [ "$(sess result)" = quit ] && [ "$(grep -c "steam.exe -shutdown" "$STANDIN_LOG")" = 1 ]'
check "watch-session by hand with no session: nothing to follow" sh -c "'$G' watch-session | grep -q '@done No session to follow'"

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
splay; steam_up
check "Play in the grace after Steam quit: joins (replay=1), its own Steam (started_steam=yes quit_steam=yes)" eval '[ "$(sess replay)/$(sess started_steam)/$(sess quit_steam)" = 1/yes/yes ] && wait_stage waiting_game'
game_session
check "  its game quits: that Steam quits" eval 'watch_done && [ "$(sess result)" = quit ] && ! steam_runs'

# Play near the end of the grace (a 4 s grace): the watcher waits for that Play's game instead of
# quitting
: >"$STANDIN_LOG"; GW2_ON_MAC_WATCH_GRACE=4 "$G" play >/dev/null 2>&1; started; watcher_up; steam_up
game_session
sleep 2.5; splay; sleep 3
check "Play in the grace: the watcher waits for the game again, past the grace, no -shutdown" eval '[ "$(sess stage)" = waiting_game ] && [ "$(sess replay)" = 1 ] && steam_runs && ! has "$STANDIN_LOG" "steam.exe -shutdown"'
game_session
check "  then that game quits: Steam quits" eval 'watch_done && [ "$(sess result)" = quit ] && ! steam_runs'

# Play in the grace, and its game starts within the grace: once it quits, Steam quits
: >"$STANDIN_LOG"; GW2_ON_MAC_WATCH_GRACE=4 "$G" play >/dev/null 2>&1; started; watcher_up; steam_up
game_session; splay
game_session
check "Play and its game within the grace: after that game, Steam quits" eval 'watch_done && [ "$(sess result)" = quit ] && [ "$(sess replay)" = 1 ] && ! steam_runs'

# two Plays at once: one watcher, the other joins
: >"$STANDIN_LOG"
"$G" play >/dev/null 2>&1 & p1=$!
"$G" play >/dev/null 2>&1 & p2=$!
wait $p1 $p2; started; watcher_up; steam_up
check "two Plays at once: one watcher, the other joined" eval '[ "$(watchers)" = 1 ] && watcher_runs && [ "$(sess replay)" = 1 ]'
game_session
check "  Steam quits once" eval 'watch_done && [ "$(sess result)" = quit ] && [ "$(grep -c "steam.exe -shutdown" "$STANDIN_LOG")" = 1 ]'

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
check "the session's lock held without an answer: Play refuses and starts nothing" eval '[ "$rc" != 0 ] && has "$SANDBOX/stuck.txt" "@error GW2 on Mac.s last session did not answer" && ! has "$STANDIN_LOG" "^wine "'
kill $hp 2>/dev/null; wait $hp 2>/dev/null

# the lock's helper: bundled and signed; without it, the game starts, with no watcher (Steam stays open)
LK="$APP/Contents/Resources/helpers/sessionlock"
check "helpers/sessionlock is bundled and signed" eval '[ -x "$LK" ] && codesign --verify "$LK" 2>/dev/null'
watch_done
g set rawmouse on >/dev/null   # (off since the Busy checks; back off below)
mv "$LK" "$SANDBOX/sessionlock.aside"
: >"$STANDIN_LOG"; wp=$(sess watcher_pid)
"$G" play >"$SANDBOX/nolock.txt" 2>&1; started
check "  without it: Play warns, starts the game, no watcher" eval 'has "$SANDBOX/nolock.txt" "^@warn .*session helper is missing" && has "$SANDBOX/nolock.txt" "^@done" && has "$STANDIN_LOG" "^wine " && [ "$(sess watcher_pid)" = "$wp" ] && [ "$(watchers)" = 0 ]'
# (that Play starts Wine without the lock, so registry writes can't be kept apart from it: they wait)
"$G" set rawmouse off >"$SANDBOX/nolock-set.txt" 2>&1
check "  a setting is saved, its registry write waits for the helper" eval 'has "$SANDBOX/nolock-set.txt" "^@done" && [ "$(sett rawmouse)" = off ] && reg "$GW2_MAC" RawMouseWhenCursorHidden y && has "$SANDBOX/nolock-set.txt" "registry settings wait for it"'
mv "$SANDBOX/sessionlock.aside" "$LK"
check "  with it back, the next write applies it" eval '"$G" set mousespeed 1 >/dev/null && reg "$GW2_MAC" RawMouseWhenCursorHidden n'

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
session_file done
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
mv "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe" "$SANDBOX/gw2-loader-copy"
cp "$SANDBOX/sleeper" "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe"
"$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe" 120 & gp=$!
sleep 0.3
check "Gw2-64.exe up, no DXMT log yet: starting_game, game=yes" eval '[ "$(ss stage)/$(ss game)" = starting_game/yes ]'
printf 'info:  Found config file: x\ninfo:  Using feature level D3D_FEATURE_LEVEL_11_1\n' >"$LOGS/Gw2-64_d3d11.log"
touch -t "$(date -r $((T0 - 600)) '+%Y%m%d%H%M.%S')" "$LOGS/Gw2-64_d3d11.log"
check "  a DXMT log from before the session doesn't count" [ "$(ss stage)" = starting_game ]
touch "$LOGS/Gw2-64_d3d11.log"
check "the device is there, no frame yet: loading" [ "$(ss stage)" = loading ]
echo 'info:  Present pacing: mode=vsync rate=60.0 refresh=60.00 cap=60 interval=1' >>"$LOGS/Gw2-64_d3d11.log"
check "the first present: playing" [ "$(ss stage)" = playing ]
check "  game_elapsed from the game process (the watcher hasn't seen it yet)" eval 'e=$(ss game_elapsed); [ -n "$e" ] && [ "$e" -le 5 ]'
GS=$(($(date +%s) - 72)) session_file playing
check "  game_elapsed from the watcher's game_started" eval 'e=$(ss game_elapsed); [ "$e" -ge 72 ] && [ "$e" -le 75 ]'
check "  quit_steam=yes from the watcher, closing=no while the game runs" eval '[ "$(ss quit_steam)/$(ss closing)" = yes/no ]'
kill $gp 2>/dev/null; wait $gp 2>/dev/null
mv -f "$SANDBOX/gw2-loader-copy" "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe"
session_file grace
check "the game quit, the watcher's grace: stage=none, closing=yes" eval '[ "$(ss stage)/$(ss closing)/$(ss game)" = none/yes/no ]'
check "  status: session=live while Steam runs" [ "$(st session)" = live ]
session_file closing_steam
check "  closing_steam: closing=yes" [ "$(ss closing)" = yes ]
QS=no session_file closing_steam
check "  quit_steam=no (Steam's window, or the setting off): closing=no" [ "$(ss closing)" = no ]
QS=no session_file grace
check "a restart's grace with Steam staying: stage=none, closing=no, but watching=yes" eval '[ "$(ss stage)/$(ss closing)/$(ss watching)" = none/no/yes ]'
cp "$SANDBOX/sleeper" "$SANDBOX/gw2-loader-tmp" && mv "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe" "$SANDBOX/gw2-loader-copy"
mv "$SANDBOX/gw2-loader-tmp" "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe"
"$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe" 120 & gp=$!
sleep 0.3
check "  the game back within the grace: playing again" eval '[ "$(ss stage)/$(ss game)" = playing/yes ]'
kill $gp 2>/dev/null; wait $gp 2>/dev/null
mv -f "$SANDBOX/gw2-loader-copy" "$AD/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe"
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
GFX="$BOTTLE/drive_c/users/crossover/AppData/Roaming/Guild Wars 2/GFXSettings.Gw2-64.exe.xml"
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
echo "something else" >"$ENG/lib/wine/dxgi/dxmt/x86_64-windows/d3d11.dll"
check "graphics=other after a change in the engine" [ "$(st graphics)" = other ]
out=$(g repair 2>&1) && rc=0 || rc=$?
check "repair exits 0" [ "$rc" = 0 ]
check "graphics=yes after repair" [ "$(st graphics)" = yes ]
check "  the mouse setting saved during the session is in the registry now" reg "$GW2_MAC" RawMouseWhenCursorHidden n
g set rawmouse on >/dev/null
echo "something else" >"$ENG/lib/wine/i386-windows/winemac.drv"
check "graphics=other with another i386 winemac.drv" [ "$(st graphics)" = other ]
g repair >/dev/null 2>&1
check "  repair puts the app's back" same "$COMP/winemac/i386-windows/winemac.drv" "$ENG/lib/wine/i386-windows/winemac.drv"
check "the game and the settings stay" [ "$(st game)/$(sett launchopts)" = yes/-maploadinfo ]

# An update of the app (0.1.0 to this one): the engine has 0.1.0's pieces (stand-ins, listed as an
# earlier version's in $OLDC: GW2_ON_MAC_OLD_COMPONENTS, a sandbox's addition to the app's table of
# 0.1.0's real hashes) and the Mac driver's PE sides as the engine's own; the next Play puts this
# version's in, without Repair, as one transaction under the session's lock
MF="$AD/install-manifest.json" U="$ENG/lib/wine/x86_64-unix" T="$ENG/lib/wine/dxgi/dxmt"
echo "0.1.0's winemac.so" >"$SANDBOX/winemac-0.1.0.so"
echo "0.1.0's i386 dxgi.dll" >"$SANDBOX/dxgi32-0.1.0.dll"
printf 'lib/wine/x86_64-unix/winemac.so %s\nlib/wine/dxgi/dxmt/i386-windows/dxgi.dll %s\n' \
  "$(shasum -a 256 "$SANDBOX/winemac-0.1.0.so" | cut -d' ' -f1)" "$(shasum -a 256 "$SANDBOX/dxgi32-0.1.0.dll" | cut -d' ' -f1)" >"$OLDC"
as_010() {   # the engine and the manifest as 0.1.0 left them (no record of the pieces)
  cp "$SANDBOX/winemac-0.1.0.so" "$U/winemac.so"; cp "$SANDBOX/dxgi32-0.1.0.dll" "$T/i386-windows/dxgi.dll"
  for a in x86_64-windows i386-windows; do cp "$ENG/lib/wine/$a/winemac.drv.stock" "$ENG/lib/wine/$a/winemac.drv"; done
  rm -f "$ENG/.gw2om-components"
  sed -i '' -e 's/"version": "[^"]*"/"version": "0.1.0"/' -e '/"winemac_pe64_sha256"/d' -e '/"winemac_pe32_sha256"/d' "$MF"
}
is_010() { same "$SANDBOX/winemac-0.1.0.so" "$U/winemac.so" && same "$SANDBOX/dxgi32-0.1.0.dll" "$T/i386-windows/dxgi.dll" && has "$ENG/lib/wine/i386-windows/winemac.drv" "engine's"; }
is_new() {   # every file of this version in the engine
  same "$COMP/winemac/winemac.so" "$U/winemac.so" && same "$COMP/winemac/x86_64-windows/winemac.drv" "$ENG/lib/wine/x86_64-windows/winemac.drv" &&
    same "$COMP/winemac/i386-windows/winemac.drv" "$ENG/lib/wine/i386-windows/winemac.drv" && same "$COMP/dxmt/i386-windows/dxgi.dll" "$T/i386-windows/dxgi.dll"
}
nolaunch() { ! grep -q '^wine ' "$STANDIN_LOG"; }
PAUSE="$SANDBOX/pause"
wait_at() { local i=0; until [ -e "$PAUSE.at" ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$PAUSE.at" ]; }
watch_done
as_010
check "after an update from 0.1.0: graphics=update (0.1.0's winemac.so and i386 dxgi.dll, the engine's own winemac.drv)" [ "$(st graphics)" = update ]
# damaged or someone else's files are never overwritten by the update: Repair
cp "$T/x86_64-windows/d3d11.dll" "$SANDBOX/d3d11.keep"; echo "damaged" >"$T/x86_64-windows/d3d11.dll"
check "  a damaged DXMT d3d11.dll (its VERSION as 0.1.0's): graphics=other" [ "$(st graphics)" = other ]
: >"$STANDIN_LOG"; out=$(g play 2>&1); started
check "    Play doesn't touch the engine and says Repair" eval 'echo "$out" | grep -q "Click Repair" && has "$T/x86_64-windows/d3d11.dll" damaged && is_010'
watch_done; cp "$SANDBOX/d3d11.keep" "$T/x86_64-windows/d3d11.dll"
echo "someone's d3d10core" >"$T/i386-windows/d3d10core.dll"
check "  another program's i386 d3d10core.dll (a sibling the update replaces): graphics=other" [ "$(st graphics)" = other ]
cp "$COMP/dxmt/i386-windows/d3d10core.dll" "$T/i386-windows/d3d10core.dll"
echo "someone's ntdll.so" >"$SANDBOX/ntdll.keep.x"; cp "$U/ntdll.so" "$SANDBOX/ntdll.keep"; cp "$SANDBOX/ntdll.keep.x" "$U/ntdll.so"
check "  an ntdll.so of someone else's: graphics=other" [ "$(st graphics)" = other ]
cp "$SANDBOX/ntdll.keep" "$U/ntdll.so"
check "  back to 0.1.0's: graphics=update" [ "$(st graphics)" = update ]
# two Plays: the first one classifies under the session's lock and pauses; the second can't start
# anything or change the engine meanwhile
touch "$PAUSE"; rm -f "$PAUSE.at"; : >"$STANDIN_LOG"
GW2_ON_MAC_TEST_PAUSE="$PAUSE" GW2_ON_MAC_TEST_PAUSE_AT=play-classified "$G" play >"$SANDBOX/playA.txt" 2>&1 & pa=$!
check "two Plays: the first one pauses after classifying, holding the session's lock" eval 'wait_at && "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock"'
out=$(g play 2>&1) && rc=0 || rc=$?
check "  the second one is refused, starts nothing and leaves the engine alone" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "^@error" && nolaunch && is_010'
rm -f "$PAUSE"; wait $pa; rc=$?; started
check "  the first one then updates the engine and starts the game" eval '[ "$rc" = 0 ] && has "$SANDBOX/playA.txt" "has new pieces for the engine" && is_new && [ "$(st graphics)" = yes ] && [ "$(grep -c "^wine " "$STANDIN_LOG")" = 1 ]'
check "  the engine's own winemac.drv kept as .stock" has "$ENG/lib/wine/i386-windows/winemac.drv.stock" "engine's"
check "  the manifest is this version's, with the Mac driver's PE sides" eval '[ "$(plutil -extract version raw -o - "$MF")" = "$(st version)" ] && [ "$(plutil -extract winemac_pe32_sha256 raw -o - "$MF")" = "$(shasum -a 256 "$COMP/winemac/i386-windows/winemac.drv" | cut -d" " -f1)" ]'
check "  the engine records the pieces it got; no journal left" eval 'grep -qx "$(shasum -a 256 "$COMP/winemac/winemac.so" | cut -d" " -f1) lib/wine/x86_64-unix/winemac.so" "$ENG/.gw2om-components" && [ ! -e "$ENG/.gw2om-update" ] && [ ! -e "$AD/.lock" ]'
watch_done
# a Play paused halfway through the replacement: the engine counts as an update under way, and a
# second Play neither starts the game on the half-replaced set nor touches it
inv() { ( eval "$(sed -n '/^component_list() {/,/^}/p' "$G")"; component_list ); }
check "the update's inventory: 18 files, the Mac driver's PE sides 15th and 16th, winemac.so 17th" eval '[ "$(inv | wc -l | tr -d " ")" = 18 ] && [ "$(inv | sed -n 15,17p | cut -f2 | tr "\n" " ")" = "lib/wine/x86_64-windows/winemac.drv lib/wine/i386-windows/winemac.drv lib/wine/x86_64-unix/winemac.so " ]'
as_010
touch "$PAUSE"; rm -f "$PAUSE.at"; : >"$STANDIN_LOG"
GW2_ON_MAC_TEST_PAUSE="$PAUSE" GW2_ON_MAC_TEST_PAUSE_AT=update-16 "$G" play >"$SANDBOX/playA.txt" 2>&1 & pa=$!
check "a Play paused after 16 of the update's 18 files (the new winemac.drv in, the old winemac.so still): graphics=update (its journal)" eval 'wait_at && [ -d "$ENG/.gw2om-update" ] && same "$COMP/winemac/i386-windows/winemac.drv" "$ENG/lib/wine/i386-windows/winemac.drv" && same "$SANDBOX/winemac-0.1.0.so" "$U/winemac.so" && [ "$(st graphics)" = update ]'
out=$(g play 2>&1) && rc=0 || rc=$?
check "  a second Play is refused (busy with the update) and starts nothing" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "busy putting its new pieces" && nolaunch'
rm -f "$PAUSE"; wait $pa; rc=$?; started
check "  the first one finishes and starts the game once" eval '[ "$rc" = 0 ] && is_new && [ "$(st graphics)" = yes ] && [ "$(grep -c "^wine " "$STANDIN_LOG")" = 1 ]'
watch_done
# a failure halfway: the engine's files back as they were, the game not started
as_010; : >"$STANDIN_LOG"
out=$(GW2_ON_MAC_UPDATE_FAIL_AFTER=16 "$G" play 2>&1) && rc=0 || rc=$?
check "an update failing after 16 files (between the Mac driver's pieces): Play fails and starts nothing" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "^@error test: the update fails" && nolaunch'
check "  the engine is 0.1.0's again (rolled back), no journal, no lock left: graphics=update" eval 'is_010 && [ ! -e "$ENG/.gw2om-update" ] && [ ! -e "$AD/.lock" ] && [ "$(st graphics)" = update ]'
# killed halfway (power, kill -9): the journal stays, nothing starts on the half-replaced set, and
# the next Play finishes the update
as_010; : >"$STANDIN_LOG"
GW2_ON_MAC_UPDATE_KILL_AFTER=16 "$G" play >"$SANDBOX/killed.txt" 2>&1; rc=$?
check "an update killed after 16 files (new winemac.drv, old winemac.so): the journal stays, graphics=update, nothing started" eval '[ "$rc" != 0 ] && [ -f "$ENG/.gw2om-update/committing" ] && same "$SANDBOX/winemac-0.1.0.so" "$U/winemac.so" && [ "$(st graphics)" = update ] && nolaunch'
out=$(g play 2>&1) && rc=0 || rc=$?; started
check "  the next Play takes over the lock it left, finishes the update and starts the game" eval '[ "$rc" = 0 ] && is_new && [ ! -e "$ENG/.gw2om-update" ] && [ "$(st graphics)" = yes ] && has "$LOGS/install.log" "finishing an interrupted update" && has "$STANDIN_LOG" "^wine "'
watch_done
# killed while backing up (a partial copy of winemac.so's backup, nothing committed), then the
# retry fails between the Mac driver's pieces: the rollback puts the intact originals back
as_010; : >"$STANDIN_LOG"
GW2_ON_MAC_UPDATE_KILL_IN_BACKUP=17 "$G" play >"$SANDBOX/killed.txt" 2>&1
check "an update killed while backing up winemac.so: a partial backup (.part), nothing committed, the engine untouched" eval '[ -f "$ENG/.gw2om-update/old/17.part" ] && [ ! -e "$ENG/.gw2om-update/old/17" ] && [ ! -e "$ENG/.gw2om-update/committing" ] && is_010 && nolaunch'
out=$(GW2_ON_MAC_UPDATE_FAIL_AFTER=16 "$G" play 2>&1) && rc=0 || rc=$?
check "  the retry backs it up again; failing after 16 files, it rolls back to the intact originals" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "test: the update fails" && is_010 && [ ! -e "$ENG/.gw2om-update" ] && nolaunch'
# a backup slot that isn't the untouched live file (before any commit) is never trusted
mkdir -p "$ENG/.gw2om-update/old" && head -c 5 "$U/winemac.so" >"$ENG/.gw2om-update/old/17"
out=$(GW2_ON_MAC_UPDATE_FAIL_AFTER=16 "$G" play 2>&1) && rc=0 || rc=$?
check "a truncated backup slot from before any commit is made again: the rollback is intact" eval '[ "$rc" != 0 ] && is_010 && [ ! -e "$ENG/.gw2om-update" ]'
out=$(g play 2>&1) && rc=0 || rc=$?; started
check "  a Play without a failure then updates the engine" eval '[ "$rc" = 0 ] && is_new && [ "$(st graphics)" = yes ]'
watch_done
# the install lock: one left by a process that is gone is taken over by exactly one contender (the
# claim, a kernel lock), and a live owner's lock is never removed by anyone else
( exit 0 ) & dp=$!; wait $dp
mkdir "$AD/.lock" && echo "$dp" >"$AD/.lock/pid"
touch "$PAUSE"; rm -f "$PAUSE.at"
GW2_ON_MAC_TEST_PAUSE="$PAUSE" GW2_ON_MAC_TEST_PAUSE_AT=lock-stale-checked "$G" set launchopts -contenderA >"$SANDBOX/contA.txt" 2>&1 & ca=$!
check "a lock left by a gone process: the first contender has the claim (paused after its check)" eval 'wait_at && "$APP/Contents/Resources/helpers/sessionlock" held "$LOGS/.lock-claim"'
out=$(GW2_ON_MAC_LOCK_WAIT=1 "$G" repair 2>&1) && rc=0 || rc=$?
check "  a second contender is refused meanwhile and leaves the lock alone" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "Another GW2 on Mac" && [ "$(cat "$AD/.lock/pid")" = "$dp" ]'
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
GW2_ON_MAC_TEST_PAUSE="$P1" GW2_ON_MAC_TEST_PAUSE_AT=locked "$G" set launchopts -ownerA >"$SANDBOX/ownA.txt" 2>&1 & oa=$!
wait_file "$P1.at"
GW2_ON_MAC_TEST_PAUSE="$P2" GW2_ON_MAC_TEST_PAUSE_AT=lock-owner-read "$G" set launchopts -contenderB >"$SANDBOX/contB.txt" 2>&1 & ob=$!
check "owner A holds the lock; contender B has read A's pid under the claim (paused)" eval 'wait_file "$P2.at" && [ "$(cat "$AD/.lock/pid")" = "$oa" ] && "$APP/Contents/Resources/helpers/sessionlock" held "$LOGS/.lock-claim"'
rm -f "$P1"; sleep 0.5
check "  A, done, waits for the claim to unlock: the lock is still A's" eval 'kill -0 $oa 2>/dev/null && [ "$(cat "$AD/.lock/pid")" = "$oa" ]'
out=$(GW2_ON_MAC_LOCK_WAIT=1 "$G" set launchopts -freshC 2>&1) && rc=0 || rc=$?
check "  a fresh acquisition (C) waits for the claim and is refused: the lock still A's, nothing of C's" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "Another GW2 on Mac" && [ "$(cat "$AD/.lock/pid")" = "$oa" ] && [ "$(sett launchopts)" != -freshC ]'
rm -f "$P2"; wait $ob; rb=$?; wait $oa; ra=$?
check "  B, resumed, finds A still there and is refused; A unlocks and ends: its setting, no lock left" eval '[ "$rb" != 0 ] && has "$SANDBOX/contB.txt" "Another GW2 on Mac" && [ "$ra" = 0 ] && [ "$(sett launchopts)" = -ownerA ] && [ ! -e "$AD/.lock" ]'
g set launchopts -maploadinfo >/dev/null
# a later version's update: what this version put in (its record) counts as an earlier version's
echo "this version's winemac.so, as a later version sees it" >"$SANDBOX/winemac-rec.so"
cp "$SANDBOX/winemac-rec.so" "$U/winemac.so"
check "a file the engine's record names (from an install of an earlier version): graphics=update" eval 'sed -i "" "s|^[0-9a-f]* lib/wine/x86_64-unix/winemac.so\$|$(shasum -a 256 "$SANDBOX/winemac-rec.so" | cut -d" " -f1) lib/wine/x86_64-unix/winemac.so|" "$ENG/.gw2om-components" && [ "$(st graphics)" = update ]'
cp "$COMP/winemac/winemac.so" "$U/winemac.so"
# an engine that already has this version's pieces under 0.1.0's manifest (Jan's): set up
sed -i '' -e 's/"version": "[^"]*"/"version": "0.1.0"/' "$MF"; rm -f "$ENG/.gw2om-components"
check "this version's pieces under 0.1.0's manifest, no record: graphics=yes" [ "$(st graphics)" = yes ]
out=$(g play 2>&1); started
check "  Play changes no piece and brings the manifest to this version" eval '! echo "$out" | grep -q "new pieces" && [ "$(plutil -extract version raw -o - "$MF")" = "$(st version)" ]'
watch_done
# a piece missing altogether: no game on an incomplete set
mv "$ENG/lib/wine/i386-windows/winemac.drv" "$SANDBOX/winemac32.keep"; : >"$STANDIN_LOG"
out=$(g play 2>&1) && rc=0 || rc=$?
check "a missing i386 winemac.drv: Play refuses (Repair) and starts nothing" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "missing GW2 on Mac.s lib/wine/i386-windows/winemac.drv" && nolaunch'
g repair >/dev/null 2>&1
check "  repair: graphics=yes" [ "$(st graphics)" = yes ]
echo "shader" >"$DXMT_CACHE/shaders_320.db"
check "reset-shaders empties DXMT's cache" sh -c "'$G' reset-shaders | grep -q '@done' && [ -d '$DXMT_CACHE' ] && [ ! -e '$DXMT_CACHE/shaders_320.db' ]"
check "  and leaves the per-user cache folder's dxmt/ alone" other_dxmt_kept
check "reinstall-engine" sh -c "'$G' reinstall-engine | grep -q '@done'"
check "  graphics=yes after it" [ "$(st graphics)" = yes ]
mkdir "$AD/.lock"
check "a second operation is refused while one runs (lock)" sh -c "'$G' repair 2>&1 | grep -q 'Another GW2 on Mac'"
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
check "the app's folder is gone (engine, bottle with the game, Game Mode, settings, the session)" [ ! -e "$AD" ]
check "  the session's watcher stopped" sh -c "! kill -0 $wp 2>/dev/null"
check "its caches are gone" eval '[ ! -e "$CACHE" ] && [ ! -e "$DXMT_CACHE" ]'
check "the per-user cache folder's dxmt/ stays (another setup's)" other_dxmt_kept
check "the Game Mode link is gone" sh -c "! ls '$SANDBOX/usertmp/'winetemp-*/Gw2-64.exe >/dev/null 2>&1"
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
# CrossOver (a Steam install, with our own addon, another addon and the game's settings), Whisky
# and a Sikarugir wrapper (ArenaNet installs), a broken one (Gw2.dat too small). Gw2.dat is sparse.
CX="$H/Library/Application Support/CrossOver/Bottles/Steam GW2/drive_c"
CXG="$CX/Program Files (x86)/Steam/steamapps/common/Guild Wars 2"
CXS="$CX/users/crossover/AppData/Roaming/Guild Wars 2"
mkdir -p "$CXG/bin64" "$CXS"
echo "stand-in game" >"$CXG/Gw2-64.exe" && mkfile -n 2g "$CXG/Gw2.dat" && echo "bin" >"$CXG/bin64/CoherentUI64.dll"
cp "$COMP/ui-scale/version.dll" "$CXG/version.dll" && echo "scale=1.75" >"$CXG/gw2-ui-scale.ini" && echo "arcdps" >"$CXG/d3d11.dll"
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
snap() { find "$H/Library/Application Support/CrossOver" "$H/Library/Containers" "$H/Applications" -exec stat -f '%N %z %m %p' {} + | sort; }
snap >"$SANDBOX/sources-before.txt"
sources_unchanged() { snap | cmp -s - "$SANDBOX/sources-before.txt"; }
BS="$BOTTLE/drive_c/users/crossover/AppData/Roaming/Guild Wars 2"

out=$(g scan)
line_of() { echo "$out" | awk -F'\t' -v s="$1" '$2 == s'; }
fields() { line_of "$1" | cut -f3,5,6 | tr '\t' ' '; }
check "scan finds CrossOver's, Whisky's and the wrapper's, not the broken one" [ "$(echo "$out" | grep -c '^game')" = 3 ]
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
check "  another addon came along, and the summary names it" eval 'has "$GDI/d3d11.dll" arcdps && has <(echo "$out") "^@done .*Addons that came along: d3d11.dll"'
check "  the game's settings in the bottle" eval 'same "$CXS/Local.dat" "$BS/Local.dat" && same "$CXS/GFXSettings.Gw2-64.exe.xml" "$BS/GFXSettings.Gw2-64.exe.xml"'
check "  the summary: cloned, with the settings" has <(echo "$out") "^@done Guild Wars 2 is ready: its files were cloned from CrossOver · Steam GW2 (no extra space), with your game settings"
check "  the source is unchanged" sources_unchanged
c=$(play_cmd); check "  Play: Steam (no login in this bottle yet: its window)" eval '[[ "$c" == *"steam.exe -applaunch 1284210"* && "$c" != *-silent* ]]'
check "  uninstall" sh -c "'$G' uninstall | grep -q '@done'"
check "  the source is still unchanged" sources_unchanged

# into an earlier run's bottle, whose own settings go to a backup folder
g install steam >/dev/null 2>&1; g stop-waiting >/dev/null
mkdir -p "$BS" && echo "the bottle's own" >"$BS/Local.dat"
backup_kept() { local f; for f in "$BS"/"GW2 on Mac backup "*/Local.dat; do has "$f" "the bottle's own" && return 0; done; return 1; }
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

echo
echo "$pass passed, $fail failed"
end_sandbox_processes
[ -n "${KEEP:-}" ] || rm -rf "$SANDBOX"
[ "$fail" = 0 ]
