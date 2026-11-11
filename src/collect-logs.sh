#!/bin/bash
# Resources/collect-logs.sh: "Collect Logs…" in the app menu and in Settings › Troubleshooting
# (src/native/App.swift), as SWTOR on Mac's. Zips what is needed to diagnose a problem into
# ~/Desktop/<the app's name, dashed>-logs-<YYYY-MM-DD-HHMM>.zip (the logs folder if the Desktop cannot be
# written) and prints the zip's path.
#   collect-logs.sh [folder]   write the zip into folder instead
#
# In the zip:
#   logs/          the app's logs (the end of large ones): install.log, wine.log (and .1-4, the
#                  game starts before the last), DXMT's Gw2-64_d3d11.log (and .1-4) and the other
#                  processes' DXMT logs, the heat counters (heat-<pid>.log, Debug logging),
#                  session.env (what the last session started with), the interface addon's logs
#   settings.conf, state, install-manifest.json, dxmt.conf, compatdb.rules and compatdb.local, the
#                  app's VERSIONS
#   session-report.txt  the last game session in short (session-report.sh)
#   game-logs/     the game's and Steam's own logs, with game_rules: ArenaNet.log (crash entries;
#                  their computer, account and address fields taken out), the game's graphics
#                  settings (GFXSettings.Gw2-64.exe.xml), the addon's log in the game folder, and
#                  Steam's bootstrap_log, content_log, gameprocess_log and shader_log (Steam IDs
#                  taken out). Not arcdps's logs (addons/arcdps): its crash log dumps the game's
#                  threads and modules, which may hold account or character names. Never Local.dat (the game's saved login), Steam's config or its
#                  login, connection or account logs, nor anything else of the bottle.
#   system-info.txt  macOS, chip, memory, displays, versions, the state of the install and its
#                  engine, which crash reports are in the zip, the GPU error count
#   gpu-errors.txt  the GPU errors of the game and Wine in macOS's unified log of the last 2 hours
#   crash-reports/  macOS's crash, hang and spin reports of the last 7 days for the game, Wine,
#                  Steam's Windows processes and the app
# Every file is redacted on the way in, as SWTOR on Mac's: home folder → ~, user and full name →
# USER and NAME, Steam account and persona names (read from the bottle's Steam loginusers.vdf, only
# the names) → ACCOUNT, e-mail addresses → EMAIL, password/user name/token settings → REDACTED,
# Steam IDs → STEAMID, serial numbers and device identifiers left out, the Mac's names → NAME.
# Then a leak check: a file that still has one of those names, a home folder path, a Steam ID or a
# token is left out of the zip (named in left-out.txt).
#
# GW2_ON_MAC_ROOT=/abs/dir: a sandbox (as for gw2om.sh); the zip then goes to its Desktop.
set -u
# The app's name and its folders' (as gw2om.sh's)
APP_NAME="GW2 on Mac arm64"
RES="$(cd "$(dirname "$0")" && pwd)"
ROOT="${GW2_ON_MAC_ROOT:-}"
H="${ROOT:+$ROOT/home}"
H="${H:-$HOME}"
APPDIR="$H/Library/Application Support/$APP_NAME"
LOGS="$H/Library/Logs/$APP_NAME"
DIAG="$H/Library/Logs/DiagnosticReports"
BOTTLE="$APPDIR/bottle"
STEAM="$BOTTLE/drive_c/Program Files (x86)/Steam"
# The bottle's Windows user, as gw2om.sh's bottle_user finds it (upstream Wine names it after the
# Mac's user)
BOTTLE_USER="$(id -un)"
for u in "$BOTTLE/drive_c/users"/*; do
  [ -d "$u" ] || continue
  case "${u##*/}" in Public|public) continue ;; esac
  BOTTLE_USER="${u##*/}"; break
done
GW2_APPDATA="$BOTTLE/drive_c/users/$BOTTLE_USER/AppData/Roaming/Guild Wars 2"
# DXMT's shader caches for the game, in the app's own cache folder (the game's compatdb rule sets
# DXMT_SHADER_CACHE_PATH to one of them): my DXMT fork's, the engine's DXMT's
DXMT_CACHE="$H/Library/Caches/$APP_NAME/dxmt/Gw2-64.exe"
DXMT_CACHE_ENGINE="$H/Library/Caches/$APP_NAME/dxmt-engine/Gw2-64.exe"

