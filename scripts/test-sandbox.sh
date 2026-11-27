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
#      GROUP (all, the default; settings: the dry runs to Collect Logs, on one Steam install;
#      sessions: Steam in the background to Uninstall, on an install it makes itself
#      (fixture_install); rest: what starts from nothing, but the move; move: the move of GW2 on
#      Mac 0.1's install, also from nothing. The Checks workflow runs the four as four jobs. On
#      one Mac run one at a time: each ends every watch-session of this app)
#      CALL_LIMIT (default 120: the seconds one gw2om.sh call may take before its check fails; the
#      slowest check of a passing run took about 40 s)
# Runs under macOS's /bin/bash 3.2.
# Many variables are read only inside the strings that check() evals, which shellcheck can't see.
# shellcheck disable=SC2034
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
# The name the app shows and its file name, from gw2om.sh, and its folders' name, written out
# here: the folders of every install before, which a new build must find where they are
APP_NAME="$(sed -n 's/^APP_NAME="\(.*\)"$/\1/p' src/gw2om.sh)"
[ -n "$APP_NAME" ] || { echo "No APP_NAME=\"…\" line in src/gw2om.sh" >&2; exit 1; }
APP_FOLDER="GW2 on Mac arm64"
WS="${GW2_ON_MAC_WORKSPACE:-$ROOT/../gw2-on-mac}"
APP="$(cd "${1:-dist/$APP_NAME.app}" && pwd)"
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
# sessions_reset: a section that plays starts from no session: no stand-in game or Steam, no
# watcher and no holder of the session's lock left by an earlier check (one that failed leaves
# them running for minutes, and every check after it would fail on them)
sessions_reset() {
  local i=0
  end_sandbox_processes
  pkill -f "^$APP/Contents/Resources/helpers/sessionlock hold" 2>/dev/null || true
  while pgrep -f "^/bin/bash $GW2OM watch-session" >/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  # (and a write of them a killed watcher left half done: put's <file>.new.<pid>)
  rm -f "$AD/session" "$AD/session.req" "$AD"/session.new.* "$AD"/session.req.new.* "$SANDBOX/steam.pid" "$SANDBOX/game.pid"
}
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
ENGINE_WINE=501796b0ed1
# (MYWINE=mine only: the checks of my file say "skip" without it)
mine() { [ "$MYWINE" = mine ]; }
skip() { echo "  skip   $* (this app has no ntdll.so of mine)"; }
# The same for my Mac driver's winemac.so (components/macdrv), apart from ntdll.so
if [ -f "$COMP/macdrv/winemac.so" ]; then MYDRV=mine; else MYDRV=engine; fi
MYDRV_COMMIT="$(sed -n 's/^commit: //p' "$COMP/macdrv/VERSION" 2>/dev/null || true)"
drv() { [ "$MYDRV" = mine ]; }
# my winemac.so has the mouse-look factor: its VERSION's switches: line names it, or it has no such
# line. A dev build from before the factor lists WINE_MACDRV_SURFACE alone
scale() { drv && { ! grep -q '^switches:' "$COMP/macdrv/VERSION" || in_switches WINE_MACDRV_MOUSE_SCALE; }; }
in_switches() { sed -n 's/^switches://p' "$COMP/macdrv/VERSION" | head -1 | tr ' ' '\n' | grep -qx "$1"; }
skipdrv() { echo "  skip   $* (this app has no winemac.so of mine)"; }
# My Mac driver's win32u.so (components/macdrv/win32u.so), in a build of it that has one: the two
# switch as one set, and the log names both (DRVSAYS: "<files>: <label of mine>"). The checks'
# stand-in has none; the checks of the set give it one for a while.
if [ -f "$COMP/macdrv/win32u.so" ]; then W32U=mine DRVNAME="winemac.so and win32u.so"; else W32U=engine DRVNAME=winemac.so; fi
drvsays() { # mine|engine: the line the switch to that set logs
  if [ "$W32U" = engine ] && [ "$1" = mine ]; then echo "winemac.so: my winemac.so (jdrly/wine ${MYDRV_COMMIT:0:11}) is in the engine, the engine's own kept next to it as winemac.so.engine"
  elif [ "$W32U" = engine ]; then echo "winemac.so: the engine's own winemac.so (athei/wine $ENGINE_WINE) is in the engine"
  elif [ "$1" = mine ]; then echo "winemac.so and win32u.so: my winemac.so and win32u.so (jdrly/wine ${MYDRV_COMMIT:0:11}) are in the engine, the engine's own kept next to each as <file>.engine"
  else echo "winemac.so and win32u.so: the engine's own winemac.so and win32u.so (athei/wine $ENGINE_WINE) are in the engine"
  fi
}
# My FEX (components/fex): in the app or not. The setting fex starts at engine either way, so the
# engine's own FEX is in place until a check sets fex mine
if [ -f "$COMP/fex/aarch64-windows/libarm64ecfex.dll" ]; then MYFEX=yes; else MYFEX=no; fi
MYFEX_COMMIT="$(sed -n 's/^commit: //p' "$COMP/fex/VERSION" 2>/dev/null || true)"
ENGINE_FEX=597e7ccbedd
fexb() { [ "$MYFEX" = yes ]; }
skipfex() { echo "  skip   $* (this app has no FEX of mine)"; }
# My KosmicKrisp (components/kosmickrisp): in the app or not. No setting: mine is in the engine
# whenever the app carries it (#339)
if [ -f "$COMP/kosmickrisp/libvulkan_kosmickrisp.dylib" ]; then MYKK=yes; else MYKK=no; fi
MYKK_COMMIT="$(sed -n 's/^commit: //p' "$COMP/kosmickrisp/VERSION" 2>/dev/null || true)"
ENGINE_MESA=d62ee13d18
kkb() { [ "$MYKK" = yes ]; }
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
GROUP="${GROUP:-all}"
case "$GROUP" in all|settings|sessions|rest|move) ;; *) echo "GROUP must be all, settings, sessions, rest or move" >&2; exit 1 ;; esac
in_group() { [ "$GROUP" = all ] || [ "$GROUP" = "$1" ]; }
# Each check's commands: what gw2om.sh prints goes to checks/NNNN.txt as well, through G, a wrapper
# that appends it there (GW2OM is the app's own gw2om.sh). checks.txt lists the results, and a
# failed check gets a copy of the state files next to it (NNNN.state). After a failure, the end
# copies the folder to $FAILED with summary.md, which the Checks workflow uploads.
CHECKS="$SANDBOX/checks"
export GW2OM CHECK_OUT="$CHECKS/0001.txt" CALL_LIMIT="${CALL_LIMIT:-120}"
G="$SANDBOX/bin/gw2om"
mkdir -p "$CHECKS" "$SANDBOX/bin"
cat >"$G" <<'EOF'
#!/bin/bash
# the app's gw2om.sh, with what it prints appended to the current check's file as well: its stdout
# and stderr through a tee each, by FIFOs the tees remove once open. gw2om.sh gets them as fds 1
# and 2 and nothing else, so its detached processes, which redirect those, hold no tee open. This
# exits with gw2om.sh's status once both tees are done, so its output is all there when it ends.
# gw2om.sh runs in a process group of its own (PGRUN), with every process it starts that doesn't
# leave the group. A call that hasn't ended after CALL_LIMIT seconds (gw2om.sh itself, or a tee whose
# FIFO a process still holds open) is ended by a watchdog: it writes the call's record, sends TERM to
# the group, the launcher's pid (whose pid is the group's) and the tees, and KILL 2 s later, with the
# shell's kill alone. Then it starts the process list and the open FIFOs into the check's file in
# the background. This script waits for the kill, adds the record to checks/timeout.new, which
# fails the check it ran in, and exits 124. While that file is there, a call doesn't run, so a
# check spends one limit at most. The watchdog holds none of the call's pipes and ends within a
# second of a call that ends in time.
f="$CHECK_OUT.$$" w=$$ to="${CHECK_OUT%/*}/timeout.new"
if [ -e "$to" ]; then echo "\$ gw2om.sh $* (not run: a call before it ran out of its limit)" >>"$CHECK_OUT"; exit 124; fi
mkfifo "$f.1" "$f.2" || exec "$GW2OM" "$@"
echo "\$ gw2om.sh $*" >>"$CHECK_OUT"
{ rm -f "$f.1"; exec tee -a "$CHECK_OUT"; } <"$f.1" & t1=$!
{ rm -f "$f.2"; exec tee -a "$CHECK_OUT" >&2; } <"$f.2" & t2=$!
"$PGRUN" "$GW2OM" "$@" <&0 >"$f.1" 2>"$f.2" & gp=$!
( i=0
  while [ "$i" -lt "$CALL_LIMIT" ]; do sleep 1; kill -0 "$w" 2>/dev/null || exit 0; i=$((i + 1)); done
  echo "gw2om.sh $* had not ended after $CALL_LIMIT s: checks/${CHECK_OUT##*/}" >"$f.rec" && mv "$f.rec" "$f.timeout"
  kill -TERM -- "-$gp" 2>/dev/null; kill -TERM "$gp" "$t1" "$t2" 2>/dev/null
  sleep 2
  kill -KILL -- "-$gp" 2>/dev/null; kill -KILL "$gp" "$t1" "$t2" 2>/dev/null
  ( { echo "gw2om.sh $* had not ended after $CALL_LIMIT s (the wrapper was pid $w, gw2om.sh's group $gp). The processes after TERM and KILL to the group:"
      ps -axww -o pid,ppid,pgid,stat,etime,command
      echo "The open FIFOs (a tee ends once no process has its FIFO open for writing):"
      lsof -n -u "$(id -u)" 2>/dev/null | awk 'NR == 1 || $5 == "FIFO"'; } >>"$CHECK_OUT" 2>&1 ) & ) </dev/null >/dev/null 2>&1 &
wd=$!
wait "$gp"; rc=$?
wait "$t1" "$t2"
if [ -e "$f.timeout" ]; then wait "$wd"; cat "$f.timeout" >>"$to"; rm -f "$f.timeout"; rc=124; fi
exit "$rc"
EOF
chmod 755 "$G"
# PGRUN <program> [<argument>...]: the program in a process group of its own, whose id is its pid,
# with INT and QUIT as a foreground start has them (bash ignores both for a job it starts with &).
# Without the group the call fails before the program starts.
export PGRUN="$SANDBOX/bin/pgrun"
printf '#include <signal.h>\n#include <stdio.h>\n#include <unistd.h>\nint main(int c, char **v) { if (c < 2) return 2; if (setpgid(0, 0) != 0) { perror("pgrun: setpgid"); return 126; } signal(SIGINT, SIG_DFL); signal(SIGQUIT, SIG_DFL); execvp(v[1], v + 1); perror(v[1]); return 127; }\n' >"$SANDBOX/pgrun.c"
clang -O2 -o "$PGRUN" "$SANDBOX/pgrun.c" || exit 1
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
# A gw2om.sh call that ran out of CALL_LIMIT (the wrapper's record in checks/timeout.new) fails the
# check it ran in, or the next one for a call outside a check, whatever its commands said, and the
# FAIL line names the call and the file with the watchdog's process list
ok() { if [ -e "$CHECKS/timeout.new" ]; then bad "$*"; return; fi; pass=$((pass + 1)); echo "  ok   $*"; end_check ok "$*"; }
bad() {
  local why=""
  if [ -e "$CHECKS/timeout.new" ]; then
    why=" ($(tr '\n' ';' <"$CHECKS/timeout.new" | sed 's/;$//; s/;/; /g'))"
    rm -f "$CHECKS/timeout.new"
  fi
  fail=$((fail + 1)); echo "  FAIL $*$why"; end_check FAIL "$*$why"
}
check() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
# section <name>: its heading; the seconds the one before it took are kept for the end
SEC_NAME="" SEC_T0=0 SEC_TIMES=""
section_end() {
  [ -z "$SEC_NAME" ] || SEC_TIMES="$SEC_TIMES$(printf '%6d s  %s' $((SECONDS - SEC_T0)) "$SEC_NAME")
"
  SEC_NAME=""
}
section() { section_end; SEC_NAME=$* SEC_T0=$SECONDS; echo; echo "== $*"; }
# finish: the seconds per section, the counts, and after a failure the summary and the checks' files
# in $FAILED; its status is the run's
finish() {
  section_end
  echo
  echo "Seconds per section (GROUP=$GROUP, $SECONDS s in all):"
  printf '%s' "$SEC_TIMES"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || { echo "### test-sandbox.sh, GROUP=$GROUP: $SECONDS s"; echo '```'; printf '%s' "$SEC_TIMES"; echo '```'; } >>"$GITHUB_STEP_SUMMARY"
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
}
g() { "$G" "$@"; }
# st/sett <key>...: those fields of one status or settings call, joined by /. A check that reads
# several fields of one state reads them from one call: a call takes about 1 s on a runner.
# kv <output> <key>...: the same from a call's output a check keeps in ST_OUT or SET_OUT
kv() { local o=$1 k v=""; shift; for k; do v="$v/$(printf '%s\n' "$o" | sed -n "s/^$k=//p")"; done; printf '%s\n' "${v#/}"; }
st() { kv "$(g status)" "$@"; }
sett() { kv "$(g settings)" "$@"; }
has() { grep -q -- "$2" "$1" 2>/dev/null; }
# play starts Wine detached: wait (up to 5 s) for the stand-in's log of that start
started() { local i=0; while ! grep -q '^wine ' "$STANDIN_LOG" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }
# the command play started (the stand-in's log of it)
play_cmd() { : >"$STANDIN_LOG"; g play >/dev/null 2>&1; started; grep -m1 '^wine ' "$STANDIN_LOG"; }
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
# rundll <on|off>: the game's compatdb rules have rundll32.exe's line, d3d11 and dxgi native first
# (arcdps's crash window and update), or no line for it
rundll() {
  if [ "$1" = on ]; then [ "$(g rules | grep '^exe=rundll32\.exe;')" = "exe=rundll32.exe;dll_overrides=d3d11,dxgi=n,b" ]
  else ! g rules | grep -q '^exe=rundll32\.exe;'
  fi
}
# compiler_rule <on|off>: the game's rule has d3dcompiler_47 native first (the compiler ReShade
# loads by name), or doesn't
compiler_rule() {
  if [ "$1" = on ]; then g rules | head -1 | grep -q ';dll_overrides=d3dcompiler_47=n,b;'
  else ! g rules | head -1 | grep -q 'd3dcompiler_47'
  fi
}
same() { cmp -s "$1" "$2"; }
# ad_list: what the app's folder holds, sorted, one line, but the session's lock file, which stays
# (a lock file is never removed while anyone may hold it)
ad_list() {
  local f
  for f in "$AD"/* "$AD"/.[!.]*; do
    { [ -e "$f" ] || [ -L "$f" ]; } && [ "${f##*/}" != .session.lock ] && printf '%s\n' "${f##*/}"
  done | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}
# the session's file, and waits (up to 10 s) for its watcher to reach a stage or end
sess() { sed -n "s/^$1=//p" "$AD/session" 2>/dev/null; }
wait_stage() { local i=0; while [ "$(sess stage)" != "$1" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; [ "$(sess stage)" = "$1" ]; }
watcher_runs() { local p; p=$(sess watcher_pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
watch_done() { local i=0; while { watcher_runs || [ "$(sess stage)" != "done" ]; } && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; ! watcher_runs && [ "$(sess stage)" = "done" ]; }

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
# ntdll_is, winemac_is and win32u_is mine|engine: my ntdll.so's and my Mac driver's two files
ntdll_is() { unix_is ntdll.so ntdll "$1"; }
winemac_is() { unix_is winemac.so macdrv "$1"; }
win32u_is() { unix_is win32u.so macdrv "$1"; }
# fex_is mine|engine: FEX's three files as the app leaves them. mine: the app's
# components/fex/aarch64-windows/libarm64ecfex.dll as both DLLs and its libarm64ecfex.so, the
# engine's own next to each as <file>.engine. engine: the engine's own, nothing next to them. Never
# an unfinished <file>.new, and the i386 half as it ships
FW="$ENG/lib/wine"
FEXF="aarch64-windows/xtajit64.dll aarch64-windows/libarm64ecfex.dll aarch64-unix/libarm64ecfex.so"
fex_src_of() { case "$1" in *.dll) echo "$COMP/fex/aarch64-windows/libarm64ecfex.dll" ;; *) echo "$COMP/fex/$1" ;; esac; }
# kk_is mine|engine: KosmicKrisp as the app leaves it. mine: the app's
# components/kosmickrisp/libvulkan_kosmickrisp.dylib, the engine's own next to it as <file>.engine.
# engine: the engine's own, nothing next to it. Never an unfinished <file>.new
KKF="$ENG/lib/external/libvulkan_kosmickrisp.dylib"
kk_is() {
  [ ! -e "$KKF.new" ] || return 1
  if [ "$1" = engine ]; then
    same "$S/lib/external/libvulkan_kosmickrisp.dylib" "$KKF" && [ ! -e "$KKF.engine" ]
    return
  fi
  same "$COMP/kosmickrisp/libvulkan_kosmickrisp.dylib" "$KKF" && same "$S/lib/external/libvulkan_kosmickrisp.dylib" "$KKF.engine"
}
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

# (the engine as it ships: every file the stand-in's, minus the SDK, plus the app's record of the
# archive; nothing of the app's in it but its DXMT trees, ntdll.so, winemac.so, win32u.so and
# KosmicKrisp, which dxgi_is, ntdll_is, winemac_is, win32u_is and kk_is check)
engine_diff() { diff -rq -x dxgi -x 'ntdll.so*' -x 'winemac.so*' -x 'win32u.so*' -x 'libvulkan_kosmickrisp.dylib*' "$S" "$ENG" 2>&1 | sed -e "s|$S|S|g" -e "s|$ENG|E|g" | LC_ALL=C sort | tr '\n' '|'; }
SDK_DIFF="Only in E: .gw2om-source|Only in S/lib/wine: tests|Only in S/lib/wine: x86_64-windows|Only in S/share: man|Only in S: include|"
# the game's folder in the bottle
GD="$STEAM/steamapps/common/Guild Wars 2"

# fixture_install: a finished Steam install with the game, as the first half's sections leave it
# for the session checks (GROUP=sessions starts here; with GROUP=all those sections made it)
fixture_install() {
  g install steam >/dev/null 2>&1 || return 1
  local m="$STEAM/steamapps/appmanifest_1284210.acf"
  printf '"AppState"\n{\n\t"appid"\t\t"1284210"\n\t"installdir"\t\t"Guild Wars 2"\n\t"StateFlags"\t\t"4"\n\t"BytesToDownload"\t\t"58900000000"\n\t"BytesDownloaded"\t\t"21400000000"\n}\n' >"$m"
  mkdir -p "$STEAM/steamapps/common/Guild Wars 2"
  echo "stand-in game" >"$STEAM/steamapps/common/Guild Wars 2/Gw2-64.exe"
  g finish >/dev/null 2>&1 || return 1
  # (what the first half's sections leave, found by comparing the two sandboxes where the session
  # checks start; each line names the section that leaves it)
  g set launchopts -maploadinfo >/dev/null   # Settings
  # (Settings: on a Mac with fewer than 8 CPUs, as GitHub's runners, ncpu ends at all of them)
  local c; c=$(sysctl -n hw.logicalcpu); [ "$c" -ge 8 ] || g set ncpu "$c" >/dev/null
  g set uiscale_size 2.0 >/dev/null          # The larger interface (addon)
  g set uiscale_sans off >/dev/null          # The larger interface (addon)
  g set metal 3 >/dev/null                   # The game's compatdb rules
  g set debug off >/dev/null                 # The game's compatdb rules
  # (Collect Logs: Steam's config/ is where the session checks write loginusers.vdf)
  mkdir -p "$STEAM/config" "$STEAM/logs" "$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2"
}

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
echo "engine's win32u.so" >"$S/lib/wine/aarch64-unix/win32u.so"
# (FEX's x86_64 half: one DLL under two names and its .so; and its i386 half, which the app leaves
# alone)
mkdir -p "$S/lib/wine/aarch64-windows"
echo "engine's libarm64ecfex.dll" >"$S/lib/wine/aarch64-windows/libarm64ecfex.dll"
cp "$S/lib/wine/aarch64-windows/libarm64ecfex.dll" "$S/lib/wine/aarch64-windows/xtajit64.dll"
echo "engine's libarm64ecfex.so" >"$S/lib/wine/aarch64-unix/libarm64ecfex.so"
echo "engine's xtajit.dll" >"$S/lib/wine/aarch64-windows/xtajit.dll"
# (KosmicKrisp, the engine's Vulkan driver)
mkdir -p "$S/lib/external"
echo "engine's libvulkan_kosmickrisp.dylib" >"$S/lib/external/libvulkan_kosmickrisp.dylib"
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
{ echo "wine $*"; env | grep -E '^(WINE|DXMT_|MTL_|USER=)' | sort | sed 's/^/  /'; } >>"$STANDIN_LOG"
case "${1:-}" in
  wineboot)
    mkdir -p "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/users/${USER:-$(id -un)}"
    printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\Machine\n' >"$WINEPREFIX/system.reg"
    printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21\n\n[Software\\\\Wine] 1700000000\n#time=1\n' >"$WINEPREFIX/user.reg"
    cp "$WINEPREFIX/system.reg" "$WINEPREFIX/userdef.reg" ;;
  *SteamSetup.exe)
    mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamapps" "$WINEPREFIX/drive_c/users/${USER:-$(id -un)}/AppData/Local/Steam"
    echo "stand-in steam" >"$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
    echo "a new Steam's" >"$WINEPREFIX/drive_c/users/${USER:-$(id -un)}/AppData/Local/Steam/htmlcache.txt" ;;
  *steam.exe)
    # -shutdown ends the stand-in Steam (a sleeper whose pid is in steam.pid), unless steam.stubborn;
    # with steam.autostart, a start of steam.exe starts that sleeper, as Wine starts Steam (once)
    d=$(dirname "$STANDIN_LOG")
    # (steam.delay: a start that hangs before Wine is up, deaf to TERM, as a stopped launcher would)
    # (steam.delay.pid: its pid, which the exec keeps)
    if [ -e "$d/steam.delay" ] && [ "${2:-}" != -shutdown ]; then echo $$ >"$d/steam.delay.pid"; trap '' TERM; exec sleep 31.25; fi
    if [ "${2:-}" = -shutdown ] && [ ! -e "$d/steam.stubborn" ] && [ -f "$d/steam.pid" ]; then kill "$(cat "$d/steam.pid")" 2>/dev/null || true
    elif [ "${2:-}" != -shutdown ] && [ -e "$d/steam.autostart" ] && ! kill -0 "$(cat "$d/steam.pid" 2>/dev/null)" 2>/dev/null; then
      ( "$(dirname "$0")/steam.exe" 120 </dev/null >/dev/null 2>&1 & echo $! >"$d/steam.pid" )
    fi ;;
esac
EOF
chmod 755 "$S/$LOADER" "$S/bin/wineserver"
export STANDIN_LOG
# (the bottle's Windows user: Mach9's Wine names it after USER, as the stand-in's wineboot does, and
# the app passes crossover for a new bottle, the name 0.1.x's engine gave it)
BUSER=crossover
# every_wine_as <user>: each Wine start in the stand-in's log has USER=<user> (and there is one)
every_wine_as() { awk -v u="  USER=$1" '/^wine / { n++ } $0 == u { m++ } END { exit !(n > 0 && n == m) }' "$STANDIN_LOG"; }
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
GW2_ON_MAC_ENGINE_WIN32U_SHA256="$(shasum -a 256 "$S/lib/wine/aarch64-unix/win32u.so" | cut -d' ' -f1)"
export GW2_ON_MAC_ENGINE_NTDLL_SHA256 GW2_ON_MAC_ENGINE_WINEMAC_SHA256 GW2_ON_MAC_ENGINE_WIN32U_SHA256
GW2_ON_MAC_ENGINE_FEX_DLL_SHA256="$(shasum -a 256 "$S/lib/wine/aarch64-windows/libarm64ecfex.dll" | cut -d' ' -f1)"
GW2_ON_MAC_ENGINE_FEX_SO_SHA256="$(shasum -a 256 "$S/lib/wine/aarch64-unix/libarm64ecfex.so" | cut -d' ' -f1)"
export GW2_ON_MAC_ENGINE_FEX_DLL_SHA256 GW2_ON_MAC_ENGINE_FEX_SO_SHA256
GW2_ON_MAC_ENGINE_KK_SHA256="$(shasum -a 256 "$S/lib/external/libvulkan_kosmickrisp.dylib" | cut -d' ' -f1)"
export GW2_ON_MAC_ENGINE_KK_SHA256
export GW2_ON_MAC_STEAMSETUP_URL="file://$SANDBOX/SteamSetup.exe"
unset GW2_ON_MAC_DRY_RUN GW2_ON_MAC_ALLOW_WINE GW2_ON_MAC_SIGNER GW2_ON_MAC_MACOS GW2_ON_MAC_ENGINE_LOADER_SHA256 GW2_ON_MAC_FEX_SWITCHES
# the session's watcher (play starts it), with its times shortened: a 2 s grace, 2 s for Steam to
# quit, a look every 0.2 s (the 15 minutes for the game to appear only in the timeout check). A
# Play whose checks end before Wine starts, with no Steam and no second Play after it, runs with
# GW2_ON_MAC_WATCH_GRACE=0: its watcher gives up at its first look, not 2 s later (watch_done)
export GW2_ON_MAC_WATCH_GRACE=2 GW2_ON_MAC_WATCH_QUITWAIT=2 GW2_ON_MAC_WATCH_POLL=0.2 GW2_ON_MAC_WATCH_TIMEOUT=60
# A development build's switches (the rows on once, dev-switches.conf) off for every check but those
# of their own section at the end: the others check the app as a release sets it up, apart from
# Debug logging's default
export GW2_ON_MAC_DEV_SWITCHES=off
# (not a pass in move, the fourth group, so the four groups' passes add up as the three groups' did)
if [ "$GROUP" = move ]; then echo "  stand-in engine ($GW2_ON_MAC_ENGINE_SIZE bytes) and SteamSetup.exe"
else ok "stand-in engine ($GW2_ON_MAC_ENGINE_SIZE bytes) and SteamSetup.exe"; fi

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
# ReShade's ReShade64.dll, and a ReShade the app didn't place: the same PE with other bytes
make_pe "$SANDBOX/pe/ReShade64.dll" ReShadeRegisterAddon ReShadeUnregisterAddon ReShadeRegisterEvent
printf 'ReShade 6.8.0 (stand-in)\n' >>"$SANDBOX/pe/ReShade64.dll"
cp "$SANDBOX/pe/ReShade64.dll" "$SANDBOX/pe/reshade-addon.dll" && printf 'the Addon build\n' >>"$SANDBOX/pe/reshade-addon.dll"
# arcdps from a local deltaconnected.com (each group's addon checks; the arcdps section changes it
# and puts it back)
cp "$SANDBOX/pe/arcdps.dll" "$ARCSRV/d3d11.dll"
echo "$(md5 -q "$ARCSRV/d3d11.dll")  d3d11.dll" >"$ARCSRV/d3d11.dll.md5sum"
export GW2_ON_MAC_ARCDPS_URL="file://$ARCSRV"
arcst() { g status | sed -n "s/^arcdps_state=//p"; }
# collect: Collect Logs into $SANDBOX/zip, unzipped into $SANDBOX/unzipped (Z: its folder)
collect() {
  rm -rf "$SANDBOX/zip" "$SANDBOX/unzipped" && mkdir -p "$SANDBOX/zip" "$SANDBOX/unzipped"
  zip=$("$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip" 2>"$SANDBOX/collect.err" | tail -1)
  Z="$SANDBOX/unzipped/$(basename "$zip" .zip)"
  [ -f "$zip" ] && (cd "$SANDBOX/unzipped" && unzip -q "$zip")
}
# winf <path>: the path as Wine writes it, without the Z:; no_home <files or folders>: no home
# folder (as / or \ paths) and no user name in them
winf() { printf '%s' "$1" | tr / '\\'; }
no_home() {
  ! grep -rqiF -e "$HOME/" -e "$H/" -e "$(winf "$HOME")\\" -e "$(winf "$H")\\" -e "\\Users\\$(id -un)\\" "$@" &&
    ! grep -rqiw -e "$(id -un)" "$@"
}
# (macOS kills copies of /bin/sleep: an ad-hoc signed program of my own keeps its signature)
printf '#include <unistd.h>\n#include <stdlib.h>\nint main(int c, char **v) { sleep(c > 1 ? atoi(v[1]) : 60); return 0; }\n' >"$SANDBOX/sleeper.c"
clang -O2 -o "$SANDBOX/sleeper" "$SANDBOX/sleeper.c"
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

if in_group rest; then
section "A gw2om.sh call that doesn't end fails its check by name (CALL_LIMIT)"
# (stand-ins for gw2om.sh, through the wrapper with a limit of 2 s, each in a checks folder of its
# own: one never ends; one waits for its child with a TERM trap, which bash runs only once the child
# has ended; one whose child ignores TERM and outlives it; one ends but leaves a detached process
# holding its stdout and stderr, so the tees wait; and one that never ends while every ps hangs)
cp "$SANDBOX/sleeper" "$SANDBOX/bin/holder"
printf '#!/bin/bash\nexec "%s" 600\n' "$SANDBOX/bin/holder" >"$SANDBOX/bin/hangs"
printf '#!/bin/bash\ntrap "exit 143" TERM\n"%s" 601\n' "$SANDBOX/bin/holder" >"$SANDBOX/bin/traps"
printf '#!/bin/bash\n( trap "" TERM; exec "%s" 603 ) &\nwait\n' "$SANDBOX/bin/holder" >"$SANDBOX/bin/resists"
printf '#!/bin/bash\necho game=yes\n"%s" 602 &\n' "$SANDBOX/bin/holder" >"$SANDBOX/bin/leaves"
printf '#!/bin/bash\nexec "%s" 604\n' "$SANDBOX/bin/holder" >"$SANDBOX/bin/stalls"
mkdir -p "$SANDBOX/stall-bin"
printf '#!/bin/bash\nexec "%s" 605\n' "$SANDBOX/bin/holder" >"$SANDBOX/stall-bin/ps"
chmod 755 "$SANDBOX/bin/hangs" "$SANDBOX/bin/traps" "$SANDBOX/bin/resists" "$SANDBOX/bin/leaves" "$SANDBOX/bin/stalls" "$SANDBOX/stall-bin/ps"
limited() { # <stand-in>: the output of a check that calls it twice (without bash's lines about the
  # processes the watchdog ended), and the seconds it took
  local t0=$SECONDS p=$PATH
  [ "$1" != stalls ] || p="$SANDBOX/stall-bin:$PATH"
  ( CHECKS="$SANDBOX/limit/$1" CHECK_OUT="$SANDBOX/limit/$1/0001.txt" GW2OM="$SANDBOX/bin/$1" CALL_LIMIT=2 pass=0 fail=0 PATH=$p
    mkdir -p "$CHECKS"; check "a check that calls $1" [ "$(st game)/$(st game)" = yes/yes ] ) 2>/dev/null
  echo "took $((SECONDS - t0))"
}
for stub in hangs:600 traps:601 resists:603 leaves:602 stalls:604; do
  out=$(limited "${stub%:*}")
  # (8 s: the limit, a second until the watchdog looks, the 2 s from TERM to KILL, and some to spare)
  check "  ${stub%:*}: the check fails within 8 s, naming the call and its file, and its second call doesn't run" \
    eval 'echo "$out" | grep -qx "  FAIL a check that calls ${stub%:*} (gw2om.sh status had not ended after 2 s: checks/0001.txt)" && [ "${out##*took }" -le 8 ] && has "$SANDBOX/limit/${stub%:*}/0001.txt" "gw2om.sh status (not run: a call before it"'
  check "  the stand-in and its holder are gone when the check ends" \
    eval '! pgrep -f "^$SANDBOX/bin/holder ${stub#*:}" >/dev/null && ! pgrep -f "^/bin/bash $SANDBOX/bin/${stub%:*} status" >/dev/null'
  # (the process list comes after the kill, in the background: a ps that hangs holds nothing up)
  if [ "${stub%:*}" != stalls ]; then
    i=0; while ! has "$SANDBOX/limit/${stub%:*}/0001.txt" "The open FIFOs" && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    check "  the file has the processes after the kill" has "$SANDBOX/limit/${stub%:*}/0001.txt" "The processes after TERM and KILL to the group:"
  fi
  pkill -f "^$SANDBOX/bin/holder" 2>/dev/null || true
done
fi

if in_group settings; then
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
  check "  with my $DRVNAME for the engine" eval 'echo "$out" | grep -qxF "[dry-run] my $DRVNAME (jdrly/wine ${MYDRV_COMMIT:0:11}) in the engine"'
else
  check "  with the engine's own winemac.so (this app has none of mine)" has <(echo "$out") "^\[dry-run\] the engine's own winemac.so (athei/wine $ENGINE_WINE) in the engine$"
fi
check "  with the engine's own FEX (fex=engine by default)" has <(echo "$out") "^\[dry-run\] the engine's own FEX (athei/FEX $ENGINE_FEX) in the engine$"
check "  with the rules file and no WINE_COMPATDB" eval 'echo "$out" | grep -qxF "[dry-run]   WINE_COMPATDB_FILE=$AD/compatdb.rules" && ! echo "$out" | grep -q "WINE_COMPATDB="'
check "dry-run creates nothing" eval '[ -z "$(ad_list)" ] && [ ! -e "$CACHE" ]'
check "fresh status: not installed" [ "$(st installed)" = no ]
check "fresh status: no engine" [ "$(st engine_installed)" = no ]
check "fresh status: the engine's pins (Mach9 0.4.0: Wine, FEX, DXMT commits)" \
  [ "$(st engine engine_wine engine_fex engine_dxmt)" = mach9-v0.4.0/501796b0ed1/597e7ccbedd/10e27aed3f5 ]
check "fresh status: gamemode=engine (the engine's loader)" [ "$(st gamemode)" = engine ]
check "fresh status: disk_free is a number" [ "$(st disk_free)" -gt 0 ]
out=$(env -u GW2_ON_MAC_ENGINE_URL -u GW2_ON_MAC_ENGINE_SHA256 -u GW2_ON_MAC_ENGINE_SIZE GW2_ON_MAC_DRY_RUN=1 "$G" install steam 2>&1)
check "dry-run without the stand-in: the real engine, Mach9 0.4.0 from athei/mach9" \
  has <(echo "$out") "^\[dry-run\] download https://github.com/athei/mach9/releases/download/v0.4.0/wine-v0.4.0-macos-arm64.tar.xz (131698496 bytes, sha256 3b81aac9b93d5652872673b400769ec525f3bc2f1f7e2ec82c9f851d0a0db05d)"
check "  no WINE_COMPATDB, no WINEDLLPATH" eval '! echo "$out" | grep -q -e WINE_COMPATDB= -e WINEDLLPATH'
check "  and still nothing created" eval '[ -z "$(ad_list)" ] && [ ! -e "$CACHE" ]'

section "macOS and the engine's checks (nothing is left behind)"
check "status: macOS 26.3, 26.4 and 26.4.1 are below the engine's 26.5" \
  [ "$(for v in 26.3 26.4 26.4.1; do GW2_ON_MAC_MACOS=$v "$G" status | sed -n 's/^macos_ok=//p'; done | tr '\n' /)$(st macos_min)" = no/no/no/26.5 ]
check "  26.5, 26.5.2, 26.7, 26.10 and 27.0 are not (compared as numbers)" \
  [ "$(for v in 26.5 26.5.2 26.7 26.10 27.0; do GW2_ON_MAC_MACOS=$v "$G" status | sed -n 's/^macos_ok=//p'; done | tr '\n' /)" = yes/yes/yes/yes/yes/ ]
out=$(GW2_ON_MAC_MACOS=26.10 GW2_ON_MAC_DRY_RUN=1 g install steam 2>&1) && rc=0 || rc=$?
check "  a dry-run install on macOS 26.10 goes ahead (no gate)" eval '[ "$rc" = 0 ] && has <(echo "$out") "@phase 4" && [ -z "$(ad_list)" ]'
out=$(GW2_ON_MAC_MACOS=26.4.1 g install steam 2>&1) && rc=0 || rc=$?
check "install on macOS 26.4.1: refused, naming both versions, nothing created" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error $APP_NAME needs macOS 26.5 or later for its Wine engine. This Mac has macOS 26.4.1. Update macOS in System Settings › General › Software Update, then try again." && [ ! -e "$ENG" ] && [ ! -e "$AD/state" ]'
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
  eval '[ -z "$(ad_list)" ] && [ "$(ls "$CACHE/downloads")" = engine.tar.xz ]'
rm -rf "$CACHE"

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
check "graphics=yes: my DXMT fork, as Settings asks by default" [ "$(st graphics dxmt dxmt_tree)" = yes/fork/fork ]
check "  status names the fork's build and its release" eval 'ST_OUT=$(g status); [ "$(kv "$ST_OUT" dxmt_version)" = "$(head -1 "$COMP/dxmt/VERSION")" ] && [ -n "$(kv "$ST_OUT" dxmt_commit)" ] && [ -n "$(kv "$ST_OUT" dxmt_release)" ] && head -1 "$COMP/dxmt/VERSION" | grep -qF "v$(kv "$ST_OUT" dxmt_release)-"'
check "  the install says so" has <(echo "$out") "^DXMT: my DXMT fork ($(head -1 "$COMP/dxmt/VERSION")) draws the game"
check "  the engine's DXMT tree is mine, the engine's own next to it as it ships" dxgi_is fork
if mine; then
  check "my ntdll.so in the engine, the engine's own next to it as ntdll.so.engine" ntdll_is mine
  check "  status names it, its commit and its Wine release" [ "$(st wine wine_ready wine_file wine_commit wine_build wine_release)" = "mine/yes/mine/$MYWINE_COMMIT/$MYWINE_COMMIT/11.21" ]
  check "  the install says so" has <(echo "$out") "^ntdll.so: my ntdll.so (jdrly/wine ${MYWINE_COMMIT:0:11}) is in the engine, the engine's own kept next to it as ntdll.so.engine$"
else
  check "no ntdll.so of mine in this app: the engine's own stays in place" ntdll_is engine
  check "  status names it and the engine's Wine" [ "$(st wine_ready wine_file wine_commit wine_build wine_release)" = "yes/engine/$ENGINE_WINE//" ]
fi
if drv; then
  check "my winemac.so in the engine, the engine's own next to it as winemac.so.engine" winemac_is mine
  check "  win32u.so: mine with it if its build has one ($W32U), the engine's own otherwise" \
    eval 'win32u_is $W32U && [ "$(st win32u_bundled win32u_file)" = "$([ $W32U = mine ] && echo yes || echo no)/$W32U" ]'
  check "  status names it, its commit and its Wine release" [ "$(st macdrv macdrv_ready macdrv_file macdrv_commit macdrv_build macdrv_release)" = "mine/yes/mine/$MYDRV_COMMIT/$MYDRV_COMMIT/11.21" ]
  check "  the install says so" eval 'echo "$out" | grep -qxF "$(drvsays mine)"'
else
  check "no winemac.so of mine in this app: the engine's own stays in place" winemac_is engine
  check "  status names it and the engine's Wine" [ "$(st macdrv_ready macdrv_file macdrv_commit macdrv_build macdrv_release)" = "yes/engine/$ENGINE_WINE//" ]
fi
check "the engine's own FEX in place (fex=engine by default), nothing next to it" fex_is engine
check "  status names it and the engine's FEX commit, and my build's commit in this app" \
  [ "$(st fex fex_ready fex_file fex_commit fex_build)" = "engine/yes/engine/$ENGINE_FEX/$MYFEX_COMMIT" ]
check "  the install says nothing of FEX (nothing switched)" eval '! echo "$out" | grep -q "^FEX:"'
if kkb; then
  check "my KosmicKrisp in the engine, the engine's own next to it as libvulkan_kosmickrisp.dylib.engine" kk_is mine
  check "  status names it and its commit" [ "$(st kosmickrisp_ready kosmickrisp_file kosmickrisp_commit kosmickrisp_build)" = "yes/mine/$MYKK_COMMIT/$MYKK_COMMIT" ]
  check "  the install says so" has <(echo "$out") "^KosmicKrisp: my KosmicKrisp (jdrly/mesa ${MYKK_COMMIT:0:11}) is in the engine, the engine's own kept next to it as libvulkan_kosmickrisp.dylib.engine$"
else
  check "no KosmicKrisp of mine in this app: the engine's own stays in place" kk_is engine
  check "  status names it and the engine's Mesa" [ "$(st kosmickrisp_ready kosmickrisp_file kosmickrisp_commit kosmickrisp_build)" = "yes/engine/$ENGINE_MESA/" ]
fi
check "gamemode=engine" [ "$(st gamemode)" = engine ]
check "steam=yes" [ "$(st steam)" = yes ]
check "stage=waiting_game" [ "$(st stage)" = waiting_game ]
check "route=steam" [ "$(st route)" = steam ]
check "game=no yet" [ "$(st game)" = no ]
check "the engine is the stand-in as it ships, without its SDK (include, tests, x86_64-windows, man)" [ "$(engine_diff)" = "$SDK_DIFF" ]
check "  and its KosmicKrisp is $(kkb && echo mine || echo "the engine's own")" kk_is "$(kkb && echo mine || echo engine)"
check "  wine.app's files have the stand-in's hashes" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
check "  bin/wine and lib/wine/aarch64-unix/wine still link to the loader in wine.app" \
  eval '[ "$(readlink "$ENG/bin/wine")" = ../$LOADER ] && [ "$(readlink "$ENG/lib/wine/aarch64-unix/wine")" = wine.app/Contents/MacOS/wine ]'
check "  no Game Mode bundle (the engine's loader is the Game Mode app)" [ ! -e "$AD/gamemode" ]
check "RetinaMode=y in the bottle" reg "$ALL_MAC" RetinaMode y
check "EmulateModeset=N (0.1.x's behaviour, not Mach9's launcher's Y: #90)" reg "$ALL_X11" EmulateModeset N
check "ShowCrashDialog=dword:0" eval 'regsec "Software\\\\\\\\Wine\\\\\\\\WineDbg" | grep -qx "\"ShowCrashDialog\"=dword:00000000"'
check "  nothing for Gw2-64.exe (AppDefaults) and no raw mouse-look values" sh -c "! grep -q -e AppDefaults -e RawMouse '$BOTTLE/user.reg'"
check "wineboot with WINEMSYNC=1 and winemenubuilder off, nothing else of the app's" \
  eval '[ "$(awk "/^wine wineboot/ { f = 1; next } /^[^ ]/ { f = 0 } f" "$STANDIN_LOG" | sed "s/^  //" | tr "\n" "|")" = "USER=crossover|WINEDEBUG=-all|WINEDLLOVERRIDES=winemenubuilder.exe=d|WINEMSYNC=1|WINEPREFIX=$BOTTLE|" ]'
check "  every Wine start of the install as the bottle's user, crossover (its folder in users/)" \
  eval 'every_wine_as crossover && [ -d "$BOTTLE/drive_c/users/crossover" ] && [ "$(ls "$BOTTLE/drive_c/users")" = crossover ]'
check "  no inherited compatdb variable reached any of the install's Wine starts (Steam's has the app's rules file)" \
  sh -c "! grep -q -e WINE_COMPATDB= -e WINE_LARGE_ADDRESS_AWARE -e WINE_PROF_SERVICE '$STANDIN_LOG' && [ \"\$(grep WINE_COMPATDB_FILE '$STANDIN_LOG')\" = '  WINE_COMPATDB_FILE=$AD/compatdb.rules' ]"
check "Steam started with the install page" has "$STANDIN_LOG" 'wine C:\\Program Files (x86)\\Steam\\steam.exe steam://install/1284210'
check "  without WINEDLLPATH" sh -c "! grep -q WINEDLLPATH '$STANDIN_LOG'"
check "logs/session.env written" has "$LOGS/session.env" "SETTING_warm=on"
check "the manifest" has "$AD/install-manifest.json" '"route": "steam"'
check "install.log" has "$LOGS/install.log" "install steam"
# (0.1.x's file name and bundle id, so a 0.1.x install takes 0.2 as its update, and the id the
# app starts Sparkle for: with another one updates stay off, silently; ADR 0018)
check "the app is $APP_NAME.app with id cz.jandrly.gw2onmac, the one Updates.swift starts Sparkle for" \
  eval '[ "${APP##*/}" = "$APP_NAME.app" ] && [ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = cz.jandrly.gw2onmac ] && grep -qE "^ *static let appBundleID *= *\"cz\\.jandrly\\.gw2onmac\"" "$ROOT/src/native/Updates.swift"'
# (the app's own three folders and nothing else in Library, so it never shares one with another
# build of the app, such as 0.1.x)
check "only the app's folders in Library: $APP_FOLDER" eval '[ "$(cd "$H/Library" && ls -d */* | tr "\n" "|")" = "Application Support/$APP_FOLDER|Caches/$APP_FOLDER|Logs/$APP_FOLDER|" ]'
check "  status reads the install from there, the folder of every install before" [ "$(st app_dir)" = "$AD" ]

section "Steam downloads the game (played by the test)"
m="$STEAM/steamapps/appmanifest_1284210.acf"
printf '"AppState"\n{\n\t"appid"\t\t"1284210"\n\t"installdir"\t\t"Guild Wars 2"\n\t"StateFlags"\t\t"1026"\n\t"BytesToDownload"\t\t"58900000000"\n\t"BytesDownloaded"\t\t"21400000000"\n}\n' >"$m"
check "game=no while downloading" [ "$(st game)" = no ]
check "game_bytes/game_total from the appmanifest" [ "$(st game_bytes game_total)" = 21400000000/58900000000 ]
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
  [ "$(sett warm fastlocks ncpu uiscale uiscale_cinema)" = on/off/8/off/off ]
check "  settings.conf of a fresh install: settings_version=2, fastlocks off, dxmt fork, wine and macdrv mine, fex engine" \
  eval 'grep -qx settings_version=2 "$AD/settings.conf" && grep -qx fastlocks=off "$AD/settings.conf" && grep -qx dxmt=fork "$AD/settings.conf" && grep -qx wine=mine "$AD/settings.conf" && grep -qx macdrv=mine "$AD/settings.conf" && grep -qx fex=engine "$AD/settings.conf"'

check "default: Steam in the background on" [ "$(sett steambg)" = on ]
check "default: Quit Steam when the game quits on" [ "$(sett quitsteam)" = on ]
check "settings: a state for each of the 27 keys" [ "$(g settings | grep -cE '^[a-z_]+_state=(ok|off:.+)$')" = 27 ]
# (greyed: the ones a later step brings, and those that need a file of mine this app hasn't, in
# SETTING_KEYS' order)
OFF=""
mine || OFF="${OFF}fastlocks "
scale || OFF="${OFF}mousespeed "
mine || OFF="${OFF}wine jobwakes "
drv || OFF="${OFF}macdrv launcherframes "
mine || OFF="${OFF}eventpool "
fexb || OFF="${OFF}fex "
check "  off: ${OFF:-none}" \
  [ "$(g settings | sed -n 's/^\([a-z_]*\)_state=off:.*/\1/p' | tr '\n' ' ')" = "$OFF" ]
if mine; then
  check "  wine=mine, jobwakes and eventpool on and fastlocks off by default, all ok" \
    [ "$(sett wine wine_state jobwakes jobwakes_state eventpool eventpool_state fastlocks fastlocks_state)" = mine/ok/on/ok/on/ok/off/ok ]
else
  check "  with their reasons; set wine engine and set jobwakes, eventpool and fastlocks refused" \
    eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" wine_state)" = "off:This build of the app has no Wine build of mine." ] && [ "$(kv "$SET_OUT" jobwakes_state)" = "off:Needs my Wine build, which this build of the app doesn'"'"'t have." ] && [ "$(kv "$SET_OUT" eventpool_state)" = "$(kv "$SET_OUT" jobwakes_state)" ] && [ "$(kv "$SET_OUT" fastlocks_state)" = "$(kv "$SET_OUT" jobwakes_state)" ] && ! "$G" set wine engine >/dev/null 2>&1 && ! "$G" set jobwakes off >/dev/null 2>&1 && ! "$G" set eventpool off >/dev/null 2>&1 && ! "$G" set fastlocks on >/dev/null 2>&1'
fi
if drv; then
  check "  macdrv=mine and launcherframes=off by default, both ok; mousespeed=1" [ "$(sett macdrv macdrv_state launcherframes launcherframes_state mousespeed)" = mine/ok/off/ok/1 ]
  if scale; then
    check "  mousespeed ok" [ "$(sett mousespeed_state)" = ok ]
  else
    check "  mousespeed greyed: my winemac.so's VERSION doesn't list its switch" \
      [ "$(sett mousespeed_state)" = "off:My Mac driver in this app (jdrly/wine ${MYDRV_COMMIT:0:11}) doesn't have this switch." ]
  fi
else
  check "  with their reasons; set macdrv engine, set launcherframes on and set mousespeed 1.5 refused" \
    eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" macdrv_state)" = "off:This build of the app has no Mac driver of mine." ] && [ "$(kv "$SET_OUT" launcherframes_state)" = "off:Needs my Mac driver, which this build of the app doesn'"'"'t have." ] && [ "$(kv "$SET_OUT" mousespeed_state)" = "$(kv "$SET_OUT" launcherframes_state)" ] && ! "$G" set macdrv engine >/dev/null 2>&1 && ! "$G" set launcherframes on >/dev/null 2>&1 && ! "$G" set mousespeed 1.5 >/dev/null 2>&1'
fi
# settings.conf's version (SETTINGS_RESETS): a file from before version 1 holds the fastlocks=on
# and coolworkers=3 the arm64 line wrote while both rows were greyed; fastlocks reads off, and
# coolworkers, no longer a key, is read by nothing. gamemode=on, which every file had until the key
# left in #269, the same
cp "$AD/settings.conf" "$SANDBOX/settings.fresh"
sed -i '' -e '/^settings_version=/d' -e 's/^fastlocks=.*/fastlocks=on/' "$AD/settings.conf"
printf 'coolworkers=3\ngamemode=on\n' >>"$AD/settings.conf"
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "a settings.conf without settings_version, fastlocks=on, coolworkers=3 and gamemode=on: fastlocks reads off" \
  eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" fastlocks)" = off ] && ! echo "$SET_OUT" | grep -q -e coolworkers -e "^gamemode" && ! g rules | grep -q WINE_HEAT_SPIN && ! echo "$out" | grep -q WINE_HEAT_SPIN'
g set hud on >/dev/null; g set hud off >/dev/null
check "  the next write keeps that, writes settings_version=2 and leaves coolworkers and gamemode out" \
  eval 'grep -qx settings_version=2 "$AD/settings.conf" && grep -qx fastlocks=off "$AD/settings.conf" && ! grep -q -e coolworkers -e gamemode "$AD/settings.conf"'
sed -i '' -e 's/^settings_version=.*/settings_version=0/' -e 's/^fastlocks=.*/fastlocks=on/' "$AD/settings.conf"
check "  settings_version=0 and fastlocks=on: reads off" [ "$(sett fastlocks)" = off ]
# a file at version 1 with the engine's own DXMT, ntdll.so and winemac.so chosen, from the rows
# version 2 took out of the window: fork, mine and mine, once
cp "$SANDBOX/settings.fresh" "$AD/settings.conf"
sed -i '' -e 's/^settings_version=.*/settings_version=1/' -e 's/^dxmt=.*/dxmt=engine/' -e 's/^wine=.*/wine=engine/' -e 's/^macdrv=.*/macdrv=engine/' "$AD/settings.conf"
echo coolworkers=off >>"$AD/settings.conf"
check "settings_version=1 with dxmt, wine and macdrv engine and a coolworkers line: read fork, mine, mine" \
  [ "$(sett dxmt wine macdrv)/$(st graphics)" = fork/mine/mine/yes ]
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
check "  ok for the ones my DXMT fork brings back: metal, metalfx, warm, vsync; dxmt=fork and vsync on by default" \
  [ "$(sett metal_state metalfx_state warm_state vsync_state dxmt vsync)" = ok/ok/ok/ok/fork/on ]
check "  metal: 4 by default, in settings.conf and status; set metal 5 refused" \
  eval '[ "$(sett metal)/$(st metal)" = 4/4 ] && grep -qx metal=4 "$AD/settings.conf" && ! "$G" set metal 5 >/dev/null 2>&1'
# (a settings.conf from before the row: no metal= line)
sed -i '' '/^metal=/d' "$AD/settings.conf"
check "  a settings.conf without the key reads 4" eval '[ "$(sett metal)" = 4 ] && g rules | sed -n 1p | grep -q ";env=DXMT_METAL4=1"'
g set hud on >/dev/null; g set hud off >/dev/null
check "  and the next write adds metal=4" eval 'grep -qx metal=4 "$AD/settings.conf"'
# (metal=3, as Install and Repair wrote it into every file while 3 was the default, at
# settings_version 1 and 2: my choice, never reset. The checks below run at Metal 3; the compatdb
# rules' Metal 4 checks set 4.)
g set metal 3 >/dev/null
sed -i '' 's/^settings_version=.*/settings_version=1/' "$AD/settings.conf"
check "  metal=3 in a file at settings_version 1 reads 3" [ "$(sett metal)" = 3 ]
g set hud on >/dev/null; g set hud off >/dev/null
check "  and stays 3 through later writes" eval '[ "$(sett metal)" = 3 ] && grep -qx metal=3 "$AD/settings.conf" && grep -qx settings_version=2 "$AD/settings.conf"'
out=$(g set coolworkers 5 2>&1) && rc=0 || rc=$?
check "set coolworkers 5: refused as an unknown setting" eval '[ "$rc" = 2 ] && [ "$out" = "@error Unknown setting: coolworkers=5" ]'
out=$(g set gamemode off 2>&1) && rc=0 || rc=$?
check "set gamemode off: refused as an unknown setting (the key left in #269)" eval '[ "$rc" = 2 ] && [ "$out" = "@error Unknown setting: gamemode=off" ]'
# (a greyed key: mousespeed while Raw mouse-look is off)
g set rawmouse off >/dev/null
sed -i '' 's/^mousespeed=.*/mousespeed=1.5/' "$AD/settings.conf"
g set hud on >/dev/null; g set hud off >/dev/null
check "  a greyed key keeps what settings.conf says (mousespeed=1.5 by hand while Raw mouse-look is off)" \
  eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" mousespeed)" = 1.5 ] && grep -qx mousespeed=1.5 "$AD/settings.conf" && [ "$(kv "$SET_OUT" mousespeed_state)" = "off:Needs Raw mouse-look, which is off." ]'
sed -i '' 's/^mousespeed=.*/mousespeed=1/' "$AD/settings.conf"
g set rawmouse on >/dev/null
check "warm on: DXMT_WARM=all; off: none" sh -c "'$G' env | grep -qx DXMT_WARM=all && '$G' set warm off >/dev/null && ! '$G' env | grep -q DXMT_WARM && '$G' set warm on >/dev/null"
check "set metalfx on: DXMT_SUBSAMPLE_METALFX=1" sh -c "'$G' set metalfx on >/dev/null && '$G' env | grep -qx DXMT_SUBSAMPLE_METALFX=1 && '$G' set metalfx off >/dev/null && ! '$G' env | grep -q DXMT_SUBSAMPLE"
# the engine's own DXMT, and back (nothing runs: the tree swaps at once)
out=$(g set dxmt engine 2>&1) && rc=0 || rc=$?
check "set dxmt engine: the engine's own tree is the active one, mine waits next to it" \
  eval '[ "$rc" = 0 ] && dxgi_is engine && [ -f "$ENG/lib/wine/dxgi/dxmt.fork/.gw2om-dxmt" ] && [ "$(st graphics dxmt_tree)" = yes/engine ] && ! echo "$out" | grep -q Repair'
check "  it says which" has <(echo "$out") "^DXMT: the engine's own DXMT (athei/dxmt 10e27aed3f5) draws the game"
check "  warming, MetalFX, Metal and Vsync greyed with the reason; set warm, set metal and set vsync refused" \
  eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" warm_state)" = "off:Needs my DXMT fork, and the engine'"'"'s own DXMT is chosen." ] && [ "$(kv "$SET_OUT" metalfx_state)" = "$(kv "$SET_OUT" warm_state)" ] && [ "$(kv "$SET_OUT" metal_state)" = "$(kv "$SET_OUT" warm_state)" ] && [ "$(kv "$SET_OUT" vsync_state)" = "$(kv "$SET_OUT" warm_state)" ] && ! "$G" set warm off >/dev/null 2>&1 && ! "$G" set metal 4 >/dev/null 2>&1 && ! "$G" set vsync off >/dev/null 2>&1'
check "  none of the fork's variables in the environment" sh -c "! '$G' env | grep -qE 'DXMT_(CACHE_DIR|WARM|DEPENDENCY_COMPRESSION|SUBSAMPLE|STATS)'"
# (after the heat entries exactly FEX's that Debug logging adds: FEX_SILENTLOG with either
# ntdll.so, nothing with Debug logging off. The engine's own FEX is in place here, so never
# FEX_PROFILESTATS, #344)
fex_tail=""
[ "$(sett debug)" != on ] || fex_tail=";env=FEX_SILENTLOG=0"
check "  the game's shader cache: the engine's DXMT's own" has <(g rules) "^exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=$DXMT_CACHE_ENGINE\(;env=WINE_HEAT_[^;]*\)*$fex_tail$"
check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
out=$(g set dxmt fork 2>&1) && rc=0 || rc=$?
check "set dxmt fork: mine again, the engine's own kept as it ships" eval '[ "$rc" = 0 ] && dxgi_is fork && [ "$(st graphics dxmt_tree)" = yes/fork ] && ! echo "$out" | grep -q Repair'
check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
# My files go into the engine only when it is this app's and their records name its engine
# (engine_refusal). First an engine an earlier version of the app left: its record of the archive
# is Mach9 0.3.1's. Then my DXMT's VERSION without an engine: line, which counts as built for 0.3.1.
cp "$ENG/.gw2om-source" "$SANDBOX/gw2om-source.keep"
echo 90aff9a897ed0ff9aac44d0e06f0aecd3ee985afb38037f3f915451e51fa974e >"$ENG/.gw2om-source"
out=$(g set dxmt engine 2>&1) && rc=0 || rc=$?
check "Mach9 0.3.1's engine in place: set dxmt engine leaves the engine's files as they are, saying why" \
  eval '[ "$rc" = 0 ] && dxgi_is fork && echo "$out" | grep -qxF "@warn The engine here is Mach9 0.3.1 · Wine 11.21, and my files are built for Mach9 0.4.0 · Wine 11.21, so they stay out of it. Click Repair to put Mach9 0.4.0 · Wine 11.21 in place."'
cp "$SANDBOX/gw2om-source.keep" "$ENG/.gw2om-source"
cp "$COMP/dxmt/VERSION" "$SANDBOX/dxmt-VERSION.keep"
grep -v '^engine: ' "$SANDBOX/dxmt-VERSION.keep" >"$COMP/dxmt/VERSION"
out=$(g set dxmt engine 2>&1) && rc=0 || rc=$?
check "my DXMT's VERSION names no engine: set dxmt engine leaves my tree in place, saying why" \
  eval '[ "$rc" = 0 ] && [ -f "$ENG/lib/wine/dxgi/dxmt/.gw2om-dxmt" ] && [ -d "$ENG/lib/wine/dxgi/dxmt.engine" ] && echo "$out" | grep -qxF "@warn My DXMT fork in this app is built for Mach9 0.3.1 · Wine 11.21, not for Mach9 0.4.0 · Wine 11.21, so none of my files go into the engine."'
cp "$SANDBOX/dxmt-VERSION.keep" "$COMP/dxmt/VERSION"
check "  its VERSION back: the tree is mine as it was, and the engine's own swaps in again" \
  eval 'dxgi_is fork && g set dxmt engine >/dev/null && dxgi_is engine && g set dxmt fork >/dev/null && dxgi_is fork'
# A swap cut short (the Mac off, a kill): between its two renames there is no active tree, and
# during the copy an unfinished dxmt.fork.new; the next call puts the asked-for tree in
DX="$ENG/lib/wine/dxgi"
mv "$DX/dxmt" "$DX/dxmt.fork" && sed -i '' 's/^dxmt=.*/dxmt=engine/' "$AD/settings.conf"
check "cut short on the way to the engine's own (no active tree): graphics=switch" [ "$(st graphics dxmt_tree)" = switch/none ]
check "  the next set dxmt engine puts it in" eval 'g set dxmt engine >/dev/null && dxgi_is engine && [ "$(st graphics)" = yes ]'
mv "$DX/dxmt" "$DX/dxmt.engine" && sed -i '' 's/^dxmt=.*/dxmt=fork/' "$AD/settings.conf"
check "cut short on the way to mine (no active tree): graphics=switch" [ "$(st graphics dxmt_tree)" = switch/none ]
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
    eval '[ "$rc" = 0 ] && ntdll_is engine && [ "$(st wine_ready wine_file wine_commit)" = "yes/engine/$ENGINE_WINE" ] && ! echo "$out" | grep -q Repair'
  check "  it says which" has <(echo "$out") "^ntdll.so: the engine's own ntdll.so (athei/wine $ENGINE_WINE) is in the engine$"
  check "  job wakes greyed with the reason; set jobwakes refused" \
    eval '[ "$(sett jobwakes_state)" = "off:Needs my Wine build, and the engine'"'"'s own ntdll.so is chosen." ] && ! "$G" set jobwakes off >/dev/null 2>&1'
  check "  wine.app and the DXMT trees untouched" eval '[ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ] && dxgi_is fork'
  out=$(g set wine mine 2>&1) && rc=0 || rc=$?
  check "set wine mine: mine again, the engine's own next to it as it ships" \
    eval '[ "$rc" = 0 ] && ntdll_is mine && [ "$(st wine_ready wine_file wine_commit)" = "yes/mine/$MYWINE_COMMIT" ] && [ "$(sett jobwakes_state)" = ok ]'
  check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
  # A switch cut short: between the two renames on the way to mine no ntdll.so is there; an
  # unfinished copy (ntdll.so.new) may be left; an earlier build of mine may be in place
  mv "$NT/ntdll.so" "$NT/ntdll.so.new"
  check "cut short between the renames (no ntdll.so): wine_ready=switch" [ "$(st wine_ready wine_file)" = switch/none ]
  check "  the next set wine mine puts it in" eval 'g set wine mine >/dev/null && ntdll_is mine && [ "$(st wine_ready)" = yes ]'
  g set wine engine >/dev/null && mv "$NT/ntdll.so" "$NT/ntdll.so.engine" && echo half >"$NT/ntdll.so.new"
  sed -i '' 's/^wine=.*/wine=mine/' "$AD/settings.conf"
  check "cut short with an unfinished ntdll.so.new: set wine mine copies it again" \
    eval 'g set wine mine >/dev/null && ntdll_is mine && [ "$(st wine_ready)" = yes ]'
  echo "an earlier build of mine" >"$NT/ntdll.so"
  check "an earlier build of mine in place: wine_ready=switch, wine_file=other" [ "$(st wine_ready wine_file wine_commit)" = switch/other/ ]
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
    eval '[ "$rc" = 0 ] && winemac_is engine && ntdll_is $MYWINE && [ "$(st macdrv_ready macdrv_file macdrv_commit wine_file)" = "yes/engine/$ENGINE_WINE/$MYWINE" ] && ! echo "$out" | grep -q Repair'
  check "  it says which" eval 'echo "$out" | grep -qxF "$(drvsays engine)" && win32u_is engine'
  check "  launcher frames greyed with the reason; set launcherframes refused" \
    eval '[ "$(sett launcherframes_state)" = "off:Needs my Mac driver, and the engine'"'"'s own winemac.so is chosen." ] && ! "$G" set launcherframes on >/dev/null 2>&1'
  out=$(g set macdrv mine 2>&1) && rc=0 || rc=$?
  check "set macdrv mine: mine again, the engine's own next to it as it ships, ntdll.so as it was" \
    eval '[ "$rc" = 0 ] && winemac_is mine && ntdll_is $MYWINE && [ "$(st macdrv_ready macdrv_file macdrv_commit)" = "yes/mine/$MYDRV_COMMIT" ] && [ "$(sett launcherframes_state)" = ok ]'
  if mine; then
    check "set wine engine and back: my winemac.so stays through both" \
      eval 'g set wine engine >/dev/null && ntdll_is engine && winemac_is mine && g set wine mine >/dev/null && ntdll_is mine && winemac_is mine'
  fi
  mv "$NT/winemac.so" "$NT/winemac.so.new"
  check "cut short between the renames (no winemac.so): macdrv_ready=switch" \
    [ "$(st macdrv_ready macdrv_file)" = "switch/$([ $W32U = mine ] && echo mix || echo none)" ]
  check "  the next set macdrv mine puts it in" eval 'g set macdrv mine >/dev/null && winemac_is mine && [ "$(st macdrv_ready)" = yes ]'
  echo "an earlier build of mine" >"$NT/winemac.so"
  check "an earlier build of mine in place: macdrv_ready=switch, macdrv_file=other (mix next to this build's win32u.so)" \
    [ "$(st macdrv_ready macdrv_file macdrv_commit)" = "switch/$([ $W32U = mine ] && echo mix || echo other)/" ]
  check "  set macdrv engine puts the engine's own back, set macdrv mine this build's" \
    eval 'g set macdrv engine >/dev/null && winemac_is engine && g set macdrv mine >/dev/null && winemac_is mine'
  check "  the engine's own winemac.so and wine.app as they ship through all of it" \
    eval 'same "$S/lib/wine/aarch64-unix/winemac.so" "$NT/winemac.so.engine" && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
else
  skipdrv "set macdrv engine and mine, and the switches cut short"
fi
# My Mac driver with win32u.so, as a build of jdrly/wine#61 has it: the two files switch as one set,
# both mine or both the engine's own. The app's components/macdrv gets a stand-in win32u.so and its
# VERSION line when its build has none (back at the end). The way to mine is two copies, then four
# renames (winemac.so aside, mine in, win32u.so aside, mine in); the way back two renames.
W32LEFT() { find "$NT" \( -name 'winemac.so.*' -o -name 'win32u.so.*' \) | LC_ALL=C sort; }
if drv; then
  W32U0=$W32U
  cp "$COMP/macdrv/VERSION" "$SANDBOX/macdrv-VERSION.w32"
  if [ "$W32U" = engine ]; then
    echo "my win32u.so" >"$COMP/macdrv/win32u.so"
    echo "win32u.so: sha256 $(shasum -a 256 "$COMP/macdrv/win32u.so" | cut -d' ' -f1)" >>"$COMP/macdrv/VERSION"
  fi
  cp "$COMP/macdrv/win32u.so" "$SANDBOX/win32u.keep"
  if [ "$W32U" = engine ]; then
    check "a build with win32u.so over one without: my winemac.so next to the engine's win32u.so is a mix, macdrv_ready=switch" \
      [ "$(st macdrv_file macdrv_ready win32u_bundled win32u_file)" = mix/switch/yes/engine ]
  fi
  out=$(g set macdrv mine 2>&1) && rc=0 || rc=$?
  check "set macdrv mine: my winemac.so and win32u.so in the engine, the engine's own next to each as <file>.engine" \
    eval '[ "$rc" = 0 ] && winemac_is mine && win32u_is mine && [ "$(st macdrv_file macdrv_ready macdrv_commit win32u_file)" = "mine/yes/$MYDRV_COMMIT/mine" ]'
  W32U=mine
  out=$(g set macdrv engine 2>&1) && rc=0 || rc=$?
  check "set macdrv engine: the engine's own winemac.so and win32u.so with the pinned hashes, nothing left over" \
    eval '[ "$rc" = 0 ] && winemac_is engine && win32u_is engine && [ -z "$(W32LEFT)" ] && [ "$(st macdrv_file macdrv_ready win32u_file)" = engine/yes/engine ] &&
      [ "$(shasum -a 256 "$NT/winemac.so" "$NT/win32u.so" | cut -d" " -f1 | tr "\n" " ")" = "$GW2_ON_MAC_ENGINE_WINEMAC_SHA256 $GW2_ON_MAC_ENGINE_WIN32U_SHA256 " ]'
  check "  it says so, naming both" eval 'echo "$out" | grep -qxF "$(drvsays engine)"'
  out=$(g set macdrv mine 2>&1)
  check "  set macdrv mine says so, naming both" eval 'echo "$out" | grep -qxF "$(drvsays mine)" && winemac_is mine && win32u_is mine'
  # A switch cut short after any of its renames, done here by hand in the switch's order, with the
  # setting already saved: the next switch finishes it. drv_cut <to> <n>: the way to <to> from the
  # other, cut after its first <n> renames (to mine after the copies)
  drv_cut() {
    local f i=0
    sed -i '' "s/^macdrv=.*/macdrv=$1/" "$AD/settings.conf"
    if [ "$1" = mine ]; then
      for f in winemac.so win32u.so; do cp -p "$COMP/macdrv/$f" "$NT/$f.new"; done
      for f in winemac.so win32u.so; do
        [ $i -lt "$2" ] || return 0; mv "$NT/$f" "$NT/$f.engine"; i=$((i + 1))
        [ $i -lt "$2" ] || return 0; mv "$NT/$f.new" "$NT/$f"; i=$((i + 1))
      done
    else
      for f in winemac.so win32u.so; do [ $i -lt "$2" ] || return 0; mv -f "$NT/$f.engine" "$NT/$f"; i=$((i + 1)); done
    fi
  }
  for n in 0 1 2 3; do
    g set macdrv engine >/dev/null
    drv_cut mine $n
    want=mix; [ $n != 0 ] || want=engine
    check "cut short on the way to mine after $n of 4 renames: macdrv_file=$want, macdrv_ready=switch; set macdrv mine finishes it$([ $n = 0 ] || echo ", saying so")" \
      eval '[ "$(st macdrv_file macdrv_ready)" = "$want/switch" ] && out=$(g set macdrv mine 2>&1) && winemac_is mine && win32u_is mine && [ -z "$(W32LEFT | grep "\.new$")" ] && { [ $n = 0 ] || echo "$out" | grep -q "^winemac.so and win32u.so: a mix of mine and the engine.s own winemac.so and win32u.so in the engine, a switch cut short; finishing the switch to my winemac.so and win32u.so"; }'
  done
  g set macdrv engine >/dev/null
  drv_cut mine 3
  check "cut short on the way to mine after 3 of 4 renames, then set macdrv engine: the engine's own pair, nothing left over" \
    eval 'g set macdrv engine >/dev/null && winemac_is engine && win32u_is engine && [ -z "$(W32LEFT)" ]'
  g set macdrv mine >/dev/null
  drv_cut engine 1
  check "cut short on the way back after 1 of 2 renames: a mix; set macdrv engine finishes it, nothing left over" \
    eval '[ "$(st macdrv_file macdrv_ready)" = mix/switch ] && g set macdrv engine >/dev/null && winemac_is engine && win32u_is engine && [ -z "$(W32LEFT)" ]'
  # A build without win32u.so after one with it: my winemac.so alone, and the engine's own win32u.so
  # back in place
  g set macdrv mine >/dev/null
  rm -f "$COMP/macdrv/win32u.so" && grep -v '^win32u\.so: ' "$SANDBOX/macdrv-VERSION.w32" >"$COMP/macdrv/VERSION"
  check "a build without win32u.so over one with it: a mix (this build's winemac.so, the earlier build's win32u.so)" \
    [ "$(st macdrv_file macdrv_ready win32u_bundled win32u_file)" = mix/switch/no/other ]
  out=$(g set macdrv mine 2>&1) && rc=0 || rc=$?
  check "  set macdrv mine: my winemac.so alone, the engine's own win32u.so back in place, nothing next to it" \
    eval '[ "$rc" = 0 ] && winemac_is mine && win32u_is engine && [ "$(st macdrv_file macdrv_ready win32u_file)" = mine/yes/engine ]'
  # back to the app's own components, and the set its build asks for
  cp "$SANDBOX/macdrv-VERSION.w32" "$COMP/macdrv/VERSION"
  W32U=$W32U0
  [ "$W32U" = engine ] || cp "$SANDBOX/win32u.keep" "$COMP/macdrv/win32u.so"
  g set macdrv mine >/dev/null
  check "  back to this app's own build: winemac.so mine, win32u.so $W32U" eval 'winemac_is mine && win32u_is $W32U && [ "$(st macdrv_ready)" = yes ]'
else
  skipdrv "my winemac.so and win32u.so as one set, and the switches cut short"
fi
# My FEX and the engine's own, and back (nothing runs: the three files switch at once). The way
# there is three copies, then six renames; the way back three renames
FEXLEFT() { find "$FW" \( -name 'xtajit64.dll.*' -o -name 'libarm64ecfex.*.*' \) | LC_ALL=C sort; }
if fexb; then
  out=$(g set fex mine 2>&1) && rc=0 || rc=$?
  check "set fex mine: my FEX's three files in the engine, the engine's own next to each as <file>.engine" \
    eval '[ "$rc" = 0 ] && fex_is mine && [ "$(st fex fex_ready fex_file fex_commit fex_build)" = "mine/yes/mine/$MYFEX_COMMIT/$MYFEX_COMMIT" ] && ! echo "$out" | grep -q Repair'
  check "  it says so" has <(echo "$out") "^FEX: my FEX (jdrly/FEX ${MYFEX_COMMIT:0:11}) is in the engine, the engine's own kept next to each of its three files as <file>.engine$"
  check "  ntdll.so, winemac.so, the DXMT trees and wine.app as they were" \
    eval 'ntdll_is $MYWINE && winemac_is $MYDRV && dxgi_is fork && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
  out=$(g set fex engine 2>&1) && rc=0 || rc=$?
  check "set fex engine: the engine's own three files with the pinned hashes, nothing left over" \
    eval '[ "$rc" = 0 ] && fex_is engine && [ -z "$(FEXLEFT)" ] && [ "$(st fex_ready fex_file fex_commit)" = "yes/engine/$ENGINE_FEX" ] &&
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
      eval '[ "$(st fex_file fex_ready)" = "$want/switch" ] && out=$(g set fex mine 2>&1) && fex_is mine && [ -z "$(FEXLEFT | grep "\.new$")" ] && { [ $n = 0 ] || echo "$out" | grep -q "^FEX: the engine.s FEX files are a mix of my FEX and the engine.s own, a switch cut short; finishing the switch to my FEX"; }'
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
      eval '[ "$(st fex_file fex_ready)" = "mix/switch" ] && g set fex engine >/dev/null && fex_is engine && [ -z "$(FEXLEFT)" ]'
  done
  # an earlier build of mine (an older version of the app's) in place of all three
  g set fex mine >/dev/null
  for f in $FEXF; do echo "an earlier build of mine" >"$FW/$f"; done
  check "an earlier build of my FEX in place: fex_file=other, fex_ready=switch; set fex mine puts this build's in" \
    eval '[ "$(st fex_file fex_ready fex_commit)" = other/switch/ ] && g set fex mine >/dev/null && fex_is mine'
  g set fex engine >/dev/null
  check "  the engine's own FEX and wine.app as they ship through all of it" eval 'fex_is engine && [ -z "$(FEXLEFT)" ] && [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]'
else
  out=$(g set fex mine 2>&1) && rc=0 || rc=$?
  check "no FEX of mine in this app: set fex mine refused, saying so; the engine's files untouched" \
    eval '[ "$rc" != 0 ] && [ "$out" = "@error This build carries no FEX of mine." ] && [ "$(sett fex_state)" = "off:This build carries no FEX of mine." ] && fex_is engine'
  sed -i '' 's/^fex=.*/fex=mine/' "$AD/settings.conf"
  g set dxmt engine >/dev/null; g set dxmt fork >/dev/null
  check "  fex=mine in settings.conf by hand: the engine's own stays through the engine's switches" eval 'fex_is engine && [ "$(st fex_ready fex_file)" = yes/engine ]'
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
check "settings: rawmouse=on, mousespeed=1 by default" [ "$(sett rawmouse mousespeed)" = on/1 ]
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
check "settings.conf has every key and settings_version" [ "$(grep -c '=' "$AD/settings.conf")" = 29 ]

section "The larger interface (addon)"
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
check "arcdps off by default: status arcdps=off, arcdps_state=off" [ "$(st arcdps arcdps_state)" = off/off ]
check "  settings say so too, and settings.conf has no arcdps key" eval '[ "$(sett arcdps arcdps_state)" = off/off ] && ! grep -q "^arcdps=" "$AD/settings.conf"'
out=$(g set arcdps on 2>&1) && rc=0 || rc=$?
check "set arcdps on: downloads it (with progress) and says so" eval '[ "$rc" = 0 ] && echo "$out" | grep -q "^@progress arcdps " && echo "$out" | grep -q "^@done arcdps is in the game folder"'
check "  d3d11.dll next to Gw2-64.exe is the published file" same "$ARCSRV/d3d11.dll" "$GD/d3d11.dll"
check "  arcdps=on, arcdps_state=on" [ "$(st arcdps arcdps_state)" = on/on ]
check "  nothing left in the downloads, no temporary file in the game folder" eval '[ ! -e "$CACHE/downloads/arcdps" ] && ! ls -a "$GD" | grep -q gw2om-new'
check "  and for rundll32.exe: d3d11 and dxgi native,builtin (arcdps's crash window and update)" rundll on
check "set arcdps on again: already there" sh -c "'$G' set arcdps on | grep -q 'already in the game folder'"
# arcdps updates itself: a newer arcdps (another hash) still counts as arcdps
printf 'self-updated\n' >>"$GD/d3d11.dll"
mkdir -p "$GD/addons/arcdps" && echo "[session]" >"$GD/addons/arcdps/arcdps.ini"
check "an arcdps that updated itself (another hash) is still on" [ "$(arcst)" = on ]
check "set arcdps off: d3d11.dll removed" sh -c "'$G' set arcdps off | grep -q '^@done arcdps is off' && [ ! -e '$GD/d3d11.dll' ]"
check "  its settings (addons/arcdps) stay" has "$GD/addons/arcdps/arcdps.ini" session
check "  arcdps_state=off" [ "$(arcst)" = off ]
check "  rundll32.exe's d3d11 and dxgi deleted" rundll off
check "arcdps x maybe refused (exit 2)" sh -c "'$G' set arcdps maybe >/dev/null; [ \$? = 2 ]"
# as dxgi.dll it counts too, and off removes it there
cp "$SANDBOX/pe/arcdps.dll" "$GD/dxgi.dll"
check "arcdps as dxgi.dll: on" [ "$(st arcdps arcdps_state)" = on/on ]
g set arcdps off >/dev/null 2>&1
check "  off removes that dxgi.dll" [ ! -e "$GD/dxgi.dll" ]
# another addon's d3d11.dll (Nexus): foreign, never touched
cp "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"
check "another addon's d3d11.dll (with arcdps's words outside its exports): arcdps_state=foreign, arcdps=off" [ "$(st arcdps_state arcdps)" = foreign/off ]
check "  arcdps_foreign names it" [ "$(st arcdps_foreign)" = d3d11.dll ]
g set rawmouse on >/dev/null
check "  rundll32.exe gets d3d11 and dxgi native,builtin for it too" rundll on
out=$(g set arcdps on 2>&1) && rc=0 || rc=$?
check "  set arcdps on refused, saying why, the file left alone" eval '[ "$rc" != 0 ] && echo "$out" | grep -q "^@error The game folder has another d3d11.dll" && same "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"'
check "  set arcdps off leaves it alone too" sh -c "'$G' set arcdps off | grep -q 'stays as it is' && cmp -s '$SANDBOX/pe/nexus.dll' '$GD/d3d11.dll'"
mv "$GD/d3d11.dll" "$GD/dxgi.dll"
check "  another addon's dxgi.dll: foreign as well" eval '[ "$(arcst)" = foreign ] && ! "$G" set arcdps on >/dev/null 2>&1 && same "$SANDBOX/pe/nexus.dll" "$GD/dxgi.dll"'
rm -f "$GD/dxgi.dll"
g set rawmouse on >/dev/null
check "  gone: rundll32.exe's d3d11 and dxgi deleted" rundll off
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
# The texts are pinned in scripts/compatdb-check/rules, which CI reads with Mach9 0.4.0's
# compatdb-core; there the sandbox's home is /Users/me
FIX="$ROOT/scripts/compatdb-check/rules"
rules_are() { g rules | sed "s|$H|/Users/me|g" | cmp -s - "$FIX/$1.rules"; }
# (the engine's own ntdll.so, so no WINE_HEAT_* entry, until the checks of my ntdll.so's switches below)
! mine || g set wine engine >/dev/null
check "everything off: the cache path and Metal 3 (DXMT_METAL4=0) for the game, both taken away from CefHost.exe" rules_are off
g set metal 4 >/dev/null
# (Metal 4's present, DXMT_MTL4_PRESENT=mtl3: in the rule only while my fork's tree in the engine
# names it. The app's build may or may not, so the tree's DLLs give way to one without the name,
# then to one with it, and come back after; status to a file, for grep)
MTREE="$ENG/lib/wine/dxgi/dxmt/aarch64-windows"
rm -rf "$SANDBOX/mtree.keep" && cp -Rp "$MTREE" "$SANDBOX/mtree.keep"
for f in "$MTREE"/*.dll; do echo "an earlier build" >"$f"; done
g status >"$SANDBOX/m-status.txt" 2>&1
check "Metal 4 with a fork that doesn't name DXMT_MTL4_PRESENT: DXMT_METAL4=1 alone for the game, unset for CefHost.exe; status says why the present stays out" \
  eval 'rules_are metal4 && grep -qx "metal_present=" "$SANDBOX/m-status.txt" && grep -qxF "metal_present_out=DXMT_MTL4_PRESENT=mtl3 (my DXMT fork doesn'"'"'t have it)" "$SANDBOX/m-status.txt"'
printf 'x\0DXMT_MTL4_PRESENT\0' >"$MTREE/d3d11.dll"
g status >"$SANDBOX/m-status.txt" 2>&1
check "  one that names it: DXMT_MTL4_PRESENT=mtl3 right after DXMT_METAL4=1, unset for CefHost.exe; status says it's in" \
  eval 'rules_are metal4-present && grep -qx "metal_present=DXMT_MTL4_PRESENT=mtl3" "$SANDBOX/m-status.txt" && grep -qx "metal_present_out=" "$SANDBOX/m-status.txt"'
g set metal 3 >/dev/null
g status >"$SANDBOX/m-status.txt" 2>&1
check "  at Metal 3: none, and status says why" \
  eval 'rules_are off && grep -qxF "metal_present_out=DXMT_MTL4_PRESENT=mtl3 (the Metal row is at Metal 3)" "$SANDBOX/m-status.txt"'
g set metal 4 >/dev/null
rm -rf "$MTREE" && cp -Rp "$SANDBOX/mtree.keep" "$MTREE"
# (the app's own tree again, which may name it: the rule ends either way)
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "  a dry run of Play prints the game's rule with it" eval 'echo "$out" | grep -qxF "[dry-run] rule $(g rules | head -1)" && echo "$out" | grep -qE "^\[dry-run\] rule exe=Gw2-64.exe;.*;env=DXMT_METAL4=1(;env=DXMT_MTL4_PRESENT=mtl3)?$"'
printf 'exe=Gw2-64.exe;env=DXMT_METAL4=0\n' >"$AD/compatdb.local"
check "  a compatdb.local line comes after the rules, so its DXMT_METAL4=0 is the last word" \
  eval '[ "$(g rules | sed -n 3p)" = "exe=Gw2-64.exe;env=DXMT_METAL4=0" ] && g rules | sed -n 1p | grep -qE ";env=DXMT_METAL4=1(;env=DXMT_MTL4_PRESENT=mtl3)?$"'
rm -f "$AD/compatdb.local"
g set dxmt engine >/dev/null
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "  the engine's own DXMT: no DXMT_METAL4 in the rules or in a dry run of Play" eval 'rules_are engine-dxmt && ! echo "$out" | grep -q DXMT_METAL4'
g set dxmt fork >/dev/null; g set metal 3 >/dev/null
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "Metal 3 again: a dry run of Play prints the rule with DXMT_METAL4=0" eval 'rules_are off && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=[^;]*;env=DXMT_METAL4=0$"'
g set vsync off >/dev/null
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "Vsync off: DXMT_DISPLAY_SYNC=0 for the game after DXMT_METAL4, unset for CefHost.exe; a dry run of Play prints it" \
  eval 'rules_are vsync-off && echo "$out" | grep -qxF "[dry-run] rule $(g rules | head -1)" && ! g env | grep -q DXMT_DISPLAY_SYNC'
g set dxmt engine >/dev/null
check "  with the engine's own DXMT: none, the row greyed" eval 'rules_are engine-dxmt && [ "$(sett vsync_state)" = "off:Needs my DXMT fork, and the engine'"'"'s own DXMT is chosen." ]'
g set dxmt fork >/dev/null; g set vsync on >/dev/null
check "  Vsync on again: the rules as before" rules_are off
g set hud on >/dev/null
check "the HUD on: metal_hud=true for the game, false for CefHost.exe" rules_are hud
g set hud off >/dev/null; g set uiscale on >/dev/null
check "the larger interface on: version native first" rules_are addon
g set hud on >/dev/null; cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"
check "the HUD and the larger interface on, arcdps in the game folder: d3d11 and dxgi native first too, for the game and for rundll32.exe (arcdps's crash window)" rules_are hud-addon-arcdps
rm -f "$GD/version.dll"
check "  the addon's version.dll missing: the override stays (n,b loads Wine's own)" rules_are hud-addon-arcdps
cp "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"
check "  another addon's d3d11.dll (Nexus): native first as well, for the game and for rundll32.exe" \
  eval 'g rules | grep "^exe=Gw2-64.exe;metal_hud=true;dll_overrides=d3d11,dxgi=n,b;" >/dev/null && [ "$(g rules | tail -1)" = "exe=rundll32.exe;dll_overrides=d3d11,dxgi=n,b" ]'
g set hud off >/dev/null; g set uiscale off >/dev/null; rm -f "$GD/d3d11.dll"
check "  all off again, with no rule for rundll32.exe" rules_are off
cp "$SANDBOX/pe/reshade-addon.dll" "$GD/d3d11.dll"
check "a ReShade in the game folder: d3d11 and dxgi native first, d3dcompiler_47 too (Microsoft's compiler next to Gw2-64.exe), and rundll32.exe's line" \
  rules_are reshade
rm -f "$GD/d3d11.dll"
g set rawmouse off >/dev/null
check "raw mouse-look off: gcmouse=false for the game, nothing for CefHost.exe" \
  eval '[ "$(g rules | head -1)" = "exe=Gw2-64.exe;gcmouse=false;env=DXMT_SHADER_CACHE_PATH=$DXMT_CACHE;env=DXMT_METAL4=0" ] && [ "$(g rules | tail -1)" = "exe=CefHost.exe;env=DXMT_SHADER_CACHE_PATH=;env=DXMT_METAL4=" ]'
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
  check "  the any row's setting off: the fork row's entry alone" eval 'GW2_ON_MAC_FEX_SWITCHES="$FEXROWS" g rules | head -1 | grep -q ";env=DXMT_SHADER_CACHE_PATH=[^;]*;env=DXMT_METAL4=0;env=FEX_TESTFORK=1$"'
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
  check "my ntdll.so, every switch off: no WINE_HEAT_* entry, not even WINE_HEAT_MSYNC_UNREG (#105)" rules_are off
  check "  a dry run of Play prints the same rule" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
  # (with my FEX in place too: the FEX my ntdll.so's sampler may read, from my FEX's VERSION, only
  # for an ntdll.so whose VERSION names it on its switches: line; no line, an empty one or one
  # without it is no. WINE_HEAT_MSYNC_UNREG on that line, as an ntdll.so from before #104 has it,
  # adds nothing. The staged VERSION back after)
  if fexb; then
    FEXID=$(sed -n 's/^libarm64ecfex\.dll: build id \([0-9a-f]\{32\}\) age \([0-9]\{1,\}\), SizeOfImage \(0x[0-9a-f]\{1,\}\)$/\1:\2:\3/p' "$COMP/fex/VERSION")
    cp "$COMP/ntdll/VERSION" "$SANDBOX/ntdll-VERSION.prof"
    nt_switches() { { grep -v '^switches:' "$SANDBOX/ntdll-VERSION.prof"; [ "$1" = none ] || echo "switches:${1#-}"; } >"$COMP/ntdll/VERSION"; }
    g set fex mine >/dev/null
    nt_switches " WINE_HEAT_MSYNC_UNREG WINE_HEAT_PROF_FEX"
    check "  and my FEX in place, my ntdll.so's VERSION naming it: WINE_HEAT_PROF_FEX=<build id>:<age>:<SizeOfImage> after it, unset for CefHost.exe" \
      eval '[ -n "$FEXID" ] && [ "$(g rules | sed "s|$H|/Users/me|g" | tr "\n" "|")" = "$(head -1 "$FIX/off.rules");env=WINE_HEAT_PROF_FEX=$FEXID|$(tail -1 "$FIX/off.rules");env=WINE_HEAT_PROF_FEX=|" ]'
    for sw in none - " WINE_HEAT_MSYNC_UNREG"; do
      nt_switches "$sw"
      check "  an ntdll.so VERSION with $([ "$sw" = none ] && echo "no switches: line" || { [ "$sw" = - ] && echo "an empty switches: line" || echo "a switches: line without it"; }): no WINE_HEAT_PROF_FEX" \
        eval '! g rules | grep -q WINE_HEAT_PROF_FEX'
    done
    nt_switches " WINE_HEAT_MSYNC_UNREG WINE_HEAT_PROF_FEX"
    g set wine engine >/dev/null
    check "  my FEX with the engine's own ntdll.so: no WINE_HEAT_PROF_FEX" eval '! g rules | grep -q WINE_HEAT_PROF_FEX'
    g set wine mine >/dev/null; g set fex engine >/dev/null
    check "  the engine's own FEX with my ntdll.so: none either" rules_are off
    cp "$SANDBOX/ntdll-VERSION.prof" "$COMP/ntdll/VERSION"
  fi
  g set jobwakes on >/dev/null
  check "job wakes on: WINE_HEAT_WAKE=one,skip for the game, unset for CefHost.exe" rules_are jobwakes
  check "  a dry run of Play prints the game's rule with it" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
  g set debug on >/dev/null
  check "  with Debug logging: the counters too, written to the logs folder, and FEX's messages; not FEX's counters, with the engine's own FEX (#344)" rules_are jobwakes-debug
  # (FEX's counters, FEX_PROFILESTATS=1, only with my FEX in place and profilestats-slots on its
  # VERSION's fixes: line: the engine's own FEX faults at its 37th thread with it on macOS (#344).
  # No line, an empty one or one without it is no. The staged VERSION back after; a
  # WINE_HEAT_PROF_FEX the staged files may add is left out of the comparison)
  if fexb; then
    cp "$COMP/fex/VERSION" "$SANDBOX/fex-VERSION.fixes"
    fex_fixes() { { grep -v '^fixes:' "$SANDBOX/fex-VERSION.fixes"; [ "$1" = none ] || echo "fixes:${1#-}"; } >"$COMP/fex/VERSION"; }
    fex_fixes " profilestats-slots"
    check "  my FEX in the app naming profilestats-slots, the engine's own in place: still no FEX_PROFILESTATS" rules_are jobwakes-debug
    g set fex mine >/dev/null
    check "  and my FEX in place, its VERSION naming profilestats-slots: FEX's counters too, FEX_PROFILESTATS=1 before FEX_SILENTLOG=0, unset for CefHost.exe" \
      eval '[ "$(g rules | sed "s|$H|/Users/me|g; s/;env=WINE_HEAT_PROF_FEX=[^;]*//")" = "$(cat "$FIX/jobwakes-debug-fex.rules")" ]'
    check "  a dry run of Play prints the game's rule with it" eval '[ "$(dry_rule)" = "$(g rules | head -1)" ]'
    for fx in none - " other-fix"; do
      fex_fixes "$fx"
      check "  my FEX whose VERSION has $([ "$fx" = none ] && echo "no fixes: line" || { [ "$fx" = - ] && echo "an empty fixes: line" || echo "a fixes: line without it"; }): no FEX_PROFILESTATS" \
        eval '! g rules | grep -q FEX_PROFILESTATS && g rules | head -1 | grep -q ";env=WINE_HEAT_LOG=[^;]*;env=FEX_SILENTLOG=0$"'
    done
    cp "$SANDBOX/fex-VERSION.fixes" "$COMP/fex/VERSION"
    g set fex engine >/dev/null
  fi
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
  # replaces any the VERSION has. Twice: from the staged VERSION as it is (the stand-in's line or the
  # dev build's, without WINE_HEAT_MSYNC_UNREG since #104), and from that VERSION with the line of
  # dev.11's 8752da04c30, which still names it. Neither rule has the entry. The staged VERSION back
  # after
  cp "$COMP/ntdll/VERSION" "$SANDBOX/ntdll-VERSION.keep"
  for from in "the staged VERSION" "dev.11's VERSION"; do
    if [ "$from" = "the staged VERSION" ]; then cp "$SANDBOX/ntdll-VERSION.keep" "$SANDBOX/ntdll-VERSION.from"
    else
      { grep -v '^switches:' "$SANDBOX/ntdll-VERSION.keep"
        echo "switches: WINE_HEAT_COUNT WINE_HEAT_EVPOOL WINE_HEAT_EXE WINE_HEAT_LOG WINE_HEAT_MSYNC_UNREG WINE_HEAT_PROF WINE_HEAT_PROF_HZ WINE_HEAT_PROF_THREADS WINE_HEAT_SPIN WINE_HEAT_SPIN_PAUSE WINE_HEAT_WAKE"; } >"$SANDBOX/ntdll-VERSION.from"
    fi
    { grep -v '^switches:' "$SANDBOX/ntdll-VERSION.from"
      echo "switches: WINE_HEAT_COUNT WINE_HEAT_EXE WINE_HEAT_LOG WINE_HEAT_MSYNC_UNREG WINE_HEAT_WAKE"; } >"$COMP/ntdll/VERSION"
    check "from $from, a VERSION that lists WINE_HEAT_WAKE and WINE_HEAT_MSYNC_UNREG only: event pool and fast locks stay out" rules_are jobwakes
    check "  event pool and fast locks greyed, saying so; set refused" \
      eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" jobwakes_state)" = ok ] && [ "$(kv "$SET_OUT" eventpool_state)" = "off:My Wine build in this app (jdrly/wine ${MYWINE_COMMIT:0:11}) doesn'"'"'t have this switch." ] && [ "$(kv "$SET_OUT" fastlocks_state)" = "$(kv "$SET_OUT" eventpool_state)" ] && ! "$G" set fastlocks off >/dev/null 2>&1'
    cp "$SANDBOX/ntdll-VERSION.from" "$COMP/ntdll/VERSION"
    check "  $from again: all three" rules_are heat-all
  done
  cp "$SANDBOX/ntdll-VERSION.keep" "$COMP/ntdll/VERSION"
  g set debug on >/dev/null; g set wine engine >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "wine engine, every switch and Debug logging on: no WINE_HEAT_* nor FEX_PROFILESTATS in the rules or in a dry run of Play, FEX_SILENTLOG=0 alone" \
    eval 'rules_are debug-engine && ! echo "$out" | grep -qE "WINE_HEAT_|FEX_PROFILESTATS" && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=[^;]*;env=DXMT_METAL4=0;env=FEX_SILENTLOG=0$"'
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
    check "  with my ntdll.so, job wakes and Debug logging: both files' switches in the table's order, then the counters (not FEX's, with the engine's own FEX)" rules_are launcherframes-jobwakes-debug
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
    eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" mousespeed_state)" = "off:My Mac driver in this app (jdrly/wine ${MYDRV_COMMIT:0:11}) doesn'"'"'t have this switch." ] && [ "$(kv "$SET_OUT" launcherframes_state)" = ok ] && ! "$G" set mousespeed 2 >/dev/null 2>&1 && rules_are off'
  drv_switches WINE_MACDRV_MOUSE_SCALE WINE_MACDRV_SURFACE
  check "  one that lists WINE_MACDRV_MOUSE_SCALE too: ok, and the entry back" eval '[ "$(sett mousespeed_state)" = ok ] && rules_are mousespeed'
  g set mousespeed 1 >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "mouse-look speed 1: no WINE_MACDRV_* in the rules or in a dry run of Play" \
    eval 'rules_are off && ! echo "$out" | grep -q WINE_MACDRV_ && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=[^;]*;env=DXMT_METAL4=0$"'
  g set launcherframes on >/dev/null; g set mousespeed 1.5 >/dev/null; g set macdrv engine >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
  check "macdrv engine with launcher frames on and mouse-look speed 1.5: no WINE_MACDRV_* in the rules or in a dry run of Play" \
    eval 'rules_are off && ! echo "$out" | grep -q WINE_MACDRV_ && echo "$out" | grep -q "^\[dry-run\] rule exe=Gw2-64.exe;env=DXMT_SHADER_CACHE_PATH=[^;]*;env=DXMT_METAL4=0$"'
  check "  mouse-look speed greyed with launcher frames' reason" eval 'SET_OUT=$(g settings); [ "$(kv "$SET_OUT" mousespeed_state)" = "off:Needs my Mac driver, and the engine'"'"'s own winemac.so is chosen." ] && [ "$(kv "$SET_OUT" launcherframes_state)" = "$(kv "$SET_OUT" mousespeed_state)" ]'
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
# at settings_version 2 so wine=engine isn't reset, and Metal 3, so no tree's names count) is all there is in it
ODD="$SANDBOX/a%b;c$(printf '\t')d é"
ODD_CONF="$ODD/home/Library/Application Support/$APP_FOLDER/settings.conf"
mkdir -p "${ODD_CONF%/*}" && printf 'settings_version=2\nwine=engine\ndebug=off\nmetal=3\n' >"$ODD_CONF"
odd_rules_are() { GW2_ON_MAC_ROOT="$ODD" "$G" rules | sed "s|$SANDBOX/a%25b%3Bc%09d é/home|/Users/a%25b%3Bc%09d é|g" | cmp -s - "$FIX/$1.rules"; }
odd_only_conf() { [ "$(cd "$ODD" && find . | LC_ALL=C sort | tr '\n' '|')" = ".|./home|./home/Library|./home/Library/Application Support|./home/Library/Application Support/$APP_FOLDER|./home/Library/Application Support/$APP_FOLDER/settings.conf|" ]; }
check "a home with %, ; and a tab: escaped as %XX, the é as it is" eval 'odd_rules_are escaped && odd_only_conf'
if mine; then
  printf 'jobwakes=on\neventpool=off\ndebug=on\nmetal=3\n' >"$ODD_CONF"
  check "  with job wakes and Debug logging on: the logs folder escaped the same way" eval 'odd_rules_are escaped-heat && odd_only_conf'
fi
rm -rf "$ODD"
printf 'exe=Gw2-64.exe;env=FEX_HOSTFEATURES=disableavx\n' >"$AD/compatdb.local"
check "compatdb.local is appended as it is" eval '[ "$(g rules | tail -1)" = "exe=Gw2-64.exe;env=FEX_HOSTFEATURES=disableavx" ] && [ "$(g rules | wc -l | tr -d " ")" = 3 ]'
# a dry run of play with every setting of 0.1.x's environment on in settings.conf
cp "$AD/settings.conf" "$SANDBOX/settings.keep"
sed -i '' -e 's/^metalfx=.*/metalfx=on/' -e 's/^hud=.*/hud=on/' -e 's/^debug=.*/debug=on/' "$AD/settings.conf"
out=$(GW2_ON_MAC_DRY_RUN=1 g play 2>&1)
check "dry-run play: the bottle's user, the engine's variables, the app's files, my DXMT fork's switches and the CPUs, nothing else" \
  eval '[ "$(echo "$out" | sed -n "s/^\[dry-run\]   //p" | grep -v ^WINENCPU= | tr "\n" "|")" = "USER=crossover|WINEPREFIX=$BOTTLE|WINEDEBUG=$WINEDEBUG_ON|WINEDLLOVERRIDES=winemenubuilder.exe=d|WINEMSYNC=1|DXMT_CONFIG_FILE=$AD/dxmt.conf|DXMT_LOG_PATH=$LOGS|WINE_COMPATDB_FILE=$AD/compatdb.rules|DXMT_CACHE_DIR=$CACHE/fork|DXMT_DEPENDENCY_COMPRESSION=1|DXMT_WARM=all|DXMT_SUBSAMPLE_METALFX=1|DXMT_LOG_LEVEL=debug|DXMT_STATS=1|" ] && echo "$out" | grep -q "^\[dry-run\]   WINENCPU="'
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
  eval 'has "$LOGS/session.env" "^ENGINE=mach9-v0.4.0$" && has "$LOGS/session.env" "^ENGINE_FEX=" && has "$LOGS/session.env" "^SETTING_hud=off$" && has "$LOGS/session.env" "^SETTING_metal=3$" && has "$LOGS/session.env" "^WINE_COMPATDB_FILE=" && [ "$(sed -n "s/^RULE=//p" "$LOGS/session.env")" = "$(cat "$AD/compatdb.rules")" ]'
check "  and which DXMT the session loads: my fork, its build" \
  eval 'has "$LOGS/session.env" "^DXMT_TREE=fork$" && [ "$(sed -n "s/^DXMT_FORK=//p" "$LOGS/session.env")" = "$(head -1 "$COMP/dxmt/VERSION")" ] && has "$LOGS/session.env" "^SETTING_dxmt=fork$"'
if mine; then
  check "  and which ntdll.so: mine, its commit and the sha256 of the file in the engine; its switches in the game's rule" \
    eval '[ "$(sed -n "s/^LIB_wine=//p" "$LOGS/session.env")" = "ntdll.so mine $MYWINE_COMMIT $(shasum -a 256 "$COMP/ntdll/ntdll.so" | cut -d" " -f1)" ] && grep -q "^RULE=exe=Gw2-64.exe;.*;env=WINE_HEAT_WAKE=one,skip;env=WINE_HEAT_EVPOOL=1$" "$LOGS/session.env"'
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
check "  and which KosmicKrisp: $(kkb && echo mine || echo "the engine's own"), with its commit and the sha256 of the file in the engine" \
  eval '[ "$(sed -n "s/^LIB_kosmickrisp=//p" "$LOGS/session.env")" = "$(kkb && echo "mine $MYKK_COMMIT" || echo "engine $ENGINE_MESA") $(shasum -a 256 "$KKF" | cut -d" " -f1)" ]'

section "Collect Logs (redaction and the leak check)"
mkdir -p "$STEAM/config" "$STEAM/logs" "$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2"
printf '"users"\n{\n\t"76561198000000042"\n\t{\n\t\t"AccountName"\t\t"zz_acct_name"\n\t\t"PersonaName"\t\t"Zz Persona Q"\n\t}\n}\n' >"$STEAM/config/loginusers.vdf"
printf '[2026-11-04] AppID 1284210 update started : download 0/58900000000\nUser zz_acct_name (76561198000000042) [U:1:39734314] logged in, path %s\n' "$HOME/Library" >"$STEAM/logs/content_log.txt"
printf 'Crash\nName: ZZ-MACHINE\nIpAddr: 192.168.77.5\nLogin: zz.person@example.com\nException: c0000005\n' >"$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2/ArenaNet.log"
printf 'started by %s from %s/Library, mail zz.person@example.com, token=abcDEF123secret\n' "$(id -un)" "$HOME" >>"$LOGS/wine.log"
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\ninfo:  STATS fps=60.0 ms=16.7/24.8 cb=1.1 rp=31.7(+0.0 merged) encode=0.23+1.03/10.3\ninfo:  HITCH frame=52 ms=120.0 dxmt(ms/calls): create=4.0/37 flush=3.5/1\n' >"$LOGS/Gw2-64_d3d11.log"
# (arcdps's logs and the crash dumps as the game's crash of 2026-11-13 left them, shortened:
# arcdps's crash log with the game's assertion and a module in the bottle user's Temp folder, and
# arcdps.log with a GW2 account name; Steam's assert dump, one of the game folder and one of the
# game's AppData folder; an older dump, one too large, one with the bottle user's folder in
# UTF-16, one with a second Steam user's persona name outside ASCII in UTF-16 at an odd offset,
# one with the account name in capitals (ZZ_ACCT_NAME: found_name would take NAME out), one with a
# GW2 account name; and .dmp files outside the dump folders and outside the bottle)
ARC="$GD/addons/arcdps" GW2A="$BOTTLE/drive_c/users/$BUSER/AppData/Roaming/Guild Wars 2"
mkdir -p "$ARC" "$STEAM/dumps" "$H/Library/Logs/DiagnosticReports"
printf '%s\n' '2026-11-13 13:23:24.244: info: build 20261023.230314-613-x64' \
  '2026-11-13 13:23:24.536: info: detected wine 11.21' \
  '2026-11-13 13:42:39.573: error: intercepted gw2 assertion "frameId", file "D:\Perforce\Live\NAEU\v2\Code\Gw2\Engine\Frame\FrApi.cpp", line 2289' \
  '	---- client -------' '	build: 210361' '	map: The Silverwastes (1015)' \
  "	0x6FFFD6FB1000 0x6FFFD6FFF000 C:\\users\\$BUSER\\AppData\\Local\\Temp\\21363cb5\\steam_api64.dll" \
  '	0x0001409DBEBD: 0x0000FFFFFFFF :0+09DBEBD gw2-64' >"$ARC/arcdps_lastcrash.log"
{ cat "$ARC/arcdps_lastcrash.log"; echo '2026-11-13 13:42:40.000: info: self Zz Arc Acct.1234'; } >"$ARC/arcdps.log"
printf 'MDMP\0\0\0\0Assert( Couldn'"'"'t get string length ):C:\\buildworker\\steam_rel_client_win64\\build\\src\\vgui2\\vgui_surfacelib\\Win32Font.cpp:1129\0' \
  >"$STEAM/dumps/assert_steam.exe_20261113132231_1.dmp"
printf 'MDMP\0\0\0\0steam.exe\0' >"$STEAM/dumps/assert_gameoverlayui64.exe_20250101000000_1.dmp"
touch -t 202501010000 "$STEAM/dumps/assert_gameoverlayui64.exe_20250101000000_1.dmp"
dd if=/dev/zero of="$STEAM/dumps/assert_large.dmp" bs=1 count=0 seek=6000000 2>/dev/null
{ printf 'MDMP\0\0\0\0'; printf 'C:\\users\\%s\\AppData' "$(id -un)" | iconv -f ASCII -t UTF-16LE; } >"$STEAM/dumps/assert_userpath.dmp"
cp "$STEAM/config/loginusers.vdf" "$SANDBOX/loginusers.keep"
printf '\t"76561198000000043"\n\t{\n\t\t"AccountName"\t\t"zz_second"\n\t\t"PersonaName"\t\t"Zž Persona Ř"\n\t}\n' >>"$STEAM/config/loginusers.vdf"
{ printf 'MDMP\0\0\0'; printf 'Zž Persona Ř' | iconv -f UTF-8 -t UTF-16LE; } >"$STEAM/dumps/assert_persona.dmp"
printf 'MDMP\0\0\0\0ZZ_ACCT_NAME\0' >"$STEAM/dumps/assert_marker.dmp"
printf 'MDMP\0\0\0\0self Zz Arc Acct.1234\0' >"$STEAM/dumps/assert_account.dmp"
printf 'MDMP\0\0\0\0Gw2-64.exe\0' >"$GD/Crash.dmp"
printf 'MDMP\0\0\0\0Gw2-64.exe appdata\0' >"$GW2A/Crash.dmp"
for f in "$H/decoy.dmp" "$BOTTLE/drive_c/decoy.dmp" "$H/Library/Logs/DiagnosticReports/Gw2-64.exe.dmp"; do printf 'MDMP\0decoy\0' >"$f"; done
# (macOS's crash reports as .ips, a line of JSON and then the report's JSON. Of this app's
# processes, by their coalition, the app's bundle ID: the game's, with its path in the home folder
# as macOS writes it (/Users/USER/*/...) and the home folder in its images (\/) and in a Windows
# path (\\). By their path in the engine's folder, in another coalition: one with /, and 9 with \/,
# the oldest 2 days old, one more than the 10 Collect Logs takes. Not ours: another Wine's game and
# its wine with the same names and paths, and an unrelated app. And 3 newer hang reports of wine,
# by their name, which take none of the 10.)
DR="$H/Library/Logs/DiagnosticReports"
jsonp() { printf '%s' "$1" | sed 's|/|\\/|g'; }
jsonw() { winf "$1" | sed 's/\\/\\\\/g'; }
ips() {  # <file> <process name> <process path, as in the report> <coalition>
  printf '{"app_name":"%s","timestamp":"2026-11-19 19:22:18.00 +0000","name":"%s","bug_type":"309"}\n{\n  "procName" : "%s",\n  "coalitionName" : "%s",\n  "procPath" : "%s",\n  "usedImages" : [{"path" : "%s"}, {"path" : "%s"}, {"name" : "wine"}],\n  "notes" : ["%s", "%s"]\n}\n' \
    "$2" "$2" "$2" "$4" "$3" "$(jsonp "$H/Library/x.dylib")" "$(jsonp "$HOME/Library/y.dylib")" \
    "Z:$(jsonw "$H")\\\\Library\\\\a" "Z:$(jsonw "$HOME")\\\\Library\\\\b" >"$DR/$1"
}
LOADER="lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine"
ips Gw2-64.exe-2026-11-19-192219.ips Gw2-64.exe "\\/Users\\/USER\\/*\\/wine.app\\/Contents\\/MacOS\\/wine" cz.jandrly.gw2onmac
ips Mach9-2026-11-19-192219.ips Mach9 "$ENG/$LOADER" com.openssh.sshd.0
for n in 0 1 2 3 4 5 6 7 8; do ips "wine-2026-11-18-00000$n.ips" wine "$(jsonp "$ENG/$LOADER")" com.openssh.sshd.0; done
touch -t "$(date -v-2d +%Y%m%d%H%M)" "$DR/wine-2026-11-18-000000.ips"
ips Gw2-64.exe-2026-11-19-192217.ips Gw2-64.exe "\\/Users\\/USER\\/*\\/wine.app\\/Contents\\/MacOS\\/wine" com.example.otherwine
ips wine-2026-11-19-192217.ips wine "$(jsonp "/Applications/Other Wine.app/Contents/MacOS/wine")" com.example.otherwine
ips Safari-2026-11-19-192219.ips Safari "\\/Applications\\/Safari.app\\/Contents\\/MacOS\\/Safari" com.apple.Safari
for n in 1 2 3; do echo "Process: wine [$n]" >"$DR/wine64-preloader_2026-11-19-19222$n.hang"; done
touch -t "$(date -v+1M +%Y%m%d%H%M)" "$DR"/wine64-preloader_*.hang
cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"
# (the heat counters of 4 games in the logs folder, whose name has spaces, each with its server
# requests, older than session.env so the session report leaves them alone, and a profile)
n=0
for pid in 9101 9202 9303 9404; do
  n=$((n + 1))
  echo "heat pid $pid" >"$LOGS/heat-$pid.log"; echo "requests pid $pid" >"$LOGS/heat-requests-$pid.log"
  touch -t "20250101000$n" "$LOGS/heat-$pid.log" "$LOGS/heat-requests-$pid.log"
done
echo "profile" >"$LOGS/heat-prof-9404.log"
mkdir -p "$ARC/logs" && : >"$ARC/logs/$(id -un)-boss.zevtc" && : >"$ARC/logs/$(id -un)_boss.zevtc"
# (arcdps.log also with the game folder as Wine writes it, and the user name)
printf '2026-11-13 13:42:41.000: info: loaded Z:%s\\d3d11.dll for %s\n' "$(winf "$GD")" "$(id -un)" >>"$ARC/arcdps.log"
rm -f "$SANDBOX/vmmap.args"
collect
check "collect-logs makes a zip" [ -f "$zip" ]
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
    eval 'has "$Z/session-report.txt" "^ntdll.so that ran: my Wine build, jdrly/wine ${MYWINE_COMMIT:0:11} (sha256 " && has "$Z/session-report.txt" "^Its switches: WINE_HEAT_WAKE=one,skip WINE_HEAT_EVPOOL=1$"'
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
check "  system-info names my KosmicKrisp in the app (or none) and the one in the engine" \
  eval 'has "$Z/system-info.txt" "^Versions: .* kosmickrisp $(kkb && echo "$MYKK_COMMIT" || echo none) " && has "$Z/system-info.txt" "^  KosmicKrisp libvulkan_kosmickrisp.dylib: [0-9a-f]\{12\}.* (the engine.s own [0-9a-f]\{12\}, this app.s " && grep -q "^kosmickrisp " "$Z/VERSIONS"'
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
# The Metal a session drew with: DXMT_METAL4 on the fork's startup line (0 Metal 3, 1 Metal 4)
printf 'info:  GW2 fork v0.80-492-g1dcb12d: DXMT_STATS=1 DXMT_METAL4=0 cpus=8 refresh=60\ninfo:  STATS fps=60.0 ms=16.7/24.8 cb=1.1 rp=2.0(+0.0 merged) encode=0.02+0.20/7.3\n' >"$SANDBOX/metal3_d3d11.log"
out=$("$APP/Contents/Resources/session-report.sh" "$SANDBOX/metal3_d3d11.log" 2>&1)
check "the session report of a Metal 3 session: Metal 3 in its header, and in place of the Metal 4 line" \
  eval 'echo "$out" | grep -qx "DXMT v0.80-492-g1dcb12d, Metal 3, 8 CPUs seen, display at 60 Hz" && echo "$out" | grep -qx "Metal 3" && ! echo "$out" | grep -q "^Metal 4"'
printf 'info:  GW2 fork v0.80-489-g2483559: DXMT_STATS=1 DXMT_METAL4=1 cpus=8 refresh=60\ninfo:  METAL4 commits=159 buffers=3 allocmb=4.84 slow=0 errors=0 resadds=1124\ninfo:  METAL4 commits=309 buffers=3 allocmb=8.53 slow=0 errors=1 resadds=35987\n' >"$SANDBOX/metal4_d3d11.log"
out=$("$APP/Contents/Resources/session-report.sh" "$SANDBOX/metal4_d3d11.log" 2>&1)
check "  of a Metal 4 session from a fork without present= (before jdrly/dxmt#227): Metal 4 in its header, no present, and its commits and errors" \
  eval 'echo "$out" | grep -qx "DXMT v0.80-489-g2483559, Metal 4, 8 CPUs seen, display at 60 Hz" && echo "$out" | grep -qx "Metal 4: 468 commits, 1 errors"'
# (the present that ran, from the METAL4 lines' present=: DXMT's log ends its lines with CR LF, so
# the field at a line's end carries a CR)
printf 'info:  GW2 fork v0.80-502-gfd2a772: DXMT_STATS=1 DXMT_METAL4=1 cpus=8 refresh=60\r\ninfo:  METAL4 commits=110 buffers=2 errors=0 present=mtl3\r\n' >"$SANDBOX/mtl3_d3d11.log"
printf 'info:  GW2 fork v0.80-503-gb765673: DXMT_STATS=1 DXMT_METAL4=1 cpus=8 refresh=60\r\ninfo:  METAL4 commits=144 buffers=2 errors=0 present=done beforepass=0\r\n' >"$SANDBOX/done_d3d11.log"
printf 'info:  GW2 fork v0.80-502-gfd2a772: DXMT_STATS=1 DXMT_METAL4=1 cpus=8 refresh=60\r\ninfo:  METAL4 commits=178 buffers=2 errors=0 present=mtl4\r\n' >"$SANDBOX/mtl4_d3d11.log"
for k in mtl3 "done" mtl4; do "$APP/Contents/Resources/session-report.sh" "$SANDBOX/${k}_d3d11.log" >"$SANDBOX/${k}_report.txt" 2>&1; done
check "  the present that ran on Metal 4 in the header: through a Metal 3 command buffer, after the pass's commit, or Metal 4's own" \
  eval 'grep -qx "DXMT v0.80-502-gfd2a772, Metal 4 (present through a Metal 3 command buffer), 8 CPUs seen, display at 60 Hz" "$SANDBOX/mtl3_report.txt" && grep -qx "DXMT v0.80-503-gb765673, Metal 4 (the drawable presented once its pass.s commit completed), 8 CPUs seen, display at 60 Hz" "$SANDBOX/done_report.txt" && grep -qx "DXMT v0.80-502-gfd2a772, Metal 4 (Metal 4.s own present), 8 CPUs seen, display at 60 Hz" "$SANDBOX/mtl4_report.txt"'
out=$("$APP/Contents/Resources/session-report.sh" --compare "$SANDBOX/metal3_d3d11.log" "$SANDBOX/metal4_d3d11.log" 2>&1 | awk '$1 == "metal4" { print $2, $3 }')
check "  and --compare prints each one's DXMT_METAL4" [ "$out" = "0 1" ]
out=$("$APP/Contents/Resources/session-report.sh" --compare "$SANDBOX/mtl3_d3d11.log" "$SANDBOX/done_d3d11.log" 2>&1 | awk '$1 == "metal4_present" { print $2, $3 }')
check "  and each one's present" [ "$out" = "mtl3 done" ]
rm -f "$SANDBOX/metal3_d3d11.log" "$SANDBOX/metal4_d3d11.log" "$SANDBOX"/mtl3_* "$SANDBOX"/done_* "$SANDBOX"/mtl4_*
cp "$LOGS/session.env" "$SANDBOX/session.env.keep"
sed -i '' -e 's/^DXMT_TREE=.*/DXMT_TREE=engine/' -e 's/^RULE=exe=Gw2-64.exe;/&gcmouse=false;/' "$LOGS/session.env"
echo "info:  Using feature level D3D_FEATURE_LEVEL_11_1" >"$LOGS/engine-only_d3d11.log"
out=$("$APP/Contents/Resources/session-report.sh" "$LOGS/engine-only_d3d11.log" 2>&1)
check "the session report of the engine's DXMT: says which, and that it writes no STATS lines" \
  eval 'echo "$out" | grep -q "^DXMT that ran: the engine.s own DXMT, athei/dxmt 10e27aed3f5$" && echo "$out" | grep -q "writes no STATS lines"'
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
check "  arcdps.log in game-logs/arcdps, redacted: Z:~\\, no home folder or user name" \
  eval 'has "$Z/game-logs/arcdps/arcdps.log" "info: build" && grep -qF "Z:~\\Library\\" "$Z/game-logs/arcdps/arcdps.log" && no_home "$Z/game-logs/arcdps/arcdps.log"'
check "  addon-files.txt lists d3d11.dll and the files under addons/arcdps with sizes, redacted" \
  eval 'f="$Z/game-logs/addon-files.txt"; grep -qE "^[0-9-]+ [0-9:]+ $(wc -c <"$GD/d3d11.dll" | tr -d " ") d3d11.dll\$" "$f" && grep -qE " addons/arcdps/arcdps_lastcrash.log\$" "$f" && grep -qE " 0 addons/arcdps/logs/USER-boss.zevtc\$" "$f" && grep -qE " 0 addons/arcdps/logs/USER_boss.zevtc\$" "$f" && ! grep -qi "$(id -un)_boss" "$f" && ! grep -q " dxgi.dll\$" "$f" && no_home "$f"'
check "  system-info names the d3d11.dll addon: arcdps" has "$Z/system-info.txt" "d3d11.dll addon: arcdps"
check "  system-info: ReShade off, arcdps in as d3d11.dll" grep -qxF "ReShade: off; arcdps on as d3d11.dll" "$Z/system-info.txt"
check "  the session report: ReShade and arcdps off as the session started, no compiler" \
  eval 'grep -qxF "ReShade at the start: off; arcdps off" "$Z/session-report.txt" && grep -qxF "  d3dcompiler_47.dll next to Gw2-64.exe: none" "$Z/session-report.txt"'
check "  arcdps's crash log, with the game's assertion and the bottle user's folder as USER" \
  eval 'has "$Z/game-logs/arcdps/arcdps_lastcrash.log" "error: intercepted gw2 assertion \"frameId\"" && has "$Z/game-logs/arcdps/arcdps_lastcrash.log" "C:.users.USER.AppData.Local.Temp" && ! has "$Z/game-logs/arcdps/arcdps_lastcrash.log" "users.$BUSER.AppData"'
check "  arcdps.log, the GW2 account name gone" eval '[ -f "$Z/game-logs/arcdps/arcdps.log" ] && ! grep -rq "Arc Acct" "$Z"'
check "  the session report's crash line, from arcdps's crash log" \
  has "$Z/session-report.txt" '^The last session ended in a crash: arcdps intercepted gw2 assertion "frameId", file "D:.Perforce.Live.NAEU.v2.Code.Gw2.Engine.Frame.FrApi.cpp", line 2289 (arcdps_lastcrash.log, 2026-11-13 13:42:39.573)$'
check "  Steam's assert dump byte for byte, the game folder's and the game's AppData folder's" \
  eval 'same "$STEAM/dumps/assert_steam.exe_20261113132231_1.dmp" "$Z/crash-dumps/steam/assert_steam.exe_20261113132231_1.dmp" && same "$GD/Crash.dmp" "$Z/crash-dumps/game/Crash.dmp" && same "$GW2A/Crash.dmp" "$Z/crash-dumps/appdata/Crash.dmp"'
check "  not the older dump, nor a .dmp outside the dump folders or the bottle" \
  eval '[ -z "$(find "$Z" \( -name "assert_gameoverlayui64*" -o -name decoy.dmp -o -name Gw2-64.exe.dmp \))" ]'
check "  the dump over 5 MB left out, and system-info says so" \
  eval '[ ! -e "$Z/crash-dumps/steam/assert_large.dmp" ] && has "$Z/system-info.txt" "^  left out: assert_large.dmp (6000 KB, too large)$"'
for f in userpath persona marker account; do
  check "  the dump with $f left out by the leak check" \
    eval '[ ! -e "$Z/crash-dumps/steam/assert_$f.dmp" ] && has "$Z/left-out.txt" "crash-dumps/steam/assert_$f.dmp"'
done
check "  the game's crash report, by this app's coalition, the home folder ~ (as \\/ and as \\\\)" \
  eval 'f="$Z/crash-reports/Gw2-64.exe-2026-11-19-192219.ips"; grep -qF "\"path\" : \"~\\/Library\\/x.dylib\"" "$f" && grep -qF "\"path\" : \"~\\/Library\\/y.dylib\"" "$f" && grep -qF "\"Z:~\\\\Library\\\\a\", \"Z:~\\\\Library\\\\b\"" "$f" && ! grep -qiF -e "$(jsonp "$H")" -e "$(jsonp "$HOME")" -e "$(jsonw "$H")" -e "$(jsonw "$HOME")" -e "\\/Users\\/$(id -un)\\/" -e "\\\\Users\\\\$(id -un)\\\\" "$f" && no_home "$f"'
check "  by their path in the engine's folder, with / and with \\/: the newest 10 of ours, and system-info names the 11th" \
  eval '[ -f "$Z/crash-reports/Mach9-2026-11-19-192219.ips" ] && grep -qF "\"procPath\" : \"~/Library/Application Support/$APP_FOLDER/engine/" "$Z/crash-reports/Mach9-2026-11-19-192219.ips" && [ -f "$Z/crash-reports/wine-2026-11-18-000008.ips" ] && [ ! -e "$Z/crash-reports/wine-2026-11-18-000000.ips" ] && [ "$(ls "$Z/crash-reports" | grep -c "\.ips$")" = 10 ] && has "$Z/system-info.txt" "^  left out: wine-2026-11-18-000000.ips (more than 10 of the game, Steam and Wine)$"'
check "  not another Wine's game or wine with the same names, nor an unrelated app, and system-info doesn't name them" \
  eval '[ ! -e "$Z/crash-reports/Gw2-64.exe-2026-11-19-192217.ips" ] && [ ! -e "$Z/crash-reports/wine-2026-11-19-192217.ips" ] && [ ! -e "$Z/crash-reports/Safari-2026-11-19-192219.ips" ] && ! grep -qE "192217|Safari" "$Z/system-info.txt"'
check "  the hang reports of wine by their name, which take none of the 10" \
  eval '[ "$(ls "$Z/crash-reports" | grep -c "^wine64-preloader_.*\.hang$")" = 3 ]'
# (the crash line from session-report.sh itself: a hardware exception with its code, a crash log
# without an intercepted line, and one from before the session)
SR="$APP/Contents/Resources/session-report.sh"
cp "$ARC/arcdps_lastcrash.log" "$SANDBOX/lastcrash.keep"
printf '2026-11-13 13:42:39.573: error: intercepted crash from hardware exception in "Gw2-64.exe"\r\n\t---- exception ----\r\n\tcode: 0x00000000C0000005\r\n' >"$ARC/arcdps_lastcrash.log"
"$SR" >"$SANDBOX/report.txt" 2>&1
check "the session report's crash line for an exception: arcdps's line and the exception's code" \
  has "$SANDBOX/report.txt" '^The last session ended in a crash: arcdps intercepted crash from hardware exception in "Gw2-64.exe", code 0x00000000C0000005 (arcdps_lastcrash.log, 2026-11-13 13:42:39.573)$'
echo "arcdps" >"$ARC/arcdps_lastcrash.log"
"$SR" >"$SANDBOX/report.txt" 2>&1
check "  a crash log without such a line: the crash, and that" \
  has "$SANDBOX/report.txt" '^The last session ended in a crash: arcdps wrote arcdps_lastcrash.log at .*, with no assertion or exception line$'
touch -t 202501010000 "$ARC/arcdps_lastcrash.log"
"$SR" >"$SANDBOX/report.txt" 2>&1
check "  a crash log from before the session: no crash line" eval '[ -s "$SANDBOX/report.txt" ] && ! has "$SANDBOX/report.txt" "^The last session ended in a crash"'
mv -f "$SANDBOX/lastcrash.keep" "$ARC/arcdps_lastcrash.log"; rm -f "$SANDBOX/report.txt"
# A release build's Collect Logs (its Resources with an app.properties without channel=dev) takes
# them too; arcdps.log from 2025 stays out
RELC="$SANDBOX/res-collect"
mkdir -p "$RELC" "$SANDBOX/zip-release"
for f in "$APP/Contents/Resources"/*; do ln -s "$f" "$RELC/${f##*/}"; done
rm -f "$RELC/app.properties" && grep -v '^channel=' "$APP/Contents/Resources/app.properties" >"$RELC/app.properties"
touch -t 202501010000 "$ARC/arcdps.log"
zip=$("$RELC/collect-logs.sh" "$SANDBOX/zip-release" 2>>"$SANDBOX/collect.err" | tail -1)
rm -rf "$SANDBOX/unzipped-release" && mkdir -p "$SANDBOX/unzipped-release" && (cd "$SANDBOX/unzipped-release" && unzip -q "$zip")
Z="$SANDBOX/unzipped-release/$(basename "$zip" .zip)"
check "a release build's Collect Logs: arcdps's crash log, the crash line and the dumps; not the older arcdps.log" \
  eval '[ -f "$Z/game-logs/arcdps/arcdps_lastcrash.log" ] && [ ! -e "$Z/game-logs/arcdps/arcdps.log" ] && has "$Z/session-report.txt" "^The last session ended in a crash: arcdps intercepted gw2 assertion" && [ -f "$Z/crash-dumps/steam/assert_steam.exe_20261113132231_1.dmp" ] && [ -f "$Z/crash-dumps/game/Crash.dmp" ]'
# A game folder whose path goes through a link out of the bottle (as a Steam library on another
# drive does): neither its dumps nor arcdps's logs are read, and the report has no crash line
cp "$AD/state" "$SANDBOX/state.keep"
mkdir -p "$SANDBOX/outside/Guild Wars 2/addons/arcdps" && ln -s "$SANDBOX/outside" "$BOTTLE/drive_c/library"
cp "$ARC/arcdps_lastcrash.log" "$SANDBOX/outside/Guild Wars 2/addons/arcdps/" && printf 'MDMP\0outside\0' >"$SANDBOX/outside/Guild Wars 2/Crash.dmp"
sed -i '' "s|^game_dir=.*|game_dir=$BOTTLE/drive_c/library/Guild Wars 2|" "$AD/state"
zip=$("$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip-outside" 2>>"$SANDBOX/collect.err" | tail -1)
rm -rf "$SANDBOX/unzipped-outside" && mkdir -p "$SANDBOX/unzipped-outside" && (cd "$SANDBOX/unzipped-outside" && unzip -q "$zip")
Z="$SANDBOX/unzipped-outside/$(basename "$zip" .zip)"
check "a game folder through a link out of the bottle: none of its dumps or arcdps's logs, no crash line" \
  eval '[ ! -e "$Z/crash-dumps/game" ] && [ ! -e "$Z/game-logs/arcdps" ] && [ -f "$Z/session-report.txt" ] && ! has "$Z/session-report.txt" "ended in a crash"'
mv -f "$SANDBOX/state.keep" "$AD/state"
mv -f "$SANDBOX/loginusers.keep" "$STEAM/config/loginusers.vdf"
rm -rf "$GD/addons" "$GD/d3d11.dll" "$AD/compatdb.local" "$STEAM/dumps" "$GD/Crash.dmp" "$GW2A/Crash.dmp" "$RELC" \
  "$BOTTLE/drive_c/library" "$SANDBOX/outside" \
  "$H/decoy.dmp" "$BOTTLE/drive_c/decoy.dmp" "$H/Library/Logs/DiagnosticReports/Gw2-64.exe.dmp" \
  "$DR"/*.ips "$DR"/*.hang
collect
check "no ReShade folder and nothing in the game folder: Collect Logs works and says ReShade is off" \
  eval '[ ! -e "$AD/ReShade" ] && [ -f "$Z/system-info.txt" ] && grep -qxF "ReShade: off; arcdps off" "$Z/system-info.txt" && grep -qxF "  ReShade folder: none" "$Z/system-info.txt" && [ ! -e "$Z/reshade" ] && [ ! -e "$Z/game-logs/addon-files.txt" ]'

fi

if in_group sessions; then
# (alone, this group starts from an install of its own: the sections before it didn't run)
[ "$GROUP" = all ] || fixture_install || { bad "the fixture's install (fixture_install), which the rest of this group needs"; finish; exit 1; }
section "Steam in the background after the first login"
LU="$STEAM/config/loginusers.vdf"
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
: >"$STANDIN_LOG"; GW2_ON_MAC_WATCH_GRACE=0 g play >/dev/null 2>&1; started
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
  : >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
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
  : >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
  check "  once it has ended, the next Play puts the engine's own in before Wine starts" \
    eval 'winemac_is engine && has "$LOGS/session.env" "^LIB_macdrv=winemac.so engine $ENGINE_WINE "'
  watch_done
  g set macdrv mine >/dev/null
else
  skipdrv "set macdrv engine while a session runs"
fi
# An update from 0.2.0 while Steam still runs with the engine's own KosmicKrisp (it crashes the game
# on macOS 26, #339): Play refuses and starts no Wine; once Steam has quit, Play puts mine in
if kkb; then
  mv -f "$KKF.engine" "$KKF"
  mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
  "$ENG/bin/wineserver" 60 & sp=$!
  sleep 0.3
  : >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1) && rc=0 || rc=$?
  check "Play while Steam runs with the engine's own KosmicKrisp: refused, no Wine started" \
    eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error Steam is still running with the engine'"'"'s own KosmicKrisp, which crashes the game on macOS 26. Quit Steam, then click Play again to put mine in." && ! has "$STANDIN_LOG" "^wine " && kk_is engine && [ "$(st kosmickrisp_ready)" = switch ]'
  kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
  mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
  : >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1) && rc=0 || rc=$?; started
  check "  once it has ended, the next Play puts mine in before Wine starts" \
    eval '[ "$rc" = 0 ] && has "$STANDIN_LOG" "^wine " && kk_is mine && has "$LOGS/session.env" "^LIB_kosmickrisp=mine $MYKK_COMMIT "'
  watch_done
fi
# A mix of my Mac driver's two files and the engine's own (a switch cut short): Play refuses it
# while Steam runs, finishes the switch once Steam has quit, and refuses one it can't finish
if drv; then
  W32U0=$W32U
  cp "$COMP/macdrv/VERSION" "$SANDBOX/macdrv-VERSION.w32"
  if [ "$W32U" = engine ]; then
    echo "my win32u.so" >"$COMP/macdrv/win32u.so"
    echo "win32u.so: sha256 $(shasum -a 256 "$COMP/macdrv/win32u.so" | cut -d' ' -f1)" >>"$COMP/macdrv/VERSION"
  fi
  cp "$COMP/macdrv/win32u.so" "$SANDBOX/win32u.keep"
  W32U=mine
  g set macdrv mine >/dev/null
  # (the way back to the engine's own, cut after its first rename: the engine's winemac.so, my
  # win32u.so)
  sed -i '' 's/^macdrv=.*/macdrv=engine/' "$AD/settings.conf"
  mv -f "$NT/winemac.so.engine" "$NT/winemac.so"
  mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
  "$ENG/bin/wineserver" 60 & sp=$!
  sleep 0.3
  : >"$STANDIN_LOG"; out=$(g play 2>&1) && rc=0 || rc=$?
  check "a mix of my Mac driver's two files while Steam runs: Play refuses, saying how to finish it, and starts nothing" \
    eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The engine'"'"'s winemac.so and win32u.so are a mix of mine and its own, a switch cut short. Quit Steam and click Play again to finish it." && ! has "$STANDIN_LOG" "^wine " && win32u_is mine'
  kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
  mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
  : >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
  check "  once Steam has quit, Play finishes the switch to the engine's own pair before Wine starts" \
    eval 'winemac_is engine && win32u_is engine && has "$LOGS/session.env" "^LIB_win32u=win32u.so engine $GW2_ON_MAC_ENGINE_WIN32U_SHA256$" && has "$STANDIN_LOG" "^wine "'
  watch_done
  # An earlier version of the app cut short between its pair's renames: its winemac.so next to the
  # engine's own win32u.so, which nothing can tell from an earlier build without win32u.so. While
  # Steam runs, Play refuses it; once Steam has quit, Play puts this build's pair in
  sed -i '' 's/^macdrv=.*/macdrv=mine/' "$AD/settings.conf"
  mv "$NT/winemac.so" "$NT/winemac.so.engine" && echo "an earlier build of mine" >"$NT/winemac.so"
  mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
  "$ENG/bin/wineserver" 60 & sp=$!
  sleep 0.3
  : >"$STANDIN_LOG"; out=$(g play 2>&1) && rc=0 || rc=$?
  check "an earlier build's winemac.so next to the engine's own win32u.so while Steam runs: macdrv_file=other, Play refuses and starts nothing" \
    eval '[ "$(st macdrv_file macdrv_ready)" = other/switch ] && [ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The engine'"'"'s winemac.so is another build of mine, and nothing proves its win32u.so is that build'"'"'s. Quit Steam and click Play again to put this build'"'"'s in." && ! has "$STANDIN_LOG" "^wine "'
  kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
  mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
  : >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
  check "  once Steam has quit, Play puts this build's pair in before Wine starts" \
    eval 'winemac_is mine && win32u_is mine && has "$STANDIN_LOG" "^wine "'
  watch_done
  g set macdrv engine >/dev/null
  # one it can't finish: my win32u.so over the engine's own, which is nowhere else
  cp "$COMP/macdrv/win32u.so" "$NT/win32u.so"
  : >"$STANDIN_LOG"; out=$(g play 2>&1) && rc=0 || rc=$?
  check "my win32u.so next to the engine's own winemac.so, the engine's win32u.so gone: macdrv_ready=other, Play refuses and starts nothing" \
    eval '[ "$(st macdrv_ready macdrv_file)" = other/mix ] && [ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The engine'"'"'s winemac.so and win32u.so are a mix of mine and its own. Click Repair." && ! has "$STANDIN_LOG" "^wine "'
  out=$(g repair 2>&1) && rc=0 || rc=$?
  check "  repair unpacks the engine again and puts the engine's own pair in, as macdrv=engine asks" \
    eval '[ "$rc" = 0 ] && echo "$out" | grep -q "unpacking the engine again" && winemac_is engine && win32u_is engine && [ "$(st macdrv_ready)" = yes ]'
  watch_done
  cp "$SANDBOX/macdrv-VERSION.w32" "$COMP/macdrv/VERSION"
  W32U=$W32U0
  [ "$W32U" = mine ] || rm -f "$COMP/macdrv/win32u.so"
  g set macdrv mine >/dev/null
else
  skipdrv "a mix of my Mac driver's two files, which Play refuses or finishes"
fi
if fexb; then
  mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
  "$ENG/bin/wineserver" 60 & sp=$!
  sleep 0.3
  check "set fex mine while a session runs: saved, and the engine's own FEX stays (the session's processes have it loaded)" \
    eval '"$G" set fex mine | grep -q "after Steam has quit" && [ "$(sett fex)" = mine ] && fex_is engine && [ "$(st fex_ready)" = switch ]'
  kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
  mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
  : >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
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
    eval '[ "$(st fex_ready fex_file)" = other/mix ] && [ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The engine'"'"'s FEX files are a mix of mine and its own. Click Repair." && ! has "$STANDIN_LOG" "^wine "'
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
check "busy=game with a Gw2-64.exe of the engine running, game_pid its pid" eval '[ "$(st busy game_pid)" = "game/$gp" ]'
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
  eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error Guild Wars 2 is running in another app. Quit it first." && [ ! -s "$STANDIN_LOG" ] && [ "$(st busy game_pid)" = none/ ]'
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
# a session: the game starts, runs, quits (it is ended even when the watcher doesn't see it)
game_session() { local r=0; game_up; wait_stage playing || r=1; game_down; [ $r = 0 ] && wait_stage grace; }
# Play, then (up to 2 s) its watcher has written its pid
watcher_up() { local i=0; until watcher_runs || [ $i -ge 20 ]; do sleep 0.1; i=$((i + 1)); done; }
splay() { : >"$STANDIN_LOG"; g play >/dev/null 2>&1; started; watcher_up; }
sessions_reset
check "the Steam in the background is on, with a remembered login" [ "$(sett steambg steam_login quitsteam)" = on/yes/on ]

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
sessions_reset
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
check "  status meanwhile: game=no (not fully installed), stage=finished, busy=steam, session=live (the window's model keeps the session)" eval '[ "$(st game stage busy session)" = no/finished/steam/live ]'
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
# (its sleep first: a TERM ends the stand-in's bash, not the sleep it waits on)
pkill -P $wp; kill $wp 2>/dev/null; wait $wp 2>/dev/null
check "a dead watcher's unfinished session is over: Steam on its own is stage=none" eval '[ "$(ss stage)/$(ss closing)/$(ss quit_steam)/$(ss watching)" = none/no/no/no ]'
check "  status: session=none (busy=steam)" [ "$(st session busy)" = none/steam ]
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
g set vsync off >/dev/null
check "  and the Vsync row off: no (the steady 60 is my DXMT fork's display sync)" [ "$(ss limiter_hint)" = no ]
g set vsync on >/dev/null
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
sessions_reset
T="$ENG/lib/wine/dxgi/dxmt"
echo "something else" >"$T/aarch64-windows/d3d11.dll"
check "another build of my DXMT in the engine (an earlier version's): graphics=switch" [ "$(st graphics dxmt_tree)" = switch/oldfork ]
: >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
check "  Play puts this version's in before Wine starts, and says so" eval 'dxgi_is fork && echo "$out" | grep -q "^DXMT: my DXMT fork" && has "$LOGS/session.env" "^DXMT_TREE=fork$"'
watch_done
rm "$T/.gw2om-dxmt"; echo "something else" >"$T/aarch64-windows/d3d11.dll"
check "graphics=other: a DXMT tree that is neither the engine's own nor mine" [ "$(st graphics)" = other ]
: >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
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
check "wine_ready=other: an ntdll.so that is neither the engine's own nor mine, and none next to it" [ "$(st wine_ready wine_file)" = other/other ]
: >"$STANDIN_LOG"; out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
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
check "  and says which ntdll.so, winemac.so and FEX are in the engine" has <(echo "$out") "^@done Repaired: .*, with $([ "$MYWINE" = mine ] && echo "my ntdll.so (jdrly/wine ${MYWINE_COMMIT:0:11})" || echo "the engine's own ntdll.so (athei/wine $ENGINE_WINE)"), with $(drv && echo "my $DRVNAME (jdrly/wine ${MYDRV_COMMIT:0:11})" || echo "the engine's own $DRVNAME (athei/wine $ENGINE_WINE)"), and runs on the engine's own FEX (athei/FEX $ENGINE_FEX)\.$"
check "  wine.app untouched" [ "$(wineapp_sums "$ENG")" = "$(wineapp_sums "$S")" ]
# A winemac.so that is neither the engine's own nor mine, and no engine's own next to it
echo "something else" >"$NT/winemac.so" && rm -f "$NT/winemac.so.engine"
check "macdrv_ready=other: a winemac.so that is neither the engine's own nor mine, and none next to it (a mix next to my win32u.so)" \
  [ "$(st macdrv_ready macdrv_file)" = "other/$([ $W32U = mine ] && echo mix || echo other)" ]
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
out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
check "an earlier version's manifest: Play brings it to this version" [ "$(plutil -extract version raw -o - "$MF")" = "$(st version)" ]
check "  the manifest names the engine's build" eval '[ "$(plutil -extract engine raw -o - "$MF")/$(plutil -extract engine_dxmt raw -o - "$MF")" = mach9-v0.4.0/10e27aed3f5 ]'
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
  eval '[ "$(st graphics)" = yes ] && [ "$(engine_diff)" = "$SDK_DIFF" ] && dxgi_is fork && ntdll_is $MYWINE && winemac_is $MYDRV && win32u_is $W32U && fex_is engine && kk_is $(kkb && echo mine || echo engine)'
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
# An engine of another release, as an earlier version of the app left it (docs/adr/0016): its
# record of the archive is Mach9 0.3.1's. It counts as installed, and Play refuses, naming Repair.
# Repair replaces it, but not while the old engine's Wine runs, and a failed download keeps it.
OLD_SHA=90aff9a897ed0ff9aac44d0e06f0aecd3ee985afb38037f3f915451e51fa974e
echo "$OLD_SHA" >"$ENG/.gw2om-source"
check "Mach9 0.3.1's engine in place: installed=yes, engine_installed=old" [ "$(st installed engine_installed)" = yes/old ]
: >"$STANDIN_LOG"; out=$(g play 2>&1) && rc=0 || rc=$?
check "  Play refuses, naming both engines and Repair, and starts no Wine" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -qxF "@error The engine here is Mach9 0.3.1 · Wine 11.21, and this version of $APP_NAME runs on Mach9 0.4.0 · Wine 11.21. Click Repair to put it in place." && ! grep -q "^wine " "$STANDIN_LOG"'
mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
"$ENG/bin/wineserver" 60 & sp=$!
sleep 0.3
out=$(g repair 2>&1) && rc=0 || rc=$?
check "  repair while the old engine's Wine runs: refused, the old engine kept" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -q "^@error " && [ "$(cat "$ENG/.gw2om-source")" = "$OLD_SHA" ] && [ "$(st engine_installed)" = old ]'
kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
out=$(GW2_ON_MAC_ENGINE_URL="file://$SANDBOX/missing.tar.xz" g repair 2>&1) && rc=0 || rc=$?
check "  repair with a failed download: the old engine kept, and the error says so" \
  eval '[ "$rc" != 0 ] && echo "$out" | grep -q "^@error The download of the Wine engine.* The engine here, Mach9 0.3.1 · Wine 11.21, stays in place. Click Repair to try again.$" && [ "$(cat "$ENG/.gw2om-source")" = "$OLD_SHA" ] && [ -x "$ENG/bin/wine" ] && [ ! -e "$ENG.new" ]'
out=$(g repair 2>&1) && rc=0 || rc=$?
check "  repair once nothing runs: this app's engine replaces it, with my files in it, saying so" \
  eval '[ "$rc" = 0 ] && echo "$out" | grep -qxF "The engine here is Mach9 0.3.1 · Wine 11.21; Mach9 0.4.0 · Wine 11.21 replaces it" && [ "$(st installed engine_installed)" = yes/yes ] && [ "$(engine_diff)" = "$SDK_DIFF" ] && dxgi_is fork && ntdll_is $MYWINE && winemac_is $MYDRV'
mkdir "$AD/.lock"
check "a second operation is refused while one runs (lock)" sh -c "'$G' repair 2>&1 | grep -q 'Another $APP_NAME'"
rmdir "$AD/.lock"
GW2_ON_MAC_ENGINE_CHECKS=1 "$G" play >"$SANDBOX/realwine.txt" 2>&1 || true
check "the real engine's Wine never runs in a sandbox" has "$SANDBOX/realwine.txt" "Refusing to run the real Wine"

section "ReShade (Settings › Interface)"
# Stand-ins from a local URL: reshade.me's installer (a PE's bytes with a zip appended, as the real
# one is), Microsoft's compiler, and the two effect packs as GitHub zips them (a top folder with
# Shaders, Textures and other files); ReShade64.dll and a ReShade the app didn't place come from
# the shared part (pe/)
RSV="$SANDBOX/reshade.me" PK="$SANDBOX/packs" RSF="$AD/ReShade"
mkdir -p "$RSV/in" "$PK"
make_pe "$RSV/d3dcompiler_47.dll" D3DCompile D3DReflect && printf 'fxc2 (stand-in)\n' >>"$RSV/d3dcompiler_47.dll"
make_pe "$SANDBOX/pe/cef-compiler.dll" D3DCompile D3DCompile2 D3DReflect && printf 'bin64/cef (stand-in)\n' >>"$SANDBOX/pe/cef-compiler.dll"
cp "$SANDBOX/pe/ReShade64.dll" "$RSV/in/" && echo "32-bit" >"$RSV/in/ReShade32.dll"
( cd "$RSV/in" && zip -q ../setup.zip ReShade64.dll ReShade32.dll && zip -q ../no64.zip ReShade32.dll )
{ printf 'MZ stand-in .NET installer\n'; cat "$RSV/setup.zip"; } >"$RSV/ReShade_Setup_6.8.0.exe"
{ printf 'MZ stand-in .NET installer\n'; cat "$RSV/no64.zip"; } >"$RSV/no64.exe"
echo '<html><body>Sign in to the Wi-Fi</body></html>' >"$RSV/portal.exe"
S1="$PK/reshade-shaders-fd00" S2="$PK/SweetFX-93dd"
mkdir -p "$S1/Shaders" "$S1/Textures" "$S2/Shaders/SweetFX" "$S2/Textures/SweetFX"
echo '// ReShade.fxh' >"$S1/Shaders/ReShade.fxh"; echo '// Deband' >"$S1/Shaders/Deband.fx"; echo 'notes' >"$S1/Shaders/notes.txt"
echo 'readme' >"$S1/README.md"; echo 'PNG' >"$S1/Textures/FontAtlas.png"
echo '// CAS' >"$S2/Shaders/SweetFX/CAS.fx"; echo '// SMAA' >"$S2/Shaders/SweetFX/SMAA.fxh"; echo 'PNG' >"$S2/Textures/SweetFX/AreaTex.png"; echo 'MIT' >"$S2/LICENSE"
( cd "$PK" && zip -qr "$RSV/standard.zip" reshade-shaders-fd00 && zip -qr "$RSV/sweetfx.zip" SweetFX-93dd )
# a pack whose file climbs out of its folder (the name patched in place: the same length), and one
# with a link in it
mkdir -p "$PK/bad/Shaders/aa/aa" && echo '// evil' >"$PK/bad/Shaders/aa/aa/evil.fx" && echo '// ok' >"$PK/bad/Shaders/ok.fx"
( cd "$PK" && zip -qr "$RSV/dotdot.zip" bad ) && perl -0777 -pi -e 's{Shaders/aa/aa/evil}{Shaders/../../evil}g' "$RSV/dotdot.zip"
mkdir -p "$PK/linked/Shaders" && ln -s /etc/hosts "$PK/linked/Shaders/hosts.fx" && echo '// ok' >"$PK/linked/Shaders/ok.fx"
( cd "$PK" && zip -qry "$RSV/link.zip" linked )
sz() { stat -f %z "$1"; }
sum() { shasum -a 256 "$1" | cut -d' ' -f1; }
export GW2_ON_MAC_RESHADE_URL="file://$RSV/ReShade_Setup_6.8.0.exe"
GW2_ON_MAC_RESHADE_SIZE=$(sz "$RSV/ReShade_Setup_6.8.0.exe") GW2_ON_MAC_RESHADE_SHA256=$(sum "$RSV/ReShade_Setup_6.8.0.exe")
GW2_ON_MAC_RESHADE_DLL_SHA256=$(sum "$SANDBOX/pe/ReShade64.dll")
export GW2_ON_MAC_RESHADE_SIZE GW2_ON_MAC_RESHADE_SHA256 GW2_ON_MAC_RESHADE_DLL_SHA256
export GW2_ON_MAC_COMPILER_URL="file://$RSV/d3dcompiler_47.dll"
GW2_ON_MAC_COMPILER_SIZE=$(sz "$RSV/d3dcompiler_47.dll") GW2_ON_MAC_COMPILER_SHA256=$(sum "$RSV/d3dcompiler_47.dll")
export GW2_ON_MAC_COMPILER_SIZE GW2_ON_MAC_COMPILER_SHA256
export GW2_ON_MAC_RESHADE_SHADERS_URL="file://$RSV/standard.zip" GW2_ON_MAC_SWEETFX_URL="file://$RSV/sweetfx.zip"
WIN_RSF="Z:$(printf %s "$RSF" | tr / '\\')"
RS_INI_WANT=$(printf '%s\n' '[GENERAL]' 'EffectSearchPaths=.\Shaders\**' 'TextureSearchPaths=.\Textures\**' \
  'PresetPath=.\Presets\ReShadePreset.ini' "IntermediateCachePath=Z:$(printf %s "$CACHE/reshade" | tr / '\\')" '' \
  '[INPUT]' 'KeyOverlay=36,0,0,0' '' '[SCREENSHOT]' 'SavePath=.\Screenshots')
rsst() { g status | sed -n "s/^reshade_state=//p"; }
gdsnap() { (cd "$GD" && find . -maxdepth 1 -type f -exec shasum {} + | sort); }
our_ini() { [ "$(cat "$GD/ReShade.ini" 2>/dev/null)" = "$(printf '[INSTALL]\nBasePath=%s' "$WIN_RSF")" ]; }
# refused <words> [<VAR=value>...]: set reshade on with those is refused, says so, and the game
# folder is as it was, with no ReShade folder
refused() {
  local want=$1; shift
  env "$@" "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 && return 1
  grep -q "^@error .*$want" "$SANDBOX/rs.txt" && [ "$(gdsnap)" = "$before" ] && [ ! -e "$RSF" ]
}
rm -f "$GD/d3d11.dll" "$GD/dxgi.dll"; rm -rf "$GD/addons"
check "ReShade off by default: reshade=off, reshade_state=off, version 6.8.0, the folder named" eval 'SET_OUT=$(g settings); [ "$(st reshade reshade_state reshade_version)/$(kv "$SET_OUT" reshade)" = off/off/6.8.0/off ] && [ "$(kv "$SET_OUT" reshade_folder)" = "$RSF" ]'
# what's in the way (arcdps only in the exclusive layout: "arcdps and ReShade together" below)
cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"
check "arcdps as d3d11.dll, the exclusive layout: reshade_state=blocked, reshade_blocker=d3d11.dll" eval '[ "$(GW2_ON_MAC_ADDONS_LAYOUT=exclusive g status | sed -n "s/^reshade_state=//p; s/^reshade_blocker=//p" | tr "\n" /)" = blocked/d3d11.dll/ ]'
before=$(gdsnap)
check "  set reshade on refused: turn arcdps off first; nothing placed" refused "arcdps is in the game folder as d3d11.dll. Turn arcdps off first" GW2_ON_MAC_ADDONS_LAYOUT=exclusive
check "  the together layout: reshade_state=off, no blocker" [ "$(st reshade_state reshade_blocker)" = off/ ]
cp "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"; before=$(gdsnap)
check "another addon's d3d11.dll: blocked, refused, left alone" eval '[ "$(rsst)" = blocked ] && refused "another d3d11.dll (Nexus or another addon?)" && same "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"'
rm -f "$GD/d3d11.dll"
# failed downloads and checks
before=$(gdsnap)
check "no server: refused (check the connection), nothing placed" refused "Check your internet connection" GW2_ON_MAC_RESHADE_URL="file://$SANDBOX/nowhere/ReShade_Setup_6.8.0.exe"
check "a web page instead of the installer: refused, saying so, nothing kept" eval 'refused "brought a web page instead of the file" GW2_ON_MAC_RESHADE_URL="file://$RSV/portal.exe" && [ ! -e "$CACHE/downloads/reshade/portal.exe" ]'
check "an installer that isn't the pinned one (its sha256): refused" refused "is not the file GW2 on Mac expects" GW2_ON_MAC_RESHADE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
check "an installer whose zip has no ReShade64.dll: refused" refused "has no ReShade64.dll in it" GW2_ON_MAC_RESHADE_URL="file://$RSV/no64.exe" GW2_ON_MAC_RESHADE_SIZE="$(sz "$RSV/no64.exe")" GW2_ON_MAC_RESHADE_SHA256="$(sum "$RSV/no64.exe")"
check "a ReShade64.dll that isn't the pinned one: refused, not kept" eval 'refused "is not the ReShade 6.8.0 GW2 on Mac expects" GW2_ON_MAC_RESHADE_DLL_SHA256=0000000000000000000000000000000000000000000000000000000000000000 && [ ! -e "$CACHE/downloads/reshade/ReShade64.dll" ]'
check "a compiler download that isn't the pinned file: refused" refused "The download of Microsoft.s shader compiler is not the file" GW2_ON_MAC_COMPILER_SIZE=1
check "a pack with a file whose path climbs out (..): refused, nothing written outside" eval 'refused "SweetFX has a file whose path leaves its folder" GW2_ON_MAC_SWEETFX_URL="file://$RSV/dotdot.zip" && [ -z "$(find "$SANDBOX" -name evil.fx -not -path "$PK/*")" ]'
check "a pack with a link in it: refused" refused "SweetFX has a link in it" GW2_ON_MAC_SWEETFX_URL="file://$RSV/link.zip"
check "a pack over the unpacked size limit: refused" refused "Standard unpacks to more than" GW2_ON_MAC_PACK_LIMIT=10
check "a pack download that is a web page: refused" refused "The download of SweetFX brought a web page" GW2_ON_MAC_SWEETFX_URL="file://$RSV/portal.exe"
# on: everything downloaded (the game has no bin64/cef copy, so the compiler too)
rm -rf "$CACHE/downloads/reshade" "$GD/bin64"
out=$(g set reshade on 2>&1) && rc=0 || rc=$?
check "set reshade on: exits 0 and says so" eval '[ "$rc" = 0 ] && echo "$out" | grep -q "^@done ReShade 6.8.0 is in the game folder as d3d11.dll"'
check "  with progress for ReShade, the compiler (no bin64/cef copy) and both packs" eval 'for l in "ReShade" "Microsoft.s shader compiler" "ReShade.s standard effects" "SweetFX"; do echo "$out" | grep -q "^@progress $l [0-9]" || exit 1; done'
check "  the game folder: ReShade64.dll as d3d11.dll, fxc2's compiler, ReShade.ini with BasePath" eval 'same "$SANDBOX/pe/ReShade64.dll" "$GD/d3d11.dll" && same "$RSV/d3dcompiler_47.dll" "$GD/d3dcompiler_47.dll" && our_ini'
check "  the ReShade folder: Presets, Shaders, Textures, Screenshots and the starting ReShade.ini" eval '[ -d "$RSF/Presets" ] && [ -d "$RSF/Screenshots" ] && [ "$(cat "$RSF/ReShade.ini")" = "$RS_INI_WANT" ]'
check "  both packs: each Shaders and Textures folder's contents under the pack's name" eval 'same "$S1/Shaders/ReShade.fxh" "$RSF/Shaders/Standard/ReShade.fxh" && [ -f "$RSF/Shaders/Standard/Deband.fx" ] && [ -f "$RSF/Textures/Standard/FontAtlas.png" ] && [ -f "$RSF/Shaders/SweetFX/SweetFX/CAS.fx" ] && [ -f "$RSF/Shaders/SweetFX/SweetFX/SMAA.fxh" ] && [ -f "$RSF/Textures/SweetFX/SweetFX/AreaTex.png" ]'
check "  only effects and images: no README, LICENSE or notes.txt" eval '[ -z "$(find "$RSF" -name README.md -o -name LICENSE -o -name notes.txt)" ]'
check "  reshade=on, reshade_state=on, reshade_dll=d3d11.dll, no blocker" eval '[ "$(sett reshade)/$(st reshade_state reshade_dll reshade_blocker)" = on/on/d3d11.dll/ ] && grep -qx reshade=on "$AD/settings.conf"'
check "  d3dcompiler_47=native,builtin for Gw2-64.exe" compiler_rule on
check "  ReShade alone: rundll32.exe gets d3d11 and dxgi native,builtin" rundll on
check "  the checked ReShade64.dll and the compiler stay in the cache; no installer, zip or temporary file" eval 'same "$SANDBOX/pe/ReShade64.dll" "$CACHE/downloads/reshade/ReShade64.dll" && [ "$(ls -A "$CACHE/downloads/reshade" | LC_ALL=C sort | tr "\n" " ")" = "ReShade64.dll d3dcompiler_47.dll " ] && ! ls -a "$GD" | grep -q gw2om-new || { ls -lA "$CACHE/downloads/reshade" "$GD"; false; }'
check "  ReShade's effect cache folder is there" [ -d "$CACHE/reshade" ]
check "set reshade on again: already there" sh -c "'$G' set reshade on | grep -q 'already in the game folder (d3d11.dll)'"
echo "the player's preset" >"$RSF/Presets/Mine.ini"
out=$(g set reshade off 2>&1) && rc=0 || rc=$?
check "set reshade off: d3d11.dll, the compiler the app placed and ReShade.ini out of the game folder" eval '[ "$rc" = 0 ] && [ ! -e "$GD/d3d11.dll" ] && [ ! -e "$GD/d3dcompiler_47.dll" ] && [ ! -e "$GD/ReShade.ini" ]'
check "  the ReShade folder stays, and the @done line says where" eval 'has "$RSF/Presets/Mine.ini" preset && [ -f "$RSF/Shaders/Standard/ReShade.fxh" ] && echo "$out" | grep -qxF "@done ReShade is off: its d3d11.dll is out of the game folder. Your presets and shaders stay in $RSF."'
check "  reshade=off, reshade_state=off, the override deleted" eval '[ "$(sett reshade)/$(rsst)" = off/off ] && compiler_rule off'
check "  rundll32.exe's d3d11 and dxgi deleted" rundll off
# the game's own compiler (bin64/cef); the packs aren't downloaded again (Shaders has ReShade.fxh,
# and On brought SweetFX once)
mkdir -p "$GD/bin64/cef" && cp "$SANDBOX/pe/cef-compiler.dll" "$GD/bin64/cef/d3dcompiler_47.dll"
rm -f "$CACHE/downloads/reshade/d3dcompiler_47.dll"
out=$(GW2_ON_MAC_COMPILER_URL="file://$SANDBOX/nowhere/c.dll" GW2_ON_MAC_RESHADE_SHADERS_URL="file://$SANDBOX/nowhere/s.zip" GW2_ON_MAC_SWEETFX_URL="file://$SANDBOX/nowhere/f.zip" "$G" set reshade on 2>&1) && rc=0 || rc=$?
check "with the game's bin64/cef compiler: on, that copy next to Gw2-64.exe, nothing downloaded" eval '[ "$rc" = 0 ] && same "$GD/bin64/cef/d3dcompiler_47.dll" "$GD/d3dcompiler_47.dll" && ! echo "$out" | grep -q "^@progress"'
g set reshade off >/dev/null 2>&1
check "  off removes that copy; the game's own in bin64/cef stays" eval '[ ! -e "$GD/d3dcompiler_47.dll" ] && same "$SANDBOX/pe/cef-compiler.dll" "$GD/bin64/cef/d3dcompiler_47.dll"'
# the player's own compiler, with no other copy anywhere (no bin64/cef, none cached, no server)
echo "the player's compiler" >"$GD/d3dcompiler_47.dll"
mv "$GD/bin64" "$SANDBOX/bin64.keep"
check "a compiler the player put there: on leaves it as it is and downloads none" eval 'GW2_ON_MAC_COMPILER_URL="file://$SANDBOX/nowhere/c.dll" "$G" set reshade on >/dev/null 2>&1 && has "$GD/d3dcompiler_47.dll" "the player" && [ "$(rsst)" = on ] && [ ! -e "$CACHE/downloads/reshade/d3dcompiler_47.dll" ]'
check "  off leaves it too" eval '"$G" set reshade off >/dev/null 2>&1 && has "$GD/d3dcompiler_47.dll" "the player" && [ ! -e "$GD/d3d11.dll" ]'
rm -f "$GD/d3dcompiler_47.dll"; mv "$SANDBOX/bin64.keep" "$GD/bin64"
# a ReShade the app didn't place
cp "$SANDBOX/pe/reshade-addon.dll" "$GD/d3d11.dll"; before=$(gdsnap)
check "a ReShade the app didn't place (another build): reshade_state=foreign, reshade_dll=d3d11.dll" [ "$(st reshade_state reshade_dll reshade)" = foreign/d3d11.dll/off ]
check "  set reshade on refused, the file left alone, nothing added" eval '! "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 && grep -q "^@error The game folder has a ReShade that GW2 on Mac didn.t put there (d3d11.dll)" "$SANDBOX/rs.txt" && [ "$(gdsnap)" = "$before" ]'
check "  set reshade off: @done, the file left alone" eval '"$G" set reshade off | grep -q "^@done GW2 on Mac didn.t put the ReShade" && same "$SANDBOX/pe/reshade-addon.dll" "$GD/d3d11.dll"'
g set rawmouse on >/dev/null
check "  the override is written for it too" compiler_rule on
check "  set arcdps on refused, naming ReShade" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "has a ReShade that GW2 on Mac didn.t put there" && same "$SANDBOX/pe/reshade-addon.dll" "$GD/d3d11.dll"'
mv "$GD/d3d11.dll" "$GD/dxgi.dll"
check "  as dxgi.dll: foreign as well, reshade_dll=dxgi.dll" [ "$(st reshade_state reshade_dll)" = foreign/dxgi.dll ]
rm -f "$GD/dxgi.dll"
g set rawmouse on >/dev/null
check "  gone: the override deleted" compiler_rule off
g set reshade on >/dev/null 2>&1
check "with the app's ReShade in, the exclusive layout: arcdps_state=foreign, set arcdps on refused: turn ReShade off first" eval '[ "$(GW2_ON_MAC_ADDONS_LAYOUT=exclusive g status | sed -n "s/^arcdps_state=//p")" = foreign ] && ! GW2_ON_MAC_ADDONS_LAYOUT=exclusive "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "ReShade is in the game folder as d3d11.dll. Turn ReShade off first" && same "$SANDBOX/pe/ReShade64.dll" "$GD/d3d11.dll" && [ ! -e "$GD/dxgi.dll" ]'
# nothing changes while a session runs, or while a Play holds the session's lock
mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
"$ENG/bin/wineserver" 60 & sp=$!
sleep 0.3
before=$(gdsnap)
check "while a session runs: set reshade off and on refused, nothing changes" eval '! "$G" set reshade off >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "Quit Guild Wars 2 and Steam first" && ! "$G" set reshade on >/dev/null 2>&1 && [ "$(gdsnap)" = "$before" ] && [ "$(sett reshade)" = on ]'
kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 30 & hp=$!
i=0; until "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock" || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
check "while a Play holds the session's lock: set reshade off refused, nothing changes" eval '! "$G" set reshade off >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "session is starting" && [ "$(gdsnap)" = "$before" ]'
kill $hp 2>/dev/null; wait $hp 2>/dev/null
check "dry run of on: places nothing" eval '"$G" set reshade off >/dev/null && GW2_ON_MAC_DRY_RUN=1 "$G" set reshade on | grep -q "would be in the game folder" && [ ! -e "$GD/d3d11.dll" ]'
# (Play, Repair and the caches)
g set reshade on >/dev/null 2>&1
rm -f "$GD/d3d11.dll" "$GD/d3dcompiler_47.dll" "$GD/ReShade.ini"   # (Steam's file check, a new bottle)
check "the files gone from the game folder: reshade=on, reshade_state=off" [ "$(st reshade reshade_state)" = on/off ]
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 GW2_ON_MAC_RESHADE_URL="file://$SANDBOX/nowhere/r.exe" GW2_ON_MAC_COMPILER_URL="file://$SANDBOX/nowhere/c.dll" "$G" play 2>&1); started
check "the next Play puts them back from the cache, without a download, and starts the game" eval 'same "$SANDBOX/pe/ReShade64.dll" "$GD/d3d11.dll" && same "$GD/bin64/cef/d3dcompiler_47.dll" "$GD/d3dcompiler_47.dll" && our_ini && ! echo "$out" | grep -q "^@progress" && has "$STANDIN_LOG" "^wine "'
check "  with the override" compiler_rule on
watch_done
# Collect Logs with ReShade on: what ReShade writes into its folder after a session (its log with
# Wine's Z:\ paths, cut at 5 MB, a line of binary bytes at its end), the current preset, a 20 MB
# file under Shaders; the session report from a DXMT log of that session
{ echo "FIRST LINE, cut away"; head -c 6000000 /dev/zero | tr '\0' '.' | fold -w 99
  printf '%s\n' "INFO | Initializing crosire's ReShade version '6.8.0.2091' (64-bit) loaded from 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Guild Wars 2\\d3d11.dll'" \
    "INFO | Loading effects from 'Z:$(winf "$RSF")\\Shaders\\Standard\\Deband.fx' and 'Z:\\Users\\$(id -un)\\Documents\\Mine.fx'"
  printf 'binary \001\002\377\376\0 end\n'; echo "LAST LINE"; } >"$RSF/ReShade.log"
# (the preset under a file name with the user's name, chosen in a ReShade.ini that starts with a
# UTF-8 BOM, as an editor may save it)
PRESET_FILE="$RSF/Presets/$(id -un) look.ini"
printf '[Deband.fx]\nIterations=4\n; from Z:%s\\Downloads\n\nTechniques=Deband@Deband.fx\n' "$(winf "$H")" >"$PRESET_FILE"
cp "$RSF/ReShade.ini" "$SANDBOX/ReShade.ini.keep"
# setpreset <PresetPath>: ReShade.ini with that PresetPath, after a BOM
setpreset() { { printf '\357\273\277'; P=$1 awk '/^PresetPath=/ { $0 = "PresetPath=" ENVIRON["P"] } { print }' "$SANDBOX/ReShade.ini.keep"; } >"$RSF/ReShade.ini"; }
setpreset ".\\Presets\\$(id -un) look.ini"
head -c 20000000 /dev/urandom >"$RSF/Shaders/big.bin"
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\ninfo:  STATS fps=60.0 ms=16.7/24.8 cb=1.1 rp=31.7(+0.0 merged) encode=0.23+1.03/10.3\n' >"$LOGS/Gw2-64_d3d11.log"
collect
check "Collect Logs with ReShade on: ReShade.log, ReShade.ini, the current preset and the names under Shaders" \
  eval 'for f in ReShade.log ReShade.ini preset.ini shaders.txt; do [ -f "$Z/reshade/$f" ] || exit 1; done'
check "  none of them, nor the reports, holds the home folder or the user name; nor does a name in the zip" \
  eval 'no_home "$Z/reshade" "$Z/system-info.txt" "$Z/session-report.txt" && ! unzip -Z1 "$zip" | grep -qiw "$(id -un)"'
check "  the Z:\\ paths kept, from ~ on; the preset's techniques kept" eval 'grep -qxF "IntermediateCachePath=Z:~\\Library\\Caches\\$APP_FOLDER\\reshade" "$Z/reshade/ReShade.ini" && has "$Z/reshade/preset.ini" "^Techniques=Deband@Deband.fx$"'
check "  ReShade.log: its last 5 MB, the binary line and the last line in, the first out" \
  eval 'head -1 "$Z/reshade/ReShade.log" | grep -qxF "[GW2 on Mac: only the last 5 MB of ReShade.log]" && has "$Z/reshade/ReShade.log" "^LAST LINE" && has "$Z/reshade/ReShade.log" "^binary " && ! has "$Z/reshade/ReShade.log" "FIRST LINE" && [ "$(stat -f %z "$Z/reshade/ReShade.log")" -lt 5100000 ]'
check "  shaders.txt names the files, the 20 MB one too; no file of Shaders in the zip" \
  eval 'grep -qxF "Standard/Deband.fx" "$Z/reshade/shaders.txt" && grep -qxF "big.bin" "$Z/reshade/shaders.txt" && [ "$(find "$Z/reshade" -type f | wc -l | tr -d " ")" = 4 ] && [ "$(stat -f %z "$zip")" -lt 3000000 ]'
check "  system-info: ReShade on, 6.8.0 as d3d11.dll, the compiler's sha256, the folder" \
  eval 'grep -qxF "ReShade: on, 6.8.0 as d3d11.dll; arcdps off" "$Z/system-info.txt" && grep -qxF "  d3dcompiler_47.dll next to Gw2-64.exe: sha256 $(sum "$GD/d3dcompiler_47.dll")" "$Z/system-info.txt" && grep -qF "look.ini, in reshade/preset.ini" "$Z/system-info.txt" && has "$Z/system-info.txt" "d3d11.dll addon: ReShade"'
check "  the session report's ReShade line matches reshade_state and the compiler's sha256" \
  eval 'ST_OUT=$(g status); grep -qxF "ReShade at the start: $(kv "$ST_OUT" reshade_state), $(kv "$ST_OUT" reshade_version) as $(kv "$ST_OUT" reshade_dll); arcdps $(kv "$ST_OUT" arcdps)" "$Z/session-report.txt" && grep -qxF "  d3dcompiler_47.dll next to Gw2-64.exe: sha256 $(sum "$GD/d3dcompiler_47.dll")" "$Z/session-report.txt" && [ "$(kv "$ST_OUT" reshade_state)" = on ]'
# a preset outside the ReShade folder (an absolute Z:\ path) stays out
echo "zz secret preset" >"$SANDBOX/secret-preset.ini"
setpreset "Z:$(winf "$SANDBOX")\\secret-preset.ini"
collect
check "a PresetPath outside the ReShade folder: that file is not collected, system-info says so" \
  eval 'grep -q "^PresetPath=Z:.*secret-preset.ini" "$RSF/ReShade.ini" && [ ! -e "$Z/reshade/preset.ini" ] && ! grep -rq "zz secret preset" "$Z" && grep -qF "preset outside the ReShade folder, not collected" "$Z/system-info.txt"'
mv -f "$SANDBOX/ReShade.ini.keep" "$RSF/ReShade.ini"; rm -f "$RSF/Shaders/big.bin" "$RSF/ReShade.log" "$PRESET_FILE" "$SANDBOX/secret-preset.ini"
rm -f "$GD/d3d11.dll" "$GD/d3dcompiler_47.dll" "$GD/ReShade.ini"; rm -rf "$CACHE/downloads/reshade" "$GD/bin64"
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 g play 2>&1); started
check "Play without the cache: the game starts without ReShade, and Play says why" eval 'echo "$out" | grep -q "^@warn ReShade.s files are not in the cache" && [ ! -e "$GD/d3d11.dll" ] && [ ! -e "$GD/d3dcompiler_47.dll" ] && ! echo "$out" | grep -q "^@progress" && has "$STANDIN_LOG" "^wine "'
check "  and without the override" compiler_rule off
watch_done
out=$(g repair 2>&1) && rc=0 || rc=$?
check "Repair downloads them again and puts them back" eval '[ "$rc" = 0 ] && echo "$out" | grep -q "^@progress ReShade " && same "$SANDBOX/pe/ReShade64.dll" "$GD/d3d11.dll" && same "$RSV/d3dcompiler_47.dll" "$GD/d3dcompiler_47.dll" && our_ini && same "$SANDBOX/pe/ReShade64.dll" "$CACHE/downloads/reshade/ReShade64.dll"'
check "  with the override, and the player's preset still there" eval 'compiler_rule on && has "$RSF/Presets/Mine.ini" preset'
rm -f "$GD/d3d11.dll"
check "Repair puts a missing file back from the cache" eval '"$G" repair >/dev/null 2>&1 && same "$SANDBOX/pe/ReShade64.dll" "$GD/d3d11.dll"'
echo "compiled" >"$CACHE/reshade/reshade-1234.cso"
check "reset-shaders empties ReShade's cache too, and keeps its folder" eval '"$G" reset-shaders | grep -q "DXMT.s and ReShade.s caches" && [ -d "$CACHE/reshade" ] && [ ! -e "$CACHE/reshade/reshade-1234.cso" ]'

section "arcdps and ReShade together"
# The layout (addon_dll): alone, each is d3d11.dll; with both in, ReShade is d3d11.dll and arcdps
# addons/arcdps/chain/d3d11.dll, which ReShade loads itself through the [PROXY] keys of the ReShade
# folder's ReShade.ini. who <file>: whose it is; lay: d3d11.dll's and the chain file's; keys: the
# EnableProxyLibrary value in [PROXY] ("1 at <path>" for a wrong ProxyLibrary); keys_ok: on exactly
# when ReShade and arcdps are both in place, and one [PROXY] section at most
CH=addons/arcdps/chain/d3d11.dll
PX="C:$(printf '/%s' "${GD#"$BOTTLE/drive_c/"}/$CH" | tr / '\\')"
who() {
  if [ ! -e "$GD/$1" ]; then echo -
  elif same "$SANDBOX/pe/ReShade64.dll" "$GD/$1"; then echo reshade
  elif has "$GD/$1" "arcdps build"; then echo arcdps
  else echo other
  fi
}
lay() { echo "$(who d3d11.dll) $(who "$CH")"; }
keys() {
  PX=$PX LC_ALL=C awk '{ sub(/\r$/, "") } /^[ \t]*\[/ { s = $0; next }
    s == "[PROXY]" && /^EnableProxyLibrary=/ { e = substr($0, 20) } s == "[PROXY]" && /^ProxyLibrary=/ { p = substr($0, 14) }
    END { if (e == "1" && p != ENVIRON["PX"]) e = "1 at " p; print e }' "$RSF/ReShade.ini" 2>/dev/null
}
keys_ok() {
  local k n
  k=$(keys) n=$(grep -c '^\[PROXY\]' "$RSF/ReShade.ini" 2>/dev/null || true)
  [ "${n:-0}" -le 1 ] || return 1
  if [ "$(lay)" = "reshade arcdps" ]; then [ "$k" = 1 ]; else case "$k" in 1*) return 1 ;; esac; fi
}
# places: the three places' files (to show nothing there changed)
places() { for f in d3d11.dll dxgi.dll "$CH"; do [ ! -e "$GD/$f" ] || shasum "$GD/$f"; done; }
# switches <addon> <on|off> <d3d11.dll's> <the chain file's>...: each set exits 0, leaves that
# layout, and the keys match it
switches() {
  while [ $# -ge 4 ]; do
    "$G" set "$1" "$2" >"$SANDBOX/both.txt" 2>&1 || { echo "    set $1 $2 failed: $(tail -1 "$SANDBOX/both.txt")"; return 1; }
    [ "$(lay)" = "$3 $4" ] || { echo "    after set $1 $2: $(lay), not $3 $4"; return 1; }
    keys_ok && [ ! -e "$GD/dxgi.dll" ] || { echo "    after set $1 $2: keys '$(keys)' with $(lay)"; return 1; }
    shift 4
  done
}
# with both off, no addon file, ReShade.ini or temporary file is left, and the keys are off
none_left() { [ ! -e "$GD/d3d11.dll" ] && [ ! -e "$GD/dxgi.dll" ] && [ ! -e "$GD/$CH" ] && [ ! -e "$GD/ReShade.ini" ] && [ -z "$(find "$GD" -name '*gw2om-new')" ] && [ "$(keys)" != 1 ]; }
g set reshade off >/dev/null 2>&1; rm -f "$GD/d3d11.dll" "$GD/dxgi.dll"; rm -rf "$GD/addons"
check "arcdps on, ReShade on, arcdps off, ReShade off" switches arcdps on arcdps - reshade on reshade arcdps arcdps off reshade - reshade off - -
check "  neither file left, keys off" none_left
check "arcdps on, ReShade on, ReShade off, arcdps off" switches arcdps on arcdps - reshade on reshade arcdps reshade off arcdps - arcdps off - -
check "  neither file left, keys off" none_left
check "ReShade on, arcdps on, arcdps off, ReShade off" switches reshade on reshade - arcdps on reshade arcdps arcdps off reshade - reshade off - -
check "  neither file left, keys off" none_left
check "ReShade on, arcdps on, ReShade off, arcdps off" switches reshade on reshade - arcdps on reshade arcdps reshade off arcdps - arcdps off - -
check "  neither file left, reshade=off, keys off" eval 'none_left && [ "$(sett reshade)" = off ]'
out=$(g set arcdps on 2>&1); out2=$(g set reshade on 2>&1)
check "both on: ReShade d3d11.dll, arcdps at the chain path, and @done says ReShade loads arcdps" eval '[ "$(lay)" = "reshade arcdps" ] && echo "$out2" | grep -qx "@done ReShade 6.8.0 is in the game folder as d3d11.dll. It loads the next time the game starts. ReShade loads arcdps itself now, so both load."'
check "  the ReShade folder's ReShade.ini: EnableProxyLibrary=1, ProxyLibrary=the chain file as C:\\" eval 'grep -qxF "EnableProxyLibrary=1" "$RSF/ReShade.ini" && grep -qxF "ProxyLibrary=$PX" "$RSF/ReShade.ini" && [ "$(keys)" = 1 ] && has "$LOGS/install.log" "ReShade.ini: \[PROXY\] EnableProxyLibrary=1"'
check "  status: arcdps on at the chain path with no foreign file, reshade_state=on with no blocker" eval '[ "$(st arcdps arcdps_state arcdps_dll arcdps_foreign reshade_state reshade_blocker reshade_dll)" = "on/on/$CH//on//d3d11.dll" ]'
check "  rundll32.exe gets d3d11 and dxgi native,builtin" rundll on
check "  settings say the same, and addons_layout=together" eval '[ "$(sett arcdps_state arcdps_dll reshade_state reshade addons_layout)" = "on/$CH/on/on/together" ]'
check "  set arcdps on and set reshade on again: already there, nothing moves" eval '"$G" set arcdps on | grep -qF "already in the game folder ($CH)" && "$G" set reshade on | grep -q "already in the game folder (d3d11.dll)" && [ "$(lay)" = "reshade arcdps" ] && keys_ok'
out=$(g set reshade off 2>&1)
check "ReShade off: @done says arcdps is d3d11.dll again; keys off" eval 'echo "$out" | grep -q "^@done ReShade is off: its d3d11.dll is out of the game folder. arcdps is d3d11.dll again." && [ "$(lay)" = "arcdps -" ] && [ "$(keys)" = 0 ]'
g set reshade on >/dev/null 2>&1; g set arcdps off >/dev/null 2>&1
out=$(g set arcdps on 2>&1)
check "arcdps on next to ReShade: downloaded straight to the chain path, keys on, and @done says so" eval 'echo "$out" | grep -qxF "@done arcdps is in the game folder ($CH from deltaconnected.com). It loads the next time the game starts, and from then on it updates itself. ReShade loads arcdps itself now, so both load." && [ "$(lay)" = "reshade arcdps" ] && keys_ok'
# the already-there answers put the keys right too
cp "$RSF/ReShade.ini" "$SANDBOX/rs.ini.keep"
grep -v -e '^EnableProxyLibrary=' "$SANDBOX/rs.ini.keep" >"$RSF/ReShade.ini"
check "  keys gone, both in: set arcdps on (already there) turns them on" eval '"$G" set arcdps on | grep -q "already in the game folder" && [ "$(keys)" = 1 ] && keys_ok'
sed 's/^EnableProxyLibrary=1/EnableProxyLibrary=0/' "$SANDBOX/rs.ini.keep" >"$RSF/ReShade.ini"
check "  keys off, both in: set reshade on (already there) turns them on" eval '"$G" set reshade on | grep -q "already in the game folder" && [ "$(keys)" = 1 ] && keys_ok'

# Play puts the keys right before the start, without a download: keys off with both files in (the
# ini rewritten without them), keys on with no arcdps at their path
nodl() { GW2_ON_MAC_RESHADE_URL="file://$SANDBOX/nowhere/r.exe" GW2_ON_MAC_COMPILER_URL="file://$SANDBOX/nowhere/c.dll" GW2_ON_MAC_ARCDPS_URL="file://$SANDBOX/nowhere" "$G" "$@"; }
cp "$RSF/ReShade.ini" "$SANDBOX/rs.ini.keep"
grep -v -e '^\[PROXY\]' -e '^EnableProxyLibrary=' -e '^ProxyLibrary=' "$SANDBOX/rs.ini.keep" >"$RSF/ReShade.ini"
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 nodl play 2>&1); started
check "keys gone, both files in: the next Play turns them on, and the game starts" eval '[ "$(keys)" = 1 ] && keys_ok && [ "$(lay)" = "reshade arcdps" ] && ! echo "$out" | grep -q "^@progress" && has "$STANDIN_LOG" "^wine "'
watch_done
rm -f "$GD/$CH"
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 nodl play 2>&1); started
check "keys on, arcdps gone from the chain path: the next Play turns them off, and the game starts with ReShade" eval '[ "$(keys)" = 0 ] && [ "$(lay)" = "reshade -" ] && has "$STANDIN_LOG" "^wine "'
watch_done

# The ini edit: the two keys and nothing else, byte for byte (CRLF, [PROXY] between other sections
# as ReShade sorts them, another key there, a ProxyLibrary in another section, no last line break);
# a missing [PROXY] goes at the end with the file's line ends
g set arcdps off >/dev/null 2>&1; g set arcdps on >/dev/null 2>&1
printf '[GENERAL]\r\nPresetPath=.\\Presets\\Mine.ini\r\nProxyLibrary=elsewhere.dll\r\n\r\n[OVERLAY]\r\nTutorialProgress=4\r\n\r\n[PROXY]\r\nEnableProxyLibrary=0\r\n;ProxyLibrary=commented\r\nKeepMe=1\r\n\r\n[SCREENSHOT]\r\nSavePath=.\\Screenshots\\Caf\303\251' >"$RSF/ReShade.ini"
printf '[GENERAL]\r\nPresetPath=.\\Presets\\Mine.ini\r\nProxyLibrary=elsewhere.dll\r\n\r\n[OVERLAY]\r\nTutorialProgress=4\r\n\r\n[PROXY]\r\nProxyLibrary=%s\r\nEnableProxyLibrary=1\r\n;ProxyLibrary=commented\r\nKeepMe=1\r\n\r\n[SCREENSHOT]\r\nSavePath=.\\Screenshots\\Caf\303\251' "$PX" >"$SANDBOX/ini.want"
check "the keys go on at Repair: two keys in [PROXY] and nothing else, byte for byte (cmp)" eval '"$G" repair >/dev/null 2>&1 && cmp "$SANDBOX/ini.want" "$RSF/ReShade.ini"'
printf '[GENERAL]\r\nPresetPath=.\\Presets\\Mine.ini\r\nProxyLibrary=elsewhere.dll\r\n\r\n[OVERLAY]\r\nTutorialProgress=4\r\n\r\n[PROXY]\r\nProxyLibrary=%s\r\nEnableProxyLibrary=0\r\n;ProxyLibrary=commented\r\nKeepMe=1\r\n\r\n[SCREENSHOT]\r\nSavePath=.\\Screenshots\\Caf\303\251' "$PX" >"$SANDBOX/ini.want"
check "  and off at set arcdps off: EnableProxyLibrary=0 and nothing else (cmp)" eval '"$G" set arcdps off >/dev/null 2>&1 && cmp "$SANDBOX/ini.want" "$RSF/ReShade.ini" && [ "$(lay)" = "reshade -" ]'
printf '[GENERAL]\r\nPresetPath=.\\Presets\\Mine.ini\r\n\r\n[SCREENSHOT]\r\nSavePath=.\\Screenshots\r\n' >"$RSF/ReShade.ini"
printf '[GENERAL]\r\nPresetPath=.\\Presets\\Mine.ini\r\n\r\n[SCREENSHOT]\r\nSavePath=.\\Screenshots\r\n[PROXY]\r\nEnableProxyLibrary=1\r\nProxyLibrary=%s\r\n' "$PX" >"$SANDBOX/ini.want"
check "  no [PROXY] yet: one at the end, CRLF, at set arcdps on (cmp)" eval '"$G" set arcdps on >/dev/null 2>&1 && cmp "$SANDBOX/ini.want" "$RSF/ReShade.ini"'
check "  and the same again changes nothing: one [PROXY]" eval '"$G" repair >/dev/null 2>&1 && cmp "$SANDBOX/ini.want" "$RSF/ReShade.ini"'
rm -f "$RSF/ReShade.ini"
check "  no ReShade.ini at all: the starting one is written first, then the keys" eval '"$G" repair >/dev/null 2>&1 && grep -q "^IntermediateCachePath=Z:" "$RSF/ReShade.ini" && keys_ok && [ "$(keys)" = 1 ]'
cp "$SANDBOX/rs.ini.keep" "$RSF/ReShade.ini"; g repair >/dev/null 2>&1

# arcdps updates itself. If it writes the game folder's d3d11.dll (over ReShade's) while ReShade
# loads it: the next Play keeps the newest arcdps at the chain path, puts ReShade back from the
# cache, the keys on; if the newer one is already the chain file, the other goes
cp "$SANDBOX/pe/arcdps.dll" "$SANDBOX/pe/arcdps-new.dll" && printf 'arcdps build 20261114 (stand-in)\n' >>"$SANDBOX/pe/arcdps-new.dll"
touch -t 202611010000 "$GD/$CH"; cp "$SANDBOX/pe/arcdps-new.dll" "$GD/d3d11.dll"
check "arcdps's update over ReShade's d3d11.dll: both arcdps, reshade_state=off" eval '[ "$(lay)" = "arcdps arcdps" ] && [ "$(st arcdps_state arcdps_foreign reshade_state)" = on//off ]'
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 nodl play 2>&1); started
check "  the next Play: the newer arcdps at the chain path, ReShade back as d3d11.dll, keys on, the game starts" eval '[ "$(lay)" = "reshade arcdps" ] && same "$SANDBOX/pe/arcdps-new.dll" "$GD/$CH" && keys_ok && has "$STANDIN_LOG" "^wine "'
check "  the log says what it found and which arcdps stayed" has "$LOGS/install.log" "arcdps: in the game folder as d3d11.dll and $CH (it updated itself); keeping the newer d3d11.dll"
watch_done
cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"; touch -t 202611010000 "$GD/d3d11.dll"; cp "$SANDBOX/pe/arcdps-new.dll" "$SANDBOX/pe/arcdps-newer.dll"; printf 'newer\n' >>"$SANDBOX/pe/arcdps-newer.dll"; cp "$SANDBOX/pe/arcdps-newer.dll" "$GD/$CH"
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 nodl play 2>&1); started
check "  an older arcdps as d3d11.dll, the newer at the chain path: Play keeps the chain file, ReShade back" eval '[ "$(lay)" = "reshade arcdps" ] && same "$SANDBOX/pe/arcdps-newer.dll" "$GD/$CH" && keys_ok'
watch_done
rm -f "$GD/$CH"; cp "$SANDBOX/pe/arcdps-new.dll" "$GD/d3d11.dll"
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 nodl play 2>&1); started
check "  arcdps only as d3d11.dll (the chain file gone): Play moves it to the chain path, ReShade back" eval '[ "$(lay)" = "reshade arcdps" ] && same "$SANDBOX/pe/arcdps-new.dll" "$GD/$CH" && keys_ok'
watch_done
mv "$CACHE/downloads/reshade/ReShade64.dll" "$SANDBOX/rs64.keep"; cp "$SANDBOX/pe/arcdps-new.dll" "$GD/d3d11.dll"
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 nodl play 2>&1); started
check "  without ReShade in the cache: Play says so, arcdps stays as d3d11.dll alone, keys off, the game starts" eval 'echo "$out" | grep -q "^@warn ReShade.s files are not in the cache" && [ "$(lay)" = "arcdps -" ] && keys_ok && has "$STANDIN_LOG" "^wine "'
watch_done
mv "$SANDBOX/rs64.keep" "$CACHE/downloads/reshade/ReShade64.dll"; g repair >/dev/null 2>&1

# A development build of 0.1.4 left arcdps as dxgi.dll next to ReShade: the next Play moves it to
# the chain path and turns the keys on
check "  (back to both on)" eval '[ "$(lay)" = "reshade arcdps" ] && keys_ok'
mv "$GD/$CH" "$GD/dxgi.dll"; rm -rf "$GD/addons/arcdps/chain"; mkdir -p "$GD/addons/arcdps" && echo "the player's arcdps settings" >"$GD/addons/arcdps/arcdps.ini"
check "arcdps as dxgi.dll next to ReShade (a development build): arcdps on, ReShade on" eval '[ "$(st arcdps_state arcdps_dll reshade_state)" = on/dxgi.dll/on ]'
: >"$STANDIN_LOG"
out=$(GW2_ON_MAC_WATCH_GRACE=0 nodl play 2>&1); started
check "  the next Play: arcdps at the chain path, no dxgi.dll, keys on, its settings stay, the game starts" eval '[ "$(lay)" = "reshade arcdps" ] && keys_ok && has "$GD/addons/arcdps/arcdps.ini" "the player" && has "$LOGS/install.log" "arcdps: dxgi.dll renamed to $CH" && has "$STANDIN_LOG" "^wine "'
watch_done
# Collect Logs with both in, after that session
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\ninfo:  STATS fps=60.0 ms=16.7/24.8 cb=1.1 rp=31.7(+0.0 merged) encode=0.23+1.03/10.3\n' >"$LOGS/Gw2-64_d3d11.log"
collect
check "  Collect Logs: system-info names ReShade as d3d11.dll and arcdps at the chain path" \
  eval 'has "$Z/system-info.txt" "^  d3d11.dll addon: ReShade, " && has "$Z/system-info.txt" "^  $CH addon: arcdps, " && grep -qxF "ReShade: on, 6.8.0 as d3d11.dll; arcdps on as $CH" "$Z/system-info.txt"'
check "  the session report: ReShade and arcdps on as that session started, arcdps at the chain path" grep -qxF "ReShade at the start: on, 6.8.0 as d3d11.dll; arcdps on as $CH" "$Z/session-report.txt"
check "  addon-files.txt names ReShade's d3d11.dll and arcdps at the chain path" eval 'grep -qE " d3d11.dll\$" "$Z/game-logs/addon-files.txt" && grep -qE " $CH\$" "$Z/game-logs/addon-files.txt"'

# another program's file at any of the three places blocks both switches, named, and is never
# touched (nor is arcdps renamed next to it)
g set arcdps off >/dev/null 2>&1; g set reshade off >/dev/null 2>&1; rm -rf "$GD/addons"
for at in dxgi.dll "$CH"; do
  mkdir -p "$GD/addons/arcdps/chain"; cp "$SANDBOX/pe/nexus.dll" "$GD/$at"; cp "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll"; before=$(places)
  check "Nexus as $at, arcdps as d3d11.dll: set reshade on refused, naming $at, nothing changes" eval '! "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "^@error The game folder has another $at (Nexus" && [ "$(places)" = "$before" ] && keys_ok'
  echo "reshade=on" >>"$AD/settings.conf"
  check "  Repair with reshade=on: ReShade stays out, saying so; nothing renamed or removed" eval 'out=$("$G" repair 2>&1); echo "$out" | grep -q "^@warn ReShade stays out of the game folder. The game folder has another $at" && [ "$(places)" = "$before" ] && keys_ok'
  g set reshade off >/dev/null 2>&1; rm -f "$GD/d3d11.dll"; before=$(places)
  check "  arcdps out: set arcdps on refused, naming $at, nothing changes" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "^@error The game folder has another $at (Nexus" && [ "$(places)" = "$before" ]'
  rm -f "$GD/$at"
done
cp "$SANDBOX/pe/nexus.dll" "$GD/d3d11.dll"; cp "$SANDBOX/pe/arcdps.dll" "$GD/$CH"; before=$(places)
check "Nexus as d3d11.dll, arcdps at the chain path: ReShade blocked by d3d11.dll alone" eval '[ "$(st arcdps_state arcdps_foreign reshade_state reshade_blocker)" = on/d3d11.dll/blocked/d3d11.dll ]'
check "  set reshade on refused, naming d3d11.dll; Repair renames nothing; keys off" eval '! "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "^@error The game folder has another d3d11.dll (Nexus" && "$G" repair >/dev/null 2>&1 && [ "$(places)" = "$before" ] && [ "$(keys)" != 1 ]'
rm -f "$GD/d3d11.dll"; rm -rf "$GD/addons"
g set reshade on >/dev/null 2>&1; cp "$SANDBOX/pe/nexus.dll" "$GD/dxgi.dll"; before=$(places)
check "Nexus as dxgi.dll next to ReShade: set arcdps on refused, naming dxgi.dll, nothing changes" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "^@error The game folder has another dxgi.dll (Nexus" && [ "$(places)" = "$before" ]'
rm -f "$GD/dxgi.dll"; g set reshade off >/dev/null 2>&1

# the exclusive layout: each switch refuses while the other is in, naming it; Play leaves the keys off
g set arcdps on >/dev/null 2>&1; before=$(gdsnap)
check "exclusive: with arcdps in, set reshade on refused, naming arcdps; nothing changes" eval '! GW2_ON_MAC_ADDONS_LAYOUT=exclusive "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "^@error arcdps is in the game folder as d3d11.dll. Turn arcdps off first, then turn ReShade on." && [ "$(gdsnap)" = "$before" ]'
g set arcdps off >/dev/null 2>&1; GW2_ON_MAC_ADDONS_LAYOUT=exclusive "$G" set reshade on >/dev/null 2>&1; before=$(gdsnap)
check "  with ReShade in, set arcdps on refused, naming ReShade; nothing changes" eval '! GW2_ON_MAC_ADDONS_LAYOUT=exclusive "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "^@error ReShade is in the game folder as d3d11.dll. Turn ReShade off first, then turn arcdps on." && [ "$(gdsnap)" = "$before" ] && [ "$(lay)" = "reshade -" ]'
check "  states: arcdps_state=foreign, arcdps_foreign=d3d11.dll" eval '[ "$(GW2_ON_MAC_ADDONS_LAYOUT=exclusive g status | sed -n "s/^arcdps_state=//p; s/^arcdps_foreign=//p" | tr "\n" /)" = foreign/d3d11.dll/ ]'
g set arcdps on >/dev/null 2>&1
check "  both in, then Repair in the exclusive layout: the keys go off, no file moves" eval '[ "$(keys)" = 1 ] && before=$(places) && GW2_ON_MAC_ADDONS_LAYOUT=exclusive "$G" repair >/dev/null 2>&1 && [ "$(keys)" = 0 ] && [ "$(places)" = "$before" ]'
g set arcdps off >/dev/null 2>&1; g set reshade off >/dev/null 2>&1

# a failed step is undone: ReShade's DLL can't go in; ReShade's ini can't be written (at On of
# either switch, and at arcdps's Off); the script killed after the rename leaves arcdps working
g set arcdps on >/dev/null 2>&1
touch "$PAUSE"; rm -f "$PAUSE.at"
GW2_ON_MAC_TEST_PAUSE="$PAUSE" GW2_ON_MAC_TEST_PAUSE_AT=arcdps-moved "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 & ra=$!
check "ReShade on with arcdps in: arcdps at the chain path before ReShade's DLL goes in, keys still off" eval 'wait_at && [ "$(lay)" = "- arcdps" ] && [ "$(keys)" != 1 ]'
chmod 000 "$CACHE/downloads/reshade/ReShade64.dll"
rm -f "$PAUSE"; wait $ra; rc=$?
chmod 644 "$CACHE/downloads/reshade/ReShade64.dll"
check "  ReShade's DLL can't go in: refused, saying so, arcdps back as d3d11.dll, keys off, no temporary file" eval '[ "$rc" != 0 ] && has "$SANDBOX/rs.txt" "^@error GW2 on Mac couldn.t put ReShade into the game folder as d3d11.dll" && [ "$(lay)" = "arcdps -" ] && same "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll" && keys_ok && [ -z "$(find "$GD" -name "*gw2om-new")" ]'
check "  reshade=off, arcdps_state=on" eval '[ "$(sett reshade)/$(arcst)" = off/on ]'
chmod 555 "$RSF"
check "ReShade's ini can't be written: set reshade on refused, saying so; ReShade out, arcdps back as d3d11.dll" eval '! "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "^@error GW2 on Mac couldn.t change ReShade.s settings .*, so ReShade stays out of the game folder" && [ "$(lay)" = "arcdps -" ] && keys_ok'
chmod 755 "$RSF"; g set arcdps off >/dev/null 2>&1; g set reshade on >/dev/null 2>&1; chmod 555 "$RSF"
check "  set arcdps on next to ReShade: refused, saying so; arcdps out again" eval '! "$G" set arcdps on >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "^@error GW2 on Mac couldn.t change ReShade.s settings .*, so arcdps stays out" && [ "$(lay)" = "reshade -" ] && keys_ok && [ -z "$(find "$GD" -name "*gw2om-new")" ]'
chmod 755 "$RSF"; g set arcdps on >/dev/null 2>&1; chmod 555 "$RSF"; before=$(places)
check "  with both in, set arcdps off and set reshade off: refused, saying so; nothing changes, keys still on" eval '! "$G" set arcdps off >"$SANDBOX/arc.txt" 2>&1 && has "$SANDBOX/arc.txt" "so arcdps stays in" && ! "$G" set reshade off >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "so ReShade stays in" && [ "$(places)" = "$before" ] && [ "$(keys)" = 1 ]'
rm -f "$GD/$CH"
: >"$STANDIN_LOG"
out=""; out=$(nodl play 2>&1) || true
check "  keys on, arcdps gone, the ini unwritable: Play refuses to start, saying why" eval '! echo "$out" | grep -q "^@done" && echo "$out" | grep -q "^@error GW2 on Mac couldn.t change ReShade.s settings .*the game would have no Direct3D 11" && ! has "$STANDIN_LOG" "^wine "'
chmod 755 "$RSF"; g repair >/dev/null 2>&1
check "  Repair, with the ini writable again: keys off, ReShade alone" eval '[ "$(lay)" = "reshade -" ] && [ "$(keys)" = 0 ]'
# both in, the keys on at an old path (ReShade reads 2 as on, and the first of a repeated key), the
# ini unwritable: Play refuses; Repair with the ini writable puts the keys right
g set arcdps on >/dev/null 2>&1
cp "$RSF/ReShade.ini" "$SANDBOX/ini.good"
OLDPX='C:\old bottle\addons\arcdps\chain\d3d11.dll'
for how in 1 2 "1 then 0"; do
  OLDPX=$OLDPX HOW=$how awk '/^EnableProxyLibrary=/ { print "EnableProxyLibrary=" substr(ENVIRON["HOW"], 1, 1); if (ENVIRON["HOW"] == "1 then 0") print "EnableProxyLibrary=0"; next }
    /^ProxyLibrary=/ { print "ProxyLibrary=" ENVIRON["OLDPX"]; next } { print }' "$SANDBOX/ini.good" >"$RSF/ReShade.ini"
  chmod 555 "$RSF"; : >"$STANDIN_LOG"
  out=""; out=$(nodl play 2>&1) || true
  check "  both in, EnableProxyLibrary=$how at an old path, the ini unwritable: Play refuses to start" eval 'grep -qxF "ProxyLibrary=$OLDPX" "$RSF/ReShade.ini" && ! echo "$out" | grep -q "^@done" && echo "$out" | grep -q "the game would have no Direct3D 11" && ! has "$STANDIN_LOG" "^wine "'
  chmod 755 "$RSF"
done
g repair >/dev/null 2>&1
check "  Repair, with the ini writable again: keys on at the chain file" eval '[ "$(lay)" = "reshade arcdps" ] && keys_ok && [ "$(keys)" = 1 ]'
g set arcdps off >/dev/null 2>&1; g set reshade off >/dev/null 2>&1

check "  then the switches work as usual" switches arcdps on arcdps - reshade on reshade arcdps reshade off arcdps -
touch "$PAUSE"; rm -f "$PAUSE.at"
# (the app's gw2om.sh itself: killing G would end only the wrapper)
GW2_ON_MAC_TEST_PAUSE="$PAUSE" GW2_ON_MAC_TEST_PAUSE_AT=arcdps-moved "$GW2OM" set reshade on >"$SANDBOX/rs.txt" 2>&1 & ra=$!
wait_at; kill -9 $ra 2>/dev/null; wait $ra 2>/dev/null; rm -f "$PAUSE" "$PAUSE.at"
check "killed after the rename: arcdps at the chain path, ReShade off, keys off" eval '[ "$(lay)" = "- arcdps" ] && [ "$(st arcdps_state reshade_state)/$(sett reshade)" = on/off/off ] && keys_ok'
g set rawmouse on >/dev/null
check "  arcdps only at the chain path: rundll32.exe gets d3d11 and dxgi native,builtin" rundll on
check "  Repair moves arcdps back to d3d11.dll" eval '"$G" repair >/dev/null 2>&1 && [ "$(lay)" = "arcdps -" ] && keys_ok'
check "  then ReShade on and off work as usual" switches reshade on reshade arcdps reshade off arcdps - arcdps off - -
g set reshade off >/dev/null 2>&1
check "  and neither file is left, nor rundll32.exe's overrides" eval 'none_left && rundll off'
# nothing changes while a session runs
g set arcdps on >/dev/null 2>&1
mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
"$ENG/bin/wineserver" 60 & sp=$!
sleep 0.3
before=$(places)
check "while a session runs: set reshade on refused, arcdps not moved" eval '! "$G" set reshade on >"$SANDBOX/rs.txt" 2>&1 && has "$SANDBOX/rs.txt" "Quit Guild Wars 2 and Steam first" && [ "$(places)" = "$before" ]'
kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
g set arcdps off >/dev/null 2>&1; rm -rf "$GD/addons"

section "ReShade presets and shaders (reshade import, reshade use)"
# The section above's ReShade folder is put aside: the import works with ReShade off, before it was
# ever on. Stand-ins of what players bring from preset pages: a preset, a zip of a preset with its
# reshade-shaders folder (and files that must stay out), a folder of loose effects; hostile zips made
# here or patched in place, and links in the ReShade folder that lead out of it.
g set reshade off >/dev/null 2>&1
mv "$RSF" "$SANDBOX/rsf.keep"
IM="$SANDBOX/import" OUT="$SANDBOX/outside"
mkdir -p "$IM/zip" "$OUT"
imp() { "$G" reshade import "$@" >"$SANDBOX/imp.txt" 2>&1; }
use() { "$G" reshade use "$@" >"$SANDBOX/imp.txt" 2>&1; }
done_is() { [ "$(sed -n 's/^@done //p' "$SANDBOX/imp.txt")" = "$1" ] || { cat "$SANDBOX/imp.txt"; false; }; }
err_has() { grep -q "^@error .*$1" "$SANDBOX/imp.txt" || { cat "$SANDBOX/imp.txt"; false; }; }
presets_are() { [ "$(sed -n 's/^@preset //p' "$SANDBOX/imp.txt")" = "$1" ]; }
rssnap() { (cd "$RSF" 2>/dev/null && find . \( -type f -o -type l \) -exec shasum {} + | LC_ALL=C sort); }
# files and links outside the ReShade folder, the logs and the checks' own files that changed after
# the marker
outside_changed() { find "$SANDBOX" -newer "$SANDBOX/marker" \( -type f -o -type l \) ! -path "$RSF/*" ! -path "$LOGS/*" ! -path "$CHECKS/*" ! -path "$SANDBOX/imp.txt"; }
DEPTH="off in online games with this build of ReShade."
printf '%s\n' 'PreprocessorDefinitions=' 'Techniques=MXAO@qUINT_mxao.fx,Vibrance@Vibrance.fx,Clarity@Clarity.fx' \
  'TechniqueSorting=MXAO@qUINT_mxao.fx,Vibrance@Vibrance.fx,Clarity@Clarity.fx' '' '[Vibrance.fx]' 'Vibrance=0.150000' >"$IM/Lumen.ini"
GH="$IM/zip/Golden Hour"
mkdir -p "$GH/reshade-shaders/Shaders/sub" "$GH/reshade-shaders/Textures" "$GH/Shaders"
printf '%s\r\n' 'Techniques=Vibrance@Vibrance.fx,CAS@CAS.fx,PD80@PD80_04_Contrast_Brightness_Saturation.fx,DisplayDepth@DisplayDepth.fx' >"$GH/Golden Hour.ini"
printf '[GENERAL]\nEffectSearchPaths=.\\Shaders\n' >"$GH/ReShade.ini"
echo '// Vibrance' >"$GH/reshade-shaders/Shaders/Vibrance.fx"; echo '// Clarity' >"$GH/reshade-shaders/Shaders/sub/Clarity.fxh"
echo 'PNG' >"$GH/reshade-shaders/Textures/Lut.png"; echo '// DisplayDepth' >"$GH/Shaders/DisplayDepth.fx"
for f in ReShade64.DLL README.txt; do echo x >"$GH/$f"; done
for f in evil.Addon64 run.sh tool.EXE Setup.Dll; do echo x >"$GH/reshade-shaders/Shaders/$f"; done
echo x >"$GH/Shaders/start.command"; chmod 755 "$GH/Shaders/start.command" "$GH/reshade-shaders/Shaders/run.sh" "$GH/Shaders/DisplayDepth.fx"
( cd "$IM/zip" && zip -qr "../Golden Hour.zip" "Golden Hour" )
LF="$IM/loose fx"
mkdir -p "$LF/sub/Shaders"
echo '// CAS' >"$LF/CAS.fx"; echo '// common' >"$LF/Common.fxh"; echo PNG >"$LF/noise.PNG"; echo x >"$LF/tool.dll"
printf '[GENERAL]\nKey=1\n' >"$LF/notes.ini"; echo '// deep' >"$LF/sub/Shaders/Deep.fx"; ln -s /etc/hosts "$LF/hosts.fx"
printf 'Techniques=CAS@CAS.fx,Deep@Deep.fx\n' >"$IM/Night.ini"
before=$(gdsnap)
check "a preset while ReShade is off and its folder isn't there yet: exits 0" imp "$IM/Lumen.ini"
check "  the ReShade folder as On makes it, with the preset in Presets" eval '[ -d "$RSF/Shaders" ] && [ -d "$RSF/Textures" ] && [ -d "$RSF/Screenshots" ] && [ "$(cat "$RSF/ReShade.ini")" = "$RS_INI_WANT" ] && same "$IM/Lumen.ini" "$RSF/Presets/Lumen.ini"'
check "  the game folder as it was, ReShade still off" eval '[ "$(gdsnap)" = "$before" ] && [ ! -e "$GD/ReShade.ini" ] && [ "$(sett reshade)/$(rsst)" = off/off ]'
check "  the report: its effects, the missing ones, the depth effect; @preset names it" eval 'done_is "Added 1 preset to Presets. This preset uses 3 effects. 3 are missing: qUINT_mxao.fx, Vibrance.fx and Clarity.fx. qUINT_mxao.fx reads the depth buffer: it stays $DEPTH" && presets_are Lumen.ini'
check "a zip of a preset with its reshade-shaders folder: the report" eval 'imp "$IM/Golden Hour.zip" && done_is "Added 1 preset to Presets, 3 shader files to Shaders/Golden Hour and 1 image to Textures/Golden Hour. This preset uses 4 effects. 2 are missing: CAS.fx and PD80_04_Contrast_Brightness_Saturation.fx. DisplayDepth.fx reads the depth buffer: it stays $DEPTH"'
check "  Shaders and Textures at any depth under the zip's name, the preset (CRLF) in Presets" eval 'same "$GH/reshade-shaders/Shaders/Vibrance.fx" "$RSF/Shaders/Golden Hour/Vibrance.fx" && [ -f "$RSF/Shaders/Golden Hour/sub/Clarity.fxh" ] && [ -f "$RSF/Shaders/Golden Hour/DisplayDepth.fx" ] && [ -f "$RSF/Textures/Golden Hour/Lut.png" ] && same "$GH/Golden Hour.ini" "$RSF/Presets/Golden Hour.ini"'
check "  its ReShade.ini (no preset) stays out: the folder's own is as it was" eval '[ ! -e "$RSF/Presets/ReShade.ini" ] && [ "$(cat "$RSF/ReShade.ini")" = "$RS_INI_WANT" ]'
check "a folder of loose effects with a preset beside it, in one import" eval 'imp "$LF" "$IM/Night.ini" && done_is "Added 1 preset to Presets, 3 shader files to Shaders/loose fx and 1 image to Textures/loose fx. This preset uses 2 effects, all of them in Shaders." && presets_are Night.ini'
check "  loose .fx and .fxh into Shaders/<folder>, images into Textures/<folder>, a Shaders folder's too" eval 'same "$LF/CAS.fx" "$RSF/Shaders/loose fx/CAS.fx" && [ -f "$RSF/Shaders/loose fx/Common.fxh" ] && [ -f "$RSF/Shaders/loose fx/Deep.fx" ] && [ -f "$RSF/Textures/loose fx/noise.PNG" ]'
check "nothing executable or scriptable came in, whatever its case, no README, no link, no other .ini" eval '[ -z "$(find "$RSF" -iname "*.dll" -o -iname "*.exe" -o -iname "*.addon*" -o -iname "*.sh" -o -iname "*.command" -o -name README.txt -o -name hosts.fx -o -name notes.ini -o -type l)" ] && [ -z "$(find "$RSF" -type f -perm -100)" ]'
# refused, with nothing added
printf '[GENERAL]\nTechniques=Vibrance@Vibrance.fx\n' >"$IM/Settings.ini"
echo x >"$IM/ReShade64.dll"
printf 'Techniques=Vibrance@Vibrance.fx\n' >"$IM/Fresh.ini"
before=$(rssnap)
check "an .ini whose Techniques key is in a section (no preset): refused, saying why" eval '! imp "$IM/Settings.ini" && err_has "Settings.ini is not a ReShade preset: it has no Techniques line" && [ "$(rssnap)" = "$before" ]'
check "a .dll: refused" eval '! imp "$IM/ReShade64.dll" && err_has "ReShade64.dll is not a preset (.ini), a zip or a folder" && [ "$(rssnap)" = "$before" ]'
check "one bad source refuses the whole import: the good one isn't added either" eval '! imp "$IM/Fresh.ini" "$IM/ReShade64.dll" && [ "$(rssnap)" = "$before" ] && [ ! -e "$CACHE/downloads/reshade/import" ]'
check "a dry run adds nothing" eval 'GW2_ON_MAC_DRY_RUN=1 "$G" reshade import "$IM/Fresh.ini" | grep -q "^@done Nothing was added" && [ "$(rssnap)" = "$before" ]'
# hostile zips and folders, links in the ReShade folder: nothing written outside it
mkdir -p "$PK/abs/Shaders" && echo '// abs' >"$PK/abs/Shaders/x.fx"
( cd "$PK" && zip -qr "$IM/abs.zip" abs ) && perl -0777 -pi -e 's{abs/Shaders/x\.fx}{/bs/Shaders/x.fx}g' "$IM/abs.zip"
mkdir -p "$IM/Evil/Shaders" && echo '// evil' >"$IM/Evil/Shaders/a.fx"
ln -s "$LF" "$IM/linked"
touch "$SANDBOX/marker"
check "a zip with a path that climbs out (..): refused, nothing written outside" eval '! imp "$RSV/dotdot.zip" && err_has "has a file whose path leaves its folder" && [ -z "$(find "$SANDBOX" -name evil.fx -not -path "$PK/*")" ]'
check "a zip with an absolute path: refused" eval '! imp "$IM/abs.zip" && err_has "abs has a file whose path leaves its folder (/bs/Shaders/x.fx)"'
check "a zip with a link in it: refused" eval '! imp "$RSV/link.zip" && err_has "link has a link in it"'
check "a zip over the size limit: refused" eval '! GW2_ON_MAC_PACK_LIMIT=10 imp "$IM/Golden Hour.zip" && err_has "Golden Hour unpacks to more than"'
check "a zip and a folder with more files than the limit: refused" eval '! GW2_ON_MAC_PACK_MAX_FILES=3 imp "$IM/Golden Hour.zip" && err_has "Golden Hour has more than 3 files in it" && ! GW2_ON_MAC_PACK_MAX_FILES=3 imp "$LF" && err_has "loose fx has more than 3 files in it"'
check "a dropped folder that is a link: refused, with or without a slash or /." eval 'for l in linked linked/ linked// linked/. linked/./; do ! imp "$IM/$l" && err_has "linked is a link" || exit 1; done'
ln -s "$OUT" "$RSF/Shaders/Evil"
check "a link in the ReShade folder where the source's folder goes: refused, nothing through it" eval '! imp "$IM/Evil" && err_has "Shaders/Evil in the ReShade folder is a link or a file" && [ -z "$(ls -A "$OUT")" ]'
rm -f "$RSF/Shaders/Evil"; mv "$RSF/Textures" "$SANDBOX/textures.keep"; ln -s "$OUT" "$RSF/Textures"
check "  Textures itself a link: refused, nothing through it" eval '! imp "$IM/Golden Hour.zip" && err_has "Textures in the ReShade folder is a link or a file" && [ -z "$(ls -A "$OUT")" ]'
rm -f "$RSF/Textures"; mv "$SANDBOX/textures.keep" "$RSF/Textures"
rmdir "$RSF/Screenshots" && ln -s "$SANDBOX/nowhere/shots" "$RSF/Screenshots"
check "  a dangling link for Screenshots: refused, saying so" eval '! imp "$IM/Fresh.ini" && err_has "Screenshots in the ReShade folder is a link or a file"'
rm -f "$RSF/Screenshots"; mkdir "$RSF/Screenshots"
mv "$RSF/.imports" "$SANDBOX/imports.keep" && ln -s "$OUT" "$RSF/.imports"
check "  a link to a folder in place of the record of imports: refused, nothing moved into it" eval '! imp "$IM/Fresh.ini" && err_has ".imports in the ReShade folder is a folder or a link to one" && [ -z "$(ls -A "$OUT")" ]'
rm -f "$RSF/.imports"; mv "$SANDBOX/imports.keep" "$RSF/.imports"
mv "$RSF" "$SANDBOX/rsf.real" && ln -s "$SANDBOX/rsf.real" "$RSF"
check "  the ReShade folder itself a link: refused, nothing added where it leads" eval '! imp "$IM/Fresh.ini" && err_has "The ReShade folder is a link or a file" && [ ! -e "$SANDBOX/rsf.real/Presets/Fresh.ini" ]'
rm -f "$RSF"; mv "$SANDBOX/rsf.real" "$RSF"
check "  the refusals wrote nothing outside the ReShade folder, and changed nothing in it" eval '[ -z "$(outside_changed)" ] && [ "$(rssnap)" = "$before" ] || { outside_changed; false; }'
# names that break careless scripts
printf 'Techniques=Vibrance@Vibrance.fx\n' >"$IM/-n \"it's\" 4K.ini"
printf 'Techniques=Vibrance@Vibrance.fx\n' >"$IM/new
line.ini"
check "presets named with a leading dash, quotes and a line break: in, as names Windows takes" eval 'imp "$IM/-n \"it'\''s\" 4K.ini" "$IM/new
line.ini" && presets_are "$(printf "%s\n" "-n _it'\''s_ 4K.ini" new_line.ini)" && same "$IM/new
line.ini" "$RSF/Presets/new_line.ini" && done_is "Added 2 presets to Presets. These 2 presets use 1 effect, which is in Shaders."'
mkdir -p "$IM/dash/Shaders" && echo '// d' >"$IM/dash/-d.fx" && echo '// q' >"$IM/dash/Shaders/q[1].fx" && echo '// star' >"$IM/dash/Shaders/a*b.fx"
( cd "$IM/dash" && zip -q "../-x [v2].zip" -- -d.fx Shaders/q\[1\].fx 'Shaders/a*b.fx' )
check "a zip with a leading dash and brackets in its name and its files' names, named from its folder: each file on its own" eval '(cd "$IM" && imp "-x [v2].zip") && same "$IM/dash/-d.fx" "$RSF/Shaders/-x _v2_/-d.fx" && same "$IM/dash/Shaders/q[1].fx" "$RSF/Shaders/-x _v2_/q[1].fx" && same "$IM/dash/Shaders/a*b.fx" "$RSF/Shaders/-x _v2_/a*b.fx"'
mkdir -p "$IM/n/Shaders" && echo '// n' >"$IM/n/Shaders/n.fx" && ( cd "$IM/n" && zip -q ../-n.zip Shaders/n.fx )
printf 'Techniques=Vibrance@Vibrance.fx\n' >"$IM/Look.INI"
check "a zip named like an option of echo (-n.zip): its folder is -n" eval 'imp "$IM/-n.zip" && same "$IM/n/Shaders/n.fx" "$RSF/Shaders/-n/n.fx"'
check "a preset ending in .INI: in Presets as .ini, the name ReShade takes" eval 'imp "$IM/Look.INI" && presets_are Look.ini && same "$IM/Look.INI" "$RSF/Presets/Look.ini"'
# a name that is there already: replaced only from a source of the same name
echo "the player's own" >"$RSF/Presets/ReShadePreset.ini"
mkdir -p "$IM/pack" && printf 'Techniques=Vibrance@Vibrance.fx\n' >"$IM/pack/ReShadePreset.ini" && printf 'Techniques=CAS@CAS.fx\n' >"$IM/pack/Lumen.ini"
( cd "$IM/pack" && zip -q ../Pack.zip ReShadePreset.ini Lumen.ini )
check "a zip whose presets clash with the player's own and another source's: both kept, and it says so" eval 'imp "$IM/Pack.zip" && done_is "Presets already had Lumen.ini and ReShadePreset.ini from elsewhere, so GW2 on Mac kept them, not the new ones." && presets_are "" && has "$RSF/Presets/ReShadePreset.ini" "the player" && same "$IM/Lumen.ini" "$RSF/Presets/Lumen.ini"'
printf 'Techniques=CAS@CAS.fx\n' >"$IM/Lumen.ini"
check "the same preset again from a source of the same name: replaced" eval 'imp "$IM/Lumen.ini" && same "$IM/Lumen.ini" "$RSF/Presets/Lumen.ini" && done_is "Added 1 preset to Presets. This preset uses 1 effect, which is in Shaders."'
echo "outside" >"$OUT/target.txt"
ln -f "$OUT/target.txt" "$RSF/Presets/Lumen.ini"
check "  a hard link in its place: replaced, the file it shares stays as it was" eval 'imp "$IM/Lumen.ini" && same "$IM/Lumen.ini" "$RSF/Presets/Lumen.ini" && has "$OUT/target.txt" "^outside$"'
ln -sf "$OUT/target.txt" "$RSF/Presets/Lumen.ini"
check "  a link in its place: replaced by the file, not written through" eval 'imp "$IM/Lumen.ini" && [ ! -L "$RSF/Presets/Lumen.ini" ] && same "$IM/Lumen.ini" "$RSF/Presets/Lumen.ini" && has "$OUT/target.txt" "^outside$"'
ln -s "$OUT/target.txt" "$RSF/Presets/Sym.ini" && printf 'Techniques=CAS@CAS.fx\n' >"$IM/Sym.ini"
check "  a link of the player's of that name: kept as it is" eval 'imp "$IM/Sym.ini" && grep -q "^@done Presets already had Sym.ini from elsewhere" "$SANDBOX/imp.txt" && [ -L "$RSF/Presets/Sym.ini" ] && has "$OUT/target.txt" "^outside$"'
# a long report
printf 'Techniques=%s\n' 'A@m1.fx,B@m2.fx,C@m3.fx,D@m4.fx,E@m5.fx,F@m6.fx,G@m7.fx,H@m8.fx' >"$IM/Many.ini"
check "many missing effects: the report names five and the number of the others" eval 'imp "$IM/Many.ini" && done_is "Added 1 preset to Presets. This preset uses 8 effects. 8 are missing: m1.fx, m2.fx, m3.fx, m4.fx, m5.fx and 3 more."'
check "  the output and the log have them all" eval 'grep -qxF "Effects missing from $RSF/Shaders: m1.fx, m2.fx, m3.fx, m4.fx, m5.fx, m6.fx, m7.fx and m8.fx" "$SANDBOX/imp.txt" && has "$LOGS/install.log" "Effects missing from .*m7.fx and m8.fx"'
# reshade use: the one key, byte for byte
printf '[ADDON]\r\nPresetPath=.\\other\r\n\r\n[GENERAL]\r\n;PresetPath=commented\r\nEffectSearchPaths=.\\Shaders\\**\r\n  PresetPath = .\\Presets\\Old.ini  \r\nTextureSearchPaths=.\\Textures\\**\r\n\r\n[SCREENSHOT]\r\nSavePath=.\\Screenshots\\Caf\303\251' >"$RSF/ReShade.ini"
printf '[ADDON]\r\nPresetPath=.\\other\r\n\r\n[GENERAL]\r\n;PresetPath=commented\r\nEffectSearchPaths=.\\Shaders\\**\r\nPresetPath=.\\Presets\\Golden Hour.ini\r\nTextureSearchPaths=.\\Textures\\**\r\n\r\n[SCREENSHOT]\r\nSavePath=.\\Screenshots\\Caf\303\251' >"$SANDBOX/ini.want"
check "reshade use: PresetPath and nothing else, byte for byte (CRLF, comments, another section's key, no last line break)" eval 'use "Golden Hour.ini" && done_is "ReShade starts with Golden Hour.ini the next time the game starts." && same "$SANDBOX/ini.want" "$RSF/ReShade.ini"'
printf 'Techniques=Vibrance@Vibrance.fx\n' >"$IM/Day, Night.ini" && imp "$IM/Day, Night.ini"
printf '[GENERAL]\nEffectSearchPaths=.\\Shaders\\**\n\n[INPUT]\nKeyOverlay=36,0,0,0\n' >"$RSF/ReShade.ini"
printf '[GENERAL]\nPresetPath=.\\Presets\\Day,, Night.ini\nEffectSearchPaths=.\\Shaders\\**\n\n[INPUT]\nKeyOverlay=36,0,0,0\n' >"$SANDBOX/ini.want"
check "  without the key: under [GENERAL]'s header, a comma doubled as ReShade reads it" eval 'use "Day, Night.ini" && same "$SANDBOX/ini.want" "$RSF/ReShade.ini"'
printf '[INPUT]\nKeyOverlay=36,0,0,0\n' >"$RSF/ReShade.ini"
printf '[INPUT]\nKeyOverlay=36,0,0,0\n[GENERAL]\nPresetPath=.\\Presets\\Night.ini\n' >"$SANDBOX/ini.want"
check "  without [GENERAL]: a section of its own at the end" eval 'use Night.ini && same "$SANDBOX/ini.want" "$RSF/ReShade.ini"'
printf '[GENERAL]\nKey=1\n' >"$RSF/Presets/NotOne.ini"; cp "$RSF/ReShade.ini" "$SANDBOX/ini.before"
check "  refused for a preset that isn't in Presets, an .ini there that isn't one, a path" eval '! use Nope.ini && err_has "Nope.ini is not in" && ! use NotOne.ini && err_has "NotOne.ini is not a ReShade preset" && ! use ../ReShade.ini && err_has "Name a preset in" && same "$SANDBOX/ini.before" "$RSF/ReShade.ini"'
mkdir "$SANDBOX/outside2" && mv "$RSF/ReShade.ini" "$SANDBOX/ini.keep" && ln -s "$SANDBOX/outside2" "$RSF/ReShade.ini"
check "  ReShade.ini a link to a folder: refused, nothing moved into it" eval '! use Night.ini && err_has "ReShade.ini in the ReShade folder is a folder or a link to one" && [ -z "$(ls -A "$SANDBOX/outside2")" ]'
rm -f "$RSF/ReShade.ini"; mv "$SANDBOX/ini.keep" "$RSF/ReShade.ini"
# while a session runs: the import adds, reshade use is refused
mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
"$ENG/bin/wineserver" 60 & sp=$!
sleep 0.3
printf 'Techniques=Vibrance@Vibrance.fx\n' >"$IM/Running.ini"
check "while a session runs: the import adds, and says to pick the preset in ReShade's menu" eval 'imp "$IM/Running.ini" && [ -f "$RSF/Presets/Running.ini" ] && grep -q "^@done .* Guild Wars 2 is running: pick the preset in ReShade.s menu (Home key).$" "$SANDBOX/imp.txt"'
check "  reshade use refused, saying to pick it in ReShade's menu; ReShade.ini as it was" eval '! use Running.ini && err_has "Guild Wars 2 is running, and ReShade rewrites its settings while it runs. Pick Running.ini in ReShade.s menu (Home key) instead." && same "$SANDBOX/ini.before" "$RSF/ReShade.ini"'
kill $sp 2>/dev/null || true; wait $sp 2>/dev/null || true
mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
"$APP/Contents/Resources/helpers/sessionlock" hold "$AD/.session.lock" 30 & hp=$!
i=0; until "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock" || [ $i -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
check "  while a Play holds the session's lock: reshade use refused" eval '! use Running.ini && err_has "A game session is starting" && same "$SANDBOX/ini.before" "$RSF/ReShade.ini"'
kill $hp 2>/dev/null; wait $hp 2>/dev/null
check "no staging folder is left in the cache" [ ! -e "$CACHE/downloads/reshade/import" ]
rm -rf "$RSF"; mv "$SANDBOX/rsf.keep" "$RSF"

section "ReShade's packs at On (after an import, deleted by hand)"
# On brings the standard effects whenever Shaders has no ReShade.fxh, and SweetFX only once. The
# folder from the sections above is put aside: each case starts before the first On.
mv "$RSF" "$SANDBOX/rsf.keep"
imp "$LF"
out=$(g set reshade on 2>&1) && rc=0 || rc=$?
check "a pack imported before the first On: On adds the standard effects and SweetFX next to it" eval '[ "$rc" = 0 ] && same "$S1/Shaders/ReShade.fxh" "$RSF/Shaders/Standard/ReShade.fxh" && [ -f "$RSF/Shaders/SweetFX/SweetFX/CAS.fx" ] && same "$LF/CAS.fx" "$RSF/Shaders/loose fx/CAS.fx" || { echo "$out"; false; }'
rm -rf "$RSF/Shaders/SweetFX" "$RSF/Textures/SweetFX"
g set reshade off >/dev/null 2>&1
out=$(GW2_ON_MAC_SWEETFX_URL="file://$SANDBOX/nowhere/f.zip" "$G" set reshade on 2>&1) && rc=0 || rc=$?
check "SweetFX deleted by hand: the next On leaves it out, without a download" eval '[ "$rc" = 0 ] && [ ! -e "$RSF/Shaders/SweetFX" ] && ! echo "$out" | grep -q "^@progress"'
rm -rf "$RSF/Shaders/Standard" "$RSF/Textures/Standard"
g set reshade off >/dev/null 2>&1
out=$(GW2_ON_MAC_SWEETFX_URL="file://$SANDBOX/nowhere/f.zip" "$G" set reshade on 2>&1) && rc=0 || rc=$?
check "the standard effects deleted by hand: the next On brings them back, and not SweetFX" eval '[ "$rc" = 0 ] && [ -f "$RSF/Shaders/Standard/ReShade.fxh" ] && [ -f "$RSF/Textures/Standard/FontAtlas.png" ] && [ ! -e "$RSF/Shaders/SweetFX" ]'
g set reshade off >/dev/null 2>&1
rm -rf "$RSF"
imp "$IM/Night.ini"
out=$(g set reshade on 2>&1) && rc=0 || rc=$?
check "a preset imported before the first On: On adds both packs" eval '[ "$rc" = 0 ] && [ -f "$RSF/Shaders/Standard/ReShade.fxh" ] && [ -f "$RSF/Shaders/SweetFX/SweetFX/CAS.fx" ] && [ -f "$RSF/Presets/Night.ini" ]'
g set reshade off >/dev/null 2>&1
rm -rf "$RSF"; mv "$SANDBOX/rsf.keep" "$RSF"

section "Uninstall"
GW2_ON_MAC_WATCH_GRACE=60 "$G" play >/dev/null 2>&1; started; watcher_up
wp=$(sess watcher_pid)
check "a session's watcher waits for the game" kill -0 "$wp"
mkdir -p "$CACHE/downloads" && echo x >"$CACHE/downloads/x"
out=$(g uninstall 2>&1) && rc=0 || rc=$?
check "uninstall exits 0" [ "$rc" = 0 ]
check "the phases 1-3" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 " ]
check "the app's folder holds only the ReShade folder (engine, bottle with the game, settings, the session gone)" [ "$(ad_list)" = ReShade ]
check "  the ReShade folder stays with the player's preset, and uninstall names it" eval 'has "$RSF/Presets/Mine.ini" preset && echo "$out" | grep -qF "your ReShade presets and shaders in $RSF."'
check "  the session's watcher stopped" sh -c "! kill -0 $wp 2>/dev/null"
check "its caches are gone" eval '[ ! -e "$CACHE" ] && [ ! -e "$DXMT_CACHE" ]'
check "the per-user cache folder's dxmt/ stays (another setup's)" other_dxmt_kept
check "the logs stay" [ -f "$LOGS/install.log" ]
check "status: not installed" [ "$(st installed engine_installed)" = no/no ]
rm -rf "$AD"
fi

# GW2 on Mac 0.1's folders, which rest and move both make, and a checksum of every file in them,
# by content
O1="$H/Library/Application Support/GW2 on Mac"
o1sum() { (cd "$H/Library" && find "Application Support/GW2 on Mac" "Caches/GW2 on Mac" -type f -print0 | sort -z | xargs -0 shasum -a 256) | shasum -a 256; }

if in_group rest; then
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
  check "route=arenanet, stage=waiting_game, no Steam" [ "$(st route stage steam)" = arenanet/waiting_game/no ]
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
check "nothing else left in the app's folder, dxmt.conf neither" [ -z "$(ad_list)" ]
# a folder or a link where dxmt.conf goes: refused before the write, and it stays as it was
mkdir -p "$AD/dxmt.conf" && echo mine >"$AD/dxmt.conf/sentinel"
out=$(g install steam 2>&1) && rc=0 || rc=$?
check "a folder at dxmt.conf: refused, the folder as it was, nothing else left" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error $AD/dxmt.conf is a folder or a link" && [ "$(ls -A "$AD/dxmt.conf")" = sentinel ] && [ "$(ad_list)" = dxmt.conf ]'
rm -rf "$AD/dxmt.conf"
ln -s "$SANDBOX/dxmt-elsewhere.conf" "$AD/dxmt.conf"
out=$(g install steam 2>&1) && rc=0 || rc=$?
check "a link at dxmt.conf to nothing: refused, the link as it was, nothing where it leads" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error $AD/dxmt.conf is a folder or a link" && [ "$(readlink "$AD/dxmt.conf")" = "$SANDBOX/dxmt-elsewhere.conf" ] && [ ! -e "$SANDBOX/dxmt-elsewhere.conf" ] && [ "$(ad_list)" = dxmt.conf ]'
rm -f "$AD/dxmt.conf"
# Cancel once Steam's start wrote the game's rules (phase 4): they go too
RP="$SANDBOX/pause-rules"
touch "$RP"
GW2_ON_MAC_TEST_PAUSE="$RP" GW2_ON_MAC_TEST_PAUSE_AT=rules-written "$GW2OM" install steam >"$SANDBOX/cancelled.txt" 2>&1 & ip=$!
i=0; until [ -e "$RP.at" ] || [ $i -ge 600 ]; do sleep 0.1; i=$((i + 1)); done
at=no; [ ! -e "$RP.at" ] || at=yes
kill -TERM "$ip"; wait "$ip"; rc=$?; rm -f "$RP" "$RP.at"
check "Cancel after Steam's start wrote the rules: the install stops, nothing left, compatdb.rules neither" \
  eval '[ "$at" = yes ] && [ "$rc" != 0 ] && has "$SANDBOX/cancelled.txt" "^@phase 4" && [ -z "$(ad_list)" ]'
# rules that appear once this install has started (another start wrote them): its failure before
# its own launch keeps them
LP="$SANDBOX/pause-lock"
touch "$LP"
GW2_ON_MAC_STEAMSETUP_URL="file://$SANDBOX/missing.exe" GW2_ON_MAC_TEST_PAUSE="$LP" GW2_ON_MAC_TEST_PAUSE_AT=locked g install steam >"$SANDBOX/rules-kept.txt" 2>&1 & lp=$!
i=0; until [ -e "$LP.at" ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
echo "rules of another start" >"$AD/compatdb.rules"; rm -f "$LP"; wait "$lp"; rc=$?; rm -f "$LP.at"
check "rules written after this install started: its failure at Steam's download keeps them, and only them" \
  eval '[ "$rc" != 0 ] && has "$SANDBOX/rules-kept.txt" "@error The download of SteamSetup.exe" && [ "$(cat "$AD/compatdb.rules")" = "rules of another start" ] && [ "$(ad_list)" = compatdb.rules ]'
rm -f "$AD/compatdb.rules"

section "Stop waiting keeps the engine and the bottle"
g install steam >/dev/null 2>&1
check "stop-waiting" sh -c "'$G' stop-waiting | grep -q '@done'"
check "  stage=none, engine and bottle stay" [ "$(st stage installed)" = none/yes ]
g uninstall >/dev/null 2>&1

section "Use existing game files (other Wine apps' installs)"
# GW2 on Mac 0.1's own bottle (a Steam install with arcdps, my own addon and the game's settings;
# DXMT's caches in its cache folder), CrossOver (a Steam install, with my own addon, another
# program's d3d11.dll, another addon and the game's settings), Whisky and a Sikarugir wrapper
# (ArenaNet installs), a broken one (Gw2.dat too small). Gw2.dat is sparse.
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
O1SUM=$(o1sum)
CX="$H/Library/Application Support/CrossOver/Bottles/Steam GW2/drive_c"
CXG="$CX/Program Files (x86)/Steam/steamapps/common/Guild Wars 2"
CXS="$CX/users/crossover/AppData/Roaming/Guild Wars 2"
mkdir -p "$CXG/bin64" "$CXS"
echo "stand-in game" >"$CXG/Gw2-64.exe" && mkfile -n 2g "$CXG/Gw2.dat" && echo "bin" >"$CXG/bin64/CoherentUI64.dll"
cp "$COMP/ui-scale/version.dll" "$CXG/version.dll" && echo "scale=1.75" >"$CXG/gw2-ui-scale.ini" && echo "arcdps" >"$CXG/d3d11.dll"
cp "$SANDBOX/pe/nexus.dll" "$CXG/dxgi.dll"
# (an addons folder outside the game folder, with arcdps at ReShade's chain path: a link to it in
# the game folder makes the import refuse, below)
mkdir -p "$SANDBOX/shared-addons/arcdps/chain" && cp "$SANDBOX/pe/arcdps.dll" "$SANDBOX/shared-addons/arcdps/chain/d3d11.dll"
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
# a ReShade from another install stays behind: its ReShade.ini (CrossOver's, whose dxgi.dll is
# Nexus's), as d3d11.dll (Whisky's), and a ReShade.ini alone (the wrapper's); its presets and
# shaders come along
printf '[INSTALL]\nBasePath=C:\\ReShade\n' >"$CXG/ReShade.ini"
mkdir -p "$CXG/reshade-shaders/Shaders" && echo '// mine' >"$CXG/reshade-shaders/Shaders/Mine.fx" && echo 'preset' >"$CXG/ReShadePreset.ini"
cp "$SANDBOX/pe/reshade-addon.dll" "$WHG/d3d11.dll"
echo '[GENERAL]' >"$WRC/Program Files/Guild Wars 2/ReShade.ini"
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
check "scan finds CrossOver's, Whisky's and the wrapper's, not 0.1's nor the broken one" eval '[ "$(echo "$out" | grep -c "^game")" = 3 ] && [ -z "$(line_of "GW2 on Mac 0.1")" ]'
check "  CrossOver's: the Steam route, the same disk, settings" [ "$(fields 'CrossOver · Steam GW2')" = "steam yes yes" ]
check "  its size: the folder's files (over 2 GB)" [ "$(line_of 'CrossOver · Steam GW2' | cut -f4)" -gt 2147483648 ]
check "  its path" [ "$(line_of 'CrossOver · Steam GW2' | cut -f7)" = "$CXG" ]
check "  Whisky's, by its bottle's name: ArenaNet" [ "$(fields 'Whisky · GW2 Whisky')" = "arenanet yes yes" ]
check "  the wrapper's: ArenaNet" [ "$(fields 'Wrapper · Guild Wars 2')" = "arenanet yes yes" ]
check "check-game: a folder without the game" sh -c "'$G' check-game '$SANDBOX/standin' | grep -q '^@error This folder has no Guild Wars 2'"
check "check-game: Gw2.dat under 1 GB is not the game" sh -c "'$G' check-game '$BR' | grep -q '^@error'"
check "check-game: the wrapper app itself finds the game in it" sh -c "'$G' check-game '$WRAP' | grep -q \"\$(printf 'game\tWrapper · Guild Wars 2\tarenanet')\""
check "check-game: a bottle's folder finds its Steam install" sh -c "'$G' check-game '$(dirname "$CX")' | grep -q \"\$(printf '\tsteam\t')\""
# gi <folder> [<option>...]: install import with my yes to the folder at its size, as check-game
# gave them (what the window passes after its alert)
gi() {
  local src=$1 l
  shift
  l=$(g check-game "$src" | grep '^game' | head -1)
  g install import "$src" "$@" --copy --confirm-path "$(printf '%s' "$l" | cut -f7)" --confirm-bytes "$(printf '%s' "$l" | cut -f4)"
}
# 0.1's game is never taken (the move renames it): by its path, inside its bottle, through a link to
# it, and through a link in 0.1's folder to a game outside; with a yes passed or not
check "check-game refuses 0.1's game, and says the first start moves it" sh -c "'$G' check-game '$O1G' | grep -q '^@error That is GW2 on Mac 0.1.s game, and GW2 on Mac doesn.t copy it\. At its first start GW2 on Mac moves it in by a rename, without extra space\.$'"
check "  and 0.1's bottle" sh -c "'$G' check-game '$O1/bottle' | grep -q '^@error That is GW2 on Mac 0.1.s game'"
ln -s "$O1G" "$SANDBOX/to-o1"
check "  and a link to it from outside" sh -c "'$G' check-game '$SANDBOX/to-o1' | grep -q '^@error That is GW2 on Mac 0.1.s game'"
rm -f "$SANDBOX/to-o1"
mkgame() { mkdir -p "$1" && echo "stand-in game" >"$1/Gw2-64.exe" && mkfile -n "${2:-1100m}" "$1/Gw2.dat"; }
mkgame "$SANDBOX/o1-out/Guild Wars 2" && mkdir "$O1C/Program Files" && ln -s "$SANDBOX/o1-out/Guild Wars 2" "$O1C/Program Files/Guild Wars 2"
check "  and a link in 0.1's bottle to a game outside it" sh -c "'$G' check-game '$O1C/Program Files/Guild Wars 2' | grep -q '^@error That is GW2 on Mac 0.1.s game'"
out=$(g install import "$O1C/Program Files/Guild Wars 2" --copy --confirm-path "$SANDBOX/o1-out/Guild Wars 2" --confirm-bytes 1153433614 2>&1) && rc=0 || rc=$?
check "    install import refuses it, even with a yes passed, and creates nothing" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error That is GW2 on Mac 0.1.s game.* Nothing changed\.$" && [ -z "$(ad_list)" ]'
check "    and the folder outside itself, where the link leads" sh -c "'$G' check-game '$SANDBOX/o1-out/Guild Wars 2' | grep -q '^@error That is GW2 on Mac 0.1.s game'"
out=$(g install import "$SANDBOX/o1-out/Guild Wars 2" --copy --confirm-path "$SANDBOX/o1-out/Guild Wars 2" --confirm-bytes 1153433614 2>&1) && rc=0 || rc=$?
check "    install import refuses that one too, and creates nothing" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error That is GW2 on Mac 0.1.s game" && [ -z "$(ad_list)" ]'
rm -f "$O1C/Program Files/Guild Wars 2"; rmdir "$O1C/Program Files"; rm -rf "$SANDBOX/o1-out"
out=$(g install import "$O1G" --copy --confirm-path "$O1G" --confirm-bytes 1153433614 2>&1) && rc=0 || rc=$?
check "install import of 0.1's game, a yes passed: refused, nothing created, 0.1's folders as they were" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error That is GW2 on Mac 0.1.s game.* Nothing changed\.$" && [ -z "$(ad_list)" ] && [ "$(o1sum)" = "$O1SUM" ]'
mkdir -p "$AD" && echo skipped >"$AD/moved-from-0.1"
check "  after Start fresh, it says to install the game anew" sh -c "'$G' check-game '$O1G' | grep -q '^@error .* Start fresh was chosen here, so install the game with Steam or ArenaNet.s installer\.$'"
rm -f "$AD/moved-from-0.1"
# a folder that is a link, and one with a link that leads out of it: refused
ln -s "$WHG" "$SANDBOX/to-whisky"
check "check-game refuses a game folder that is a link" sh -c "'$G' check-game '$SANDBOX/to-whisky' | grep -q '^@error $SANDBOX/to-whisky is a link or reached through one'"
rm -f "$SANDBOX/to-whisky"
ln -s "$WHG/Gw2.dat" "$WHG/Gw2.dat.link"
check "check-game refuses a game folder with a link in it, even one to a file inside" sh -c "'$G' check-game '$WHG' | grep -q '^@error $WHG/Gw2.dat.link is a link, so GW2 on Mac doesn.t copy the game folder it is in'"
rm -f "$WHG/Gw2.dat.link"
ln -s "$SANDBOX/shared-addons" "$CXG/addons"
check "check-game refuses a game folder with a link to a folder outside it" sh -c "'$G' check-game '$CXG' | grep -q '^@error $CXG/addons is a link, so'"
out=$(g install import "$CXG" --copy --confirm-path "$CXG" --confirm-bytes 1 2>&1) && rc=0 || rc=$?
check "  install import too, nothing created; the file it leads to is still there" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error $CXG/addons is a link" && [ -z "$(ad_list)" ] && same "$SANDBOX/pe/arcdps.dll" "$SANDBOX/shared-addons/arcdps/chain/d3d11.dll"'
check "  the scan leaves it out" eval '! g scan | grep -qF "$CXG"'
rm -f "$CXG/addons"
# (the links above came and went: the sources' snapshot again, for the checks below)
snap >"$SANDBOX/sources-before.txt"
# no copy without my yes to this folder at this size
CXB=$(g check-game "$CXG" | grep '^game' | cut -f4)
out=$(g install import "$CXG" 2>&1) && rc=0 || rc=$?
check "install import without a yes: refused with the size, nothing created" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac copies $CXG only after you say yes to it: it may take up to 3 GB on this disk\. Nothing changed\.$" && [ -z "$(ad_list)" ]'
out=$(g install import "$CXG" --copy --confirm-path "$CXG" --confirm-bytes "$((CXB - 1))" 2>&1) && rc=0 || rc=$?
check "  with a yes to another size (the folder changed since): refused, nothing created" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error The folder isn.t the one you said yes to, or it changed since" && [ -z "$(ad_list)" ]'
out=$(g install import "$CXG" --copy --confirm-path "$WHG" --confirm-bytes "$CXB" 2>&1) && rc=0 || rc=$?
check "  with a yes to another folder: refused, nothing created" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error The folder isn.t the one you said yes to" && [ -z "$(ad_list)" ]'
# the folder changes after the yes, while the install takes its first steps: checked again under the
# install lock right before the transfer, refused, and the failed install leaves nothing
IP="$SANDBOX/pause-import"
touch "$IP"
GW2_ON_MAC_TEST_PAUSE="$IP" GW2_ON_MAC_TEST_PAUSE_AT=locked gi "$WHG" >"$SANDBOX/import-changed.txt" 2>&1 & ip=$!
i=0; until [ -e "$IP.at" ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
echo "patched" >"$WHG/patch.txt"; rm -f "$IP"; wait "$ip"; rc=$?; rm -f "$IP.at" "$WHG/patch.txt"
check "the folder changed after the yes: refused under the lock before the copy, nothing left" \
  eval '[ "$rc" != 0 ] && has "$SANDBOX/import-changed.txt" "^@error $WHG isn.t the folder you said yes to, or it changed since" && [ -z "$(ad_list)" ]'
# (the folder changed and came back: the sources' snapshot again, for the checks below)
snap >"$SANDBOX/sources-before.txt"

# a Guild Wars 2 that runs (in another app): its files may change, so nothing is copied
mkdir -p "$SANDBOX/elsewhere" && cp "$SANDBOX/sleeper" "$SANDBOX/elsewhere/Gw2-64.exe"
"$SANDBOX/elsewhere/Gw2-64.exe" 60 & ep=$!
sleep 0.3
out=$(gi "$CXG" 2>&1) && rc=0 || rc=$?
check "install import refused while Guild Wars 2 runs elsewhere, nothing created" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error Guild Wars 2 is running" && [ ! -e "$AD/engine" ]'
kill $ep 2>/dev/null || true; wait $ep 2>/dev/null || true

out=$(GW2_ON_MAC_DRY_RUN=1 gi "$CXG" 2>&1) && rc=0 || rc=$?
check "dry-run install import: exits 0, would clone, creates nothing" eval '[ "$rc" = 0 ] && has <(echo "$out") "\[dry-run\] clone" && [ -z "$(ad_list)" ]'

: >"$STANDIN_LOG"
out=$(gi "$CXG" 2>&1) && rc=0 || rc=$?
GDI="$STEAM/steamapps/common/Guild Wars 2"
check "install import (CrossOver's Steam install) exits 0" [ "$rc" = 0 ]
check "  the phases 1-5 (engine, bottle, Steam, the files, finishing)" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 @phase 4 @phase 5 " ]
check "  cloned: the same disk" has <(echo "$out") "Cloning the game's files"
check "  route=steam origin=import stage=finished game=yes" [ "$(st route origin stage game)" = steam/import/finished/yes ]
check "  the game's files in the bottle's Steam library" eval '[ -f "$GDI/Gw2-64.exe" ] && [ "$(stat -f %z "$GDI/Gw2.dat")" = 2147483648 ] && has "$GDI/bin64/CoherentUI64.dll" bin'
check "  Steam's record of them, as it was" same "$CX/Program Files (x86)/Steam/steamapps/appmanifest_1284210.acf" "$STEAM/steamapps/appmanifest_1284210.acf"
check "  Steam installed, not started for an install" eval '[ "$(st steam)" = yes ] && ! grep -q "steam://install" "$STANDIN_LOG"'
check "  our own addon left out (version.dll, gw2-ui-scale.ini)" eval '[ ! -e "$GDI/version.dll" ] && [ ! -e "$GDI/gw2-ui-scale.ini" ]'
check "  another program's d3d11.dll left out, and the summary says so" eval '[ ! -e "$GDI/d3d11.dll" ] && has <(echo "$out") "^@done .*Another program.s d3d11.dll stayed behind\."'
check "  another addon (not arcdps) came along, and the summary names it" eval 'same "$CXG/dxgi.dll" "$GDI/dxgi.dll" && has <(echo "$out") "^@done .*Addons that came along: dxgi.dll"'
check "  its ReShade.ini stayed behind, the summary says so; its presets and shaders came along" eval '[ ! -e "$GDI/ReShade.ini" ] && has <(echo "$out") "^@done .*ReShade stayed behind: turn it on in Settings › Interface." && has <(echo "$out") "^ReShade stayed behind in $CXG (ReShade.ini)" && same "$CXG/ReShadePreset.ini" "$GDI/ReShadePreset.ini" && same "$CXG/reshade-shaders/Shaders/Mine.fx" "$GDI/reshade-shaders/Shaders/Mine.fx"'
check "  the game's settings in the bottle" eval 'same "$CXS/Local.dat" "$BS/Local.dat" && same "$CXS/GFXSettings.Gw2-64.exe.xml" "$BS/GFXSettings.Gw2-64.exe.xml"'
check "  the summary: cloned, with the settings" has <(echo "$out") "^@done Guild Wars 2 is ready: its files were cloned from CrossOver · Steam GW2, with your game settings"
check "  the source is unchanged" sources_unchanged
c=$(play_cmd); check "  Play: Steam (no login in this bottle yet: its window)" eval '[[ "$c" == *"steam.exe -applaunch 1284210"* && "$c" != *-silent* ]]'
check "  uninstall" sh -c "'$G' uninstall | grep -q '@done'"
check "  the source is still unchanged" sources_unchanged

# into an earlier run's bottle, whose own settings go to a backup folder
g install steam >/dev/null 2>&1; g stop-waiting >/dev/null
mkdir -p "$BS" && echo "the bottle's own" >"$BS/Local.dat"
backup_kept() { local f; for f in "$BS"/"$APP_FOLDER backup "*/Local.dat; do has "$f" "the bottle's own" && return 0; done; return 1; }
: >"$STANDIN_LOG"
out=$(gi "$WRAP" 2>&1) && rc=0 || rc=$?
check "install import of the wrapper's (ArenaNet) into the earlier bottle exits 0" [ "$rc" = 0 ]
check "  the phases 1-4 (engine, bottle, the files, finishing)" [ "$(echo "$out" | grep '^@phase' | tr '\n' ' ')" = "@phase 1 @phase 2 @phase 3 @phase 4 " ]
check "  route=arenanet origin=import game=yes, in Program Files" eval 'ST_OUT=$(g status); [ "$(kv "$ST_OUT" route origin game)" = arenanet/import/yes ] && [ "$(kv "$ST_OUT" game_dir)" = "$BOTTLE/drive_c/Program Files/Guild Wars 2" ]'
check "  its settings in the bottle" same "$WRS/Local.dat" "$BS/Local.dat"
check "  its lone ReShade.ini stayed behind, and the summary says so" eval '[ ! -e "$BOTTLE/drive_c/Program Files/Guild Wars 2/ReShade.ini" ] && has <(echo "$out") "^@done .*ReShade stayed behind"'
check "  the bottle's own kept in a backup folder" backup_kept
g play >/dev/null 2>&1; started
check "  Play starts the game's own launcher" has "$STANDIN_LOG" 'wine C:\\Program Files\\Guild Wars 2\\Gw2-64.exe'
g uninstall >/dev/null 2>&1

out=$(gi "$WHG" --no-settings 2>&1) && rc=0 || rc=$?
check "install import --no-settings (Whisky's) exits 0" [ "$rc" = 0 ]
check "  no game settings brought" eval '[ ! -e "$BS/Local.dat" ] && ! has <(echo "$out") "with your game settings"'
check "  its ReShade (d3d11.dll) stayed behind, and the summary says so" eval '[ ! -e "$BOTTLE/drive_c/Program Files/Guild Wars 2/d3d11.dll" ] && has <(echo "$out") "^@done .*ReShade stayed behind" && ! has <(echo "$out") "Addons that came along"'
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
  out=$(gi "$OG" 2>&1) && rc=0 || rc=$?
  check "install import from another disk exits 0: copied, with progress" eval '[ "$rc" = 0 ] && has <(echo "$out") "Copying the game" && has <(echo "$out") "^@progress Guild Wars 2 " && has <(echo "$out") "^@done .*copied from"'
  check "  the copy is complete" eval '[ "$(st game)" = yes ] && [ "$(stat -f %z "$BOTTLE/drive_c/Program Files/Guild Wars 2/Gw2.dat")" = "$(stat -f %z "$OG/Gw2.dat")" ]'
  g uninstall >/dev/null 2>&1
  hdiutil detach -quiet -force "$VOL" >/dev/null 2>&1; trap - EXIT
else
  echo "  skip the disk image (hdiutil could not attach one); the forced copy below covers the copy"
fi
out=$(GW2_ON_MAC_IMPORT_COPY=1 gi "$WHG" 2>&1) && rc=0 || rc=$?
check "install import, copy forced: exits 0, copied with progress" eval '[ "$rc" = 0 ] && has <(echo "$out") "Copying the game" && has <(echo "$out") "^@progress Guild Wars 2 "'
check "  the copy is complete, without Whisky's ReShade" eval '[ "$(st game)" = yes ] && [ "$(stat -f %z "$BOTTLE/drive_c/Program Files/Guild Wars 2/Gw2.dat")" = 1153433600 ] && [ ! -e "$BOTTLE/drive_c/Program Files/Guild Wars 2/d3d11.dll" ]'
g uninstall >/dev/null 2>&1
out=$(GW2_ON_MAC_IMPORT_COPY=1 GW2_ON_MAC_FREE_KB=3020000 gi "$CXG" 2>&1) && rc=0 || rc=$?
check "a copy without the free space is refused" eval '[ "$rc" != 0 ] && has <(echo "$out") "@error Not enough free disk space to copy the game"'
check "  and leaves nothing behind" eval '[ ! -e "$AD/engine" ] && [ ! -e "$AD/bottle" ] && [ ! -e "$AD/state" ] && [ ! -e "$AD/.lock" ]'
check "the sources never changed" sources_unchanged
check "0.1's folders: still the same checksum" [ "$(o1sum)" = "$O1SUM" ]
fi

if in_group move; then
section "Move GW2 on Mac 0.1's install (install move), its fixture and the checks' own checks"
# GW2 on Mac 0.1.4's install as its folders hold it (main's gw2om.sh): a manifest, its state and
# settings, an engine, a bottle whose Windows user is crossover with Steam (its login, config and
# userdata) and the game in Steam's library, or the game in Program Files (ArenaNet's route); the
# game's settings and Steam's files in the profile; the addons in the game folder, arcdps alone
# as d3d11.dll or with ReShade, then at ReShade's chain path; the ReShade folder outside the bottle,
# its ini naming 0.1's folders, and the record of the compiler 0.1 placed.
OC="$H/Library/Caches/GW2 on Mac"
# (this app's folder empty, as on a Mac that had only 0.1: the sections before leave files in it;
# and install.log begun anew, since an import before may have cloned these same 0.1 folders, which
# no_cp_of must not count against the move)
rm -rf "$AD"
: >"$LOGS/install.log"
O1B="$O1/bottle" O1ST="$O1/bottle/drive_c/Program Files (x86)/Steam" O1U="$O1/bottle/drive_c/users/crossover"
O1RS="$O1/ReShade"
winp() { printf 'Z:%s' "$1" | tr / '\\'; }
ARC_CHAIN=addons/arcdps/chain/d3d11.dll CHAINW='addons\arcdps\chain\d3d11.dll'
GW2_ON_MAC_RESHADE_DLL_SHA256="$(shasum -a 256 "$SANDBOX/pe/ReShade64.dll" | cut -d' ' -f1)"
export GW2_ON_MAC_RESHADE_DLL_SHA256
# every one of 0.1.4's keys off its default (reshade on, with the "both" layout), and the values a
# move gives them here (SETTINGS_FROM_01: kept, this version's default, or dropped)
OLD_SET="retina=off fpscap=40 metalfx=on hud=on warm=off coolworkers=3 fastlocks=on ncpu=2 uiscale=on uiscale_size=2.0 uiscale_sans=off uiscale_cinema=off gamemode=off launchopts=-maploadinfo rawmouse=off mousespeed=1.5 updates=off debug=on steambg=off quitsteam=off reshade=on"
FROM01=$(sed -n '/^SETTINGS_FROM_01="$/,/^"$/p' "$APP/Contents/Resources/gw2om.sh" | awk 'NF >= 2 { print $1, $2 }')
old01() { # <steam|arenanet> <arcdps|both> [<settings.conf lines>]
  local g k
  rm -rf "$O1" "$OC"
  mkdir -p "$O1/engine/bin" "$O1/engine/lib/wine/x86_64-unix" "$O1B/drive_c/windows" "$O1U/AppData/Local/Steam" \
    "$O1U/AppData/Roaming/Guild Wars 2/Screens" "$O1/gamemode/GW2.app/Contents/MacOS" "$OC/reshade" "$OC/dxmt/Gw2-64.exe"
  echo "0.1's loader" >"$O1/engine/lib/wine/x86_64-unix/wine"
  printf '{\n  "app": "GW2 on Mac",\n  "version": "0.1.4"\n}\n' >"$O1/install-manifest.json"
  printf 'WINE REGISTRY Version 2\n' >"$O1B/system.reg" && cp "$O1B/system.reg" "$O1B/user.reg"
  echo "0.1's local.vdf" >"$O1U/AppData/Local/Steam/local.vdf"
  echo "0.1 local.dat" >"$O1U/AppData/Roaming/Guild Wars 2/Local.dat"
  echo "<GSA_SDK 0.1/>" >"$O1U/AppData/Roaming/Guild Wars 2/GFXSettings.Gw2-64.exe.xml"
  echo "JPG" >"$O1U/AppData/Roaming/Guild Wars 2/Screens/gw001.jpg"
  echo "0.1's shaders" >"$OC/dxmt/Gw2-64.exe/shaders.bin" && echo "compiled" >"$OC/reshade/effect.bin"
  if [ "$1" = steam ]; then
    g="$O1ST/steamapps/common/Guild Wars 2"
    mkdir -p "$g" "$O1ST/config" "$O1ST/userdata/12345/config"
    echo "0.1's steam" >"$O1ST/steam.exe"
    printf '"users"\n{\n\t"76561190000000000"\n\t{\n\t\t"AccountName"\t\t"someone"\n\t\t"RememberPassword"\t\t"1"\n\t}\n}\n' >"$O1ST/config/loginusers.vdf"
    echo "0.1's config.vdf" >"$O1ST/config/config.vdf" && echo "0.1's localconfig" >"$O1ST/userdata/12345/config/localconfig.vdf"
    printf '"AppState"\n{\n\t"appid"\t\t"1284210"\n\t"installdir"\t\t"Guild Wars 2"\n\t"StateFlags"\t\t"4"\n}\n' >"$O1ST/steamapps/appmanifest_1284210.acf"
    printf 'route=steam\nstage=finished\ngame_dir=%s\ngame_exe=\norigin=download\n' "$g" >"$O1/state"
  else
    g="$O1B/drive_c/Program Files/Guild Wars 2"
    mkdir -p "$g"
    printf 'route=arenanet\nstage=finished\ngame_dir=%s\ngame_exe=\norigin=download\n' "$g" >"$O1/state"
  fi
  O1GAME=$g
  echo "stand-in game" >"$g/Gw2-64.exe" && mkfile -n 1100m "$g/Gw2.dat"
  mkdir -p "$g/addons/arcdps" && echo "[session]" >"$g/addons/arcdps/arcdps.ini"
  cp "$COMP/ui-scale/version.dll" "$g/version.dll" && echo "0.1's" >>"$g/version.dll" && echo "scale=1.5" >"$g/gw2-ui-scale.ini"
  if [ "$2" = arcdps ]; then
    cp "$SANDBOX/pe/arcdps.dll" "$g/d3d11.dll"
  else
    cp "$SANDBOX/pe/ReShade64.dll" "$g/d3d11.dll"
    mkdir -p "$g/addons/arcdps/chain" && cp "$SANDBOX/pe/arcdps.dll" "$g/$ARC_CHAIN"
    echo "0.1's compiler" >"$g/d3dcompiler_47.dll" && shasum -a 256 "$g/d3dcompiler_47.dll" | cut -d' ' -f1 >"$O1/reshade-compiler"
    printf '[INSTALL]\nBasePath=%s\n' "$(winp "$O1RS")" >"$g/ReShade.ini"
    mkdir -p "$O1RS/Presets" "$O1RS/Shaders/Standard" "$O1RS/Textures" "$O1RS/Screenshots"
    printf '[GENERAL]\nEffectSearchPaths=.\\Shaders\\**\nPresetPath=.\\Presets\\Mine.ini\nIntermediateCachePath=%s\n\n[PROXY]\nEnableProxyLibrary=1\nProxyLibrary=C:\\%s\\%s\n\n[SCREENSHOT]\nSavePath=%s\\Screenshots\n' \
      "$(winp "$OC/reshade")" "$(printf %s "${g#"$O1B/drive_c/"}" | tr / '\\')" "$CHAINW" "$(winp "$O1RS")" >"$O1RS/ReShade.ini"
    echo "[Mine]" >"$O1RS/Presets/Mine.ini" && echo "// fxh" >"$O1RS/Shaders/Standard/ReShade.fxh"
    # (on the ArenaNet route its ini is a link to a file beside it, as a player may keep one)
    if [ "$1" = arenanet ]; then mv "$O1RS/ReShade.ini" "$O1RS/Mine-settings.ini" && ln -s Mine-settings.ini "$O1RS/ReShade.ini"; fi
  fi
  if [ -n "${3+x}" ]; then printf '%s' "$3" >"$O1/settings.conf"
  else
    { echo "# GW2 on Mac settings"; for k in $OLD_SET; do
        case "$2 $k" in "arcdps reshade="*) echo reshade=off ;; *) echo "$k" ;; esac
      done; } >"$O1/settings.conf"
  fi
}
# 0.1's folders, <folder> left out: every file's size, mtime, mode and content, and every folder's
# mode (a rename out of a folder and back changes its mtime, nothing else)
o1snap() {
  local x=${1:-$SANDBOX/no-such-folder}
  { find "$O1" "$OC" -path "$x" -prune -o -type d -exec stat -f 'd %N %p' {} +
    find "$O1" "$OC" -path "$x" -prune -o ! -type d -exec stat -f 'f %N %z %m %p' {} +
    find "$O1" "$OC" -path "$x" -prune -o -type f -exec shasum -a 256 {} +; } | LC_ALL=C sort
}
o1_same() { [ "$(o1snap)" = "$O1SNAP" ]; }
# o1_rest_same <folder>: 0.1's folders as they were but for <folder>, which the move renamed
o1_rest_same() { [ "$(o1snap "$1")" = "$(printf '%s\n' "$O1SNAP" | awk -v x="$1" '!index($0, x)')" ]; }
# ino <path>: its inode (a rename keeps it, a copy doesn't)
ino() { stat -f %i "$1"; }
# no_cp_of <folder>...: install.log (or NOCP_LOG) has no cp or mv of these folders, which could be a
# copy, only renames (the log's "+ cp", "+ mv" lines quote paths as printf %q does)
no_cp_of() {
  local f
  for f in "$@"; do
    Q=" $(printf '%q' "$f")" awk '/^\+ (cp|mv) / && (index($0, ENVIRON["Q"] " ") || substr($0, length($0) - length(ENVIRON["Q"]) + 1) == ENVIRON["Q"]) { f = 1 } END { exit f }' "${NOCP_LOG:-$LOGS/install.log}" || return 1
  done
}
# (the check itself: a cp of 0.1's Steam folder in a log is found, at the end of a line or not)
NOCP_LOG="$SANDBOX/nocp.log"
printf '+ cp -Rpc %q %q\n' "$H/Library/Application Support/GW2 on Mac/bottle/drive_c/Program Files (x86)/Steam" /x >"$NOCP_LOG"
check "no_cp_of finds a logged cp of a folder with spaces and parentheses in its path" \
  eval '! no_cp_of "$H/Library/Application Support/GW2 on Mac/bottle/drive_c/Program Files (x86)/Steam" && no_cp_of "$H/Library/Application Support/GW2 on Mac/bottle/drive_c/Program Files (x86)/Stea"'
printf '+ mv /y %q\n' "$H/a b/(c)" >"$NOCP_LOG"
check "  and a logged mv at the end of a line" eval '! no_cp_of "$H/a b/(c)"'
unset NOCP_LOG
# every recursive removal goes through safe_rm, which leaves a folder with a game in it
rm_outside() {
  awk '/^safe_rm\(\) \{/ { f = 1 } f && /^}/ { f = 0; next }
    !f && !/^[[:space:]]*#/ && /(^|[^[:alnum:]_-])rm([[:space:]]+-[[:alpha:]]+)*[[:space:]]+-[[:alpha:]]*[rR]/ { print FNR ": " $0; n++ } END { exit n > 0 }' "$1"
}
check "gw2om.sh has no recursive rm outside safe_rm" rm_outside "$APP/Contents/Resources/gw2om.sh"
{ cat "$APP/Contents/Resources/gw2om.sh"; printf '  rm -fr "$x"\n  rm -f -r "$x"\n  x && rm -R "$y"\n  rm\t-f\t-r "$x"\n'; } >"$SANDBOX/rmcheck.sh"
check "  (the check finds each of rm -fr, rm -f -r, rm -R and a tab-separated one added)" eval '[ "$(rm_outside "$SANDBOX/rmcheck.sh" | wc -l | tr -d " ")" = 4 ]'
# (the session's lock file stays, held or not: a lock file is never removed while anyone may hold it)
nothing_made() { [ -z "$(ad_list)" ]; }
# ini_clean <file>: no line names 0.1's folders (Application Support's or Caches' GW2 on Mac)
ini_clean() { ! grep -iqF -e "$(winp "$O1")\\" -e "$(winp "$OC")\\" "$1" && ! grep -iqE "$(winp "$O1" | sed 's/\\/\\\\/g')$" "$1"; }
# settings_moved: this app's settings.conf as SETTINGS_FROM_01 says for the OLD_SET file, key by key
settings_moved() {
  local k how want got now defaults
  # (this app's settings and the defaults, each read once for every key)
  now=$(g settings) defaults=$(GW2_ON_MAC_ROOT="$SANDBOX/nowhere-root" "$GW2OM" settings)
  printf '%s\n' "$FROM01" | while read -r k how; do
    case " $OLD_SET " in *" $k="*) ;; *) echo "OLD_SET has no $k"; return 1 ;; esac
    want=$(printf '%s\n' $OLD_SET | sed -n "s/^$k=//p")
    got=$(kv "$now" "$k")
    case "$how" in
      kept) [ "$got" = "$want" ] || { echo "$k: $got, not $want"; return 1; } ;;
      default) [ "$got" = "$(kv "$defaults" "$k")" ] || { echo "$k: $got, not the default"; return 1; } ;;
      dropped) ! grep -q "^$k=" "$AD/settings.conf" || [ "$k" = gamemode ] || { echo "$k is in settings.conf"; return 1; } ;;
      *) echo "$k: $how?"; return 1 ;;
    esac
  done
}
mv_done() { echo "$out" | sed -n 's/^@done //p'; }

section "Below the engine's macOS nothing is written (macOS 26.4.1, over 0.1's install)"
# (this app's three folders out of the way, back after this section)
mv "$LOGS" "$LOGS.aside" 2>/dev/null; mv "$CACHE" "$CACHE.aside" 2>/dev/null
old01 steam both
O1SNAP=$(o1snap) O1INO="$(ino "$O1ST") $(ino "$O1GAME") $(ino "$O1B")"
GATE_ERR="@error $APP_NAME needs macOS 26.5 or later for its Wine engine. This Mac has macOS 26.4.1. Update macOS in System Settings › General › Software Update, then try again."
echo "[Mine]" >"$SANDBOX/gate-preset.ini"
# every command that writes, each refused with preflight's sentence and nothing else
gate_out=""
while IFS= read -r c; do
  # shellcheck disable=SC2086 # (the command and its arguments, one word each)
  out=$(GW2_ON_MAC_MACOS=26.4.1 "$G" $c 2>&1 </dev/null) && rc=0 || rc=$?
  [ "$rc" != 0 ] && [ "$out" = "$GATE_ERR" ] || gate_out="$gate_out [$c: $rc $out]"
done <<GATE
install steam
install move
install arenanet $SANDBOX/gate-preset.ini
install import $SANDBOX
check-setup $SANDBOX/gate-preset.ini
finish
stop-waiting
repair
uninstall
start-fresh
start-fresh --before-move
rollback
recover
move-in
play
watch-session
show-steam
set fpscap 60
set arcdps on
set reshade on
reshade import $SANDBOX/gate-preset.ini
reshade use Mine.ini
reset-shaders
reinstall-engine
end-leftovers
fetch-engine
vmmap
GATE
check "every command that writes is refused, with preflight's sentence only" eval '[ -z "$gate_out" ] || { echo "$gate_out"; false; }'
# (and what only reads answers: status sees 0.1's install and names the last 0.1.x's DMG)
for c in settings session-status scan rules env; do GW2_ON_MAC_MACOS=26.4.1 "$G" $c >/dev/null 2>&1; done
out=$(GW2_ON_MAC_MACOS=26.4.1 "$G" status 2>&1)
V=$(echo "$out" | sed -n 's/^rollback_version=//p')
check "status answers: macos_ok=no, 0.1's install to move, the last 0.1.x and its DMG" \
  eval 'echo "$out" | grep -qx macos_ok=no && echo "$out" | grep -qx move=yes && echo "$V" | grep -qx "0\.1\.[0-9]*" &&
    echo "$out" | grep -qxF "rollback_dmg=https://github.com/jdrly/gw2-on-mac/releases/download/v$V/GW2-on-Mac-$V.dmg"'
check "  and none of the app's three folders exists afterwards" eval '[ ! -e "$AD" ] && [ ! -e "$LOGS" ] && [ ! -e "$CACHE" ]'
check "  0.1's install as it was: the same inodes, every file the same, no move record" \
  eval '[ "$(ino "$O1ST") $(ino "$O1GAME") $(ino "$O1B")" = "$O1INO" ] && o1_same && [ ! -e "$AD/moved-from-0.1" ]'
rm -f "$SANDBOX/gate-preset.ini"
mv "$LOGS.aside" "$LOGS" 2>/dev/null; mv "$CACHE.aside" "$CACHE" 2>/dev/null
mkdir -p "$LOGS" && : >"$LOGS/install.log"

section "Move GW2 on Mac 0.1's install (install move), the move"
old01 steam both
check "status: 0.1's install, to move (the Steam route, nothing of 0.1 runs)" \
  [ "$(st old_install move move_route move_busy)" = yes/yes/steam/none ]
# 0.1's processes, a sleeper at each place 0.1's proc_list counts: its Steam, the game as the Game
# Mode bundle's copy of the loader, the stock wineserver kept next to mine, and the game through a
# winetemp link of the loader
WT="$SANDBOX/T/winetemp-$(stat -f '%i-%z' "$O1/engine/lib/wine/x86_64-unix/wine")-x"
mkdir -p "$WT"
O1SNAP=$(o1snap)
for p in "$O1/engine/bin/steam.exe:steam" "$O1/gamemode/GW2.app/Contents/MacOS/Gw2-64.exe:game" \
  "$O1/engine/bin/wineserver.stock:session" "$WT/Gw2-64.exe:game"; do
  f=${p%:*} k=${p##*:}
  cp "$SANDBOX/sleeper" "$f"
  "$f" 30 & sp=$!
  sleep 0.3
  out=$(g install move 2>&1) && rc=0 || rc=$?
  check "  $k of 0.1 runs ($(basename "$f")): status says so, the move is refused with why, nothing made" \
    eval 'ST_OUT=$(g status); [ "$(kv "$ST_OUT" move_busy)" = "$k" ] && [ -n "$(kv "$ST_OUT" move_wait)" ] && [ "$rc" != 0 ] && has <(echo "$out") "^@error $(kv "$ST_OUT" move_wait | sed "s/[().]/./g")" && nothing_made'
  kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null; rm -f "$f"
done
out=$(g start-fresh --before-move 2>&1) && rc=0 || rc=$?
check "Start fresh before the move: the move no longer starts by itself, nothing else made" \
  eval '[ "$rc" = 0 ] && [ "$(st move move_record)" = no/skipped ] && [ "$(ad_list)" = moved-from-0.1 ]'
rm -f "$AD/moved-from-0.1"
check "  Steam's sentence names 0.1 and says to quit Steam there" \
  eval 'cp "$SANDBOX/sleeper" "$O1/engine/bin/steam.exe" && { "$O1/engine/bin/steam.exe" 30 & sp=$!; sleep 0.3; w=$(st move_wait); kill $sp; wait $sp 2>/dev/null; rm -f "$O1/engine/bin/steam.exe"; [ "$w" = "Steam is running in GW2 on Mac 0.1. Quit Steam there (Steam > Exit), and the move starts." ]; }'
O1SNAP=$(o1snap)

out=$(GW2_ON_MAC_DRY_RUN=1 g install move 2>&1) && rc=0 || rc=$?
check "dry-run install move: exits 0, makes nothing; every Wine call as crossover; it would rename Steam's folder" \
  eval '[ "$rc" = 0 ] && nothing_made && echo "$out" | grep -qxF "[dry-run] wine (USER=crossover) wineboot --init" && ! echo "$out" | grep "^\[dry-run\] wine " | grep -qv "(USER=crossover)" && has <(echo "$out") "^\[dry-run\] rename $O1ST to "'

# a failure at each step, and a cancel after the rename: Steam's folder back in 0.1's bottle (the
# same inode), with the addon files 0.1 had; nothing of the move stays, 0.1 as it was
O1INO=$(ino "$O1ST")
for p in engine settings bottle steam files profile reshade finish; do
  out=$(GW2_ON_MAC_MOVE_FAIL=$p g install move 2>&1) && rc=0 || rc=$?
  check "the move failing at $p leaves nothing, and 0.1 as it was" \
    eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error The move failed at $p" && nothing_made && o1_same && [ "$(ino "$O1ST")" = "$O1INO" ] && [ "$(st move)" = yes ]'
done
PAUSE="$SANDBOX/pause"
# move_paused <signal> <command...>: the command stopped by <signal> at the pause it names
# (paused: yes when it got to the pause before the signal; rc: its exit status)
move_paused() {
  local sig=$1; shift
  touch "$PAUSE"
  GW2_ON_MAC_TEST_PAUSE="$PAUSE" "$@" >"$SANDBOX/cancel.txt" 2>&1 & mp=$!
  i=0; until [ -e "$PAUSE.at" ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
  if [ -e "$PAUSE.at" ]; then paused=yes; else paused=no; fi
  kill "-$sig" "$mp" 2>/dev/null; rm -f "$PAUSE"; wait "$mp"; rc=$?
  rm -f "$PAUSE.at"
}
# TERM (a cancel) and KILL (a crash) before the rename and after it: the game back in 0.1's place
# (the same inode), nothing of the move left, 0.1 as it was. After a KILL the next status, or the
# next command that takes the install lock, undoes the move before it removes anything.
move_paused TERM env GW2_ON_MAC_TEST_PAUSE_AT=move-before-rename "$GW2OM" install move
check "a move cancelled before the rename (TERM): nothing left, 0.1 as it was" \
  eval '[ "$paused $rc" = "yes 143" ] && nothing_made && o1_same && [ "$(ino "$O1ST")" = "$O1INO" ]'
move_paused KILL env GW2_ON_MAC_TEST_PAUSE_AT=move-before-rename "$GW2OM" install move
check "a move killed before the rename: its record of the move is there, the game in 0.1's place" \
  eval '[ "$paused $rc" = "yes 137" ] && [ -f "$AD/move-undo" ] && [ "$(ino "$O1ST")" = "$O1INO" ]'
out=$(g uninstall 2>&1) || true
check "  then Uninstall: what the move made goes, 0.1 as it was" \
  eval '[ ! -e "$AD/move-undo" ] && [ ! -e "$BOTTLE" ] && o1_same && [ "$(ino "$O1ST")" = "$O1INO" ]'
rm -rf "$AD"
move_paused TERM env GW2_ON_MAC_TEST_PAUSE_AT=move-renamed "$GW2OM" install move
check "a move cancelled after the rename (TERM) renames it back, leaves nothing, 0.1 as it was" \
  eval '[ "$paused $rc" = "yes 143" ] && nothing_made && o1_same && [ "$(ino "$O1ST")" = "$O1INO" ]'
move_paused KILL env GW2_ON_MAC_TEST_PAUSE_AT=move-renamed "$GW2OM" install move
check "a move killed after the rename: Steam's folder is in the new bottle, the record of the move beside it" \
  eval '[ "$paused $rc" = "yes 137" ] && [ ! -e "$O1ST" ] && [ "$(ino "$BOTTLE/drive_c/Program Files (x86)/Steam")" = "$O1INO" ] && [ -f "$AD/move-undo" ]'
check "  the next status renames it back and removes what the move made: 0.1 as it was, the move ready again" \
  eval '[ "$(st move)" = yes ] && nothing_made && o1_same && [ "$(ino "$O1ST")" = "$O1INO" ]'
# another disk (forced, then a real one: a disk image mounted where 0.1's Program Files (x86) is),
# and a link on the way (0.1's Steam folder, or a folder above it on the same disk): refused before
# anything is written, the logs untouched too
logstamp() { stat -f '%z %m' "$LOGS/install.log" 2>/dev/null; }
LST=$(logstamp)
out=$(GW2_ON_MAC_IMPORT_COPY=1 g install move 2>&1) && rc=0 || rc=$?
check "0.1's Steam folder on another disk (forced): refused, nothing written, 0.1 as it was" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac 0.1.s Steam folder is on another disk .* never by copying it, so nothing changed" && nothing_made && [ "$(logstamp)" = "$LST" ] && o1_same'
PF="$O1B/drive_c/Program Files (x86)"
mv "$PF" "$PF.away" && mkdir "$PF"
if hdiutil create -quiet -size 4g -type SPARSE -fs APFS -volname gw2om-o1 "$SANDBOX/o1vol" >/dev/null 2>&1 &&
  hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$PF" "$SANDBOX/o1vol.sparseimage" >/dev/null 2>&1; then
  trap 'hdiutil detach -quiet -force "$PF" 2>/dev/null' EXIT
  rsync -a --exclude Gw2.dat "$PF.away/" "$PF/" && mkfile -n 1100m "$PF/Steam/steamapps/common/Guild Wars 2/Gw2.dat"
  out=$(g install move 2>&1) && rc=0 || rc=$?
  check "0.1's Steam folder on another volume (a disk image mounted in 0.1's bottle, no link): refused, nothing written" \
    eval '[ "$(st old_install)" = yes ] && [ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac 0.1.s Steam folder is on another disk" && nothing_made && [ "$(logstamp)" = "$LST" ] && [ -f "$PF/Steam/steam.exe" ]'
  hdiutil detach -quiet -force "$PF" >/dev/null 2>&1; trap - EXIT
else
  echo "  skip the disk image (hdiutil could not attach one); the forced refusal above covers the branch"
fi
rmdir "$PF" && mv "$PF.away" "$PF"
check "  0.1 as it was" o1_same
mv "$O1ST" "$SANDBOX/linked-steam" && ln -s "$SANDBOX/linked-steam" "$O1ST"
out=$(g install move 2>&1) && rc=0 || rc=$?
check "0.1's Steam folder as a link: refused, nothing written" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac 0.1.s Steam folder is on another disk .*or reached through a link" && nothing_made'
rm "$O1ST" && mv "$SANDBOX/linked-steam" "$O1ST"
mv "$PF" "$SANDBOX/linked-pf86" && ln -s "$SANDBOX/linked-pf86" "$PF"
out=$(g install move 2>&1) && rc=0 || rc=$?
check "0.1's Program Files (x86) as a link on the same disk: refused, nothing written" \
  eval '[ "$(st old_install)" = yes ] && [ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac 0.1.s Steam folder is on another disk .*or reached through a link" && nothing_made'
rm "$PF" && mv "$SANDBOX/linked-pf86" "$PF"
check "  0.1 as it was" o1_same
# the game folder's ReShade.ini as a link to a file beside it: refused before the rename (Rollback
# couldn't put the file it leads to back), 0.1 as it was
mv "$O1GAME/ReShade.ini" "$O1GAME/Mine.ini" && ln -s Mine.ini "$O1GAME/ReShade.ini"
O1SNAP=$(o1snap)
out=$(g install move 2>&1) && rc=0 || rc=$?
check "a ReShade.ini in the game folder that is a link: refused, nothing left, 0.1 as it was" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error .*ReShade.ini is a link, so GW2 on Mac couldn.t put GW2 on Mac 0.1.s addon files back" && nothing_made && o1_same && [ "$(ino "$O1ST")" = "$O1INO" ]'
rm "$O1GAME/ReShade.ini" && mv "$O1GAME/Mine.ini" "$O1GAME/ReShade.ini"
O1SNAP=$(o1snap)
# a game folder that is a link (out of 0.1's bottle): refused before the rename, nothing written
# through it
mv "$O1GAME" "$SANDBOX/linked-game" && ln -s "$SANDBOX/linked-game" "$O1GAME"
LSNAP=$(find "$SANDBOX/linked-game" -exec stat -f '%N %z %m %p' {} + | LC_ALL=C sort)
out=$(g install move 2>&1) && rc=0 || rc=$?
check "a game folder that is a link: refused, nothing written through it, nothing left" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error .*Guild Wars 2 is a link or reached through one, so GW2 on Mac doesn.t move this install" && nothing_made && [ "$(find "$SANDBOX/linked-game" -exec stat -f "%N %z %m %p" {} + | LC_ALL=C sort)" = "$LSNAP" ]'
rm "$O1GAME" && mv "$SANDBOX/linked-game" "$O1GAME"
# a link into 0.1's ReShade folder inside its Steam folder: refused after the rename, nothing left
ln -s "$O1RS" "$O1ST/linked-reshade"
O1SNAP=$(o1snap)
out=$(g install move 2>&1) && rc=0 || rc=$?
check "a link into 0.1's folders inside its Steam folder: refused, nothing left, 0.1 as it was" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error .*linked-reshade is a link to a folder or out of the files the move brought" && nothing_made && o1_same'
rm "$O1ST/linked-reshade"
# 0.1's ReShade folder's screenshots on another disk, which 0.1 writes too: refused, nothing left
mkdir -p "$SANDBOX/ext-shots" && rmdir "$O1RS/Screenshots" && ln -s "$SANDBOX/ext-shots" "$O1RS/Screenshots"
O1SNAP=$(o1snap)
out=$(g install move 2>&1) && rc=0 || rc=$?
check "a link in 0.1's ReShade folder to a folder elsewhere: refused, nothing left, 0.1 as it was" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error .*Screenshots is a link to a folder or out of the files the move brought" && nothing_made && o1_same && [ -z "$(ls -A "$SANDBOX/ext-shots")" ]'
rm "$O1RS/Screenshots" && mkdir "$O1RS/Screenshots"
# a link to a folder inside the clone (Screenshots to Presets): refused too, since what is in a
# linked folder isn't looked through
rmdir "$O1RS/Screenshots" && ln -s Presets "$O1RS/Screenshots"
O1SNAP=$(o1snap)
out=$(g install move 2>&1) && rc=0 || rc=$?
check "a link to a folder beside it in 0.1's ReShade folder: refused, nothing left, 0.1 as it was" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error .*Screenshots is a link to a folder or out of the files the move brought" && nothing_made && o1_same'
rm "$O1RS/Screenshots" && mkdir "$O1RS/Screenshots"
O1SNAP=$(o1snap)

: >"$STANDIN_LOG"
GDINO=$(ino "$O1GAME/Gw2.dat")
# (TERM and KILL once the move's record is written: the move is done and stays; then Rollback and
# Uninstall, for the move below)
for p in "TERM move-done" "KILL move-done" "TERM move-retired"; do
  sig=${p% *}
  move_paused "$sig" env GW2_ON_MAC_TEST_PAUSE_AT="${p#* }" "$GW2OM" install move
  check "a move stopped ($p: after its record is written) keeps the move: installed, the game here" \
    eval '[ "$paused" = yes ] && [ "$rc" = "$([ "$sig" = TERM ] && echo 143 || echo 137)" ] && [ "$(st installed move_game)" = yes/here ] && [ ! -e "$AD/move-undo" ] && [ "$(ino "$STEAM")" = "$O1INO" ] && [ -f "$GD/Gw2.dat" ]'
  g rollback >/dev/null 2>&1; g uninstall >/dev/null 2>&1; rm -rf "$AD"
  check "  Rollback, Uninstall: 0.1 as it was" eval 'o1_same && [ "$(ino "$O1ST")" = "$O1INO" ]'
done
: >"$STANDIN_LOG"
out=$(g install move 2>&1) && rc=0 || rc=$?
GM="$GD" U="$BOTTLE/drive_c/users/crossover"
check "install move (Steam, ReShade with arcdps) exits 0, the phases 1-5" \
  eval '[ "$rc" = 0 ] && [ "$(echo "$out" | grep "^@phase" | tr "\n" " ")" = "@phase 1 @phase 2 @phase 3 @phase 4 @phase 5 " ]'
check "  installed, route=steam origin=move stage=finished game=yes; the move is done and won't start again" \
  [ "$(st installed route origin stage game move move_record)" = yes/steam/move/finished/yes/no/moved ]
check "  every Wine call as crossover, and the bottle's user is crossover" eval 'every_wine_as crossover && [ "$(ls "$BOTTLE/drive_c/users")" = crossover ]'
check "  0.1's Steam folder renamed into the new bottle in place of Valve's (the same inode, not inside it), gone from 0.1's" \
  eval '[ ! -e "$O1ST" ] && [ "$(ino "$STEAM")" = "$O1INO" ] && [ "$(ino "$GM/Gw2.dat")" = "$GDINO" ] && [ ! -e "$STEAM/Steam" ]'
check "  in it steam.exe, the login, config, userdata, the record of the game, the game's files" \
  eval 'has "$STEAM/steam.exe" "0.1.s steam" && has "$STEAM/config/loginusers.vdf" RememberPassword && has "$STEAM/config/config.vdf" "0.1.s config" && has "$STEAM/userdata/12345/config/localconfig.vdf" "0.1.s localconfig" && has "$STEAM/steamapps/appmanifest_1284210.acf" 1284210 && [ "$(stat -f %z "$GM/Gw2.dat")" = 1153433600 ] && has "$GM/Gw2-64.exe" "stand-in game"'
check "  no step copied or cloned Steam's or the game's folder (install.log), and no line of gw2om.sh does" \
  eval 'no_cp_of "$O1ST" "$O1GAME" && ! grep -nE "(clone_tree|cp )[^#]*[$][{]?OLD_(STEAM|GAME)" "$APP/Contents/Resources/gw2om.sh"'
check "  the record names both places; status: the game is here, Rollback names 0.1.4" \
  eval 'ST_OUT=$(g status); [ "$(cat "$AD/moved-from-0.1")" = "$(printf "moved\nold=%s\nnew=%s\ngame=steamapps/common/Guild Wars 2\ninode=%s" "$O1ST" "$STEAM" "$O1INO")" ] && [ "$(kv "$ST_OUT" move_game)/$(sett move_game rollback_version)" = here/here/0.1.4 ] && [ "$(kv "$ST_OUT" rollback_dmg)" = https://github.com/jdrly/gw2-on-mac/releases/download/v0.1.4/GW2-on-Mac-0.1.4.dmg ] && [ ! -e "$AD/move-undo" ]'
check "  the profile's Steam files in place of the new Steam's, and the game's settings folder whole" \
  eval 'same "$O1U/AppData/Local/Steam/local.vdf" "$U/AppData/Local/Steam/local.vdf" && [ ! -e "$U/AppData/Local/Steam/htmlcache.txt" ] && [ ! -e "$U/AppData/Local/Steam/Steam" ] && same "$O1U/AppData/Roaming/Guild Wars 2/Local.dat" "$U/AppData/Roaming/Guild Wars 2/Local.dat" && same "$O1U/AppData/Roaming/Guild Wars 2/GFXSettings.Gw2-64.exe.xml" "$U/AppData/Roaming/Guild Wars 2/GFXSettings.Gw2-64.exe.xml" && has "$U/AppData/Roaming/Guild Wars 2/Screens/gw001.jpg" JPG'
check "  arcdps at ReShade's chain path, its settings with it; ReShade as d3d11.dll with the compiler and its record" \
  eval 'same "$SANDBOX/pe/arcdps.dll" "$GM/$ARC_CHAIN" && has "$GM/addons/arcdps/arcdps.ini" session && same "$SANDBOX/pe/ReShade64.dll" "$GM/d3d11.dll" && has "$GM/d3dcompiler_47.dll" "0.1.s compiler" && same "$O1/reshade-compiler" "$AD/reshade-compiler" && [ "$(st arcdps_state reshade_state)" = on/on ]'
check "  0.1's addon files kept apart: its own version.dll and both inis as they were" \
  eval 'has "$AD/0.1-addons/files/version.dll" "0.1.s\$" && has "$AD/0.1-addons/files/ReShade.ini" "BasePath=$(winp "$O1RS" | sed "s/\\\\/\\\\\\\\/g")\$" && has "$AD/0.1-addons/files/gw2-ui-scale.ini" "scale=1.5"'
check "  the game folder's ReShade.ini names this app's ReShade folder" \
  eval '[ "$(cat "$GM/ReShade.ini")" = "$(printf "[INSTALL]\nBasePath=%s" "$(winp "$AD/ReShade")")" ]'
check "  the ReShade folder with the preset and shaders; its ini names this app's cache and folder, the chain path on" \
  eval 'same "$O1RS/Presets/Mine.ini" "$AD/ReShade/Presets/Mine.ini" && same "$O1RS/Shaders/Standard/ReShade.fxh" "$AD/ReShade/Shaders/Standard/ReShade.fxh" && has "$AD/ReShade/ReShade.ini" "^IntermediateCachePath=$(winp "$CACHE/reshade" | sed "s/\\\\/\\\\\\\\/g")\$" && has "$AD/ReShade/ReShade.ini" "^SavePath=$(winp "$AD/ReShade" | sed "s/\\\\/\\\\\\\\/g")\\\\Screenshots\$" && has "$AD/ReShade/ReShade.ini" "^EnableProxyLibrary=1\$"'
check "  no line of either ini names a folder of 0.1's" eval 'ini_clean "$GM/ReShade.ini" && ini_clean "$AD/ReShade/ReShade.ini"'
check "  the larger interface: this app's version.dll, its ini from the settings" \
  eval 'same "$COMP/ui-scale/version.dll" "$GM/version.dll" && has "$GM/gw2-ui-scale.ini" "^scale=2.0\$"'
check "  the settings, key by key as SETTINGS_FROM_01 says, at this version; Vsync, which 0.1 doesn't have, at its default" \
  eval 'settings_moved && grep -q "^settings_version=" "$AD/settings.conf" && ! grep -q -e "^coolworkers=" -e "^gamemode=" "$AD/settings.conf" && [ "$(sett vsync)" = on ]'
check "  no DXMT or ReShade cache of 0.1's came along" eval '[ -z "$(find "$CACHE" -type f \( -name shaders.bin -o -name effect.bin \) 2>/dev/null)" ]'
check "  the summary: what came along, what changed, Steam's login, 0.1 as it was" \
  eval 'has <(mv_done) "^Your install moved from GW2 on Mac 0.1: Steam with Guild Wars 2 in its library (moved on this disk, no extra space), your game settings, your addons as they were (arcdps, ReShade with your presets, the larger interface) and your settings\. Changed from GW2 on Mac 0\.1: Cooler job workers isn.t a setting on this engine; Faster locks is off, this version.s default; Game Mode is always on here\. Steam may ask you to sign in once\. To play on GW2 on Mac 0\.1 again, choose Rollback to 0\.1\.4 in Settings › Troubleshooting\. Press Play\.$" || { mv_done; false; }'
check "  0.1's folders as they were, but for the Steam folder" o1_rest_same "$O1ST"
c=$(play_cmd)
check "  Play: Steam as crossover" eval 'every_wine_as crossover && [[ "$c" == *"steam.exe -applaunch 1284210"* ]]'
sessions_reset
# Steam moved the game to another library in this app's bottle: Rollback (and with it Start fresh)
# refuses, the game stays where Steam put it
SL="$BOTTLE/drive_c/SteamLibrary/steamapps"
mkdir -p "$SL/common" && mv "$GM" "$SL/common/" && mv "$STEAM/steamapps/appmanifest_1284210.acf" "$SL/" &&
  printf '"libraryfolders"\n{\n\t"1"\n\t{\n\t\t"path"\t\t"C:\\\\SteamLibrary"\n\t}\n}\n' >"$STEAM/steamapps/libraryfolders.vdf"
check "Steam's game in another library of the bottle: status follows it" eval 'ST_OUT=$(g status); [ "$(kv "$ST_OUT" game_dir)" = "$SL/common/Guild Wars 2" ] && [ "$(kv "$ST_OUT" game)" = yes ]'
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "  Rollback refuses: the game isn't in the folder that came from 0.1; nothing moved" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error Guild Wars 2 isn.t in the folder that came from GW2 on Mac 0.1" && [ "$(ino "$STEAM")" = "$O1INO" ] && [ -f "$SL/common/Guild Wars 2/Gw2.dat" ] && [ ! -e "$AD/move-undo" ]'
out=$(g start-fresh --moved 2>&1) && rc=0 || rc=$?
check "  Start fresh refuses too, and Uninstall; the game stays" \
  eval '[ "$rc" != 0 ] && ! g uninstall >/dev/null 2>&1 && [ -f "$SL/common/Guild Wars 2/Gw2.dat" ] && [ "$(st installed)" = yes ]'
mv "$SL/common/Guild Wars 2" "$STEAM/steamapps/common/" && mv "$SL/appmanifest_1284210.acf" "$STEAM/steamapps/" &&
  rm "$STEAM/steamapps/libraryfolders.vdf" && rm -r "$BOTTLE/drive_c/SteamLibrary"
# Steam moved the game to another folder inside the Steam folder: a Gw2.dat is in what would go
# back, but the game folder the move recorded isn't there, so 0.1's addon files can't go back:
# Rollback refuses, nothing changed
mv "$GM" "$STEAM/steamapps/common/Elsewhere"
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "Rollback with the game moved elsewhere inside Steam's folder: refused, nothing changed" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error The game.s folder isn.t where the move put it" && [ "$(ino "$STEAM")" = "$O1INO" ] && [ -f "$STEAM/steamapps/common/Elsewhere/Gw2.dat" ] && [ ! -e "$AD/move-undo" ]'
mv "$STEAM/steamapps/common/Elsewhere" "$GM"
# Repair with the bottle's system.reg gone: it would make the bottle anew, but the game is in it
mv "$BOTTLE/system.reg" "$SANDBOX/system.reg"
out=$(g repair 2>&1) && rc=0 || rc=$?
check "Repair with system.reg gone and the game in the bottle: refused, the game stays" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error The game.s bottle has no system.reg, and a game is in it" && [ "$(ino "$STEAM")" = "$O1INO" ] && [ -f "$GM/Gw2.dat" ]'
mv "$SANDBOX/system.reg" "$BOTTLE/system.reg"
out=$(g start-fresh --before-move 2>&1) && rc=0 || rc=$?
check "Start fresh confirmed before the move, with the move finished meanwhile: refused, the install stays" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error The move from GW2 on Mac 0.1 has finished meanwhile" && [ "$(st installed move_record)" = yes/moved ]'
mv "$AD/moved-from-0.1" "$SANDBOX/record"
out=$(g start-fresh --moved 2>&1) && rc=0 || rc=$?
check "Start fresh with the move's record missing: refused, the game stays here" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac can.t give the game back to GW2 on Mac 0.1" && [ "$(st installed)" = yes ] && [ "$(ino "$STEAM")" = "$O1INO" ]'
out=$(g uninstall 2>&1) && rc=0 || rc=$?
check "  Uninstall with the record missing (origin move): refused, the game stays" \
  eval '[ "$rc" != 0 ] && [ "$(ino "$STEAM")" = "$O1INO" ] && [ -f "$GM/Gw2.dat" ] && [ "$(st installed)" = yes ]'
cp "$SANDBOX/record" "$AD/moved-from-0.1"
out=$(g start-fresh --moved 2>&1) && rc=0 || rc=$?
check "Start fresh: the game goes back first (the same inode, 0.1's addon files), this app's install goes, the move doesn't start by itself again; 0.1 as it was" \
  eval '[ "$rc" = 0 ] && has <(echo "$out") "^@done .*Guild Wars 2 went back to GW2 on Mac 0.1.s folder first" && [ "$(st installed move move_record old_install)" = no/no/skipped/yes ] && [ "$(ad_list)" = "ReShade moved-from-0.1" ] && [ "$(ino "$O1ST")" = "$O1INO" ] && o1_same'
rm -rf "$AD"

# a 0.1.3-age settings file (keys missing: 0.1's defaults) with Cooler job workers at 3, arcdps alone
old01 steam arcdps "$(printf 'fpscap=60\ncoolworkers=3\nncpu=99\n')"
O1SNAP=$(o1snap) O1INO=$(ino "$O1ST")
out=$(g install move 2>&1) && rc=0 || rc=$?
check "install move (Steam, arcdps alone, an older settings file with coolworkers=3 and ncpu=99) exits 0" [ "$rc" = 0 ]
check "  arcdps as d3d11.dll, no ReShade, no ReShade folder made" \
  eval 'same "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll" && [ "$(st arcdps_state reshade_state)" = on/off ] && [ ! -e "$AD/ReShade" ]'
check "  the keys the file lacks read as 0.1's defaults (uiscale_cinema on), the rest as kept, ncpu=99 as this Mac's 8; coolworkers dropped" \
  eval '[ "$(sett fpscap uiscale_cinema steambg fastlocks ncpu)" = 60/on/on/off/8 ] && ! grep -q "^coolworkers=" "$AD/settings.conf"'
check "  the summary names Cooler job workers, Faster locks and the CPUs" \
  has <(mv_done) "Changed from GW2 on Mac 0.1: Cooler job workers isn.t a setting on this engine; Faster locks is off, this version.s default; CPUs the game sees is 8: 99 isn.t a choice here\."
c=$(play_cmd)
check "  the first Play shows Steam's window though Steam remembers a login" \
  eval '[[ "$c" == *"steam.exe -applaunch 1284210"* && "$c" != *-silent* ]] && [ "$(st origin)" = moved ]'
sessions_reset
c=$(play_cmd)
check "  the next goes silent again" eval '[[ "$c" == *"steam.exe -silent -applaunch 1284210"* ]]'
sessions_reset
check "  0.1's folders as they were, but for the Steam folder" o1_rest_same "$O1ST"
# Rollback to 0.1.4 (Settings › Troubleshooting): refused while this app's Wine runs
mv "$ENG/bin/wineserver" "$ENG/bin/wineserver.heat" && cp "$SANDBOX/sleeper" "$ENG/bin/wineserver"
"$ENG/bin/wineserver" 30 & sp=$!
sleep 0.3
out=$(g rollback 2>&1) && rc=0 || rc=$?
kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null; mv -f "$ENG/bin/wineserver.heat" "$ENG/bin/wineserver"
check "Rollback while this app's Wine runs: refused, the game stays here" \
  eval '[ "$rc" != 0 ] && [ "$(st move_game)" = here ] && [ ! -e "$O1ST" ] && [ "$(ino "$STEAM")" = "$O1INO" ]'
# (a file 0.1's addon list names, missing from what was kept: refused, nothing changed, the
# snapshot of this app's put back by the undo. gw2-ui-scale.ini comes after version.dll, which
# differs between the two (0.1's has its own mark), so the restore has really changed a file first)
GSNAP0=$(find "$GD" -path "$GD/Gw2.dat" -prune -o -type f -exec shasum -a 256 {} + | LC_ALL=C sort)
mv "$AD/0.1-addons/files/gw2-ui-scale.ini" "$SANDBOX/kept-ini"
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "Rollback with one of 0.1's kept addon files missing, after another went back: refused, the game here, its addon files as they were" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac couldn.t put back GW2 on Mac 0.1.s addon files" && [ "$(ino "$STEAM")" = "$O1INO" ] && [ ! -e "$AD/move-undo" ] && [ "$(find "$GD" -path "$GD/Gw2.dat" -prune -o -type f -exec shasum -a 256 {} + | LC_ALL=C sort)" = "$GSNAP0" ]'
mv "$SANDBOX/kept-ini" "$AD/0.1-addons/files/gw2-ui-scale.ini"
mv "$AD/0.1-addons/list" "$SANDBOX/kept-list"
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "Rollback without the list of 0.1's kept addon files: refused, nothing changed" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac didn.t find GW2 on Mac 0.1.s addon files" && [ "$(ino "$STEAM")" = "$O1INO" ] && [ ! -e "$AD/move-undo" ] && [ "$(find "$GD" -path "$GD/Gw2.dat" -prune -o -type f -exec shasum -a 256 {} + | LC_ALL=C sort)" = "$GSNAP0" ]'
mv "$SANDBOX/kept-list" "$AD/0.1-addons/list"
# (0.1's place taken: refused before anything changes, this app's addon files as they were)
gsnap() { find "$GD" -path "$GD/Gw2.dat" -prune -o -type f -exec shasum -a 256 {} + | LC_ALL=C sort; }
GSNAP=$(gsnap)
mkdir "$O1ST"
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "Rollback with 0.1's place taken: refused, nothing changed, the game here" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error .*Steam is there already" && [ "$(gsnap)" = "$GSNAP" ] && [ "$(ino "$STEAM")" = "$O1INO" ] && [ ! -e "$AD/move-undo" ]'
rmdir "$O1ST"
move_paused KILL env GW2_ON_MAC_TEST_PAUSE_AT=rollback-renamed "$GW2OM" rollback
check "Rollback killed after its rename: the next status renames it in again, the install as it was" \
  eval '[ "$paused $rc" = "yes 137" ] && [ -e "$O1ST" ] && [ "$(st move_game game)" = here/yes ] && [ ! -e "$O1ST" ] && [ "$(ino "$STEAM")" = "$O1INO" ] && [ ! -e "$AD/move-undo" ] && [ "$(gsnap)" = "$GSNAP" ]'
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "Rollback: Steam's folder back in 0.1's bottle (the same inode), with the addon files 0.1 had: 0.1 as it was" \
  eval '[ "$rc" = 0 ] && [ "$(ino "$O1ST")" = "$O1INO" ] && o1_same'
check "  this app stays installed, without Steam and the game; the summary says how to go back to 0.1.4" \
  eval '[ "$(st installed steam game move_game move)" = yes/no/no/01/no ] && has <(echo "$out") "^@done Guild Wars 2 is back in GW2 on Mac 0.1.s folder\. To play on it, download GW2 on Mac 0\.1\.4, quit GW2 on Mac, and drag GW2 on Mac 0\.1\.4 to Applications over it\.$"'
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "  a second Rollback changes nothing" eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error There is no game moved from" && o1_same'
out=$(g move-in 2>&1) && rc=0 || rc=$?
check "Move in: Steam's folder renamed in again (the same inode), the game ready, arcdps as it was" \
  eval '[ "$rc" = 0 ] && [ ! -e "$O1ST" ] && [ "$(ino "$STEAM")" = "$O1INO" ] && [ "$(st game stage move_game arcdps_state)" = yes/finished/here/on ] && same "$SANDBOX/pe/arcdps.dll" "$GD/d3d11.dll" && no_cp_of "$O1ST" "$O1GAME"'
# (the game back in 0.1 before Uninstall, which would remove it with the bottle)
g rollback >/dev/null 2>&1
# another volume mounted inside the bottle: Uninstall leaves the bottle (rm -x wouldn't cross into
# it, and find -xdev doesn't look there), and what is on it
MNT="$BOTTLE/drive_c/mnt"
mkdir -p "$MNT"
if hdiutil create -quiet -size 20m -type SPARSE -fs APFS -volname gw2om-mnt "$SANDBOX/mnt" >/dev/null 2>&1 &&
  hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MNT" "$SANDBOX/mnt.sparseimage" >/dev/null 2>&1; then
  trap 'hdiutil detach -quiet -force "$MNT" 2>/dev/null' EXIT
  echo "on another volume" >"$MNT/kept.txt" && echo "beside it" >"$BOTTLE/drive_c/sentinel.txt"
  out=$(g uninstall 2>&1) && rc=0 || rc=$?
  check "Uninstall with another volume mounted in the bottle: refused, the bottle (a file beside the mount too) and the volume's file stay" \
    eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac kept its bottle" && has "$BOTTLE/drive_c/sentinel.txt" beside && has "$MNT/kept.txt" "another volume" && has "$LOGS/install.log" "another volume is mounted inside it"'
  # (detached for sure before the next check: a runner may still hold the volume a moment. The
  # mount table read whole, no pipe; a mount that fails to list counts as still mounted. The EXIT
  # trap that detaches goes only once it is detached)
  mnt_listed() { local m; m=$(mount) || return 0; case "$m" in *" on $MNT ("*) return 0 ;; esac; return 1; }
  i=0
  while mnt_listed && [ $i -lt 20 ]; do
    hdiutil detach -quiet -force "$MNT" >/dev/null 2>&1 || sleep 0.5
    i=$((i + 1))
  done
  check "  the volume is detached again" eval '! mnt_listed'
  mnt_listed || trap - EXIT
else
  echo "  skip the mounted volume (hdiutil could not attach one)"
fi
rmdir "$MNT" 2>/dev/null || true
# (no watcher of the Plays above left to write the session's files into the app's folder)
sessions_reset
out=$(g uninstall 2>&1)
check "uninstall after a move keeps the move's record: no second move by itself" \
  eval '[ "$(st installed move move_record)" = no/no/moved ] && { [ "$(ad_list)" = moved-from-0.1 ] || { echo "    the app folder holds: $(ad_list)"; false; }; }'
out=$(g install move 2>&1) && rc=0 || rc=$?
check "  install move refused with the record there, nothing else made" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error GW2 on Mac doesn.t move GW2 on Mac 0.1.s install again: it was moved here before" && { [ "$(ad_list)" = moved-from-0.1 ] || { echo "    the app folder holds: $(ad_list)"; false; }; } && o1_same'
g install steam >/dev/null 2>&1
out=$(g start-fresh --moved 2>&1) && rc=0 || rc=$?
check "  Start fresh over an install made after it (not the moved one): refused, the install stays" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error This install isn.t the one moved from GW2 on Mac 0.1" && [ "$(st installed move_record)" = yes/moved ]'
g uninstall >/dev/null 2>&1
rm -rf "$AD"

old01 arenanet both
O1SNAP=$(o1snap) O1INO=$(ino "$O1GAME")
: >"$STANDIN_LOG"
out=$(g install move 2>&1) && rc=0 || rc=$?
GA="$BOTTLE/drive_c/Program Files/Guild Wars 2"
check "install move (ArenaNet, ReShade with arcdps) exits 0, the phases 1-4, no Steam" \
  eval '[ "$rc" = 0 ] && [ "$(echo "$out" | grep "^@phase" | tr "\n" " ")" = "@phase 1 @phase 2 @phase 3 @phase 4 " ] && [ "$(st steam)" = no ] && ! grep -q SteamSetup "$STANDIN_LOG"'
check "  route=arenanet origin=move game=yes, the game in Program Files" \
  eval 'ST_OUT=$(g status); [ "$(kv "$ST_OUT" route origin game)" = arenanet/move/yes ] && [ "$(kv "$ST_OUT" game_dir)" = "$GA" ] && [ "$(stat -f %z "$GA/Gw2.dat")" = 1153433600 ]'
check "  the game's settings; no Steam files in the profile" \
  eval 'same "$O1U/AppData/Roaming/Guild Wars 2/Local.dat" "$BOTTLE/drive_c/users/crossover/AppData/Roaming/Guild Wars 2/Local.dat" && [ ! -e "$BOTTLE/drive_c/users/crossover/AppData/Local/Steam" ]'
check "  arcdps at the chain path, ReShade in, both inis name only this app's folders, the linked one's file too" \
  eval 'same "$SANDBOX/pe/arcdps.dll" "$GA/$ARC_CHAIN" && [ "$(st arcdps_state reshade_state)" = on/on ] && ini_clean "$GA/ReShade.ini" && ini_clean "$AD/ReShade/ReShade.ini" && ini_clean "$AD/ReShade/Mine-settings.ini" && [ -L "$AD/ReShade/ReShade.ini" ] && has "$AD/ReShade/ReShade.ini" "^ProxyLibrary=C:.Program Files.Guild Wars 2.addons.arcdps.chain.d3d11.dll\$"'
check "  the summary" has <(mv_done) "^Your install moved from GW2 on Mac 0.1: Guild Wars 2 (moved on this disk, no extra space), your game settings, your addons as they were (arcdps, ReShade with your presets, the larger interface) and your settings\..* To play on GW2 on Mac 0\.1 again, choose Rollback to 0\.1\.4 in Settings › Troubleshooting\. Press Play\.$"
check "  the game folder renamed (the same inode, gone from 0.1's bottle); 0.1's folders as they were but for it" \
  eval '[ ! -e "$O1GAME" ] && [ "$(ino "$GA")" = "$O1INO" ] && o1_rest_same "$O1GAME" && no_cp_of "$O1GAME" && [ "$(sed -n "s/^game=//p" "$AD/moved-from-0.1")" = "" ]'
out=$(g rollback 2>&1) && rc=0 || rc=$?
check "Rollback (ArenaNet): the game folder back with 0.1's addon files and its own ReShade.ini, 0.1 as it was" \
  eval '[ "$rc" = 0 ] && [ "$(ino "$O1GAME")" = "$O1INO" ] && o1_same && [ "$(st installed game move_game)" = yes/no/01 ]'
out=$(g move-in 2>&1) && rc=0 || rc=$?
check "  Move in: the game folder here again, both inis name only this app's folders" \
  eval '[ "$rc" = 0 ] && [ "$(ino "$GA")" = "$O1INO" ] && [ "$(st game move_game reshade_state)" = yes/here/on ] && ini_clean "$GA/ReShade.ini"'
# a bottle an earlier version made keeps its user's name (the Mac's login there)
mv "$BOTTLE/drive_c/users/crossover" "$BOTTLE/drive_c/users/$(id -un)x"
c=$(play_cmd)
check "a bottle with another user's name: Wine runs as that user" eval 'every_wine_as "$(id -un)x" && [[ "$c" == *Gw2-64.exe* ]]'
sessions_reset
out=$(g uninstall 2>&1) && rc=0 || rc=$?
check "Uninstall with the moved game in the bottle: refused, Rollback named, nothing removed" \
  eval '[ "$rc" != 0 ] && has <(echo "$out") "^@error .*only copy. Choose Rollback to 0.1.4" && [ "$(ino "$GA")" = "$O1INO" ] && [ "$(st installed)" = yes ]'
mv "$BOTTLE/drive_c/users/$(id -un)x" "$BOTTLE/drive_c/users/crossover"
g rollback >/dev/null 2>&1; g uninstall >/dev/null 2>&1
rm -rf "$AD" "$O1" "$OC"
check "no 0.1 install: status offers no move" [ "$(st old_install move)" = no/no ]
# Uninstall takes a game with the bottle only when no move is recorded: Start fresh's record counts
# as none only as exactly the one line "skipped" (a NUL in it, say, makes it a move's)
g install steam >/dev/null 2>&1
# Play while the install waits for Steam's download and no Steam runs starts Steam; a start that
# hangs is ended (SIGKILL, reaped) at the time limit before the session's lock goes
SD=$(dirname "$STANDIN_LOG")
rm -f "$SD/steam.delay.pid" && touch "$SD/steam.delay"
out=$(GW2_ON_MAC_LAUNCH_WAIT=20 g play 2>&1) && rc=0 || rc=$?
DP=$(cat "$SD/steam.delay.pid" 2>/dev/null || true)
check "Play in waiting_game with a Steam start that hangs: it reached the hang, refused at the limit, that start ended, the session's lock free" \
  eval '[ "$(st stage)" = waiting_game ] && [ -n "$DP" ] && [ "$rc" != 0 ] && has <(echo "$out") "^@error Steam didn.t start" && ! kill -0 "$DP" 2>/dev/null && ! "$APP/Contents/Resources/helpers/sessionlock" held "$AD/.session.lock"'
[ -z "$DP" ] || kill -KILL "$DP" 2>/dev/null || true
rm -f "$SD/steam.delay" "$SD/steam.delay.pid"
mkdir -p "$BOTTLE/drive_c/games" && echo "a game" >"$BOTTLE/drive_c/games/Gw2.dat"
printf 'skipped\0\n' >"$AD/moved-from-0.1"
out=$(g uninstall 2>&1) && rc=0 || rc=$?
check "Uninstall with a record that isn't exactly \"skipped\": the bottle with the game stays" \
  eval '[ "$rc" != 0 ] && [ -f "$BOTTLE/drive_c/games/Gw2.dat" ]'
printf 'skipped\n' >"$AD/moved-from-0.1"
out=$(g uninstall 2>&1) && rc=0 || rc=$?
check "  with exactly \"skipped\": Uninstall removes it, the game with it" eval '[ "$rc" = 0 ] && [ ! -e "$BOTTLE" ]'
rm -rf "$AD"
fi

if in_group rest; then
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
# The table's rows, "<piece> <NAME=value>", and its version, read from gw2om.sh: the newest of its
# rows and of the rows taken out of it (DEV_GONE)
DEVTABLE=$(sed -n '/^DEV_SWITCHES="$/,/^"$/p' "$APP/Contents/Resources/gw2om.sh" | awk 'NF > 4 { print $2, $5 }')
DEVVER=$(sed -n -e '/^DEV_SWITCHES="$/,/^"$/p' -e '/^DEV_GONE="$/,/^"$/p' "$APP/Contents/Resources/gw2om.sh" | awk 'NF > 3 && $1 > v { v = $1 } END { print v + 0 }')
# Version 8's rows of DEV_GONE, as dev_update names them after "out of the list:"
GONE8="DXMT_PRESENT_QUEUE=pace DXMT_PSO_ARCHIVE=1 DXMT_PSO_GENERATIONS=1"
# Version 9's rows of DEV_GONE
GONE9="DXMT_MTL4_DEVICE_RESIDENCY=1 DXMT_MTL4_TIMESTAMP_REUSE=1 DXMT_MTL4_ALLOCATOR_POOL=1"
# Version 10's row of DEV_GONE, and version 10's rows of DEV_SWITCHES in the table's order
GONE10="DXMT_MTL4_SHOWN_WAIT=write"
V10ON="DXMT_PRESENT_SKIP_NIL=1 DXMT_DRAIN_SPLITS=1 DXMT_REFRESH_REQUERY=1 DXMT_STEADY_SLEEP=1"
# Version 11's rows of DEV_GONE
GONE11="FEX_DISPATCHERL1LOOKUP=1 FEX_ENTRYHEADERLOOKUP=1"
# Version 12's rows of DEV_SWITCHES, in the table's order
V12ON="DXMT_MTL4_PRESENT_FENCES=1 FEX_RETURNLOOKUPOUTOFLINE=1"
# Version 13's row of DEV_GONE: WINE_HEAT_SPIN's line before it took a new value (#368)
GONE13="WINE_HEAT_SPIN=lock=20:game,event=30:game,sem=5:game"
# Version 14's row of DEV_GONE: version 13's WINE_HEAT_SPIN line, whose spin the job workers stay out of (#370)
GONE14="WINE_HEAT_SPIN=lock=20:game+halfworkers,event=30:game"
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
# W32WHY: why the WINE_WIN32U_* lines stay out with the app's own Mac driver: its build has no
# win32u.so, or its narrowed record doesn't name them
if [ "$W32U" = mine ]; then W32WHY="my win32u.so doesn't have it"; else W32WHY="my win32u.so isn't in the engine"; fi
rows_on() { # <settings.conf>: the rows of a development build on, once (dev_version=2)
  local k
  for k in dev_version=2 debug=on jobwakes=on eventpool=on fastlocks=on launcherframes=on warm=on metalfx=on rawmouse=on fex=mine; do
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
check "  the rows on, once: settings.conf at dev_version=2" rows_on "$DAD/settings.conf"
check "  and the install said both" eval 'echo "$out" | grep -q "^Development build: the switch rows on, once: jobwakes=on " && echo "$out" | grep -q "^dev-switches.conf: version $DEVVER, switched on: "'
# A release candidate, X.Y.Z-rc.N (docs/adr/0017), is a development build by another name.
# build.sh's bundle_version (read from build.sh) gives it a CFBundleVersion above every dev build
# of its version and below the release, and refuses any other form. An app.properties with
# version=0.2.0-rc.1 and the dev channel, as build.sh writes it for one: status shows that version,
# and its switches are the development build's.
eval "$(sed -n '/^bundle_version() {/,/^}/p' "$ROOT/build.sh")"
rc_order() {
  [ "$(bundle_version 0.2.0-dev.23)" = 0.1.9999.1023 ] && [ "$(bundle_version 0.2.0-rc.1)" = 0.1.9999.2001 ] || return 1
  [ "$(printf '%s\n' 1.0.0 0.2.0 0.2.0-rc.1 1.0.0-rc.1 0.2.0-dev.999 0.1.9999 0.2.0-rc.999 0.1.9999-rc.1 0.2.0-dev.23 | while read -r v; do echo "$(bundle_version "$v") $v"; done |
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | cut -d' ' -f2 | tr '\n' ' ')" = "0.1.9999-rc.1 0.1.9999 0.2.0-dev.23 0.2.0-dev.999 0.2.0-rc.1 0.2.0-rc.999 0.2.0 1.0.0-rc.1 1.0.0 " ]
}
check "build.sh's versions: 0.2.0-rc.1 is 0.1.9999.2001, above every dev build of 0.2.0 and below 0.2.0, and in order across the patch and major steps" rc_order
rc_refused() {
  local v
  for v in 0.2.0-rc 0.2.0-rc.01 0.2.0-rc.1000 0.2.0-beta.1 0.2.0-rc.1-dev.2 0.2.0-dev.rc.1 0.2-rc.1 0.1.08-rc.1 0.0.0-rc.1 0.10000.0-rc.1 0.2.10000-dev.1 10000.0.0-rc.1; do
    ! bundle_version "$v" >/dev/null 2>"$SANDBOX/bv.txt" && grep -qxF "Unsupported version $v (X.Y.Z, X.Y.Z-dev.N or X.Y.Z-rc.N, above 0.0.0, no leading zeros, X, Y and Z below 10000, N below 1000)" "$SANDBOX/bv.txt" || return 1
  done
}
check "  and refuses a malformed one (0.2.0-rc, rc.01, rc.1000, beta.1, rc.1-dev.2, dev.rc.1, 0.2-rc.1, 0.1.08-rc.1, 0.0.0-rc.1, 0.10000.0-rc.1, 0.2.10000-dev.1, 10000.0.0-rc.1), saying which forms it takes" rc_refused
RCR="$SANDBOX/res-rc"
res_copy "$RCR" channel=dev
sed -i '' 's/^version=.*/version=0.2.0-rc.1/' "$RCR/app.properties"
GW2OM="$RCR/gw2om.sh" GW2_ON_MAC_ROOT="$DROOT" GW2_ON_MAC_DEV_SWITCHES='' "$G" status >"$SANDBOX/rc-status.txt" 2>&1
check "  a release candidate's install (version=0.2.0-rc.1, channel=dev): status shows 0.2.0-rc.1, and the switches in the rule are a development build's" \
  eval 'grep -qx version=0.2.0-rc.1 "$SANDBOX/rc-status.txt" && [ "$(sed -n "s/^dev_switches=//p" "$SANDBOX/rc-status.txt")" = "$(dev_expect | tr "\n" " " | sed "s/ \$//")" ]'
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
  check "  the rows' WINE_HEAT_SPIN first, then the file's" eval 'dg rules | head -1 | grep -q ";env=WINE_HEAT_SPIN=lock=20:game,event=30:game;.*;env=WINE_HEAT_SPIN=lock=20:game,event=30:game"'
fi
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "  a dry run of Play prints that rule, and each line it leaves out with why" \
  eval 'echo "$out" | grep -qxF "[dry-run] rule $(dg rules | head -1)" && echo "$out" | grep -qxF "[dry-run] dev-switches.conf leaves out WINE_WIN32U_SETCURSOR=shm ($W32WHY)" && { ! drv || echo "$out" | grep -qxF "[dry-run] dev-switches.conf leaves out WINE_MACDRV_CLIP=changes (my winemac.so doesn'"'"'t have it)"; }'
check "  and doesn't write the file again" eval '! echo "$out" | grep -q "dev-switches.conf: version"'
check "status lists the lines in the rule, and those left out" \
  eval 'ST_OUT=$(dg status); [ "$(kv "$ST_OUT" dev_switches)" = "$(dev_expect | tr "\n" " " | sed "s/ \$//")" ] && kv "$ST_OUT" dev_switches_out | grep -qF "WINE_WIN32U_PEEK_YIELD=off ($W32WHY)"'
# The table's WINE_MACDRV_* lines with the staged Mac driver's own record for a moment (#144): each
# one its switches: line names is in the rule, each other one out, saying why. The stand-in's line
# is jdrly/wine 472d777's, which names all four; a dev build's names what its commit has
drv_lines_ok() {
  local st piece e in out
  st=$(dg status)
  in=" $(printf '%s\n' "$st" | sed -n 's/^dev_switches=//p') "
  out=";$(printf '%s\n' "$st" | sed -n 's/^dev_switches_out=//p');"
  printf '%s\n' "$DEVTABLE" | {
    while read -r piece e; do
      [ "$piece" = macdrv ] || continue
      if in_switches "${e%%=*}"; then
        case "$in" in *" $e "*) ;; *) exit 1 ;; esac
      else
        case "$out" in *";$e (my winemac.so doesn't have it);"*) ;; *) exit 1 ;; esac
      fi
    done
  }
}
if drv; then
  cp "$DEVKEEP/macdrv" "$COMP/macdrv/VERSION"
  check "  the staged Mac driver's record: each of the table's WINE_MACDRV_* lines it names in the rule, each other one out, saying so" drv_lines_ok
  dev_switches_line macdrv WINE_MACDRV_SURFACE WINE_MACDRV_VIEW
fi
check "the install's start of Steam: session.env names the lines in the rule, install.log those left out" \
  eval '[ "$(sed -n "s/^DEV_SWITCHES=//p" "$DLOGS/session.env")" = "$(dev_expect | tr "\n" " " | sed "s/ \$//")" ] && grep -qF "dev-switches.conf: left out WINE_WIN32U_SETCURSOR=shm ($W32WHY)" "$DLOGS/install.log"'
printf 'info:  GW2 fork v0.80-441-ge02a4d6: DXMT_STATS=1 cpus=8 refresh=60\n' >"$DLOGS/Gw2-64_d3d11.log"
# (the report to a file first: a grep -q on its pipe would end it with a broken pipe, which
# pipefail counts as the check's failure)
GW2_ON_MAC_ROOT="$DROOT" "$APP/Contents/Resources/session-report.sh" >"$CHECKS/devreport.txt" 2>&1
check "  the session report's header prints them" \
  eval 'grep -qxF "Dev switches that were on (dev-switches.conf): $(dev_expect | tr "\n" " " | sed "s/ \$//")" "$CHECKS/devreport.txt"'
# line_has <file> <start> <text>: a line of the file that begins with <start> holds <text>, both
# taken as they are (awk reads the whole file: no early end of a pipe under pipefail)
line_has() { awk -v s="$2" -v t="$3" 'index($0, s) == 1 && index($0, t) { f = 1 } END { exit !f }' "$1" 2>/dev/null; }
check "  and those it left out, each with why: session.env's DEV_SWITCHES_OUT, and the report's header" \
  eval 'line_has "$DLOGS/session.env" "DEV_SWITCHES_OUT=" "WINE_WIN32U_SETCURSOR=shm ($W32WHY)" && line_has "$CHECKS/devreport.txt" "Dev switches left out: " "WINE_WIN32U_SETCURSOR=shm ($W32WHY)"'
# The sampler and FEX_ENTRYHEADERLOOKUP (#162), which my FEX has on by default (#266): with it on,
# FEX stores no block header at a block's entry, which my ntdll.so's sampler reads. While the rule
# can start the sampler (WINE_HEAT_PROF=on or =1, or WINE_HEAT_CONTROL, from dev-switches.conf or
# compatdb.local) and my FEX, whose record names the switch, is in the engine, the game's rule ends
# with FEX_ENTRYHEADERLOOKUP=0, after the file's lines, and CefHost.exe has it unset. A line of mine
# that turns it on stays out then, saying why. Status and the rules go to files first, for the greps.
SAMPLERWHY="the sampler can run (WINE_HEAT_PROF or WINE_HEAT_CONTROL), so the game's rule has FEX_ENTRYHEADERLOOKUP=0 after it"
dev_files() { dg status >"$SANDBOX/dev-status.txt" 2>&1; dg rules >"$SANDBOX/dev-rules.txt" 2>&1; }
rule_has() { sed -n 1p "$SANDBOX/dev-rules.txt" | grep -E ";env=$1(;|\$)" >/dev/null; }
in_status() { line_has "$SANDBOX/dev-status.txt" "dev_switches=" "$1"; }
out_status() { line_has "$SANDBOX/dev-status.txt" "dev_switches_out=" "$1"; }
sampler_off() { sed -n 1p "$SANDBOX/dev-rules.txt" | grep -E ";env=FEX_ENTRYHEADERLOOKUP=0\$" >/dev/null && sed -n 2p "$SANDBOX/dev-rules.txt" | grep -E ";env=FEX_ENTRYHEADERLOOKUP=(;|\$)" >/dev/null; }
no_lookup() { ! grep -q FEX_ENTRYHEADERLOOKUP "$SANDBOX/dev-rules.txt"; }
if fexb; then
  echo WINE_HEAT_PROF=on >>"$DEVF"
  dev_files
  check "my FEX's record without FEX_ENTRYHEADERLOOKUP, with WINE_HEAT_PROF=on: no FEX_ENTRYHEADERLOOKUP in the rules" no_lookup
  sed -i '' '/^WINE_HEAT_PROF=/d' "$DEVF"
  dev_switches_line fex FEX_INITIALCODEBUFFERMB FEX_ENTRYHEADERLOOKUP
  dev_files
  check "  one that names it, and no line that starts the sampler: none either" no_lookup
  for prof in WINE_HEAT_PROF=on WINE_HEAT_PROF=1 WINE_HEAT_CONTROL=/tmp/gw2-heat-control; do
    echo "$prof" >>"$DEVF"
    dev_files
    check "  with $prof in dev-switches.conf: FEX_ENTRYHEADERLOOKUP=0 last in the game's rule, unset for CefHost.exe" sampler_off
    sed -i '' "/^${prof%%=*}=/d" "$DEVF"
  done
  echo WINE_HEAT_PROF=off >>"$DEVF"
  dev_files
  check "  with WINE_HEAT_PROF=off: none" no_lookup
  sed -i '' '/^WINE_HEAT_PROF=/d' "$DEVF"
  printf 'exe=*;env=WINE_HEAT_PROF=on\n' >"$DAD/compatdb.local"
  dev_files
  check "  with WINE_HEAT_PROF=on in a compatdb.local rule for exe=*, which reaches the game too: FEX_ENTRYHEADERLOOKUP=0 last in the game's rule" sampler_off
  echo FEX_ENTRYHEADERLOOKUP=1 >>"$DEVF"
  dev_files
  check "  and a FEX_ENTRYHEADERLOOKUP=1 line of mine: out of the rule and status, saying why, and FEX_ENTRYHEADERLOOKUP=0 still last" \
    eval 'sampler_off && ! rule_has FEX_ENTRYHEADERLOOKUP=1 && ! in_status FEX_ENTRYHEADERLOOKUP && out_status "FEX_ENTRYHEADERLOOKUP=1 ($SAMPLERWHY)"'
  sed -i '' '/^FEX_ENTRYHEADERLOOKUP=1$/d' "$DEVF"
  dg set fex engine >/dev/null 2>&1
  dev_files
  check "  the engine's own FEX, the sampler's line still there: none (that FEX doesn't have the switch)" no_lookup
  dg set fex mine >/dev/null 2>&1
  rm -f "$DAD/compatdb.local"
  dev_files
  check "  without the sampler's line: none again" no_lookup
  dev_switches_line fex FEX_INITIALCODEBUFFERMB
  # Version 6's FEX lines (#164, #165, #118): out while my FEX's record doesn't name them, in once
  # it does (FEX_HOSTFEATURES with its value, as jdrly/FEX#12's VERSION writes it), out with the
  # engine's own FEX. FEX_HOSTFEATURES: the file's lines as one entry, the later of enableavx and
  # disableavx kept, and out while a compatdb.local rule for the game sets it, but not for another
  # program's. (Status and the rules to files, read with awk: no grep -q on a pipe under pipefail)
  V6FEX="FEX_LEA32BITADDS=1 FEX_SIGNEXTENDINGLOADS=1 FEX_ENTRYCOMPILELOCK=1 FEX_HOSTFEATURES=disableavx"
  v6_fex() { # in|<why>: each of them in the rule and status, or out of both, status saying <why>
    local e
    for e in $V6FEX; do
      if [ "$1" = in ]; then rule_has "$e" && in_word "$e" || return 1
      else ! rule_has "$e" && ! in_status "$e" && out_status "$e ($1)" || return 1; fi
    done
  }
  # in_word <NAME=value>: one of status's dev_switches= words is exactly it; hf_count: the
  # FEX_HOSTFEATURES entries of the game's rule
  in_word() { awk -v w="$1" 'index($0, "dev_switches=") == 1 { n = split(substr($0, 14), a, " "); for (i = 1; i <= n; i++) if (a[i] == w) f = 1 } END { exit !f }' "$SANDBOX/dev-status.txt"; }
  hf_count() { awk -F';' 'NR == 1 { for (i = 1; i <= NF; i++) if (index($i, "env=FEX_HOSTFEATURES=") == 1) n++ } END { print n + 0 }' "$SANDBOX/dev-rules.txt"; }
  dev_files
  check "my FEX's record without version 6's FEX lines: each out, saying so" v6_fex "my FEX doesn't have it"
  dev_switches_line fex FEX_INITIALCODEBUFFERMB FEX_ENTRYCOMPILELOCK FEX_LEA32BITADDS FEX_SIGNEXTENDINGLOADS FEX_HOSTFEATURES=disableavx
  dev_files
  check "  one that names them, FEX_HOSTFEATURES as FEX_HOSTFEATURES=disableavx: each in the rule and status, FEX_HOSTFEATURES once" \
    eval 'v6_fex in && [ "$(hf_count)" = 1 ]'
  echo FEX_HOSTFEATURES=enableafp >>"$DEVF"
  dev_files
  check "  with a FEX_HOSTFEATURES=enableafp line of mine after it: one entry, disableavx,enableafp, in the rule and status" \
    eval '[ "$(hf_count)" = 1 ] && rule_has FEX_HOSTFEATURES=disableavx,enableafp && in_word FEX_HOSTFEATURES=disableavx,enableafp'
  sed -i '' 's/^FEX_HOSTFEATURES=enableafp$/FEX_HOSTFEATURES=enableavx,enableafp/' "$DEVF"
  dev_files
  check "  with FEX_HOSTFEATURES=enableavx,enableafp instead: enableavx,enableafp, no disableavx (FEX refuses a value with both)" \
    eval '[ "$(hf_count)" = 1 ] && rule_has FEX_HOSTFEATURES=enableavx,enableafp && in_word FEX_HOSTFEATURES=enableavx,enableafp'
  sed -i '' '/^FEX_HOSTFEATURES=enableavx,enableafp$/d' "$DEVF"
  HFWHY="compatdb.local's rule for Gw2-64.exe sets FEX_HOSTFEATURES=enableafp, which comes later and replaces it. For both, write FEX_HOSTFEATURES=disableavx,enableafp there"
  printf 'exe=Gw2-64.exe;env=FEX_HOSTFEATURES=enableafp\n' >"$DAD/compatdb.local"
  dev_files
  GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/hfplay.txt" 2>&1
  check "  with exe=Gw2-64.exe;env=FEX_HOSTFEATURES=enableafp in compatdb.local: the line out of the game's rule, status and a dry run of Play saying why and what to write there; the other three in" \
    eval '[ "$(hf_count)" = 0 ] && ! in_status FEX_HOSTFEATURES && out_status "FEX_HOSTFEATURES=disableavx ($HFWHY)" && grep -qxF "[dry-run] dev-switches.conf leaves out FEX_HOSTFEATURES=disableavx ($HFWHY)" "$SANDBOX/hfplay.txt" && rule_has FEX_LEA32BITADDS=1 && rule_has FEX_SIGNEXTENDINGLOADS=1 && rule_has FEX_ENTRYCOMPILELOCK=1'
  printf 'exe=CefHost.exe;env=FEX_HOSTFEATURES=enableafp\n' >"$DAD/compatdb.local"
  dev_files
  check "  with a compatdb.local rule for CefHost.exe instead: the line in" \
    eval '[ "$(hf_count)" = 1 ] && rule_has FEX_HOSTFEATURES=disableavx && in_word FEX_HOSTFEATURES=disableavx'
  rm -f "$DAD/compatdb.local"
  dg set fex engine >/dev/null 2>&1
  dev_files
  check "  the engine's own FEX: each out, saying so" v6_fex "my FEX isn't in the engine"
  dg set fex mine >/dev/null 2>&1
  dev_switches_line fex FEX_INITIALCODEBUFFERMB
  # Version 12's FEX line (#343): out while my FEX's record doesn't name it, in once it does, out
  # with the engine's own FEX
  RLO=FEX_RETURNLOOKUPOUTOFLINE=1
  dev_files
  check "my FEX's record without FEX_RETURNLOOKUPOUTOFLINE: its line out, saying so" \
    eval '! rule_has "$RLO" && ! in_status FEX_RETURNLOOKUPOUTOFLINE && out_status "$RLO (my FEX doesn'"'"'t have it)"'
  dev_switches_line fex FEX_INITIALCODEBUFFERMB FEX_RETURNLOOKUPOUTOFLINE
  dev_files
  check "  one that names it: in the rule and status, unset for CefHost.exe" \
    eval 'rule_has "$RLO" && in_word "$RLO" && ! out_status FEX_RETURNLOOKUPOUTOFLINE && sed -n 2p "$SANDBOX/dev-rules.txt" | grep -qE ";env=FEX_RETURNLOOKUPOUTOFLINE=(;|\$)"'
  dg set fex engine >/dev/null 2>&1
  dev_files
  check "  the engine's own FEX: out, saying so" \
    eval '! rule_has "$RLO" && ! in_status FEX_RETURNLOOKUPOUTOFLINE && out_status "$RLO (my FEX isn'"'"'t in the engine)"'
  dg set fex mine >/dev/null 2>&1
  dev_switches_line fex FEX_INITIALCODEBUFFERMB
else
  skipfex "FEX_ENTRYHEADERLOOKUP=0 in the rule while the sampler can run"
  skipfex "version 6's FEX lines in and out of the rule, and FEX_HOSTFEATURES with my own lines and compatdb.local"
  skipfex "version 12's FEX_RETURNLOOKUPOUTOFLINE in and out of the rule"
fi
# My win32u.so in the engine with my winemac.so, from a build whose record names its two switches:
# the rule takes the WINE_WIN32U_* lines; with the engine's own pair, they stay out. The app's
# components/macdrv gets a stand-in win32u.so when its build has none (back after)
if drv; then
  cp "$COMP/macdrv/VERSION" "$SANDBOX/dev-macdrv-VERSION.w32"
  [ "$W32U" = mine ] || echo "my win32u.so" >"$COMP/macdrv/win32u.so"
  { grep -v -e '^switches:' -e '^win32u\.so: ' "$SANDBOX/dev-macdrv-VERSION.w32"
    echo "switches: WINE_MACDRV_SURFACE WINE_MACDRV_VIEW WINE_WIN32U_SETCURSOR WINE_WIN32U_PEEK_YIELD"
    echo "win32u.so: sha256 $(shasum -a 256 "$COMP/macdrv/win32u.so" | cut -d' ' -f1)"; } >"$COMP/macdrv/VERSION"
  dg set macdrv mine >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
  check "my win32u.so in the engine with my winemac.so: a dry run of Play prints the rule with the WINE_WIN32U_* lines, and leaves neither out" \
    eval '[ "$(dg status | sed -n "s/^win32u_file=//p")" = mine ] && dg rules | head -1 | grep -q ";env=WINE_WIN32U_SETCURSOR=shm;env=WINE_WIN32U_PEEK_YIELD=off" && echo "$out" | grep -qxF "[dry-run] rule $(dg rules | head -1)" && ! echo "$out" | grep -q "leaves out WINE_WIN32U_"'
  dg set macdrv engine >/dev/null
  out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
  check "  with the engine's own winemac.so and win32u.so: neither in the rule, each left out saying so" \
    eval '[ "$(dg status | sed -n "s/^win32u_file=//p")" = engine ] && ! dg rules | grep -q WINE_WIN32U_ && echo "$out" | grep -qxF "[dry-run] dev-switches.conf leaves out WINE_WIN32U_SETCURSOR=shm (my win32u.so isn'"'"'t in the engine)" && echo "$out" | grep -qxF "[dry-run] dev-switches.conf leaves out WINE_WIN32U_PEEK_YIELD=off (my win32u.so isn'"'"'t in the engine)"'
  cp "$SANDBOX/dev-macdrv-VERSION.w32" "$COMP/macdrv/VERSION"
  [ "$W32U" = mine ] || rm -f "$COMP/macdrv/win32u.so"
  dg set macdrv mine >/dev/null
else
  skipdrv "the WINE_WIN32U_* lines with my win32u.so in the engine"
fi
sed -i '' 's/^FEX_DYNAMICL1CACHE=/#FEX_DYNAMICL1CACHE=/' "$DEVF"
echo "MY_OWN_SWITCH=1" >>"$DEVF"
check "a line commented out is gone from the rule and status; a line I added is in, after the others" \
  eval '! dg rules | grep -q FEX_DYNAMICL1CACHE && ! dg status | grep "^dev_switches=" | grep -q FEX_DYNAMICL1CACHE && dg rules | head -1 | grep -q ";env=MY_OWN_SWITCH=1\$"'
dg set dxmt engine >/dev/null
check "  the engine's own DXMT: no DXMT_* line in the rule, each left out saying so" \
  eval 'no_dxmt_lines && dg status | sed -n "s/^dev_switches_out=//p" | grep -q "DXMT_PRESENTER_FREE=1 (my DXMT fork isn'"'"'t in the engine)"'
dg set dxmt fork >/dev/null
# My DXMT fork's tree in the engine is what's read, not this app's build: it can be an earlier
# build while Steam runs with it. Its DLLs replaced by one without a name, then by one with only
# DXMT_WARM_JOBS (the tree back after)
DTREE="$DAD/engine/lib/wine/dxgi/dxmt/aarch64-windows"
rm -rf "$SANDBOX/dtree.keep" && cp -Rp "$DTREE" "$SANDBOX/dtree.keep"
for f in "$DTREE"/*.dll; do echo "an earlier build" >"$f"; done
check "an earlier build of my DXMT fork in the engine: its DXMT_* lines out, saying so" \
  eval 'ST_OUT=$(dg status); ! echo "$ST_OUT" | grep "^dev_switches=" | grep -q DXMT_ && kv "$ST_OUT" dev_switches_out | grep -q "DXMT_PRESENTER_FREE=1 (my DXMT fork doesn'"'"'t have it)"'
dev_files
check "  DXMT_RENAME_TRIM=600 (jdrly/dxmt#265) among them" \
  eval '! rule_has DXMT_RENAME_TRIM=600 && ! in_status DXMT_RENAME_TRIM && out_status "DXMT_RENAME_TRIM=600 (my DXMT fork doesn'"'"'t have it)"'
GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/swplay.txt" 2>&1
v10_dxmt() { # in|out: version 10's four lines each in the rule, status and a dry run of Play's rule, or out of them, status and the dry run saying why
  local e
  for e in $V10ON; do
    if [ "$1" = in ]; then rule_has "$e" && in_status "$e" && ! out_status "${e%%=*}" && line_has "$SANDBOX/swplay.txt" "[dry-run] rule " ";env=$e" || return 1
    else ! rule_has "$e" && ! in_status "${e%%=*}" && out_status "$e (my DXMT fork doesn't have it)" && grep -qxF "[dry-run] dev-switches.conf leaves out $e (my DXMT fork doesn't have it)" "$SANDBOX/swplay.txt" || return 1; fi
  done
}
check "  version 10's four lines (jdrly/dxmt#324, #316, #314) among them, status and a dry run of Play saying why" v10_dxmt out
check "  and version 12's DXMT_MTL4_PRESENT_FENCES=1 (jdrly/dxmt#358)" \
  eval '! rule_has DXMT_MTL4_PRESENT_FENCES=1 && ! in_status DXMT_MTL4_PRESENT_FENCES && out_status "DXMT_MTL4_PRESENT_FENCES=1 (my DXMT fork doesn'"'"'t have it)" && grep -qxF "[dry-run] dev-switches.conf leaves out DXMT_MTL4_PRESENT_FENCES=1 (my DXMT fork doesn'"'"'t have it)" "$SANDBOX/swplay.txt"'
printf 'x\0DXMT_WARM_JOBS\0' >"$DTREE/d3d11.dll"
check "  one that has DXMT_WARM_JOBS: that line in, the others out" \
  eval 'ST_OUT=$(dg status); echo "$ST_OUT" | grep "^dev_switches=" | grep -q DXMT_WARM_JOBS=2 && kv "$ST_OUT" dev_switches_out | grep -q "DXMT_PRESENTER_FREE=1 (my DXMT fork doesn'"'"'t have it)"'
printf 'x\0DXMT_RENAME_TRIM\0' >"$DTREE/d3d11.dll"
dev_files
check "  one that has DXMT_RENAME_TRIM: DXMT_RENAME_TRIM=600 in the rule and status" \
  eval 'rule_has DXMT_RENAME_TRIM=600 && in_status DXMT_RENAME_TRIM=600 && ! out_status DXMT_RENAME_TRIM'
printf 'x\0DXMT_PRESENT_SKIP_NIL\0DXMT_DRAIN_SPLITS\0DXMT_REFRESH_REQUERY\0DXMT_STEADY_SLEEP\0DXMT_MTL4_SHOWN_WAIT\0' >"$DTREE/d3d11.dll"
dev_files
GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/swplay.txt" 2>&1
check "  one that has the four: each in the rule, status and a dry run of Play's rule, and no DXMT_MTL4_SHOWN_WAIT there, which left the table" \
  eval 'v10_dxmt in && ! grep -q DXMT_MTL4_SHOWN_WAIT "$SANDBOX/dev-rules.txt" "$SANDBOX/dev-status.txt" "$SANDBOX/swplay.txt"'
dg status >"$SANDBOX/dev-status.txt" 2>&1
check "  DXMT_RENAME_TRIM=600 among those out, and the rule's own DXMT_MTL4_PRESENT=mtl3 out at Metal 4, the default, each saying so" \
  eval 'sed -n "s/^dev_switches_out=//p" "$SANDBOX/dev-status.txt" | grep -qF "DXMT_RENAME_TRIM=600 (my DXMT fork doesn'"'"'t have it)" && grep -qx metal=4 "$SANDBOX/dev-status.txt" && grep -qxF "metal_present_out=DXMT_MTL4_PRESENT=mtl3 (my DXMT fork doesn'"'"'t have it)" "$SANDBOX/dev-status.txt"'
# (jdrly/dxmt#316's drain and jdrly/dxmt#358's present fences: in the rule only with a build that
# names them, whatever the Metal row says, as the drain acts only on Metal 3 and the fences only on
# Metal 4. jdrly/dxmt#227's present: the rule's own entry at Metal 4, before the file's lines.
# Status and the rules to files, for grep)
dtree_names() { printf 'x\0DXMT_MTL4_PRESENT\0DXMT_DRAIN_SPLITS\0DXMT_MTL4_PRESENT_FENCES\0' >"$DTREE/d3d11.dll"; }
dtree_names
dg status >"$SANDBOX/dev-status.txt" 2>&1; dg rules >"$SANDBOX/dev-rules.txt" 2>&1
check "  one that has both, at Metal 4: DXMT_MTL4_PRESENT=mtl3 right after DXMT_METAL4=1 and not a line of the file, DXMT_DRAIN_SPLITS=1 among the file's; both unset for CefHost.exe" \
  eval 'sed -n 1p "$SANDBOX/dev-rules.txt" | grep -q ";env=DXMT_METAL4=1;env=DXMT_MTL4_PRESENT=mtl3;.*;env=DXMT_DRAIN_SPLITS=1" && grep -qx "metal_present=DXMT_MTL4_PRESENT=mtl3" "$SANDBOX/dev-status.txt" && grep -q "^dev_switches=.*DXMT_DRAIN_SPLITS=1" "$SANDBOX/dev-status.txt" && ! grep -q "^dev_switches=.*DXMT_MTL4_PRESENT=" "$SANDBOX/dev-status.txt" && sed -n 2p "$SANDBOX/dev-rules.txt" | grep -q ";env=DXMT_METAL4=;env=DXMT_MTL4_PRESENT=;" && sed -n 2p "$SANDBOX/dev-rules.txt" | grep -qE ";env=DXMT_DRAIN_SPLITS=(;|\$)"'
check "  DXMT_MTL4_PRESENT_FENCES=1 among the file's lines, after the rule's DXMT_MTL4_PRESENT=mtl3, and in status; unset for CefHost.exe" \
  eval 'sed -n 1p "$SANDBOX/dev-rules.txt" | grep -qE ";env=DXMT_MTL4_PRESENT=mtl3;(.*;)?env=DXMT_MTL4_PRESENT_FENCES=1(;|\$)" && in_status DXMT_MTL4_PRESENT_FENCES=1 && ! out_status DXMT_MTL4_PRESENT_FENCES && sed -n 2p "$SANDBOX/dev-rules.txt" | grep -qE ";env=DXMT_MTL4_PRESENT_FENCES=(;|\$)"'
# (a line of mine with the same variable: after the rule's entry, so it wins)
echo DXMT_MTL4_PRESENT=done >>"$DEVF"
dg status >"$SANDBOX/dev-status.txt" 2>&1; dg rules >"$SANDBOX/dev-rules.txt" 2>&1
check "  a DXMT_MTL4_PRESENT=done line of mine: in the rule after the rule's own entry, and in status" \
  eval 'sed -n 1p "$SANDBOX/dev-rules.txt" | grep -qE ";env=DXMT_METAL4=1;env=DXMT_MTL4_PRESENT=mtl3;(.*;)?env=DXMT_MTL4_PRESENT=done(;|\$)" && grep -q "^dev_switches=.*DXMT_MTL4_PRESENT=done" "$SANDBOX/dev-status.txt"'
sed -i '' '/^DXMT_MTL4_PRESENT=done$/d' "$DEVF"
dg set metal 3 >/dev/null
dg status >"$SANDBOX/dev-status.txt" 2>&1; dg rules >"$SANDBOX/dev-rules.txt" 2>&1
check "  at Metal 3: no DXMT_MTL4_PRESENT, status says why; DXMT_DRAIN_SPLITS=1 and DXMT_MTL4_PRESENT_FENCES=1 still in" \
  eval 'sed -n 1p "$SANDBOX/dev-rules.txt" | grep -q ";env=DXMT_METAL4=0;.*;env=DXMT_DRAIN_SPLITS=1" && rule_has DXMT_MTL4_PRESENT_FENCES=1 && ! grep -q DXMT_MTL4_PRESENT= "$SANDBOX/dev-rules.txt" && grep -qxF "metal_present_out=DXMT_MTL4_PRESENT=mtl3 (the Metal row is at Metal 3)" "$SANDBOX/dev-status.txt"'
dg set metal 4 >/dev/null
rm -rf "$DTREE" && cp -Rp "$SANDBOX/dtree.keep" "$DTREE"
if mine; then
  # (a VERSION without a switches: line names nothing for a development build's lines)
  grep -v '^switches:' "$DEVKEEP/ntdll" >"$COMP/ntdll/VERSION"
  check "my ntdll.so's VERSION without a switches: line: WINE_HEAT_SPIN's line out, saying so" \
    eval 'dg status | sed -n "s/^dev_switches_out=//p" | grep -q "WINE_HEAT_SPIN=lock=20:game,event=30:game (my ntdll.so doesn'"'"'t have it)"'
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
  eval 'echo "$out" | grep -qxF "[dry-run] write $DEVF" && echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: DXMT_COMPILE_DEMAND=1; out of the list: DXMT_MTL4_PRESENT=mtl3 $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14"'
dg repair >/dev/null 2>&1
check "  updated: the newer switch at the end, on, under its comment; the commented-out line and mine kept" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(tail -1 "$DEVF")" = DXMT_COMPILE_DEMAND=1 ] && tail -2 "$DEVF" | head -1 | grep -q "^# my DXMT fork " && grep -qx "#FEX_DYNAMICL1CACHE=0" "$DEVF" && ! grep -qx "FEX_DYNAMICL1CACHE=0" "$DEVF" && grep -qx MY_OWN_SWITCH=1 "$DEVF"'
dg set metalfx off >/dev/null
dg repair >/dev/null 2>&1
check "a row I turn off stays off through the next update" eval 'grep -qx metalfx=off "$DAD/settings.conf" && grep -qx dev_version=2 "$DAD/settings.conf"'
# (a file a development build before row 2 wrote, with Debug logging off: row 2 turns it on once,
# the rows of 1 stay as they are; Debug logging off afterwards stays off)
sed -i '' -e 's/^dev_version=.*/dev_version=1/' -e 's/^debug=.*/debug=off/' "$DAD/settings.conf"
out=$(dg repair 2>&1)
check "a file at dev_version=1 with Debug logging off: row 2 turns it on once, metalfx stays off" \
  eval 'grep -qx debug=on "$DAD/settings.conf" && grep -qx metalfx=off "$DAD/settings.conf" && grep -qx dev_version=2 "$DAD/settings.conf" && echo "$out" | grep -qx "Development build: the switch rows on, once: debug=on"'
dg set debug off >/dev/null
dg repair >/dev/null 2>&1
check "  Debug logging off afterwards stays off" eval 'grep -qx debug=off "$DAD/settings.conf" && grep -qx dev_version=2 "$DAD/settings.conf"'
dg set debug on >/dev/null
# drop_rows: the file without those variables' lines, their comments and the empty line above
# each, as an older build wrote them
drop_rows() { # <file> <NAME...>
  local f=$1
  shift
  awk -v names="$*" '
    BEGIN { n = split(names, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
    { l[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        k = l[i]; sub(/=.*/, "", k)
        if (l[i] ~ /^[A-Z]/ && (k in want)) {
          d[i] = 1
          if (i > 1 && index(l[i - 1], "# ") == 1) { d[i - 1] = 1; if (i > 2 && l[i - 2] == "") d[i - 2] = 1 }
        }
      }
      for (i = 1; i <= NR; i++) if (!d[i]) print l[i]
    }' "$f"
}
# A file at version 4, before version 5's rows (#161, #162): nothing is added, since both left the
# table at version 11 and the file names every later row. Play says which lines left the list.
sed 's/^version=.*/version=4/' "$DEVF" >"$SANDBOX/devf.v4old"
cp "$SANDBOX/devf.v4old" "$DEVF"
GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/v4play.txt" 2>&1
check "a file at version 4: Play would switch nothing on and say what left the list (dry run)" \
  eval '[ "$(grep -c "^FEX_.*LOOKUP=" "$DEVF")" = 0 ] && grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14" "$SANDBOX/v4play.txt"'
dg repair >/dev/null 2>&1
sed 1d "$SANDBOX/devf.v4old" >"$SANDBOX/devf.v4rest"
sed 1d "$DEVF" >"$SANDBOX/devf.v5"
check "  updated: the table's version, the rest as it was" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && same "$SANDBOX/devf.v4rest" "$SANDBOX/devf.v5"'
# A file at version 5, before version 6's rows (#164, #165, #118, jdrly/dxmt#265): the five added
# at the end, on, each under its comment, and nothing else changes. Then FEX_HOSTFEATURES: a line of
# mine about something else (enableafp) still gets disableavx added; one that already says enableavx,
# or a disableavx line commented out, doesn't.
added_ok() { # <file> <label|ref|entry>...: per row, an empty line, "# <label> (<ref>), unplayed: …" and <entry>, nothing more
  local f=$1 i=0 r label ref entry
  shift
  [ "$(wc -l <"$f" | tr -d ' ')" = $(($# * 3)) ] || return 1
  for r in "$@"; do
    label=${r%%|*} r=${r#*|}
    ref=${r%%|*} entry=${r#*|}
    [ -z "$(sed -n "$((i + 1))p" "$f")" ] || return 1
    case "$(sed -n "$((i + 2))p" "$f")" in "# $label ($ref), unplayed: "*) ;; *) return 1 ;; esac
    [ "$(sed -n "$((i + 3))p" "$f")" = "$entry" ] || return 1
    i=$((i + 3))
  done
}
V5ON="FEX_LEA32BITADDS=1 FEX_SIGNEXTENDINGLOADS=1 FEX_ENTRYCOMPILELOCK=1 FEX_HOSTFEATURES=disableavx DXMT_RENAME_TRIM=600"
cp "$DEVF" "$SANDBOX/devf.full"
drop_rows "$DEVF" FEX_LEA32BITADDS FEX_SIGNEXTENDINGLOADS FEX_ENTRYCOMPILELOCK FEX_HOSTFEATURES DXMT_RENAME_TRIM | sed 's/^version=.*/version=5/' >"$SANDBOX/devf.v5old"
cp "$SANDBOX/devf.v5old" "$DEVF"
GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/v5play.txt" 2>&1
check "a file at version 5: Play would add the five lines of version 6 (dry run)" \
  eval '[ "$DEVVER" = 14 ] && [ "$(grep -c -e "^FEX_LEA32BITADDS=" -e "^FEX_HOSTFEATURES=" -e "^DXMT_RENAME_TRIM=" "$DEVF")" = 0 ] && grep -qxF "dev-switches.conf: version $DEVVER, switched on: $V5ON; out of the list: $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14" "$SANDBOX/v5play.txt"'
dg repair >/dev/null 2>&1
n=$(wc -l <"$DEVF" | tr -d ' ')
awk -v n="$n" 'NR > 1 && NR <= n - 15' "$DEVF" >"$SANDBOX/devf.v5new"
sed 1d "$SANDBOX/devf.v5old" >"$SANDBOX/devf.v5rest"
tail -15 "$DEVF" >"$SANDBOX/devf.added"
check "  updated: the table's version, the five lines at the end, each under a comment naming its piece, its issue and unplayed, the rest as it was" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && same "$SANDBOX/devf.v5rest" "$SANDBOX/devf.v5new" && added_ok "$SANDBOX/devf.added" "my FEX|#164|FEX_LEA32BITADDS=1" "my FEX|#164|FEX_SIGNEXTENDINGLOADS=1" "my FEX|#165|FEX_ENTRYCOMPILELOCK=1" "my FEX|#118|FEX_HOSTFEATURES=disableavx" "my DXMT fork|jdrly/dxmt#265|DXMT_RENAME_TRIM=600"'
v5_with() { { cat "$SANDBOX/devf.v5old"; echo "$1"; } >"$DEVF"; GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/v5play.txt" 2>&1; dg repair >/dev/null 2>&1; }
v5_with FEX_HOSTFEATURES=enableafp
check "  a version-5 file with a FEX_HOSTFEATURES=enableafp line of mine: disableavx added at the end all the same, mine kept" \
  eval 'grep -qxF "dev-switches.conf: version $DEVVER, switched on: $V5ON; out of the list: $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14" "$SANDBOX/v5play.txt" && grep -qx FEX_HOSTFEATURES=enableafp "$DEVF" && [ "$(sed -n "/^FEX_HOSTFEATURES=disableavx\$/=" "$DEVF")" -gt "$(sed -n "/^FEX_HOSTFEATURES=enableafp\$/=" "$DEVF")" ]'
for hand in FEX_HOSTFEATURES=enableavx,enableafp '#FEX_HOSTFEATURES=disableavx'; do
  v5_with "$hand"
  check "  a version-5 file with $hand: the other four added, no FEX_HOSTFEATURES line" \
    eval 'grep -qxF "dev-switches.conf: version $DEVVER, switched on: FEX_LEA32BITADDS=1 FEX_SIGNEXTENDINGLOADS=1 FEX_ENTRYCOMPILELOCK=1 DXMT_RENAME_TRIM=600; out of the list: $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14" "$SANDBOX/v5play.txt" && [ "$(grep -c "FEX_HOSTFEATURES=" "$DEVF")" = 1 ] && grep -qxF "$hand" "$DEVF"'
done
# A file at version 9, before version 10's rows (jdrly/dxmt#324, #316, #314): the four added at
# the end, on, each under its comment, and nothing else changes. With one of them commented out in
# the file, the other three are added and that line stays commented out.
drop_rows "$SANDBOX/devf.full" DXMT_PRESENT_SKIP_NIL DXMT_DRAIN_SPLITS DXMT_REFRESH_REQUERY DXMT_STEADY_SLEEP | sed 's/^version=.*/version=9/' >"$SANDBOX/devf.v9old"
cp "$SANDBOX/devf.v9old" "$DEVF"
GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/v9play.txt" 2>&1
check "a file at version 9: Play would add the four lines of version 10 and say DXMT_MTL4_SHOWN_WAIT=write left the list (dry run)" \
  eval '[ "$(grep -c -e "^DXMT_PRESENT_SKIP_NIL=" -e "^DXMT_DRAIN_SPLITS=" -e "^DXMT_REFRESH_REQUERY=" -e "^DXMT_STEADY_SLEEP=" "$DEVF")" = 0 ] && grep -qxF "dev-switches.conf: version $DEVVER, switched on: $V10ON; out of the list: $GONE10 $GONE11 $GONE13 $GONE14" "$SANDBOX/v9play.txt"'
dg repair >/dev/null 2>&1
n=$(wc -l <"$DEVF" | tr -d ' ')
awk -v n="$n" 'NR > 1 && NR <= n - 12' "$DEVF" >"$SANDBOX/devf.v9new"
sed 1d "$SANDBOX/devf.v9old" >"$SANDBOX/devf.v9rest"
tail -12 "$DEVF" >"$SANDBOX/devf.added"
check "  updated: the table's version, the four lines at the end, each under a comment naming my DXMT fork, its issue and unplayed, the rest as it was" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && same "$SANDBOX/devf.v9rest" "$SANDBOX/devf.v9new" && added_ok "$SANDBOX/devf.added" "my DXMT fork|jdrly/dxmt#324|DXMT_PRESENT_SKIP_NIL=1" "my DXMT fork|jdrly/dxmt#316|DXMT_DRAIN_SPLITS=1" "my DXMT fork|jdrly/dxmt#314|DXMT_REFRESH_REQUERY=1" "my DXMT fork|jdrly/dxmt#314|DXMT_STEADY_SLEEP=1"'
{ cat "$SANDBOX/devf.v9old"; echo '#DXMT_DRAIN_SPLITS=1'; } >"$DEVF"
GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/v9play.txt" 2>&1
dg repair >/dev/null 2>&1
dev_files
check "  a version-9 file with #DXMT_DRAIN_SPLITS=1: the other three added, the line still commented out, and not in the rule or status" \
  eval 'grep -qxF "dev-switches.conf: version $DEVVER, switched on: DXMT_PRESENT_SKIP_NIL=1 DXMT_REFRESH_REQUERY=1 DXMT_STEADY_SLEEP=1; out of the list: $GONE10 $GONE11 $GONE13 $GONE14" "$SANDBOX/v9play.txt" && [ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(grep -c DXMT_DRAIN_SPLITS "$DEVF")" = 1 ] && grep -qx "#DXMT_DRAIN_SPLITS=1" "$DEVF" && ! grep -q DXMT_DRAIN_SPLITS "$SANDBOX/dev-rules.txt" "$SANDBOX/dev-status.txt"'
cp "$SANDBOX/devf.full" "$DEVF"
# A file at version 11, before version 12's rows (jdrly/dxmt#358, #343): both added at the end, on,
# each under its comment, nothing else changes, and only the old WINE_HEAT_SPIN lines of versions 13
# and 14 left the list (this file has the new one)
drop_rows "$SANDBOX/devf.full" DXMT_MTL4_PRESENT_FENCES FEX_RETURNLOOKUPOUTOFLINE | sed 's/^version=.*/version=11/' >"$SANDBOX/devf.v11old"
cp "$SANDBOX/devf.v11old" "$DEVF"
GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/v11play.txt" 2>&1
check "a file at version 11: Play would add the two lines of version 12, and say the old WINE_HEAT_SPIN lines left the list (dry run)" \
  eval '[ "$(grep -c -e "^DXMT_MTL4_PRESENT_FENCES=" -e "^FEX_RETURNLOOKUPOUTOFLINE=" "$DEVF")" = 0 ] && grep -qxF "dev-switches.conf: version $DEVVER, switched on: $V12ON; out of the list: $GONE13 $GONE14" "$SANDBOX/v11play.txt"'
dg repair >/dev/null 2>&1
n=$(wc -l <"$DEVF" | tr -d ' ')
awk -v n="$n" 'NR > 1 && NR <= n - 6' "$DEVF" >"$SANDBOX/devf.v11new"
sed 1d "$SANDBOX/devf.v11old" >"$SANDBOX/devf.v11rest"
tail -6 "$DEVF" >"$SANDBOX/devf.added"
check "  updated: the table's version, the two lines at the end, each under a comment naming its piece, its issue and unplayed, the rest as it was" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && same "$SANDBOX/devf.v11rest" "$SANDBOX/devf.v11new" && added_ok "$SANDBOX/devf.added" "my DXMT fork|jdrly/dxmt#358|DXMT_MTL4_PRESENT_FENCES=1" "my FEX|#343|FEX_RETURNLOOKUPOUTOFLINE=1"'
cp "$SANDBOX/devf.full" "$DEVF"
# A file at version 12 or 13, which has WINE_HEAT_SPIN's line as that build wrote it, under its
# comment (here at the end, #368, #370): as written, the line and its comment go and version 14's
# value comes at the end under its own comment. Version 12's line goes from a file at version 12
# though version 13's line is the newer row of DEV_GONE. A value I changed stays, one I commented out
# stays as it is, and one I deleted stays deleted: no line comes for any of them, nor with a line of
# mine beside the old one.
spin_old() { # <line>: the file as the build of version $old would have it, <line> last under its comment
  { cat "$SANDBOX/devf.spinrest"; echo; echo "$oldcomment"; echo "$1"; } >"$DEVF"
}
for old in 12 13; do
  if [ "$old" = 12 ]; then
    oldline=$GONE13 oldgone="$GONE13 $GONE14"
    oldcomment="# my ntdll.so (#14,#45), unplayed: the Faster locks row's two spins, and the job workers spin 5 µs on their semaphore before they sleep. While this line is here, its value replaces the row's."
  else
    oldline=$GONE14 oldgone=$GONE14
    oldcomment="# my ntdll.so (#14,#45,#368), unplayed: the Faster locks row's two spins, and every other job worker spins before a lock sleep too, so one session compares the two halves: each thread's row in the heat log says spin 1 or spin 0. Needs my ntdll.so from jdrly/wine#59 on: an older one doesn't know the scope and leaves the lock spin off. While this line is here, its value replaces the row's."
  fi
  drop_rows "$SANDBOX/devf.full" WINE_HEAT_SPIN | sed "s/^version=.*/version=$old/" >"$SANDBOX/devf.spinrest"
  spin_old "$oldline"
  GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/spinplay.txt" 2>&1
  check "a file at version $old with WINE_HEAT_SPIN's line as it wrote it: Play would switch the new value on and say the old ones left the list (dry run)" \
    eval 'grep -qxF "dev-switches.conf: version $DEVVER, switched on: WINE_HEAT_SPIN=lock=20:game,event=30:game; out of the list: $oldgone" "$SANDBOX/spinplay.txt"'
  dg repair >/dev/null 2>&1
  n=$(wc -l <"$DEVF" | tr -d ' ')
  awk -v n="$n" 'NR > 1 && NR <= n - 3' "$DEVF" >"$SANDBOX/devf.spinnew"
  sed 1d "$SANDBOX/devf.spinrest" >"$SANDBOX/devf.spinkeep"
  tail -3 "$DEVF" >"$SANDBOX/devf.added"
  check "  updated: the old line, its comment and the empty line above them gone, the new one at the end under its comment, the rest as it was" \
    eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && same "$SANDBOX/devf.spinkeep" "$SANDBOX/devf.spinnew" && added_ok "$SANDBOX/devf.added" "my ntdll.so|#14,#45,#370|WINE_HEAT_SPIN=lock=20:game,event=30:game"'
  for hand in WINE_HEAT_SPIN=lock=50:game "#$oldline" "no line"; do
    if [ "$hand" = "no line" ]; then cp "$SANDBOX/devf.spinrest" "$DEVF"; else spin_old "$hand"; fi
    sed 1d "$DEVF" >"$SANDBOX/devf.spinhand"
    GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/spinplay.txt" 2>&1
    dg repair >/dev/null 2>&1
    check "  a version-$old file with $hand: nothing switched on, the file as it was but its version" \
      eval 'grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: $oldgone" "$SANDBOX/spinplay.txt" && [ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(sed 1d "$DEVF")" = "$(cat "$SANDBOX/devf.spinhand")" ]'
  done
  spin_old "$oldline
WINE_HEAT_SPIN=lock=50:game"
  GW2_ON_MAC_DRY_RUN=1 dg play >"$SANDBOX/spinplay.txt" 2>&1
  dg repair >/dev/null 2>&1
  check "  a version-$old file with the old line and a WINE_HEAT_SPIN=lock=50:game of mine after it: nothing switched on, the old line and its comment gone, mine kept last" \
    eval 'grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: $oldgone" "$SANDBOX/spinplay.txt" && [ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(sed 1d "$DEVF")" = "$(sed 1d "$SANDBOX/devf.spinrest"; echo WINE_HEAT_SPIN=lock=50:game)" ]'
done
cp "$SANDBOX/devf.full" "$DEVF"
# A file at version 2 or 1: nothing is added, since version 3's DXMT_MTL4_ALLOCATOR_POOL left the
# table at version 9 and the file names every later row. Play says which lines left the list.
for old in 2 1; do
  sed -i '' -e "s/^version=.*/version=$old/" "$DEVF"
  sed 1d "$DEVF" >"$SANDBOX/devf.v$old"
  out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
  check "a file at version $old: Play would switch nothing on and say what left the list (dry run)" \
    eval '[ "$DEVVER" = 14 ] && echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: DXMT_MTL4_PRESENT=mtl3 $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14"'
  dg repair >/dev/null 2>&1
  sed 1d "$DEVF" >"$SANDBOX/devf.v${old}new"
  check "  updated: the table's version, the rest as it was" \
    eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && same "$SANDBOX/devf.v$old" "$SANDBOX/devf.v${old}new"'
done
# The table (version 4 took DXMT_MTL4_PRESENT=mtl3 out) over the file of a build at version 3, which has DXMT_MTL4_PRESENT=mtl3
# under the comment that build wrote (here at the end): as written, the line and its comment go; a
# value I changed stays; commented out, it becomes DXMT_MTL4_PRESENT=mtl4. Nothing else changes.
cp "$DEVF" "$SANDBOX/devf.now"
v3_present() { # <line>: the file as a version-3 build would have it, <line> last under its comment
  { echo version=3; sed 1d "$SANDBOX/devf.now"; echo
    echo "# my DXMT fork (jdrly/dxmt#227), unplayed: only with the Metal row at Metal 4, nothing on Metal 3: each frame is presented the Metal 3 way, through a Metal 3 command buffer, and everything else stays on Metal 4"
    echo "$1"; } >"$DEVF"
}
v3_present DXMT_MTL4_PRESENT=mtl3
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "a file at version 3 with DXMT_MTL4_PRESENT=mtl3: Play would switch nothing on and say it left the list (dry run)" \
  eval 'echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: DXMT_MTL4_PRESENT=mtl3 $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14"'
dg repair >/dev/null 2>&1
check "  updated: the line, its comment and the empty line above them gone, the table's version, the rest as it was" same "$DEVF" "$SANDBOX/devf.now"
v3_present DXMT_MTL4_PRESENT=done
sed 1d "$DEVF" >"$SANDBOX/devf.v3"
dg repair >/dev/null 2>&1
dtree_names
dg rules >"$SANDBOX/dev-rules.txt" 2>&1
check "  a DXMT_MTL4_PRESENT=done line (a value I changed): kept with its comment, and in the rule after the rule's own entry, so it wins" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(sed 1d "$DEVF")" = "$(cat "$SANDBOX/devf.v3")" ] && sed -n 1p "$SANDBOX/dev-rules.txt" | grep -qE ";env=DXMT_METAL4=1;env=DXMT_MTL4_PRESENT=mtl3;(.*;)?env=DXMT_MTL4_PRESENT=done(;|\$)"'
rm -rf "$DTREE" && cp -Rp "$SANDBOX/dtree.keep" "$DTREE"
v3_present '#DXMT_MTL4_PRESENT=mtl3'
n=$(wc -l <"$DEVF" | tr -d ' ')
awk -v n="$n" 'NR > 1 && NR < n' "$DEVF" >"$SANDBOX/devf.v3"
dg repair >/dev/null 2>&1
n=$(wc -l <"$DEVF" | tr -d ' ')
awk -v n="$n" 'NR > 1 && NR < n - 1' "$DEVF" >"$SANDBOX/devf.v4"
dtree_names
dg rules >"$SANDBOX/dev-rules.txt" 2>&1
check "  commented out (to play Metal 4's own present): DXMT_MTL4_PRESENT=mtl4 in its place under a comment saying why, the rest as it was, and in the rule after the rule's own entry" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && same "$SANDBOX/devf.v3" "$SANDBOX/devf.v4" && [ "$(tail -1 "$DEVF")" = DXMT_MTL4_PRESENT=mtl4 ] && tail -2 "$DEVF" | head -1 | grep -q "^# Commented out before version 4\. DXMT_MTL4_PRESENT=mtl3 is on without this line now, so this keeps it off\." && sed -n 1p "$SANDBOX/dev-rules.txt" | grep -qE ";env=DXMT_METAL4=1;env=DXMT_MTL4_PRESENT=mtl3;(.*;)?env=DXMT_MTL4_PRESENT=mtl4(;|\$)"'
rm -rf "$DTREE" && cp -Rp "$SANDBOX/dtree.keep" "$DTREE"
# The table (version 8 took the PSO archive's two lines and DXMT_PRESENT_QUEUE=pace out: my DXMT
# fork deletes those switches) over the file of a build at version 7, which has the three lines
# under the comments that build wrote (here at the end): as written, each line and its comment go;
# a value I changed stays; commented out, it stays as it is, since there is nothing to keep off.
cp "$DEVF" "$SANDBOX/devf.now8"
v7_gone() { # <the DXMT_PRESENT_QUEUE line> <the DXMT_PSO_GENERATIONS line>
  { echo version=7; sed 1d "$SANDBOX/devf.now8"; echo
    echo "# my DXMT fork (jdrly/dxmt#157), unplayed: Present sleeps after a frame whose nextDrawable blocked (never two, which can latch 30 fps). Needs DXMT_STATS, on by default."
    echo "$1"; echo
    echo "# my DXMT fork (jdrly/dxmt#5), played: Metal binary archives of the pipelines, looked up in the last 4 sessions' archives"
    echo "DXMT_PSO_ARCHIVE=1"; echo
    echo "# my DXMT fork (jdrly/dxmt#75), unplayed: the archives published as generations instead of one file a session"
    echo "$2"; } >"$DEVF"
}
v7_gone DXMT_PRESENT_QUEUE=pace DXMT_PSO_GENERATIONS=1
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "a file at version 7 with the PSO archive's lines and DXMT_PRESENT_QUEUE=pace: Play would switch nothing on and say they left the list (dry run)" \
  eval 'echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: $GONE8 $GONE9 $GONE10 $GONE11 $GONE13 $GONE14"'
dg repair >/dev/null 2>&1
check "  updated: the three lines, their comments and the empty lines above them gone, the table's version, the rest as it was" same "$DEVF" "$SANDBOX/devf.now8"
v7_gone DXMT_PRESENT_QUEUE=two '#DXMT_PSO_GENERATIONS=1'
dg repair >/dev/null 2>&1
check "  a DXMT_PRESENT_QUEUE=two line (a value I changed) and a #DXMT_PSO_GENERATIONS=1 line (commented out): both kept as they are, DXMT_PSO_ARCHIVE=1 gone, and nothing says a rule keeps them off" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && grep -qx DXMT_PRESENT_QUEUE=two "$DEVF" && grep -qx "#DXMT_PSO_GENERATIONS=1" "$DEVF" && ! grep -q "^DXMT_PSO_ARCHIVE=" "$DEVF" && ! grep -q "^DXMT_PSO_GENERATIONS=" "$DEVF" && ! grep -q "Commented out before version 8" "$DEVF"'
cp "$SANDBOX/devf.now8" "$DEVF"
# The table (version 9 took three Metal 4 lines out: my DXMT fork has them on by default) over the
# file of a build at version 8, which has them under the comments that build wrote: as written,
# each line and its comment go; commented out, a line becomes NAME=0 under a comment saying why.
cp "$DEVF" "$SANDBOX/devf.now9"
v8_gone() { # <the DXMT_MTL4_ALLOCATOR_POOL line>
  { echo version=8; sed 1d "$SANDBOX/devf.now9"; echo
    echo "# my DXMT fork (jdrly/dxmt#153), unplayed: Metal 4 only, nothing on Metal 3: pipelines and argument buffers stay in the device's residency set, out of each chunk's"
    echo "DXMT_MTL4_DEVICE_RESIDENCY=1"; echo
    echo "# my DXMT fork (jdrly/dxmt#154), unplayed: Metal 4 only, nothing on Metal 3: timestamp queries read the chunk's last command buffer, with no empty one after it"
    echo "DXMT_MTL4_TIMESTAMP_REUSE=1"; echo
    echo "# my DXMT fork (jdrly/dxmt#204), unplayed: only with the Metal row at Metal 4, nothing on Metal 3: a Metal 4 queue's chunks take their command allocator from a pool that keeps at most 8 idle, instead of one allocator per ring slot"
    echo "$1"; } >"$DEVF"
}
v8_gone DXMT_MTL4_ALLOCATOR_POOL=1
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "a file at version 8 with the three Metal 4 lines: Play would switch nothing on and say they left the list (dry run)" \
  eval 'echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: $GONE9 $GONE10 $GONE11 $GONE13 $GONE14"'
dg repair >/dev/null 2>&1
check "  updated: the three lines, their comments and the empty lines above them gone, the table's version, the rest as it was" same "$DEVF" "$SANDBOX/devf.now9"
v8_gone '#DXMT_MTL4_ALLOCATOR_POOL=1'
dg repair >/dev/null 2>&1
check "  commented out: DXMT_MTL4_ALLOCATOR_POOL=0 in its place under a comment saying why, the other two gone" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(tail -1 "$DEVF")" = DXMT_MTL4_ALLOCATOR_POOL=0 ] && tail -2 "$DEVF" | head -1 | grep -q "^# Commented out before version 9\. DXMT_MTL4_ALLOCATOR_POOL=1 is on without this line now, so this keeps it off\." && ! grep -q "^DXMT_MTL4_DEVICE_RESIDENCY=\|^DXMT_MTL4_TIMESTAMP_REUSE=" "$DEVF"'
cp "$SANDBOX/devf.now9" "$DEVF"
# The table (version 10 took DXMT_MTL4_SHOWN_WAIT=write out: my DXMT fork has it by default) over
# the file of a build at version 9, which has it under the comment that build wrote: as written, the
# line and its comment go; a value I changed stays; commented out, it becomes
# DXMT_MTL4_SHOWN_WAIT=next under a comment saying why.
cp "$DEVF" "$SANDBOX/devf.now10"
v9_gone() { # <the DXMT_MTL4_SHOWN_WAIT line>
  { echo version=9; sed 1d "$SANDBOX/devf.now10"; echo
    echo "# my DXMT fork (jdrly/dxmt#271), unplayed: only with the Metal row at Metal 4, where the game's rule presents through a Metal 3 command buffer (DXMT_MTL4_PRESENT=mtl3), nothing on Metal 3: the Metal 4 queue waits for the last present's shown event only before the first encoder that writes the presented texture, not before the next frame's work, so that work runs while the present waits for its drawable"
    echo "$1"; } >"$DEVF"
}
v9_gone DXMT_MTL4_SHOWN_WAIT=write
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "a file at version 9 with DXMT_MTL4_SHOWN_WAIT=write: Play would switch nothing on and say it left the list (dry run)" \
  eval 'echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: $GONE10 $GONE11 $GONE13 $GONE14"'
dg repair >/dev/null 2>&1
check "  updated: the line, its comment and the empty line above them gone, the table's version, the rest as it was" same "$DEVF" "$SANDBOX/devf.now10"
v9_gone DXMT_MTL4_SHOWN_WAIT=next
dg repair >/dev/null 2>&1
check "  a DXMT_MTL4_SHOWN_WAIT=next line (a value I changed): kept with its comment" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(tail -1 "$DEVF")" = DXMT_MTL4_SHOWN_WAIT=next ] && tail -2 "$DEVF" | head -1 | grep -q "^# my DXMT fork (jdrly/dxmt#271), " && ! grep -q "Commented out before version 10" "$DEVF"'
v9_gone '#DXMT_MTL4_SHOWN_WAIT=write'
dg repair >/dev/null 2>&1
check "  commented out: DXMT_MTL4_SHOWN_WAIT=next in its place under a comment saying why" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(tail -1 "$DEVF")" = DXMT_MTL4_SHOWN_WAIT=next ] && tail -2 "$DEVF" | head -1 | grep -q "^# Commented out before version 10\. DXMT_MTL4_SHOWN_WAIT=write is on without this line now, so this keeps it off\." && ! grep -qx "#DXMT_MTL4_SHOWN_WAIT=write" "$DEVF"'
cp "$SANDBOX/devf.now10" "$DEVF"
# The table (version 11 took FEX_DISPATCHERL1LOOKUP=1 and FEX_ENTRYHEADERLOOKUP=1 out: my FEX has
# both on by default, #266) over the file of a build at version 10, which has them under the
# comments that build wrote: as written, each line and its comment go; commented out, a line
# becomes NAME=0 under a comment saying why.
cp "$DEVF" "$SANDBOX/devf.now11"
v10_gone() { # <the FEX_ENTRYHEADERLOOKUP line>
  { echo version=10; sed 1d "$SANDBOX/devf.now11"; echo
    echo "# my FEX (#161), unplayed: the dispatcher looks in the thread's L1 before it leaves for the lookup in C++"
    echo "FEX_DISPATCHERL1LOOKUP=1"; echo
    echo "# my FEX (#162), unplayed: a block's entry stores nothing, and faults, suspends and self-modifying code find the block from the host PC. Stays out while the sampler can run (WINE_HEAT_PROF or WINE_HEAT_CONTROL), which reads what the entries stored."
    echo "$1"; } >"$DEVF"
}
v10_gone FEX_ENTRYHEADERLOOKUP=1
out=$(GW2_ON_MAC_DRY_RUN=1 dg play 2>&1)
check "a file at version 10 with my FEX's two lookup lines: Play would switch nothing on and say they left the list (dry run)" \
  eval 'echo "$out" | grep -qxF "dev-switches.conf: version $DEVVER, switched on: nothing; out of the list: $GONE11 $GONE13 $GONE14"'
dg repair >/dev/null 2>&1
check "  updated: both lines, their comments and the empty lines above them gone, the table's version, the rest as it was" same "$DEVF" "$SANDBOX/devf.now11"
v10_gone '#FEX_ENTRYHEADERLOOKUP=1'
dg repair >/dev/null 2>&1
check "  commented out: FEX_ENTRYHEADERLOOKUP=0 in its place under a comment saying why, FEX_DISPATCHERL1LOOKUP gone" \
  eval '[ "$(head -1 "$DEVF")" = "version=$DEVVER" ] && [ "$(tail -1 "$DEVF")" = FEX_ENTRYHEADERLOOKUP=0 ] && tail -2 "$DEVF" | head -1 | grep -q "^# Commented out before version 11\. FEX_ENTRYHEADERLOOKUP=1 is on without this line now, so this keeps it off\." && ! grep -q "^FEX_DISPATCHERL1LOOKUP=" "$DEVF"'
cp "$SANDBOX/devf.now11" "$DEVF"

# A release: no file, its defaults; a file there anyway changes nothing
out=$(rg install steam 2>&1) && rc=0 || rc=$?
check "a release's install: no dev-switches.conf, the rows at their defaults, no dev_version" \
  eval '[ "$rc" = 0 ] && [ ! -e "$RDEVF" ] && grep -qx fastlocks=off "$RAD/settings.conf" && grep -qx launcherframes=off "$RAD/settings.conf" && grep -qx fex=engine "$RAD/settings.conf" && ! grep -q "^dev_version=" "$RAD/settings.conf"'
# (Metal 4's present in a release too: the release's tree given a DLL that names it, and back)
RTREE="$RAD/engine/lib/wine/dxgi/dxmt/aarch64-windows"
rm -rf "$SANDBOX/rtree.keep" && cp -Rp "$RTREE" "$SANDBOX/rtree.keep"
printf 'x\0DXMT_MTL4_PRESENT\0' >"$RTREE/d3d11.dll"
rg rules >"$SANDBOX/rel-rules.txt" 2>&1
check "  at Metal 4, its default, with a fork that names DXMT_MTL4_PRESENT: DXMT_MTL4_PRESENT=mtl3 right after DXMT_METAL4=1, unset for CefHost.exe" \
  eval 'grep -qx metal=4 "$RAD/settings.conf" && sed -n 1p "$SANDBOX/rel-rules.txt" | grep -qE ";env=DXMT_METAL4=1;env=DXMT_MTL4_PRESENT=mtl3(;|\$)" && sed -n 2p "$SANDBOX/rel-rules.txt" | grep -qE ";env=DXMT_METAL4=;env=DXMT_MTL4_PRESENT=(;|\$)"'
rm -rf "$RTREE" && cp -Rp "$SANDBOX/rtree.keep" "$RTREE"
rules_before=$(rg rules)
cp "$DEVF" "$RDEVF"
check "  dev-switches.conf there by hand: the rules, status and a dry run of Play don't read it" \
  eval '[ "$(rg rules)" = "$rules_before" ] && [ -z "$(rg status | sed -n "s/^dev_switches=//p")" ] && ! GW2_ON_MAC_DRY_RUN=1 rg play 2>&1 | grep -q -e MY_OWN_SWITCH -e "dev-switches.conf"'
rm -f "$RDEVF"
# (version 12's two lines in a release: a tree that names DXMT_MTL4_PRESENT_FENCES, my FEX with a
# record that names FEX_RETURNLOOKUPOUTOFLINE, and dev-switches.conf there by hand; then all back.
# The FEX setting first: setting it puts the engine's files in place, the DXMT tree too)
if fexb; then rg set fex mine >/dev/null 2>&1; dev_switches_line fex FEX_INITIALCODEBUFFERMB FEX_RETURNLOOKUPOUTOFLINE; fi
printf 'x\0DXMT_MTL4_PRESENT\0DXMT_MTL4_PRESENT_FENCES\0' >"$RTREE/d3d11.dll"
cp "$DEVF" "$RDEVF"
rg rules >"$SANDBOX/rel-rules.txt" 2>&1
rg status >"$SANDBOX/rel-status.txt" 2>&1
check "  with a tree that names DXMT_MTL4_PRESENT_FENCES, my FEX whose record names FEX_RETURNLOOKUPOUTOFLINE, and the file there: neither in the rules, DXMT_MTL4_PRESENT=mtl3 still there" \
  eval 'sed -n 1p "$SANDBOX/rel-rules.txt" | grep -qE ";env=DXMT_MTL4_PRESENT=mtl3(;|\$)" && { ! fexb || grep -qx fex_file=mine "$SANDBOX/rel-status.txt"; } && ! grep -q -e DXMT_MTL4_PRESENT_FENCES -e FEX_RETURNLOOKUPOUTOFLINE "$SANDBOX/rel-rules.txt"'
rm -f "$RDEVF"
rm -rf "$RTREE" && cp -Rp "$SANDBOX/rtree.keep" "$RTREE"
if fexb; then dev_switches_line fex FEX_INITIALCODEBUFFERMB; rg set fex engine >/dev/null 2>&1; fi
# (the sampler in a release too: my FEX chosen, its record naming FEX_ENTRYHEADERLOOKUP, and
# WINE_HEAT_PROF=on in compatdb.local; then all back)
if fexb; then
  rg set fex mine >/dev/null 2>&1
  dev_switches_line fex FEX_INITIALCODEBUFFERMB FEX_ENTRYHEADERLOOKUP
  printf 'exe=Gw2-64.exe;env=WINE_HEAT_PROF=on\n' >"$RAD/compatdb.local"
  rg rules >"$SANDBOX/rel-rules.txt" 2>&1
  check "  with my FEX and WINE_HEAT_PROF=on in compatdb.local: FEX_ENTRYHEADERLOOKUP=0 in the game's rule, as in a development build" \
    eval 'sed -n 1p "$SANDBOX/rel-rules.txt" | grep -qE ";env=FEX_ENTRYHEADERLOOKUP=0\$"'
  rm -f "$RAD/compatdb.local"
  dev_switches_line fex FEX_INITIALCODEBUFFERMB
  rg set fex engine >/dev/null 2>&1
fi
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
# A release build over it (a development build and the release share the folders, ADR 0018): the
# rows read as their defaults while the dev_version= line is there, and its next write drops the
# line and writes those defaults
rsett() { kv "$(rg settings)" "$@"; }
check "a release build over it reads the rows at their defaults: fex engine, fast locks off, raw mouse-look on, Debug logging off" \
  eval 'grep -qx dev_version=2 "$RAD/settings.conf" && grep -qx fex=mine "$RAD/settings.conf" && [ "$(rsett fex fastlocks rawmouse debug)" = engine/off/on/off ] && grep -qx dev_version=2 "$RAD/settings.conf"'
rg set quitsteam off >/dev/null
check "  its next write: no dev_version line, the rows at their defaults, my change in" \
  eval '! grep -q "^dev_version=" "$RAD/settings.conf" && grep -qx fex=engine "$RAD/settings.conf" && grep -qx fastlocks=off "$RAD/settings.conf" && grep -qx rawmouse=on "$RAD/settings.conf" && grep -qx debug=off "$RAD/settings.conf" && grep -qx quitsteam=off "$RAD/settings.conf"'
dgr repair >/dev/null 2>&1
check "  a development build after it turns the rows on again" rows_on "$RAD/settings.conf"
mkdir -p "$SANDBOX/relzip"
zip=$(GW2_ON_MAC_ROOT="$RROOT" "$RELR/collect-logs.sh" "$SANDBOX/relzip" 2>/dev/null | tail -1)
unzip -l "$zip" >"$SANDBOX/relzip.txt" 2>&1
check "a release's Collect Logs leaves out the dev-switches.conf a development build left" \
  eval '[ -f "$RDEVF" ] && [ -f "$zip" ] && grep -q settings.conf "$SANDBOX/relzip.txt" && ! grep -q dev-switches.conf "$SANDBOX/relzip.txt"'
for k in ntdll macdrv fex; do [ ! -f "$DEVKEEP/$k" ] || cp "$DEVKEEP/$k" "$COMP/$k/VERSION"; done
rm -rf "$DROOT" "$RROOT" "$DEVR" "$RELR"
fi

# (a call after the last check that ran out of its limit)
[ ! -e "$CHECKS/timeout.new" ] || bad "after the last check"
finish
