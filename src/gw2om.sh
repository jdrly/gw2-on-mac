#!/bin/bash
# The install, status, play and settings logic behind the app's window. Unlike SWTOR
# on Mac it changes no existing install: it creates its own Wine engine and bottle and installs the
# game through Steam or ArenaNet's own installer. On this line the engine is Mach9's arm64 Wine as
# it ships: the app puts nothing into it.
#
#   gw2om.sh status            KEY=VALUE lines describing this Mac (what the window shows)
#   gw2om.sh install steam     phases 1-4: engine, bottle, Steam from Valve, then Steam starts
#                              with Guild Wars 2's install page; the window follows the download
#                              (status: stage=waiting_game) and runs finish once it is complete
#   gw2om.sh install arenanet <Gw2Setup-64.exe>
#                              the same with ArenaNet's installer (checked first, check-setup)
#   gw2om.sh install import <game folder> [--no-settings]
#                              uses game files the Mac already has (another Wine app's Guild Wars
#                              2): engine, bottle (and Steam, if the folder is Steam's), then the
#                              folder cloned into the bottle (same disk) or copied, the game's
#                              settings with it, and the finishing touches; the source is only read
#   gw2om.sh scan              the Guild Wars 2 installs of other Wine apps on this Mac (GW2 on Mac
#                              0.1, CrossOver, Whisky, app wrappers, Heroic, GameHub, ~/.wine), one
#                              "game" line each
#   gw2om.sh check-game DIR    is DIR (or a game folder in it) a Guild Wars 2 install: its "game"
#                              line, or "@error <why>"
#   gw2om.sh finish            phase 5 once the game is there: the shader cache's folder, the
#                              interface addon (if on), the registry settings, the manifest
#   gw2om.sh stop-waiting      the window stops following the game's download (the engine and
#                              the bottle stay; Install picks up from there)
#   gw2om.sh repair            the engine (unpacked again if it isn't the expected one), the bottle's
#                              settings; keeps the game and the settings
#   gw2om.sh uninstall         removes everything this app created: the bottle (with the game in
#                              it), the engine, the settings, its caches (DXMT's in them); logs
#                              stay
#   gw2om.sh play              starts the game (Steam: steam.exe -applaunch 1284210, -silent once
#                              Steam remembers a login; ArenaNet: Gw2-64.exe) with the settings as
#                              its environment and its compatdb rules (compatdb.rules), and the
#                              session's watcher (watch-session)
#   gw2om.sh watch-session     follows the session Play started (the file `session`): waits for
#                              Gw2-64.exe, then for its exit, and quits the Steam that Play started
#                              in the background (Quit Steam when the game quits); play starts it
#                              detached, one per session
#   gw2om.sh session-status [--since EPOCH]
#                              KEY=VALUE lines: how far the game's start is (stage, detail,
#                              progress, elapsed, steam, game, closing, limiter_hint...), from
#                              the session's processes, Steam's logs (their state lines only),
#                              DXMT's log and the watcher's session file; the window polls it
#   gw2om.sh show-steam        brings Steam's window up (steam.exe steam://open/main in the bottle)
#   gw2om.sh settings          KEY=VALUE lines: the settings (Settings window), and for each
#                              <key>_state=ok or off:<reason> (setting_state) and maybe <key>_note
#   gw2om.sh set K V           change one setting (see setting_valid); refuses one that is off
#   gw2om.sh set arcdps on|off arcdps into the game folder (downloaded from deltaconnected.com,
#                              checked against its published md5) or out of it (only arcdps; its
#                              addons/arcdps settings stay), while no session runs; status and
#                              settings print arcdps, arcdps_state (on|off|foreign|nogame)
#   gw2om.sh check-setup FILE  is FILE ArenaNet's Gw2Setup-64.exe: a PE x86_64 executable with a
#                              valid Authenticode signature by ArenaNet ("@done <what>")
#   gw2om.sh reset-shaders     deletes DXMT's caches (shaders, pipelines, recipes) in the app's
#                              own cache folder; never DXMT's in the per-user cache folder
#   gw2om.sh reinstall-engine  unpacks the engine again
#   gw2om.sh end-leftovers     ends leftover Wine processes of the engine (no session running)
#   gw2om.sh fetch-engine      downloads and verifies the engine into the cache
#   gw2om.sh env               the game's environment as play would set it (for Terminal)
#   gw2om.sh rules             the compatdb rules play would write (for Terminal)
#
# Environment:
#   GW2_ON_MAC_ROOT=/abs/dir   sandbox for tests: the app's files, logs and caches all live under
#                              it ($ROOT/home/Library/...)
#   GW2_ON_MAC_DRY_RUN=1       print what would change and change nothing (no downloads, no Wine,
#                              no log file)
#   In a sandbox only, for scripts/test-sandbox.sh's stand-ins (never the real Wine there):
#   GW2_ON_MAC_ENGINE_URL, GW2_ON_MAC_ENGINE_SHA256, GW2_ON_MAC_ENGINE_SIZE   another engine
#                              archive (a stand-in whose bin/wine only pretends)
#   GW2_ON_MAC_ENGINE_CHECKS=0 don't check the unpacked engine's files against the real engine's
#   GW2_ON_MAC_ENGINE_LOADER_SHA256, GW2_ON_MAC_ENGINE_NTDLL_SHA256, GW2_ON_MAC_ENGINE_D3D11_SHA256,
#   GW2_ON_MAC_ENGINE_WINEMETAL_SHA256   a stand-in engine's own files (engine_matches, graphics)
#   GW2_ON_MAC_MACOS           the macOS version preflight sees
#   GW2_ON_MAC_STEAMSETUP_URL  another SteamSetup.exe
#   GW2_ON_MAC_SIGNER          the signer check-setup accepts (default ArenaNet)
#   GW2_ON_MAC_ARCDPS_URL      another place for arcdps's d3d11.dll and d3d11.dll.md5sum (a
#                              fixture: file://...)
#   GW2_ON_MAC_TEST_PAUSE, GW2_ON_MAC_TEST_PAUSE_AT   wait at a point while that file is there
#                              (test_pause: locked, lock-owner-read, lock-stale-checked)
#   GW2_ON_MAC_LOCK_WAIT      how long a contender waits for the install lock's claim (5 s)
#   GW2_ON_MAC_ALLOW_WINE=1    let the real engine's Wine run in a sandbox (never in the tests)
#   GW2_ON_MAC_IMPORT_COPY=1   install import copies even on the same disk (the other-disk path)
#   GW2_ON_MAC_FREE_KB=<n>     the free space the app's disk reports (KB)
#   GW2_ON_MAC_WATCH_TIMEOUT, GW2_ON_MAC_WATCH_GRACE, GW2_ON_MAC_WATCH_QUITWAIT,
#   GW2_ON_MAC_WATCH_POLL      watch-session's times in seconds (900, 30, 20, 2)
#
# Lines for the app start with "@": "@phase <n>" (the timeline: install 1 engine, 2 bottle,
# 3 Steam or ArenaNet's installer, 4 the game's download, 5 finishing touches; install import
# 1 engine, 2 bottle, then Steam's route 3 Steam, 4 the files, 5 finishing touches, or ArenaNet's
# 3 the files, 4 finishing touches; uninstall 1 stop, 2 bottle, 3 the rest), "@step <text>", "@progress <label> <bytes> <total>", "@warn <text>",
# "@notice <text>", "@error <text>", "@done <text>". Everything else is plain log text.
# Runs under macOS's /bin/bash 3.2.
set -euo pipefail
# The app's name, for its texts and its three folders in ~/Library (Application Support, Logs,
# Caches). The 0.2 development build has its own, so it installs next to 0.1.x and shares nothing
# with it. build.sh and the scripts in scripts/ read it from here.
APP_NAME="GW2 on Mac arm64"
RES="$(cd "$(dirname "$0")" && pwd)"
COMP="$RES/components"
VERSION="$(sed -n 's/^version=//p' "$RES/app.properties" 2>/dev/null || true)"
VERSION="${VERSION:-dev}"
CHANNEL="$(sed -n 's/^channel=//p' "$RES/app.properties" 2>/dev/null || true)"
CHANNEL="${CHANNEL:-release}"

# --- The engine: athei's Mach9 0.3.1, an arm64 Wine 11.21 that runs x86_64 Windows code with FEX,
# with his DXMT build, downloaded at install time (never bundled) and used as it ships. Bump name,
# URL, size, sha256 and the files' hashes together.
ENGINE_NAME=mach9-v0.3.1
ENGINE_TITLE="Mach9 0.3.1 · Wine 11.21"
ENGINE_URL=https://github.com/athei/mach9/releases/download/v0.3.1/wine-v0.3.1-macos-arm64.tar.xz
# the same file through GitHub's API (the release asset's id): the download's second way
ENGINE_API_URL=https://api.github.com/repos/athei/mach9/releases/assets/730461181
ENGINE_SIZE=128991668
ENGINE_SHA256=90aff9a897ed0ff9aac44d0e06f0aecd3ee985afb38037f3f915451e51fa974e
# What it was built from (the release page's Components list): status, the manifest and Collect
# Logs print them
ENGINE_WINE=53def89293a   # athei/wine, wine-11.21-37
ENGINE_FEX=9d4fa4b46b1
ENGINE_DXMT=d903db89036   # athei/dxmt
# Checked after unpacking (engine_matches): the loader, a signed app bundle that every Wine process
# runs as (nothing may change inside it: a copied or re-signed loader exits), and ntdll.so. The
# DXMT tree's d3d11.dll and winemetal.so tell status whether the graphics are the engine's own.
ENGINE_LOADER_APP=lib/wine/aarch64-unix/wine.app
ENGINE_LOADER_SHA256=fac8babc821737c25483679e179f2e61e9dd2c43e3122decb1a77c5870dbeb99
ENGINE_LOADER_ID=app.mach9.loader
ENGINE_TEAM=WLKUUJD25W
ENGINE_NTDLL_SHA256=a0df4d34bc4918886606bcf9d04c9f853c521636fcbf3b6cce08e8c11b74e787
ENGINE_D3D11_SHA256=49099142c39d2aa066527d0f1a573d61e3177d317e638b4f7f1457978a61b8df
ENGINE_WINEMETAL_SHA256=c28171fd25beb364d01c097a5546e2bba9780d34641acb65ad7b63fec985c64f
# The loader's entitlements need macOS 26.4 (wine.app's own Info.plist says so too)
MACOS_MIN=26.4
# Valve's Steam installer, from Valve's CDN (Valve updates it in place: not pinned, its sha256
# goes to the log)
STEAM_SETUP_URL=https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe
GW2_APPID=1284210
# Guild Wars 2 needs about 75 GB (the window warns below that)
DISK_NEEDED=75000000000
FETCH_TRIES=3
FETCH_SECOND_TRIES=2
# watch-session: how long Guild Wars 2 may take to appear (Steam updating itself and signing in);
# the grace after it quits (its patcher or a restart starts it again) and after Steam vanishes
# before the game (Steam restarting itself after an update); how long Steam gets to quit after
# -shutdown before wineserver -k; how often it looks
WATCH_TIMEOUT=900 WATCH_GRACE=30 WATCH_QUITWAIT=20 WATCH_POLL=2

# --- Paths
ROOT="${GW2_ON_MAC_ROOT:-}"
DRY="${GW2_ON_MAC_DRY_RUN:-}"
if [ -n "$ROOT" ]; then
  case "$ROOT" in /*) ;; *) echo "@error GW2_ON_MAC_ROOT must be an absolute path"; exit 2 ;; esac
  if [ -d "$ROOT" ]; then ROOT="$(cd "$ROOT" && pwd -P)"; fi
  H="$ROOT/home"
  ENGINE_URL="${GW2_ON_MAC_ENGINE_URL:-$ENGINE_URL}"
  [ -z "${GW2_ON_MAC_ENGINE_URL:-}" ] || ENGINE_API_URL=""
  ENGINE_SHA256="${GW2_ON_MAC_ENGINE_SHA256:-$ENGINE_SHA256}"
  ENGINE_SIZE="${GW2_ON_MAC_ENGINE_SIZE:-$ENGINE_SIZE}"
  ENGINE_CHECKS="${GW2_ON_MAC_ENGINE_CHECKS:-1}"
  ENGINE_LOADER_SHA256="${GW2_ON_MAC_ENGINE_LOADER_SHA256:-$ENGINE_LOADER_SHA256}"
  ENGINE_NTDLL_SHA256="${GW2_ON_MAC_ENGINE_NTDLL_SHA256:-$ENGINE_NTDLL_SHA256}"
  ENGINE_D3D11_SHA256="${GW2_ON_MAC_ENGINE_D3D11_SHA256:-$ENGINE_D3D11_SHA256}"
  ENGINE_WINEMETAL_SHA256="${GW2_ON_MAC_ENGINE_WINEMETAL_SHA256:-$ENGINE_WINEMETAL_SHA256}"
  MACOS="${GW2_ON_MAC_MACOS:-}"
  STEAM_SETUP_URL="${GW2_ON_MAC_STEAMSETUP_URL:-$STEAM_SETUP_URL}"
  SIGNER="${GW2_ON_MAC_SIGNER:-ArenaNet}"
  SYS_APPS="$ROOT/Applications"
  IMPORT_COPY="${GW2_ON_MAC_IMPORT_COPY:-}"
  FREE_KB="${GW2_ON_MAC_FREE_KB:-}"
  WATCH_TIMEOUT="${GW2_ON_MAC_WATCH_TIMEOUT:-$WATCH_TIMEOUT}" WATCH_GRACE="${GW2_ON_MAC_WATCH_GRACE:-$WATCH_GRACE}"
  WATCH_QUITWAIT="${GW2_ON_MAC_WATCH_QUITWAIT:-$WATCH_QUITWAIT}" WATCH_POLL="${GW2_ON_MAC_WATCH_POLL:-$WATCH_POLL}"
else
  H="$HOME"
  ENGINE_CHECKS=1
  MACOS=""
  SIGNER=ArenaNet
  SYS_APPS=/Applications
  IMPORT_COPY="" FREE_KB=""
fi
APPDIR="$H/Library/Application Support/$APP_NAME"
LOGS="$H/Library/Logs/$APP_NAME"
CACHE="$H/Library/Caches/$APP_NAME"
ENG="$APPDIR/engine"                  # the unpacked engine, as it ships
BOTTLE="$APPDIR/bottle"               # the game's Wine prefix (Steam and the game live in it)
SETTINGS="$APPDIR/settings.conf"
STATE="$APPDIR/state"                 # route, stage (none|waiting_game|finished), game_dir,
                                      # origin (download|import)
MANIFEST="$APPDIR/install-manifest.json"
DXMT_CONF="$APPDIR/dxmt.conf"
# The game's compatdb rules (WINE_COMPATDB_FILE): written at each start, read by every process of
# the bottle when it starts. compatdb.local, if I create one, is appended as it is (FEX switches to
# try); nothing of the app writes it.
RULES="$APPDIR/compatdb.rules"
RULES_LOCAL="$APPDIR/compatdb.local"
# The last Play's session (watch-session keeps it; key=value lines, SESSION_KEYS), the requests to
# its watcher, and the lock that keeps one watcher per session (a file the watcher holds a flock on)
SESSION="$APPDIR/session"
WATCH_LOCK="$APPDIR/.session.lock"
SESSION_REQ="$APPDIR/session.req"
# DXMT's shader cache for the game, in the app's own cache folder instead of the per-user one
# ($(getconf DARWIN_USER_CACHE_DIR)dxmt/, which another DXMT setup of the game on this Mac may use
# and this app never touches): the game's rule sets DXMT_SHADER_CACHE_PATH to $DXMT_CACHE
# (rules_text)
DXMT_CACHE_ROOT="$CACHE/dxmt"
DXMT_CACHE="$DXMT_CACHE_ROOT/Gw2-64.exe"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
# What uninstall removes in APPDIR (the folder itself goes too once empty; gamemode is what a build
# of this line before the Mach9 engine made)
APP_FILES="engine bottle gamemode settings.conf state install-manifest.json dxmt.conf compatdb.rules compatdb.local engine.new bottle.new session session.req .session.lock"
LOGFILE=/dev/null

# --- Output and logging
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGFILE"; }
say() { echo "$*"; log "$*"; }
step() { echo "@step $*"; log "== $*"; }
phase() { echo "@phase $1"; }
warn() { echo "@warn $*"; log "WARNING: $*"; }
die() { echo "@error $*"; log "ERROR: $*"; exit 1; }
open_log() { if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/install.log"; fi; }

# run <command...>: a change to the system (only printed in a dry run)
run() {
  if [ -n "$DRY" ]; then
    printf '[dry-run]'; printf ' %q' "$@"; printf '\n'
  else
    { printf '+'; printf ' %q' "$@"; printf '\n'; } >>"$LOGFILE"
    "$@"
  fi
}

# put <file> <mode>: writes stdin to <file> atomically
put() {
  if [ -n "$DRY" ]; then
    cat >/dev/null
    echo "[dry-run] write $1"
    return
  fi
  log "+ write $1"
  cat >"$1.new.$$"
  chmod "$2" "$1.new.$$"
  mv -f "$1.new.$$" "$1"
}

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
json_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }   # <file> <keypath>
mb() { echo $((($1 + 524288) / 1048576)); }
thousands() { echo "$1" | sed -e :a -e 's/^\([0-9]\{1,\}\)\([0-9]\{3\}\)/\1,\2/;ta'; }   # 234978748 -> 234,978,748
in_list() { local w; for w in $2; do [ "$w" = "$1" ] && return 0; done; return 1; }
macos_version() { if [ -n "$MACOS" ]; then echo "$MACOS"; else sw_vers -productVersion 2>/dev/null || echo 0; fi; }
# macos_ok: this Mac's macOS is MACOS_MIN or later (major and minor compared as numbers)
macos_ok() {
  local a b x y
  IFS=. read -r a b _ <<<"$(macos_version)"
  IFS=. read -r x y _ <<<"$MACOS_MIN"
  case "${a:-0}${b:-0}" in *[!0-9]*) return 1 ;; esac
  [ "${a:-0}" -gt "$x" ] || { [ "${a:-0}" -eq "$x" ] && [ "${b:-0}" -ge "$y" ]; }
}
# free_kb: free space (KB) on the volume the app's folder is (or will be) on
free_kb() {
  local d="$APPDIR"
  if [ -n "$FREE_KB" ]; then echo "$FREE_KB"; return; fi
  while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
  { df -k "$d" 2>/dev/null || true; } | awk 'NR == 2 { print $4 }'
}

# state <key>: a value of the state file; set_state <key> <value>
state() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | tail -1; }
set_state() {
  local k
  { for k in route stage game_dir game_exe origin; do
      if [ "$k" = "$1" ]; then echo "$k=$2"; else echo "$k=$(state "$k")"; fi
    done; } | put "$STATE" 644
}

# --- Processes
#
# Programs are told by their real executable (helpers/procpaths, the resolved path): Wine rewrites
# argv[0], so ps shows C:\...\name.exe for its processes, while their executable is the engine's
# loader in wine.app. Only this engine's processes count (another Wine, a Mach9.app elsewhere,
# another sandbox's test or my own setup never stop this one).
proc_list() {
  local helper="$RES/helpers/procpaths"
  { if [ -x "$helper" ]; then "$helper" 2>/dev/null | sed 's/^/P /'; fi
    ps -axww -o pid=,comm= 2>/dev/null | sed 's/^ */C /'; } |
  awk -v e="$ENG/" -v s="$ENG/bin/wineserver" '
    $1 == "P" { x = $0; sub(/^P [0-9]+ /, "", x); real[$2] = x; next }
    { pid = $2; prog = $0; sub(/^C [0-9]+ /, "", prog)
      exe = (pid in real) ? real[pid] : prog
      if (index(exe, e) != 1) next
      p = tolower(prog) }
    exe == s { print "session", pid, prog; next }
    p ~ /[\/\\]gw2-64\.exe$/ { print "game", pid, prog; next }
    p ~ /[\/\\]gw2setup-64\.exe$/ { print "installer", pid, prog; next }
    p ~ /[\/\\](steam|steamwebhelper|steamservice|steamerrorreporter)\.exe$/ { print "steam", pid, prog; next }
    { print "engine", pid, prog }' || true
}
# busy_of <proc_list output>: game, steam, installer, session (only the bottle's Wine), leftovers
# (engine processes without a wineserver), none
busy_of() {
  local k
  for k in game steam installer session; do
    if printf '%s\n' "$1" | grep -q "^$k "; then echo "$k"; return; fi
  done
  if printf '%s\n' "$1" | grep -q '^engine '; then echo leftovers; else echo none; fi
}
proc_names() {
  local l=$1; shift
  printf '%s\n' "$l" | awk -v k=" $* " 'index(k, " " $1 " ") { $1 = ""; $2 = ""; sub(/^ +/, ""); n = split($0, p, /[\/\\]/); print p[n] }' |
    sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}