name="${APP_NAME// /-}-logs-$(date +%Y-%m-%d-%H%M)"
dest="${1:-$H/Desktop}"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT
out="$work/$name"
mkdir -p "$out/logs" "$out/crash-reports"

# The game folder (gw2om.sh's state file names it)
GAME_DIR="$(sed -n 's/^game_dir=//p' "$APPDIR/state" 2>/dev/null | tail -1)"

# Steam account and persona names to hide (only these values are read from loginusers.vdf)
accounts="$(sed -n -E 's/^[[:space:]]*"(AccountName|PersonaName)"[[:space:]]*"(.*)"[[:space:]]*$/\2/p' \
  "$STEAM/config/loginusers.vdf" 2>/dev/null | sed '/^$/d' | sort -u)"
# Names to replace wherever they are, in any case (NAME), and to look for in the leak check:
# the Mac's names; those of 2 or 3 characters only as whole words. Not a model's own name or a
# common word; the longest first.
literals="$work/literals" literals_short="$work/literals-short"
{ scutil --get ComputerName; scutil --get LocalHostName; scutil --get HostName; hostname -s; hostname
  printf '%s\n' "$accounts"
} 2>/dev/null | tr -d '\r' | LC_ALL=C awk '
  { l = tolower($0); sub(/\.local$/, "", l); gsub(/-/, " ", l) }
  length($0) >= 2 && l !~ /^(mac|imac|macbook|macbook air|macbook pro|mac mini|mac studio|mac pro|localhost)( [0-9]+)?$/ &&
  l !~ /^(admin|user|users|test|game|wine|guest|root|home|apple|steam|shared|crossover)$/ {
    print length($0) "\t" $0 }' | sort -rn | cut -f2- | uniq >"$work/names"
awk 'length($0) >= 4' "$work/names" >"$literals"
awk 'length($0) < 4' "$work/names" >"$literals_short"

