#!/bin/bash
# Summary of one game session from DXMT's log (the jdrly/dxmt fork writes it for Gw2-64.exe into
# the app's logs folder, Gw2-64_d3d11.log; gw2om.sh keeps the 4 before as .1-.4): frame rate,
# hitches (and DXMT's share of them), shader and pipeline compile waits, shader warming,
# presentation, Metal 4. As SWTOR on Mac's session report, for DXMT's lines.
#
#   session-report.sh [--keep] [--from S] [--to S] [Gw2-64_d3d11.log]
#                                  one session (default: the current log; the last session in it)
#   session-report.sh --compare A.log B.log          two sessions side by side (before/after)
#
#   --keep  also save the log as the logs folder's sessions/Gw2-64_d3d11-<date>.log: the
#           log is rotated at every game start, so keep the sessions to compare
#   --from S, --to S  the interval of the server request tables and of the game thread's
#           table, in seconds since the game started (default: the heat log's whole run)
#
# Which DXMT ran (my fork, or the engine's own, which writes none of the lines below) comes from
# the session's record, logs/session.env (DXMT_TREE, DXMT_FORK), for the current log, and so do
# which mouse the game had (its rule, RULE: GameController's counts, or the pointer's with
# gcmouse=false), which ntdll.so ran (LIB_wine: mine with its commit, or the engine's own) and its
# switches (the WINE_HEAT_* entries of the game's rule), which winemac.so ran (LIB_macdrv) and its
# switches (WINE_MACDRV_* and WINE_WIN32U_*), and which FEX ran (LIB_fex: mine with its commit, or
# the engine's own) and its switches (the FEX_* entries of the game's rule). With Debug logging my
# ntdll.so writes its counters to heat-<pid>.log in the logs folder: the report reads the newest
# one written since the session started, and from it the game thread's row, the thread with the most semaphore releases
# (it hands the job workers their jobs: about 49,000 a second, the workers a few thousand). Next to
# it, heat-requests-<pid>.log has blocks of the game thread's server requests, each the change since
# that thread's last block ("requests thread <tid> from <s> to <s> time <epoch>", jdrly/wine#15):
# the report sums that thread's blocks that lie wholly inside the interval and prints its twelve
# busiest requests and the set_cursor, get_message and set_queue_mask splits, a second too.
# A heat log whose thread rows end in "start <hex> name <text>" (jdrly/gw2-on-mac#99) has more:
# the request log follows two more threads, and each block has a line "counters <name> <n> ...",
# that thread's change since its last block, the zero ones left out. From such a log the report
# also prints the game thread's counters and timers a second and a frame, from the heat log's
# totals (which include loading) or, with --from or --to, from its blocks' counters lines; the
# lock and wait sleeps by length; the workers (the rows whose woken is at least half the busiest
# other row's) summed in one line, from the totals; and the request tables of the two other
# threads with the most server time in the interval, each under its name and start address. The
# frames are DXMT's (frames= on its GPU lines, summed over the session) for the whole run, and the
# game thread's select requests in the blocks for an interval: GW2 polls its socket once a frame.
# Without either the report gives no frame column.
# With Debug logging the game's rule has FEX_PROFILESTATS=1, and my ntdll.so puts FEX's counters of
# a block's thread into the block, one line after "requests thread" (the format is in
# jdrly/gw2-on-mac#111): "fex jit_ms <ms> jit <n> miss <n> rlock_ms <ms> wlock_ms <ms> smc <n>
# sigbus <n> float <n> signal_ms <ms> dcache_hit <n> dcache_miss <n> dcache_ms <ms>", the change
# since that thread's last block, more names maybe after those; or "fex has no slot of <n>"; or
# "fex stats version <v> slot <bytes>". From the same blocks as the request tables, for each thread
# with such lines (the game thread first) the report prints the totals, the median and the highest
# 5 s block of compile time and of lookup cache misses a second, the compile bursts (blocks in a row
# where compiling took over 10% of the time, a block without counters ending one: the first is the
# start, a later one of similar size a discard or a new map), every other name summed as it is, and
# the blocks without counters with the last such line. The rule has FEX_SILENTLOG=0 too, and FEX's
# lines go to wine.log ("<I|E|D> <thread id in hex> <message>", "A <message>" for an assertion):
# the report says whether one was "FEX: Using hardware TSO", how many FEX wrote, how many a second
# from Play to the log's last write, and how many were errors. My Mac
# driver writes its macsurface lines to wine.log for Gw2-64.exe ("hwnd <h> ...: <n> flushes, ..."
# every 600 flushes of a window): the report prints the last line of the window with the most
# flushes, which is the launcher's (it flushes about 40 times a second; the game draws with Metal).
# Each vmmap-<date>-<time>.txt written since the session started (gw2om.sh vmmap, or Collect Logs
# while the game runs) gives one line: minutes in, the footprint, and FEX's code buffers (its rwx/rwx
# regions) by size. FEX starts a new buffer twice the size, up to 128 MB, each time it throws its
# code away, so the largest is the one in use and the others are full; the buffers less one is how
# often it threw its code away.
# Sources, all from the fork's own lines (DXMT_STATS is on by default):
#   "GW2 fork <version>: …"  the start of a session: DXMT's version, its switches, cpus, refresh
#   STATS    the frame rate and frame times (avg/max ms) of each interval, the command buffers
#            and render passes per frame, the encode thread's time
#   HITCH    each frame over DXMT_HITCH_MS (50): its time and DXMT's calls in it (ms/calls)
#   COMPILE  shader variants and pipelines built, DXMT's encode thread's waits for them: each
#            window's count, total and longest (wait=Nx total/max ms)
#   WARM     shader warming: pipelines planned and built ahead (DXMT_WARM)
#   PRESENT  presentation: presented-to-display latency, missed and dropped frames
#   METAL4   Metal 4 commits and errors
# Also in Collect Logs (session-report.txt). Runs under macOS's /bin/bash 3.2 and awk.
set -euo pipefail
# The app's logs folder (as gw2om.sh's APP_FOLDER)
APP_FOLDER="GW2 on Mac arm64"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