busy_message() {
  case "$1" in
    game) echo "Guild Wars 2 is running. Quit it first." ;;
    steam) echo "Steam is running in the game's bottle. Quit Steam first (Steam > Exit)." ;;
    installer) echo "ArenaNet's installer is running. Let it finish or quit it first." ;;
    session) echo "The game's Wine is still running ($(proc_names "$2" session engine)). It ends by itself a few seconds after Steam and the game have quit; try again then." ;;
  esac
}
session_running() { case "$(busy_of "$(proc_list)")" in game|steam|installer|session) return 0 ;; esac; return 1; }

# Ends leftover processes of the engine: only when no wineserver of it runs, so they can't belong
# to a session
end_leftovers() {
  local l pids names
  l=$(proc_list)
  [ "$(busy_of "$l")" = leftovers ] || return 0
  pids=$(printf '%s\n' "$l" | awk '$1 == "engine" { print $2 }' | tr '\n' ' ')
  names=$(proc_names "$l" engine)
  if [ -n "$DRY" ]; then echo "[dry-run] end leftover Wine processes: $names (${pids% })"; return 0; fi
  # shellcheck disable=SC2086
  kill -9 $pids 2>/dev/null || true
  say "Ended leftover Wine processes (no Wine session was running): $names (pids ${pids% })"
}

check_not_running() {
  local l b
  end_leftovers
  l=$(proc_list)
  b=$(busy_of "$l")
  case "$b" in game|steam|installer|session) die "$(busy_message "$b" "$l")" ;; esac
}

# --- Downloads

is_xz() { [ "$(head -c 6 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = fd377a585a00 ]; }

# fetch_source <url> <tries> [<header>]: attempts at <url> into $f.part (fetch's locals f, sha,
# size, label, dir); sets OUT: ok, empty, page, notfile, stopped, wrong (as SWTOR on Mac's)
fetch_source() {
  local url=$1 tries=$2 hdr=${3:-} try pid http info="$dir/.curl-info" h=()
  [ -z "$hdr" ] || h=(-H "$hdr")
  CURL_RC=0 GOT=0 START="" ACTUAL=""
  for try in $(seq 1 "$tries"); do
    if [ -f "$f.part" ]; then
      GOT=$(stat -f %z "$f.part")
      if [ "$GOT" -gt "$size" ] || ! is_xz "$f.part"; then
        log "attempt $try: the partial download ($GOT bytes) is not the start of the file; starting over"
        rm -f "$f.part"
      elif [ "$GOT" -eq "$size" ]; then
        break
      else
        log "attempt $try: resuming at $GOT of $size bytes"
      fi
    fi
    CURL_RC=0
    curl -fsSL --connect-timeout 20 --speed-limit 10240 --speed-time 60 -C - ${h[@]+"${h[@]}"} \
      -w '%{http_code}' -o "$f.part" "$url" >"$info" 2>>"$LOGFILE" &
    pid=$!
    FETCH_PID=$pid
    while kill -0 "$pid" 2>/dev/null; do
      echo "@progress $label $(stat -f %z "$f.part" 2>/dev/null || echo 0) $size"
      sleep 1
    done
    wait "$pid" || CURL_RC=$?
    FETCH_PID=
    GOT=$(stat -f %z "$f.part" 2>/dev/null || echo 0)
    http=$(cat "$info" 2>/dev/null || true)
    log "attempt $try: curl status $CURL_RC, HTTP ${http:-none}, $GOT of $size bytes"
    case "$CURL_RC" in
      23) rm -f "$f.part" "$info"; die "Not enough free disk space for the $label download ($(mb "$size") MB). Free some space and try again." ;;
      33) log "attempt $try: the server can't resume; starting over"; rm -f "$f.part"; GOT=0; continue ;;
    esac
    if [ ! -s "$f.part" ]; then
      case "$http" in 4??) break ;; esac
    else
      [ "$GOT" -lt "$size" ] && is_xz "$f.part" || break
    fi
    [ "$try" -eq "$tries" ] || sleep 2
  done
  rm -f "$info"
  if [ ! -s "$f.part" ]; then
    rm -f "$f.part"; OUT=empty
  elif ! is_xz "$f.part"; then
    START=$(head -c 200 "$f.part" | LC_ALL=C tr -c '[:print:]' ' ' | tr -s ' ')
    log "not the file: $GOT bytes starting with: $START"
    rm -f "$f.part"
    case "$START" in *[Hh][Tt][Mm][Ll]*|*'<?xml'*) OUT=page ;; *) OUT=notfile ;; esac
  elif [ "$GOT" -lt "$size" ]; then
    OUT=stopped
  else
    ACTUAL=$(sha256 "$f.part")
    if [ "$GOT" -eq "$size" ] && [ "$ACTUAL" = "$sha" ]; then
      OUT=ok
    else
      log "not the expected file: $GOT bytes (expected $size), sha256 $ACTUAL (expected $sha)"
      rm -f "$f.part"; OUT=wrong
    fi
  fi
}

# fetch <url> <sha256> <size> <label> [<second url>]: the verified download in $CACHE/downloads
# (FETCHED), resumed and retried; a second address of the same file if the first fails
fetch() {
  local url=$1 sha=$2 size=$3 label=$4 second=${5:-} dir="$CACHE/downloads" f manual have=""
  f="$dir/$(basename "$url")"
  FETCHED=$f
  [ ! -f "$f" ] || have=$(sha256 "$f")
  if [ "$have" = "$sha" ]; then
    say "$label: using the verified download in the cache"
    return
  fi
  if [ -n "$DRY" ]; then
    echo "[dry-run] download $url ($size bytes, sha256 $sha) to $f"
    return
  fi
  mkdir -p "$dir"
  # A file that isn't the one expected, often one the player put here by hand: moved aside under
  # .wrong (replacing an earlier one) instead of deleted, and named in the window
  if [ -n "$have" ]; then
    log "$f in the cache is not the expected file ($(stat -f %z "$f") bytes, sha256 $have); moved to $f.wrong"
    warn "$(basename "$f") in $dir is not the $label. It has $(thousands "$(stat -f %z "$f")") bytes and a sha256 starting ${have:0:12}, the $label has $(thousands "$size") bytes and a sha256 starting ${sha:0:12}. $APP_NAME renamed your file to $(basename "$f").wrong and downloads the $label itself."
    mv -f "$f" "$f.wrong"
  fi
  say "Downloading $label from $url"
  fetch_source "$url" "$FETCH_TRIES"
  if [ "$OUT" != ok ] && [ -n "$second" ]; then
    say "The download from $url did not bring the file ($OUT); trying GitHub's other address for it, $second"
    fetch_source "$second" "$FETCH_SECOND_TRIES" "Accept: application/octet-stream"
  fi
  echo "@progress $label $GOT $size"
  manual="Or download $url in your browser, put the file into $dir and click Install again. It must be that exact file: $(thousands "$size") bytes, with the sha256 $sha."
  case "$OUT" in
    ok) mv -f "$f.part" "$f"; log "verified $f (sha256 $sha)"; return ;;
    empty) die "The download of the $label failed (curl status $CURL_RC). Check your internet connection and try again. $manual" ;;
    page) die "The download of the $label brought a web page instead of the file. A captive portal (hotel or public Wi-Fi), a proxy, a VPN or a content filter is in the way: log in to the network or turn it off, then try again. $manual" ;;
    notfile) die "The download of the $label brought something else than the file ($(mb "$GOT") MB, not an archive). A proxy, VPN or content filter may be in the way. Try again. $manual" ;;
    stopped) die "The download of the $label stopped at $(mb "$GOT") of $(mb "$size") MB (curl status $CURL_RC). Check your internet connection and click Install again: it continues where it stopped. $manual" ;;
    wrong) die "The download of the $label is not the expected file: got $(mb "$GOT") MB of $(mb "$size") MB, sha256 ${ACTUAL:0:12}… (expected ${sha:0:12}…). Something on the way changes it (a proxy, VPN, antivirus or content filter). $manual" ;;
  esac
}

# download <url> <file> <label>: an unpinned file (SteamSetup.exe), with progress
download() {
  local url=$1 out=$2 label=$3 total pid rc=0
  if [ -n "$DRY" ]; then echo "[dry-run] download $url to $out"; return; fi
  mkdir -p "$(dirname "$out")"
  # (its size for the progress, if the server says; unknown is fine)
  total=$( { curl -fsIL --connect-timeout 20 "$url" 2>/dev/null || true; } | tr -d '\r' | awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }')
  rm -f "$out.part"
  curl -fsSL --connect-timeout 20 --retry 2 -o "$out.part" "$url" 2>>"$LOGFILE" &
  pid=$!
  FETCH_PID=$pid
  while kill -0 "$pid" 2>/dev/null; do
    echo "@progress $label $(stat -f %z "$out.part" 2>/dev/null || echo 0) $total"
    sleep 1
  done
  wait "$pid" || rc=$?
  FETCH_PID=
  [ "$rc" -eq 0 ] && [ -s "$out.part" ] || { rm -f "$out.part"; die "The download of $label from $url failed (curl status $rc). Check your internet connection and try again."; }
  echo "@progress $label $(stat -f %z "$out.part") $(stat -f %z "$out.part")"
  mv -f "$out.part" "$out"
  log "downloaded $url: $(stat -f %z "$out") bytes, sha256 $(sha256 "$out")"
}

# --- Wine

# The real engine's Wine never runs in a sandbox (a stand-in engine's does, for the tests):
# wine_allowed refuses it, real_wine_in_sandbox says so without stopping
real_wine_in_sandbox() { [ -n "$ROOT" ] && [ "$ENGINE_CHECKS" != 0 ] && [ "${GW2_ON_MAC_ALLOW_WINE:-}" != 1 ]; }
wine_allowed() {
  ! real_wine_in_sandbox ||
    die "Refusing to run the real Wine engine in a sandbox (GW2_ON_MAC_ROOT): use a stand-in engine or GW2_ON_MAC_DRY_RUN=1."
}

# Variables of the engine's compatdb that would change what every process of the bottle does, if
# the app inherited them (the engine's own rules give Steam and the game what they need)
COMPATDB_UNSET=(-u WINE_COMPATDB -u WINE_COMPATDB_FILE -u WINE_LARGE_ADDRESS_AWARE -u WINE_PROF_SERVICE)

# wine_do <args...>: Wine in the bottle for the install's own steps (output to the log)
wine_do() {
  if [ -n "$DRY" ]; then echo "[dry-run] wine $*"; return; fi
  wine_allowed
  log "+ wine $*"
  env -u WINELOADER -u WINESERVER -u WINEDLLPATH -u DYLD_FALLBACK_LIBRARY_PATH "${COMPATDB_UNSET[@]}" \
    WINEPREFIX="$BOTTLE" WINEDEBUG=-all WINEMSYNC=1 WINEDLLOVERRIDES=winemenubuilder.exe=d \
    "$ENG/bin/wine" "$@" </dev/null >>"$LOGFILE" 2>&1
}

# End the bottle's Wine session and make sure nothing of it stays running
stop_wine() {
  [ -n "$DRY" ] && { echo "[dry-run] wineserver -k"; return; }
  [ -x "$ENG/bin/wineserver" ] && ! real_wine_in_sandbox || return 0
  WINEPREFIX="$BOTTLE" "$ENG/bin/wineserver" -k >>"$LOGFILE" 2>&1 || true
  WINEPREFIX="$BOTTLE" "$ENG/bin/wineserver" -w >>"$LOGFILE" 2>&1 || true
  local left
  for _ in 1 2 3 4 5; do
    left=$(proc_list | awk '$1 != "" { print $2 }')
    [ -z "$left" ] && return 0
    sleep 1
  done
  warn "Ending leftover Wine processes: $(echo "$left" | tr '\n' ' ')"
  echo "$left" | xargs kill -9 2>/dev/null || true
}

# wait_wine: the session's processes have ended (wineserver -w)
wait_wine() {
  [ -n "$DRY" ] && { echo "[dry-run] wineserver -w"; return; }
  ! real_wine_in_sandbox || return 0
  WINEPREFIX="$BOTTLE" "$ENG/bin/wineserver" -w >>"$LOGFILE" 2>&1 || true
}