redact() {  # [game] stdin → stdout (game: also game_rules)
  SOM_HOME_PATH="$HOME" SOM_ROOT_HOME="$H" SOM_USER="$(id -un)" SOM_NAME="$(id -F 2>/dev/null)" SOM_ACCOUNTS="$accounts" \
  LC_ALL=C awk -v litfile="$literals" -v shortfile="$literals_short" -v gamelog="${1:+1}" '
    # Replace w with r in s, ignoring case; only where w is a whole word if whole is set.
    function rep(s, w, r, whole,    ls, lw, res, p, n, before, after, last) {
      if (w == "") return s
      ls = tolower(s); lw = tolower(w); n = length(lw); res = ""; last = ""
      while ((p = index(ls, lw)) > 0) {
        before = p > 1 ? substr(ls, p - 1, 1) : last
        after = substr(ls, p + n, 1)
        if (!whole || (before !~ /[a-z0-9_]/ && after !~ /[a-z0-9_]/))
          res = res substr(s, 1, p - 1) r
        else
          res = res substr(s, 1, p - 1 + n)
        last = substr(ls, p + n - 1, 1)
        s = substr(s, p + n); ls = substr(ls, p + n)
      }
      return res s
    }
    # key=value, key: value, "key":"value" with a secret or identifying key: value → REDACTED.
    function secrets(s,    ls, res, p) {
      ls = tolower(s); res = ""
      while (match(ls, secret_key)) {
        p = RSTART + RLENGTH - 1
        res = res substr(s, 1, p); s = substr(s, p + 1); ls = substr(ls, p + 1)
        if (match(ls, secret_value)) {
          res = res "REDACTED"; s = substr(s, RLENGTH + 1); ls = substr(ls, RLENGTH + 1)
        }
      }
      return res s
    }
    # "-set <key> <value>" pairs on a command line (as SWTOR'"'"'s launcher passes its account):
    # every -set value goes.
    function setargs(s,    res) {
      res = ""
      while (match(s, /-set[ \t]+[A-Za-z0-9_.]+[ \t]+/)) {
        res = res substr(s, 1, RSTART + RLENGTH - 1)
        s = substr(s, RSTART + RLENGTH)
        if (match(s, /^("[^"]*"|[^ \t"]+)/)) { res = res "REDACTED"; s = substr(s, RLENGTH + 1) }
      }
      return res s
    }
    # IPv4 addresses, except 127.0.0.1 and version numbers ("Version: 7.2.207.0", "v1.2.3.4")
    function ipv4(s,    out, pre, m) {
      out = ""
      while (match(s, /[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?/)) {
        pre = substr(s, 1, RSTART - 1); m = substr(s, RSTART, RLENGTH)
        if (m == "127.0.0.1" || tolower(" " pre) ~ /[^a-z](version|ver|v)[:= ]*$/ || pre ~ /[0-9.]$/) out = out pre m
        else out = out pre "IP"
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    # IPv6 addresses: a run of hex digits and colons, not part of a word, with "::" (fe80::1,
    # 2001:db8::1) or 4 colons or more (the full form; MAC addresses are taken before)
    function ipv6(s,    out, pre, m, rest, nc, t) {
      out = ""
      while (match(s, /[0-9A-Fa-f:]*:[0-9A-Fa-f:]*/)) {
        pre = substr(s, 1, RSTART - 1); m = substr(s, RSTART, RLENGTH); rest = substr(s, RSTART + RLENGTH)
        t = m; nc = gsub(/:/, ":", t)
        if ((index(m, "::") || nc >= 4) && m ~ /[0-9A-Fa-f]/ && pre !~ /[A-Za-z0-9_.]$/ && rest !~ /^[A-Za-z0-9_]/) out = out pre "IP6"
        else out = out pre m
        s = rest
      }
      return out s
    }
    # The game and Steam logs (ArenaNet.log, Steam logs): crash entries name the computer, the
    # account and its addresses; Steam logs carry Steam IDs and the account paths
    function game_rules(s) {
      if (s ~ /^[ \t]*(Name|Login|Account|AccountName|Email|Character|CharName|Machine|MachineName|Computer|User|IpAddr|Ip)[ \t]*:/) {
        sub(/:.*/, ": REDACTED", s)
      }
      gsub(/7656119[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]/, "STEAMID", s)
      gsub(/\[U:1:[0-9]+\]/, "[U:1:STEAMID]", s)
      gsub("/Users/[^/ \"\047:]+", "/Users/USER", s)
      gsub("drive_c/users/[^/ \"\047:]+", "drive_c/users/USER", s)
      gsub("[Cc]:\\\\+[Uu]sers\\\\+[^\\\\ \"\047:]+", "C:\\users\\USER", s)
      gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "MAC-ADDRESS", s)
      s = ipv4(s)
      s = ipv6(s)
      return s
    }
    BEGIN {
      secret_key = "(password|passwd|pwd|username|user_name|accountname|account|email|token|ticket|session|" \
        "crashreporterkey|deviceidentifierforvendor|bootsessionuuid|sleepwakeuuid|steamid|accountid|personaname)[\"\047]?[ \t]*[:=][ \t]*[\"\047]?"
      secret_value = "^[^\"\047&,; \t}]+"
      home = ENVIRON["SOM_HOME_PATH"]; rhome = ENVIRON["SOM_ROOT_HOME"]
      user = ENVIRON["SOM_USER"]; fullname = ENVIRON["SOM_NAME"]
      # A user name that is a common word is only replaced in paths, not everywhere.
      split("admin user users mac test game wine guest root home apple steam shared crossover", w, " ")
      for (i in w) common[w[i]] = 1
      n = split(ENVIRON["SOM_ACCOUNTS"], accounts, "\n")
      nl = 0; while ((getline l < litfile) > 0) lit[++nl] = l
      ns = 0; while ((getline l < shortfile) > 0) short[++ns] = l
    }
    {
      line = tolower($0)
      if (line ~ /serial number|hardware uuid|provisioning udid/) next
      s = $0
      if (rhome != home) s = rep(s, rhome, "~", 0)
      s = rep(s, home, "~", 0)
      s = rep(s, "/Users/" user, "/Users/USER", 1)
      s = rep(s, "\\users\\" user, "\\users\\USER", 1)
      if (length(user) >= 2 && !(tolower(user) in common)) s = rep(s, user, "USER", 1)
      if (length(fullname) >= 3) s = rep(s, fullname, "NAME", 1)
      for (i = 1; i <= n; i++) if (length(accounts[i]) >= 2) s = rep(s, accounts[i], "ACCOUNT", 1)
      if (gamelog) s = game_rules(s)
      for (i = 1; i <= nl; i++) s = rep(s, lit[i], "NAME", 0)
      for (i = 1; i <= ns; i++) s = rep(s, short[i], "NAME", 1)
      # session tokens and sessions on command lines, JWT-style tokens
      # (a value in quotes, also JSON-escaped ones, \"...\", is one value with its spaces)
      gsub("--registry-token[ \t]+-t[ \t]+\\\\*\"[^\"]*\"", "--registry-token -t TOKEN", s)
      gsub("--registry-token[ \t]+-t[ \t]+\\\\*\047[^\047]*\047", "--registry-token -t TOKEN", s)
      gsub("--registry-token[ \t]+-t[ \t]+[^ \t\"\047\\\\]+", "--registry-token -t TOKEN", s)
      gsub("--session=\\\\*\"[^\"]*\"", "--session=REDACTED", s)
      gsub("--session=\\\\*\047[^\047]*\047", "--session=REDACTED", s)
      gsub("--session=[^ \t\"\047\\\\]+", "--session=REDACTED", s)
      gsub(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)?/, "TOKEN", s)
      s = setargs(s)
      s = secrets(s)
      gsub(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z][A-Za-z]+/, "EMAIL", s)
      print s
    }'
}