KEEP="" COMPARE="" FROM=0 TO="" RANGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1; shift ;;
    --compare) COMPARE=1; shift ;;
    --from|--to)
      case "${2:-}" in ''|.|*[!0-9.]*|*.*.*) usage ;; esac
      if [ "$1" = --from ]; then FROM=$2; else TO=$2; fi
      RANGE=1
      shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) break ;;
  esac
done
ROOT="${GW2_ON_MAC_ROOT:-}"
H="${ROOT:+$ROOT/home}"
H="${H:-$HOME}"
LOGS="$H/Library/Logs/$APP_FOLDER"

# summary <log>: KEY=VALUE lines of its last session
summary() {
  LC_ALL=C awk '
    /GW2 fork .*: DXMT_STATS=/ {
      # a new session: forget the one before
      n = 0; delete fps; summs = 0; maxms = 0; hitches = 0; worst = 0; delete dx; variants = 0; builtp = 0
      failed = 0; waits = 0; waitms = 0; waitmax = 0; warm = ""; warmp = 0; present = ""; m4commits = 0; m4errors = 0; cb = 0; rp = 0
      enc = 0; missed = 0; dropped = 0; slowc = 0
      v = $0; sub(/.*GW2 fork /, "", v); sub(/:.*/, "", v); version = v
      c = $0; cpus = (match(c, /cpus=[0-9]+/) ? substr(c, RSTART + 5, RLENGTH - 5) : "?")
      r = $0; refresh = (match(r, /refresh=[0-9.]+/) ? substr(r, RSTART + 8, RLENGTH - 8) : "?")
      sw = $0; sub(/.*: DXMT_STATS=/, "DXMT_STATS=", sw); switches = sw
      sessions++; frames = 0
      next
    }
    function val(line, key,    s) {
      if (!match(line, key "=[^ ]+")) return ""
      s = substr(line, RSTART + length(key) + 1, RLENGTH - length(key) - 1)
      return s
    }
    /info: +STATS fps=/ {
      f = val($0, "fps") + 0; fps[++n] = f
      ms = val($0, "ms"); split(ms, a, "/"); summs += a[1]; if (a[2] + 0 > maxms) maxms = a[2] + 0
      cb += val($0, "cb") + 0; rp += val($0, "rp") + 0
      e = val($0, "encode"); split(e, b, "/"); split(b[1], c2, "+"); enc += c2[1] + c2[2]
      next
    }
    /info: +HITCH frame=/ {
      hitches++; ms = val($0, "ms") + 0; if (ms > worst) worst = ms
      s = $0; sub(/.*dxmt\(ms\/calls\): */, "", s)
      k = split(s, parts, " ")
      for (i = 1; i <= k; i++) { split(parts[i], kv, "="); split(kv[2], mc, "/"); dx[kv[1]] += mc[1] }
      next
    }
    /info: +COMPILE variants=/ {
      variants += val($0, "variants") + 0; builtp += val($0, "built") + 0; failed += val($0, "failed") + 0
      w = $0; if (match(w, /wait=[0-9]+x [0-9.]+\/[0-9.]+/)) { split(substr(w, RSTART + 5, RLENGTH - 5), wx, "x "); waits += wx[1]; split(wx[2], wt, "/"); waitms += wt[1]; if (wt[2] + 0 > waitmax) waitmax = wt[2] + 0 }
      slowc += val($0, "slow") + 0
      next
    }
    # (the line with the most pipelines built: warming reports as it goes)
    /info: +WARM functions=/ { p = val($0, "pipelines") + 0; if (warm == "" || p >= warmp) { warmp = p; warm = $0; sub(/.*WARM /, "", warm) } next }
    /info: +PRESENT presented=/ {
      present = val($0, "presented"); missed += val($0, "missed") + 0; dropped += val($0, "dropped") + 0; next
    }
    /info: +METAL4 commits=/ { m4commits += val($0, "commits") + 0; m4errors += val($0, "errors") + 0; next }
    /info: +GPU .*frames=/ { frames += val($0, "frames"); next }
    END {
      if (!sessions) { print "sessions=0"; exit }
      print "sessions=" sessions; print "version=" version; print "cpus=" cpus; print "refresh=" refresh
      print "switches=" switches
      print "samples=" n
      if (n) {
        # fps: median, the low (10th percentile), min
        for (i = 1; i <= n; i++) s2[i] = fps[i]
        for (i = 2; i <= n; i++) { x = s2[i]; j = i - 1; while (j > 0 && s2[j] > x) { s2[j + 1] = s2[j]; j-- } s2[j + 1] = x }
        printf "fps_median=%.1f\nfps_low=%.1f\nfps_min=%.1f\n", s2[int((n + 1) / 2)], s2[int(n / 10) + 1], s2[1]
        printf "ms_avg=%.1f\nms_max=%.1f\ncb=%.1f\nrp=%.1f\nencode=%.2f\n", summs / n, maxms, cb / n, rp / n, enc / n
      }
      print "hitches=" hitches; printf "hitch_worst=%.0f\n", worst
      top = ""
      for (k2 in dx) if (dx[k2] >= 1) top = top sprintf("%s %.0f ms, ", k2, dx[k2])
      sub(/, $/, "", top); print "hitch_dxmt=" top
      print "variants=" variants; print "pipelines_built=" builtp; print "compile_failed=" failed
      printf "compile_waits=%d\ncompile_wait_ms=%.0f\ncompile_wait_max=%.1f\n", waits, waitms, waitmax
      print "warm=" warm; print "present=" present; print "missed=" missed; print "dropped=" dropped
      print "metal4_commits=" m4commits; print "metal4_errors=" m4errors
      print "gpu_frames=" frames
    }' "$1"
}

get() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# lib_report <key> <what mine is> <switches' prefix, an extended regex>: the file of gw2om.sh's unix_lib <key> that the
# session loaded (session.env's LIB_<key>) and its switches, the entries of the game's rule that
# match the pattern; fails without LIB_<key>
lib_report() {
  local lib name f commit hash switches
  lib=$(sed -n "s/^LIB_$1=//p" "$LOGS/session.env")
  [ -n "$lib" ] || return 1
  read -r name f commit hash <<<"$lib"
  case "$f" in
    mine) echo "$name that ran: $2, jdrly/wine ${commit:0:11} (sha256 ${hash:0:12})" ;;
    engine) echo "$name that ran: the engine's own, athei/wine $commit" ;;
    *) echo "$name that ran: neither the engine's own nor mine (sha256 ${hash:0:12})" ;;
  esac
  switches=$(sed -n 's/^RULE=exe=Gw2-64\.exe;//p' "$LOGS/session.env" | tr ';' '\n' |
    sed -n -E -e '/^env=WINE_HEAT_LOG=/d' -e "s/^env=($3[A-Z_]*=.*)/\\1/p" | tr '\n' ' ' | sed 's/ $//')
  echo "Its switches: ${switches:-none}"
}

# wine_report <frames>: the ntdll.so the session loaded and its switches (session.env), the game
# thread's row of the session's heat log, a second, and that thread's server requests in
# --from..--to from heat-requests-<pid>.log, when there is one. From a log of #99's format also the
# game thread's table, the workers' line and the two other threads' requests (<frames>: DXMT's
# frames in the session, 0 without them)
wine_report() {
  local heat req
  lib_report wine "my Wine build" 'WINE_HEAT_' || return 0
  heat=$(ls -t "$LOGS"/heat-[0-9]*.log 2>/dev/null | head -1 || true)
  [ -n "$heat" ] && [ "$heat" -nt "$LOGS/session.env" ] || return 0
  req="$LOGS/heat-requests-$(basename "$heat" | sed 's/^heat-//')"
  [ -f "$req" ] || req=""
  LC_ALL=C awk -v name="$(basename "$heat")" -v from="$FROM" -v to="$TO" -v range="$RANGE" -v frames="${1:-0}" '
    FILENAME == ARGV[1] && FNR == 1 { for (i = 1; i < NF; i++) if ($i == "seconds") secs = $(i + 1) + 0; next }
    FILENAME == ARGV[1] && $1 == "thread" {
      rows[++nrows] = $0
      r = 0
      for (i = 3; i < NF; i += 2) {
        if ($i == "release") r = $(i + 1) + 0
        if ($i == "start") tstart[$2] = $(i + 1)
        if ($i == "name") tname[$2] = $(i + 1)
      }
      if (row == "" || r > most) { most = r; row = $0 }
    }
    FILENAME == ARGV[1] { next }
    # heat-requests-<pid>.log: the game thread is the heat log row, read by now
    FNR == 1 {
      reqname = FILENAME; sub(/.*\//, "", reqname); split(row, g, " "); game = g[2]
      # (without --to, the heat log run: the dump writes the heat log just before the block and
      # both round to a tenth)
      if (to == "") { to = secs; end = secs + 0.15 } else { to += 0; end = to }
      from += 0
    }
    # the blocks wholly inside the interval, by thread
    $1 == "requests" {
      t = $3; take = ($2 == "thread" && $5 + 0 >= from && $7 + 0 <= end)
      if (take) { if (!(t in blocks)) tids[++ntids] = t; blocks[t]++; covered[t] += $7 - $5 }
      bfrom = $5 + 0; bto = $7 + 0
      next
    }
    !take { next }
    # the counters FEX keeps for the thread of the block: the series, by block (with its place among
    # the thread blocks, so a block without counters ends a burst), and the sum of each name
    $1 == "fex" {
      if (!(t in fseen)) { fseen[t] = 1; forder[++nfex] = t }
      if ($2 == "has" || $2 == "stats") { fmsg[t] = $0; fmsgn[t]++; next }
      k = ++fexn[t]; ffrom[t, k] = bfrom; fto[t, k] = bto; fseq[t, k] = blocks[t]
      for (i = 2; i < NF; i += 2) {
        if (!((t, $i) in fsum)) fnames[t, ++nfnames[t]] = $i
        fsum[t, $i] += $(i + 1); fv[t, k, $i] = $(i + 1) + 0
      }
      next
    }
    $1 == "req" { k = t SUBSEP $2; if (!(k in rn)) names[t, ++nnames[t]] = $2; rn[k] += $3; rt[k] += $4; next }
    $1 == "message" { k = t SUBSEP $2; if (!(k in mn)) msgs[t, ++nmsgs[t]] = $2; mn[k] += $3; next }
    $1 == "set_cursor" || $1 == "get_message" || $1 == "set_queue_mask" {
      for (i = 2; i < NF; i += 2) { k = t SUBSEP $1 " " $i; if (!(k in sn)) splits[t, ++nsplits[t]] = $1 " " $i; sn[k] += $(i + 1) }
      next
    }
    # (server_ms ranks the other threads: the req lines are only the twelve busiest by count)
    $1 == "counters" {
      for (i = 2; i < NF; i += 2) { if (t == game) bc[$i] += $(i + 1); if ($i == "server_ms") srv[t] += $(i + 1) }
    }
    # <n> and <n> a second in <c> seconds
    function rate(n, c) { return sprintf("%.0f (%.1f)", n, c > 0 ? n / c : 0) }
    # the line of thread <t>s split <s>: its counters in the log order
    function split_line(t, s,    i, k, out) {
      out = ""
      for (i = 1; i <= nsplits[t]; i++) if (index(splits[t, i], s " ") == 1) {
        k = splits[t, i]; sub(/^[^ ]* /, "", k); out = out (out == "" ? "" : ", ") k " " rate(sn[t, splits[t, i]], covered[t])
      }
      if (out != "") print "  " s ": " out
    }
    # thread <t>s name and start address, from the heat log
    function who(t) {
      if (!(t in tname)) return "not in the heat log"
      return (tname[t] == "-" ? "no name" : "named " tname[t]) ", start " tstart[t]
    }
    # the request table of thread <t>, <what> it is
    function req_table(t, what,    i, j, b, m, c, out) {
      c = covered[t]
      printf "Server requests of thread %s, %s, in %s from %.1f to %.1f s: blocks wholly inside %d, covering %.1f s; each count, then a second in brackets\n", \
        t, what, reqname, from, to, blocks[t], c
      # the twelve busiest, by count (the first seen first on a tie)
      for (j = 1; j <= 12; j++) {
        b = ""; for (i = 1; i <= nnames[t]; i++) { m = names[t, i]; if (!((t, m) in done) && (b == "" || rn[t, m] > rn[t, b])) b = m }
        if (b == "") break
        done[t, b] = 1
        printf "  %s %s, %.3f ms (%.3f)\n", b, rate(rn[t, b], c), rt[t, b], (c > 0 ? rt[t, b] / c : 0)
      }
      split_line(t, "set_cursor")
      split_line(t, "get_message")
      # the ten busiest messages of the replies, then those the log calls unlisted
      out = ""
      for (j = 1; j <= 10; j++) {
        b = ""; for (i = 1; i <= nmsgs[t]; i++) { m = msgs[t, i]; if (m != "unlisted" && !((t, m) in mdone) && (b == "" || mn[t, m] > mn[t, b])) b = m }
        if (b == "") break
        mdone[t, b] = 1; out = out (out == "" ? "" : ", ") b " " rate(mn[t, b], c)
      }
      if ((t, "unlisted") in mn) out = out (out == "" ? "" : ", ") "unlisted " rate(mn[t, "unlisted"], c)
      if (out != "") print "  message: " out
      split_line(t, "set_queue_mask")
    }
    # the median of a[1..n], which it sorts
    function median(a, n,    i, j, x) {
      for (i = 2; i <= n; i++) { x = a[i]; j = i - 1; while (j > 0 && a[j] > x) { a[j + 1] = a[j]; j-- } a[j + 1] = x }
      return n % 2 ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
    }
    # a compile burst from <bs> to <be> s with <bj> blocks compiled
    function burst(bs, be, bj) { return sprintf("at %.1f s for %.1f s, %.0f blocks", bs, be - bs, bj) }
    # the counters FEX keeps for thread <t>, <what> it is
    function fex_thread(t, what,    k, d, c, n, jr, mr, jmax, mmax, hot, inb, bs, be, bj, out, i, m, w) {
      if (!fexn[t]) {
        m = fmsg[t]; split(m, w, " ")
        if (w[2] == "has") printf "FEX\047s counters of thread %s, %s: none, FEX had no slot left for it (%s in use). Its stats have room for about 36 threads and can\047t grow on macOS.\n", t, what, w[6]
        else printf "FEX\047s counters of thread %s, %s: my ntdll.so can\047t read them: %s\n", t, what, m
        return
      }
      c = 0; n = 0; jmax = 0; mmax = 0
      for (k = 1; k <= fexn[t]; k++) {
        d = fto[t, k] - ffrom[t, k]; c += d
        if (d <= 0) continue
        jr[++n] = fv[t, k, "jit_ms"] / d; mr[n] = fv[t, k, "miss"] / d
        if (jr[n] > jmax) jmax = jr[n]
        if (mr[n] > mmax) mmax = mr[n]
      }
      printf "FEX\047s counters of thread %s, %s, in %s from %.1f to %.1f s: %d blocks, covering %.1f s\n", t, what, reqname, from, to, fexn[t], c
      printf "  In all: compiling %.3f ms, %.0f blocks; lookup cache misses %.0f, its lock %.3f ms read, %.3f ms write; SMC %.0f; signals %.3f ms\n", \
        fsum[t, "jit_ms"], fsum[t, "jit"], fsum[t, "miss"], fsum[t, "rlock_ms"], fsum[t, "wlock_ms"], fsum[t, "smc"], fsum[t, "signal_ms"]
      if (n) printf "  A second, the median and the highest 5 s: compiling %.3f and %.3f ms, lookup cache misses %.0f and %.0f\n", median(jr, n), jmax, median(mr, n), mmax
      # (blocks of the thread in a row whose compile time is over 10% of their time: ms over 100
      # times the seconds; a block of the thread without counters ends one)
      out = ""; inb = 0
      for (k = 1; k <= fexn[t]; k++) {
        d = fto[t, k] - ffrom[t, k]; hot = (d > 0 && fv[t, k, "jit_ms"] > 100 * d)
        if (inb && (!hot || fseq[t, k] != fseq[t, k - 1] + 1)) { out = out (out == "" ? "" : "; ") burst(bs, be, bj); inb = 0 }
        if (hot) { if (!inb) { inb = 1; bs = ffrom[t, k]; bj = 0 } be = fto[t, k]; bj += fv[t, k, "jit"] }
      }
      if (inb) out = out (out == "" ? "" : "; ") burst(bs, be, bj)
      print "  Compile bursts, compiling over 10% of the time: " (out == "" ? "none" : out)
      if (fmsgn[t]) printf "  %d of its blocks had no counters, the last with: %s\n", fmsgn[t], fmsg[t]
      out = ""
      for (i = 1; i <= nfnames[t]; i++) {
        m = fnames[t, i]; if (m ~ /^(jit_ms|jit|miss|rlock_ms|wlock_ms|smc|signal_ms)$/) continue
        out = out (out == "" ? "" : ", ") m " " sprintf(m ~ /_ms$/ ? "%.3f" : "%.0f", fsum[t, m])
      }
      if (out != "") print "  Also, in all: " out
    }
    # every thread with FEX lines in the interval, the game thread first
    function fex_report(    i) {
      if (game in fseen) fex_thread(game, "the game thread")
      for (i = 1; i <= nfex; i++) if (forder[i] != game) fex_thread(forder[i], forder[i] in tname ? who(forder[i]) : "another thread")
    }
    # counter or timer <k> of the game thread: from its blocks, or from the heat log totals
    function v(k) { return (useblk ? bc[k] : gv[k]) + 0 }
    # a row of the game thread table: counter <c> a second and a frame, timer <tm> ms a frame
    # (ms a second without frames); either may be ""
    function table_row(c, tm,    lab, a, b, ms, s) {
      lab = c; if (lab == "") lab = tm; else if (tm != "") lab = c ", " tm
      a = ""; b = ""; ms = ""
      if (c != "" && sec > 0) a = sprintf("%.1f", v(c) / sec)
      if (c != "" && fr > 0) b = sprintf("%.2f", v(c) / fr)
      if (tm != "" && fr > 0) ms = sprintf("%.3f", v(tm) / fr)
      if (tm != "" && fr <= 0 && sec > 0) ms = sprintf("%.3f", v(tm) / sec)
      if (fr > 0) s = sprintf("  %-22s %10s %10s %11s", lab, a, b, ms)
      else s = sprintf("  %-22s %10s %11s", lab, a, ms)
      sub(/ +$/, "", s); print s
    }
    # the sleeps <p>_sleep by length (the buckets of the yield), as shares of them
    function lengths(p, what,    all, i, out) {
      if (!((p "_sleep") in gv) || !((p "_long") in gv) || (all = v(p "_sleep")) <= 0) return
      split("5us 20us 100us 1ms long", hk, " "); split("under 5 us,5 to 20 us,20 to 100 us,0.1 to 1 ms,1 ms or more", hl, ",")
      out = ""
      for (i = 1; i <= 5; i++) out = out (i > 1 ? ", " : "") hl[i] " " sprintf("%.1f%%", 100 * v(p "_" hk[i]) / all)
      print "  " what " by length: " out
    }
    # the game thread table: its counters and timers a second and a frame, and the sleeps by length
    function game_table(    i, m, how, src, tm) {
      useblk = (range != "")
      if (useblk && reqname == "") { printf "The game thread, thread %s (%s): no server requests log, so no table for --from and --to\n", game, who(game); return }
      sec = (useblk ? covered[game] : secs)
      if (frames > 0 && !useblk) { fr = frames; how = "counted by DXMT" } else { fr = rn[game, "select"] + 0; how = "by the game\047s socket poll" }
      src = "from the heat log totals, which include loading"
      if (useblk) src = sprintf("from the counters lines of its blocks wholly inside %.1f to %.1f s", from, to)
      how = (fr > 0 ? sprintf("%d frames %s", fr, how) : "no frame count")
      printf "The game thread, thread %s (%s), %s: %.1f s, %s\n", game, who(game), src, sec, how
      if (fr > 0) printf "  %-22s %10s %10s %11s\n", "", "a second", "a frame", "ms a frame"
      else printf "  %-22s %10s %11s\n", "", "a second", "ms a second"
      m = split("lock_sleep:lock_ms wait_sleep:wait_ms :wake_ms alert_wake:alert_ms server:server_ms release wake_skipped" \
        " wake_one wake_none event_set event_wake event_wake_none wait wait_timed wait_poll evpool_hit lspin_hit lspin_miss" \
        " espin_hit espin_miss sspin_hit sspin_miss spin_scoped qpc yield", spec, " ")
      for (i = 1; i <= m; i++) {
        tm = ""; if (split(spec[i], p, ":") > 1) tm = p[2]
        if (tm != "" && !(tm in gv)) tm = ""
        if (p[1] == "" && tm == "" || p[1] != "" && !(p[1] in gv)) continue
        table_row(p[1], tm)
      }
      lengths("lock", "lock sleeps")
      lengths("wait", "wait sleeps")
    }
    # the workers: the other rows whose woken is at least half that of the busiest other row, summed
    function workers(    r, i, n, w, most, nw, out, k, wf) {
      most = 0
      for (r = 1; r <= nrows; r++) {
        n = split(rows[r], wr, " "); if (wr[2] == game) continue
        for (i = 3; i < n; i += 2) if (wr[i] == "woken" && wr[i + 1] + 0 > most) most = wr[i + 1] + 0
      }
      if (most <= 0) return
      for (r = 1; r <= nrows; r++) {
        n = split(rows[r], wr, " "); if (wr[2] == game) continue
        w = 0; for (i = 3; i < n; i += 2) if (wr[i] == "woken") w = wr[i + 1] + 0
        if (w * 2 < most) continue
        nw++; for (i = 3; i < n; i += 2) ws[wr[i]] += wr[i + 1]
      }
      wf = (frames > 0 ? frames : (useblk ? 0 : fr))
      out = ""
      split("lock_sleep lock_ms woken spurious sspin_hit sspin_miss", wk, " ")
      for (i = 1; i <= 6; i++) {
        k = wk[i]; if (!(k in ws)) continue
        out = out (out == "" ? "" : ", ") k " " sprintf(k ~ /_ms$/ ? "%.1f" : "%.0f", ws[k] / secs)
        if (wf > 0) out = out sprintf(k ~ /_ms$/ ? " (%.3f)" : " (%.2f)", ws[k] / wf)
      }
      printf "The workers, %d threads whose woken is at least half the busiest other thread\047s, from the heat log totals, a second%s: %s\n", \
        nw, (wf > 0 ? " (a frame)" : ""), out
    }
    END {
      if (row == "" || secs <= 0) exit
      n = split(row, f, " "); out = ""; game = f[2]
      for (i = 3; i < n; i += 2) {
        gv[f[i]] = f[i + 1]
        k = f[i]; if (k !~ /^(release|wake_skipped|wake_one|wake_none|woken|spurious|server|lock_sleep|yield)$/) continue
        out = out sprintf("%s%s %.0f", out == "" ? "" : ", ", k, f[i + 1] / secs)
      }
      printf "Heat log %s (%.0f s): the game thread, thread %s (the most releases), a second: %s\n", name, secs, f[2], out
      # (a log of #99s format: its rows name the threads)
      if ("name" in gv) { game_table(); workers() }
      if (reqname == "") exit
      req_table(game, "the game thread")
      fex_report()
      if (!("name" in gv)) exit
      # the two other threads with the most server time in the interval
      for (j = 1; j <= 2; j++) {
        b = ""; for (i = 1; i <= ntids; i++) { t = tids[i]; if (t != game && !(t in odone) && (b == "" || srv[t] > srv[b])) b = t }
        if (b == "") break
        odone[b] = 1; req_table(b, who(b))
      }
    }' "$heat" ${req:+"$req"}
}

# fex_tso_report: with FEX_SILENTLOG=0 in the game's rule, what FEX said in wine.log about memory
# ordering, how many lines it wrote, how many a second from Play (session.env) to the log's last
# write, and how many of them were errors (E) or assertions (A)
fex_tso_report() {
  local secs
  grep -qE '^RULE=exe=Gw2-64\.exe;(.*;)?env=FEX_SILENTLOG=0(;|$)' "$LOGS/session.env" && [ -f "$LOGS/wine.log" ] || return 0
  secs=$(( $(date -r "$LOGS/wine.log" +%s) - $(date -r "$LOGS/session.env" +%s) ))
  LC_ALL=C awk -v secs="$secs" '
    /^[IEDA] [0-9A-F]+ / || /^A / { lines++ }
    /^E [0-9A-F]+ / || /^A / { errors++ }
    /FEX: Using hardware TSO/ { tso = 1 }
    END {
      s = (tso ? "Memory ordering: hardware TSO (FEX said so)" : "FEX didn\047t say it uses hardware TSO")
      s = s sprintf("; FEX wrote %d lines to wine.log", lines)
      if (secs > 0) s = s sprintf(", %.2f a second over the %.1f min from Play to its last line", lines / secs, secs / 60)
      if (errors) s = s sprintf(", %d of them errors", errors)
      print s
    }' "$LOGS/wine.log"
}

# macdrv_report: the winemac.so the session loaded and its switches (session.env), and the last
# macsurface line of the window with the most flushes in wine.log
macdrv_report() {
  lib_report macdrv "my Mac driver" 'WINE_(MACDRV|WIN32U)_' || return 0
  [ -f "$LOGS/wine.log" ] || return 0
  LC_ALL=C awk '
    /:macsurface:/ {
      h = ""; n = -1
      for (i = 1; i < NF; i++) {
        if ($i == "hwnd") h = $(i + 1)
        if ($(i + 1) ~ /^flushes/ && $i ~ /^[0-9]+$/) n = $i + 0
      }
      if (h == "" || n < 0) next
      line[h] = $0; flushes[h] = n
    }
    END {
      for (h in line) if (best == "" || flushes[h] > flushes[best]) best = h
      if (best == "") exit
      s = line[best]; sub(/.*:macsurface:[^ ]* /, "", s)
      print "Its last macsurface line, the window with the most flushes (the launcher): " s
    }' "$LOGS/wine.log"
}

# vmmap_report: a line for each vmmap file of the session, in the order they were taken
vmmap_report() {
  local f
  for f in "$LOGS"/vmmap-*.txt; do
    [ -f "$f" ] && [ "$f" -nt "$LOGS/session.env" ] || continue
    LC_ALL=C awk -v name="${f##*/}" '
      FNR == 1 { for (i = 1; i < NF; i++) if ($i == "running") secs = $(i + 1) }
      /^vmmap failed/ { failed = $0 }
      /^Physical footprint:/ { fp = $3 }
      /^Physical footprint \(peak\):/ { peak = $4 }
      # (Untagged  <start>-<end> [ VSIZE RSDNT DIRTY SWAP] rwx/rwx SM=PRV)
      / rwx\/rwx / { s = $0; sub(/.*\[ */, "", s); split(s, c, / +/); n++; vs[n] = c[1]; rs[n] = c[2]; by[n] = bytes(c[1]) }
      function bytes(v,    x, u) {
        x = v + 0; u = substr(v, length(v))
        if (u == "K") x *= 1024; else if (u == "M") x *= 1048576; else if (u == "G") x *= 1073741824
        return x
      }
      END {
        at = (secs ~ /^[0-9]+$/ ? sprintf("at %.1f min", secs / 60) : "at an unknown time")
        if (failed != "") { printf "vmmap %s (%s): %s\n", at, name, failed; exit }
        out = ""
        if (n) {
          # by size, the smallest first; the same size in the order of the list
          for (i = 1; i <= n; i++) o[i] = i
          for (i = 2; i <= n; i++) { x = o[i]; j = i - 1; while (j > 0 && by[o[j]] > by[x]) { o[j + 1] = o[j]; j-- } o[j + 1] = x }
          for (i = 1; i <= n; i++) {
            v = vs[o[i]]; if (v ~ /\.0[KMG]$/) v = substr(v, 1, length(v) - 3) substr(v, length(v))
            out = out (i > 1 ? ", " : "") v " " (i < n ? "full" : rs[o[i]] " resident")
          }
          out = out "; FEX has thrown its code away " (n == 2 ? "once" : (n - 1) " times")
        } else out = "none (no rwx/rwx region)"
        printf "vmmap %s (%s): footprint %s, peak %s; code buffers %s\n", at, name, fp, peak, out
      }' "$f"
  done
}

# fex_report: the FEX the session ran (session.env's LIB_fex: mine <commit> <sha256>, or engine)
# and the FEX_* entries of the game's rule
fex_report() {
  local lib f commit hash switches
  lib=$(sed -n 's/^LIB_fex=//p' "$LOGS/session.env")
  [ -n "$lib" ] || return 0
  read -r f commit hash <<<"$lib"
  case "$f" in
    mine) echo "FEX that ran: my FEX, jdrly/FEX ${commit:0:11} (xtajit64.dll sha256 ${hash:0:12})" ;;
    engine) echo "FEX that ran: the engine's own, athei/FEX $(sed -n 's/^ENGINE_FEX=//p' "$LOGS/session.env")" ;;
    *) echo "FEX that ran: $f" ;;
  esac
  switches=$(sed -n 's/^RULE=exe=Gw2-64\.exe;//p' "$LOGS/session.env" | tr ';' '\n' |
    sed -n -E 's/^env=(FEX_[A-Z0-9_]*=.*)/\1/p' | tr '\n' ' ' | sed 's/ $//')
  echo "Its switches: ${switches:-none}"
}