# set_reg <key> <name> <data>: a value in HKCU, written straight into the bottle's user.reg (Wine
# reads it when its wineserver starts: only while no session runs). <key> as in user.reg's section
# headers, with doubled backslashes; <data> as user.reg spells it ("y" with its quotes for a
# string, dword:00000000 for a number).
set_reg() {
  local reg="$BOTTLE/user.reg"
  if [ -n "$DRY" ]; then echo "[dry-run] $2=$3 under $1 in $reg"; return; fi
  [ -f "$reg" ] || die "The game's bottle is incomplete ($reg is missing). Click Repair."
  log "+ $2=$3 under $1 in $reg"
  K="[$1]" N="\"$2\"=" V="$3" T="$(date +%s)" awk '
    BEGIN { k = ENVIRON["K"]; n = ENVIRON["N"]; line = n ENVIRON["V"] }
    index($0, "[") == 1 {
      if (pending) { print line; pending = 0 }
      insec = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ")
      if (insec) { found = 1; pending = 1 }
      print; next
    }
    insec && index($0, n) == 1 { next }
    pending && index($0, "#time=") == 1 { print; next }
    pending { print line; pending = 0 }
    { print }
    END {
      if (pending) print line
      if (!found) { print ""; print k " " ENVIRON["T"]; print line }
    }' "$reg" >"$reg.new.$$"
  mv -f "$reg.new.$$" "$reg"
}
# get_reg <key> <name>: its value, if set
get_reg() {
  K="[$1]" N="\"$2\"=\"" awk '
    BEGIN { k = ENVIRON["K"]; n = ENVIRON["N"] }
    index($0, "[") == 1 { insec = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ") }
    insec && index($0, n) == 1 { v = substr($0, length(n) + 1); sub(/"$/, "", v); print v }' "$BOTTLE/user.reg" 2>/dev/null || true
}
REG_MAC='Software\\Wine\\Mac Driver'
REG_X11='Software\\Wine\\X11 Driver'
REG_WINEDBG='Software\\Wine\\WineDbg'

# registry_lock: the session's lock (WATCH_LOCK, see watch-session) on fd 8, without waiting. A
# Play takes it before it starts Wine and its watcher holds it for the whole session, so while the
# registry writes hold it no session can start (that Play waits for it, see join_session); fails
# if a Play or a session holds it, or without the lock's helper (a Play then starts the game
# unlocked, so the writes wait for it to be back). registry_unlock releases it (and so does the
# process's exit).
registry_lock() {
  [ -z "$DRY" ] || return 0
  # (a Play that holds the session's lock already, on fd 9: SESSION_LOCKED)
  [ -z "${SESSION_LOCKED:-}" ] || return 0
  [ -x "$LOCKER" ] || { warn "$APP_NAME's session helper is missing ($LOCKER): registry settings wait for it. Reinstall $APP_NAME."; return 1; }
  [ ! -d "$WATCH_LOCK" ] || rm -rf "$WATCH_LOCK"
  exec 8>>"$WATCH_LOCK"
  "$LOCKER" take 8 2>/dev/null && return 0
  exec 8>&-
  return 1
}
registry_unlock() { [ -z "$DRY" ] && [ -z "${SESSION_LOCKED:-}" ] || return 0; exec 8>&-; }

# The bottle's registry settings, the three values Mach9's own launcher writes: RetinaMode (from
# settings.conf), EmulateModeset and ShowCrashDialog off. Only while no session runs or starts (Wine reads user.reg when its wineserver
# starts and writes it back), else at the next game start that finds none (play).
apply_registry() {
  [ -f "$BOTTLE/user.reg" ] || [ -n "$DRY" ] || return 0
  if ! registry_lock; then
    log "registry settings wait for the next start without a running session (its lock is held, or its helper missing)"
    return 0
  fi
  if session_running; then
    registry_unlock
    log "registry settings wait for the next start without a running session"
    return 0
  fi
  set_reg "$REG_MAC" RetinaMode "\"$([ "$(setting retina)" = on ] && echo y || echo n)\""
  set_reg "$REG_X11" EmulateModeset '"Y"'
  set_reg "$REG_WINEDBG" ShowCrashDialog dword:00000000
  registry_unlock
}

# --- Settings
#
# The keys are 0.1.x's, so settings.conf reads the same on both lines. On this engine some of them
# need pieces of mine that come in later steps: setting_state says so, the Settings window greys
# them with the reason, set refuses them, and they keep what settings.conf says without an effect.
SETTING_KEYS="retina fpscap metalfx hud warm coolworkers fastlocks ncpu uiscale uiscale_size uiscale_sans uiscale_cinema gamemode launchopts rawmouse mousespeed updates debug steambg quitsteam"
FPS_CAPS="off 30 40 60 120"
# Mouse-look speed (mousespeed): RawMouseGameControllerScale, a factor on the macOS pointer's
# speed (SWTOR on Mac's MOUSE_SPEEDS)
MOUSE_SPEEDS="0.5 0.75 1 1.25 1.5 1.75 2 2.5 3"
# CPUs the game sees (ncpu): 2 up to this Mac's logical CPUs, or all
CPU_MAX="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
UI_SCALES="1.5 1.75 1.8 2.0"
setting_default() {
  case "$1" in
    retina|warm|fastlocks|uiscale_sans|gamemode|rawmouse|updates|steambg|quitsteam) echo on ;;
    metalfx|hud|uiscale|uiscale_cinema) echo off ;;
    mousespeed) echo 1 ;;
    debug) if [ "$CHANNEL" = dev ]; then echo on; else echo off; fi ;;
    fpscap) echo off ;;
    coolworkers) echo 3 ;;
    ncpu) echo 8 ;;
    uiscale_size) echo 1.75 ;;
    launchopts) echo "" ;;
  esac
}
setting_valid() { # <key> <value>
  case "$1" in
    retina|metalfx|hud|warm|fastlocks|uiscale|uiscale_sans|uiscale_cinema|gamemode|rawmouse|updates|debug|steambg|quitsteam)
      [ "$2" = on ] || [ "$2" = off ] ;;
    mousespeed) in_list "$2" "$MOUSE_SPEEDS" ;;
    fpscap) in_list "$2" "$FPS_CAPS" ;;
    ncpu) [ "$2" = all ] || { case "$2" in ''|*[!0-9]*) false ;; *) [ "$2" -ge 2 ] && [ "$2" -le "$CPU_MAX" ] ;; esac; } ;;
    uiscale_size) in_list "$2" "$UI_SCALES" ;;
    coolworkers) [ "$2" = off ] || { case "$2" in ''|*[!0-9]*) false ;; *) [ "$2" -ge 1 ] && [ "$2" -le 15 ] ;; esac; } ;;
    # Gw2-64.exe's arguments: words of letters, digits and -_.:=,/+ only (nothing a shell or Wine
    # would take for something else)
    launchopts) case "$2" in *[!A-Za-z0-9\ _.:=,/+-]*) false ;; *) [ ${#2} -le 200 ] ;; esac ;;
    *) false ;;
  esac
}
setting() { # <key>: its value, or the default
  local v
  if [ -f "$SETTINGS" ] && grep -q "^$1=" "$SETTINGS"; then
    v=$(sed -n "s/^$1=//p" "$SETTINGS" | tail -1)
    if setting_valid "$1" "$v"; then echo "$v"; return; fi
  fi
  setting_default "$1"
}
# setting_state <key>: ok, or off:<reason> for a setting this engine can't do yet (the one table of
# them; settings prints it, the window greys the row and shows the reason, set refuses the key)
setting_state() {
  case "$1" in
    metalfx|warm) echo "off:Needs my DXMT fork. Comes with step 2." ;;
    coolworkers|fastlocks) echo "off:Need my Wine changes. Come with step 3." ;;
    rawmouse|mousespeed) echo "off:This engine reads the mouse from GameController by itself. My mouse-look comes with step 4." ;;
    gamemode) echo "off:The engine's loader is a Game Mode app. Nothing to switch." ;;
    *) echo ok ;;
  esac
}
# setting_note <key>: what the window shows under a setting that works but is untested here
setting_note() {
  case "$1" in
    uiscale|uiscale_size|uiscale_sans) echo "Untested on this engine. #27." ;;
    uiscale_cinema|arcdps) echo "A code patch, untested under FEX." ;;
  esac
}
write_settings() { # [<key> <value>]: settings.conf with every key, one of them changed
  local k v
  for k in $SETTING_KEYS; do
    v=$(setting "$k")
    if [ "$k" = "${1:-}" ]; then v=$2; fi
    echo "$k=$v"
  done | {
    echo "# $APP_NAME settings (change them in the app: $APP_NAME > Settings…)"
    cat
  } | put "$SETTINGS" 644
}

# dxmt.conf: DXMT's options for the game (DXMT_CONFIG_FILE)
write_dxmt_conf() {
  local cap
  cap=$(setting fpscap)
  {
    echo "# DXMT options for Guild Wars 2, written by $APP_NAME from its settings (DXMT_CONFIG_FILE)."
    if [ "$cap" != off ]; then
      echo "# Frame cap: Metal-paced, a divisor of the display's refresh (use it with the game's vsync)"
      echo "d3d11.preferredMaxFrameRate = $cap"
    fi
  } | put "$DXMT_CONF" 644
}

# The environment of the session's first process (play), from settings.conf; also what `env`
# prints. Steam passes it on to the game, so it is fixed while Steam runs. What only the game gets
# goes into its compatdb rules instead (rules_text), which each process reads when it starts.
game_env() {
  local n debug=-all
  [ "$(setting debug)" != on ] || debug=err+all,fixme-all
  E=(
    "WINEPREFIX=$BOTTLE"
    "WINEDEBUG=$debug"
    "WINEDLLOVERRIDES=winemenubuilder.exe=d"
    "WINEMSYNC=1"
    "DXMT_CONFIG_FILE=$DXMT_CONF"
    "DXMT_LOG_PATH=$LOGS"
    "WINE_COMPATDB_FILE=$RULES"
  )
  n=$(setting ncpu)
  [ "$n" = all ] || E+=("WINENCPU=$n")
  [ "$(setting debug)" != on ] || E+=("DXMT_LOG_LEVEL=debug")
  return 0
}

# cdb_value <text>: <text> as a value of a compatdb rule (the crate's wire.rs, encode_into): %, ;
# and every ASCII control character as %XX, everything else as it is
cdb_value() {
  local v=$1 out="" c i LC_ALL=C
  v=${v//%/%25}
  v=${v//;/%3B}
  case "$v" in
    *[[:cntrl:]]*)
      for ((i = 0; i < ${#v}; i++)); do
        c=${v:i:1}
        case "$c" in [[:cntrl:]]) out="$out$(printf '%%%02X' "'$c")" ;; *) out="$out$c" ;; esac
      done
      v=$out ;;
  esac
  printf '%s' "$v"
}

# rules_text: the game's compatdb rules, one line each, in the canonical text of Mach9's compatdb
# 0.3.1 (Table's Display: the fields in the order of Key::ALL, words in lowercase), which CI's
# compatdb check reads back byte for byte. The engine's built-in rules already give every process
# DXMT, DPI awareness, raw mouse from GameController and FEX's reduced x87 precision. Gw2-64.exe:
#   metal_hud=true     the Metal HUD (Settings › Graphics), in the game only
#   dll_overrides      native first, for an addon in the game folder: d3d11 and dxgi while one is
#                      there (arcdps, Nexus), version while the larger interface is on. With no
#                      such file Wine loads its own (n,b).
#   env                DXMT's shader cache in the app's cache folder
# CefHost.exe, which the game starts for its launcher and the Trading Post, inherits the game's
# variables: the rule takes the cache path away from it again, and the HUD while it is on.
rules_text() {
  local game="exe=Gw2-64.exe" cef="exe=CefHost.exe"
  if [ "$(setting hud)" = on ]; then game="$game;metal_hud=true" cef="$cef;metal_hud=false"; fi
  arcdps_state
  case "$ARC" in on|foreign) game="$game;dll_overrides=d3d11,dxgi=n,b" ;; esac
  [ "$(setting uiscale)" != on ] || game="$game;dll_overrides=version=n,b"
  echo "$game;env=DXMT_SHADER_CACHE_PATH=$(cdb_value "$DXMT_CACHE")"
  echo "$cef;env=DXMT_SHADER_CACHE_PATH="
}
# write_rules: compatdb.rules from the settings, then compatdb.local as it is (a temporary file
# and a rename, so a process that starts meanwhile reads the old rules or the new, never half)
write_rules() {
  { rules_text; [ ! -f "$RULES_LOCAL" ] || cat "$RULES_LOCAL"; } | put "$RULES" 644
}

# --- Engine

engine_ok() { [ -x "$ENG/bin/wine" ] && [ "$(cat "$ENG/.gw2om-source" 2>/dev/null || true)" = "$ENGINE_SHA256" ]; }

# engine_matches <dir>: the unpacked engine is the expected build: its loader's and ntdll.so's
# sha256, and wine.app's signature (codesign reads it and starts nothing): valid, by Mach9's team,
# with the loader's identifier
engine_matches() {
  local app="$1/$ENGINE_LOADER_APP" info
  [ "$(sha256 "$app/Contents/MacOS/wine" 2>/dev/null)" = "$ENGINE_LOADER_SHA256" ] &&
    [ "$(sha256 "$1/lib/wine/aarch64-unix/ntdll.so" 2>/dev/null)" = "$ENGINE_NTDLL_SHA256" ] &&
    codesign --verify --strict "$app" >>"$LOGFILE" 2>&1 || return 1
  info=$(codesign -dv "$app" 2>&1) || return 1
  printf '%s\n' "$info" | grep -qx "Identifier=$ENGINE_LOADER_ID" &&
    printf '%s\n' "$info" | grep -qx "TeamIdentifier=$ENGINE_TEAM"
}

# Graphics in the engine: yes (its DXMT tree's d3d11.dll and winemetal.so are the engine's own),
# other (something else: Repair unpacks the engine again), no (no engine)
graphics_state() {
  local t="$ENG/lib/wine/dxgi/dxmt"
  [ -x "$ENG/bin/wine" ] || { echo no; return; }
  if [ "$(sha256 "$t/aarch64-windows/d3d11.dll" 2>/dev/null)" = "$ENGINE_D3D11_SHA256" ] &&
    [ "$(sha256 "$t/aarch64-unix/winemetal.so" 2>/dev/null)" = "$ENGINE_WINEMETAL_SHA256" ]; then
    echo yes
  else
    echo other
  fi
}

# test_pause <point>: the tests' interleavings (a sandbox only): waits at <point> while the file
# GW2_ON_MAC_TEST_PAUSE is there, if GW2_ON_MAC_TEST_PAUSE_AT names that point (<file>.at says it
# got there)
test_pause() {
  [ -n "$ROOT" ] && [ -n "${GW2_ON_MAC_TEST_PAUSE:-}" ] && [ "${GW2_ON_MAC_TEST_PAUSE_AT:-}" = "$1" ] || return 0
  local i=0
  touch "$GW2_ON_MAC_TEST_PAUSE.at"
  while [ -e "$GW2_ON_MAC_TEST_PAUSE" ] && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
}

# install_engine [force]: the verified engine unpacked into $ENG (unless it's there already). The
# app writes nothing into it afterwards, and nothing at all inside wine.app.
install_engine() {
  local dst="$ENG"
  if engine_ok && [ "${1:-}" != force ]; then
    say "The Wine engine ($ENGINE_TITLE) is already in place"
    return
  fi
  fetch "$ENGINE_URL" "$ENGINE_SHA256" "$ENGINE_SIZE" "Wine engine" "$ENGINE_API_URL"
  say "Unpacking the Wine engine ($ENGINE_TITLE)"
  run rm -rf "$dst.new"
  run mkdir -p "$dst.new"
  run tar -xJf "$FETCHED" -C "$dst.new" --strip-components 1
  if [ -z "$DRY" ]; then
    # An archive downloaded in a browser carries the quarantine attribute and tar copies it onto
    # every file: the loader is notarized and would pass, the engine's ad hoc signed libraries not
    run xattr -dr com.apple.quarantine "$dst.new"
    # its SDK (headers, link libraries, Wine's conformance tests, man pages) is not needed to run it
    rm -rf "$dst.new/include" "$dst.new/lib/wine/tests" "$dst.new/lib/wine/x86_64-windows" "$dst.new/share/man"
    if [ "$ENGINE_CHECKS" = 1 ]; then
      engine_matches "$dst.new" || die "The unpacked Wine engine does not match the expected build."
    fi
    echo "$ENGINE_SHA256" >"$dst.new/.gw2om-source"
  fi
  run rm -rf "$dst"
  run mv "$dst.new" "$dst"
  CREATED="$CREATED engine"
  log "engine: $ENGINE_NAME (Wine $ENGINE_WINE, FEX $ENGINE_FEX, DXMT $ENGINE_DXMT)"
}

# --- The game

# Steam's library folders in the bottle (the default one, and any added in Steam), as paths on
# this Mac
steam_libraries() {
  echo "$STEAM_DIR/steamapps"
  sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$STEAM_DIR/steamapps/libraryfolders.vdf" 2>/dev/null |
    sed 's/\\\\/\\/g' | while IFS= read -r p; do
      case "$p" in [Cc]:\\*) echo "$BOTTLE/drive_c/$(echo "${p#??}" | sed 's/^\\//; s/\\/\//g')/steamapps" ;; esac
    done | sort -u
}
# acf <file> <key>: a top-level value of a Steam appmanifest
acf() { sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$1" 2>/dev/null | head -1; }
# Steam remembers a login: a user in its config/loginusers.vdf with "RememberPassword" "1" (Steam
# signs in by itself; without one, it asks in its window)
steam_remembers_login() {
  awk -F'"' 'tolower($2) == "rememberpassword" && $4 == "1" { f = 1 } END { exit !f }' "$STEAM_DIR/config/loginusers.vdf" 2>/dev/null
}

# game_state: sets GAME (yes|no), GAME_DIR, GAME_EXE (its Windows path), GAME_BYTES, GAME_TOTAL
game_state() {
  local lib m dir flags exe
  GAME=no GAME_DIR="" GAME_EXE="" GAME_BYTES="" GAME_TOTAL=""
  case "$(state route)" in
    steam)
      for lib in $(steam_libraries | tr ' ' '\001'); do
        lib=$(echo "$lib" | tr '\001' ' ')
        m="$lib/appmanifest_$GW2_APPID.acf"
        [ -f "$m" ] || continue
        dir="$lib/common/$(acf "$m" installdir)"
        flags=$(acf "$m" StateFlags)
        GAME_DIR=$dir
        GAME_BYTES=$(acf "$m" BytesDownloaded)
        GAME_TOTAL=$(acf "$m" BytesToDownload)
        # 4: fully installed (Steam's StateFlags)
        if [ "$flags" = 4 ] && [ -f "$dir/Gw2-64.exe" ]; then GAME=yes; fi
        break
      done ;;
    arenanet)
      dir=$(state game_dir)
      if [ -z "$dir" ] || [ ! -f "$dir/Gw2-64.exe" ]; then
        dir="$BOTTLE/drive_c/Program Files/Guild Wars 2"
        if [ ! -f "$dir/Gw2-64.exe" ]; then
          exe=$(find "$BOTTLE/drive_c" -maxdepth 5 -iname Gw2-64.exe -not -path '*/Steam/*' 2>/dev/null | head -1 || true)
          [ -z "$exe" ] || dir=$(dirname "$exe")
        fi
      fi
      if [ -f "$dir/Gw2-64.exe" ]; then
        GAME_DIR=$dir
        GAME_BYTES=$(stat -f %z "$dir/Gw2.dat" 2>/dev/null || echo 0)
        # ArenaNet's installer gives no completion record: the game is there once Gw2.dat has
        # data and neither the installer nor the game's own launcher still runs
        if [ "$GAME_BYTES" -gt 1000000000 ] && ! printf '%s\n' "$(proc_list)" | grep -q -e '^installer ' -e '^game '; then
          GAME=yes
        fi
      fi ;;
  esac
  if [ -n "$GAME_DIR" ]; then
    GAME_EXE="C:\\$(echo "${GAME_DIR#"$BOTTLE/drive_c/"}" | sed 's/\//\\/g')\\Gw2-64.exe"
  fi
}

# --- The interface addon (addon/ui-scale: version.dll and gw2-ui-scale.ini in the game folder)
UI_MARK='gw2-on-mac ui-scale'
uiscale_state() {
  local dll
  game_state
  [ -n "$GAME_DIR" ] || { [ "$(setting uiscale)" = on ] && echo nogame || echo off; return; }
  dll="$GAME_DIR/version.dll"
  if [ -f "$dll" ] && ! grep -aq "$UI_MARK" "$dll"; then echo foreign; return; fi
  if [ "$(setting uiscale)" != on ]; then echo off; return; fi
  if [ -f "$dll" ]; then echo on; else echo missing; fi
}
write_uiscale_ini() {
  sed -e "s/^scale=.*/scale=$(setting uiscale_size)/" \
    -e "s/^sans=.*/sans=$([ "$(setting uiscale_sans)" = on ] && echo cronos || echo keep)/" \
    -e "s/^cinema=.*/cinema=$([ "$(setting uiscale_cinema)" = on ] && echo 1 || echo 0)/" \
    "$COMP/ui-scale/gw2-ui-scale.ini" | put "$1" 644
}
# The addon in or out of the game folder, as the setting says (another program's version.dll is
# never touched). The game's compatdb rules give version.dll its native-first order (rules_text).
sync_uiscale() {
  local dll
  game_state
  [ -n "$GAME_DIR" ] || return 0
  dll="$GAME_DIR/version.dll"
  if [ -f "$dll" ] && ! grep -aq "$UI_MARK" "$dll"; then
    [ "$(setting uiscale)" != on ] || warn "The game folder has another version.dll (another addon?); the larger interface stays off."
    return 0
  fi
  if [ "$(setting uiscale)" = on ]; then
    say "The larger interface: version.dll and gw2-ui-scale.ini in the game folder"
    run install -m 644 "$COMP/ui-scale/version.dll" "$dll"
    write_uiscale_ini "$GAME_DIR/gw2-ui-scale.ini"
  else
    if [ -f "$dll" ]; then run rm -f "$dll"; say "Removed the larger interface's version.dll"; fi
    if [ -f "$GAME_DIR/gw2-ui-scale.ini" ]; then run rm -f "$GAME_DIR/gw2-ui-scale.ini"; fi
    if [ -f "$GAME_DIR/gw2-ui-scale.log" ] && [ -z "$DRY" ]; then
      mkdir -p "$LOGS" && mv -f "$GAME_DIR/gw2-ui-scale.log" "$LOGS/gw2-ui-scale-$(date '+%Y%m%d-%H%M%S').log"
    fi
  fi
}

# --- arcdps (deltaconnected's addon; Settings › Interface): downloaded on request from
# deltaconnected.com (never hosted or changed by the app) into the game folder as d3d11.dll,
# where it loads first (the game's compatdb rules give d3d11 and dxgi a native-first order while
# one is there, rules_text) and passes the game's Direct3D 11 on to DXMT. It updates itself, so it
# is recognised by what it is, not by a hash: a PE
# whose export table has arcdps's extension API (addextension2) and that names arcdps. As dxgi.dll
# it counts too. Its settings (addons/arcdps/) stay when it goes. Another d3d11.dll or dxgi.dll
# (Nexus, ReShade...) is never touched: state foreign.
ARCDPS_URL=https://www.deltaconnected.com/arcdps/x64
[ -z "$ROOT" ] || ARCDPS_URL="${GW2_ON_MAC_ARCDPS_URL:-$ARCDPS_URL}"
ARCDPS_DLLS="d3d11.dll dxgi.dll"

pe32() { od -An -tu4 -j "$2" -N4 "$1" 2>/dev/null | tr -d ' ' || true; }   # <file> <offset>
pe16() { od -An -tu2 -j "$2" -N2 "$1" 2>/dev/null | tr -d ' ' || true; }
# pe_export_names <file>: the strings of a PE's export directory (the DLL's name and its export
# names, one a line); nothing for a file that isn't a PE or exports nothing
pe_export_names() {
  local f=$1 pe opt nsec optsz dd rva size s i va vs rs raw off=""
  [ "$(head -c 2 "$f" 2>/dev/null || true)" = MZ ] || return 0
  pe=$(pe32 "$f" 60)
  [ "$(bytes "$f" "${pe:-0}" 4 | od -An -tx1 | tr -d ' \n' || true)" = 50450000 ] || return 0
  nsec=$(pe16 "$f" $((pe + 6))) optsz=$(pe16 "$f" $((pe + 20))) opt=$((pe + 24))
  case "$(pe16 "$f" "$opt")" in
    523) dd=$((opt + 112)) ;;   # PE32+
    267) dd=$((opt + 96)) ;;    # PE32
    *) return 0 ;;
  esac
  rva=$(pe32 "$f" "$dd") size=$(pe32 "$f" $((dd + 4)))
  [ "${rva:-0}" -gt 0 ] && [ "${size:-0}" -gt 0 ] && [ "$size" -le 65536 ] || return 0
  s=$((opt + ${optsz:-0})) i=0
  while [ "$i" -lt "${nsec:-0}" ] && [ "$i" -lt 96 ]; do
    vs=$(pe32 "$f" $((s + 8))) va=$(pe32 "$f" $((s + 12))) rs=$(pe32 "$f" $((s + 16))) raw=$(pe32 "$f" $((s + 20)))
    vs=${vs:-0} va=${va:-0} rs=${rs:-0} raw=${raw:-0}
    [ "$vs" -ge "$rs" ] || vs=$rs
    if [ "$rva" -ge "$va" ] && [ "$rva" -lt $((va + vs)) ]; then off=$((raw + rva - va)); break; fi
    s=$((s + 40)) i=$((i + 1))
  done
  [ -n "$off" ] || return 0
  bytes "$f" "$off" "$size" | LC_ALL=C tr '\0' '\n' || true
}
# is_arcdps <file>
is_arcdps() {
  local names nl='
'
  [ -f "$1" ] || return 1
  names=$(pe_export_names "$1")
  case "$nl$names$nl" in *"${nl}addextension2${nl}"*) ;; *) return 1 ;; esac
  LC_ALL=C grep -aq arcdps "$1"
}
# arcdps_state: ARC (on: arcdps is in the game folder, as d3d11.dll or dxgi.dll; off; foreign:
# another program's d3d11.dll or dxgi.dll, ARC_FOREIGN its names; nogame), ARC_DLL (arcdps's file)
arcdps_state() {
  local n
  ARC=off ARC_FOREIGN="" ARC_DLL=""
  game_state
  [ -n "$GAME_DIR" ] || { ARC=nogame; return 0; }
  for n in $ARCDPS_DLLS; do
    [ -f "$GAME_DIR/$n" ] || continue
    if is_arcdps "$GAME_DIR/$n"; then ARC=on ARC_DLL=${ARC_DLL:+$ARC_DLL }$n; else ARC_FOREIGN=${ARC_FOREIGN:+$ARC_FOREIGN }$n; fi
  done
  [ "$ARC" = on ] || [ -z "$ARC_FOREIGN" ] || ARC=foreign
  return 0
}