add() {  # file [name in the zip]
  [ -f "$1" ] && redact <"$1" >"$out/${2:-${1##*/}}"
}

add_log() {  # file max-bytes [folder in the zip [game]]: the end of a log
  local f=$1 size dir="$out/${3:-logs}"
  [ -f "$f" ] || return 0
  mkdir -p "$dir"
  size=$(stat -f %z "$f")
  if [ "$size" -gt "$2" ]; then
    { echo "[$APP_NAME: only the last $(($2 / 1000000)) MB of ${f##*/}]"
      tail -c "$2" "$f" | awk 'NR > 1'; } | redact ${4:+"$4"} >"$dir/${f##*/}"
  else
    redact ${4:+"$4"} <"$f" >"$dir/${f##*/}"
  fi
}

# Crash reports: macOS's reports in ~/Library/Logs/DiagnosticReports (crashes .ips/.crash, hangs
# .hang, spins .spin, .diag) of the last 7 days, of the game and Wine (wine, wineserver, Gw2-64.exe),
# Steam's Windows processes, this app and Metal's shader compiler when
# it worked for the game or Wine. The newest first, at most CRASH_MAX of them, CRASH_MAX_BYTES
# together and CRASH_FILE_MAX each. Prints "add <path>" or "skip <name> (<why>)" per report.
CRASH_MAX=20
CRASH_MAX_BYTES=10000000
CRASH_FILE_MAX=3000000
crash_reports() {
  local size f n=0 total=0
  find "$DIAG" -maxdepth 1 -type f \( -iname '*wine*' -o -iname 'Gw2*' -o -iname 'steam*' \
    -o -name "$APP_NAME*" -o -name 'GW2onMac*' -o -name 'MTLCompilerService*' \) \
    \( -name '*.ips' -o -name '*.crash' -o -name '*.hang' -o -name '*.spin' -o -name '*.diag' \) \
    -mtime -7 -exec stat -f '%m %z %N' {} + 2>/dev/null | sort -rn | while read -r _ size f; do
      case "${f##*/}" in
        MTLCompilerService*) LC_ALL=C grep -q -i -E '"responsibleProc" : "(gw2|wine)' "$f" || continue ;;
      esac
      if [ "$n" -ge "$CRASH_MAX" ]; then echo "skip ${f##*/} (more than $CRASH_MAX reports)"
      elif [ "$size" -gt "$CRASH_FILE_MAX" ]; then echo "skip ${f##*/} ($(((size + 999) / 1000)) KB, too large)"
      elif [ $((total + size)) -gt "$CRASH_MAX_BYTES" ]; then echo "skip ${f##*/} (over $((CRASH_MAX_BYTES / 1000000)) MB together)"
      else
        echo "add $f"
        n=$((n + 1)); total=$((total + size))
      fi
    done
}

