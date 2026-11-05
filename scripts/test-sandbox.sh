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
reg() { grep -A3 "^\[$1\]" "$BOTTLE/user.reg" 2>/dev/null | grep -q "^\"$2\"=\"$3\""; }
same() { cmp -s "$1" "$2"; }
# the session's file, and waits (up to 10 s) for its watcher to reach a stage or end
sess() { sed -n "s/^$1=//p" "$AD/session" 2>/dev/null; }
wait_stage() { local i=0; while [ "$(sess stage)" != "$1" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; [ "$(sess stage)" = "$1" ]; }
watch_done() { local i=0; while { [ -d "$AD/.session.lock" ] || [ "$(sess stage)" != done ]; } && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; [ ! -d "$AD/.session.lock" ] && [ "$(sess stage)" = done ]; }

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
check "the engine's SDK removed" eval '[ ! -e "$ENG/include" ] && [ ! -e "$ENG/share/man" ]'
check "RetinaMode=y in the bottle" reg 'Software\\\\Wine\\\\Mac Driver' RetinaMode y
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
check "set gamemode off: no WINEDLLPATH" sh -c "'$G' set gamemode off >/dev/null && ! '$G' env | grep -q WINEDLLPATH && [ \"\$('$G' status | sed -n 's/^gamemode=//p')\" = off ]"
g set gamemode on >/dev/null
check "set launchopts -maploadinfo" g set launchopts "-maploadinfo"
check "launchopts with a ; refused" sh -c "! '$G' set launchopts '-x; rm -rf /' >/dev/null"
check "unknown value refused (exit 2)" sh -c "'$G' set fpscap 45 >/dev/null; [ \$? = 2 ]"
check "unknown key refused" sh -c "! '$G' set colour red >/dev/null"
check "settings.conf has every key" [ "$(grep -c '=' "$AD/settings.conf")" = 18 ]

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
echo "another addon" >"$GD/version.dll"
check "another version.dll: uiscale_state=foreign" [ "$(sett uiscale_state)" = foreign ]
g set uiscale on >/dev/null 2>&1 || true
check "  turning it on leaves the other dll alone" has "$GD/version.dll" "another addon"
g set uiscale off >/dev/null 2>&1 || true
check "  turning it off leaves it alone too" has "$GD/version.dll" "another addon"
rm -f "$GD/version.dll"

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
steam_up() { ( "$ENG/bin/steam.exe" 300 & echo $! >"$SP" ); sleep 0.2; }
steam_runs() { kill -0 "$(cat "$SP")" 2>/dev/null; }
steam_down() { kill "$(cat "$SP")" 2>/dev/null; rm -f "$SP"; sleep 0.2; }
game_up() { ( "$ENG/bin/Gw2-64.exe" 300 & echo $! >"$SANDBOX/game.pid" ); }
game_down() { kill "$(cat "$SANDBOX/game.pid")" 2>/dev/null; }
# a session: the game starts, runs, quits
game_session() { game_up; wait_stage playing && game_down && wait_stage grace; }
splay() { : >"$STANDIN_LOG"; g play >/dev/null 2>&1; started; }
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
check "a second Play keeps the session and its watcher" [ "$(sess watcher_pid)/$(sess started_steam)/$(sess quit_steam)" = "$wp/yes/yes" ]
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

# a Steam that ignores -shutdown: wineserver -k (a stand-in wineserver that ends it)
touch "$SANDBOX/steam.stubborn"
mv "$ENG/bin/wineserver" "$SANDBOX/wineserver.heat"
printf '#!/bin/bash\necho "wineserver $*" >>"$STANDIN_LOG"\n[ "$1" != -k ] || kill "$(cat "%s")" 2>/dev/null\nexit 0\n' "$SP" >"$ENG/bin/wineserver" && chmod 755 "$ENG/bin/wineserver"
splay; steam_up
game_session
check "Steam ignores -shutdown: wineserver -k for the bottle after the wait" eval 'watch_done && [ "$(sess result)" = killed ] && has "$STANDIN_LOG" "steam.exe -shutdown" && has "$STANDIN_LOG" "^wineserver -k" && ! steam_runs'
mv -f "$SANDBOX/wineserver.heat" "$ENG/bin/wineserver"
rm -f "$SANDBOX/steam.stubborn" "$ENG/bin/steam.exe" "$ENG/bin/Gw2-64.exe"
check "busy=none after the sessions" [ "$(st busy)" = none ]

section "Repair and Troubleshooting"
echo "something else" >"$ENG/lib/wine/dxgi/dxmt/x86_64-windows/d3d11.dll"
check "graphics=other after a change in the engine" [ "$(st graphics)" = other ]
out=$(g repair 2>&1) && rc=0 || rc=$?
check "repair exits 0" [ "$rc" = 0 ]
check "graphics=yes after repair" [ "$(st graphics)" = yes ]
check "the game and the settings stay" [ "$(st game)/$(sett launchopts)" = yes/-maploadinfo ]
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
GW2_ON_MAC_WATCH_GRACE=60 "$G" play >/dev/null 2>&1; started
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
[ -n "${KEEP:-}" ] || rm -rf "$SANDBOX"
[ "$fail" = 0 ]