# set arcdps on|off (cmd_set): only while no session runs or starts (the session's lock, as the
# registry writes take it)
set_arcdps() {
  local dir="$CACHE/downloads/arcdps" sum want got n gone=""
  arcdps_state
  [ "$ARC" != nogame ] || die "Guild Wars 2 is not installed yet: arcdps goes into its folder once it is."
  ! session_running || die "Quit Guild Wars 2 and Steam first: arcdps goes into or out of the game folder only while they are closed."
  registry_lock || die "A game session is starting. Try again once Guild Wars 2 and Steam have quit."
  if [ "$1" = off ]; then
    for n in $ARCDPS_DLLS; do
      if is_arcdps "$GAME_DIR/$n"; then run rm -f "$GAME_DIR/$n"; gone=${gone:+$gone and }$n; fi
    done
    registry_unlock
    if [ -n "$gone" ]; then
      say "arcdps removed from the game folder ($gone); its settings stay in addons/arcdps"
      echo "@done arcdps is off: its $gone is out of the game folder. Its settings stay in addons/arcdps for next time."
    elif [ -n "$ARC_FOREIGN" ]; then
      echo "@done arcdps isn't in the game folder. The other $ARC_FOREIGN there (another addon?) stays as it is."
    else
      echo "@done arcdps isn't in the game folder."
    fi
    return 0
  fi
  case "$ARC" in
    on) registry_unlock; echo "@done arcdps is already in the game folder ($ARC_DLL)."; return 0 ;;
    foreign) die "The game folder has another $ARC_FOREIGN (Nexus or another addon?). $APP_NAME leaves it alone, so it can't add arcdps: remove that file, or add arcdps through that addon." ;;
  esac
  if [ -n "$DRY" ]; then
    echo "[dry-run] download $ARCDPS_URL/d3d11.dll, check it against $ARCDPS_URL/d3d11.dll.md5sum, put it into $GAME_DIR/d3d11.dll"
    echo "@done arcdps would be in the game folder."
    return 0
  fi
  trap 'rm -rf "$CACHE/downloads/arcdps"; unlock' EXIT
  step "Downloading arcdps from deltaconnected.com"
  rm -rf "$dir" && mkdir -p "$dir"
  sum=$(curl -fsSL --connect-timeout 20 --max-time 60 --max-filesize 4096 "$ARCDPS_URL/d3d11.dll.md5sum" 2>>"$LOGFILE") ||
    die "The download of arcdps's checksum from $ARCDPS_URL/d3d11.dll.md5sum failed. Check your internet connection and try again."
  want=$(printf '%s\n' "$sum" | awk 'NR == 1 { print tolower($1) }')
  case "$want" in
    *[!0-9a-f]*|"") die "$ARCDPS_URL/d3d11.dll.md5sum is not a checksum (a captive portal, proxy or content filter in the way?). Try again." ;;
  esac
  [ ${#want} = 32 ] || die "$ARCDPS_URL/d3d11.dll.md5sum is not a checksum (a captive portal, proxy or content filter in the way?). Try again."
  download "$ARCDPS_URL/d3d11.dll" "$dir/d3d11.dll" arcdps
  got=$(md5 -q "$dir/d3d11.dll")
  [ "$got" = "$want" ] ||
    die "The arcdps download is not the file deltaconnected.com publishes: its md5 is $got, the published one $want. Something on the way changes it (a proxy, VPN, antivirus or content filter), or arcdps was updated meanwhile. Try again."
  is_arcdps "$dir/d3d11.dll" || die "The file from $ARCDPS_URL/d3d11.dll is not arcdps. Try again later."
  # (no session can start meanwhile: this holds its lock)
  arcdps_state
  [ "$ARC" = off ] || die "The game folder changed during the download ($ARC). Try again."
  run install -m 644 "$dir/d3d11.dll" "$GAME_DIR/.d3d11.dll.gw2om-new"
  run mv -f "$GAME_DIR/.d3d11.dll.gw2om-new" "$GAME_DIR/d3d11.dll"
  registry_unlock
  log "arcdps: $ARCDPS_URL/d3d11.dll into $GAME_DIR/d3d11.dll (md5 $got, sha256 $(sha256 "$GAME_DIR/d3d11.dll"))"
  echo "@done arcdps is in the game folder (d3d11.dll from deltaconnected.com). It loads the next time the game starts, and from then on it updates itself."
}

# --- Existing game files (install import): another Wine app's Guild Wars 2, cloned into the bottle
# (the same disk: APFS clonefile, instant and without extra space) or copied (another disk). The
# source is only read: its files, its bottle and its app stay as they are.

# Where a bottle keeps the game: Steam's default library, ArenaNet's default folder
GAME_RELS=("Program Files (x86)/Steam/steamapps/common/Guild Wars 2" "Program Files/Steam/steamapps/common/Guild Wars 2"
  "Program Files/Guild Wars 2" "Program Files (x86)/Guild Wars 2")

# The drive_c of every bottle other Wine apps keep in their known places: GW2 on Mac 0.1's own
# bottle (the stable line, in its own folder), CrossOver's bottles, Whisky's, app wrappers
# (Sikarugir, Kegworks, Wineskin, Porting Kit: <app>/Contents/...), Heroic's prefixes, ~/.wine;
# GameHub doesn't document where it keeps its bottles, so its folders are looked through (a few
# levels). Anything else: Choose folder… (check-game).
wine_places() {
  local d a
  for d in "$H/Library/Application Support/GW2 on Mac/bottle/drive_c" \
    "$H/Library/Application Support/CrossOver/Bottles"/*/drive_c \
    "$H/Library/Containers/com.isaacmarovitz.Whisky/Bottles"/*/drive_c \
    "$H/Library/Containers/com.isaacmarovitz.Whisky/Data/Bottles"/*/drive_c \
    "$H/Games/Heroic/Prefixes"/*/drive_c "$H/Games/Heroic/Prefixes"/*/*/drive_c "$H/.wine/drive_c"; do
    if [ -d "$d" ]; then echo "$d"; fi
  done
  for a in "$H/Applications"/*.app "$H/Applications"/*/*.app "$SYS_APPS"/*.app "$SYS_APPS"/*/*.app; do
    [ -d "$a/Contents" ] || continue
    for d in "$a/Contents/SharedSupport/prefix/drive_c" "$a/Contents/drive_c" "$a/Contents/Resources/drive_c"; do
      if [ -d "$d" ]; then echo "$d"; fi
    done
  done
  for d in "$H/Library/Application Support"/[Gg]ame[Hh]ub* "$H/Library/Containers"/*[Gg]ame[Hh]ub*; do
    if [ -d "$d" ]; then find "$d" -maxdepth 6 -type d -name drive_c -prune 2>/dev/null || true; fi
  done
}

# source_label <game dir>: the app it belongs to, as the window shows it ("CrossOver · Steam")
source_label() {
  local p=$1 r n
  case "$p" in
    "$H/Library/Application Support/GW2 on Mac/"*) echo "GW2 on Mac 0.1" ;;
    "$H/Library/Application Support/CrossOver/Bottles/"*)
      r=${p#"$H/Library/Application Support/CrossOver/Bottles/"}; echo "CrossOver · ${r%%/*}" ;;
    "$H/Library/Containers/com.isaacmarovitz.Whisky/"*)
      r=${p#*/Bottles/}; r=${r%%/*}
      n=$(plutil -extract name raw -o - "${p%%/Bottles/*}/Bottles/$r/Metadata.plist" 2>/dev/null || true)
      echo "Whisky · ${n:-$r}" ;;
    "$H/Games/Heroic/"*) echo "Heroic · $(basename "${p%%/drive_c/*}")" ;;
    "$H/.wine/"*) echo "Wine · ~/.wine" ;;
    *[Gg]ame[Hh]ub*) echo "GameHub · $(basename "${p%%/drive_c/*}")" ;;
    *.app/Contents/*) r=${p%%.app/Contents/*}; echo "Wrapper · $(basename "$r")" ;;
    *) echo "Folder · $(basename "$(dirname "$p")")" ;;
  esac
}

# game_ok <dir>: a complete Guild Wars 2 (its launcher, and a Gw2.dat with more than 1 GB)
game_ok() { [ -f "$1/Gw2-64.exe" ] && [ "$(stat -f %z "$1/Gw2.dat" 2>/dev/null || echo 0)" -gt 1000000000 ]; }
# game_route_of <game dir>: steam if Steam's record of it is there (steamapps/appmanifest_1284210.acf),
# else arenanet
game_route_of() { if [ -f "$1/../../appmanifest_$GW2_APPID.acf" ]; then echo steam; else echo arenanet; fi; }
folder_bytes() { find "$1" -type f -exec stat -f %z {} + 2>/dev/null | awk '{ s += $1 } END { printf "%.0f\n", s }'; }
volume_of() { local d=$1; while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done; stat -f %d "$d"; }
# the game folder is on the disk of the app's folder (it can be cloned)
same_volume() { [ -z "$IMPORT_COPY" ] && [ "$(volume_of "$1")" = "$(volume_of "$APPDIR")" ]; }
# settings_source <game dir>: the newest users/*/AppData/Roaming/Guild Wars 2 of its bottle that has
# the game's settings (Local.dat, GFXSettings.Gw2-64.exe.xml)
settings_source() {
  local c d f t best="" bt=0
  case "$1" in */drive_c/*) c="${1%%/drive_c/*}/drive_c" ;; *) return 1 ;; esac
  for d in "$c/users"/*/"AppData/Roaming/Guild Wars 2"; do
    for f in Local.dat GFXSettings.Gw2-64.exe.xml; do
      [ -f "$d/$f" ] || continue
      t=$(stat -f %m "$d/$f")
      if [ "$t" -gt "$bt" ]; then bt=$t; best=$d; fi
    done
  done
  [ -n "$best" ] || return 1
  echo "$best"
}
# game_dir_of <path>: the Guild Wars 2 folder at <path>, or in the bottle (or wrapper) at <path>
game_dir_of() {
  local p=${1:-} b rel
  [ -n "$p" ] && [ -d "$p" ] || return 1
  for b in "$p" "$p/Guild Wars 2" "$p/common/Guild Wars 2" "$p/steamapps/common/Guild Wars 2"; do
    if game_ok "$b"; then (cd "$b" && pwd -P); return 0; fi
  done
  for b in "$p" "$p/drive_c" "$p/Contents/SharedSupport/prefix/drive_c" "$p/Contents/drive_c"; do
    for rel in "${GAME_RELS[@]}"; do
      if game_ok "$b/$rel"; then (cd "$b/$rel" && pwd -P); return 0; fi
    done
  done
  return 1
}
# game_line <game dir>: what the window lists, tab-separated:
#   game <source> <route> <bytes> <same disk yes|no> <settings yes|no> <path>
game_line() {
  local d=$1
  case "$d/" in "$BOTTLE/"*) return 0 ;; esac
  printf 'game\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(source_label "$d")" "$(game_route_of "$d")" "$(folder_bytes "$d")" \
    "$(same_volume "$d" && echo yes || echo no)" "$(settings_source "$d" >/dev/null && echo yes || echo no)" "$d"
}

cmd_scan() {
  local c rel
  wine_places | while IFS= read -r c; do
    for rel in "${GAME_RELS[@]}"; do
      if game_ok "$c/$rel"; then game_line "$(cd "$c/$rel" && pwd -P)"; fi
    done
  done | awk -F'\t' '!seen[$NF]++'
  echo "@done scanned"
}

cmd_check_game() {
  local d
  d=$(game_dir_of "${1:-}") || { echo "@error This folder has no Guild Wars 2 in it: it needs Gw2-64.exe and a Gw2.dat of more than 1 GB."; exit 1; }
  case "$d/" in "$BOTTLE/"*) echo "@error That is $APP_NAME's own copy of the game."; exit 1 ;; esac
  game_line "$d"
  echo "@done $d"
}

# A Guild Wars 2 runs, in any Wine (its files may change while they are copied). In a sandbox only
# the sandbox's own count.
game_runs_anywhere() {
  local l
  l=$(ps -axww -o args= 2>/dev/null || true)
  printf '%s\n' "$l" | awk -v r="${ROOT:+$ROOT/}" 'tolower($0) ~ /gw2-64\.exe/ && (r == "" || index($0, r)) { f = 1 } END { exit !f }'
}