# GPU errors: macOS's unified log of the last GPU_HOURS hours, as SWTOR on Mac's: the game's
# IOGPUMetalError lines per process, the GPU driver's (AGX) events, Metal's other errors in the
# game and Wine. The query is ended after GPU_TIMEOUT s. In a sandbox the unified log is
# $ROOT/bin/log if there is one (a test's), else it is not read.
GPU_HOURS=2
GPU_LINES=50
METAL_LINES=20
GPU_TIMEOUT=90
GPU_GRACE=5
UNIFIED_LOG=/usr/bin/log
if [ -n "$ROOT" ]; then
  UNIFIED_LOG="$ROOT/bin/log"
  GPU_TIMEOUT="${GW2_ON_MAC_GPU_TIMEOUT:-$GPU_TIMEOUT}"
fi
gpu_errors() {  # → stdout; the count's line also into $work/gpu-summary
  local pid killer st timedout=0
  echo "GPU errors in macOS's unified log, the last $GPU_HOURS hours (until $(date '+%F %T %z'))"
  if [ ! -x "$UNIFIED_LOG" ]; then
    echo "not read (no $UNIFIED_LOG)" | tee "$work/gpu-summary"
    return 0
  fi
  "$UNIFIED_LOG" show --last "${GPU_HOURS}h" --style compact --predicate 'process != "log" AND (eventMessage CONTAINS "IOGPUMetalError"
    OR ((process BEGINSWITH "wine" OR process ==[c] "Gw2-64.exe") AND (messageType == error OR messageType == fault)
      AND (sender CONTAINS[c] "metal" OR sender CONTAINS[c] "IOGPU" OR sender CONTAINS[c] "AGX"))
    OR (process == "kernel" AND sender BEGINSWITH "AGX"))' </dev/null >"$work/gpu-log" 2>/dev/null &
  pid=$!
  # (the time limit: TERM, and KILL for a query that ignores it. The mark says it ran out of
  # time, also for a query that ends with status 0 on TERM; it goes again if the TERM finds no
  # query to end.)
  ( sleep "$GPU_TIMEOUT" && : >"$work/gpu-timeout" &&
    { kill "$pid" || { rm -f "$work/gpu-timeout"; exit 0; }; } &&
    sleep "$GPU_GRACE" && kill -KILL "$pid" ) </dev/null >/dev/null 2>&1 &
  killer=$!
  wait "$pid" 2>/dev/null; st=$?  # (2>: not bash's "Terminated" line for a query that ran out of time)
  # The query has ended: end the watchdog wherever it is, so it never signals that pid again.
  # Stopped first, it can't start a sleep in between; then its sleep, if any, and itself.
  kill -STOP "$killer" 2>/dev/null
  pkill -KILL -P "$killer" 2>/dev/null
  kill -KILL "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null
  [ ! -e "$work/gpu-timeout" ] || timedout=1
  # (a line: date time type process[pid:tid] (sender) message; only other apps' names have spaces)
  LC_ALL=C awk -v lines="$GPU_LINES" -v mlines="$METAL_LINES" -v st="$st" -v timedout="$timedout" \
      -v summary="$work/gpu-summary" -v mdbfull="$work/gpu-mdbfull" '
    !/^[0-9][0-9][0-9][0-9]-/ { next }
    { name = $4; sub(/\[.*/, "", name); ours = name ~ /^wine/ || tolower(name) == "gw2-64.exe" }
    name == "kernel" {
      sender = $5; if (sender !~ /^\([A-Za-z0-9_.-]+\)$/) sender = "(AGX)"
      body = $0; for (i = 1; i <= 5; i++) sub(/^[^ ]+ +/, "", body); body = tolower(body)
      kind = body ~ /restart|reset|recover/ ? "GPU restart" : body ~ /fault/ ? "GPU fault" : \
        body ~ /timeout|timed out|hang|stall/ ? "GPU timeout" : body ~ /error|fail/ ? "GPU error" : "other"
      gpu[++g] = $1 " " $2 " " $3 " kernel " sender ": " kind (body ~ /wine|gw2/ ? ", names the game or Wine" : "")
      next
    }
    /IOGPUMetalError/ {
      if (!ours) { other++; next }
      pid = $4; sub(/^[^[]*\[/, "", pid); sub(/:.*/, "", pid)
      key = name " (pid " pid ")"
      if (!(key in n)) { order[++keys] = key; first[key] = $1 " " $2 }
      n[key]++; last[key] = $1 " " $2; total++
    }
    /MDB_MAP_FULL/ { if (ours) cachefull++; next }
    !ours { next }
    /IOGPUMetalError/ || name == "kernel" { gpu[++g] = $0; next }
    { metal[++m] = $0 }
    END {
      if (timedout) print "(the query ran out of time: what came until then)"
      else if (st) print "(the query failed, status " st ")"
      s = "IOGPUMetalError (GPU command buffer errors, 2 lines each): " total + 0 " in the game and Wine"
      if (other) s = s ", " other " in other apps"
      print s; print s >summary
      for (i = 1; i <= keys; i++) print "  " order[i] ": " n[order[i]] ", " first[order[i]] " to " last[order[i]]
      print cachefull + 0 >mdbfull
      if (cachefull) print "Metal'"'"'s archive usage index full (MDB_MAP_FULL) in the game and Wine: " cachefull " lines; compiled shaders are still cached"
      print ""
      print "The last " lines " lines of them and of the GPU driver (AGX):"
      if (!g) print "  none"
      for (i = (g > lines ? g - lines + 1 : 1); i <= g; i++) print gpu[i]
      print ""
      print "The last " mlines " of Metal'"'"'s other errors in the game and Wine (" m + 0 " in all):"
      if (!m) print "  none"
      for (i = (m > mlines ? m - mlines + 1 : 1); i <= m; i++) print metal[i]
    }' "$work/gpu-log"
}

for f in "$LOGS"/*; do
  case "$f" in
    *.zip|*/heat-prof-*) continue ;;
    # (the game starts before the last: what matters is how they ended)
    */wine.log.[0-9]|*_d3d11.log.[0-9]) add_log "$f" 5000000 ;;
    # the heat counters: the newest 3
    */heat-*.log) ;;
    *) [ -f "$f" ] && add_log "$f" 20000000 ;;
  esac