report() {  # <log>
  local s ran=""
  s=$(summary "$1")
  echo "Session: $1 (the last of $(get "$s" sessions) in it)"
  if [ -f "$LOGS/session.env" ] && [ "$(dirname "$1")" = "$LOGS" ]; then
    case "$(sed -n 's/^DXMT_TREE=//p' "$LOGS/session.env")" in
      fork) ran="my DXMT fork, $(sed -n 's/^DXMT_FORK=//p' "$LOGS/session.env")" ;;
      engine) ran="the engine's own DXMT, athei/dxmt $(sed -n 's/^ENGINE_DXMT=//p' "$LOGS/session.env")" ;;
      ?*) ran="a DXMT that is neither the engine's own nor mine" ;;
    esac
    [ -z "$ran" ] || echo "DXMT that ran: $ran"
    # (the game's rule as play wrote it: gcmouse=false with raw mouse-look off)
    if grep -qE '^RULE=exe=Gw2-64\.exe;(.*;)?gcmouse=false(;|$)' "$LOGS/session.env"; then
      echo "Mouse the game had: the pointer's movement, as Wine does it (gcmouse=false)"
    else
      echo "Mouse the game had: the mouse's own counts from GameController (the engine's built-in rule)"
    fi
    wine_report "$(get "$s" gpu_frames)"
    fex_report
    fex_tso_report
    macdrv_report
    vmmap_report
  fi
  if [ "$(get "$s" sessions)" = 0 ]; then
    case "$ran" in
      "the engine's"*) echo "No session of my DXMT fork in this log: the engine's DXMT writes no STATS lines." ;;
      *) echo "No session of my DXMT fork in this log." ;;
    esac
    return
  fi
  echo "DXMT $(get "$s" version), $(get "$s" cpus) CPUs seen, display at $(get "$s" refresh) Hz"
  if [ -f "$LOGS/session.env" ] && [ "$(dirname "$1")" = "$LOGS" ]; then
    echo "Settings at the start: $(sed -n 's/^SETTING_//p' "$LOGS/session.env" | tr '\n' ' ')"
  fi
  echo
  if [ "$(get "$s" samples)" -gt 0 ]; then
    echo "Frame rate: median $(get "$s" fps_median), low (10th percentile) $(get "$s" fps_low), min $(get "$s" fps_min) fps ($(get "$s" samples) intervals)"
    echo "Frame time: average $(get "$s" ms_avg) ms, the longest $(get "$s" ms_max) ms"
    echo "Per frame: $(get "$s" cb) command buffers, $(get "$s" rp) render passes; encode thread $(get "$s" encode) ms"
  else
    echo "No STATS lines (DXMT_STATS=0?)"
  fi
  echo "Hitches (frames over 50 ms): $(get "$s" hitches), the worst $(get "$s" hitch_worst) ms"
  [ -z "$(get "$s" hitch_dxmt)" ] || echo "  DXMT's time in them: $(get "$s" hitch_dxmt)"
  echo "Compiles: $(get "$s" variants) shader variants, $(get "$s" pipelines_built) pipelines built, $(get "$s" compile_failed) failed;" \
    "DXMT's encode thread waited $(get "$s" compile_waits) times, about $(get "$s" compile_wait_ms) ms in all, the longest $(get "$s" compile_wait_max) ms"
  [ -z "$(get "$s" warm)" ] || echo "Shader warming: $(get "$s" warm | cut -c1-160)"
  [ -z "$(get "$s" present)" ] || echo "Presentation: presented-to-display $(get "$s" present) ms (min/avg/max), $(get "$s" missed) missed, $(get "$s" dropped) dropped"
  echo "Metal 4: $(get "$s" metal4_commits) commits, $(get "$s" metal4_errors) errors"
}