# import_game <source dir> <bottle's game dir>: the folder cloned (same disk) or copied (with a
# free-space check and progress). Left out, and named in LEFT: my own addon's files (version.dll
# with its mark, gw2-ui-scale.*), arcdps (d3d11.dll or dxgi.dll; addons are not cleared for this
# engine yet) and another program's d3d11.dll. Any other addon comes along as it is (ADDONS names
# them).
import_game() {
  local src=$1 dst=$2 total pid n out="" arc="" other=""
  total=$(folder_bytes "$src")
  LEFT=""
  if [ -f "$src/version.dll" ] && grep -aq "$UI_MARK" "$src/version.dll"; then
    out=" version.dll" LEFT=" The larger interface's version.dll stayed behind: this app has its own."
  fi
  for n in $ARCDPS_DLLS; do
    [ -f "$src/$n" ] || continue
    if is_arcdps "$src/$n"; then out="$out $n" arc=yes
    elif [ "$n" = d3d11.dll ]; then out="$out $n" other=yes
    fi
  done
  [ -z "$arc" ] || LEFT="$LEFT arcdps stayed behind. Turn it on in Settings once it is cleared for this engine."
  [ -z "$other" ] || LEFT="$LEFT Another program's d3d11.dll stayed behind."
  if [ -e "$dst" ]; then
    [ -z "$(ls -A "$dst" 2>/dev/null)" ] ||
      die "The game's bottle already has a Guild Wars 2 folder ($dst). Uninstall $APP_NAME first to use your own game files."
    run rmdir "$dst"
  fi
  if [ -n "$DRY" ]; then
    echo "[dry-run] $(same_volume "$src" && echo clone || echo copy) $src ($total bytes) to $dst"
    IMPORT_HOW=cloned ADDONS=""
    return
  fi
  run mkdir -p "$(dirname "$dst")"
  IMPORT_DST=$dst IMPORT_HOW=""
  if same_volume "$src"; then
    say "Cloning the game's files from $src: the same disk, so it takes no extra space"
    if run cp -Rpc "$src" "$dst" 2>>"$LOGFILE"; then
      IMPORT_HOW=cloned
    else
      log "cloning failed; copying instead"
      rm -rf "$dst"
    fi
  fi
  if [ -z "$IMPORT_HOW" ]; then
    local free
    free=$(free_kb)
    [ "$(( ${free:-0} * 1024 ))" -ge "$((total + 1000000000))" ] ||
      die "Not enough free disk space to copy the game's files: they need $(( (total + 999999999) / 1000000000 )) GB (and 1 GB to spare), $(( ${free:-0} / 1000000 )) GB are free."
    say "Copying the game's files from $src ($(( (total + 500000000) / 1000000000 )) GB, from another disk)"
    { printf '+ cp -Rp %q %q\n' "$src" "$dst"; } >>"$LOGFILE"
    cp -Rp "$src" "$dst" 2>>"$LOGFILE" &
    pid=$!
    FETCH_PID=$pid
    while kill -0 "$pid" 2>/dev/null; do
      echo "@progress Guild Wars 2 $(folder_bytes "$dst") $total"
      sleep 1
    done
    wait "$pid" || { FETCH_PID=; die "Copying the game's files failed (details in $LOGS/install.log)."; }
    FETCH_PID=
    IMPORT_HOW=copied
  fi
  echo "@progress Guild Wars 2 $total $total"
  for n in $out; do run rm -f "$dst/$n"; done
  run rm -f "$dst/gw2-ui-scale.ini" "$dst/gw2-ui-scale.log"
  chmod -R u+w "$dst"
  ADDONS=$( (cd "$dst" && ls -d ./*.dll addons bin64/d3d9.dll 2>/dev/null || true) | sed 's|^\./||' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  [ -z "$ADDONS" ] || say "Addons that came along with the game's files: $ADDONS ($APP_NAME leaves them as they are)"
  log "game files $IMPORT_HOW: $src -> $dst ($total bytes)${out:+; left out:$out}"
}

# The bottle's Windows user (upstream Wine names it after the Mac's user; CrossOver's engine said
# crossover)
bottle_user() {
  local u
  for u in "$BOTTLE/drive_c/users"/*; do
    [ -d "$u" ] || continue
    case "$(basename "$u")" in Public|public) continue ;; esac
    basename "$u"; return
  done
  id -un
}

# import_settings <source game dir>: the game's settings (Local.dat: options and the remembered
# login; GFXSettings.Gw2-64.exe.xml: graphics) from the source bottle's AppData into ours; any the
# bottle had already go to a backup folder next to them
import_settings() {
  local from to backup f
  SETTINGS_IMPORTED=no
  from=$(settings_source "$1") || { say "No game settings next to these files: the game starts with its defaults"; return 0; }
  to="$BOTTLE/drive_c/users/$(bottle_user)/AppData/Roaming/Guild Wars 2"
  say "Your game settings from $from"
  if [ -n "$DRY" ]; then echo "[dry-run] copy Local.dat and GFXSettings.Gw2-64.exe.xml to $to"; return 0; fi
  backup="$to/$APP_NAME backup $(date '+%Y-%m-%d %H%M%S')"
  run mkdir -p "$to"
  for f in GFXSettings.Gw2-64.exe.xml Local.dat; do
    [ -f "$from/$f" ] || continue
    if [ -f "$to/$f" ]; then run mkdir -p "$backup"; run mv -f "$to/$f" "$backup/$f"; fi
    run cp -p "$from/$f" "$to/$f"
    SETTINGS_IMPORTED=yes
  done
  if [ -d "$backup" ]; then say "The bottle's own game settings are kept in $backup"; fi
}

# install import, after the engine and the bottle: Steam (for Steam's files), the game's files and
# settings, then the finishing touches. Steam's record comes along with its files: Steam may check
# them at the first Play. If its record says the game isn't complete, Steam's install step follows
# as usual (it continues from the files).
install_imported() {
  local route=$1 src=$2 with_settings=$3 dst m="" how label
  label=$(source_label "$src")
  phase 3
  if [ "$route" = steam ]; then
    install_steam
    phase 4
    m="$src/../../appmanifest_$GW2_APPID.acf"
    dst="$STEAM_DIR/steamapps/common/$(acf "$m" installdir)"
    [ "$dst" != "$STEAM_DIR/steamapps/common/" ] || dst="$STEAM_DIR/steamapps/common/Guild Wars 2"
  else
    dst="$BOTTLE/drive_c/Program Files/Guild Wars 2"
  fi
  step "Your game files, from $label"
  import_game "$src" "$dst"
  if [ -n "$m" ]; then
    run cp -p "$m" "$STEAM_DIR/steamapps/appmanifest_$GW2_APPID.acf"
    IMPORT_ACF="$STEAM_DIR/steamapps/appmanifest_$GW2_APPID.acf"
  fi
  SETTINGS_IMPORTED=no
  if [ "$with_settings" = yes ]; then import_settings "$src"; fi
  if [ -z "$DRY" ]; then
    set_state route "$route"
    set_state origin import
    [ "$route" = steam ] || set_state game_dir "$dst"
  fi
  write_manifest
  game_state
  how="cloned from $label (no extra space)"
  [ "$IMPORT_HOW" != copied ] || how="copied from $label"
  if [ "$GAME" = yes ] || [ -n "$DRY" ]; then
    if [ "$route" = steam ]; then phase 5; else phase 4; fi
    step "Finishing touches"
    finish_touches
    IMPORT_DST="" IMPORT_ACF=""
    log "install import complete"
    echo "@done Guild Wars 2 is ready: its files were $how$([ "$SETTINGS_IMPORTED" = yes ] && echo ", with your game settings").$([ -z "$ADDONS" ] || echo " Addons that came along: $ADDONS; $APP_NAME leaves them as they are.")$LEFT$([ "$route" = steam ] && echo " Steam may check the files at the first Play.") Press Play."
  else
    step "Steam opens: sign in, and it brings Guild Wars 2 up to date"
    launch "$STEAM_EXE" "steam://install/$GW2_APPID"
    set_state stage waiting_game
    IMPORT_DST="" IMPORT_ACF=""
    log "install import: Steam's record of the game is not complete; waiting for Steam"
    echo "@done Your game files were $how.$LEFT Steam is starting: sign in, and it brings the game up to date; this window follows it."
  fi
}

# --- check-setup: ArenaNet's Gw2Setup-64.exe, checked without new tools (macOS's own openssl):
# a PE x86_64 executable with an Authenticode signature that is valid (the signer's signature over
# its signed attributes; their message digest over the SpcIndirectData content), covers this very
# file (its PE hash, recomputed here) and was made with a certificate issued to ArenaNet. The
# certificate chain ends in Windows' roots, which macOS doesn't have: it is not checked.

le32() { od -An -tu4 -j "$2" -N4 "$1" | tr -d ' '; }   # <file> <offset>
le16() { od -An -tu2 -j "$2" -N2 "$1" | tr -d ' '; }
bytes() { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null; }   # <file> <offset> <count>
setup_bad() { echo "@error $*"; exit 1; }
cmd_check_setup() {
  local f=${1:-} pe opt cs dd certoff certlen size t line o hl l alg want got md attrs sigline ok="" cert subject
  # (its pipes stop reading early on purpose: grep -m1, head -c)
  set +o pipefail
  [ -f "$f" ] || setup_bad "That file is not there."
  size=$(stat -f %z "$f")
  [ "$(head -c 2 "$f")" = MZ ] || setup_bad "This is not a Windows program."
  pe=$(le32 "$f" 60)
  [ "$(bytes "$f" "$pe" 4 | od -An -tx1 | tr -d ' \n')" = 50450000 ] || setup_bad "This is not a Windows program."
  [ "$(le16 "$f" $((pe + 4)))" = 34404 ] || setup_bad "This is not the 64-bit installer (Gw2Setup-64.exe)."
  opt=$((pe + 24))
  [ "$(le16 "$f" "$opt")" = 523 ] || setup_bad "This is not a 64-bit Windows program."
  cs=$((opt + 64))                    # CheckSum
  dd=$((opt + 112 + 4 * 8))           # the data directory's Certificate Table entry (PE32+)
  certoff=$(le32 "$f" "$dd")
  certlen=$(le32 "$f" $((dd + 4)))
  [ "$certoff" -gt 0 ] && [ "$certlen" -gt 8 ] && [ $((certoff + certlen)) -le "$size" ] ||
    setup_bad "This program is not signed. Download Gw2Setup-64.exe again from ArenaNet's site."
  t=$(mktemp -d "${TMPDIR:-/tmp}/gw2om-check.XXXXXX"); CHECK_TMP=$t
  trap 'rm -rf "$CHECK_TMP"' EXIT
  # WIN_CERTIFICATE: dwLength, wRevision, wCertificateType, then the PKCS#7 SignedData (DER)
  bytes "$f" $((certoff + 8)) $((certlen - 8)) >"$t/sig.der"
  /usr/bin/openssl asn1parse -inform DER -in "$t/sig.der" >"$t/asn1.txt" 2>/dev/null ||
    setup_bad "The signature of this file can't be read. Download Gw2Setup-64.exe again from ArenaNet's site."
  # "<offset> <header length> <length>" of an asn1parse line
  pos() { echo "$1" | sed -n 's/^ *\([0-9]*\):d=[0-9]* *hl=\([0-9]*\) *l= *\([0-9]*\).*/\1 \2 \3/p'; }
  # the SpcIndirectDataContent: its digest algorithm and the PE hash it carries
  line=$(grep -n ':1.3.6.1.4.1.311.2.1.4$' "$t/asn1.txt" | head -1 | cut -d: -f1)
  [ -n "$line" ] || setup_bad "This is not an Authenticode signature."
  # shellcheck disable=SC2046 # (pos prints three numbers, split on purpose)
  set -- $(pos "$(sed -n "$((line + 2))p" "$t/asn1.txt")"); o=$1 hl=$2 l=$3
  bytes "$t/sig.der" $((o + hl)) "$l" >"$t/spc.bin"
  alg=$(sed -n "$((line + 2)),\$p" "$t/asn1.txt" | grep -m1 -oE ':(sha1|sha256|sha384|sha512)$' | tr -d :)
  want=$(sed -n "$((line + 2)),\$p" "$t/asn1.txt" | grep -m1 'OCTET STRING' | sed 's/.*\[HEX DUMP\]://' | tr 'A-F' 'a-f')
  [ -n "$alg" ] && [ -n "$want" ] || setup_bad "This is not an Authenticode signature."
  # this file's PE hash: all of it but the checksum, the certificate table entry and the table
  got=$( { head -c "$cs" "$f"; bytes "$f" $((cs + 4)) $((dd - cs - 4))
           tail -c +$((dd + 8 + 1)) "$f" | head -c $((certoff - dd - 8)); } | shasum -a "${alg#sha}" | cut -d' ' -f1)
  [ "$want" = "$got" ] || setup_bad "This file was changed after it was signed. Download Gw2Setup-64.exe again from ArenaNet's site."
  # the signer's signed attributes (the first SignerInfo's [0], the one around the first
  # messageDigest): their messageDigest must be the digest of the SpcIndirectData content, and the
  # signature is over them (as a SET)
  attrs=$(awk '{ d = $1; sub(/^.*d=/, "", d); d += 0 }
    /cont \[ 0 \]/ { c[d] = $0 }
    /:messageDigest$/ { print c[d - 2]; exit }' "$t/asn1.txt")
  [ -n "$attrs" ] || setup_bad "The signature has no signed attributes."
  # shellcheck disable=SC2046
  set -- $(pos "$attrs"); o=$1 hl=$2 l=$3
  { printf '\061'; bytes "$t/sig.der" $((o + 1)) $((hl + l - 1)); } >"$t/attrs.der"
  md=$(grep -A2 ':messageDigest$' "$t/asn1.txt" | grep -m1 'OCTET STRING' | sed 's/.*\[HEX DUMP\]://' | tr 'A-F' 'a-f')
  [ "$md" = "$(shasum -a "${alg#sha}" "$t/spc.bin" | cut -d' ' -f1)" ] || setup_bad "The signature of this file is not valid."
  # the signature: the OCTET STRING after the signed attributes' end
  sigline=$(awk -v end=$((o + hl + l)) '{ split($1, a, ":"); if (a[1] + 0 >= end && /OCTET STRING/) { print; exit } }' "$t/asn1.txt")
  # shellcheck disable=SC2046
  set -- $(pos "$sigline"); bytes "$t/sig.der" $(($1 + $2)) "$3" >"$t/sig.bin"
  # the certificate whose key made it, and its organisation
  /usr/bin/openssl pkcs7 -inform DER -in "$t/sig.der" -print_certs >"$t/certs.pem" 2>/dev/null || true
  awk -v d="$t" '/-----BEGIN CERTIFICATE-----/ { n++ } n { print > (d "/cert" n ".pem") }' "$t/certs.pem"
  for cert in "$t"/cert*.pem; do
    [ -f "$cert" ] || continue
    /usr/bin/openssl x509 -in "$cert" -pubkey -noout >"$t/key.pem" 2>/dev/null || continue
    if /usr/bin/openssl dgst -"$alg" -verify "$t/key.pem" -signature "$t/sig.bin" "$t/attrs.der" >/dev/null 2>&1; then
      ok=$cert; break
    fi
  done
  [ -n "$ok" ] || setup_bad "The signature of this file is not valid. Download Gw2Setup-64.exe again from ArenaNet's site."
  subject=$(/usr/bin/openssl x509 -in "$ok" -noout -subject 2>/dev/null | sed -n 's/.*O *= *\([^,/]*\).*/\1/p' | sed 's/ *$//')
  case "$subject" in
    *"$SIGNER"*) echo "@done $(basename "$f") · signed by $subject" ;;
    *) setup_bad "This file is signed by ${subject:-someone else}, not by $SIGNER. Use Gw2Setup-64.exe from ArenaNet's official site." ;;
  esac
}

# --- Status

status() {
  local free b l installed=no
  echo "version=$VERSION"
  echo "engine=$ENGINE_NAME"
  echo "engine_title=$ENGINE_TITLE"
  echo "engine_wine=$ENGINE_WINE"
  echo "engine_fex=$ENGINE_FEX"
  echo "engine_dxmt=$ENGINE_DXMT"
  echo "root=${ROOT:-/}"
  echo "app_dir=$APPDIR"
  echo "arch=$(uname -m)"
  echo "macos=$(macos_version)"
  echo "macos_min=$MACOS_MIN"
  echo "macos_ok=$(macos_ok && echo yes || echo no)"
  [ -f "$MANIFEST" ] && engine_ok && [ -f "$BOTTLE/system.reg" ] && installed=yes
  echo "installed=$installed"
  echo "installed_version=$(json_get "$MANIFEST" version)"
  echo "engine_installed=$(engine_ok && echo yes || echo no)"
  echo "graphics=$(graphics_state)"
  # (the engine's loader is a Game Mode app: nothing for the app to set up or switch)
  echo "gamemode=engine"
  echo "route=$(state route)"
  echo "origin=$(state origin)"
  echo "steam=$([ -f "$STEAM_DIR/steam.exe" ] && echo yes || echo no)"
  game_state
  echo "game=$GAME"
  echo "game_dir=$GAME_DIR"
  echo "game_bytes=$GAME_BYTES"
  echo "game_total=$GAME_TOTAL"
  echo "stage=$(state stage)"
  free=$(free_kb)
  echo "disk_free=$(( ${free:-0} * 1024 ))"
  echo "disk_needed=$DISK_NEEDED"
  l=$(proc_list)
  b=$(busy_of "$l")
  echo "busy=$b"
  case "$b" in none) echo "busy_detail=" ;; *) echo "busy_detail=$(proc_names "$l" "$b")" ;; esac
  # (every Wine process runs as the engine's loader, Steam's too: the window finds the game by pid)
  echo "game_pid=$(printf '%s\n' "$l" | awk '$1 == "game" { print $2; exit }')"
  echo "uiscale=$(setting uiscale)"
  arcdps_state
  echo "arcdps=$([ "$ARC" = on ] && echo on || echo off)"
  echo "arcdps_state=$ARC"
  echo "arcdps_foreign=$ARC_FOREIGN"
  echo "session=$(session_live)"
}

settings() {
  local k n
  echo "installed=$([ -f "$MANIFEST" ] && echo yes || echo no)"
  if session_running; then echo "running=yes"; else echo "running=no"; fi
  echo "route=$(state route)"
  for k in $SETTING_KEYS; do
    echo "$k=$(setting "$k")"
    echo "${k}_state=$(setting_state "$k")"
    n=$(setting_note "$k")
    [ -z "$n" ] || echo "${k}_note=$n"
  done
  echo "arcdps_note=$(setting_note arcdps)"
  echo "uiscale_addon=$(uiscale_state)"
  arcdps_state
  echo "arcdps=$([ "$ARC" = on ] && echo on || echo off)"
  echo "arcdps_state=$ARC"
  echo "arcdps_foreign=$ARC_FOREIGN"
  echo "cpus=$CPU_MAX"
  echo "steam_login=$(steam_remembers_login && echo yes || echo no)"
}

cmd_set() {
  local key="${1:-}" value="${2:-}"
  # (arcdps: not kept in settings.conf; the game folder says whether it is on, arcdps_state)
  { [ "$key" = arcdps ] && { [ "$value" = on ] || [ "$value" = off ]; }; } || setting_valid "$key" "$value" ||
    { echo "@error Unknown setting: $key=$value"; exit 2; }
  case "$(setting_state "$key")" in off:*) echo "@error $(setting_state "$key" | cut -c5-)"; exit 1 ;; esac
  [ -f "$MANIFEST" ] || die "$APP_NAME is not installed."
  open_log
  log "---- set $key=$value"
  lock
  trap 'unlock' EXIT
  if [ "$key" = arcdps ]; then set_arcdps "$value"; return; fi
  write_settings "$key" "$value"
  case "$key" in
    fpscap) write_dxmt_conf ;;
    uiscale|uiscale_size|uiscale_sans|uiscale_cinema) sync_uiscale ;;
    retina) apply_registry ;;
  esac
  # (each process reads the rules and dxmt.conf when it starts; the environment and the registry
  # are the session's, fixed while Steam runs)
  if session_running && in_list "$key" "ncpu debug retina"; then
    echo "@done $key=$value. It takes effect the next time the game starts after Steam has quit."
  else
    echo "@done $key=$value. It takes effect the next time the game starts."
  fi
}

