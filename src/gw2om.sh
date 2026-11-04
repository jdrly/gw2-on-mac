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
#   gw2om.sh finish            phase 5 once the game is there: the shader cache's folder, the
#                              interface addon (if on), the registry settings, the manifest
#   gw2om.sh stop-waiting      the window stops following the game's download (the engine and
#                              the bottle stay; Install picks up from there)
#   gw2om.sh repair            engine, graphics, Wine pieces, bottle settings and Game Mode again;
#                              keeps the game and the settings
#   gw2om.sh uninstall         removes everything this app created: the bottle (with the game in
#                              it), the engine, Game Mode, the settings, DXMT's caches; logs stay
#   gw2om.sh play              starts the game (Steam: steam.exe -applaunch 1284210; ArenaNet:
#                              Gw2-64.exe) with the settings as its environment
#   gw2om.sh settings          KEY=VALUE lines: the settings (Settings window) and their state
#   gw2om.sh set K V           change one setting (see setting_valid)
#   gw2om.sh check-setup FILE  is FILE ArenaNet's Gw2Setup-64.exe: a PE x86_64 executable with a
#                              valid Authenticode signature by ArenaNet ("@done <what>")
#   gw2om.sh reset-shaders     deletes DXMT's caches for the game (shaders, pipelines, recipes)
#   gw2om.sh reinstall-engine  unpacks the engine again and puts GW2 on Mac's pieces back
#   gw2om.sh end-leftovers     ends leftover Wine processes of the engine (no session running)
#   gw2om.sh fetch-engine      downloads and verifies the engine into the cache
#   gw2om.sh env               the game's environment as play would set it (for Terminal)
#
# Environment:
#   GW2_ON_MAC_ROOT=/abs/dir   sandbox for tests: the app's files, logs, caches and the per-user
#                              temp and cache folders all live under it ($ROOT/home/Library/...,
#                              $ROOT/usertmp/, $ROOT/usercache/)
#   GW2_ON_MAC_DRY_RUN=1       print what would change and change nothing (no downloads, no Wine,
#                              no log file)
#   In a sandbox only, for app/scripts/test-sandbox.sh's stand-ins (never the real Wine there):
#   GW2_ON_MAC_ENGINE_URL, GW2_ON_MAC_ENGINE_SHA256, GW2_ON_MAC_ENGINE_SIZE   another engine
#                              archive (a stand-in whose bin/wine only pretends)
#   GW2_ON_MAC_ENGINE_CHECKS=0 don't check the unpacked engine's files against the real engine's
#   GW2_ON_MAC_STEAMSETUP_URL  another SteamSetup.exe
#   GW2_ON_MAC_SIGNER          the signer check-setup accepts (default ArenaNet)
#   GW2_ON_MAC_ALLOW_WINE=1    let the real engine's Wine run in a sandbox (never in the tests)
#
# Lines for the app start with "@": "@phase <n>" (the timeline: install 1 engine, 2 bottle,
# 3 Steam or ArenaNet's installer, 4 the game's download, 5 finishing touches; uninstall 1 stop,
# 2 bottle, 3 the rest), "@step <text>", "@progress <label> <bytes> <total>", "@warn <text>",
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

