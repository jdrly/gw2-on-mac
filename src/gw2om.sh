#!/bin/bash
# GW2 on Mac: the install, status, play and settings logic behind the app's window. Unlike SWTOR
# on Mac it changes no existing install: it creates its own Wine engine and bottle, puts GW2 on
# Mac's graphics (DXMT) and Wine pieces into them, and installs the game through Steam or
# ArenaNet's own installer.
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
#   gw2om.sh scan              the Guild Wars 2 installs of other Wine apps on this Mac (CrossOver,
#                              Whisky, app wrappers, Heroic, GameHub, ~/.wine), one "game" line each
#   gw2om.sh check-game DIR    is DIR (or a game folder in it) a Guild Wars 2 install: its "game"
#                              line, or "@error <why>"
#   gw2om.sh finish            phase 5 once the game is there: the shader cache's folder, the
#                              interface addon (if on), the registry settings, the manifest
#   gw2om.sh stop-waiting      the window stops following the game's download (the engine and
#                              the bottle stay; Install picks up from there)
#   gw2om.sh repair            engine, graphics, Wine pieces, bottle settings and Game Mode again;
#                              keeps the game and the settings
#   gw2om.sh uninstall         removes everything this app created: the bottle (with the game in
#                              it), the engine, Game Mode, the settings, its caches (DXMT's in
#                              them); logs stay
#   gw2om.sh play              starts the game (Steam: steam.exe -applaunch 1284210, -silent once
#                              Steam remembers a login; ArenaNet: Gw2-64.exe) with the settings as
#                              its environment, and the session's watcher (watch-session)
#   gw2om.sh watch-session     follows the session Play started (the file `session`): waits for
#                              Gw2-64.exe, then for its exit, and quits the Steam that Play started
#                              in the background (Quit Steam when the game quits); play starts it
#                              detached, one per session
#   gw2om.sh settings          KEY=VALUE lines: the settings (Settings window) and their state
#   gw2om.sh set K V           change one setting (see setting_valid)
#   gw2om.sh check-setup FILE  is FILE ArenaNet's Gw2Setup-64.exe: a PE x86_64 executable with a
#                              valid Authenticode signature by ArenaNet ("@done <what>")
#   gw2om.sh reset-shaders     deletes DXMT's caches (shaders, pipelines, recipes) in the app's
#                              own cache folder; never DXMT's in the per-user cache folder
#   gw2om.sh reinstall-engine  unpacks the engine again and puts GW2 on Mac's pieces back
#   gw2om.sh end-leftovers     ends leftover Wine processes of the engine (no session running)
#   gw2om.sh fetch-engine      downloads and verifies the engine into the cache
#   gw2om.sh env               the game's environment as play would set it (for Terminal)
#
# Environment:
#   GW2_ON_MAC_ROOT=/abs/dir   sandbox for tests: the app's files, logs, caches and the per-user
#                              temp folder all live under it ($ROOT/home/Library/..., $ROOT/usertmp/)
#   GW2_ON_MAC_DRY_RUN=1       print what would change and change nothing (no downloads, no Wine,
#                              no log file)
#   In a sandbox only, for scripts/test-sandbox.sh's stand-ins (never the real Wine there):
#   GW2_ON_MAC_ENGINE_URL, GW2_ON_MAC_ENGINE_SHA256, GW2_ON_MAC_ENGINE_SIZE   another engine
#                              archive (a stand-in whose bin/wine only pretends)
#   GW2_ON_MAC_ENGINE_CHECKS=0 don't check the unpacked engine's files against the real engine's
#   GW2_ON_MAC_STEAMSETUP_URL  another SteamSetup.exe
#   GW2_ON_MAC_SIGNER          the signer check-setup accepts (default ArenaNet)
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
RES="$(cd "$(dirname "$0")" && pwd)"
COMP="$RES/components"
VERSION="$(sed -n 's/^version=//p' "$RES/app.properties" 2>/dev/null || true)"
VERSION="${VERSION:-dev}"
CHANNEL="$(sed -n 's/^channel=//p' "$RES/app.properties" 2>/dev/null || true)"
CHANNEL="${CHANNEL:-release}"
DXMT_VERSION="$(cat "$COMP/dxmt/VERSION" 2>/dev/null || echo unknown)"

# --- The engine: athei's build of CodeWeavers' CrossOver 26.3 (Wine 11.0, x86_64 WoW64), the
# engine of SWTOR on Mac and SWGL on Mac, downloaded at install time from its release (never
# bundled or mirrored). Bump name, URL, size and sha256 together.
ENGINE_NAME=cx-26.3.0-8
ENGINE_TITLE="CrossOver 26.3 · Wine 11"
ENGINE_URL=https://github.com/athei/wine-build/releases/download/cx-26.3.0-8/wine-cx-26.3.0-8-macos-x86_64.tar.xz
# the same file through GitHub's API (the release asset's id): the download's second way
ENGINE_API_URL=https://api.github.com/repos/athei/wine-build/releases/assets/627976236
ENGINE_SIZE=234978748
ENGINE_SHA256=1976c3310a1f8be2f8e9a46fcb524f77b4316df3d281d94af2c8542bef60456d
# The engine's own files that GW2 on Mac replaces (kept next to them as <file>.stock) and its
# loader, checked after unpacking: the bundled builds are made for exactly these
ENGINE_LOADER_SHA256=2100dea802b2c560ba5d719c20ba1fcc1c8a09daf66580a4da6dd48e552d5a05
ENGINE_NTDLL_SHA256=f1ca0f092c9435299bb06f2e6e9c92b52b4b0ab5016a42c1a4ce01ccc18c9f4a
ENGINE_WINEMAC_SHA256=e0ed7ac7405c21ae5644370aec778ff333c8ef6c27e45e6dd739ee83ad422001
ENGINE_WIN32U_SHA256=3f58b3fdd196fc6e04211a5009fe3ab078b435e2915641d237c084f737e09837
ENGINE_WINESERVER_SHA256=c65ca777e46e2f05dedf838743aeba6bd6b7f7e7cc650f6f979fa87be1f7003e
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
  USER_TMP="$ROOT/usertmp/"
  ENGINE_URL="${GW2_ON_MAC_ENGINE_URL:-$ENGINE_URL}"
  [ -z "${GW2_ON_MAC_ENGINE_URL:-}" ] || ENGINE_API_URL=""
  ENGINE_SHA256="${GW2_ON_MAC_ENGINE_SHA256:-$ENGINE_SHA256}"
  ENGINE_SIZE="${GW2_ON_MAC_ENGINE_SIZE:-$ENGINE_SIZE}"
  ENGINE_CHECKS="${GW2_ON_MAC_ENGINE_CHECKS:-1}"
  STEAM_SETUP_URL="${GW2_ON_MAC_STEAMSETUP_URL:-$STEAM_SETUP_URL}"
  SIGNER="${GW2_ON_MAC_SIGNER:-ArenaNet}"
  SYS_APPS="$ROOT/Applications"
  IMPORT_COPY="${GW2_ON_MAC_IMPORT_COPY:-}"
  FREE_KB="${GW2_ON_MAC_FREE_KB:-}"
  WATCH_TIMEOUT="${GW2_ON_MAC_WATCH_TIMEOUT:-$WATCH_TIMEOUT}" WATCH_GRACE="${GW2_ON_MAC_WATCH_GRACE:-$WATCH_GRACE}"
  WATCH_QUITWAIT="${GW2_ON_MAC_WATCH_QUITWAIT:-$WATCH_QUITWAIT}" WATCH_POLL="${GW2_ON_MAC_WATCH_POLL:-$WATCH_POLL}"