# lock: the install lock (no two installs, repairs, uninstalls, settings changes or engine
# updates at once): the folder .lock with its owner's pid. Creating it and publishing the pid,
# taking over one whose owner is gone (killed, the Mac switched off) and removing it all happen
# under the claim: Logs/.lock-claim, a kernel lock (the session helper's flock) that every contender
# must get, held only for those few steps and released before anything else runs, so no child
# (Wine, Steam) ever inherits it. unlock removes .lock only for its owner.
LOCK_CLAIM="$LOGS/.lock-claim"     # (in the logs folder, which uninstall keeps: the same file for good)
LOCK_WAIT=5                       # seconds a contender waits for the claim (held only briefly)
[ -z "$ROOT" ] || LOCK_WAIT="${GW2_ON_MAC_LOCK_WAIT:-$LOCK_WAIT}"
claim() {   # <seconds>: the claim on fd 6, waiting up to that long
  local i=0 n=$(( $1 * 10 ))
  exec 6>>"$LOCK_CLAIM"
  until "$LOCKER" take 6 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt "$n" ] || { exec 6>&-; return 1; }
    sleep 0.1
  done
}
unclaim() { exec 6>&-; }
lock() {
  local p age
  [ -n "$DRY" ] && return
  mkdir -p "$APPDIR" "$LOGS"
  if [ ! -x "$LOCKER" ]; then
    # (without the helper: no claim, so no takeover either)
    mkdir "$APPDIR/.lock" 2>/dev/null || die "Another $APP_NAME install, repair or uninstall is running."
    echo $$ >"$APPDIR/.lock/pid"
    return 0
  fi
  claim "$LOCK_WAIT" || die "Another $APP_NAME install, repair or uninstall is running."
  if mkdir "$APPDIR/.lock" 2>/dev/null; then
    echo $$ >"$APPDIR/.lock/pid"
    unclaim
    test_pause locked
    return 0
  fi
  p=$(cat "$APPDIR/.lock/pid" 2>/dev/null || true)
  test_pause lock-owner-read
  age=$(( $(date +%s) - $(stat -f %m "$APPDIR/.lock" 2>/dev/null || date +%s) ))
  # (gone: its pid no longer runs, which it can't while it holds .lock (unlock needs the claim);
  # or no pid after a minute: its owner killed right after mkdir)
  if [ -d "$APPDIR/.lock" ] && { { [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; } || { [ -z "$p" ] && [ "$age" -gt 60 ]; }; }; then
    test_pause lock-stale-checked
    log "taking over the install lock left by ${p:-a process} that is gone"
    echo $$ >"$APPDIR/.lock/pid"
    unclaim
    test_pause locked
    return 0
  fi
  unclaim
  die "Another $APP_NAME install, repair or uninstall is running."
}
unlock() {
  [ "$(cat "$APPDIR/.lock/pid" 2>/dev/null || true)" = "$$" ] || return 0
  if [ -x "$LOCKER" ]; then
    # (if the claim can't be had, .lock stays: once this process is gone, it is taken over)
    claim 20 || { log "the install lock's claim stayed busy; .lock is left for a takeover"; return 0; }
  fi
  [ "$(cat "$APPDIR/.lock/pid" 2>/dev/null || true)" != "$$" ] || rm -rf "$APPDIR/.lock"
  unclaim
}

write_manifest() {
  put "$MANIFEST" 644 <<EOF
{
  "app": "$APP_NAME",
  "version": "$VERSION",
  "installed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "route": "$(state route)",
  "engine": "$ENGINE_NAME",
  "engine_sha256": "$ENGINE_SHA256",
  "engine_wine": "$ENGINE_WINE",
  "engine_fex": "$ENGINE_FEX",
  "engine_dxmt": "$ENGINE_DXMT",
  "loader_sha256": "$ENGINE_LOADER_SHA256",
  "ntdll_sha256": "$ENGINE_NTDLL_SHA256",
  "dxmt_d3d11_sha256": "$ENGINE_D3D11_SHA256",
  "winemetal_sha256": "$ENGINE_WINEMETAL_SHA256",
  "app_files": ["$(echo $APP_FILES | sed 's/ /", "/g')"],
  "logs": "$LOGS",
  "caches": ["$CACHE"]
}
EOF
}

# --- Install

on_install_exit() {
  local st=$? c
  if [ $st -ne 0 ] && [ -z "$DRY" ]; then
    if [ -n "${FETCH_PID:-}" ]; then kill "$FETCH_PID" 2>/dev/null || true; fi
    stop_wine >/dev/null 2>&1 || true
    # all or nothing: what this run created goes again (an earlier engine or bottle stays)
    for c in $CREATED; do
      if [ -e "$APPDIR/$c" ]; then rm -rf "${APPDIR:?}/$c"; log "removed $c (install failed)"; fi
    done
    # the game's files this run cloned or copied (and Steam's record of them), if the bottle stays
    if [ -n "${FETCH_PID:-}" ]; then wait "$FETCH_PID" 2>/dev/null || true; fi
    if [ -n "${IMPORT_DST:-}" ] && [ -e "$IMPORT_DST" ]; then rm -rf "$IMPORT_DST"; log "removed $IMPORT_DST (install failed)"; fi
    if [ -n "${IMPORT_ACF:-}" ] && [ -e "$IMPORT_ACF" ]; then rm -f "$IMPORT_ACF"; fi
    rm -rf "$APPDIR"/*.new 2>/dev/null || true
    log "install failed (status $st)"
  fi
  unlock
}

# preflight [import]: (an import checks the space its copy needs itself)
preflight() {
  [ "$(uname -m)" = arm64 ] || die "$APP_NAME needs a Mac with Apple silicon."
  macos_ok || die "$APP_NAME needs macOS $MACOS_MIN or later for its Wine engine. This Mac has macOS $(macos_version). Update macOS in System Settings › General › Software Update, then try again."
  check_not_running
  local avail
  avail=$(free_kb)
  [ "${avail:-0}" -gt 3000000 ] || die "Not enough free disk space (the engine and Steam need about 3 GB, the game about 75 GB)."
  [ "${1:-}" = import ] || [ "$((${avail:-0} * 1024))" -ge "$DISK_NEEDED" ] || warn "Only $(( ${avail:-0} / 1000000 )) GB free: Guild Wars 2 needs about 75 GB."
}

# The bottle: created once (wineboot), then its settings (registry, dxmt.conf)
install_bottle() {
  if [ ! -f "$BOTTLE/system.reg" ]; then
    say "Creating the game's bottle (wineboot, about a minute)"
    run rm -rf "$BOTTLE"
    run mkdir -p "$BOTTLE"
    CREATED="$CREATED bottle"
    # (no Mono or Gecko: the engine's built-in rules leave both out for every process)
    wine_do wineboot --init || { stop_wine; die "Wine could not create the bottle (details in $LOGS/install.log)."; }
    stop_wine
    [ -n "$DRY" ] || [ -f "$BOTTLE/user.reg" ] || die "Wine did not create the bottle (details in $LOGS/install.log)."
  else
    say "The game's bottle is there (the game and its settings in it are kept)"
  fi
  [ -f "$SETTINGS" ] || CREATED="$CREATED settings.conf"
  write_settings
  write_dxmt_conf
  say "Bottle settings: Retina mode $(setting retina)"
  apply_registry
}

install_steam() {
  if [ -f "$STEAM_DIR/steam.exe" ]; then
    say "Steam is installed in the bottle"
    return
  fi
  local setup="$CACHE/downloads/SteamSetup.exe"
  step "Steam, from Valve"
  download "$STEAM_SETUP_URL" "$setup" "SteamSetup.exe"
  say "Installing Steam (Valve's installer, silently)"
  wine_do "$setup" /S || { stop_wine; die "Valve's Steam installer failed (details in $LOGS/install.log)."; }
  wait_wine
  [ -n "$DRY" ] || [ -f "$STEAM_DIR/steam.exe" ] || die "Steam's installer ended without installing Steam (details in $LOGS/install.log)."
}

# A new session's logs start afresh; the 4 before stay as <log>.1-.4 (Collect Logs, the session
# report's --compare)
rotate_logs() {
  local f i
  for f in wine.log Gw2-64_d3d11.log; do
    [ -s "$LOGS/$f" ] || continue
    for i in 3 2 1; do [ ! -f "$LOGS/$f.$i" ] || mv -f "$LOGS/$f.$i" "$LOGS/$f.$((i + 1))"; done
    mv -f "$LOGS/$f" "$LOGS/$f.1"
  done
}

# launch <program> <args...>: a program in the bottle with the game's environment and its compatdb
# rules (written first), detached; the session's environment and rules go to logs/session.env
# (Collect Logs, the session report)
launch() {
  local e
  game_env
  write_rules
  if [ -n "$DRY" ]; then
    echo "[dry-run] environment:"; for e in "${E[@]}"; do printf '[dry-run]   %s\n' "$e"; done
    echo "[dry-run] wine $*"
    return
  fi
  wine_allowed
  mkdir -p "$LOGS"
  if ! session_running; then
    rotate_logs
    { echo "STARTED=$(date '+%F %T')"; echo "APP=$VERSION"; echo "ROUTE=$(state route)"
      echo "ENGINE=$ENGINE_NAME"; echo "ENGINE_WINE=$ENGINE_WINE"; echo "ENGINE_FEX=$ENGINE_FEX"; echo "ENGINE_DXMT=$ENGINE_DXMT"
      for k in $SETTING_KEYS; do echo "SETTING_$k=$(setting "$k")"; done
      printf '%s\n' "${E[@]}"
      sed 's/^/RULE=/' "$RULES"; } >"$LOGS/session.env"
    printf '%s\n' "${E[@]}" | shasum | cut -c1-12 >"$LOGS/session.key"
  fi
  echo "=== $(date '+%F %T') $*" >>"$LOGS/wine.log"
  ( cd "$BOTTLE" && env -u WINELOADER -u WINESERVER -u WINEDLLPATH -u DYLD_FALLBACK_LIBRARY_PATH "${COMPATDB_UNSET[@]}" "${E[@]}" \
      nohup "$ENG/bin/wine" "$@" </dev/null >>"$LOGS/wine.log" 2>&1 9>&- & )
  log "started: $*"
}

# --- The session's watcher (watch-session)
#
# Play records the session in $SESSION and starts watch-session detached (nohup: it outlives the
# app's window, which "Quit the app after launching" closes). The watcher follows the session
# through proc_list (only this engine's processes): it waits for Gw2-64.exe, then for its exit and
# a grace, and then, if Play started Steam itself in the background with Quit Steam when the game
# quits on, asks Steam to quit (steam.exe -shutdown), with wineserver -k for this bottle as the
# fallback. Steam that already ran, or whose window showed, is left alone. Everything goes to
# install.log under "---- session".
#
# One writer: Play writes the session's first version while it holds the lock (before the
# watcher exists); after that only the watcher writes it. Others ask it, by a line appended to
# $SESSION_REQ, which it applies in order at its next look (and counts in `requests`):
#   join <steam_before> <steam_window> <quit_steam>   a Play that joins the running session (while
#                  Steam starts the game, or in the grace after it quit): the watcher waits for
#                  the game again; if no Steam ran before that Play, the session's Steam is that
#                  Play's (its window and decision). Refused once Steam is quitting.
#   shown          Steam's window was brought up (Show Steam): Steam stays open after the game
# Who decides about Steam: Play, from proc_list before it starts Steam. The bottle's Steam starts
# only through Play (which refuses while the game runs and says in its join whether Steam ran
# before it), so a steam.exe that is replaced without a request is Steam restarting itself (after
# an update) and stays the session's.
#
# The keys (lane B's session-status reads them too):
#   route          steam|arenanet
#   started_steam  yes: no Steam of the bottle ran before Play
#   steam_window   hidden (-silent) | shown (Steam's window; empty on the ArenaNet route)
#   quit_steam     yes: the watcher quits Steam after the game
#   watcher_pid    the watcher's pid
#   stage          waiting_game|playing|grace|closing_steam|done
#   started, game_started, game_ended, updated   seconds since 1970
#   replay         how many Plays joined the session
#   requests       how many requests the watcher has applied (or refused)
#   result         at done: quit, killed (wineserver -k), left_running, steam_already_gone,
#                  timeout, steam_gone (Steam quit before the game appeared), no_game (ArenaNet:
#                  nothing started), uninstalled, ended (stopped otherwise)
SESSION_KEYS="route started_steam steam_window quit_steam watcher_pid stage started game_started game_ended replay requests updated result"
session_get() { sed -n "s/^$1=//p" "$SESSION" 2>/dev/null | tail -1 || true; }   # (no session yet: empty)
# session_set <key> <value> [<key> <value>...]: changes those keys (and updated), atomically (only
# the lock's holder calls it)
session_set() {
  local k v new
  [ -d "$APPDIR" ] || return 0
  new="updated=$(date +%s)"
  while [ $# -ge 2 ]; do new="$new
$1=$2"; shift 2; done
  { for k in $SESSION_KEYS; do
      case "
$new" in
        *"
$k="*) v=$(printf '%s\n' "$new" | sed -n "s/^$k=//p" | tail -1) ;;
        *) v=$(session_get "$k") ;;
      esac
      echo "$k=$v"
    done; } >"$SESSION.new.$$" 2>/dev/null && mv -f "$SESSION.new.$$" "$SESSION" 2>/dev/null || rm -f "$SESSION.new.$$"
}
# session_request <request...>: appended for the watcher (one short line: a single write); prints
# its number
session_request() { echo "$*" >>"$SESSION_REQ"; wc -l <"$SESSION_REQ" | tr -d ' '; }
# has_kind <kind> <proc_list output>
has_kind() { case "
$2" in *"
$1 "*) return 0 ;; esac; return 1; }
# steam_decision <route> <started_steam> <steam_window>: quit_steam
steam_decision() {
  [ "$1" = steam ] && [ "$2" = yes ] && [ "$3" = hidden ] && [ "$(setting quitsteam)" = on ] && echo yes || echo no
}

# The session's lock: a kernel lock (flock) on the file $WATCH_LOCK, taken on file descriptor 9
# by the app's own helper (helpers/sessionlock; bash has no flock). The lock belongs to the open
# file, so the shell keeps it after the helper exits, the watcher inherits it from Play (the
# handoff), and the kernel releases it when the last holder exits: no stale lock to recover. Wine
# never gets fd 9 (launch: 9>&-).
LOCKER="$RES/helpers/sessionlock"
# lock9: takes the lock on fd 9 (open on $WATCH_LOCK), without waiting
lock9() { "$LOCKER" take 9 2>/dev/null; }
# open_lock: fd 9 on the lock file (one left as a folder by an earlier build goes)
open_lock() { [ ! -d "$WATCH_LOCK" ] || rm -rf "$WATCH_LOCK"; exec 9>>"$WATCH_LOCK"; }
# lock_held: another process holds the lock
lock_held() {
  [ -f "$WATCH_LOCK" ] || return 1
  "$LOCKER" held "$WATCH_LOCK" 2>/dev/null
}
# watcher_proc <pid>: a running watch-session
watcher_proc() { [ -n "$1" ] && ps -p "$1" -o command= 2>/dev/null | grep -q 'gw2om\.sh watch-session'; }
# watcher_alive: the session's watcher runs (the lock is held and the session names it)
watcher_alive() { lock_held && watcher_proc "$(session_get watcher_pid)"; }
# stop_watcher: ends the session's watcher (uninstall) and waits for it
stop_watcher() {
  local p i=0
  # (a watcher that has just started writes its pid first)
  while lock_held && ! watcher_proc "$(session_get watcher_pid)" && [ $i -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  p=$(session_get watcher_pid)
  watcher_proc "$p" || return 0
  if [ -n "$DRY" ]; then echo "[dry-run] stop the session's watcher (pid $p)"; return 0; fi
  kill "$p" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$p" 2>/dev/null || break; sleep 0.2; done
  log "session: stopped its watcher (pid $p)"
}

# join_session <steam_before> <steam_window> <quit_steam>: Play joins the running session and waits
# for the watcher to apply its join: 0 joined, 1 refused (Steam is quitting), 2 the lock is free
# (Play takes the session itself), 3 no answer (Play doesn't start: fail closed)
join_session() {
  local n h i=0 lim
  # (the watcher looks every WATCH_POLL seconds)
  lim=$(awk -v p="$WATCH_POLL" 'BEGIN { print int((p * 3 + 3) * 10) }')
  # the session's watcher must run (a Play that has just taken the lock is still writing the
  # session and emptying the requests; a watcher that is done is about to release it)
  until watcher_proc "$(session_get watcher_pid)" && [ "$(session_get stage)" != "done" ]; do
    lock_held || return 2
    i=$((i + 1))
    [ $i -lt "$lim" ] || return 3
    sleep 0.1
  done
  n=$(session_request join "$@")
  i=0
  while :; do
    h=$(session_get requests)
    if [ "${h:-0}" -ge "$n" ]; then
      case "$(session_get stage)" in closing_steam|done) return 1 ;; *) return 0 ;; esac
    fi
    lock_held || return 2
    i=$((i + 1))
    [ $i -lt "$lim" ] || return 3
    sleep 0.1
  done
}

# --- The watcher's own steps (it holds the lock)

# watch_stage <stage> [<key> <value>...]
watch_stage() { STAGE=$1; shift; session_set stage "$STAGE" "$@"; }

# apply_requests: the requests appended since the last look, in order
apply_requests() {
  local n h line
  n=$( { wc -l <"$SESSION_REQ" 2>/dev/null || echo 0; } | tr -d ' ')
  h=$REQS
  [ "${n:-0}" -gt "$h" ] || return 0
  while [ "$h" -lt "$n" ]; do
    h=$((h + 1))
    line=$(sed -n "${h}p" "$SESSION_REQ")
    # shellcheck disable=SC2086
    set -- $line
    case "$STAGE:${1:-}" in
      closing_steam:*|done:*) log "session: refused (Steam is quitting): $line" ;;
      *:join)
        JOINS=$((JOINS + 1)) JOINED=$(date +%s)
        if [ "${2:-}" = no ]; then
          session_set started_steam yes steam_window "${3:-}" quit_steam "${4:-no}"
          log "session: Play joined the session and started Steam (steam_window=${3:-} quit_steam=${4:-no})"
        else
          log "session: Play joined the session (Steam was running)"
        fi ;;
      *:shown)
        session_set steam_window shown quit_steam no
        log "session: Steam's window was brought up; Steam stays open after the game" ;;
      *) log "session: unknown request: $line" ;;
    esac
  done
  REQS=$h
  session_set requests "$h" replay "$JOINS"
}

# watch_exit: the watcher's end, however it ends (it holds the lock until it has exited)
watch_exit() {
  # (after an uninstall it writes nothing: the app's folder is going)
  [ "$STAGE" = "done" ] || [ "${WATCH_RESULT:-}" = uninstalled ] || watch_stage "done" result "${WATCH_RESULT:-ended}"
  log "session: done (${WATCH_RESULT:-ended})"
}

# watch_poll: proc_list into WL after a pause, and the requests; false once the app's install is
# gone
watch_poll() {
  sleep "$WATCH_POLL"
  [ -f "$MANIFEST" ] || { WATCH_RESULT=uninstalled; log "session: $APP_NAME was uninstalled; stopping"; return 1; }
  WL=$(proc_list)
  apply_requests
}

# watch-session [--handoff]: Play starts it with --handoff (it inherits Play's lock on fd 9); by
# hand, it takes the lock or says another watcher follows the session
cmd_watch_session() {
  local i start now last ended back route quit why at_start
  open_log
  if [ -n "$DRY" ]; then echo "[dry-run] watch-session"; return 0; fi
  if [ "${1:-}" = --handoff ]; then
    lock9 || { log "session: the watcher (pid $$) was not handed the session's lock"; return 0; }
  else
    [ -f "$SESSION" ] && [ -x "$LOCKER" ] || { echo "@done No session to follow."; return 0; }
    open_lock
    lock9 || { echo "@done Another watcher follows this session (pid $(session_get watcher_pid))."; return 0; }
    case "$(session_get stage)" in ''|done) echo "@done No session to follow."; return 0 ;; esac
  fi
  WATCH_RESULT="" STAGE=$(session_get stage) JOINS=$(session_get replay) REQS=$(session_get requests) JOINED=0
  JOINS=${JOINS:-0} REQS=${REQS:-0}
  trap watch_exit EXIT
  trap 'exit 143' TERM INT
  route=$(session_get route)
  start=$(date +%s)
  log "---- session $VERSION route=$route started_steam=$(session_get started_steam) steam_window=$(session_get steam_window) quit_steam=$(session_get quit_steam) (watcher pid $$)"
  watch_stage waiting_game watcher_pid $$

  while :; do
    # 1. Guild Wars 2 starts (Steam may update itself and sign in first; a Play that joins starts
    # the wait again). Steam and the bottle's wineserver gone for the grace (Steam restarts itself
    # after an update) without the game means Steam was closed: left as it is.
    last=$start
    while :; do
      watch_poll || return 0
      now=$(date +%s)
      [ "$JOINED" -le "$start" ] || { start=$JOINED; last=$JOINED; }
      has_kind game "$WL" && break
      if has_kind steam "$WL" || has_kind session "$WL"; then last=$now; fi
      if [ $((now - last)) -ge "$WATCH_GRACE" ]; then
        if [ "$route" = steam ]; then
          WATCH_RESULT=steam_gone; log "session: Steam is not running and Guild Wars 2 did not start (Steam was closed or did not start); nothing to quit"
        else
          WATCH_RESULT=no_game; log "session: Guild Wars 2's launcher did not start or quit before the game"
        fi
        return 0
      fi
      if [ $((now - start)) -ge "$WATCH_TIMEOUT" ]; then
        WATCH_RESULT=timeout
        log "session: Guild Wars 2 did not start within $((WATCH_TIMEOUT / 60)) minutes ($WATCH_TIMEOUT s); Steam is left running"
        return 0
      fi
    done

    # 2. The game runs, until it quits and doesn't start again within the grace
    at_start=$JOINS
    watch_stage playing game_started "$now" game_ended ""
    log "session: Guild Wars 2 started ($((now - start)) s after Play)"
    while :; do
      while has_kind game "$WL"; do watch_poll || return 0; done
      ended=$(date +%s)
      watch_stage grace game_ended "$ended"
      log "session: Guild Wars 2 quit; waiting $WATCH_GRACE s in case it starts again (its patcher, a restart)"
      back=no
      while [ $(( $(date +%s) - ended )) -lt "$WATCH_GRACE" ]; do
        watch_poll || return 0
        if has_kind game "$WL"; then back=yes; break; fi
      done
      [ "$back" = yes ] || break
      at_start=$JOINS   # (a Play that joined in the grace: this is its game)
      watch_stage playing game_ended ""
      log "session: Guild Wars 2 started again within the grace"
    done

    # 3. The decision (the requests up to now applied): a Play that joined after the game started
    # means waiting for its game; else Steam quits if Play started it in the background and the
    # setting is (still) on, or is left alone. A join after this is refused.
    apply_requests
    if [ "$JOINS" -gt "$at_start" ]; then
      start=$(date +%s)
      watch_stage waiting_game
      log "session: Play was pressed again during the grace; waiting for the game again"
      continue
    fi
    quit=$(session_get quit_steam)
    why=""
    if [ "$quit" != yes ]; then
      if [ "$route" != steam ]; then why="the ArenaNet route has no Steam"
      elif [ "$(session_get started_steam)" != yes ]; then why="Steam already ran before Play"
      elif [ "$(session_get steam_window)" != hidden ]; then why="Steam's window was shown (no remembered login, Start Steam in the background off, or Show Steam)"
      else why="Quit Steam when the game quits was off"; fi
    elif [ "$(setting quitsteam)" != on ]; then
      why="Quit Steam when the game quits was turned off during the session"
    fi
    if [ -n "$why" ]; then
      if has_kind steam "$WL"; then WATCH_RESULT=left_running; log "session: Steam stays open: $why"
      else WATCH_RESULT=steam_already_gone; log "session: Steam is not running ($why)"; fi
      return 0
    fi
    if ! has_kind steam "$WL"; then
      WATCH_RESULT=steam_already_gone; log "session: Steam has already quit"; return 0
    fi
    watch_stage closing_steam
    break
  done

  # 4. Steam quits: -shutdown, then wineserver -k for this bottle
  wine_allowed
  game_env
  log "session: asking Steam to quit (steam.exe -shutdown)"
  echo "=== $(date '+%F %T') $STEAM_EXE -shutdown (the game quit)" >>"$LOGS/wine.log"
  ( cd "$BOTTLE" && env -u WINELOADER -u WINESERVER -u DYLD_FALLBACK_LIBRARY_PATH "${COMPATDB_UNSET[@]}" "${E[@]}" \
      nohup "$ENG/bin/wine" "$STEAM_EXE" -shutdown </dev/null >>"$LOGS/wine.log" 2>&1 9>&- & )
  now=$(date +%s)
  while :; do
    watch_poll || return 0
    if has_kind game "$WL"; then
      WATCH_RESULT=left_running; log "session: Guild Wars 2 started again while Steam was quitting; Steam is left as it is"; return 0
    fi
    has_kind steam "$WL" || { WATCH_RESULT=quit; log "session: Steam quit ($(( $(date +%s) - now )) s after -shutdown)"; return 0; }
    [ $(( $(date +%s) - now )) -lt "$WATCH_QUITWAIT" ] || break
  done
  log "session: Steam did not quit within $WATCH_QUITWAIT s; ending the bottle's Wine (wineserver -k)"
  WINEPREFIX="$BOTTLE" "$ENG/bin/wineserver" -k >>"$LOGFILE" 2>&1 || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    WL=$(proc_list)
    has_kind steam "$WL" || has_kind session "$WL" || break
    sleep 0.5
  done
  end_leftovers >/dev/null
  WATCH_RESULT=killed
}

cmd_install() {
  local route=${1:-} setup=${2:-} want src="" with_settings=yes
  CREATED="" FETCH_PID="" IMPORT_DST="" IMPORT_ACF=""
  # a first install's state and manifest go too if it fails
  [ -f "$MANIFEST" ] || CREATED="state install-manifest.json"
  case "$route" in steam|arenanet|import) ;; *) echo "@error Usage: gw2om.sh install steam | install arenanet <Gw2Setup-64.exe> | install import <game folder> [--no-settings]"; exit 2 ;; esac
  if [ "$route" = import ]; then
    [ "${3:-}" != --no-settings ] || with_settings=no
    src=$(game_dir_of "$setup") || { echo "@error There is no Guild Wars 2 in ${setup:-that folder} (Gw2-64.exe and a Gw2.dat of more than 1 GB)."; exit 2; }
    case "$src/" in "$BOTTLE/"*) echo "@error That is $APP_NAME's own copy of the game."; exit 2 ;; esac
    route=$(game_route_of "$src")
    if game_runs_anywhere; then echo "@error Guild Wars 2 is running. Quit it first (in every app), so its files don't change while they are copied."; exit 1; fi
  fi
  if [ "$route" = arenanet ] && [ -z "$src" ]; then
    [ -n "$setup" ] || { echo "@error Drop Gw2Setup-64.exe from ArenaNet's site first."; exit 2; }
    want=$(cmd_check_setup "$setup") || true
    want=$(echo "$want" | tail -1)
    case "$want" in "@done "*) ;; *) echo "$want"; exit 1 ;; esac
  fi
  open_log
  log "---- install $route${src:+ import $src} $VERSION (engine $ENGINE_NAME) root=${ROOT:-/} dry=${DRY:-0}"
  phase 1
  step "Checking your Mac"
  preflight ${src:+import}
  lock
  trap on_install_exit EXIT
  trap 'exit 143' TERM INT HUP   # Cancel in the app: roll back through the EXIT trap
  [ -n "$DRY" ] || mkdir -p "$APPDIR"
  step "The Wine engine"
  install_engine
  phase 2
  step "The game's own bottle"
  install_bottle
  if [ -n "$src" ]; then
    install_imported "$route" "$src" "$with_settings"
    return
  fi
  phase 3
  if [ "$route" = steam ]; then
    install_steam
  else
    step "ArenaNet's installer"
    say "$(echo "$want" | sed 's/^@done //')"
    run mkdir -p "$CACHE/downloads"
    run cp "$setup" "$CACHE/downloads/Gw2Setup-64.exe"
  fi
  [ -n "$DRY" ] || { set_state route "$route"; set_state origin download; }
  write_manifest
  phase 4
  if [ "$route" = steam ]; then
    step "Steam opens: sign in, then install Guild Wars 2"
    launch "$STEAM_EXE" "steam://install/$GW2_APPID"
    [ -n "$DRY" ] || set_state stage waiting_game
    log "install: waiting for the game (Steam)"
    echo "@done Steam is starting. Sign in, then install Guild Wars 2 there; this window follows the download."
  else
    step "ArenaNet's installer opens: it downloads the game"
    launch "$CACHE/downloads/Gw2Setup-64.exe"
    [ -n "$DRY" ] || set_state stage waiting_game
    log "install: waiting for the game (ArenaNet's installer)"
    echo "@done ArenaNet's installer is starting. Let it download the game; this window follows it."
  fi
}

# The finishing touches, once the game is there (game_state): the shader cache's folder, the
# interface addon, the registry settings, stage=finished
finish_touches() {
  say "The shader cache: $DXMT_CACHE (DXMT fills it while you play)"
  run mkdir -p "$DXMT_CACHE"
  sync_uiscale
  apply_registry
  [ -n "$DRY" ] || { set_state stage finished; set_state game_dir "$GAME_DIR"; }
  write_manifest
}

# Phase 5, once the game is there
cmd_finish() {
  open_log
  log "---- finish $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  [ -f "$MANIFEST" ] || die "$APP_NAME is not installed."
  phase 5
  step "Finishing touches"
  game_state
  [ "$GAME" = yes ] || [ -n "$DRY" ] || die "Guild Wars 2 is not installed yet."
  lock
  trap 'unlock' EXIT
  finish_touches
  log "finish complete"
  echo "@done Guild Wars 2 is ready. Press Play."
}

cmd_stop_waiting() {
  [ "$(state stage)" = waiting_game ] || { echo "@done not waiting"; return; }
  [ -n "$DRY" ] || set_state stage none
  echo "@done Stopped following the game's download. Install picks up from there."
}

# Repair: the engine (unpacked again if it isn't the expected one), the bottle's settings; Steam
# again if it is gone; the game and settings stay
cmd_repair() {
  CREATED="" FETCH_PID=""
  open_log
  log "---- repair $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  [ -f "$MANIFEST" ] || [ -d "$ENG" ] || die "$APP_NAME is not installed."
  phase 1
  step "Checking your Mac"
  preflight
  lock
  trap on_install_exit EXIT
  trap 'exit 143' TERM INT HUP
  step "The Wine engine"
  if engine_ok && { [ "$(graphics_state)" != yes ] || { [ "$ENGINE_CHECKS" = 1 ] && ! engine_matches "$ENG"; }; }; then
    warn "The engine's files changed; unpacking the engine again"
    install_engine force
  else
    install_engine
  fi
  phase 2
  step "The game's own bottle"
  install_bottle
  phase 3
  if [ "$(state route)" = steam ]; then install_steam; fi
  phase 5
  step "Finishing touches"
  run mkdir -p "$DXMT_CACHE"
  sync_uiscale
  apply_registry
  write_manifest
  log "repair complete"
  echo "@done Repaired: the engine and the bottle's settings are set up again."
}

cmd_reinstall_engine() {
  CREATED="" FETCH_PID=""
  open_log
  log "---- reinstall-engine $VERSION"
  [ -d "$ENG" ] || die "$APP_NAME is not installed."
  check_not_running
  lock
  trap on_install_exit EXIT
  install_engine force
  echo "@done The engine was unpacked again."
}

cmd_reset_shaders() {
  open_log
  log "---- reset-shaders"
  case "$(busy_of "$(proc_list)")" in game) die "Quit Guild Wars 2 first." ;; esac
  if [ -d "$DXMT_CACHE_ROOT" ]; then
    run rm -rf "$DXMT_CACHE_ROOT"
    run mkdir -p "$DXMT_CACHE"
  fi
  echo "@done DXMT's caches for the game are empty. The next sessions build them again."
}

cmd_play() {
  local key
  open_log
  log "---- play $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  [ -f "$MANIFEST" ] && engine_ok || [ -n "$DRY" ] || die "$APP_NAME is not installed. Install it first."
  [ "$(state stage)" = finished ] || [ -n "$DRY" ] || die "Guild Wars 2 is not installed yet."
  game_state
  [ "$GAME" = yes ] || [ -n "$DRY" ] || die "Guild Wars 2 is not in the bottle any more. Install it again (Uninstall, then Install)."
  case "$(busy_of "$(proc_list)")" in
    game) echo "@done Guild Wars 2 is already running."; return ;;
    installer) die "ArenaNet's installer is still running. Let it finish first." ;;
    leftovers) end_leftovers ;;
  esac
  # (one account, one login: not while another app's Guild Wars 2 runs, 0.1.x's or a Mach9.app's)
  ! game_runs_anywhere || die "Guild Wars 2 is running in another app. Quit it first."
  # The session (watch-session): a new one (this Play takes the session's lock) unless a watcher
  # still follows the last one. Then this Play joins it (while Steam starts the game, or in the
  # grace after the game quit) and waits until the watcher has it; refused while Steam quits.
  # Whether this Play starts Steam itself is decided here, from the processes before the launch.
  local fresh=no joined=no steam_before=no route silent="" window="" quit=no try rc
  route=$(state route)
  [ "$route" = arenanet ] || route=steam
  if [ "$route" = steam ]; then
    if [ "$(setting steambg)" = on ] && steam_remembers_login; then silent=-silent window=hidden; else window=shown; fi
  fi
  if [ -z "$DRY" ] && [ ! -x "$LOCKER" ]; then
    warn "$APP_NAME's session helper is missing ($LOCKER): Steam stays open after the game. Reinstall $APP_NAME."
  elif [ -z "$DRY" ]; then
    open_lock
    for try in 1 2 3; do
      steam_before=no
      has_kind steam "$(proc_list)" && steam_before=yes
      if lock9; then fresh=yes; break; fi
      [ "$(session_get stage)" != closing_steam ] || die "Steam is quitting after your last session. Try again in a few seconds."
      rc=0
      join_session "$steam_before" "$window" "$(steam_decision "$route" yes "$window")" || rc=$?
      case "$rc" in
        0) joined=yes; break ;;
        1) die "Steam is quitting after your last session. Try again in a few seconds." ;;
        3) die "$APP_NAME's last session did not answer. Try again in a few seconds." ;;
      esac
      # (2: the lock is free again: the last watcher has ended, this Play takes the session)
    done
    [ "$fresh" = yes ] || [ "$joined" = yes ] || die "$APP_NAME is still busy with the last session. Try again in a few seconds."
  fi
  # This Play's own session (it holds the session's lock: no other Play, session or registry write
  # until its watcher takes over), with no Wine of the bottle running: the manifest follows this
  # version, then the registry and DXMT's options. A Play that joined a session changes nothing;
  # without the session helper the registry waits.
  if [ "$fresh" = yes ] && [ -z "$DRY" ]; then SESSION_LOCKED=yes; fi
  if { [ "$fresh" = yes ] || [ -n "$DRY" ] || [ ! -x "$LOCKER" ]; } && ! session_running; then
    [ "$(json_get "$MANIFEST" version)" = "$VERSION" ] || [ -n "$DRY" ] || write_manifest
    apply_registry
    write_dxmt_conf
  fi
  [ -n "$DRY" ] || [ "$(graphics_state)" = yes ] || warn "The engine's graphics are not its own. Click Repair."
  # A running session keeps the settings it started with: Steam passes its own environment on
  if session_running && [ -f "$LOGS/session.key" ]; then
    game_env
    key=$(printf '%s\n' "${E[@]}" | shasum | cut -c1-12)
    [ "$key" = "$(cat "$LOGS/session.key")" ] ||
      echo "@notice Steam is still running with the settings it started with; quit Steam for the new ones."
  fi
  if [ "$route" = arenanet ]; then
    # shellcheck disable=SC2046
    launch "$GAME_EXE" $(setting launchopts)
  else
    # Once Steam remembers a login, it starts without its window (-silent, above): it signs in by
    # itself and starts the game. Before the first sign-in its window shows, as at the install.
    # shellcheck disable=SC2046
    launch "$STEAM_EXE" ${silent:+"$silent"} -applaunch "$GW2_APPID" $(setting launchopts)
  fi
  if [ -n "$DRY" ]; then
    echo "[dry-run] watch-session"
  elif [ "$fresh" = yes ]; then
    # Steam quits after the game only if this Play started it, without its window, and the
    # setting is on
    quit=$(steam_decision "$route" "$([ "$steam_before" = no ] && echo yes || echo no)" "$window")
    { echo "route=$route"; echo "started_steam=$([ "$route" = steam ] && [ "$steam_before" = no ] && echo yes || echo no)"
      echo "steam_window=$window"; echo "quit_steam=$quit"; echo "watcher_pid="; echo "stage=waiting_game"
      echo "started=$(date +%s)"; echo "game_started="; echo "game_ended="; echo "replay=0"; echo "requests=0"
      echo "updated=$(date +%s)"; echo "result="; } >"$SESSION.new.$$"
    mv -f "$SESSION.new.$$" "$SESSION"
    : >"$SESSION_REQ"
    # the watcher, which inherits the lock (fd 9) and writes its pid into the session
    nohup /bin/bash "$RES/gw2om.sh" watch-session --handoff </dev/null >/dev/null 2>&1 &
    exec 9>&-
    log "session: watcher started (pid $!), quit_steam=$quit"
  elif [ "$joined" = yes ]; then
    log "session: this Play joined the running session (watcher pid $(session_get watcher_pid))"
  fi
  echo "@done Starting Guild Wars 2."
}

# --- The session's stages (session-status, which the window polls every second while the game
# starts and runs)
#
# Stages, in order: starting_steam, updating_steam, signing_in, checking_files (Steam's route),
# starting_game, playing; none when no start is under way (Steam on its own, or nothing).
# Steam's logs are read only for their state lines (since the session's start) and nothing of them
# is printed: no account names or IDs ever leave this function.

# since <log> <stamp>: Steam's log lines from "[<stamp>]" on (local time, as Steam writes it)
since() { awk -v t="[$2]" '/^\[2[0-9][0-9][0-9]-/ && substr($0, 1, 21) >= t' "$1" 2>/dev/null || true; }
# etime_seconds <ps etime>: [[dd-]hh:]mm:ss as seconds
etime_seconds() {
  echo "$1" | awk '{ d = 0; t = $0
    if (index(t, "-")) { d = substr(t, 1, index(t, "-") - 1); t = substr(t, index(t, "-") + 1) }
    n = split(t, p, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + p[i]; print d * 86400 + s }'
}

# The game's own Frame Limiter at a value together with vsync: under Wine it lands just under the
# display's rate (58 instead of 60); Unlimited with vsync keeps a steady 60. Sets LIMIT (the
# Frame Limiter's value, or empty) and LIMIT_HINT (yes|no). The game's settings file is only read.
limiter_state() {
  local gfx vsync
  gfx="$BOTTLE/drive_c/users/$(bottle_user)/AppData/Roaming/Guild Wars 2/GFXSettings.Gw2-64.exe.xml"
  LIMIT=$(sed -n 's/.*<OPTION Name="frameLimit"[^>]*Value="\([^"]*\)".*/\1/p' "$gfx" 2>/dev/null | head -1 || true)
  vsync=$(sed -n 's/.*<OPTION Name="verticalSync"[^>]*Value="\([^"]*\)".*/\1/p' "$gfx" 2>/dev/null | head -1 || true)
  LIMIT_HINT=no
  if [ -n "$LIMIT" ] && [ "$LIMIT" != unlimited ] && [ "$vsync" = true ]; then LIMIT_HINT=yes; fi
}

# Steam updating or verifying itself (logs/bootstrap_log.txt since <stamp>): sets UPD (no, update
# or verify) and UPD_PCT. Its verification at each start is usually done within the second; a
# damaged install's takes longer, and is followed by the update that repairs it.
steam_update_state() {
  local last a b
  UPD=no UPD_PCT=""
  last=$(since "$STEAM_DIR/logs/bootstrap_log.txt" "$1" |
    grep -E '\] (Downloading update|Download complete|Extracting package|Installing update|Cleaning up|Update complete|Verifying installation|Verifying file sizes|Verifying all executable|Package file|Unable to read and verify|uninstalled manifest found|Verification complete|Nothing to do|Shutdown|Startup - )' |
    tail -1 | cut -c23- || true)
  case "$last" in
    "Verifying"*|"Package file"*|"Unable to read and verify"*|"uninstalled manifest found"*) UPD=verify; return ;;
  esac
  case "$last" in
    "Downloading update ("*)
      UPD=update
      a=$(echo "$last" | sed -n 's/^Downloading update (\([0-9,]*\) of \([0-9,]*\) KB).*/\1/p' | tr -d ,)
      b=$(echo "$last" | sed -n 's/^Downloading update (\([0-9,]*\) of \([0-9,]*\) KB).*/\2/p' | tr -d ,)
      if [ -n "$a" ] && [ -n "$b" ] && [ "$b" -gt 0 ]; then UPD_PCT=$((a * 100 / b)); fi ;;
    "Downloading update"*) UPD=update ;;
    "Download complete"*|"Extracting package"*|"Installing update"*|"Cleaning up"*) UPD=update UPD_PCT=100 ;;
  esac
}