done
for f in $(ls -t "$LOGS"/heat-[0-9]*.log 2>/dev/null | head -3); do add_log "$f" 5000000; done
for f in settings.conf state install-manifest.json dxmt.conf compatdb.rules compatdb.local; do add "$APPDIR/$f"; done
add "$RES/VERSIONS"
# the game's and Steam's own logs (game_rules)
add_log "$GW2_APPDATA/ArenaNet.log" 5000000 game-logs game
add_log "$GW2_APPDATA/GFXSettings.Gw2-64.exe.xml" 1000000 game-logs game
[ -z "$GAME_DIR" ] || add_log "$GAME_DIR/gw2-ui-scale.log" 5000000 game-logs game
for f in bootstrap_log.txt content_log.txt gameprocess_log.txt shader_log.txt; do
  add_log "$STEAM/logs/$f" 2000000 game-logs/steam game
done
# the last game session in short
if [ -f "$LOGS/Gw2-64_d3d11.log" ] && [ -x "$RES/session-report.sh" ]; then
  "$RES/session-report.sh" "$LOGS/Gw2-64_d3d11.log" 2>&1 | redact >"$out/session-report.txt"
fi
crash_reports >"$work/crash-list"
while IFS= read -r line; do
  case "$line" in
    "add "*) f=${line#add }; add "$f" "crash-reports/${f##*/}" &&
      echo "  ${f##*/} ($(stat -f '%Sm' -t '%F %R' "$f"), $((($(stat -f %z "$f") + 999) / 1000)) KB)" ;;
    "skip "*) echo "  left out: ${line#skip }" ;;
  esac
done <"$work/crash-list" >"$work/crash-index"
gpu_errors 2>&1 | redact >"$out/gpu-errors.txt"