else
  H="$HOME"
  USER_TMP="$(getconf DARWIN_USER_TEMP_DIR)"
  ENGINE_CHECKS=1
  SIGNER=ArenaNet
  SYS_APPS=/Applications
  IMPORT_COPY="" FREE_KB=""
fi
APPDIR="$H/Library/Application Support/GW2 on Mac"
LOGS="$H/Library/Logs/GW2 on Mac"
CACHE="$H/Library/Caches/GW2 on Mac"
ENG="$APPDIR/engine"                  # the unpacked engine with GW2 on Mac's pieces
BOTTLE="$APPDIR/bottle"               # the game's Wine prefix (Steam and the game live in it)
GAMEMODE_APP="$APPDIR/gamemode/GW2.app"
SETTINGS="$APPDIR/settings.conf"
STATE="$APPDIR/state"                 # route, stage (none|waiting_game|finished), game_dir,
                                      # origin (download|import)
MANIFEST="$APPDIR/install-manifest.json"
DXMT_CONF="$APPDIR/dxmt.conf"
# The last Play's session (watch-session keeps it; key=value lines, SESSION_KEYS) and the lock that
# keeps one watcher per session (a folder with the watcher's pid in it)
SESSION="$APPDIR/session"
WATCH_LOCK="$APPDIR/.session.lock"
# DXMT's caches, in the app's own cache folder (DXMT_CACHE_DIR=$CACHE, jdrly/dxmt #134) instead of
# the per-user one ($(getconf DARWIN_USER_CACHE_DIR)dxmt/, which another DXMT setup of the game on
# this Mac may use and this app never touches): per process <exe>/ (the game's Gw2-64.exe/:
# shaders, pipeline archives, recorded pipelines)
DXMT_CACHE_ROOT="$CACHE/dxmt"
DXMT_CACHE="$DXMT_CACHE_ROOT/Gw2-64.exe"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
# What uninstall removes in APPDIR (the folder itself goes too once empty)
APP_FILES="engine bottle gamemode settings.conf state install-manifest.json dxmt.conf engine.new bottle.new session .session.lock"
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
in_list() { local w; for w in $2; do [ "$w" = "$1" ] && return 0; done; return 1; }
rosetta_ok() { /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; }
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
# Programs are told by their real executable (helpers/procpaths): Wine 11 rewrites argv[0], so ps
# shows C:\...\name.exe for its processes, while their executable is the engine's loader, a
# winetemp link to it or the Game Mode bundle's copy. Only this engine's processes count (another
# Wine, another sandbox's test or Jan's own setup never stop this one).
winetemp_tag() {
  local l="$ENG/lib/wine/x86_64-unix/wine"
  if [ -f "$l" ]; then echo "/winetemp-$(stat -f '%i-%z' "$l")-"; fi
}
proc_list() {
  local helper="$RES/helpers/procpaths"
  { if [ -x "$helper" ]; then "$helper" 2>/dev/null | sed 's/^/P /'; fi
    ps -axww -o pid=,comm= 2>/dev/null | sed 's/^ */C /'; } |
  awk -v e="$ENG/" -v g="$GAMEMODE_APP/" -v s="$ENG/bin/wineserver" -v t="$(winetemp_tag)" '
    $1 == "P" { x = $0; sub(/^P [0-9]+ /, "", x); real[$2] = x; next }
    { pid = $2; prog = $0; sub(/^C [0-9]+ /, "", prog)
      exe = (pid in real) ? real[pid] : prog
      sub(/\/lib\/wine\/\.\.\/\.\.\/bin\//, "/bin/", exe)
      ours = index(exe, e) == 1 || index(exe, g) == 1 || (t != "" && index(exe, t))
      if (!ours) next
      p = tolower(prog) }
    exe == s || exe ~ /\/bin\/wineserver(\.stock)?$/ { print "session", pid, prog; next }
    p ~ /[\/\\]gw2-64\.exe$/ || exe ~ /\/Gw2-64\.exe$/ { print "game", pid, prog; next }
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
  local url=$1 sha=$2 size=$3 label=$4 second=${5:-} dir="$CACHE/downloads" f manual
  f="$dir/$(basename "$url")"
  FETCHED=$f
  if [ -f "$f" ] && [ "$(sha256 "$f")" = "$sha" ]; then
    say "$label: using the verified download in the cache"
    return
  fi
  if [ -n "$DRY" ]; then
    echo "[dry-run] download $url ($size bytes, sha256 $sha) to $f"
    return
  fi
  mkdir -p "$dir"
  if [ -f "$f" ]; then log "$f in the cache is not the expected file (sha256 $(sha256 "$f")); downloading it again"; rm -f "$f"; fi
  say "Downloading $label from $url"
  fetch_source "$url" "$FETCH_TRIES"
  if [ "$OUT" != ok ] && [ -n "$second" ]; then
    say "The download from $url did not bring the file ($OUT); trying GitHub's other address for it, $second"
    fetch_source "$second" "$FETCH_SECOND_TRIES" "Accept: application/octet-stream"
  fi
  echo "@progress $label $GOT $size"
  manual="Or download $url in your browser, put the file into $dir and click Install again."
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

# The real engine's Wine never runs in a sandbox (a stand-in engine's does, for the tests)
wine_allowed() {
  [ -z "$ROOT" ] || [ "$ENGINE_CHECKS" = 0 ] || [ "${GW2_ON_MAC_ALLOW_WINE:-}" = 1 ] ||
    die "Refusing to run the real Wine engine in a sandbox (GW2_ON_MAC_ROOT): use a stand-in engine or GW2_ON_MAC_DRY_RUN=1."
}

# Every process of the bottle gets DXMT for Direct3D 11 (the engine's compatdb picks the tree),
# Steam's windows and the game launcher's CefHost.exe included
COMPATDB='v=5
name=gw2-on-mac;exe=*;dxgi=dxmt
name=gw2-launcher;exe=CefHost.exe;dxgi=dxmt'

# wine_do <args...>: Wine in the bottle for the install's own steps (output to the log)
wine_do() {
  if [ -n "$DRY" ]; then echo "[dry-run] wine $*"; return; fi
  wine_allowed
  log "+ wine $*"
  env -u WINELOADER -u WINESERVER -u WINEDLLPATH -u DYLD_FALLBACK_LIBRARY_PATH \
    WINEPREFIX="$BOTTLE" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d" \
    WINE_COMPATDB="$COMPATDB" WINEMSYNC=1 ROSETTA_X87_PATH="" \
    "$ENG/bin/wine" "$@" </dev/null >>"$LOGFILE" 2>&1
}

# End the bottle's Wine session and make sure nothing of it stays running
stop_wine() {
  [ -n "$DRY" ] && { echo "[dry-run] wineserver -k"; return; }
  [ -x "$ENG/bin/wineserver" ] || return 0
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
  WINEPREFIX="$BOTTLE" "$ENG/bin/wineserver" -w >>"$LOGFILE" 2>&1 || true
}

# set_reg <key> <name> <value> / del_reg <key> <name>: a REG_SZ value in HKCU, written straight
# into the bottle's user.reg (Wine reads it when its wineserver starts: only while no session
# runs). <key> as in user.reg's section headers, with doubled backslashes.
set_reg() {
  local reg="$BOTTLE/user.reg"
  if [ -n "$DRY" ]; then echo "[dry-run] $2=$3 under $1 in $reg"; return; fi
  [ -f "$reg" ] || die "The game's bottle is incomplete ($reg is missing). Click Repair."
  log "+ $2=$3 under $1 in $reg"
  K="[$1]" N="\"$2\"=" V="$3" T="$(date +%s)" awk '
    BEGIN { k = ENVIRON["K"]; n = ENVIRON["N"]; line = n "\"" ENVIRON["V"] "\"" }
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
del_reg() {
  local reg="$BOTTLE/user.reg"
  if [ -n "$DRY" ]; then echo "[dry-run] delete $2 under $1 in $reg"; return; fi
  [ -f "$reg" ] || return 0
  log "+ delete $2 under $1 in $reg"
  K="[$1]" N="\"$2\"=" awk '
    BEGIN { k = ENVIRON["K"]; n = ENVIRON["N"] }
    index($0, "[") == 1 { insec = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ") }
    insec && index($0, n) == 1 { next }
    { print }' "$reg" >"$reg.new.$$"
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
REG_GW2_DLLS='Software\\Wine\\AppDefaults\\Gw2-64.exe\\DllOverrides'

# The bottle's registry settings from settings.conf (Retina mode; the addon's version.dll
# override for Gw2-64.exe only): only while no session runs, else at the next game start that
# finds none (play)
apply_registry() {
  [ -f "$BOTTLE/user.reg" ] || [ -n "$DRY" ] || return 0
  if session_running; then
    log "registry settings wait for the next start without a running session"
    return 0
  fi
  set_reg "$REG_MAC" RetinaMode "$([ "$(setting retina)" = on ] && echo y || echo n)"
  if [ "$(setting uiscale)" = on ] && [ "$(uiscale_state)" = on ]; then
    set_reg "$REG_GW2_DLLS" version native,builtin
  else
    del_reg "$REG_GW2_DLLS" version
  fi
}

# --- Settings
#
# The defaults are the mix Jan plays with (in the development workspace). Some are newer than
# the rest; Settings turns each off:
#   warm=on          DXMT_WARM=all: pipelines built ahead by recent use (jdrly/dxmt #128)
#   coolworkers=3    HEAT_QOS=1=utility:3: only the first 3 job workers on the cooler cores
#   fastlocks=on     HEAT_SPIN=lock=20:game,event=30:game: short spins before sleeps (round 7)
# (and, with no setting of their own, DXMT_DEPENDENCY_COMPRESSION=1, the checkpoint chain, #133,
# and round 7's HEAT_LAZYCLOCK, HEAT_MSYNC_UNREG and HEAT_MSYNC_PORTFIX: see game_env)
SETTING_KEYS="retina fpscap metalfx hud warm coolworkers fastlocks ncpu uiscale uiscale_size uiscale_sans uiscale_cinema gamemode launchopts updates debug steambg quitsteam"
FPS_CAPS="off 30 40 60 120"
# CPUs the game sees (ncpu): 2 up to this Mac's logical CPUs, or all
CPU_MAX="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
UI_SCALES="1.5 1.75 1.8 2.0"
setting_default() {
  case "$1" in
    retina|warm|fastlocks|uiscale_sans|uiscale_cinema|gamemode|updates|steambg|quitsteam) echo on ;;
    metalfx|hud|uiscale) echo off ;;
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
    retina|metalfx|hud|warm|fastlocks|uiscale|uiscale_sans|uiscale_cinema|gamemode|updates|debug|steambg|quitsteam)
      [ "$2" = on ] || [ "$2" = off ] ;;
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
write_settings() { # [<key> <value>]: settings.conf with every key, one of them changed
  local k v
  for k in $SETTING_KEYS; do
    v=$(setting "$k")
    if [ "$k" = "${1:-}" ]; then v=$2; fi
    echo "$k=$v"
  done | {
    echo "# GW2 on Mac settings (change them in the app: GW2 on Mac > Settings…)"
    cat
  } | put "$SETTINGS" 644
}

# dxmt.conf: DXMT's options for the game (DXMT_CONFIG_FILE)
write_dxmt_conf() {
  local cap
  cap=$(setting fpscap)
  {
    echo "# DXMT options for Guild Wars 2, written by GW2 on Mac from its settings (DXMT_CONFIG_FILE)."
    if [ "$cap" != off ]; then
      echo "# Frame cap: Metal-paced, a divisor of the display's refresh (use it with the game's vsync)"
      echo "d3d11.preferredMaxFrameRate = $cap"
    fi
  } | put "$DXMT_CONF" 644
}

# The game's environment at its start (play), from settings.conf; also what `env` prints
game_env() {
  local n qos
  E=(
    "WINEPREFIX=$BOTTLE"
    "WINEDEBUG=-all"
    "WINEDLLOVERRIDES=winemenubuilder.exe=d"
    "WINEMSYNC=1"
    "WINE_COMPATDB=$COMPATDB"
    # the engine's compatdb turns on x87sidecar for every process: GW2 is x86_64 with hardly any
    # x87 code, so it's off (as scripts/common.zsh)
    "ROSETTA_X87_PATH="
    # the heat ntdll.so (components/heat) applies these to Gw2-64.exe only
    "WINE_HEAT_EVPOOL=1"
    "WINE_HEAT_WAKE=one,skip"
    # round 7, in the mix: msync waits read the clock only for a relative timeout; msync's
    # contention bailout unregisters; the shm reply port's receive right is released
    "WINE_HEAT_LAZYCLOCK=1"
    "WINE_HEAT_MSYNC_UNREG=1"
    "WINE_HEAT_MSYNC_PORTFIX=1"
    "DXMT_CONFIG_FILE=$DXMT_CONF"
    "DXMT_LOG_PATH=$LOGS"
    # the caches under the app's own cache folder: $CACHE/dxmt/<exe>/ (jdrly/dxmt #134)
    "DXMT_CACHE_DIR=$CACHE"
    # the checkpoint-chain fence compression on Metal 4 (jdrly/dxmt #133; in the mix)
    "DXMT_DEPENDENCY_COMPRESSION=1"
  )
  n=$(setting ncpu)
  [ "$n" = all ] || E+=("WINENCPU=$n")
  # the Metal HUD on the game only: the heat ntdll.so sets MTL_HUD_ENABLED=1 in Gw2-64.exe at its
  # start (Metal reads it at a process's first device); in Steam's environment every process
  # Steam starts would show it (jdrly/dxmt #138)
  [ "$(setting hud)" = on ] && E+=("WINE_HEAT_METAL_HUD=1")
  [ "$(setting warm)" = on ] && E+=("DXMT_WARM=all")
  [ "$(setting metalfx)" = on ] && E+=("DXMT_SUBSAMPLE_METALFX=1")
  qos=$(setting coolworkers)
  [ "$qos" = off ] || E+=("WINE_HEAT_QOS=1=utility:$qos")
  [ "$(setting fastlocks)" = on ] && E+=("WINE_HEAT_SPIN=lock=20:game,event=30:game")
  if [ "$(setting debug)" = on ]; then
    E+=("WINE_HEAT_COUNT=1" "WINE_HEAT_LOG=$LOGS" "DXMT_LOG_LEVEL=debug" "WINEDEBUG=err+all,fixme-all")
  fi
  return 0
}

# --- Engine

# install_file <src> <dst> <mode> [<stock sha256>]: puts <src> in the engine's place, keeping the
# engine's own as <dst>.stock (checked against the known build when given)
install_file() {
  local src=$1 dst=$2 mode=$3 want=${4:-}
  if [ -n "$DRY" ]; then echo "[dry-run] engine's ${dst#"$ENG/"}: $(basename "$src") from the app"; return; fi
  if [ ! -f "$dst.stock" ] && [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    if [ -n "$want" ] && [ "$ENGINE_CHECKS" = 1 ] && [ "$(sha256 "$dst")" != "$want" ]; then
      die "The engine's ${dst#"$ENG/"} is not the expected build. Click Repair (or reinstall the engine in Settings › Troubleshooting)."
    fi
    run cp -p "$dst" "$dst.stock"
  fi
  run rm -f "$dst"
  run install -m "$mode" "$src" "$dst"
}

# GW2 on Mac's pieces in the engine: DXMT as the dxmt DXGI tree (the PE DLLs and winemetal.so of
# one build always together); the heat ntdll.so (the msync fix, the heat probes) and wineserver
# (msync unregister fix); winemac.so (the launcher fix) and win32u.so (its drawing at -O2)
install_components() {
  local u="$ENG/lib/wine/x86_64-unix" t="$ENG/lib/wine/dxgi/dxmt" f a
  say "Installing DXMT $DXMT_VERSION as the game's Direct3D 11 (the engine's dxmt tree)"
  if [ -z "$DRY" ]; then
    [ -d "$t" ] || die "The engine has no dxmt tree ($t). Reinstall the engine (Settings › Troubleshooting)."
    for a in x86_64-windows i386-windows x86_64-unix; do
      run mkdir -p "$t/$a"
      for f in "$COMP/dxmt/$a"/*; do
        [ -f "$f" ] || continue
        run rm -f "$t/$a/$(basename "$f")"
        run install -m 644 "$f" "$t/$a/$(basename "$f")"
      done
    done
    run chmod 755 "$t/x86_64-unix/winemetal.so"
    run cp "$COMP/dxmt/VERSION" "$COMP/dxmt/LICENSE" "$COMP/dxmt/COPYING.LIB" "$t/"
  else
    echo "[dry-run] DXMT files into $t"
  fi
  say "Installing the tuned Wine pieces: ntdll.so and wineserver (heat), winemac.so and win32u.so (the launcher fix)"
  install_file "$COMP/heat/ntdll.so" "$u/ntdll.so" 755 "$ENGINE_NTDLL_SHA256"
  install_file "$COMP/heat/wineserver" "$ENG/bin/wineserver" 755 "$ENGINE_WINESERVER_SHA256"
  install_file "$COMP/winemac/winemac.so" "$u/winemac.so" 755 "$ENGINE_WINEMAC_SHA256"
  install_file "$COMP/winemac/win32u.so" "$u/win32u.so" 755 "$ENGINE_WIN32U_SHA256"
  log "engine components: dxmt $DXMT_VERSION, ntdll $(sha256 "$COMP/heat/ntdll.so"), wineserver $(sha256 "$COMP/heat/wineserver"), winemac $(sha256 "$COMP/winemac/winemac.so"), win32u $(sha256 "$COMP/winemac/win32u.so")"
}

engine_ok() { [ -x "$ENG/bin/wine" ] && [ "$(cat "$ENG/.gw2om-source" 2>/dev/null || true)" = "$ENGINE_SHA256" ]; }

# Graphics in the engine: yes (this app's DXMT and Wine pieces), other (something else), no
graphics_state() {
  local u="$ENG/lib/wine/x86_64-unix" t="$ENG/lib/wine/dxgi/dxmt"
  [ -x "$ENG/bin/wine" ] || { echo no; return; }
  if cmp -s "$COMP/dxmt/x86_64-windows/d3d11.dll" "$t/x86_64-windows/d3d11.dll" &&
    cmp -s "$COMP/dxmt/x86_64-unix/winemetal.so" "$t/x86_64-unix/winemetal.so" &&
    cmp -s "$COMP/heat/ntdll.so" "$u/ntdll.so" && cmp -s "$COMP/winemac/winemac.so" "$u/winemac.so" &&
    cmp -s "$COMP/winemac/win32u.so" "$u/win32u.so" && cmp -s "$COMP/heat/wineserver" "$ENG/bin/wineserver"; then
    echo yes
  else
    echo other
  fi
}

# install_engine [force]: the verified engine unpacked into $ENG (unless it's there already),
# then GW2 on Mac's pieces
install_engine() {
  local dst="$ENG"
  if engine_ok && [ "${1:-}" != force ]; then
    say "The Wine engine ($ENGINE_TITLE, $ENGINE_NAME) is already in place"
  else
    fetch "$ENGINE_URL" "$ENGINE_SHA256" "$ENGINE_SIZE" "Wine engine" "$ENGINE_API_URL"
    say "Unpacking the Wine engine ($ENGINE_TITLE)"
    run rm -rf "$dst.new"
    run mkdir -p "$dst.new"
    run tar -xJf "$FETCHED" -C "$dst.new" --strip-components 1
    if [ -z "$DRY" ]; then
      chmod -R u+w "$dst.new"
      if [ "$ENGINE_CHECKS" = 1 ]; then
        [ "$(sha256 "$dst.new/lib/wine/x86_64-unix/wine")" = "$ENGINE_LOADER_SHA256" ] &&
          [ "$(sha256 "$dst.new/lib/wine/x86_64-unix/ntdll.so")" = "$ENGINE_NTDLL_SHA256" ] ||
          die "The unpacked Wine engine does not match the expected build."
      fi
      # its SDK (headers, Wine's conformance tests, man pages) is not needed to run it
      rm -rf "$dst.new/include" "$dst.new/lib/wine/tests" "$dst.new/share/man"
      echo "$ENGINE_SHA256" >"$dst.new/.gw2om-source"
    fi
    remove_gamemode_links   # they name the old engine's loader
    run rm -rf "$dst"
    run mv "$dst.new" "$dst"
    CREATED="$CREATED engine"
  fi
  install_components
}

# --- Game Mode
#
# macOS turns Game Mode on only for a full-screen process whose executable belongs to a bundle
# with LSSupportsGameMode, and every Wine process runs Wine's loader. As SWGL on Mac and
# scripts/common.zsh do it: while WINEDLLPATH is set, CrossOver's ntdll starts each process from
# a link in $TMPDIR/winetemp-<loader ino>-<size>-<mtime s>-<mtime ns>/ named after its exe, and
# reuses what is there. Steam starts the game, so the link is Gw2-64.exe (APFS is case-
# insensitive) and points at a bundle with an unsigned copy of the loader under that name and an
# ntdll.so link back to the engine.
install_gamemode() {
  local app="$GAMEMODE_APP" new loader="$ENG/lib/wine/x86_64-unix/wine"
  say "Creating the Game Mode bundle"
  new="$APPDIR/gamemode/.GW2.app.new.$$"
  run rm -rf "$new"
  run mkdir -p "$new/Contents/MacOS"
  put "$new/Contents/Info.plist" 644 <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Gw2-64.exe</string>
	<key>CFBundleIdentifier</key><string>cz.jandrly.gw2onmac.game</string>
	<key>CFBundleName</key><string>Guild Wars 2</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.role-playing-games</string>
	<key>LSSupportsGameMode</key><true/>
	<key>GCSupportsGameMode</key><true/>
</dict>
</plist>
EOF
  run cp -c "$loader" "$new/Contents/MacOS/Gw2-64.exe"
  if [ -z "$DRY" ]; then codesign --remove-signature "$new/Contents/MacOS/Gw2-64.exe" 2>/dev/null || true; fi
  # (relative: Contents/MacOS -> APPDIR/engine/lib/wine/x86_64-unix/ntdll.so)
  run ln -s "../../../../engine/lib/wine/x86_64-unix/ntdll.so" "$new/Contents/MacOS/ntdll.so"
  if [ -z "$DRY" ]; then stat -f '%i-%z-%m' "$loader" >"$new/Contents/.source"; fi
  run rm -rf "$app"
  run mv "$new" "$app"
}
gamemode_current() {
  [ -x "$GAMEMODE_APP/Contents/MacOS/Gw2-64.exe" ] &&
    [ "$(cat "$GAMEMODE_APP/Contents/.source" 2>/dev/null || true)" = "$(stat -f '%i-%z-%m' "$ENG/lib/wine/x86_64-unix/wine" 2>/dev/null || echo none)" ]
}
winetemp_dir() {
  local l="$ENG/lib/wine/x86_64-unix/wine" m
  m=$(stat -f '%Fm' "$l")
  echo "${USER_TMP}winetemp-$(stat -f '%i-%z' "$l")-${m%.*}-$((10#${m#*.}))"
}
# The link for this start (play), and WINEDLLPATH in E
gamemode_link() {
  local dir
  [ "$(setting gamemode)" = on ] || return 0
  E+=("WINEDLLPATH=$ENG/lib/wine")
  if [ -n "$DRY" ]; then echo "[dry-run] link <winetemp of the engine's loader>/Gw2-64.exe -> $GAMEMODE_APP/Contents/MacOS/Gw2-64.exe"; return; fi
  gamemode_current || install_gamemode >/dev/null
  dir=$(winetemp_dir)
  mkdir -p -m 700 "$dir" && ln -sfn "$GAMEMODE_APP/Contents/MacOS/Gw2-64.exe" "$dir/Gw2-64.exe" || return 0
  # steam.exe, the command's first process, must not run from the game's bundle
  [ -L "$dir/wine" ] && rm -f "$dir/wine"
  echo "$(date '+%F %T') game mode: $dir/Gw2-64.exe -> $GAMEMODE_APP/Contents/MacOS/Gw2-64.exe" >>"$LOGS/gamemode.log"
}
remove_gamemode_links() {
  local l="$ENG/lib/wine/x86_64-unix/wine" dir
  [ -f "$l" ] || return 0
  dir=$(winetemp_dir)
  if [ -L "$dir/Gw2-64.exe" ]; then run rm -f "$dir/Gw2-64.exe"; say "Removed the Game Mode link $dir/Gw2-64.exe"; fi
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
# never touched); the registry override follows (apply_registry)
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

# --- Existing game files (install import): another Wine app's Guild Wars 2, cloned into the bottle
# (the same disk: APFS clonefile, instant and without extra space) or copied (another disk). The
# source is only read: its files, its bottle and its app stay as they are.

# Where a bottle keeps the game: Steam's default library, ArenaNet's default folder
GAME_RELS=("Program Files (x86)/Steam/steamapps/common/Guild Wars 2" "Program Files/Steam/steamapps/common/Guild Wars 2"
  "Program Files/Guild Wars 2" "Program Files (x86)/Guild Wars 2")

# The drive_c of every bottle other Wine apps keep in their known places: CrossOver's bottles,
# Whisky's, app wrappers (Sikarugir, Kegworks, Wineskin, Porting Kit: <app>/Contents/...),
# Heroic's prefixes, ~/.wine; GameHub doesn't document where it keeps its bottles, so its folders
# are looked through (a few levels). Anything else: Choose folder… (check-game).
wine_places() {
  local d a
  for d in "$H/Library/Application Support/CrossOver/Bottles"/*/drive_c \
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
  case "$d/" in "$BOTTLE/"*) echo "@error That is GW2 on Mac's own copy of the game."; exit 1 ;; esac
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
# free-space check and progress); our own addon's files (version.dll with its mark,
# gw2-ui-scale.*) are left out; any other addon comes along as it is (ADDONS names them)
import_game() {
  local src=$1 dst=$2 total pid
  total=$(folder_bytes "$src")
  if [ -e "$dst" ]; then
    [ -z "$(ls -A "$dst" 2>/dev/null)" ] ||
      die "The game's bottle already has a Guild Wars 2 folder ($dst). Uninstall GW2 on Mac first to use your own game files."
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
  if [ -f "$dst/version.dll" ] && grep -aq "$UI_MARK" "$dst/version.dll"; then run rm -f "$dst/version.dll"; fi
  run rm -f "$dst/gw2-ui-scale.ini" "$dst/gw2-ui-scale.log"
  chmod -R u+w "$dst"
  ADDONS=$( (cd "$dst" && ls -d ./*.dll addons bin64/d3d9.dll 2>/dev/null || true) | sed 's|^\./||' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  [ -z "$ADDONS" ] || say "Addons that came along with the game's files: $ADDONS (GW2 on Mac leaves them as they are)"
  log "game files $IMPORT_HOW: $src -> $dst ($total bytes)"
}

# The bottle's Windows user (CrossOver's engine: crossover)
bottle_user() {
  local u
  for u in "$BOTTLE/drive_c/users"/*; do
    [ -d "$u" ] || continue
    case "$(basename "$u")" in Public|public) continue ;; esac
    basename "$u"; return
  done
  echo crossover
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
  backup="$to/GW2 on Mac backup $(date '+%Y-%m-%d %H%M%S')"
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
    echo "@done Guild Wars 2 is ready: its files were $how$([ "$SETTINGS_IMPORTED" = yes ] && echo ", with your game settings").$([ -z "$ADDONS" ] || echo " Addons that came along: $ADDONS; GW2 on Mac leaves them as they are.")$([ "$route" = steam ] && echo " Steam may check the files at the first Play.") Press Play."
  else
    step "Steam opens: sign in, and it brings Guild Wars 2 up to date"
    launch "$STEAM_EXE" "steam://install/$GW2_APPID"
    set_state stage waiting_game
    IMPORT_DST="" IMPORT_ACF=""
    log "install import: Steam's record of the game is not complete; waiting for Steam"
    echo "@done Your game files were $how. Steam is starting: sign in, and it brings the game up to date; this window follows it."
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
  set -- $(pos "$attrs"); o=$1 hl=$2 l=$3
  { printf '\061'; bytes "$t/sig.der" $((o + 1)) $((hl + l - 1)); } >"$t/attrs.der"
  md=$(grep -A2 ':messageDigest$' "$t/asn1.txt" | grep -m1 'OCTET STRING' | sed 's/.*\[HEX DUMP\]://' | tr 'A-F' 'a-f')
  [ "$md" = "$(shasum -a "${alg#sha}" "$t/spc.bin" | cut -d' ' -f1)" ] || setup_bad "The signature of this file is not valid."
  # the signature: the OCTET STRING after the signed attributes' end
  sigline=$(awk -v end=$((o + hl + l)) '{ split($1, a, ":"); if (a[1] + 0 >= end && /OCTET STRING/) { print; exit } }' "$t/asn1.txt")
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
  echo "dxmt=$DXMT_VERSION"
  echo "root=${ROOT:-/}"
  echo "app_dir=$APPDIR"
  echo "rosetta=$(rosetta_ok && echo yes || echo no)"
  echo "arch=$(uname -m)"
  echo "macos=$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  [ -f "$MANIFEST" ] && engine_ok && [ -f "$BOTTLE/system.reg" ] && installed=yes
  echo "installed=$installed"
  echo "installed_version=$(json_get "$MANIFEST" version)"
  echo "engine_installed=$(engine_ok && echo yes || echo no)"
  echo "graphics=$(graphics_state)"
  if [ "$(setting gamemode)" != on ]; then echo "gamemode=off"
  elif gamemode_current; then echo "gamemode=yes"; else echo "gamemode=no"; fi
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
  echo "uiscale=$(setting uiscale)"
}

settings() {
  local k
  echo "installed=$([ -f "$MANIFEST" ] && echo yes || echo no)"
  if session_running; then echo "running=yes"; else echo "running=no"; fi
  echo "route=$(state route)"
  for k in $SETTING_KEYS; do echo "$k=$(setting "$k")"; done
  echo "uiscale_state=$(uiscale_state)"
  echo "cpus=$CPU_MAX"
  echo "steam_login=$(steam_remembers_login && echo yes || echo no)"
}

cmd_set() {
  local key="${1:-}" value="${2:-}"
  setting_valid "$key" "$value" || { echo "@error Unknown setting: $key=$value"; exit 2; }
  [ -f "$MANIFEST" ] || die "GW2 on Mac is not installed."
  open_log
  log "---- set $key=$value"
  lock
  trap 'rmdir "$APPDIR/.lock" 2>/dev/null || true' EXIT
  write_settings "$key" "$value"
  case "$key" in
    fpscap) write_dxmt_conf ;;
    uiscale|uiscale_size|uiscale_sans|uiscale_cinema) sync_uiscale; apply_registry ;;
    retina) apply_registry ;;
    gamemode) [ "$value" = off ] || gamemode_current || install_gamemode ;;
  esac
  if session_running; then
    echo "@done $key=$value. It takes effect the next time the game starts after Steam has quit."
  else
    echo "@done $key=$value. It takes effect the next time the game starts."
  fi
}

lock() {
  [ -n "$DRY" ] && return
  mkdir -p "$APPDIR" "$LOGS"
  mkdir "$APPDIR/.lock" 2>/dev/null || die "Another GW2 on Mac install, repair or uninstall is running."
}

write_manifest() {
  put "$MANIFEST" 644 <<EOF
{
  "app": "GW2 on Mac",
  "version": "$VERSION",
  "installed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "route": "$(state route)",
  "engine": "$ENGINE_NAME",
  "engine_sha256": "$ENGINE_SHA256",
  "dxmt": "$DXMT_VERSION",
  "ntdll_sha256": "$(sha256 "$COMP/heat/ntdll.so")",
  "wineserver_sha256": "$(sha256 "$COMP/heat/wineserver")",
  "winemac_sha256": "$(sha256 "$COMP/winemac/winemac.so")",
  "win32u_sha256": "$(sha256 "$COMP/winemac/win32u.so")",
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
    rm -rf "$APPDIR"/*.new "$APPDIR/gamemode"/.GW2.app.new.* 2>/dev/null || true
    log "install failed (status $st)"
  fi
  rmdir "$APPDIR/.lock" 2>/dev/null || true
}

# preflight [import]: (an import checks the space its copy needs itself)
preflight() {
  [ "$(uname -m)" = arm64 ] || die "GW2 on Mac needs a Mac with Apple silicon."
  rosetta_ok || die "Rosetta is not installed. Install it (softwareupdate --install-rosetta in Terminal), then try again."
  check_not_running
  local avail
  avail=$(free_kb)
  [ "${avail:-0}" -gt 3000000 ] || die "Not enough free disk space (the engine and Steam need about 3 GB, the game about 75 GB)."
  [ "${1:-}" = import ] || [ "$((${avail:-0} * 1024))" -ge "$DISK_NEEDED" ] || warn "Only $(( ${avail:-0} / 1000000 )) GB free: Guild Wars 2 needs about 75 GB."
}

# The bottle: created once (wineboot), then its settings (registry, dxmt.conf) and Game Mode
install_bottle() {
  if [ ! -f "$BOTTLE/system.reg" ]; then
    say "Creating the game's bottle (wineboot, about a minute)"
    run rm -rf "$BOTTLE"
    run mkdir -p "$BOTTLE"
    CREATED="$CREATED bottle"
    # no Mono or Gecko: Steam and the game need neither
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
  install_gamemode
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

# launch <program> <args...>: a program in the bottle with the game's environment, detached; the
# session's environment goes to logs/session.env (Collect Logs, the session report)
launch() {
  local e
  game_env
  gamemode_link
  if [ -n "$DRY" ]; then
    echo "[dry-run] environment:"; for e in "${E[@]}"; do printf '[dry-run]   %s\n' "$e"; done
    echo "[dry-run] wine $*"
    return
  fi
  wine_allowed
  mkdir -p "$LOGS"
  if ! session_running; then
    rotate_logs
    { echo "STARTED=$(date '+%F %T')"; echo "APP=$VERSION"; echo "ROUTE=$(state route)"; echo "DXMT=$DXMT_VERSION"
      for k in $SETTING_KEYS; do echo "SETTING_$k=$(setting "$k")"; done
      printf '%s\n' "${E[@]}" | grep -v '^WINE_COMPATDB='; } >"$LOGS/session.env"
    printf '%s\n' "${E[@]}" | shasum | cut -c1-12 >"$LOGS/session.key"
  fi
  echo "=== $(date '+%F %T') $*" >>"$LOGS/wine.log"
  ( cd "$BOTTLE" && env -u WINELOADER -u WINESERVER -u DYLD_FALLBACK_LIBRARY_PATH "${E[@]}" \
      nohup "$ENG/bin/wine" "$@" </dev/null >>"$LOGS/wine.log" 2>&1 & )
  log "started: $*"
}

# --- The session's watcher (watch-session)
#
# Play records the session in $SESSION and starts watch-session detached (nohup: it outlives the
# app's window, which "Quit GW2 on Mac after launching" closes). The watcher follows the session
# through proc_list (only this engine's processes): it waits for Gw2-64.exe, then for its exit and
# a grace, and then, if Play started Steam itself in the background with Quit Steam when the game
# quits on, asks Steam to quit (steam.exe -shutdown), with wineserver -k for this bottle as the
# fallback. Steam that already ran, or whose window showed, is left alone. Everything goes to
# install.log under "---- session". The keys (lane B's session-status reads them too):
#   route          steam|arenanet
#   started_steam  yes: no Steam of the bottle ran before this Play
#   steam_window   hidden (-silent) | shown (Steam's window; empty on the ArenaNet route)
#   quit_steam     yes: the watcher quits Steam after the game (the decision at Play)
#   watcher_pid    the watcher's pid
#   stage          waiting_game|playing|grace|closing_steam|done
#   started, game_started, game_ended, updated   seconds since 1970
#   result         at done: quit, killed (wineserver -k), left_running, steam_already_gone,
#                  timeout, steam_gone (Steam quit before the game appeared), no_game (ArenaNet:
#                  nothing started), uninstalled, ended (stopped otherwise)
SESSION_KEYS="route started_steam steam_window quit_steam watcher_pid stage started game_started game_ended updated result"
session_get() { sed -n "s/^$1=//p" "$SESSION" 2>/dev/null | tail -1; }
# session_set <key> <value> [<key> <value>...]: changes those keys (and updated), atomically
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
# has_kind <kind> <proc_list output>
has_kind() { case "
$2" in *"
$1 "*) return 0 ;; esac; return 1; }

# watcher_alive: the lock is held by a live watcher (or by a Play handing the session over to one)
watcher_alive() {
  local p
  [ -d "$WATCH_LOCK" ] || return 1
  p=$(cat "$WATCH_LOCK/pid" 2>/dev/null || true)
  if [ -z "$p" ]; then
    # just taken (its pid follows at once); stale after 10 seconds
    [ $(( $(date +%s) - $(stat -f %m "$WATCH_LOCK" 2>/dev/null || echo 0) )) -lt 10 ]
    return
  fi
  ps -p "$p" -o command= 2>/dev/null | grep -q 'gw2om\.sh'
}
# take_watch_lock: the session's lock for this process (a stale one is taken over)
take_watch_lock() {
  mkdir -p "$APPDIR"
  if ! mkdir "$WATCH_LOCK" 2>/dev/null; then
    watcher_alive && return 1
    rm -rf "$WATCH_LOCK"
    mkdir "$WATCH_LOCK" 2>/dev/null || return 1
  fi
  echo $$ >"$WATCH_LOCK/pid"
}
# drop_watch_lock: only if this process holds it
drop_watch_lock() {
  [ "$(cat "$WATCH_LOCK/pid" 2>/dev/null || true)" = $$ ] && rm -rf "$WATCH_LOCK"
  return 0
}
# stop_watcher: ends the session's watcher (uninstall) and waits for it
stop_watcher() {
  local p i
  watcher_alive || return 0
  p=$(cat "$WATCH_LOCK/pid" 2>/dev/null || true)
  [ -n "$p" ] && [ "$p" != $$ ] || return 0
  if [ -n "$DRY" ]; then echo "[dry-run] stop the session's watcher (pid $p)"; return 0; fi
  kill "$p" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$p" 2>/dev/null || break; sleep 0.2; done
  log "session: stopped its watcher (pid $p)"
}

# watch_exit: the watcher's end, however it ends
watch_exit() {
  [ "$(session_get stage)" = done ] || session_set stage done result "${WATCH_RESULT:-ended}"
  log "session: done (${WATCH_RESULT:-ended})"
  drop_watch_lock
}

# watch_poll: proc_list into WL, after a pause; WATCH_RESULT=uninstalled and false once the app's
# install is gone
watch_poll() {
  sleep "$WATCH_POLL"
  [ -f "$MANIFEST" ] || { WATCH_RESULT=uninstalled; log "session: GW2 on Mac was uninstalled; stopping"; return 1; }
  WL=$(proc_list)
}

# watch-session [--handoff]: Play starts it with --handoff (its lock is handed over: the pid in it
# becomes this one's); by hand, it takes the lock or says another watcher follows the session
cmd_watch_session() {
  local i start now last ended back route quit why
  open_log
  if [ -n "$DRY" ]; then echo "[dry-run] watch-session"; return 0; fi
  if [ "${1:-}" = --handoff ]; then
    i=0
    while [ "$(cat "$WATCH_LOCK/pid" 2>/dev/null || true)" != $$ ]; do
      [ $i -lt 50 ] || { log "session: the watcher (pid $$) was not handed the session; another one follows it"; return 0; }
      sleep 0.1; i=$((i + 1))
    done
  else
    take_watch_lock || { echo "@done Another watcher follows this session (pid $(cat "$WATCH_LOCK/pid" 2>/dev/null || true))."; return 0; }
    case "$(session_get stage)" in ''|done) drop_watch_lock; echo "@done No session to follow."; return 0 ;; esac
  fi
  WATCH_RESULT=""
  trap watch_exit EXIT
  trap 'exit 143' TERM INT
  route=$(session_get route) quit=$(session_get quit_steam)
  start=$(date +%s)
  log "---- session $VERSION route=$route started_steam=$(session_get started_steam) steam_window=$(session_get steam_window) quit_steam=$quit (watcher pid $$)"
  session_set stage waiting_game watcher_pid $$

  # 1. Guild Wars 2 starts (Steam may update itself and sign in first). Steam and the bottle's
  # wineserver gone for the grace (Steam restarts itself after an update) without the game means
  # Steam was closed: left as it is.
  last=$start
  while :; do
    watch_poll || return 0
    now=$(date +%s)
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
  session_set stage playing game_started "$now" game_ended ""
  log "session: Guild Wars 2 started ($((now - start)) s after Play)"
  while :; do
    while has_kind game "$WL"; do watch_poll || return 0; done
    ended=$(date +%s)
    session_set stage grace game_ended "$ended"
    log "session: Guild Wars 2 quit; waiting $WATCH_GRACE s in case it starts again (its patcher, a restart)"
    back=no
    while [ $(( $(date +%s) - ended )) -lt "$WATCH_GRACE" ]; do
      watch_poll || return 0
      if has_kind game "$WL"; then back=yes; break; fi
    done
    [ "$back" = yes ] || break
    session_set stage playing game_ended ""
    log "session: Guild Wars 2 started again within the grace"
  done

  # 3. Steam quits, if Play started it in the background and the setting is (still) on
  why=""
  if [ "$quit" != yes ]; then
    if [ "$route" != steam ]; then why="the ArenaNet route has no Steam"
    elif [ "$(session_get started_steam)" != yes ]; then why="Steam already ran before Play"
    elif [ "$(session_get steam_window)" != hidden ]; then why="Steam's window was shown (no remembered login, or Start Steam in the background off)"
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
  session_set stage closing_steam
  wine_allowed
  game_env
  log "session: asking Steam to quit (steam.exe -shutdown)"
  echo "=== $(date '+%F %T') $STEAM_EXE -shutdown (the game quit)" >>"$LOGS/wine.log"
  ( cd "$BOTTLE" && env -u WINELOADER -u WINESERVER -u DYLD_FALLBACK_LIBRARY_PATH "${E[@]}" \
      nohup "$ENG/bin/wine" "$STEAM_EXE" -shutdown </dev/null >>"$LOGS/wine.log" 2>&1 & )
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
    case "$src/" in "$BOTTLE/"*) echo "@error That is GW2 on Mac's own copy of the game."; exit 2 ;; esac
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
  log "---- install $route${src:+ import $src} $VERSION (dxmt $DXMT_VERSION, engine $ENGINE_NAME) root=${ROOT:-/} dry=${DRY:-0}"
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
# interface addon, the registry settings, Game Mode, stage=finished
finish_touches() {
  say "The shader cache: $DXMT_CACHE (DXMT fills it while you play; warming builds ahead)"
  run mkdir -p "$DXMT_CACHE"
  sync_uiscale
  apply_registry
  gamemode_current || [ "$(setting gamemode)" != on ] || install_gamemode
  [ -n "$DRY" ] || { set_state stage finished; set_state game_dir "$GAME_DIR"; }
  write_manifest
}

# Phase 5, once the game is there
cmd_finish() {
  open_log
  log "---- finish $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  [ -f "$MANIFEST" ] || die "GW2 on Mac is not installed."
  phase 5
  step "Finishing touches"
  game_state
  [ "$GAME" = yes ] || [ -n "$DRY" ] || die "Guild Wars 2 is not installed yet."
  lock
  trap 'rmdir "$APPDIR/.lock" 2>/dev/null || true' EXIT
  finish_touches
  log "finish complete"
  echo "@done Guild Wars 2 is ready. Press Play."
}

cmd_stop_waiting() {
  [ "$(state stage)" = waiting_game ] || { echo "@done not waiting"; return; }
  [ -n "$DRY" ] || set_state stage none
  echo "@done Stopped following the game's download. Install picks up from there."
}

# Repair: the engine (unpacked again if it isn't the expected one), GW2 on Mac's pieces in it,
# the bottle's settings and Game Mode; Steam again if it is gone; the game and settings stay
cmd_repair() {
  CREATED="" FETCH_PID=""
  open_log
  log "---- repair $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  [ -f "$MANIFEST" ] || [ -d "$ENG" ] || die "GW2 on Mac is not installed."
  phase 1
  step "Checking your Mac"
  preflight
  lock
  trap on_install_exit EXIT
  trap 'exit 143' TERM INT HUP
  step "The Wine engine"
  if engine_ok && [ "$ENGINE_CHECKS" = 1 ] && [ -f "$ENG/lib/wine/x86_64-unix/wine" ] &&
    [ "$(sha256 "$ENG/lib/wine/x86_64-unix/wine")" != "$ENGINE_LOADER_SHA256" ]; then
    warn "The engine's loader changed; unpacking the engine again"
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
  echo "@done Repaired: the engine, the graphics, the bottle's settings and Game Mode are set up again."
}

cmd_reinstall_engine() {
  CREATED="" FETCH_PID=""
  open_log
  log "---- reinstall-engine $VERSION"
  [ -d "$ENG" ] || die "GW2 on Mac is not installed."
  check_not_running
  lock
  trap on_install_exit EXIT
  install_engine force
  install_gamemode
  echo "@done The engine was unpacked again with GW2 on Mac's pieces."
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
  [ -f "$MANIFEST" ] && engine_ok || [ -n "$DRY" ] || die "GW2 on Mac is not installed. Install it first."
  [ "$(state stage)" = finished ] || [ -n "$DRY" ] || die "Guild Wars 2 is not installed yet."
  game_state
  [ "$GAME" = yes ] || [ -n "$DRY" ] || die "Guild Wars 2 is not in the bottle any more. Install it again (Uninstall, then Install)."
  case "$(busy_of "$(proc_list)")" in
    game) echo "@done Guild Wars 2 is already running."; return ;;
    installer) die "ArenaNet's installer is still running. Let it finish first." ;;
    leftovers) end_leftovers ;;
  esac
  if ! session_running; then
    apply_registry
    write_dxmt_conf
  fi
  [ "$(graphics_state)" = yes ] || [ -n "$DRY" ] || warn "The engine's graphics are not GW2 on Mac's. Click Repair."
  # A running session keeps the settings it started with: Steam passes its own environment on
  if session_running && [ -f "$LOGS/session.key" ]; then
    game_env
    key=$(printf '%s\n' "${E[@]}" | shasum | cut -c1-12)
    [ "$key" = "$(cat "$LOGS/session.key")" ] ||
      echo "@notice Steam is still running with the settings it started with; quit Steam for the new ones."
  fi
  # The session (watch-session): a new one unless a watcher still follows the last one (a second
  # Play while Steam starts the game keeps it, and what it knew about Steam)
  local fresh=no steam_before=no route silent="" quit=no
  route=$(state route)
  [ "$route" = arenanet ] || route=steam
  if [ -z "$DRY" ]; then
    if take_watch_lock; then
      fresh=yes
      trap drop_watch_lock EXIT
      has_kind steam "$(proc_list)" && steam_before=yes
    else
      [ "$(session_get stage)" != closing_steam ] || die "Steam is quitting after your last session. Try again in a few seconds."
    fi
  fi
  if [ "$route" = arenanet ]; then
    # shellcheck disable=SC2086
    launch "$GAME_EXE" $(setting launchopts)
  else
    # Once Steam remembers a login, it starts without its window (-silent): it signs in by itself
    # and starts the game. Before the first sign-in its window shows, as at the install.
    if [ "$(setting steambg)" = on ] && steam_remembers_login; then silent=-silent; fi
    # shellcheck disable=SC2086
    launch "$STEAM_EXE" ${silent:+"$silent"} -applaunch "$GW2_APPID" $(setting launchopts)
  fi
  if [ -n "$DRY" ]; then
    echo "[dry-run] watch-session"
  elif [ "$fresh" = yes ]; then
    # Steam quits after the game only if this Play started it, without its window, and the
    # setting is on
    [ "$route" = steam ] && [ "$steam_before" = no ] && [ -n "$silent" ] && [ "$(setting quitsteam)" = on ] && quit=yes
    { echo "route=$route"; echo "started_steam=$([ "$route" = steam ] && [ "$steam_before" = no ] && echo yes || echo no)"
      echo "steam_window=$([ "$route" = steam ] && { [ -n "$silent" ] && echo hidden || echo shown; } || true)"
      echo "quit_steam=$quit"; echo "watcher_pid="; echo "stage=waiting_game"; echo "started=$(date +%s)"
      echo "game_started="; echo "game_ended="; echo "updated=$(date +%s)"; echo "result="; } >"$SESSION.new.$$"
    mv -f "$SESSION.new.$$" "$SESSION"
    nohup /bin/bash "$RES/gw2om.sh" watch-session --handoff </dev/null >/dev/null 2>&1 &
    local wpid=$!
    session_set watcher_pid "$wpid"
    echo "$wpid" >"$WATCH_LOCK/pid"
    trap - EXIT
    log "session: watcher started (pid $wpid), quit_steam=$quit"
  else
    log "session: the watcher of the running session (pid $(cat "$WATCH_LOCK/pid" 2>/dev/null || true)) follows this Play too"
  fi
  echo "@done Starting Guild Wars 2."
}

cmd_env() {
  game_env
  gamemode_link >/dev/null 2>&1 || true
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
  trap 'rmdir "$APPDIR/.lock" "$APPDIR" 2>/dev/null || true' EXIT
  stop_watcher
  [ -n "$DRY" ] || stop_wine
  remove_gamemode_links
  phase 2
  step "Removing the bottle (Steam and the game in it)"
  if [ -d "$BOTTLE" ]; then run rm -rf "$BOTTLE"; fi
  phase 3
  step "Removing the engine, Game Mode, the settings and caches"
  for c in $APP_FILES; do
    if [ -e "$APPDIR/$c" ]; then run rm -rf "${APPDIR:?}/$c"; fi
  done
  # (DXMT's caches are in it: $CACHE/dxmt)
  if [ -d "$CACHE" ]; then run rm -rf "$CACHE"; say "Removed the caches, DXMT's with them ($CACHE)"; fi
  log "uninstall complete"
  echo "@done GW2 on Mac is removed, with the bottle and the game in it. Logs stay in $LOGS."
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
  *) sed -n '2,/^# Environment/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