# Steam checking or updating the game (logs/content_log.txt since <stamp>, its lines for app
# 1284210): sets CONTENT (verify|update|none) and CONTENT_PCT (an update's download, from the
# appmanifest)
steam_content_state() {
  local last
  CONTENT=none CONTENT_PCT=""
  last=$(since "$STEAM_DIR/logs/content_log.txt" "$1" |
    grep -E "AppID $GW2_APPID (state changed|update changed|update started|update queued|scheduler update|finished update|update canceled|update stopped)" |
    tail -1 | cut -c23- || true)
  case "$last" in
    *"finished update"*|*"update canceled"*|*"update stopped"*|*"App Running"*) ;;
    *Validating*|*Verifying*) CONTENT=verify ;;
    *Downloading*|*Staging*|*Committing*|*Preallocating*|*"Update Running"*|*"Running Update"*|*"update started"*|*"Update Queued"*|*"update queued"*|*Reconfiguring*)
      CONTENT=update
      game_state
      if [ -n "$GAME_TOTAL" ] && [ "${GAME_TOTAL:-0}" -gt 0 ] 2>/dev/null; then CONTENT_PCT=$((GAME_BYTES * 100 / GAME_TOTAL)); fi ;;
  esac
}

# Steam is signed in (logs/connection_log.txt since <stamp>): only the state word of its lines
# ("[Logged On, ...]") is read
steam_signed_in() {
  [ "$(since "$STEAM_DIR/logs/connection_log.txt" "$1" | sed -n 's/^\[[^]]*\] \[\([A-Za-z ]*\), .*/\1/p' | tail -1)" = "Logged On" ]
}