# --- Paths
ROOT="${GW2_ON_MAC_ROOT:-}"
DRY="${GW2_ON_MAC_DRY_RUN:-}"
if [ -n "$ROOT" ]; then
  case "$ROOT" in /*) ;; *) echo "@error GW2_ON_MAC_ROOT must be an absolute path"; exit 2 ;; esac
  if [ -d "$ROOT" ]; then ROOT="$(cd "$ROOT" && pwd -P)"; fi
  H="$ROOT/home"
  USER_TMP="$ROOT/usertmp/"
  USER_CACHE="$ROOT/usercache/"
  ENGINE_URL="${GW2_ON_MAC_ENGINE_URL:-$ENGINE_URL}"
  [ -z "${GW2_ON_MAC_ENGINE_URL:-}" ] || ENGINE_API_URL=""
  ENGINE_SHA256="${GW2_ON_MAC_ENGINE_SHA256:-$ENGINE_SHA256}"
  ENGINE_SIZE="${GW2_ON_MAC_ENGINE_SIZE:-$ENGINE_SIZE}"
  ENGINE_CHECKS="${GW2_ON_MAC_ENGINE_CHECKS:-1}"
  STEAM_SETUP_URL="${GW2_ON_MAC_STEAMSETUP_URL:-$STEAM_SETUP_URL}"
  SIGNER="${GW2_ON_MAC_SIGNER:-ArenaNet}"
else
  H="$HOME"
  USER_TMP="$(getconf DARWIN_USER_TEMP_DIR)"
  # the per-user cache folder (/var/folders/.../C/), where DXMT keeps its caches for the game in
  # dxmt/Gw2-64.exe/ (shaders, pipeline archives, recorded pipelines)
  USER_CACHE="$(getconf DARWIN_USER_CACHE_DIR)"
  ENGINE_CHECKS=1
  SIGNER=ArenaNet
fi
APPDIR="$H/Library/Application Support/GW2 on Mac"
LOGS="$H/Library/Logs/GW2 on Mac"
CACHE="$H/Library/Caches/GW2 on Mac"
ENG="$APPDIR/engine"                  # the unpacked engine with GW2 on Mac's pieces
BOTTLE="$APPDIR/bottle"               # the game's Wine prefix (Steam and the game live in it)
GAMEMODE_APP="$APPDIR/gamemode/GW2.app"
SETTINGS="$APPDIR/settings.conf"
STATE="$APPDIR/state"                 # route, stage (none|waiting_game|finished), game_dir
MANIFEST="$APPDIR/install-manifest.json"
DXMT_CONF="$APPDIR/dxmt.conf"
DXMT_CACHE="${USER_CACHE}dxmt/Gw2-64.exe"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
# What uninstall removes in APPDIR (the folder itself goes too once empty)
APP_FILES="engine bottle gamemode settings.conf state install-manifest.json dxmt.conf engine.new bottle.new"
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
  while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
  { df -k "$d" 2>/dev/null || true; } | awk 'NR == 2 { print $4 }'
}

# state <key>: a value of the state file; set_state <key> <value>
state() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | tail -1; }
set_state() {
  local k
  { for k in route stage game_dir game_exe; do
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
# The defaults are the mix Jan plays with (scripts/common.zsh, docs/research). Some are newer than
# the rest; Settings turns each off:
#   warm=on          DXMT_WARM=all: pipelines built ahead by recent use (jdrly/dxmt #128)
#   coolworkers=3    HEAT_QOS=1=utility:3: only the first 3 job workers on the cooler cores
#   fastlocks=on     HEAT_SPIN=lock=20:game,event=30:game: short spins before sleeps (round 7)
# (and, with no setting of their own, DXMT_DEPENDENCY_COMPRESSION=1, the checkpoint chain, #133,
# and round 7's HEAT_LAZYCLOCK, HEAT_MSYNC_UNREG and HEAT_MSYNC_PORTFIX: see game_env)
SETTING_KEYS="retina fpscap metalfx hud warm coolworkers fastlocks ncpu uiscale uiscale_size uiscale_sans uiscale_cinema gamemode launchopts updates debug"
FPS_CAPS="off 30 40 60 120"
CPU_COUNTS="4 6 8 10 12 all"
UI_SCALES="1.5 1.75 1.8 2.0"
setting_default() {
  case "$1" in
    retina|warm|fastlocks|uiscale_sans|uiscale_cinema|gamemode|updates) echo on ;;
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
    retina|metalfx|hud|warm|fastlocks|uiscale|uiscale_sans|uiscale_cinema|gamemode|updates|debug)
      [ "$2" = on ] || [ "$2" = off ] ;;
    fpscap) in_list "$2" "$FPS_CAPS" ;;
    ncpu) in_list "$2" "$CPU_COUNTS" ;;
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
    # the checkpoint-chain fence compression on Metal 4 (jdrly/dxmt #133; in the mix)
    "DXMT_DEPENDENCY_COMPRESSION=1"
  )
  n=$(setting ncpu)
  [ "$n" = all ] || E+=("WINENCPU=$n")
  [ "$(setting hud)" = on ] && E+=("MTL_HUD_ENABLED=1")
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
  "caches": ["$CACHE", "$DXMT_CACHE"]
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
    rm -rf "$APPDIR"/*.new "$APPDIR/gamemode"/.GW2.app.new.* 2>/dev/null || true
    log "install failed (status $st)"
  fi
  rmdir "$APPDIR/.lock" 2>/dev/null || true
}

preflight() {
  [ "$(uname -m)" = arm64 ] || die "GW2 on Mac needs a Mac with Apple silicon."
  rosetta_ok || die "Rosetta is not installed. Install it (softwareupdate --install-rosetta in Terminal), then try again."
  check_not_running
  local avail
  avail=$(free_kb)
  [ "${avail:-0}" -gt 3000000 ] || die "Not enough free disk space (the engine and Steam need about 3 GB, the game about 75 GB)."
  [ "$((${avail:-0} * 1024))" -ge "$DISK_NEEDED" ] || warn "Only $(( ${avail:-0} / 1000000 )) GB free: Guild Wars 2 needs about 75 GB."
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

cmd_install() {
  local route=${1:-} setup=${2:-} want
  CREATED="" FETCH_PID=""
  # a first install's state and manifest go too if it fails
  [ -f "$MANIFEST" ] || CREATED="state install-manifest.json"
  case "$route" in steam|arenanet) ;; *) echo "@error Usage: gw2om.sh install steam | install arenanet <Gw2Setup-64.exe>"; exit 2 ;; esac
  if [ "$route" = arenanet ]; then
    [ -n "$setup" ] || { echo "@error Drop Gw2Setup-64.exe from ArenaNet's site first."; exit 2; }
    want=$(cmd_check_setup "$setup") || true
    want=$(echo "$want" | tail -1)
    case "$want" in "@done "*) ;; *) echo "$want"; exit 1 ;; esac
  fi
  open_log
  log "---- install $route $VERSION (dxmt $DXMT_VERSION, engine $ENGINE_NAME) root=${ROOT:-/} dry=${DRY:-0}"
  phase 1
  step "Checking your Mac"
  preflight
  lock
  trap on_install_exit EXIT
  trap 'exit 143' TERM INT HUP   # Cancel in the app: roll back through the EXIT trap
  [ -n "$DRY" ] || mkdir -p "$APPDIR"
  step "The Wine engine"
  install_engine
  phase 2
  step "The game's own bottle"
  install_bottle
  phase 3
  if [ "$route" = steam ]; then
    install_steam
  else
    step "ArenaNet's installer"
    say "$(echo "$want" | sed 's/^@done //')"
    run mkdir -p "$CACHE/downloads"
    run cp "$setup" "$CACHE/downloads/Gw2Setup-64.exe"
  fi
  [ -n "$DRY" ] || set_state route "$route"
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
  say "The shader cache: $DXMT_CACHE (DXMT fills it while you play; warming builds ahead)"
  run mkdir -p "$DXMT_CACHE"
  sync_uiscale
  apply_registry
  gamemode_current || [ "$(setting gamemode)" != on ] || install_gamemode
  [ -n "$DRY" ] || { set_state stage finished; set_state game_dir "$GAME_DIR"; }
  write_manifest
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
  if [ -d "$DXMT_CACHE" ]; then
    run rm -rf "$DXMT_CACHE"
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
  if [ "$(state route)" = arenanet ]; then
    # shellcheck disable=SC2086
    launch "$GAME_EXE" $(setting launchopts)
  else
    # shellcheck disable=SC2086
    launch "$STEAM_EXE" -applaunch "$GW2_APPID" $(setting launchopts)
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
  if [ -d "$CACHE" ]; then run rm -rf "$CACHE"; fi
  if [ -d "$DXMT_CACHE" ]; then run rm -rf "$DXMT_CACHE"; say "Removed DXMT's caches for the game ($DXMT_CACHE)"; fi
  rmdir "${USER_CACHE}dxmt" 2>/dev/null || true
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
  settings) settings ;;
  set) shift; cmd_set "$@" ;;
  check-setup) shift; cmd_check_setup "$@" ;;
  reset-shaders) cmd_reset_shaders ;;
  reinstall-engine) cmd_reinstall_engine ;;
  end-leftovers) cmd_end_leftovers ;;
  fetch-engine) cmd_fetch_engine ;;
  env) cmd_env ;;
  *) sed -n '2,/^# Environment/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