compare() {  # <A> <B>
  local a b k
  a=$(summary "$1"); b=$(summary "$2")
  printf '%-34s %18s %18s\n' "" "A" "B"
  printf '%-34s %18s %18s\n' "log" "$(basename "$1")" "$(basename "$2")"
  for k in version fps_median fps_low fps_min ms_avg ms_max cb rp encode hitches hitch_worst variants pipelines_built \
    compile_waits compile_wait_ms compile_wait_max missed dropped metal4_errors; do
    printf '%-34s %18s %18s\n' "$k" "$(get "$a" "$k" | cut -c1-18)" "$(get "$b" "$k" | cut -c1-18)"
  done
}

if [ -n "$COMPARE" ]; then
  [ $# -eq 2 ] || usage
  compare "$1" "$2"
  exit 0
fi
LOG="${1:-$LOGS/Gw2-64_d3d11.log}"
[ -f "$LOG" ] || { echo "No DXMT log at $LOG (play a session first)" >&2; exit 1; }
report "$LOG"
if [ -n "$KEEP" ]; then
  mkdir -p "$LOGS/sessions"
  cp "$LOG" "$LOGS/sessions/Gw2-64_d3d11-$(date -r "$LOG" +%Y%m%d-%H%M).log"
  echo "Kept as $LOGS/sessions/Gw2-64_d3d11-$(date -r "$LOG" +%Y%m%d-%H%M).log"
fi