# session_live: live while the watcher follows the session (it waits for the game, follows it,
# waits through a restart's grace or closes Steam); none otherwise, Steam idling on its own included
# (the polled paths, session-status and status, tell the watcher by its process alone: probing its
# lock every second could make a Play that is just starting miss it)
session_live() {
  if [ -f "$SESSION" ] && watcher_proc "$(session_get watcher_pid)"; then
    case "$(session_get stage)" in
      waiting_game|playing|grace|closing_steam) echo live; return ;;
    esac
  fi
  echo none
}

cmd_session_status() {
  local since=""
  if [ "${1:-}" = --since ]; then since=${2:-}; fi
  local l now t0="" stamp="" s_stage="" alive=no pending=no gpid et dx
  local stage=none detail="" progress="" elapsed="" game_elapsed="" steam=none game=no closing=no
  local route quit
  l=$(proc_list)
  now=$(date +%s)
  route=$(state route || true)
  # the watcher's session (its file stays after the session; a dead watcher's unfinished one is over)
  if [ -f "$SESSION" ]; then
    s_stage=$(session_get stage)
    t0=$(session_get started)
    if watcher_proc "$(session_get watcher_pid)"; then alive=yes; fi
    [ -z "$(session_get route)" ] || route=$(session_get route)
  fi
  # (without a watcher: the start play recorded in session.env)
  if [ -z "$t0" ] && [ -f "$LOGS/session.env" ]; then
    t0=$(date -j -f '%Y-%m-%d %H:%M:%S' "$(sed -n 's/^STARTED=//p' "$LOGS/session.env" | head -1)" +%s 2>/dev/null || true)
  fi
  # (--since: the window's Play, later than the session's start when that Play joined it)
  case "$since" in ''|*[!0-9]*) ;; *) if [ -z "$t0" ] || [ "$since" -gt "$t0" ]; then t0=$since; fi ;; esac
  if [ -n "$t0" ]; then
    stamp=$(date -r "$t0" '+%Y-%m-%d %H:%M:%S')
    elapsed=$((now - t0))
  fi
  quit=no
  if [ "$alive" = yes ] && [ "$(session_get quit_steam)" = yes ]; then quit=yes; fi
  # A start is under way: the watcher waits for the game, or (no watcher) play ran in the last
  # 15 minutes, the watcher's own wait
  if [ -f "$SESSION" ]; then
    [ "$alive" = yes ] && [ "$s_stage" = waiting_game ] && pending=yes
  elif [ -n "$elapsed" ] && [ "$elapsed" -lt 900 ]; then
    pending=yes
  fi
  if printf '%s\n' "$l" | grep -q '^steam '; then
    steam="bg"
    case "$(session_get steam_window)" in
      shown) steam=window ;;
      hidden) ;;
      *) since "$STEAM_DIR/logs/bootstrap_log.txt" "${stamp:-0000}" | grep 'Startup - Steam Client launched with' | tail -1 |
           grep -q -- ' -silent' || steam=window ;;
    esac
  fi
  gpid=$(printf '%s\n' "$l" | awk '$1 == "game" { print $2; exit }')
  if [ -n "$gpid" ]; then
    game=yes
    dx="$LOGS/Gw2-64_d3d11.log"
    # (DXMT's log of this session: written since its start. The engine's DXMT logs its device
    # and nothing per frame, so the device is as far as it tells.)
    if [ -f "$dx" ] && { [ -z "$t0" ] || [ "$(stat -f %m "$dx")" -ge "$t0" ]; } && grep -q -m1 'Using feature level' "$dx"; then
      stage=playing
    else
      stage=starting_game
    fi
    if [ "$stage" = playing ] && [ -n "$(session_get game_started)" ] && [ "$alive" = yes ]; then
      game_elapsed=$((now - $(session_get game_started)))
    else
      et=$(ps -o etime= -p "$gpid" 2>/dev/null | tr -d ' ' || true)
      [ -z "$et" ] || game_elapsed=$(etime_seconds "$et")
    fi
  elif [ "$pending" = yes ]; then
    if [ "$route" = arenanet ]; then
      stage=starting_game
    elif [ "$steam" = none ]; then
      stage=starting_steam
    else
      steam_update_state "$stamp"
      steam_content_state "$stamp"
      if [ "$UPD" != no ]; then
        stage=updating_steam
        if [ "$UPD" = verify ]; then detail="Steam checks its own files"; else detail="Steam updates itself${UPD_PCT:+ · $UPD_PCT%}"; fi
        progress=$UPD_PCT
      elif [ "$CONTENT" != none ]; then
        stage=checking_files
        if [ "$CONTENT" = verify ]; then detail="Steam verifies Guild Wars 2"; else detail="Steam updates Guild Wars 2"; fi
        detail="$detail${CONTENT_PCT:+ · $CONTENT_PCT%}"
        progress=$CONTENT_PCT
      elif steam_signed_in "$stamp"; then
        stage=starting_game
      elif printf '%s\n' "$l" | grep -qi '^steam .*steamwebhelper'; then
        stage=signing_in
      else
        stage=starting_steam
      fi
    fi
  fi
  # The watcher closes Steam after the game (its grace, then -shutdown)
  if [ "$game" = no ] && [ "$quit" = yes ] && [ "$steam" != none ]; then
    case "$s_stage" in grace|closing_steam) closing=yes ;; esac
  fi
  limiter_state
  echo "stage=$stage"
  echo "detail=$detail"
  echo "progress=$progress"
  echo "elapsed=$elapsed"
  echo "game_elapsed=$game_elapsed"
  echo "route=$route"
  echo "steam=$steam"
  echo "game=$game"
  echo "game_pid=$gpid"
  echo "closing=$closing"
  echo "quit_steam=$quit"
  # (the window keeps polling while it does: a game restarted within the grace shows again)
  echo "watching=$([ "$(session_live)" = live ] && echo yes || echo no)"
  echo "limiter_hint=$LIMIT_HINT"
  echo "limiter_value=$LIMIT"
}

# Show Steam: its main window, through the running Steam (a second steam.exe hands the URL over)
cmd_show_steam() {
  local n h i=0 lim ask
  open_log
  log "---- show-steam"
  [ "$(state route)" = steam ] || die "Guild Wars 2 doesn't start through Steam here."
  printf '%s\n' "$(proc_list)" | grep -q '^steam ' || die "Steam isn't running."
  # Steam's window up: the session leaves this Steam open after the game, as a Steam whose window
  # showed from the start. The watcher decides (a "shown" request, as Play's join); while it
  # already quits Steam, the window doesn't come up.
  if lock_held || watcher_proc "$(session_get watcher_pid)"; then
    [ "$(session_get stage)" != closing_steam ] || die "Steam is quitting after the game."
    # Steam's window opens only once the watcher has answered (or is gone, and with it whoever
    # would quit Steam): on no answer it stays shut, so the watcher can't quit a Steam the user
    # brought up. (The watcher looks every WATCH_POLL seconds; as Play's join, it must run and
    # name itself in the session first: a Play that has just taken the lock is still writing the
    # session and emptying the requests.)
    lim=$(awk -v p="$WATCH_POLL" 'BEGIN { print int((p * 3 + 3) * 10) }')
    ask=yes
    until watcher_proc "$(session_get watcher_pid)" && [ "$(session_get stage)" != "done" ]; do
      lock_held || { ask=no; break; }
      i=$((i + 1))
      [ $i -lt "$lim" ] || die "$APP_NAME is still handing the session over. Try Show Steam again in a moment."
      sleep 0.1
    done
    if [ "$ask" = yes ]; then
      n=$(session_request shown)
      i=0
      while :; do
        h=$(session_get requests)
        if [ "${h:-0}" -ge "$n" ]; then
          [ "$(session_get stage)" != closing_steam ] || die "Steam is quitting after the game."
          log "show-steam: the session leaves Steam open after the game (quit_steam=$(session_get quit_steam))"
          break
        fi
        lock_held || break
        i=$((i + 1))
        if [ $i -ge "$lim" ]; then
          log "show-steam: the watcher did not answer the request; Steam's window stays shut"
          die "$APP_NAME's session didn't answer. Try Show Steam again in a moment."
        fi
        sleep 0.1
      done
    fi
  fi
  launch "$STEAM_EXE" steam://open/main
  echo "@done Steam's window opens."
}

cmd_env() {
  game_env
  printf '%s\n' "${E[@]}"
}

cmd_uninstall() {
  local c
  open_log
  log "---- uninstall $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  phase 1
  step "Stopping the game's Wine"
  check_not_running
  lock
  # (the folder itself goes too once empty)
  trap 'unlock; rmdir "$APPDIR" 2>/dev/null || true' EXIT
  stop_watcher
  [ -n "$DRY" ] || stop_wine
  phase 2
  step "Removing the bottle (Steam and the game in it)"
  if [ -d "$BOTTLE" ]; then run rm -rf "$BOTTLE"; fi
  phase 3
  step "Removing the engine, the settings and caches"
  for c in $APP_FILES; do
    if [ -e "$APPDIR/$c" ]; then run rm -rf "${APPDIR:?}/$c"; fi
  done
  # (DXMT's caches are in it: $CACHE/dxmt)
  if [ -d "$CACHE" ]; then run rm -rf "$CACHE"; say "Removed the caches, DXMT's with them ($CACHE)"; fi
  log "uninstall complete"
  echo "@done $APP_NAME is removed, with the bottle and the game in it. Logs stay in $LOGS."
}

cmd_end_leftovers() {
  open_log
  local l b
  l=$(proc_list)
  b=$(busy_of "$l")
  case "$b" in
    game|steam|installer|session) die "$(busy_message "$b" "$l")" ;;
    leftovers) end_leftovers; echo "@done Ended the leftover Wine processes." ;;
    *) echo "@done No leftover Wine processes." ;;
  esac
}

cmd_fetch_engine() {
  open_log
  log "---- fetch-engine $ENGINE_URL"
  trap '[ -z "${FETCH_PID:-}" ] || kill "$FETCH_PID" 2>/dev/null || true' EXIT
  fetch "$ENGINE_URL" "$ENGINE_SHA256" "$ENGINE_SIZE" "Wine engine" "$ENGINE_API_URL"
  echo "@done $FETCHED"
}

case "${1:-}" in
  status) status ;;
  install) shift; cmd_install "$@" ;;
  finish) cmd_finish ;;
  stop-waiting) cmd_stop_waiting ;;
  repair) cmd_repair ;;
  uninstall) cmd_uninstall ;;
  play) cmd_play ;;
  watch-session) shift; cmd_watch_session "$@" ;;
  session-status) shift; cmd_session_status "$@" ;;
  show-steam) cmd_show_steam ;;
  settings) settings ;;
  set) shift; cmd_set "$@" ;;
  check-setup) shift; cmd_check_setup "$@" ;;
  scan) cmd_scan ;;
  check-game) shift; cmd_check_game "$@" ;;
  reset-shaders) cmd_reset_shaders ;;
  reinstall-engine) cmd_reinstall_engine ;;
  end-leftovers) cmd_end_leftovers ;;
  fetch-engine) cmd_fetch_engine ;;
  env) cmd_env ;;
  rules) rules_text; [ ! -f "$RULES_LOCAL" ] || cat "$RULES_LOCAL" ;;
  *) sed -n '2,/^# Environment/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