m() { plutil -extract "$1" raw -o - "$APPDIR/install-manifest.json" 2>/dev/null || echo -; }
sha12() { shasum -a 256 "$1" 2>/dev/null | cut -c1-12; }
# pin <name>: a value gw2om.sh pins for the engine
pin() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$RES/gw2om.sh"; }
{
  echo "$APP_NAME logs, collected $(date '+%F %T %z')"
  echo "Versions: $(tr -s '\n' ' ' <"$RES/VERSIONS" 2>/dev/null)"
  echo "Engine: $(pin ENGINE_NAME), Wine $(pin ENGINE_WINE), FEX $(pin ENGINE_FEX), DXMT $(pin ENGINE_DXMT)"
  echo "Installed: $(m version), route $(m route), engine $(m engine)"
  echo "State: $(tr '\n' ' ' <"$APPDIR/state" 2>/dev/null | sed 's|game_dir=[^ ]*|game_dir=(set)|')"
  E="$APPDIR/engine"
  echo "Engine in place: $([ -x "$E/bin/wine" ] && echo "yes, sha256 of the archive $(cut -c1-12 "$E/.gw2om-source" 2>/dev/null)" || echo none)"
  # (the active tree, and the other one waiting next to it: gw2om.sh's dxmt_tree)
  for t in dxmt dxmt.engine dxmt.fork; do
    [ -d "$E/lib/wine/dxgi/$t" ] || continue
    echo "  DXMT tree $t: $(cat "$E/lib/wine/dxgi/$t/.gw2om-dxmt" 2>/dev/null || echo "no mark (the engine's?)")," \
      "d3d11.dll $(sha12 "$E/lib/wine/dxgi/$t/aarch64-windows/d3d11.dll") (the engine's own $(pin ENGINE_D3D11_SHA256 | cut -c1-12))," \
      "winemetal.so $(sha12 "$E/lib/wine/dxgi/$t/aarch64-unix/winemetal.so") (the engine's own $(pin ENGINE_WINEMETAL_SHA256 | cut -c1-12))"
  done
  echo "Game: $([ -n "$GAME_DIR" ] && [ -f "$GAME_DIR/Gw2-64.exe" ] && echo "installed, Gw2-64.exe $(stat -f '%z bytes, %Sm' "$GAME_DIR/Gw2-64.exe")" || echo "not found")"
  [ -z "$GAME_DIR" ] || echo "  interface addon (version.dll): $([ -f "$GAME_DIR/version.dll" ] && { grep -aq 'gw2-on-mac ui-scale' "$GAME_DIR/version.dll" && echo "$APP_NAME's" || echo "another program's"; } || echo none)"
  # d3d11.dll and dxgi.dll addons (arcdps, Nexus): which, by a quick look (gw2om.sh's arcdps_state
  # reads the exports); arcdps's own logs stay out (its crash log dumps the game's memory)
  for f in d3d11.dll dxgi.dll; do
    [ -n "$GAME_DIR" ] && [ -f "$GAME_DIR/$f" ] || continue
    echo "  $f addon: $(LC_ALL=C grep -aq addextension2 "$GAME_DIR/$f" && LC_ALL=C grep -aq arcdps "$GAME_DIR/$f" && echo arcdps || echo "another program's"), $(stat -f '%z bytes, %Sm' "$GAME_DIR/$f")"
  done
  echo "DXMT's caches for the game: my fork's $(du -sk "$DXMT_CACHE" 2>/dev/null | awk '{ printf "%.1f MB", $1 / 1024 }' || echo none)," \
    "the engine's DXMT's $(du -sk "$DXMT_CACHE_ENGINE" 2>/dev/null | awk '{ printf "%.1f MB", $1 / 1024 }' || echo none)"
  echo "Mac: $(sysctl -n hw.model), $(sysctl -n machdep.cpu.brand_string)" \
    "($(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)+$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null) cores)," \
    "$(($(sysctl -n hw.memsize) / 1073741824)) GB, macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "Power: $(pmset -g ps 2>/dev/null | sed -n "1s/.*'\(.*\)'.*/\1/p")$(pmset -g 2>/dev/null | awk '$1 == "lowpowermode" && $2 == 1 { print ", Low Power Mode" }')"
  echo "Free space: $(df -h "$H" 2>/dev/null | awk 'NR == 2 { print $4 " of " $2 }')"
  system_profiler SPDisplaysDataType 2>/dev/null | awk '
    function out() {
      if (name != "") print "Display: " name (type != "" ? " (" type ")" : "") ", " res (ui != "" ? ", looks like " ui : "") (main ? ", main" : "")
      name = type = res = ui = ""; main = 0
    }
    /^ *$/ { next }
    { i = match($0, /[^ ]/); line = substr($0, i) }
    line == "Displays:" { out(); d = i; next }
    d && i <= d { out(); d = 0 }
    d && line ~ /:$/ { out(); name = substr(line, 1, length(line) - 1); next }
    d && sub(/^Display Type: /, "", line) { type = line }
    d && sub(/^Resolution: /, "", line) { res = line }
    d && sub(/^UI Looks like: /, "", line) { ui = line }
    d && line == "Main Display: Yes" { main = 1 }
    END { out() }'
  echo
  echo "Crash reports of the last 7 days (newest first; in crash-reports/):"
  if [ -s "$work/crash-index" ]; then cat "$work/crash-index"; else echo "  none"; fi
  echo
  echo "GPU errors of the last $GPU_HOURS hours (in gpu-errors.txt):"
  echo "  $(cat "$work/gpu-summary" 2>/dev/null || echo "not read")"
  echo
  # names only, never command lines
  echo "Running game, Steam and Wine processes (name only):"
  ps -axww -o pid=,etime=,rss=,comm= 2>/dev/null |
    awk '/[Ww]ine|[Gg]w2|[Ss]team|GW2/ && !/awk|collect-logs/'
  echo
  system_profiler SPHardwareDataType 2>/dev/null | grep -v -i -E 'serial|uuid|udid|activation lock'
} 2>&1 | redact >"$out/system-info.txt"

# The leak check: a file that still has one of the names above, a home folder's path or an
# account name, session or token on a command line is left out (left-out.txt names it). (A
# redacted value may end a quoted string, REDACTED" or REDACTED\", not go on after one; a token
# that begins as a JWT's header, eyJ..., is one even when cut off.)
cat >"$work/leak-patterns" <<'EOF'
--registry-token[[:space:]]+-t[[:space:]]+[^T]
--session=[^R]
7656119[0-9]{10}
--session=REDACTED[^[:space:],;)}"'\\]
--session=REDACTED\\*["'][A-Za-z0-9]
eyJ[A-Za-z0-9_-]{8}
EOF
# found <grep options>: a match, or grep failed (the check fails closed); found_name: the same
# on the file without this script's own markers, also inside words (a name "Name" is not found
# in NAME or app_NAME; redact replaces names in any case, so a marker hides none)
found() { LC_ALL=C grep -q "$@"; [ $? != 1 ]; }
found_name() {  # <file> <grep options>
  local f=$1; shift
  LC_ALL=C sed -E 's/NAME|ACCOUNT|USER|REDACTED|TOKEN|EMAIL|MAC-ADDRESS|IP6|IP//g' "$f" | LC_ALL=C grep -q "$@"
  [ $? != 1 ]
}
( cd "$out" && find . -type f ) | sed 's|^\./||' | while IFS= read -r rel; do
  f="$out/$rel"
  if { [ -s "$literals" ] && found_name "$f" -i -F -f "$literals"; } ||
     { [ -s "$literals_short" ] && found_name "$f" -i -w -F -f "$literals_short"; } ||
     found -F -e "$HOME/" -e "$H/" -e "/Users/$(id -un)/" "$f" ||
     found -E -f "$work/leak-patterns" "$f"; then
    rm -f "$f"
    echo "$rel"
  fi
done >"$work/leaks"
if [ -s "$work/leaks" ]; then
  { echo "Left out: a name, home folder or token the redaction missed was still in these files"
    sed 's/^/  /' "$work/leaks"; } >"$out/left-out.txt"
fi

mkdir -p "$dest" 2>/dev/null
zip="$dest/$name.zip"
( cd "$work" && zip -q -r -X "$name.zip" "$name" ) || { echo "Could not create the zip" >&2; exit 1; }
if ! mv -f "$work/$name.zip" "$zip" 2>/dev/null; then
  # No access to the Desktop (privacy settings): leave it with the logs instead.
  mkdir -p "$LOGS"
  zip="$LOGS/$name.zip"
  mv -f "$work/$name.zip" "$zip" || exit 1
fi
echo "$zip"
