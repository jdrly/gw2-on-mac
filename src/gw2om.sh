#!/bin/bash
# The install, status, play and settings logic behind the app's window. Unlike SWTOR
# on Mac it changes no existing install: it creates its own Wine engine and bottle and installs the
# game through Steam or ArenaNet's own installer. On this line the engine is Mach9's arm64 Wine as
# it ships, with three exceptions: its DXMT tree is my DXMT fork's (components/dxmt), its ntdll.so
# is my Wine build's (components/ntdll), and its winemac.so, with win32u.so when the build has one,
# my Mac driver's (components/macdrv), the engine's own kept next to each (`set dxmt engine`, `set
# wine engine` and `set macdrv engine` switch back, for comparisons from Terminal; the Settings
# window has no row for them). A fourth,
# my FEX (components/fex), goes in only after `set fex mine` from Terminal, the engine's own kept
# next to it too; a development build sets it once, with every other switch of mine (DEV_ROWS,
# dev-switches.conf). Nothing goes inside wine.app.
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
#   gw2om.sh install move      GW2 on Mac 0.1.x's install into this app (the window starts it by
#                              itself at the first start, status: move=yes): engine, a new bottle
#                              whose Windows user is crossover as 0.1.x's, Steam from Valve, then
#                              0.1.x's Steam folder (its login and the game) renamed into it, or
#                              on ArenaNet's route its game folder, never copied; the profile's
#                              Steam files, the game's settings, the ReShade folder and the app's
#                              settings (SETTINGS_FROM_01) cloned in; the addons as they were;
#                              refused while 0.1.x's Wine runs (the window waits for it), and from
#                              another disk; of 0.1.x's folders only that one folder is renamed
#   gw2om.sh rollback          Settings › Troubleshooting's Rollback to 0.1.x: the moved Steam or
#                              game folder renamed back to where 0.1.x had it, with the addon files
#                              0.1.x had in the game folder; this app's install stays, without the
#                              game (status: move_game=01); refused while Wine runs
#   gw2om.sh move-in           the main window after a rollback: the game moved in again, as the
#                              move did
#   gw2om.sh recover           a rename a killed install, Rollback or Move in left (move-undo)
#                              undone under the install lock; status runs it
#   gw2om.sh scan              the Guild Wars 2 installs of other Wine apps on this Mac (GW2 on Mac
#                              0.1, CrossOver, Whisky, app wrappers, Heroic, GameHub, ~/.wine), one
#                              "game" line each
#   gw2om.sh check-game DIR    is DIR (or a game folder in it) a Guild Wars 2 install: its "game"
#                              line, or "@error <why>"
#   gw2om.sh finish            phase 5 once the game is there: the shader cache's folder, the
#                              interface addon (if on), the registry settings, the manifest
#   gw2om.sh stop-waiting      the window stops following the game's download (the engine and
#                              the bottle stay; Install picks up from there)
#   gw2om.sh repair            the engine (unpacked again if it isn't the expected one), its DXMT
#                              tree, ntdll.so, winemac.so (and win32u.so) and FEX as the settings
#                              ask, the bottle's settings; keeps the game and the settings
#   gw2om.sh uninstall         removes everything this app created: the bottle (with the game in
#                              it), the engine, the settings, its caches (DXMT's in them); logs
#                              stay
#   gw2om.sh start-fresh [--before-move|--moved]
#                              Settings › Troubleshooting: the move from 0.1.x no longer starts by
#                              itself, and this app's install goes as uninstall removes it
#                              (--before-move: not if the move has finished meanwhile; after a
#                              move the game goes back to 0.1.x first, as rollback does)
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
#                              <key>_state=ok or off:<reason> (setting_state; reshade_state is
#                              the addon's, as arcdps_state)
#   gw2om.sh set K V           change one setting (see setting_valid); refuses one that is off
#   gw2om.sh set arcdps on|off arcdps into the game folder (downloaded from deltaconnected.com,
#                              checked against its published md5) or out of it (only arcdps; its
#                              addons/arcdps settings stay), while no session runs; status and
#                              settings print arcdps, arcdps_state (on|off|foreign|nogame),
#                              arcdps_dll. With ReShade in, ReShade loads arcdps from
#                              addons/arcdps/chain/d3d11.dll (ADDONS_LAYOUT)
#   gw2om.sh set reshade on|off
#                              ReShade 6.8.0 into the game folder as d3d11.dll (from reshade.me's
#                              installer, pinned by sha256), with Microsoft's d3dcompiler_47.dll
#                              (the game's bin64/cef copy, else mozilla/fxc2's) and a ReShade.ini
#                              that points ReShade at the ReShade folder in the app's folder
#                              (its ini, presets, shaders, textures, screenshots; the standard
#                              effects while Shaders has no ReShade.fxh, SweetFX at the first On),
#                              or out of it (only what the app placed; the ReShade folder
#                              stays), while no session runs;
#                              remembered as reshade= in the settings, so Play, Install and Repair
#                              put missing files back; status and settings print reshade,
#                              reshade_state (on|off|foreign|blocked|nogame), reshade_version,
#                              reshade_dll, reshade_blocker, reshade_folder, addons_layout
#                              (together|exclusive, ADDONS_LAYOUT). ReShade's menu opens
#                              in the game with Home (fn + Left Arrow on a MacBook).
#   gw2om.sh reshade import <path>...
#                              presets (.ini with a Techniques line), zips and folders into the
#                              ReShade folder, whether ReShade is on or off and while the game runs
#                              (never into the game folder): presets into Presets (one of the same
#                              name stays unless it came from a source of the same name), the
#                              contents of Shaders and Textures folders at any depth and loose .fx,
#                              .fxh and images into Shaders/<name> and Textures/<name>; nothing
#                              else. "@preset <name>" for each preset that came in, and a report
#                              as @done: what went where, the effects the presets use that aren't
#                              in Shaders, those that read the depth buffer
#   gw2om.sh reshade use <preset>
#                              that preset in Presets as ReShade's current one (PresetPath in the
#                              ReShade folder's ReShade.ini, nothing else of it), while no session
#                              runs
#   gw2om.sh check-setup FILE  is FILE ArenaNet's Gw2Setup-64.exe: a PE x86_64 executable with a
#                              valid Authenticode signature by ArenaNet ("@done <what>")
#   gw2om.sh reset-shaders     deletes DXMT's caches (shaders, pipelines, recipes; my fork's and
#                              the engine's DXMT's) in the app's own cache folder; never DXMT's in
#                              the per-user cache folder
#   gw2om.sh reinstall-engine  unpacks the engine again
#   gw2om.sh end-leftovers     ends leftover Wine processes of the engine (no session running)
#   gw2om.sh fetch-engine      downloads and verifies the engine into the cache
#   gw2om.sh env               the game's environment as play would set it (for Terminal)
#   gw2om.sh rules             the compatdb rules play would write (for Terminal)
#   gw2om.sh vmmap             while the game runs: FEX's code buffers and the footprint from
#                              macOS's vmmap, into the logs folder (cmd_vmmap; Collect Logs too)
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
#   GW2_ON_MAC_ENGINE_LOADER_SHA256, GW2_ON_MAC_ENGINE_NTDLL_SHA256, GW2_ON_MAC_ENGINE_WINEMAC_SHA256,
#   GW2_ON_MAC_ENGINE_WIN32U_SHA256, GW2_ON_MAC_ENGINE_D3D11_SHA256,
#   GW2_ON_MAC_ENGINE_WINEMETAL_SHA256,
#   GW2_ON_MAC_ENGINE_FEX_DLL_SHA256, GW2_ON_MAC_ENGINE_FEX_SO_SHA256   a stand-in engine's own
#                              files (engine_matches, graphics, unix_lib, fex_file)
#   GW2_ON_MAC_FEX_SWITCHES    rows for FEX_SWITCHES, whose table is empty until a switch of mine
#                              has one (the rules check's fork and any rows)
#   GW2_ON_MAC_MACOS           the macOS version preflight sees
#   GW2_ON_MAC_STEAMSETUP_URL  another SteamSetup.exe
#   GW2_ON_MAC_SIGNER          the signer check-setup accepts (default ArenaNet)
#   GW2_ON_MAC_ARCDPS_URL      another place for arcdps's d3d11.dll and d3d11.dll.md5sum (a
#                              fixture: file://...)
#   GW2_ON_MAC_RESHADE_URL, GW2_ON_MAC_RESHADE_SIZE, GW2_ON_MAC_RESHADE_SHA256,
#   GW2_ON_MAC_RESHADE_DLL_SHA256   another ReShade installer, and its ReShade64.dll's sha256
#   GW2_ON_MAC_COMPILER_URL, GW2_ON_MAC_COMPILER_SIZE, GW2_ON_MAC_COMPILER_SHA256   another
#                              d3dcompiler_47.dll to download
#   GW2_ON_MAC_RESHADE_SHADERS_URL, GW2_ON_MAC_SWEETFX_URL   other effect pack zips
#   GW2_ON_MAC_PACK_LIMIT, GW2_ON_MAC_PACK_MAX_FILES   the most bytes one effect pack (or one
#                              zip, folder or preset of reshade import) may unpack to, and the
#                              most files it may have
#   GW2_ON_MAC_ADDONS_LAYOUT   exclusive: arcdps and ReShade refuse each other (ADDONS_LAYOUT)
#   GW2_ON_MAC_TEST_PAUSE, GW2_ON_MAC_TEST_PAUSE_AT   wait at a point while that file is there
#                              (test_pause: locked, lock-owner-read, lock-stale-checked, arcdps-moved,
#                              move-renamed, rollback-renamed)
#   GW2_ON_MAC_LOCK_WAIT      how long a contender waits for the install lock's claim (5 s)
#   GW2_ON_MAC_LAUNCH_WAIT=<n>  how long Play's resume of a Steam download waits for Steam to show
#                              (tenths of a second, 1200)
#   GW2_ON_MAC_ALLOW_WINE=1    let the real engine's Wine run in a sandbox (never in the tests)
#   GW2_ON_MAC_IMPORT_COPY=1   install import copies even on the same disk (the other-disk path),
#                              and install move refuses as from another disk
#   GW2_ON_MAC_FREE_KB=<n>     the free space the app's disk reports (KB)
#   GW2_ON_MAC_MOVE_FAIL=<step>  install move fails at that step (engine, settings, bottle, steam,
#                              files, profile, reshade, finish: move_fail)
#   GW2_ON_MAC_WATCH_TIMEOUT, GW2_ON_MAC_WATCH_GRACE, GW2_ON_MAC_WATCH_QUITWAIT,
#   GW2_ON_MAC_WATCH_POLL      watch-session's times in seconds (900, 30, 20, 2)
#   GW2_ON_MAC_VMMAP_TIMEOUT   how long vmmap may take before it is ended, in seconds (60)
#
# Lines for the app start with "@": "@phase <n>" (the timeline: install 1 engine, 2 bottle,
# 3 Steam or ArenaNet's installer, 4 the game's download, 5 finishing touches; install import
# 1 engine, 2 bottle, then Steam's route 3 Steam, 4 the files, 5 finishing touches, or ArenaNet's
# 3 the files, 4 finishing touches; install move the same as install import; uninstall 1 stop,
# 2 bottle, 3 the rest), "@step <text>", "@progress <label> <bytes> <total>", "@warn <text>",
# "@notice <text>", "@error <text>", "@done <text>", "@preset <name>" (reshade import). Everything
# else is plain log text.
# Runs under macOS's /bin/bash 3.2.
set -euo pipefail
# The app's name in its texts and the .app's file name, as 0.1.x's, and the name of its three
# folders in ~/Library (Application Support, Logs, Caches), which stay 0.2's own: 0.2 replaces the
# 0.1.x app and only ever reads 0.1.x's folders (ADR 0018). A text that names a folder uses the
# folder's name. build.sh and the scripts in scripts/ read both from here.
APP_NAME="GW2 on Mac"
APP_FOLDER="GW2 on Mac arm64"
RES="$(cd "$(dirname "$0")" && pwd)"
COMP="$RES/components"
VERSION="$(sed -n 's/^version=//p' "$RES/app.properties" 2>/dev/null || true)"
VERSION="${VERSION:-dev}"
CHANNEL="$(sed -n 's/^channel=//p' "$RES/app.properties" 2>/dev/null || true)"
CHANNEL="${CHANNEL:-release}"

# --- The engine: athei's Mach9 0.4.0, an arm64 Wine 11.21 that runs x86_64 Windows code with FEX,
# with his DXMT build, downloaded at install time (never bundled) and used as it ships. Bump name,
# URL, size, sha256 and the files' hashes together.
ENGINE_NAME=mach9-v0.4.0
ENGINE_TITLE="Mach9 0.4.0 · Wine 11.21"
ENGINE_URL=https://github.com/athei/mach9/releases/download/v0.4.0/wine-v0.4.0-macos-arm64.tar.xz
# the same file through GitHub's API (the release asset's id): the download's second way
ENGINE_API_URL=https://api.github.com/repos/athei/mach9/releases/assets/758011620
ENGINE_SIZE=131698496
ENGINE_SHA256=3b81aac9b93d5652872673b400769ec525f3bc2f1f7e2ec82c9f851d0a0db05d
# What it was built from (the release page's Components list): status, the manifest and Collect
# Logs print them
ENGINE_WINE=501796b0ed1   # athei/wine, wine-11.21-54
ENGINE_FEX=597e7ccbedd
ENGINE_DXMT=10e27aed3f5   # athei/dxmt
# Checked after unpacking (engine_matches): the loader, a signed app bundle that every Wine process
# runs as (nothing may change inside it: a copied or re-signed loader exits), and ntdll.so,
# winemac.so and win32u.so, which also tell the engine's own from mine (unix_lib). The DXMT tree's
# d3d11.dll and winemetal.so tell the engine's own DXMT from mine (dxmt_tree).
ENGINE_LOADER_APP=lib/wine/aarch64-unix/wine.app
ENGINE_LOADER_SHA256=1feebbe2764cc3c759d7a7bf90a44235bef5d0a61488882836e980418e797b49
ENGINE_LOADER_ID=app.mach9.loader
ENGINE_TEAM=WLKUUJD25W
ENGINE_NTDLL_SHA256=2b7972a767126f85557915383a3c33ffaaac265441a4141d25267826176c8f11
ENGINE_WINEMAC_SHA256=19c5ff04d31d2b5016b30bcba7b0793ab2805fb14c5aeaf9939498fe2d980f76
ENGINE_WIN32U_SHA256=1ac94b076bd2d60e41a34af3dcb138218c29389020a7d0192ffdd45413293b0c
ENGINE_D3D11_SHA256=89119817edc2e7b152d6245d18d41ef6965cdede9cc8c75a6adeea79825fa02c
ENGINE_WINEMETAL_SHA256=1ad9bf4d38726c00c7484aae70ea253f3b73976a20e06fc9c5894612a4251b77
# FEX's ARM64EC half, which tells the engine's own from mine (fex_file): lib/wine/aarch64-windows/
# xtajit64.dll and libarm64ecfex.dll (one file under two names) and aarch64-unix/libarm64ecfex.so
ENGINE_FEX_DLL_SHA256=cd6803d9ad0733c43c31aebca84203aac5256779093bc3d0b71324d2d564a429
ENGINE_FEX_SO_SHA256=0a3e7ea4b76a3acc634993ec98f2ef7e4d52b3806a871856e8f808099577bc4b
# My files in components/ are built for one engine, and their records (each VERSION) name it:
# "engine: Mach9 v0.4.0 (wine-v0.4.0-macos-arm64.tar.xz, sha256 <its sha256>)". A record without
# that line counts as built for Mach9 0.3.1, the engine before 0.4.0. They go into the engine only
# when it is the one this pin names (apply_engine_files): an engine of another release runs
# another wineserver protocol.
ENGINE_PIN_SHA256=$ENGINE_SHA256
ENGINE_0_3_1_SHA256=90aff9a897ed0ff9aac44d0e06f0aecd3ee985afb38037f3f915451e51fa974e
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
  ENGINE_WINEMAC_SHA256="${GW2_ON_MAC_ENGINE_WINEMAC_SHA256:-$ENGINE_WINEMAC_SHA256}"
  ENGINE_WIN32U_SHA256="${GW2_ON_MAC_ENGINE_WIN32U_SHA256:-$ENGINE_WIN32U_SHA256}"
  ENGINE_D3D11_SHA256="${GW2_ON_MAC_ENGINE_D3D11_SHA256:-$ENGINE_D3D11_SHA256}"
  ENGINE_WINEMETAL_SHA256="${GW2_ON_MAC_ENGINE_WINEMETAL_SHA256:-$ENGINE_WINEMETAL_SHA256}"
  ENGINE_FEX_DLL_SHA256="${GW2_ON_MAC_ENGINE_FEX_DLL_SHA256:-$ENGINE_FEX_DLL_SHA256}"
  ENGINE_FEX_SO_SHA256="${GW2_ON_MAC_ENGINE_FEX_SO_SHA256:-$ENGINE_FEX_SO_SHA256}"
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
APPDIR="$H/Library/Application Support/$APP_FOLDER"
LOGS="$H/Library/Logs/$APP_FOLDER"
CACHE="$H/Library/Caches/$APP_FOLDER"
ENG="$APPDIR/engine"                  # the unpacked engine, as it ships
BOTTLE="$APPDIR/bottle"               # the game's Wine prefix (Steam and the game live in it)
SETTINGS="$APPDIR/settings.conf"
STATE="$APPDIR/state"                 # route, stage (none|waiting_game|finished), game_dir,
                                      # origin (download|import|move, moved after the first
                                      # Play of a move)
MANIFEST="$APPDIR/install-manifest.json"
DXMT_CONF="$APPDIR/dxmt.conf"
# The game's compatdb rules (WINE_COMPATDB_FILE): written at each start, read by every process of
# the bottle when it starts. compatdb.local, if I create one, is appended as it is (FEX switches to
# try); nothing of the app writes it.
RULES="$APPDIR/compatdb.rules"
RULES_LOCAL="$APPDIR/compatdb.local"
# A development build's switches, one a line, that I take lines out of (DEV_SWITCHES)
DEV_FILE="$APPDIR/dev-switches.conf"
# The last Play's session (watch-session keeps it; key=value lines, SESSION_KEYS), the requests to
# its watcher, and the lock that keeps one watcher per session (a file the watcher holds a flock on)
SESSION="$APPDIR/session"
WATCH_LOCK="$APPDIR/.session.lock"
SESSION_REQ="$APPDIR/session.req"
# DXMT's caches, in the app's own cache folder instead of the per-user one
# ($(getconf DARWIN_USER_CACHE_DIR)dxmt/, which another DXMT setup of the game on this Mac may use
# and this app never touches), one place for each DXMT: the two translate shaders differently, and
# a switch must not hand one the other's.
#   the engine's DXMT  $CACHE/dxmt/Gw2-64.exe, as 0.2.0-dev.1 had it: the game's rule sets
#                      DXMT_SHADER_CACHE_PATH there (rules_text)
#   my fork            under $FORK_CACHE_BASE: the fork takes its caches' base from
#                      DXMT_CACHE_DIR (game_env) and doesn't read DXMT_SHADER_CACHE_PATH; the rule
#                      names its game folder anyway, $DXMT_CACHE_FORK
DXMT_CACHE_ROOT="$CACHE/dxmt"
DXMT_CACHE="$DXMT_CACHE_ROOT/Gw2-64.exe"
FORK_CACHE_BASE="$CACHE/fork"
DXMT_CACHE_FORK="$FORK_CACHE_BASE/dxmt/Gw2-64.exe"
STEAM_DIR="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
# GW2 on Mac 0.1.x's install, which this app moves into its own folder at its first start (install
# move): 0.1.x's folders by their own name. The move renames 0.1.x's Steam or game folder into
# this app's bottle and writes nothing else of 0.1.x's (docs/adr/0020). 0.1.x's Windows user is
# crossover (CrossOver's Wine names every user so), and every bottle of this app gets that name
# too (bottle_user, docs/adr/0019). MOVE_RECORD's first line says the move happened ("moved") or
# that I chose Start fresh ("skipped"): either way the app doesn't move by itself again. Uninstall
# keeps it. After a move it also names the renamed folder's two places and the game folder in it
# (old=, new=, game=), for Rollback and Move in. MOVE_ADDONS: the addon files 0.1.x had in the
# game folder (ADDON_FILES), which Rollback puts back. MOVE_UNDO: the rename in flight, written
# before it and removed once it is done or undone; one left by a run that was killed is undone
# under the next install lock (move_recover).
OLD_LABEL="GW2 on Mac 0.1"
OLD_APPDIR="$H/Library/Application Support/GW2 on Mac"
OLD_CACHE="$H/Library/Caches/GW2 on Mac"
OLD_ENG="$OLD_APPDIR/engine"
OLD_BOTTLE="$OLD_APPDIR/bottle"
OLD_STEAM="$OLD_BOTTLE/drive_c/Program Files (x86)/Steam"
WIN_USER=crossover
MOVE_RECORD="$APPDIR/moved-from-0.1"
MOVE_ADDONS="$APPDIR/0.1-addons"
MOVE_UNDO="$APPDIR/move-undo"
MOVE_SNAP="$APPDIR/move-undo.addons"
MOVING="" UNINSTALL_WITH=""
# how long Play's resume of a Steam download waits for Steam to show, in tenths of a second
LAUNCH_POLLS=1200
[ -z "$ROOT" ] || LAUNCH_POLLS="${GW2_ON_MAC_LAUNCH_WAIT:-$LAUNCH_POLLS}"
# the last 0.1.x release: Rollback's version, and its DMG (a release asset, notarized)
LAST_01=0.1.4
LAST_01_DMG="https://github.com/jdrly/gw2-on-mac/releases/download/v$LAST_01/GW2-on-Mac-$LAST_01.dmg"
# What uninstall removes in APPDIR (the folder itself goes too once empty; gamemode is what a build
# of this line before the Mach9 engine made). Not .session.lock: a lock file stays, held or not.
APP_FILES="engine bottle gamemode settings.conf state install-manifest.json dxmt.conf compatdb.rules compatdb.local dev-switches.conf engine.new bottle.new session session.req reshade-compiler 0.1-addons"
LOGFILE=/dev/null

# --- Output and logging
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGFILE"; }
say() { echo "$*"; log "$*"; }
step() { echo "@step $*"; log "== $*"; }
phase() { echo "@phase $1"; }
warn() { echo "@warn $*"; log "WARNING: $*"; }
# (DIE_NOTE, when set, ends the text: install_engine's while it replaces an engine of another release)
DIE_NOTE=""
die() { echo "@error $*${DIE_NOTE:+ $DIE_NOTE}"; log "ERROR: $*${DIE_NOTE:+ $DIE_NOTE}"; exit 1; }
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
#
# proc_list old: GW2 on Mac 0.1.x's processes instead, as 0.1.x's own proc_list tells them (main's
# src/gw2om.sh): an executable in its folder (the engine, or the Game Mode bundle's copy of the
# loader, gamemode/GW2.app, which the game runs as with Game Mode on), or a winetemp link to the
# engine's loader (tagged by the loader's inode and size); its wineserver, or the stock one kept
# next to mine (wineserver.stock), is the session.
proc_list() {
  local helper="$RES/helpers/procpaths" e="$ENG/" s="$ENG/bin/wineserver" t="" old="" l
  if [ "${1:-}" = old ]; then
    e="$OLD_APPDIR/" s="$OLD_ENG/bin/wineserver" old=yes l="$OLD_ENG/lib/wine/x86_64-unix/wine"
    [ ! -f "$l" ] || t="/winetemp-$(stat -f '%i-%z' "$l")-"
  fi
  { if [ -x "$helper" ]; then "$helper" 2>/dev/null | sed 's/^/P /'; fi
    ps -axww -o pid=,comm= 2>/dev/null | sed 's/^ */C /'; } |
  awk -v e="$e" -v s="$s" -v t="$t" -v old="$old" '
    $1 == "P" { x = $0; sub(/^P [0-9]+ /, "", x); real[$2] = x; next }
    { pid = $2; prog = $0; sub(/^C [0-9]+ /, "", prog)
      exe = (pid in real) ? real[pid] : prog
      if (old != "") sub(/\/lib\/wine\/\.\.\/\.\.\/bin\//, "/bin/", exe)
      if (index(exe, e) != 1 && (t == "" || !index(exe, t))) next
      p = tolower(prog) }
    exe == s || (old != "" && exe ~ /\/bin\/wineserver(\.stock)?$/) { print "session", pid, prog; next }
    p ~ /[\/\\]gw2-64\.exe$/ || (old != "" && exe ~ /\/Gw2-64\.exe$/) { print "game", pid, prog; next }
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
# old_busy: OLD_BUSY (none, or what of 0.1.x runs: game, steam, installer, session) and OLD_WAIT, the
# sentence for it. The move waits while any of them runs, since they may write the files it
# clones. Leftovers (Wine processes without their wineserver) can't, and may never end: they don't
# count.
old_busy() {
  local l
  l=$(proc_list old)
  OLD_BUSY=$(busy_of "$l") OLD_WAIT=""
  case "$OLD_BUSY" in
    game) OLD_WAIT="Guild Wars 2 is running in $OLD_LABEL. Quit it, and the move starts." ;;
    steam) OLD_WAIT="Steam is running in $OLD_LABEL. Quit Steam there (Steam > Exit), and the move starts." ;;
    installer) OLD_WAIT="ArenaNet's installer is running in $OLD_LABEL. Let it finish or quit it, and the move starts." ;;
    session) OLD_WAIT="$OLD_LABEL's Wine is still running ($(proc_names "$l" session engine)). It ends a few seconds after Steam and the game have quit, and the move starts then." ;;
    *) OLD_BUSY=none ;;
  esac
}

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

# download <url> <file> <label> [<most bytes>]: a file with progress, unpinned (SteamSetup.exe) or
# checked by the caller
download() {
  local url=$1 out=$2 label=$3 max=${4:-} total pid rc=0
  if [ -n "$DRY" ]; then echo "[dry-run] download $url to $out"; return; fi
  mkdir -p "$(dirname "$out")"
  # (its size for the progress, if the server says; unknown is fine)
  total=$( { curl -fsIL --connect-timeout 20 "$url" 2>/dev/null || true; } | tr -d '\r' | awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }')
  rm -f "$out.part"
  curl -fsSL --connect-timeout 20 --retry 2 ${max:+--max-filesize "$max"} -o "$out.part" "$url" 2>>"$LOGFILE" &
  pid=$!
  FETCH_PID=$pid
  while kill -0 "$pid" 2>/dev/null; do
    echo "@progress $label $(stat -f %z "$out.part" 2>/dev/null || echo 0) $total"
    sleep 1
  done
  wait "$pid" || rc=$?
  FETCH_PID=
  # (63: larger than the most it may be)
  [ "$rc" != 63 ] || { rm -f "$out.part"; die "The download of $label is not the file $APP_NAME expects: it is larger than that file. Something on the way changes it (a proxy, VPN, antivirus or content filter). Try again."; }
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

# wine_do <args...>: Wine in the bottle for the install's own steps (output to the log), as the
# bottle's Windows user (USER, bottle_user)
wine_do() {
  local u
  u=$(bottle_user)
  if [ -n "$DRY" ]; then echo "[dry-run] wine (USER=$u) $*"; return; fi
  wine_allowed
  log "+ wine (USER=$u) $*"
  env -u WINELOADER -u WINESERVER -u WINEDLLPATH -u DYLD_FALLBACK_LIBRARY_PATH "${COMPATDB_UNSET[@]}" \
    USER="$u" WINEPREFIX="$BOTTLE" WINEDEBUG=-all WINEMSYNC=1 WINEDLLOVERRIDES=winemenubuilder.exe=d \
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
  [ ! -d "$WATCH_LOCK" ] || safe_rm --quiet "$WATCH_LOCK"
  exec 8>>"$WATCH_LOCK"
  "$LOCKER" take 8 2>/dev/null && return 0
  exec 8>&-
  return 1
}
registry_unlock() { [ -z "$DRY" ] && [ -z "${SESSION_LOCKED:-}" ] || return 0; exec 8>&-; }

# The bottle's registry settings: RetinaMode (from settings.conf), EmulateModeset off and
# ShowCrashDialog off. Mach9's own launcher writes EmulateModeset on; 0.1.x never writes it. I
# write it off, as N, so a bottle with Y from an earlier 0.2 build loses it (#90). With Y, moving
# the cursor made the frame interval saw between 16.7 and 33 ms, where 0.1.x stays at 16.7: win32u
# fakes the game's mode set and drops its gamma ramp (dlls/win32u/dc.c), so the window server flips
# the game's frames straight to the display and each cursor update blocks a frame's swap (the
# value is measured in play, the gamma part read from samples). The game's Gamma slider did
# nothing either. Values under AppDefaults stay as they are. Only while no session runs or starts
# (Wine reads user.reg when its wineserver starts and writes it back), else at the next game start
# that finds none (play).
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
  set_reg "$REG_X11" EmulateModeset '"N"'
  set_reg "$REG_WINEDBG" ShowCrashDialog dword:00000000
  registry_unlock
}

# --- Settings
#
# The keys are 0.1.x's, so settings.conf reads the same on both lines, and dxmt (fork: my DXMT
# fork; engine: the engine's own, to compare), wine (mine: my ntdll.so; engine: the engine's own),
# macdrv (mine: my winemac.so, and my win32u.so when its build has one; engine: the engine's own),
# fex (mine: my FEX; engine: the engine's own, the default), and jobwakes, launcherframes and
# eventpool (rows of HEAT_SWITCHES, as fastlocks is), and metal (3 or 4: the Metal my DXMT fork
# draws with, DXMT_METAL4 in the game's rule; 4 by default, and in a file without the key, with its
# frames presented through a Metal 3 command buffer, metal_present), and vsync (on: my DXMT fork's
# display sync, its default; off: DXMT_DISPLAY_SYNC=0 in the game's rule). A file that has metal=
# keeps it: Install and Repair wrote metal=3 into every file while 3 was the default, and that reads
# as my choice, so no reset. gamemode left the keys in #269: nothing read it on this line, where
# the engine's loader is the Game Mode app, and a file's gamemode= line goes at its next write, as
# coolworkers' did. dxmt, wine, macdrv and fex have no row in the
# Settings window: they are for my comparisons from Terminal (gw2om.sh set …). On this engine some
# of the keys need pieces of mine that come in later steps: setting_state says so, the Settings
# window greys them with the reason, set refuses them, and they keep what settings.conf says without
# an effect.
SETTING_KEYS="retina fpscap vsync metal metalfx hud warm fastlocks ncpu uiscale uiscale_size uiscale_sans uiscale_cinema launchopts rawmouse mousespeed updates debug steambg quitsteam dxmt wine jobwakes macdrv launcherframes eventpool fex reshade"
# settings.conf's version, its line settings_version=. Install and Repair write every key with its
# value, so a file holds the defaults it was written with, as if I had chosen them. A default that
# changes for the files that exist gets a row here, "<version> <keys>": in a file older than
# <version> (or without the line) those keys read as their defaults, and the next write of the
# file (set, Install, Repair) keeps that and writes this version. Version 1: fastlocks starts off
# on this line (#45). Until then the arm64 line wrote on into every file, while its row was greyed
# and set refused it, so no file holds a choice of mine. (It reset coolworkers too, a key since
# removed: write_settings leaves out a line whose key isn't in SETTING_KEYS.) Version 2: dxmt, wine
# and macdrv back to fork, mine and mine, once, as their rows leave the Settings window, so no
# bottle stays on the engine's files with no row that shows it. A later set from Terminal stays.
SETTINGS_RESETS="
1 fastlocks
2 dxmt wine macdrv
"
SETTINGS_VERSION=$(printf '%s\n' "$SETTINGS_RESETS" | awk 'NF { v = $1 } END { print v + 0 }')
# What a move from 0.1.x (install move, move_settings) does with each of 0.1.x's settings, one row
# a key: "<key> <what> <0.1.x's default, - for none> <its name in Settings>". kept: 0.1.x's value,
# which means the same here (a key 0.1.x's file doesn't have reads as 0.1.x's default; a value this
# version doesn't take, as this version's default). default: this version's default. dropped: no
# such setting here. 0.1.x's settings.conf has no version line and every key in it, chosen or not
# (main's write_settings), so a kept value is what 0.1.x ran with. Keys of this version that 0.1.x
# doesn't have start at their defaults (vsync, #269). fastlocks: 0.1.x's default was on, a spin in CrossOver's
# msync; here it is another port, off by default (#45, #105). gamemode: always on here, the
# engine's loader is a Game Mode app. coolworkers: none here (docs/adr/0006). mousespeed is a factor
# on GameController's counts here, on the pointer's speed there: the same choice in Settings.
SETTINGS_FROM_01="
retina kept on Retina
fpscap kept off Frame cap
metalfx kept off MetalFX for Subsample
hud kept off Metal HUD
warm kept on Shader warming
coolworkers dropped off Cooler job workers
fastlocks default on Faster locks
ncpu kept 8 CPUs the game sees
uiscale kept off Larger interface
uiscale_size kept 1.75 Interface Size Larger
uiscale_sans kept on Small text in Cronos
uiscale_cinema kept on Cinematic dialogue
gamemode dropped on Game Mode
launchopts kept - Launch options
rawmouse kept on Raw mouse-look
mousespeed kept 1 Mouse-look speed
updates kept on Check for updates automatically
debug kept off Debug logging
steambg kept on Start Steam in the background
quitsteam kept on Quit Steam when the game quits
reshade kept off ReShade
"
# A development build (CHANNEL=dev) starts with every switch on: I debug from everything on
# backwards. Its rows that are switches go on once, by settings.conf's line dev_version=, as
# SETTINGS_RESETS does for defaults: a row of DEV_ROWS, "<version> <key>=<value> ...", reads as
# that value in a file older than <version> (or without the line), and the next write of the file
# (dev_update, set, Install, Repair) keeps it and writes this version, so a row I turn off
# afterwards stays off. fex=mine takes effect only in a build that carries my FEX (fex_want). A
# development build and the release share the app's folders, so a release build that finds a
# dev_version= line reads the keys of DEV_ROWS as their defaults, and its next write drops the line
# with those values (dev_dropped). A development build after it turns them on again. The switches
# without a row are in dev-switches.conf (DEV_SWITCHES).
DEV_ROWS="
1 jobwakes=on eventpool=on fastlocks=on launcherframes=on warm=on metalfx=on rawmouse=on fex=mine
"
DEV_ROWS_VERSION=$(printf '%s\n' "$DEV_ROWS" | awk 'NF { v = $1 } END { print v + 0 }')
DEV_ROW_KEYS=$(printf '%s\n' "$DEV_ROWS" | awk '{ for (i = 2; i <= NF; i++) { sub(/=.*/, "", $i); print $i } }')
# The sandbox's checks of the rest of the app turn this off (GW2_ON_MAC_DEV_SWITCHES=off): they
# check a development build as a release would set it up, apart from Debug logging's default
DEV_ON=""
[ "$CHANNEL" != dev ] || DEV_ON=yes
[ -z "$ROOT" ] || [ "${GW2_ON_MAC_DEV_SWITCHES:-}" != off ] || DEV_ON=""
# dev_version: settings.conf's dev_version= (0 without one)
dev_version() {
  local v
  v=$(sed -n 's/^dev_version=//p' "$SETTINGS" 2>/dev/null | tail -1)
  case "$v" in ''|*[!0-9]*) echo 0 ;; *) echo "$v" ;; esac
}
# dev_dropped <key>: a release build, and <key> a row of DEV_ROWS that a development build set
# (settings.conf has a dev_version= line)
dev_dropped() { [ "$CHANNEL" != dev ] && in_list "$1" "$DEV_ROW_KEYS" && grep -q '^dev_version=' "$SETTINGS" 2>/dev/null; }
# dev_row <key>: the value DEV_ROWS gives <key> while settings.conf is older than its row, or
# nothing
dev_row() {
  [ -n "$DEV_ON" ] && in_list "$1" "$DEV_ROW_KEYS" || return 0
  printf '%s\n' "$DEV_ROWS" | awk -v k="$1" -v v="$(dev_version)" \
    'NF && $1 > v { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) r = substr($i, length(k) + 2) } END { if (r != "") print r }'
}
FPS_CAPS="off 30 40 60 120"
# Mouse-look speed (mousespeed): 0.1.x's values, there RawMouseGameControllerScale, a factor on
# the macOS pointer's speed (SWTOR on Mac's MOUSE_SPEEDS); here a factor on GameController's counts
MOUSE_SPEEDS="0.5 0.75 1 1.25 1.5 1.75 2 2.5 3"
# CPUs the game sees (ncpu): 2 up to this Mac's logical CPUs, or all
CPU_MAX="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
UI_SCALES="1.5 1.75 1.8 2.0"
setting_default() {
  case "$1" in
    retina|vsync|warm|uiscale_sans|rawmouse|updates|steambg|quitsteam|jobwakes|eventpool) echo on ;;
    metalfx|hud|uiscale|uiscale_cinema|launcherframes|fastlocks|reshade) echo off ;;
    mousespeed) echo 1 ;;
    debug) if [ "$CHANNEL" = dev ]; then echo on; else echo off; fi ;;
    fpscap) echo off ;;
    ncpu) echo 8 ;;
    uiscale_size) echo 1.75 ;;
    launchopts) echo "" ;;
    dxmt) echo fork ;;
    wine|macdrv) echo mine ;;
    fex) echo engine ;;
    metal) echo 4 ;;
  esac
}
setting_valid() { # <key> <value>
  case "$1" in
    retina|vsync|metalfx|hud|warm|fastlocks|uiscale|uiscale_sans|uiscale_cinema|rawmouse|updates|debug|steambg|quitsteam|jobwakes|launcherframes|eventpool|reshade)
      [ "$2" = on ] || [ "$2" = off ] ;;
    mousespeed) in_list "$2" "$MOUSE_SPEEDS" ;;
    fpscap) in_list "$2" "$FPS_CAPS" ;;
    ncpu) [ "$2" = all ] || { case "$2" in ''|*[!0-9]*) false ;; *) [ "$2" -ge 2 ] && [ "$2" -le "$CPU_MAX" ] ;; esac; } ;;
    uiscale_size) in_list "$2" "$UI_SCALES" ;;
    # Gw2-64.exe's arguments: words of letters, digits and -_.:=,/+ only (nothing a shell or Wine
    # would take for something else)
    launchopts) case "$2" in *[!A-Za-z0-9\ _.:=,/+-]*) false ;; *) [ ${#2} -le 200 ] ;; esac ;;
    dxmt) [ "$2" = fork ] || [ "$2" = engine ] ;;
    wine|macdrv|fex) [ "$2" = mine ] || [ "$2" = engine ] ;;
    metal) [ "$2" = 3 ] || [ "$2" = 4 ] ;;
    *) false ;;
  esac
}
# setting_reset <key>: settings.conf is older than a reset of <key>'s default (SETTINGS_RESETS)
setting_reset() {
  local v
  in_list "$1" "$SETTINGS_RESETS" || return 1
  v=$(sed -n 's/^settings_version=//p' "$SETTINGS" | tail -1)
  case "$v" in ''|*[!0-9]*) v=0 ;; esac
  printf '%s\n' "$SETTINGS_RESETS" | awk -v k="$1" -v v="$v" 'NF && $1 > v { for (i = 2; i <= NF; i++) if ($i == k) f = 1 } END { exit !f }'
}
setting() { # <key>: its value, or the default
  local v
  v=$(dev_row "$1")
  if [ -n "$v" ]; then echo "$v"; return; fi
  if [ -f "$SETTINGS" ] && grep -q "^$1=" "$SETTINGS" && ! setting_reset "$1" && ! dev_dropped "$1"; then
    v=$(sed -n "s/^$1=//p" "$SETTINGS" | tail -1)
    if setting_valid "$1" "$v"; then echo "$v"; return; fi
  fi
  setting_default "$1"
}
# setting_state <key>: ok, or off:<reason> for a setting this engine can't do yet (the one table of
# them; settings prints it, the window greys the row and shows the reason, set refuses the key)
setting_state() {
  local e l n
  if [ "$1" = mousespeed ] && [ "$(setting rawmouse)" != on ]; then echo "off:Needs Raw mouse-look, which is off."; return; fi
  case "$1" in
    metal|metalfx|warm|vsync) if [ "$(setting dxmt)" = fork ]; then echo ok; else echo "off:Needs my DXMT fork, and the engine's own DXMT is chosen."; fi ;;
    wine) if lib_bundled wine; then echo ok; else echo "off:This build of the app has no Wine build of mine."; fi ;;
    macdrv) if lib_bundled macdrv; then echo ok; else echo "off:This build of the app has no Mac driver of mine."; fi ;;
    fex) if fex_bundled; then echo ok; else echo "off:This build carries no FEX of mine."; fi ;;
    *)
      e=$(fex_switch_row "$1")
      if [ -n "$e" ]; then fex_switch_state "${e% *}" "${e##* }"; return; fi
      e=$(switch_entry "$1") l=$(switch_lib "$e")
      if [ -z "$l" ]; then echo ok
      elif [ "$(lib_want "$l")" != mine ]; then
        if [ "$l" = macdrv ]; then n="my Mac driver"; else n="my Wine build"; fi
        if lib_bundled "$l"; then echo "off:Needs $n, and the engine's own $LIB is chosen."
        else echo "off:Needs $n, which this build of the app doesn't have."
        fi
      elif switch_in_file "$e"; then
        if dev_sets "$e"; then echo "off:Set in dev-switches.conf (${e%%=*}). Take its line out there to use this row."
        else echo ok
        fi
      elif [ "$l" = macdrv ]; then echo "off:My Mac driver in this app (jdrly/wine $(lib_commit macdrv | cut -c1-11)) doesn't have this switch."
      else echo "off:My Wine build in this app (jdrly/wine $(lib_commit wine | cut -c1-11)) doesn't have this switch."
      fi ;;
  esac
}
write_settings() { # [<key> <value>]: settings.conf with every key, one of them changed
  local k v d
  d=$(dev_version)
  [ -z "$DEV_ON" ] || d=$DEV_ROWS_VERSION
  [ "$CHANNEL" = dev ] || d=0
  for k in $SETTING_KEYS; do
    v=$(setting "$k")
    if [ "$k" = "${1:-}" ]; then v=$2; fi
    echo "$k=$v"
  done | {
    echo "# $APP_NAME settings (change them in the app: $APP_NAME > Settings…)"
    echo "settings_version=$SETTINGS_VERSION"
    [ "$d" = 0 ] || echo "dev_version=$d"
    cat
  } | put "$SETTINGS" 644
}

# move_settings: this app's settings.conf from 0.1.x's, through SETTINGS_FROM_01, at this version
# (settings_version: no reset of SETTINGS_RESETS applies to it); the keys left out read as this
# version's defaults, and write_settings (install_bottle) writes them all. MOVE_OLD: each key's
# value as 0.1.x ran with it, for move_changes.
move_settings() {
  local old="$OLD_APPDIR/settings.conf" k how def v lines=""
  MOVE_OLD=""
  while read -r k how def _; do
    [ -n "$k" ] || continue
    [ "$def" != - ] || def=""
    if grep -q "^$k=" "$old" 2>/dev/null; then v=$(sed -n "s/^$k=//p" "$old" | tail -1); else v=$def; fi
    MOVE_OLD="$MOVE_OLD$k=$v
"
    case "$how" in
      kept)
        if setting_valid "$k" "$v"; then lines="$lines$k=$v
"
        else log "settings from $OLD_LABEL: $k=$v isn't a value of this version; its default"
        fi ;;
      default|dropped) log "settings from $OLD_LABEL: $k=$v $how" ;;
    esac
  done <<EOF
$SETTINGS_FROM_01
EOF
  { echo "# $APP_NAME settings (change them in the app: $APP_NAME > Settings…)"
    echo "settings_version=$SETTINGS_VERSION"
    printf '%s' "$lines"
  } | put "$SETTINGS" 644
}

# move_changes: MOVE_LOST, the move's sentence for each setting that doesn't run as 0.1.x ran it,
# in SETTINGS_FROM_01's order, with why: a dropped one 0.1.x had off its default, one at this
# version's default, a development build's switch (DEV_ROWS), a value this Mac or this version
# doesn't take. None in a dry run, which writes no settings to compare with.
move_changes() {
  local k how def label old new gone=""
  MOVE_LOST=""
  [ -z "$DRY" ] || return 0
  while read -r k how def label; do
    [ -n "$k" ] || continue
    [ "$def" != - ] || def=""
    old=$(printf '%s' "$MOVE_OLD" | sed -n "s/^$k=//p" | tail -1)
    case "$how" in
      dropped)
        [ "$old" != "$def" ] || continue
        if [ "$k" = gamemode ]; then gone="${gone:+$gone; }$label is always on here"
        else gone="${gone:+$gone; }$label isn't a setting on this engine"
        fi ;;
      *)
        new=$(setting "$k")
        [ "$new" != "$old" ] || continue
        if [ -n "$DEV_ON" ] && in_list "$k" "$DEV_ROW_KEYS"; then gone="${gone:+$gone; }$label is ${new:-none}, as a development build starts"
        elif [ "$how" = default ]; then gone="${gone:+$gone; }$label is ${new:-none}, this version's default"
        elif ! setting_valid "$k" "$old"; then gone="${gone:+$gone; }$label is ${new:-none}: ${old:-none} isn't a choice here"
        else gone="${gone:+$gone; }$label is ${new:-none}, not ${old:-none}"
        fi ;;
    esac
  done <<EOF
$SETTINGS_FROM_01
EOF
  [ -z "$gone" ] || MOVE_LOST="Changed from $OLD_LABEL: $gone."
}

# dxmt.conf: DXMT's options for the game (DXMT_CONFIG_FILE)
write_dxmt_conf() {
  local cap
  cap=$(setting fpscap)
  {
    echo "# DXMT options for Guild Wars 2, written by $APP_NAME from its settings (DXMT_CONFIG_FILE)."
    if [ "$cap" != off ]; then
      echo "# Frame cap: paced by Metal. While display sync paces the game (Vsync and the game's vsync on), only a cap below the refresh acts"
      echo "d3d11.preferredMaxFrameRate = $cap"
    fi
  } | put "$DXMT_CONF" 644
}

# The environment of the session's first process (play), from settings.conf; also what `env`
# prints. Steam passes it on to the game, so it is fixed while Steam runs. What only the game gets
# goes into its compatdb rules instead (rules_text), which each process reads when it starts.
# With my DXMT fork in the engine (dxmt_in_use), what it reads (jdrly/dxmt's docs/gw2/README.md):
#   DXMT_CACHE_DIR=$FORK_CACHE_BASE its caches under the app's own cache folder,
#                                   $CACHE/fork/dxmt/<exe>/ (#134), never the per-user one, 0.1.x's
#                                   or the engine's DXMT's
#   DXMT_DEPENDENCY_COMPRESSION=1   the checkpoint chain on Metal 4 (#133; in the mix)
#   DXMT_WARM=all                   warm=on: pipelines built ahead by recent use (#128)
#   DXMT_SUBSAMPLE_METALFX=1        metalfx=on: MetalFX for the Subsample pass (#56)
#   DXMT_STATS=1                    debug=on: the 2 s STATS lines (on by default in the fork; said
#                                   here so the session's record shows it)
# The engine's DXMT reads none of them, so they stay out while it runs. With Debug logging and my
# winemac.so in the engine, WINEDEBUG also takes my Mac driver's channel macsurface for Gw2-64.exe
# (the launcher and the game; Wine's <process>:<channel> form): each window surface's flushes and
# skipped frames every 600 flushes, in wine.log, which the session report reads.
game_env() {
  local n debug=-all fork=""
  if [ "$(setting debug)" = on ]; then
    debug=err+all,fixme-all
    [ "$(lib_in_use macdrv)" != mine ] || debug="$debug,Gw2-64.exe:+macsurface"
  fi
  [ "$(dxmt_in_use)" != fork ] || fork=yes
  E=(
    "USER=$(bottle_user)"
    "WINEPREFIX=$BOTTLE"
    "WINEDEBUG=$debug"
    "WINEDLLOVERRIDES=winemenubuilder.exe=d"
    "WINEMSYNC=1"
    "DXMT_CONFIG_FILE=$DXMT_CONF"
    "DXMT_LOG_PATH=$LOGS"
    "WINE_COMPATDB_FILE=$RULES"
  )
  if [ -n "$fork" ]; then
    E+=("DXMT_CACHE_DIR=$FORK_CACHE_BASE" "DXMT_DEPENDENCY_COMPRESSION=1")
    [ "$(setting warm)" != on ] || E+=("DXMT_WARM=all")
    [ "$(setting metalfx)" != on ] || E+=("DXMT_SUBSAMPLE_METALFX=1")
  fi
  n=$(setting ncpu)
  [ "$n" = all ] || E+=("WINENCPU=$n")
  if [ "$(setting debug)" = on ]; then
    E+=("DXMT_LOG_LEVEL=debug")
    [ -z "$fork" ] || E+=("DXMT_STATS=1")
  fi
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
# 0.4.0 (Table's Display: the fields in the order of Key::ALL, words in lowercase), which CI's
# compatdb check reads back byte for byte. The engine's built-in rules already give every process
# DXMT, DPI awareness, raw mouse from GameController and FEX's reduced x87 precision. Gw2-64.exe:
#   gcmouse=false      rawmouse=off: the game's raw input is the pointer's movement, as Wine does
#                      it, not GameController's counts
#   metal_hud=true     the Metal HUD (Settings › Graphics), in the game only
#   dll_overrides      native first, for an addon in the game folder: d3d11 and dxgi while one is
#                      there (arcdps, a ReShade, Nexus), d3dcompiler_47 while a ReShade is
#                      (Microsoft's compiler next to Gw2-64.exe: ReShade loads it by name, and
#                      Wine's own can't compile ReShade's effects), version while the larger
#                      interface is on. With no such file Wine loads its own (n,b).
#   env                DXMT's shader cache in the app's cache folder (dxmt_cache: my fork's, or
#                      the engine's DXMT's own), with my fork in place the Metal it draws with
#                      (DXMT_METAL4=0 for Metal 3, =1 for Metal 4: the Metal row; the engine's
#                      DXMT doesn't read it) and at Metal 4 its present (metal_present), with Vsync
#                      off DXMT_DISPLAY_SYNC=0 (my fork's display sync is on without it), then the
#                      switches of my ntdll.so and my Mac
#                      driver (heat_entries), then FEX's (fex_entries), then, in a development
#                      build, the lines of dev-switches.conf (dev_entries)
# CefHost.exe, which the game starts for its launcher and the Trading Post, inherits the game's
# variables: the rule takes the cache path and the switches away from it again (an empty value
# unsets a variable), and the HUD while it is on. rundll32.exe gets the game's d3d11 and dxgi
# order while an addon is there, arcdps also at ReShade's chain path (ARC_CHAIN). arcdps does part
# of its work in rundll32 with its own DLL: its crash window, with the entry point
# c_exceptionerrormsg, and very likely its update (c_closeandupdate). In Wine's default order
# rundll32 loads Wine's own d3d11 in place of that file, since arcdps's version block names no
# company (version_heuristics in Wine's loadorder.c), and that d3d11 has no such entry point (#155,
# #209). A line of compatdb.local comes after the rules (write_rules), so its DXMT_METAL4 wins
# over the row's.
rules_text() {
  local game="exe=Gw2-64.exe" cef="exe=CefHost.exe" rundll="" entries="" removed="" e metal="" present="" sync=""
  [ "$(setting rawmouse)" = on ] || game="$game;gcmouse=false"
  if [ "$(setting hud)" = on ]; then game="$game;metal_hud=true" cef="$cef;metal_hud=false"; fi
  arcdps_state
  reshade_state
  case "$ARC $RSH" in
    on\ *|foreign\ *|*\ on|*\ foreign)
      game="$game;dll_overrides=d3d11,dxgi=n,b" rundll="exe=rundll32.exe;dll_overrides=d3d11,dxgi=n,b" ;;
  esac
  case "$RSH" in on|foreign) game="$game;dll_overrides=d3dcompiler_47=n,b" ;; esac
  [ "$(setting uiscale)" != on ] || game="$game;dll_overrides=version=n,b"
  # (the tree read once for this run: dxmt_cache asks again)
  dxmt_look "$DXGI/dxmt"
  if [ "$(dxmt_in_use)" = fork ]; then
    if [ "$(setting metal)" = 4 ]; then metal=DXMT_METAL4=1; else metal=DXMT_METAL4=0; fi
    present=$(metal_present | sed -n 's/^in //p')
    [ "$(setting vsync)" = on ] || sync=DXMT_DISPLAY_SYNC=0
  fi
  while IFS= read -r e; do
    if [ -n "$e" ]; then entries="$entries;env=$e" removed="$removed;env=${e%%=*}="; fi
  done <<EOF
$metal
$present
$sync
$(heat_entries)
$(fex_entries)
$(dev_entries)
$(sampler_fex)
EOF
  echo "$game;env=DXMT_SHADER_CACHE_PATH=$(cdb_value "$(dxmt_cache)")$entries"
  echo "$cef;env=DXMT_SHADER_CACHE_PATH=$removed"
  [ -z "$rundll" ] || echo "$rundll"
}
# metal_present: my fork's present on Metal 4 for the game's rule, "in DXMT_MTL4_PRESENT=mtl3", or
# "out DXMT_MTL4_PRESENT=mtl3 (<why>)". On Metal 4 a moving cursor makes macOS hand a present's
# drawable back a refresh late, whatever the order of Metal 4's own present (jdrly/dxmt#223).
# Through a Metal 3 command buffer (jdrly/dxmt#227) it is flat, and Metal 4 with it ran about 58 fps
# median in my Lion's Arch laps, against 50.5 on Metal 3. It goes in with the Metal row at Metal 4,
# in release and development builds alike, while my fork's tree in the engine names the switch
# (dxmt_names, as for the DXMT lines of dev-switches.conf). A line of dev-switches.conf with the same
# variable comes later in the rule and wins.
metal_present() {
  local e=DXMT_MTL4_PRESENT=mtl3 why=""
  if [ "$(dxmt_in_use)" != fork ]; then why="$(dev_piece_label dxmt) isn't in the engine"
  elif [ "$(setting metal)" != 4 ]; then why="the Metal row is at Metal 3"
  else
    case "$NL$(dxmt_names)$NL" in *"${NL}DXMT_MTL4_PRESENT$NL"*) ;; *) why="$(dev_piece_label dxmt) doesn't have it" ;; esac
  fi
  if [ -z "$why" ]; then echo "in $e"; else echo "out $e ($why)"; fi
}

# The game's switches in my Wine builds (jdrly/wine; they act on them in Gw2-64.exe only, which is
# the launcher too), one row per setting: "<setting> <entry>". The entry goes into the game's rule
# while the setting isn't off and the file that reads it is mine (heat_entries): WINE_HEAT_* my
# ntdll.so (wine), WINE_MACDRV_* and WINE_WIN32U_* my Mac driver (macdrv; switch_lib). The entry
# also needs that file to have the switch (switch_in_file). An entry ending in = takes the
# setting's value, and stays out at the setting's default. A new switch is a new row.
#   launcherframes  my winemac.so hands Cocoa a copy of each frame of a window it draws with GDI,
#                   such as the launcher's, and skips a frame equal to the last (#57)
#   mousespeed      my winemac.so multiplies GameController's mouse counts by the factor before
#                   the game gets them; only while Raw mouse-look is on, as with it off the game
#                   doesn't get those counts
#   fex            the FEX my ntdll.so's sampler may read (#111): while my FEX is in place, its
#                   libarm64ecfex.dll's build id, age and SizeOfImage from its VERSION
#                   (fex_prof_id). A build id can't tell that a FEX is mine; the app installed it.
#                   Only for an ntdll.so whose switches: line names it (no line is no)
# No row for WINE_HEAT_MSYNC_UNREG: since #104 my ntdll.so unregisters without a switch. An older
# one that still reads it runs with the unregister off, as the engine's own does (#105).
HEAT_SWITCHES="
jobwakes WINE_HEAT_WAKE=one,skip
eventpool WINE_HEAT_EVPOOL=1
fastlocks WINE_HEAT_SPIN=lock=20:game,event=30:game
fex WINE_HEAT_PROF_FEX=
launcherframes WINE_MACDRV_SURFACE=copy,skip
mousespeed WINE_MACDRV_MOUSE_SCALE=
"
# switch_entry <setting>: its row's entry, or nothing; switch_lib <entry>: the unix_lib key whose
# file reads it, or nothing for no entry
switch_entry() { printf '%s\n' "$HEAT_SWITCHES" | awk -v k="$1" '$1 == k { print $2 }'; }
switch_lib() { case "$1" in '') ;; WINE_MACDRV_*|WINE_WIN32U_*) echo macdrv ;; *) echo wine ;; esac; }
# switch_in_file <entry>: the file of mine in this app that reads the entry (switch_lib: my ntdll.so
# or my winemac.so) reads its variable. Its VERSION names the commit, not the switches, and a
# commit can't tell which of them it has. So the answer comes from a line "switches: <variable> …"
# (every switch variable the file reads) when VERSION has one, and is yes when it hasn't.
# switch_named <entry>: the same, but no without the line (a development build's lines,
# dev_lines, need the record to name them)
switch_in_file() {
  grep -q '^switches:' "$(switch_version "$1")" 2>/dev/null || return 0
  switch_named "$1"
}
switch_named() { in_list "${1%%=*}" "$(sed -n 's/^switches://p' "$(switch_version "$1")" 2>/dev/null | head -1)"; }
switch_version() { if [ "$(switch_lib "$1")" = macdrv ]; then echo "$COMP/macdrv/VERSION"; else echo "$COMP/ntdll/VERSION"; fi; }
# heat_entries: the entries for the game's rule, one a line and already through cdb_value (a
# newline in the logs folder's path can't split one): the switches that are on and whose file is
# mine and, with Debug logging and my ntdll.so, its counters (WINE_HEAT_COUNT), which it writes to
# the logs folder as heat-<pid>.log every 5 s, and FEX's counters (FEX_PROFILESTATS=1: FEX keeps
# them per thread, my ntdll.so reads them; each costs FEX a timer read around every compile and
# locked lookup). None of a file while the engine's own is in place. With Debug logging, whichever
# ntdll.so, FEX_SILENTLOG=0 too: FEX's messages go to wine.log, where the session report looks for
# "FEX: Using hardware TSO".
heat_entries() {
  local k e v wine macdrv fex
  wine=$(lib_in_use wine) macdrv=$(lib_in_use macdrv) fex=$(fex_in_use)
  printf '%s\n' "$HEAT_SWITCHES" | while read -r k e; do
    [ -n "$k" ] && v=$(setting "$k") && [ "$v" != off ] || continue
    if [ "$k" = fex ]; then
      [ "$fex" = mine ] && v=$(fex_prof_id) && [ -n "$v" ] || continue
      grep -q '^switches:' "$COMP/ntdll/VERSION" 2>/dev/null || continue
      e=$e$v
    else
      case "$e" in *=) [ "$v" != "$(setting_default "$k")" ] || continue; e=$e$v ;; esac
    fi
    [ "$k" != mousespeed ] || [ "$(setting rawmouse)" = on ] || continue
    if [ "$(switch_lib "$e")" = macdrv ]; then [ "$macdrv" = mine ] || continue; else [ "$wine" = mine ] || continue; fi
    switch_in_file "$e" || continue
    cdb_value "$e"; echo
  done
  [ "$(setting debug)" = on ] || return 0
  if [ "$wine" = mine ]; then echo WINE_HEAT_COUNT=1; echo "WINE_HEAT_LOG=$(cdb_value "$LOGS")"; echo FEX_PROFILESTATS=1; fi
  echo FEX_SILENTLOG=0
}
# FEX's switches, one row per setting: "<setting> <entry> <needs>", built like HEAT_SWITCHES (an
# entry ending in = takes the setting's value and stays out at its default). <needs> is fork for
# an option only my FEX has (jdrly/FEX), any for one the engine's FEX has too. The entry goes into
# the game's rule while the setting isn't off and, for fork, my FEX is in place (fex_in_use) and
# its VERSION's "switches:" line names the variable: that line lists every FEX_* option my commits
# add, so a build without the option leaves it out. Empty until a switch of mine has a row.
FEX_SWITCHES="
"
[ -z "$ROOT" ] || FEX_SWITCHES="${GW2_ON_MAC_FEX_SWITCHES:-$FEX_SWITCHES}"
# fex_switch_row <setting>: its row's entry and needs, or nothing
fex_switch_row() { printf '%s\n' "$FEX_SWITCHES" | awk -v k="$1" '$1 == k { print $2, $3 }'; }
# fex_in_version <entry>: my FEX's VERSION names the entry's variable on its switches: line. A
# word there can carry a value, FEX_HOSTFEATURES=disableavx (jdrly/FEX#12: upstream's variable, a
# value only mine honours); the name counts.
fex_in_version() { in_list "${1%%=*}" "$(sed -n 's/^switches://p' "$FEX_COMP/VERSION" 2>/dev/null | head -1 | sed 's/=[^ ]*//g')"; }
# fex_switch_state <entry> <needs>: setting_state for a row of FEX_SWITCHES
fex_switch_state() {
  if [ "$2" != fork ]; then echo ok
  elif ! fex_bundled; then echo "off:Needs my FEX, which this build of the app doesn't have."
  elif [ "$(fex_want)" != mine ]; then echo "off:Needs my FEX, and the engine's own is chosen."
  elif fex_in_version "$1"; then echo ok
  else echo "off:My FEX in this app (jdrly/FEX $(fex_commit | cut -c1-11)) doesn't have this switch."
  fi
}
# fex_entries: the entries of FEX_SWITCHES for the game's rule, one a line, through cdb_value
fex_entries() {
  local k e n v fex
  fex=$(fex_in_use)
  printf '%s\n' "$FEX_SWITCHES" | while read -r k e n; do
    [ -n "$k" ] && v=$(setting "$k") && [ "$v" != off ] || continue
    case "$e" in *=) [ "$v" != "$(setting_default "$k")" ] || continue; e=$e$v ;; esac
    [ "$n" != fork ] || { [ "$fex" = mine ] && fex_in_version "$e"; } || continue
    cdb_value "$e"; echo
  done
}

# --- dev-switches.conf: a development build's switches (DEV_ON)
#
# The forks merge each new behaviour with its switch off. A development build turns every one of
# them on: the rows of DEV_ROWS once, and the rest from dev-switches.conf in the app's folder, one
# NAME=value a line, which I take lines out of when something breaks. A line I comment out (#) or
# delete is off. The game's rule gets every line left, after the rows' entries (dev_entries), and
# CefHost.exe has them unset as it has the others. A line of the table below goes in only while
# the file of mine that reads it is in place and has the switch:
#   wine    my ntdll.so, its VERSION's switches: line (switch_named; a VERSION without the line
#           names none)
#   macdrv  my winemac.so, the same
#   win32u  my win32u.so, which comes in the same build as my winemac.so, when that build has one,
#           and on its switches: line: in place only with my winemac.so, as one set (unix_lib)
#   fex     my FEX, its VERSION's switches: line (fex_in_version)
#   fexany  FEX's own option, which the engine's FEX has too: always
#   dxmt    my DXMT fork. Its build carries no record of its switches: the app looks for the
#           variable's name in the DLLs of the fork's tree in the engine (dxmt_names), where each
#           switch it reads is a string. That tree can be an earlier build of mine while Steam
#           still runs with it, so it's the one read, not this app's.
# A line that isn't in the table (one I added) goes in as it is. What stays out is said once in the
# log at each start (launch), and status and the session report list what went in.
#
# The table, one switch a row: "<version> <piece> <issue> <played|unplayed> <NAME=value> <what it
# does>". dev_update writes the file at install and when the table's version is newer than the
# file's (its line version=): each row newer than the file whose variable the file doesn't name,
# not even commented out, is added at the end, on. Nothing else in the file changes. A switch goes
# in at the value that turns its new behaviour on. Not in it: diagnostics (Debug logging has
# them), anything that can cap the frame rate below 60 (the lower thread
# priorities DXMT_THREAD_PRIORITY, DXMT_COMPILE_PRIORITY and DXMT_RENDER_THREAD_PRIORITY, which
# are tuning values, and lower priorities cost frames in crowds on 0.1.x; DXMT_BG_POLICY=occlusion,
# which throttles the game whenever another window covers it), a value only I can choose (the
# mouse speed, DXMT_CHUNKS), a switch that brings back upstream's behaviour (DXMT_DEPTH_PFV,
# DXMT_STENCIL_PFV), and the rows' own variables. A row whose variable a line of the file sets is
# greyed while the line is there (dev_sets): the file's entry comes later in the rule and wins. A fork's issues are
# jdrly/<fork>#n, the app's #n. Unplayed: no session of the game has run with it. A DXMT switch
# that acts on one Metal only (DXMT_DRAIN_SPLITS, Metal 3) stays in with the Metal row at the other,
# where it does nothing, so my lines last through a switch of Metal; its comment says so. DXMT_MTL4_PRESENT=mtl3 left the table at
# version 4: the game's rule has it at Metal 4 in every build (metal_present). DXMT_MTL4_LAYER_SET
# (jdrly/dxmt#226), a diagnostic for the same stutter, stays out: I turn it on by hand, so a change
# in play has one cause. My ntdll.so's other changes
# have no line: #99's counts act only with WINE_HEAT_COUNT=1, which Debug logging sets; the app sets
# WINE_HEAT_PROF_FEX itself (#111); #101 and #104 have no switch. FEX_ENTRYHEADERLOOKUP (#162) is on
# in my FEX by default, and off while the rule can start my ntdll.so's sampler (sampler_fex); a line
# of the file that turns it on stays out then.
# FEX_HOSTFEATURES (#118) is a comma list that FEX ORs into one mask, and in a compatdb rule a later
# entry for a variable replaces the earlier one. So the file's FEX_HOSTFEATURES lines go into the
# rule as one entry (hf_join), and while a rule of compatdb.local for Gw2-64.exe sets it
# (local_hostfeatures), that rule replaces them: they stay out, saying what to write there instead.
DEV_SWITCHES="
1 wine #14,#45 unplayed WINE_HEAT_SPIN=lock=20:game,event=30:game,sem=5:game the Faster locks row's two spins, and the job workers spin 5 µs on their semaphore before they sleep. While this line is here, its value replaces the row's.
1 macdrv #62 unplayed WINE_MACDRV_VIEW=changes a window's view frame goes to the main thread only when it changed
1 macdrv #62 unplayed WINE_MACDRV_CLIP=changes ClipCursor doesn't call the main thread for the rectangle it applied last
1 macdrv #62 unplayed WINE_MACDRV_CALL=quiet after a call to the main thread, the event pipe holds a byte only if an event waits
1 macdrv #62 unplayed WINE_MACDRV_DRAIN=fionread ProcessEvents asks the event pipe for its byte count instead of polling it
1 win32u #61 unplayed WINE_WIN32U_SETCURSOR=shm SetCursor answers a repeated cursor from shared memory
1 win32u #61 unplayed WINE_WIN32U_PEEK_YIELD=off an empty PeekMessage doesn't yield
1 fex #112 unplayed FEX_INITIALCODEBUFFERMB=128 the first code buffer is 128 MB instead of 16
1 fex #113 unplayed FEX_HARDWARETSOSYSCALLS=keep the hardware memory ordering stays on through Wine's system calls
1 fexany #47 unplayed FEX_DYNAMICL1CACHE=0 a fixed L1 lookup cache instead of the dynamic one (16 MB of address space a thread). Hung once at process start on the runner (jdrly/FEX run 43315659403, #132): if a development build doesn't start, take this line out first.
1 dxmt jdrly/dxmt#185 unplayed DXMT_PRESENTER_FREE=1 a swap chain's presenter is freed with its last reference
1 dxmt jdrly/dxmt#159 unplayed DXMT_WARM_JOBS=2 with Shader warming, two speculative jobs at once while Metal's cache is cold
1 dxmt jdrly/dxmt#147 unplayed DXMT_SKIP_SAME_SRV=1 SetShaderResources skips a slot that already holds the incoming view
1 dxmt jdrly/dxmt#73 unplayed DXMT_COMPILE_DEMAND=1 the compile service's declared policy (Shader warming turns it on too)
6 fex #164 unplayed FEX_LEA32BITADDS=1 lea with a 32-bit destination computes its address with 32-bit adds, one instruction instead of two
6 fex #164 unplayed FEX_SIGNEXTENDINGLOADS=1 movsx and movsxd from memory load and sign-extend in one instruction when the load needs no TSO emulation, which hardware TSO turns off
6 fex #165 unplayed FEX_ENTRYCOMPILELOCK=1 threads that miss on the same entry at once compile it once, and FEX's pool allocators read the CPU's counter for their clock instead of QueryPerformanceCounter
6 fex #118 unplayed FEX_HOSTFEATURES=disableavx the game sees no AVX, AVX2, BMI, FMA or F16C and takes its SSE paths. Another FEX_HOSTFEATURES line here joins this one. A compatdb.local rule for Gw2-64.exe that sets FEX_HOSTFEATURES replaces them, and status says what to write there instead. If the game crashes at start or in play, take this line out first.
6 dxmt jdrly/dxmt#265 unplayed DXMT_RENAME_TRIM=600 every 2 s, the rename queues give back the allocations the GPU finished with more than 600 sequence ids (about 10 s) ago
10 dxmt jdrly/dxmt#324 unplayed DXMT_PRESENT_SKIP_NIL=1 a present whose layer gave no drawable (nextDrawable timed out, or the drawable size is zero) is skipped: no pass, no wait and no present call, instead of the nil going to Metal
10 dxmt jdrly/dxmt#316 unplayed DXMT_DRAIN_SPLITS=1 only with the Metal row at Metal 3, nothing on Metal 4: at teardown the drain also waits for the split-off command buffers of chunks not yet retired, so it frees nothing they still use
10 dxmt jdrly/dxmt#314 unplayed DXMT_REFRESH_REQUERY=1 the swap chain reads the monitor's refresh rate again after exclusive fullscreen and for a fullscreen mode of 0 Hz, instead of assuming 60 Hz
10 dxmt jdrly/dxmt#314 unplayed DXMT_STEADY_SLEEP=1 the frame limiter and the background throttle keep their deadlines on QueryPerformanceCounter and sleep for what is left, so a wall clock that steps back can't lengthen a sleep
"
# Rows taken out of the table, "<version> <issue> <NAME=value> <off value>". dev_update brings a file
# older than <version> up to it (dev_gone): the line as the table wrote it goes, with the comment and
# the empty line above it. A line with another value stays, and like every line of the file it comes
# after the rule's entries and wins. A line I commented out becomes NAME=<off value> under a comment
# saying why, so what I turned off stays off. An off value of - is a switch that left my fork: there
# is nothing to keep off, so a line I commented out stays as it is. Version 4: DXMT_MTL4_PRESENT=mtl3,
# which the game's rule has at Metal 4 (metal_present); mtl4 is my fork's name for Metal 4's own
# present. Version 8: my DXMT fork deletes the PSO archive (jdrly/dxmt#5, #75: with it on the game
# crashed at exit, and Metal's own shader cache already keeps what it saved) and the present
# queue's pace (jdrly/dxmt#157: it gave up at frame 181 in every session).
# Version 9: my DXMT fork has jdrly/dxmt#153, #154 and #204 on by default, and =0 turns each off.
# Version 10: my DXMT fork has jdrly/dxmt#271's wait on by default (jdrly/dxmt#332), and =next turns
# it off. Version 11: my FEX has #161's and #162's lookups on by default (#266), and =0 turns each off.
DEV_GONE="
4 jdrly/dxmt#227 DXMT_MTL4_PRESENT=mtl3 mtl4
8 jdrly/dxmt#157 DXMT_PRESENT_QUEUE=pace -
8 jdrly/dxmt#5 DXMT_PSO_ARCHIVE=1 -
8 jdrly/dxmt#75 DXMT_PSO_GENERATIONS=1 -
9 jdrly/dxmt#153 DXMT_MTL4_DEVICE_RESIDENCY=1 0
9 jdrly/dxmt#154 DXMT_MTL4_TIMESTAMP_REUSE=1 0
9 jdrly/dxmt#204 DXMT_MTL4_ALLOCATOR_POOL=1 0
10 jdrly/dxmt#271 DXMT_MTL4_SHOWN_WAIT=write next
11 #161 FEX_DISPATCHERL1LOOKUP=1 0
11 #162 FEX_ENTRYHEADERLOOKUP=1 0
"
DEV_SWITCHES_VERSION=$(printf '%s\n' "$DEV_SWITCHES" "$DEV_GONE" | awk 'NF && $1 > v { v = $1 } END { print v + 0 }')
# dev_piece_label <piece>: what the file and the log call it
dev_piece_label() {
  case "$1" in
    wine) echo "my ntdll.so" ;;
    macdrv) echo "my winemac.so" ;;
    win32u) echo "my win32u.so" ;;
    fex) echo "my FEX" ;;
    fexany) echo "FEX's own option" ;;
    dxmt) echo "my DXMT fork" ;;
  esac
}
# dev_sets <entry of a row>: in a development build, a line of dev-switches.conf sets the entry's
# variable and goes into the rule (my file's record names it: the row's caller has checked that the
# file is mine)
dev_sets() { [ -n "$DEV_ON" ] && grep -q "^${1%%=*}=" "$DEV_FILE" 2>/dev/null && switch_named "$1"; }
# dev_file_version: dev-switches.conf's version= (0 without the file or the line)
dev_file_version() {
  local v
  v=$(sed -n 's/^version=//p' "$DEV_FILE" 2>/dev/null | head -1)
  case "$v" in ''|*[!0-9]*) echo 0 ;; *) echo "$v" ;; esac
}
# dev_update: in a development build, the rows of DEV_ROWS on once (settings.conf), and
# dev-switches.conf written, or brought up to the table's version (the header above DEV_SWITCHES)
dev_update() {
  [ -n "$DEV_ON" ] || return 0
  local v since piece ref played entry text added="" gone=""
  if [ "$(dev_version)" -lt "$DEV_ROWS_VERSION" ]; then
    say "Development build: the switch rows on, once: $(printf '%s\n' "$DEV_ROWS" | awk -v v="$(dev_version)" 'NF && $1 > v { for (i = 2; i <= NF; i++) { printf "%s%s", s, $i; s = " " } }')"
    write_settings
  fi
  v=$(dev_file_version)
  [ "$v" -lt "$DEV_SWITCHES_VERSION" ] || return 0
  # (the rows newer than the file whose variable it doesn't name, not even commented out)
  added=$(printf '%s\n' "$DEV_SWITCHES" | while read -r since piece ref played entry text; do
    [ -n "$since" ] && [ "$since" -gt "$v" ] || continue
    dev_names "$entry" || echo "$entry"
  done)
  # (the rows taken out of the table since the file's version, for an existing file)
  [ ! -f "$DEV_FILE" ] || gone=$(printf '%s\n' "$DEV_GONE" | awk -v v="$v" 'NF && $1 > v { print $3 }')
  {
    if [ ! -f "$DEV_FILE" ]; then
      echo "version=$DEV_SWITCHES_VERSION"
      echo "# My development switches ($APP_NAME, development builds only). One switch a line, NAME=value,"
      echo "# with what it does above it: the piece that reads it, its issue, and whether a session of"
      echo "# the game has run with it (played or unplayed). A line I comment out (#) or delete is off. The"
      echo "# game gets every line left, while the file that reads it is in place and has the switch. A"
      echo "# newer build adds its new switches at the end, on. It changes a line here only when its"
      echo "# switch leaves the list: a line as the build wrote it goes, a line I commented out stays off."
    elif grep -q '^version=' "$DEV_FILE"; then
      sed "s/^version=.*/version=$DEV_SWITCHES_VERSION/" "$DEV_FILE" | dev_gone "$v"
    else
      echo "version=$DEV_SWITCHES_VERSION"
      dev_gone "$v" <"$DEV_FILE"
    fi
    printf '%s\n' "$DEV_SWITCHES" | while read -r since piece ref played entry text; do
      in_list "$entry" "$added" || continue
      echo
      echo "# $(dev_piece_label "$piece") ($ref), $played: $text"
      echo "$entry"
    done
  } | put "$DEV_FILE" 644
  say "dev-switches.conf: version $DEV_SWITCHES_VERSION, switched on: $(printf '%s' "${added:-nothing}" | tr '\n' ' ')${gone:+; out of the list: $(printf '%s' "$gone" | tr '\n' ' ')}"
}
# dev_names <entry of a row>: dev-switches.conf has a line for the entry's variable, on or commented
# out. For FEX_HOSTFEATURES only a line with one of the row's features, enabled or disabled, counts:
# a line of mine with other items (enableafp) isn't a choice about AVX.
dev_names() {
  [ -f "$DEV_FILE" ] || return 1
  if [ "${1%%=*}" != FEX_HOSTFEATURES ]; then grep -qE "^[#[:space:]]*${1%%=*}=" "$DEV_FILE"; return; fi
  awk -v row="${1#*=}" '
    BEGIN { n = split(row, r, ","); for (i = 1; i <= n; i++) { k = r[i]; sub(/^(enable|disable)/, "", k); want[k] = 1 } }
    /^[#[:space:]]*FEX_HOSTFEATURES=/ {
      v = $0; sub(/^[^=]*=/, "", v); n = split(v, it, ",")
      for (i = 1; i <= n; i++) { k = it[i]; sub(/^(enable|disable)/, "", k); if (k in want) f = 1 }
    }
    END { exit !f }' "$DEV_FILE"
}
# hf_join <value>...: FEX_HOSTFEATURES values (comma lists; an argument can hold several, one a line)
# as one, their items in order. Of two items for one feature (enableX, disableX) the later stays: FEX
# refuses a value with both (ENABLE_DISABLE_OPTION in jdrly/FEX's Source/Common/HostFeatures.cpp). An
# item twice stays once.
hf_join() {
  printf '%s\n' "$@" | tr ',' '\n' | awk '
    NF { k = $0; if (!sub(/^(enable|disable)/, "", k)) k = "=" k
         if (k in at) del[at[k]] = 1
         at[k] = NR; item[NR] = $0 }
    END { for (i = 1; i <= NR; i++) if ((i in item) && !(i in del)) { printf "%s%s", s, item[i]; s = "," } }'
}
# local_hostfeatures: "FEX_HOSTFEATURES=<value>" when a rule of compatdb.local for Gw2-64.exe sets it
# (the last such rule's value), else nothing. Matched as compatdb matches them, without case. That
# rule comes after the app's, so its entry replaces the app's.
local_hostfeatures() {
  [ -f "$RULES_LOCAL" ] || return 0
  awk -F';' '
    { exe = 0; set = 0
      for (i = 1; i <= NF; i++) {
        f = tolower($i)
        if (f == "exe=gw2-64.exe") exe = 1
        else if (index(f, "env=fex_hostfeatures=") == 1) { set = 1; v = substr($i, 22) }
      }
      if (exe && set) { found = 1; out = v } }
    END { if (found) printf "FEX_HOSTFEATURES=%s", out }' "$RULES_LOCAL"
}
# dev_gone <the file's version>: dev-switches.conf from stdin to stdout, without the rows of DEV_GONE
# newer than the file (the header above DEV_GONE). A line commented out with spaces or more than one
# # counts too, as dev_update's search for a name does. With a line of the variable on, one
# commented out stays as it is. A row whose off value is - never changes a commented-out line. (The
# rows go in through the environment: macOS's awk refuses a -v value with a newline.)
dev_gone() {
  GONE_ROWS="$DEV_GONE" awk -v v="$1" '
    BEGIN {
      n = split(ENVIRON["GONE_ROWS"], r, "\n")
      for (i = 1; i <= n; i++) {
        if (split(r[i], f, " ") < 4 || f[1] + 0 <= v + 0) continue
        k = f[3]; sub(/=.*/, "", k); line[k] = f[3]; ref[k] = f[2]; off[k] = f[4]; since[k] = f[1]
      }
    }
    { l[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (match(l[i], /^[A-Za-z_][A-Za-z0-9_]*=/)) on[substr(l[i], 1, RLENGTH - 1)] = 1
      for (i = 1; i <= NR; i++) {
        for (k in line) {
          if (l[i] == line[k]) {
            drop[i] = 1
            if (i > 1 && index(l[i - 1], "# ") == 1 && index(l[i - 1], "(" ref[k] ")")) {
              drop[i - 1] = 1
              if (i > 2 && l[i - 2] == "") drop[i - 2] = 1
            }
          } else if (off[k] != "-" && !(k in on) && l[i] ~("^[[:space:]]*#[#[:space:]]*" k "=")) {
            l[i] = "# Commented out before version " since[k] ". " line[k] " is on without this line now, so this keeps it off. Take this line out to turn it on.\n" k "=" off[k]
            on[k] = 1
          }
        }
      }
      for (i = 1; i <= NR; i++) if (!drop[i]) print l[i]
    }'
}
# dxmt_names: the DXMT_* names in the DLLs the game loads (aarch64-windows) of my DXMT fork's tree
# in the engine, or of this app's build without an engine, one a line (every byte that can't be in a
# name splits them, so a name inside a longer one doesn't count; -s makes each run of such bytes
# one newline: the real DLLs are 15 MB, 13 million lines for grep without it and 1.3 million with)
dxmt_names() {
  local d="$DXGI/dxmt/aarch64-windows"
  [ -d "$d" ] || d="$COMP/dxmt/aarch64-windows"
  find "$d" -type f -name '*.dll' -exec cat {} + 2>/dev/null | LC_ALL=C tr -cs 'A-Z0-9_' '\n' |
    LC_ALL=C grep -x 'DXMT_[A-Z0-9_]*' | LC_ALL=C sort -u || true
}
# heat_prof_on: the game's rule can start my ntdll.so's sampler: WINE_HEAT_PROF=on or =1, or
# WINE_HEAT_CONTROL, whose file can say prof=on during a session, in a line of dev-switches.conf (a
# development build's) or an env= entry of compatdb.local. Any rule's entry counts: a rule for
# exe=* or the game's Steam app id reaches the game too, and one for another program only costs
# the game FEX_ENTRYHEADERLOOKUP for as long as that line stays (sampler_fex). (awk reads all of
# it: nothing ends the pipe early under pipefail.)
heat_prof_on() {
  { if [ -n "$DEV_ON" ] && [ -f "$DEV_FILE" ]; then cat "$DEV_FILE"; fi
    if [ -f "$RULES_LOCAL" ]; then tr ';' '\n' <"$RULES_LOCAL" | sed -n 's/^env=//p'; fi; } |
    awk '/^WINE_HEAT_PROF=(on|1)$/ || /^WINE_HEAT_CONTROL=./ { f = 1 } END { exit !f }'
}
# sampler_fex: FEX_ENTRYHEADERLOOKUP=0 for the game's rule while the rule can start my ntdll.so's
# sampler (heat_prof_on) and my FEX, whose record names the switch, is in the engine; else nothing.
# With the switch on, FEX no longer stores the block a thread entered last, which the sampler reads
# (jdrly/FEX's GW2Contract.h), and my FEX has it on by default (#266). It comes after the file's
# lines in the rule, so it wins over them. A release too: compatdb.local can start the sampler there.
sampler_fex() {
  heat_prof_on && [ "$(fex_in_use)" = mine ] && fex_in_version FEX_ENTRYHEADERLOOKUP || return 0
  echo FEX_ENTRYHEADERLOOKUP=0
}
# dev_lines: dev-switches.conf's switch lines in a development build, one a line: "in NAME=value"
# for one that goes into the game's rule, "out NAME=value <why>" for one that stays out. The
# FEX_HOSTFEATURES lines that go in are one "in" line, at the first one's place (hf_join).
dev_lines() {
  [ -n "$DEV_ON" ] && [ -f "$DEV_FILE" ] || return 0
  local l row piece wine macdrv fex dxmt dnames="" why sampler hf lhf hfdone=""
  wine=$(lib_in_use wine) macdrv=$(lib_in_use macdrv) fex=$(fex_in_use) dxmt=$(dxmt_in_use)
  [ "$dxmt" != fork ] || dnames=$(dxmt_names)
  sampler=$(sampler_fex)
  # (the file's FEX_HOSTFEATURES as one value, and compatdb.local's for the game, which replaces it)
  hf=$(sed -n 's/^FEX_HOSTFEATURES=//p' "$DEV_FILE")
  hf=$(hf_join "$hf")
  lhf=$(local_hostfeatures)
  awk '/^[A-Za-z_][A-Za-z0-9_]*=/ && !/^version=/' "$DEV_FILE" | while IFS= read -r l; do
    row=$(printf '%s\n' "$DEV_SWITCHES" | awk -v n="${l%%=*}" '{ e = $5; sub(/=.*/, "", e) } e == n { print $2; exit }')
    # (a line of mine that isn't in the table: no piece, it goes in as it is)
    piece=${row:-none} why=""
    case "$piece" in
      wine|macdrv|win32u)
        case "$piece" in
          wine) [ "$wine" = mine ] ;;
          macdrv) [ "$macdrv" = mine ] ;;
          win32u) [ "$macdrv" = mine ] && [ -f "$COMP/macdrv/win32u.so" ] ;;
        esac || why="$(dev_piece_label "$piece") isn't in the engine"
        [ -n "$why" ] || switch_named "$l" || why="$(dev_piece_label "$piece") doesn't have it" ;;
      fex)
        if [ "$fex" != mine ]; then why="$(dev_piece_label fex) isn't in the engine"
        elif ! fex_in_version "$l"; then why="$(dev_piece_label fex) doesn't have it"
        elif [ "${l%%=*}" = FEX_HOSTFEATURES ] && [ -n "$lhf" ]; then
          why="compatdb.local's rule for Gw2-64.exe sets $lhf, which comes later and replaces it. For both, write FEX_HOSTFEATURES=$(hf_join "$hf" "${lhf#*=}") there"
        elif [ "${l%%=*}" = FEX_HOSTFEATURES ]; then
          [ -z "$hfdone" ] || continue
          hfdone=1 l=FEX_HOSTFEATURES=$hf
        fi ;;
      dxmt)
        if [ "$dxmt" != fork ]; then why="$(dev_piece_label dxmt) isn't in the engine"
        elif ! printf '%s\n' "$dnames" | grep -qx "${l%%=*}"; then why="$(dev_piece_label dxmt) doesn't have it"
        fi ;;
      none)
        if [ "${l%%=*}" = FEX_ENTRYHEADERLOOKUP ] && [ -n "$sampler" ]; then
          why="the sampler can run (WINE_HEAT_PROF or WINE_HEAT_CONTROL), so the game's rule has FEX_ENTRYHEADERLOOKUP=0 after it"
        fi ;;
    esac
    if [ -z "$why" ]; then echo "in $l"; else echo "out $l ($why)"; fi
  done
}
# dev_entries: the lines of dev_lines that go in, for the game's rule, one a line, through cdb_value
dev_entries() {
  local l
  dev_lines | sed -n 's/^in //p' | while IFS= read -r l; do cdb_value "$l"; echo; done
}
# dev_session_line <dev_lines' output>: session.env's DEV_SWITCHES= (what went in) and
# DEV_SWITCHES_OUT= (what stayed out, each with why, joined by "; "), which the session report's
# header prints, in a development build only
dev_session_line() {
  [ -n "$DEV_ON" ] || return 0
  echo "DEV_SWITCHES=$(printf '%s\n' "$1" | sed -n 's/^in //p' | tr '\n' ' ' | sed 's/ $//')"
  echo "DEV_SWITCHES_OUT=$(printf '%s\n' "$1" | sed -n 's/^out //p' | awk '{ printf "%s%s", s, $0; s = "; " }')"
}
# and a rename, so a process that starts meanwhile reads the old rules or the new, never half)
write_rules() {
  { rules_text; [ ! -f "$RULES_LOCAL" ] || cat "$RULES_LOCAL"; } | put "$RULES" 644
}

# --- Engine

engine_ok() { [ -x "$ENG/bin/wine" ] && [ "$(cat "$ENG/.gw2om-source" 2>/dev/null || true)" = "$ENGINE_SHA256" ]; }
# engine_old: an engine is there, but not this app's: one of another release that an earlier
# version of the app installed (docs/adr/0016). It still counts as installed; Play refuses and
# Repair replaces it.
engine_old() { [ -x "$ENG/bin/wine" ] && ! engine_ok; }
# engine_label <its tarball's sha256>: the engine by name
engine_label() {
  case "$1" in
    "$ENGINE_SHA256" | "$ENGINE_PIN_SHA256") echo "$ENGINE_TITLE" ;;
    "$ENGINE_0_3_1_SHA256") echo "Mach9 0.3.1 · Wine 11.21" ;;
    *) echo "another build of the engine" ;;
  esac
}
# record_engine <VERSION>: the sha256 of the engine that record of mine is built for (0.3.1's
# without an engine: line)
record_engine() {
  local s
  s=$(sed -n 's/^engine: .*sha256 \([0-9a-f]\{64\}\).*/\1/p' "$1" 2>/dev/null | head -1)
  echo "${s:-$ENGINE_0_3_1_SHA256}"
}
# engine_refusal: why none of my files may go into the engine now, or nothing. Either the engine
# there is not this app's (an earlier version of the app left one of another release: Repair
# replaces it), or one of my files' records names another engine than the pin.
engine_refusal() {
  local d n
  if ! engine_ok; then
    echo "The engine here is $(engine_label "$(cat "$ENG/.gw2om-source" 2>/dev/null || true)"), and my files are built for $ENGINE_TITLE, so they stay out of it. Click Repair to put $ENGINE_TITLE in place."
    return
  fi
  for d in dxmt ntdll macdrv fex; do
    [ -f "$COMP/$d/VERSION" ] || continue
    [ "$(record_engine "$COMP/$d/VERSION")" != "$ENGINE_PIN_SHA256" ] || continue
    case $d in dxmt) n="My DXMT fork" ;; ntdll) n="My ntdll.so" ;; macdrv) n="My Mac driver" ;; *) n="My FEX" ;; esac
    echo "$n in this app is built for $(engine_label "$(record_engine "$COMP/$d/VERSION")"), not for $ENGINE_TITLE, so none of my files go into the engine."
    return
  done
}

# engine_matches <dir>: the unpacked engine is the expected build: its loader's sha256, the
# engine's own ntdll.so, winemac.so and win32u.so (in place, or next to mine as <file>.engine: every
# file of unix_lib's rows) and FEX's three files (the same, FEX_FILES), and wine.app's signature
# (codesign reads it and starts nothing): valid, by Mach9's team, with the loader's identifier
engine_matches() {
  local app="$1/$ENGINE_LOADER_APP" info k f u="$1/lib/wine/aarch64-unix"
  [ "$(sha256 "$app/Contents/MacOS/wine" 2>/dev/null)" = "$ENGINE_LOADER_SHA256" ] || return 1
  for k in $UNIX_LIBS; do
    unix_lib "$k"
    for f in $LIB_FILES; do
      [ "$(sha256 "$u/$f" 2>/dev/null)" = "$(lib_pin "$f")" ] || [ "$(sha256 "$u/$f.engine" 2>/dev/null)" = "$(lib_pin "$f")" ] || return 1
    done
  done
  for k in $FEX_FILES; do
    [ "$(sha256 "$1/lib/wine/$k" 2>/dev/null)" = "$(fex_pin "$k")" ] || [ "$(sha256 "$1/lib/wine/$k.engine" 2>/dev/null)" = "$(fex_pin "$k")" ] || return 1
  done
  codesign --verify --strict "$app" >>"$LOGFILE" 2>&1 || return 1
  info=$(codesign -dv "$app" 2>&1) || return 1
  printf '%s\n' "$info" | grep -qx "Identifier=$ENGINE_LOADER_ID" &&
    printf '%s\n' "$info" | grep -qx "TeamIdentifier=$ENGINE_TEAM"
}

# --- DXMT: my fork (components/dxmt, jdrly/dxmt built for this engine) or the engine's own
#
# Mach9's compatdb gives every process the DXGI tree lib/wine/dxgi/dxmt (its built-in dxgi=dxmt
# rule; Steam's web helper is pinned to it), and Wine loads winemetal.so from the same tree's
# aarch64-unix/. A rule can't point the game at a tree of mine: the dxgi key knows only dxmt and
# wined3d. So the app swaps the tree itself, outside wine.app. The active one is always
# lib/wine/dxgi/dxmt, and the other waits next to it:
#   dxmt.engine   the engine's own, as it ships (moved aside, never changed)
#   dxmt.fork     the engine's tree with my fork's files over it (components/dxmt: d3d11, dxgi,
#                 d3d10core and winemetal for aarch64-windows and i386-windows, winemetal.so,
#                 VERSION and the licence), marked with $DXMT_MARK. The engine's tree has
#                 aarch64-unix/winemetal.so as a link to lib/wine/aarch64-unix/winemetal.so, the
#                 one .so behind its ARM64X and i386 DLLs: mine replaces the link with its own
#                 file, so the two DXMTs never share one, and the engine's stays as it ships
# Steam's processes get the same DXMT as the game, as on 0.1.x. The setting dxmt (fork|engine)
# picks the tree; the swap happens only while no session runs or starts (apply_engine_files): at install,
# repair, set dxmt and Play.
DXGI="$ENG/lib/wine/dxgi"
DXMT_MARK=.gw2om-dxmt
# my fork's build: its VERSION's first line (git describe: v0.80-…-g<commit>), the release and
# the commit in it
DXMT_VERSION="$(head -1 "$COMP/dxmt/VERSION" 2>/dev/null || true)"
DXMT_RELEASE="$(printf '%s\n' "$DXMT_VERSION" | grep -oE 'v[0-9]+(\.[0-9]+)+' | head -1 | cut -c2- || true)"
DXMT_COMMIT="$(printf '%s\n' "$DXMT_VERSION" | grep -oE '[0-9a-f]{7,40}' | tail -1 || true)"
# dxmt_files: the component's files, relative to components/dxmt
dxmt_files() { (cd "$COMP/dxmt" 2>/dev/null && find . -type f | sed 's|^\./||' | LC_ALL=C sort); }
# dxmt_tree <dir>: engine (the engine's own DXMT: its d3d11.dll and winemetal.so), fork (mine, this
# app's build), oldfork (mine, another build: an earlier version of the app), other, none. An
# answer dxmt_look has remembered in this run comes from DXMT_SEEN, without reading the files again.
dxmt_tree() {
  local t=$1 f s=${DXMT_SEEN#*"$NL$1="}
  if [ "$s" != "$DXMT_SEEN" ]; then echo "${s%%"$NL"*}"; return; fi
  [ -d "$t" ] || { echo none; return; }
  if [ ! -e "$t/$DXMT_MARK" ] && [ "$(sha256 "$t/aarch64-windows/d3d11.dll" 2>/dev/null)" = "$ENGINE_D3D11_SHA256" ] &&
    [ "$(sha256 "$t/aarch64-unix/winemetal.so" 2>/dev/null)" = "$ENGINE_WINEMETAL_SHA256" ]; then
    echo engine; return
  fi
  [ -f "$t/$DXMT_MARK" ] || { echo other; return; }
  for f in $(dxmt_files); do cmp -s "$COMP/dxmt/$f" "$t/$f" || { echo oldfork; return; }; done
  echo fork
}
# dxmt_look <dir>: dxmt_tree's answer for <dir>, remembered for the rest of this run. My fork's build
# is tens of MB, and Play and status ask for the active tree up to five times, mostly from $(…),
# whose variables die with it: so the command's own shell calls this first, and the $(…) after it
# inherit DXMT_SEEN. dxmt_switch forgets the answers when it changes a tree.
NL=$'\n'
DXMT_SEEN=""
dxmt_look() {
  case "$DXMT_SEEN" in *"$NL$1="*) return ;; esac
  DXMT_SEEN="$DXMT_SEEN$NL$1=$(dxmt_tree "$1")"
}
# dxmt_in_use: the DXMT the next process loads (fork or engine; without an engine, the setting's)
dxmt_in_use() {
  case "$(dxmt_tree "$DXGI/dxmt")" in engine) echo engine ;; none) setting dxmt ;; *) echo fork ;; esac
}
# dxmt_cache: the game's shader cache for that DXMT
dxmt_cache() { if [ "$(dxmt_in_use)" = engine ]; then echo "$DXMT_CACHE"; else echo "$DXMT_CACHE_FORK"; fi; }
# dxmt_label <fork|engine>: what the window and the log call it
dxmt_label() {
  if [ "$1" = engine ]; then echo "the engine's own DXMT (athei/dxmt $ENGINE_DXMT)"; else echo "my DXMT fork ($DXMT_VERSION)"; fi
}

# Graphics in the engine: yes (the DXMT tree Settings asks for is the active one), switch (it is
# not, and the engine's own tree is there to make it from: apply_engine_files swaps them at the next
# chance), other (something else: Repair unpacks the engine again), no (no engine)
graphics_state() {
  local cur
  [ -x "$ENG/bin/wine" ] || { echo no; return; }
  cur=$(dxmt_tree "$DXGI/dxmt")
  if [ "$cur" = "$(setting dxmt)" ]; then
    echo yes
  elif [ "$cur" != other ] && { [ "$cur" = engine ] || [ "$(dxmt_tree "$DXGI/dxmt.engine")" = engine ]; }; then
    echo switch
  else
    echo other
  fi
}

# dxmt_switch: the tree Settings asks for into place (the caller has made sure that no session runs
# or starts). My fork's tree is made first, from the engine's own; then the active tree goes aside
# (the engine's as dxmt.engine, mine as dxmt.fork, an earlier build of mine away) and the wanted
# one comes in, two renames. Interrupted between them, there is no active tree, and the next
# switch puts it in.
dxmt_switch() {
  local want cur src f
  want=$(setting dxmt)
  dxmt_look "$DXGI/dxmt"
  cur=$(dxmt_tree "$DXGI/dxmt")
  [ "$cur" != "$want" ] || return 0
  if [ "$cur" = engine ]; then src="$DXGI/dxmt"
  elif [ "$cur" != other ] && [ "$(dxmt_tree "$DXGI/dxmt.engine")" = engine ]; then src="$DXGI/dxmt.engine"
  else
    # (graphics_state says other: Play and set dxmt say Repair)
    log "DXMT: the engine's tree is neither its own nor mine; $(dxmt_label "$want") waits for Repair"
    return 0
  fi
  DXMT_SEEN=""
  if [ "$want" = fork ] && [ "$(dxmt_tree "$DXGI/dxmt.fork")" != fork ]; then
    safe_rm "$DXGI/dxmt.fork.new" "$DXGI/dxmt.fork"
    run cp -Rp "$src" "$DXGI/dxmt.fork.new"
    for f in $(dxmt_files); do
      run mkdir -p "$(dirname "$DXGI/dxmt.fork.new/$f")"
      # (the engine's winemetal.so is a link into lib/wine/aarch64-unix: removed, never written through)
      run rm -f "$DXGI/dxmt.fork.new/$f"
      run cp -p "$COMP/dxmt/$f" "$DXGI/dxmt.fork.new/$f"
    done
    if [ -z "$DRY" ]; then
      echo "$DXMT_VERSION" >"$DXGI/dxmt.fork.new/$DXMT_MARK"
      # cp -p copies the quarantine attribute of an app copied out of a browser's download (a dev
      # build is ad hoc signed, not notarized), and the engine's tree has none (install_engine)
      run xattr -dr com.apple.quarantine "$DXGI/dxmt.fork.new"
    fi
    run mv "$DXGI/dxmt.fork.new" "$DXGI/dxmt.fork"
  fi
  case "$cur" in
    engine) safe_rm "$DXGI/dxmt.engine"; run mv "$DXGI/dxmt" "$DXGI/dxmt.engine" ;;
    fork) safe_rm "$DXGI/dxmt.fork"; run mv "$DXGI/dxmt" "$DXGI/dxmt.fork" ;;
    oldfork) safe_rm "$DXGI/dxmt" ;;
  esac
  run mv "$DXGI/dxmt.$want" "$DXGI/dxmt"
  dxmt_look "$DXGI/dxmt"
  say "DXMT: $(dxmt_label "$want") draws the game$([ "$want" = fork ] && echo ", the engine's own kept next to it")"
}

# --- My unix libraries: files of the engine's lib/wine/aarch64-unix that a build of mine replaces,
# each key with a setting of its own (mine|engine). One row each in unix_lib:
#   <setting>) LIB=<its main file> LIB_FILES=<the set's files> LIB_COMP=<its folder in components/>
# wine is ntdll.so alone. macdrv is my Mac driver's winemac.so and, when its build has one, my
# win32u.so: win32u.so calls into the driver, the two come from one tree, and a pair from two
# builds must never load together, so they switch as one set, both mine or both the engine's own. A
# build of my Mac driver without win32u.so (one before jdrly/wine#61, or one whose compare lists
# none of its functions) has winemac.so alone, and the engine's own win32u.so stays in place.
# Each engine's own file moves aside once, as <file>.engine, and only when its sha256 is the pin's
# (lib_pin); mine is copied in from the components. Every process of the bottle loads the same
# files, Steam's too, so they change only while no session runs or starts (apply_engine_files). A
# build of the app without my file (no components/<folder>) leaves the engine's own in place and
# greys the setting.
UNIX_LIBS="wine macdrv"
UNIX_DIR="$ENG/lib/wine/aarch64-unix"
# unix_lib <key> also sets LIB_SET, the set's files this app has a build of (LIB first), and
# LIB_NAME, what the log calls them ("winemac.so and win32u.so")
unix_lib() {
  case "$1" in
    wine) LIB=ntdll.so LIB_FILES=ntdll.so LIB_COMP="$COMP/ntdll" ;;
    macdrv) LIB=winemac.so LIB_FILES="winemac.so win32u.so" LIB_COMP="$COMP/macdrv" ;;
    *) return 1 ;;
  esac
  LIB_SET=$LIB
  [ "$1" != macdrv ] || [ ! -f "$LIB_COMP/win32u.so" ] || LIB_SET="$LIB win32u.so"
  LIB_NAME=${LIB_SET// / and }
}
# lib_pin <file>: the engine's own file's sha256
lib_pin() {
  case "$1" in
    ntdll.so) echo "$ENGINE_NTDLL_SHA256" ;;
    winemac.so) echo "$ENGINE_WINEMAC_SHA256" ;;
    win32u.so) echo "$ENGINE_WIN32U_SHA256" ;;
  esac
}
# lib_bundled <key>: this app carries my build of it
lib_bundled() { unix_lib "$1" && [ -f "$LIB_COMP/$LIB" ]; }
# lib_commit <key>: the commit of my build in this app (its VERSION's "commit:" line)
lib_commit() { unix_lib "$1"; sed -n 's/^commit: //p' "$LIB_COMP/VERSION" 2>/dev/null | head -1; }
# lib_one <file> <path>: what <path> is, for one file of the set unix_lib last named: mine (this
# app's build of <file>), engine (the engine's own, by the pin), other (another build of mine, from
# an earlier version of the app, or anything else), none
lib_one() {
  if [ ! -f "$2" ]; then echo none
  elif [ -f "$LIB_COMP/$1" ] && cmp -s "$LIB_COMP/$1" "$2"; then echo mine
  elif [ "$(sha256 "$2")" = "$(lib_pin "$1")" ]; then echo engine
  else echo other
  fi
}
# lib_target <file> <mine|engine>: what <file> is in that set: mine for a file of LIB_SET, the
# engine's own for the rest
lib_target() { if [ "$2" = mine ] && in_list "$1" "$LIB_SET"; then echo mine; else echo engine; fi; }
# lib_file <key>: the set in the engine: mine or engine when every file is, none when none is there
# (between the renames of a single file), other when its main file is another build of mine and
# the rest are that build's or the engine's own (an earlier version of the app), mix otherwise (a
# switch cut short, or my file next to the engine's own other half). A file this app has no build
# of counts only when it isn't the engine's own.
lib_file() {
  local f t first=yes m=yes e=yes n=yes o=yes
  unix_lib "$1"
  for f in $LIB_FILES; do
    t=$(lib_one "$f" "$UNIX_DIR/$f")
    [ "$t" = "$(lib_target "$f" mine)" ] || m=no
    [ "$t" = engine ] || e=no
    if [ "$t" != engine ] || in_list "$f" "$LIB_SET"; then [ "$t" = none ] || n=no; fi
    if [ -n "$first" ]; then [ "$t" = other ] || o=no; first=""
    elif [ "$t" != other ] && [ "$t" != engine ]; then o=no
    fi
  done
  if [ $e = yes ]; then echo engine
  elif [ $m = yes ]; then echo mine
  elif [ $n = yes ]; then echo none
  elif [ $o = yes ]; then echo other
  else echo mix
  fi
}
# lib_want <key>: the set the setting asks for (engine without my build in the app)
lib_want() { if lib_bundled "$1" && [ "$(setting "$1")" = mine ]; then echo mine; else echo engine; fi; }
# lib_in_use <key>: the set the next process loads (lib_file; without an engine, or between a
# single file's renames, the one it will be)
lib_in_use() {
  local f
  f=$(lib_file "$1")
  if [ "$f" = none ]; then lib_want "$1"; else echo "$f"; fi
}
# lib_commit_of <key> <mine|engine|other|mix|none>: that set's commit (mine: my build's; engine: the
# engine's Wine)
lib_commit_of() { case "$2" in mine) lib_commit "$1" ;; engine) echo "$ENGINE_WINE" ;; esac; }
# lib_release_of <key> <mine|engine|other|mix|none>: the Wine release my build is on (11.21 from the
# first line of its VERSION, git describe: wine-11.21-…-g<commit>); empty for the others
lib_release_of() {
  unix_lib "$1"
  [ "$2" != mine ] || head -1 "$LIB_COMP/VERSION" 2>/dev/null | grep -oE 'wine-[0-9]+(\.[0-9]+)+' | head -1 | cut -c6- || true
}
# lib_label <key> <mine|engine|mix|other>: what the window and the log call it
lib_label() {
  unix_lib "$1"
  case "$2" in
    mine) echo "my $LIB_NAME (jdrly/wine $(lib_commit "$1" | cut -c1-11))" ;;
    engine) echo "the engine's own $LIB_NAME (athei/wine $ENGINE_WINE)" ;;
    mix) echo "a mix of mine and the engine's own ${LIB_FILES// / and }" ;;
    *) echo "another $LIB" ;;
  esac
}
# lib_kept <key>: each of the engine's own files of the set is in place or next to it as
# <file>.engine
lib_kept() {
  local f
  unix_lib "$1"
  for f in $LIB_FILES; do
    [ "$(lib_one "$f" "$UNIX_DIR/$f")" = engine ] || [ "$(lib_one "$f" "$UNIX_DIR/$f.engine")" = engine ] || return 1
  done
}
# lib_state <key>: yes (the set the setting asks for is in place), switch (it is not, and the
# engine's own files are there to make it from: apply_engine_files puts it in at the next chance),
# other (one of the engine's own is nowhere: Repair unpacks the engine again), no (no engine)
lib_state() {
  [ -x "$ENG/bin/wine" ] || { echo no; return; }
  if [ "$(lib_file "$1")" = "$(lib_want "$1")" ]; then echo yes
  elif lib_kept "$1"; then echo switch
  else echo other
  fi
}
# lib_neither <key>: the warning for lib_state other
lib_neither() {
  unix_lib "$1"
  if [ "$LIB_SET" = "$LIB" ]; then echo "The engine's $LIB is neither its own nor mine. Click Repair."
  else echo "The engine's $LIB_NAME are neither its own nor mine. Click Repair."
  fi
}
# lib_switch <key>: the set the setting asks for into place (the caller has made sure that no
# session runs or starts). To mine: my files copied next to theirs (<file>.new) first, then, file by
# file, the engine's own aside as <file>.engine when it is the one in place, and mine in. To the
# engine's own: a rename a file. A file already right is left as it is, so the next switch finishes
# one cut short; until then the set is a mix, which Play never starts on.
lib_switch() {
  local want cur f p todo=""
  unix_lib "$1"
  want=$(lib_want "$1")
  cur=$(lib_file "$1")
  # (copies a switch to mine cut short left, whichever way this one goes)
  for f in $LIB_FILES; do [ ! -e "$UNIX_DIR/$f.new" ] || run rm -f "$UNIX_DIR/$f.new"; done
  [ "$cur" != "$want" ] || return 0
  if ! lib_kept "$1"; then
    # (lib_state says other: Play and set say Repair)
    log "$LIB_NAME: the engine's own isn't in place or next to it for each; $(lib_label "$1" "$want") waits for Repair"
    return 0
  fi
  [ "$cur" != mix ] || say "${LIB_FILES// / and }: $(lib_label "$1" mix) in the engine, a switch cut short; finishing the switch to $(lib_label "$1" "$want")"
  for f in $LIB_FILES; do [ "$(lib_one "$f" "$UNIX_DIR/$f")" = "$(lib_target "$f" "$want")" ] || todo="$todo $f"; done
  for f in $todo; do
    [ "$(lib_target "$f" "$want")" = mine ] || continue
    run cp -p "$LIB_COMP/$f" "$UNIX_DIR/$f.new"
    # (cp -p copies the quarantine attribute of an app copied out of a browser's download)
    [ -n "$DRY" ] || xattr -d com.apple.quarantine "$UNIX_DIR/$f.new" 2>/dev/null || true
  done
  for f in $todo; do
    p="$UNIX_DIR/$f"
    if [ "$(lib_target "$f" "$want")" = engine ]; then
      run mv -f "$p.engine" "$p"
    else
      [ "$(lib_one "$f" "$p")" != engine ] || run mv -f "$p" "$p.engine"
      run mv -f "$p.new" "$p"
    fi
  done
  if [ "$want" = engine ]; then say "$LIB_NAME: $(lib_label "$1" engine) $([ "$LIB_SET" = "$LIB" ] && echo is || echo are) in the engine"
  elif [ "$LIB_SET" = "$LIB" ]; then say "$LIB: $(lib_label "$1" mine) is in the engine, the engine's own kept next to it as $LIB.engine"
  else say "$LIB_NAME: $(lib_label "$1" mine) are in the engine, the engine's own kept next to each as <file>.engine"
  fi
}

# --- FEX: my build (components/fex, jdrly/FEX built for this engine) or the engine's own
#
# FEX runs the game's x86_64 code. Its ARM64EC half is three files of the engine that change
# together (FEX_FILES): aarch64-windows/xtajit64.dll, the name Wine loads for an x86_64 process,
# and libarm64ecfex.dll, the same file under FEX's own name, and aarch64-unix/libarm64ecfex.so,
# which the DLL loads by name and calls by index, so the two come from one build. My build has the
# DLL once (components/fex/aarch64-windows/libarm64ecfex.dll), and both names get it. Its WoW64
# half (xtajit.dll, Steam's i386 code) stays the engine's. The setting fex (mine|engine) starts at
# engine: my FEX goes in only after `set fex mine`. As for unix_lib's files, each engine's own
# file moves aside once as <file>.engine, and only when its sha256 is the pin's; mine is copied in
# from the components, only while no session runs or starts (apply_engine_files). The three can't
# change in one step: a switch copies all three of mine first ($f.new), then renames back to back.
# Cut short, it leaves a mix, which the next switch finishes and Play never starts on.
FEX_FILES="aarch64-windows/xtajit64.dll aarch64-windows/libarm64ecfex.dll aarch64-unix/libarm64ecfex.so"
FEX_COMP="$COMP/fex"
FEX_DIR="$ENG/lib/wine"
# fex_src <file>: my build's file for one of FEX_FILES
fex_src() { case "$1" in *.dll) echo "$FEX_COMP/aarch64-windows/libarm64ecfex.dll" ;; *) echo "$FEX_COMP/$1" ;; esac; }
# fex_pin <file>: the engine's own file's sha256
fex_pin() { case "$1" in *.dll) echo "$ENGINE_FEX_DLL_SHA256" ;; *) echo "$ENGINE_FEX_SO_SHA256" ;; esac; }
# fex_bundled: this app carries my FEX
fex_bundled() { [ -f "$FEX_COMP/aarch64-windows/libarm64ecfex.dll" ] && [ -f "$FEX_COMP/aarch64-unix/libarm64ecfex.so" ]; }
# fex_commit: the commit of my FEX in this app (its VERSION's "commit:" line)
fex_commit() { sed -n 's/^commit: //p' "$FEX_COMP/VERSION" 2>/dev/null | head -1; }
# fex_file <file> <path>: what <path> is, for one of FEX_FILES: mine (this app's build), engine (the
# engine's own, by the pin), other (another build of mine, from an earlier version of the app, or
# anything else), none
fex_file() {
  local src
  src=$(fex_src "$1")
  if [ ! -f "$2" ]; then echo none
  elif [ -f "$src" ] && cmp -s "$src" "$2"; then echo mine
  elif [ "$(sha256 "$2")" = "$(fex_pin "$1")" ]; then echo engine
  else echo other
  fi
}
# fex_prof_id: <build id>:<age>:<SizeOfImage> of my libarm64ecfex.dll, as its VERSION's line
# "libarm64ecfex.dll: build id <32 hex> age <n>, SizeOfImage <0x hex>" writes them, or nothing
fex_prof_id() {
  sed -n 's/^libarm64ecfex\.dll: build id \([0-9a-f]\{32\}\) age \([0-9]\{1,\}\), SizeOfImage \(0x[0-9a-f]\{1,\}\)$/\1:\2:\3/p' "$FEX_COMP/VERSION" 2>/dev/null | head -1
}
# fex_want: the FEX the setting asks for (engine without my build in the app)
fex_want() { if fex_bundled && [ "$(setting fex)" = mine ]; then echo mine; else echo engine; fi; }
# fex_in_place: the FEX in the engine: mine or engine when all three files are, other when one is
# neither (an earlier build of mine, or something else), mix otherwise (some mine, some the
# engine's own or missing: a switch cut short)
fex_in_place() {
  local f k all=""
  for f in $FEX_FILES; do
    k=$(fex_file "$f" "$FEX_DIR/$f")
    [ "$k" != other ] || { echo other; return; }
    [ -z "$all" ] || [ "$all" = "$k" ] || all=mix
    [ "$all" = mix ] || all=$k
  done
  case "$all" in mine|engine) echo "$all" ;; *) echo mix ;; esac
}
# fex_in_use: the FEX the next process loads (fex_in_place; without an engine, the one it will be)
fex_in_use() { if [ -x "$ENG/bin/wine" ]; then fex_in_place; else fex_want; fi; }
# fex_label <mine|engine|mix|other>: what the window and the log call it
fex_label() {
  case "$1" in
    mine) echo "my FEX (jdrly/FEX $(fex_commit | cut -c1-11))" ;;
    engine) echo "the engine's own FEX (athei/FEX $ENGINE_FEX)" ;;
    mix) echo "a mix of my FEX and the engine's own" ;;
    *) echo "another FEX" ;;
  esac
}
# fex_kept: each of the engine's own three files is in place or next to it as <file>.engine
fex_kept() {
  local f
  for f in $FEX_FILES; do
    [ "$(fex_file "$f" "$FEX_DIR/$f")" = engine ] || [ "$(fex_file "$f" "$FEX_DIR/$f.engine")" = engine ] || return 1
  done
}
# fex_state: yes (the FEX the setting asks for is in place, all three files), switch (it is not, and
# the engine's own files are there to make it from: apply_engine_files puts it in at the next
# chance), other (the engine's own is missing: Repair unpacks the engine again), no (no engine)
fex_state() {
  [ -x "$ENG/bin/wine" ] || { echo no; return; }
  if [ "$(fex_in_place)" = "$(fex_want)" ]; then echo yes
  elif fex_kept; then echo switch
  else echo other
  fi
}
# fex_switch: the FEX the setting asks for into place (the caller has made sure that no session
# runs or starts). To mine: my three files copied next to theirs ($f.new) first, then, file by
# file, the engine's own aside as $f.engine when it is the one in place, and mine in. To the
# engine's own: three renames. A file already right is left as it is, so the next switch finishes
# one cut short.
fex_switch() {
  local want cur f p todo=""
  want=$(fex_want)
  cur=$(fex_in_place)
  # (copies a switch to mine cut short left, whichever way this one goes)
  for f in $FEX_FILES; do [ ! -e "$FEX_DIR/$f.new" ] || run rm -f "$FEX_DIR/$f.new"; done
  [ "$cur" != "$want" ] || return 0
  if ! fex_kept; then
    # (fex_state says other: Play and set say Repair)
    log "FEX: the engine's own files are neither in place nor next to them; $(fex_label "$want") waits for Repair"
    return 0
  fi
  [ "$cur" != mix ] || say "FEX: the engine's FEX files are $(fex_label mix), a switch cut short; finishing the switch to $(fex_label "$want")"
  for f in $FEX_FILES; do [ "$(fex_file "$f" "$FEX_DIR/$f")" = "$want" ] || todo="$todo $f"; done
  if [ "$want" = engine ]; then
    for f in $todo; do run mv -f "$FEX_DIR/$f.engine" "$FEX_DIR/$f"; done
    say "FEX: $(fex_label engine) is in the engine"
    return 0
  fi
  for f in $todo; do
    p="$FEX_DIR/$f"
    run cp -p "$(fex_src "$f")" "$p.new"
    # (cp -p copies the quarantine attribute of an app copied out of a browser's download)
    [ -n "$DRY" ] || xattr -d com.apple.quarantine "$p.new" 2>/dev/null || true
  done
  for f in $todo; do
    p="$FEX_DIR/$f"
    [ "$(fex_file "$f" "$p")" != engine ] || run mv -f "$p" "$p.engine"
    run mv -f "$p.new" "$p"
  done
  say "FEX: $(fex_label mine) is in the engine, the engine's own kept next to each of its three files as <file>.engine"
}

# apply_engine_files: dxmt_switch, lib_switch for each of UNIX_LIBS and fex_switch while no session
# runs or starts (the session's lock, as apply_registry takes it), else at the next game start that
# finds none (Play). Nothing while engine_refusal says why not: the engine's files stay as they are.
apply_engine_files() {
  local k why
  if [ ! -x "$ENG/bin/wine" ]; then
    if [ -n "$DRY" ]; then
      echo "[dry-run] $(dxmt_label "$(setting dxmt)") as the engine's DXMT tree"
      for k in $UNIX_LIBS; do echo "[dry-run] $(lib_label "$k" "$(lib_want "$k")") in the engine"; done
      echo "[dry-run] $(fex_label "$(fex_want)") in the engine"
    fi
    return 0
  fi
  why=$(engine_refusal)
  if [ -n "$why" ]; then
    warn "$why"
    return 0
  fi
  if ! registry_lock; then
    log "The engine's DXMT tree, unix libraries and FEX wait for the next start without a running session (its lock is held, or its helper missing)"
    return 0
  fi
  if session_running; then
    registry_unlock
    log "The engine's DXMT tree, unix libraries and FEX wait for the next start without a running session"
    return 0
  fi
  dxmt_switch
  for k in $UNIX_LIBS; do lib_switch "$k"; done
  fex_switch
  registry_unlock
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
# app writes nothing into it afterwards but its DXMT tree and its unix libraries of mine
# (apply_engine_files), and nothing at all inside wine.app.
install_engine() {
  local dst="$ENG"
  if engine_ok && [ "${1:-}" != force ]; then
    say "The Wine engine ($ENGINE_TITLE) is already in place"
    return
  fi
  if engine_old; then
    say "The engine here is $(engine_label "$(cat "$ENG/.gw2om-source" 2>/dev/null || true)"); $ENGINE_TITLE replaces it"
    DIE_NOTE="The engine here, $(engine_label "$(cat "$ENG/.gw2om-source" 2>/dev/null || true)"), stays in place. Click Repair to try again."
  fi
  fetch "$ENGINE_URL" "$ENGINE_SHA256" "$ENGINE_SIZE" "Wine engine" "$ENGINE_API_URL"
  say "Unpacking the Wine engine ($ENGINE_TITLE)"
  safe_rm "$dst.new"
  run mkdir -p "$dst.new"
  run tar -xJf "$FETCHED" -C "$dst.new" --strip-components 1 || die "The Wine engine could not be unpacked (the log shows tar's error)."
  if [ -z "$DRY" ]; then
    # An archive downloaded in a browser carries the quarantine attribute and tar copies it onto
    # every file: the loader is notarized and would pass, the engine's ad hoc signed libraries not
    run xattr -dr com.apple.quarantine "$dst.new"
    # its SDK (headers, link libraries, Wine's conformance tests, man pages) is not needed to run it
    safe_rm --quiet "$dst.new/include" "$dst.new/lib/wine/tests" "$dst.new/lib/wine/x86_64-windows" "$dst.new/share/man"
    if [ "$ENGINE_CHECKS" = 1 ]; then
      engine_matches "$dst.new" || die "The unpacked Wine engine does not match the expected build."
    fi
    echo "$ENGINE_SHA256" >"$dst.new/.gw2om-source"
  fi
  safe_rm "$dst"
  run mv "$dst.new" "$dst"
  DIE_NOTE=""
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
    # (install copies the quarantine attribute too, as cp -p does in dxmt_switch)
    if [ -z "$DRY" ] && xattr "$dll" | grep -qx com.apple.quarantine; then run xattr -d com.apple.quarantine "$dll"; fi
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
# it counts too, and at the chain path (below). Its settings (addons/arcdps/) stay when it goes.
# Another file at those places (Nexus, a ReShade the app didn't place...) is never touched: state
# foreign.
ARCDPS_URL=https://www.deltaconnected.com/arcdps/x64
[ -z "$ROOT" ] || ARCDPS_URL="${GW2_ON_MAC_ARCDPS_URL:-$ARCDPS_URL}"
ARC_CHAIN=addons/arcdps/chain/d3d11.dll
ARCDPS_DLLS="d3d11.dll dxgi.dll $ARC_CHAIN"
# chain_ok [<game folder>]: ARC_CHAIN's folders are real folders. Through a link (an addons folder
# shared with another install, which the import keeps as a link) the app neither counts arcdps
# there nor puts, moves or removes a file there: the file would be the other folder's.
chain_ok() { local d="${1:-$GAME_DIR}"; [ ! -L "$d/addons" ] && [ ! -L "$d/addons/arcdps" ] && [ ! -L "$d/addons/arcdps/chain" ]; }
# arcdps and the app's ReShade in one game folder. ADDONS_LAYOUT=together (addon_dll): alone, each
# is d3d11.dll; with both in, ReShade is d3d11.dll and arcdps is ARC_CHAIN, which ReShade loads
# itself through the [PROXY] keys of the ReShade folder's ReShade.ini (proxy_sync). Next to
# ReShade, arcdps as dxgi.dll didn't load in my sessions (#205, #208), so an arcdps that 0.1.4's
# development builds left as dxgi.dll moves to ARC_CHAIN too. ADDONS_LAYOUT=exclusive: each counts the other as a file in its
# way, and its switch refuses until the other is off.
ADDONS_LAYOUT=together
[ -z "$ROOT" ] || ADDONS_LAYOUT="${GW2_ON_MAC_ADDONS_LAYOUT:-$ADDONS_LAYOUT}"
PROXY_ON=0
# addon_dll <arcdps|reshade> <the other one in: on|off>: the addon's path in the game folder
addon_dll() { case "$1 $2 $ADDONS_LAYOUT" in "arcdps on together") echo "$ARC_CHAIN" ;; *) echo d3d11.dll ;; esac; }
# our_reshade <file>: the app's ReShade (the pinned file)
our_reshade() { [ -f "$1" ] && [ "$(sha256 "$1")" = "$RESHADE_DLL_SHA256" ]; }

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
# another program's d3d11.dll or dxgi.dll, ARC_FOREIGN its names, the app's ReShade too in the
# exclusive layout; nogame), ARC_DLL (arcdps's files)
arcdps_state() {
  local n
  ARC=off ARC_FOREIGN="" ARC_DLL=""
  game_state
  [ -n "$GAME_DIR" ] || { ARC=nogame; return 0; }
  for n in $ARCDPS_DLLS; do
    [ -f "$GAME_DIR/$n" ] || continue
    [ "$n" != "$ARC_CHAIN" ] || chain_ok || continue
    if is_arcdps "$GAME_DIR/$n"; then ARC=on ARC_DLL=${ARC_DLL:+$ARC_DLL }$n
    elif [ "$ADDONS_LAYOUT" = together ] && [ "$n" != "$ARC_CHAIN" ] && our_reshade "$GAME_DIR/$n"; then :
    else ARC_FOREIGN=${ARC_FOREIGN:+$ARC_FOREIGN }$n
    fi
  done
  [ "$ARC" = on ] || [ -z "$ARC_FOREIGN" ] || ARC=foreign
  return 0
}

# arcdps_move <from> <to>: arcdps renamed in the game folder, checked first (the file is arcdps,
# <to> is free; else nothing changes, status 1). One rename, so arcdps is under one name or the
# other whenever the script stops. ARC_MOVED: the new name.
arcdps_move() {
  local from="$GAME_DIR/$1" to="$GAME_DIR/$2"
  case " $1 $2 " in *" $ARC_CHAIN "*) chain_ok || { log "arcdps: not renamed from $1 to $2 (a folder of $ARC_CHAIN is a link)"; return 1; } ;; esac
  if ! is_arcdps "$from" || [ -e "$to" ] || [ -L "$to" ]; then
    log "arcdps: not renamed from $1 to $2 (not arcdps, or $2 is taken)"
    return 1
  fi
  [ -d "$(dirname "$to")" ] || run mkdir -p "$(dirname "$to")" || return 1
  run mv -n "$from" "$to" || return 1
  if [ -z "$DRY" ] && { [ -e "$from" ] || ! is_arcdps "$to"; }; then
    log "arcdps: the rename from $1 to $2 didn't happen"
    return 1
  fi
  ARC_MOVED=$2
  log "arcdps: $1 renamed to $2"
}

# arcdps_tidy <ReShade in: on|off>: arcdps under the name addon_dll gives (the caller holds the
# session's lock, and no session runs). arcdps updates itself and may write a new d3d11.dll while
# ReShade loads it from ARC_CHAIN: under two or three names, the newest file stays and the others
# go (all are arcdps; the name addon_dll gives wins a tie). A name that is taken leaves arcdps where
# it is. ARC_MOVED: the name arcdps was renamed to, if any.
arcdps_tidy() {
  local want newer n
  ARC_MOVED=""
  arcdps_state
  [ "$ARC" = on ] || return 0
  want=$(addon_dll arcdps "$1")
  case "$ARC_DLL" in
    *" "*)
      case " $ARC_DLL " in *" $want "*) newer=$want ;; *) newer=${ARC_DLL%% *} ;; esac
      for n in $ARC_DLL; do [ ! "$GAME_DIR/$n" -nt "$GAME_DIR/$newer" ] || newer=$n; done
      log "arcdps: in the game folder as ${ARC_DLL// / and } (it updated itself); keeping the newer $newer (sha256 $(sha256 "$GAME_DIR/$newer"))"
      for n in $ARC_DLL; do
        [ "$n" = "$newer" ] || { log "arcdps: removing $n (sha256 $(sha256 "$GAME_DIR/$n"))"; run rm -f "$GAME_DIR/$n"; }
      done
      ARC_DLL=$newer ;;
  esac
  [ "$ARC_DLL" = "$want" ] || arcdps_move "$ARC_DLL" "$want" || true
}

# proxy_sync [off]: ReShade's [PROXY] keys in the ReShade folder's ReShade.ini (ReShade reads them
# from its own ini at its start, source/dll_main.cpp at v6.8.0), on exactly when the app's ReShade
# is d3d11.dll and arcdps is ARC_CHAIN in the together layout: EnableProxyLibrary=1 and
# ProxyLibrary=ARC_CHAIN's Windows path, so ReShade loads arcdps in place of system32's d3d11.dll.
# Else EnableProxyLibrary=0 where the file has the key (with off: always, before a step takes
# either file away). The keys on with no arcdps there would leave the game without Direct3D 11, so
# the files go in before the keys go on, and the keys go off before a file goes. Only those keys
# change (ini_set); the caller holds the session's lock. PROXY_ON: 1 when on. Status 1 when the
# ini can't be written.
proxy_sync() {
  local want=0 ini="$RS/ReShade.ini"
  if [ "${1:-}" != off ] && [ "$ADDONS_LAYOUT" = together ] && our_reshade "$GAME_DIR/d3d11.dll" &&
    chain_ok && is_arcdps "$GAME_DIR/$ARC_CHAIN"; then want=1; fi
  PROXY_ON=0
  if [ "$want" = 1 ]; then
    rs_safe "$ini" || return 1
    reshade_folder
    set -- EnableProxyLibrary=1 "ProxyLibrary=$(proxy_path)"
  else
    [ -f "$ini" ] && grep -q EnableProxyLibrary "$ini" || return 0
    rs_safe "$ini" || return 1
    set -- EnableProxyLibrary=0
  fi
  if [ ! -f "$ini" ]; then
    [ -n "$DRY" ] || return 1
    echo "[dry-run] $* in $ini"
  elif ! ini_set "$ini" PROXY "$@" | cmp -s - "$ini"; then
    ini_set "$ini" PROXY "$@" | put "$ini" 644 || return 1
    log "ReShade.ini: [PROXY] $*"
  fi
  PROXY_ON=$want
}
# proxy_path: ARC_CHAIN as the game sees it (C:\ in the bottle, else Z:\; a comma doubled, as
# ReShade's ini reads it)
proxy_path() {
  case "$GAME_DIR" in
    "$BOTTLE/drive_c/"*) printf 'C:\\%s' "${GAME_DIR#"$BOTTLE/drive_c/"}/$ARC_CHAIN" | tr '/' '\\' | sed 's/,/,,/g' ;;
    *) winpath "$GAME_DIR/$ARC_CHAIN" ;;
  esac
}
# proxy_enabled <ini>: [PROXY] EnableProxyLibrary is on in it, as ReShade 6.8.0 reads it
# (source/ini_file.cpp, ini_file.hpp): a repeated key appends its values and ReShade takes the
# first, a value splits at a single comma, an empty value adds nothing, and a bool is on when
# strtol gives a number other than 0 or the value is true, True or TRUE
proxy_enabled() {
  LC_ALL=C awk '
    function strip(s, c) {
      while (s != "" && index(c, substr(s, 1, 1))) s = substr(s, 2)
      while (s != "" && index(c, substr(s, length(s), 1))) s = substr(s, 1, length(s) - 1)
      return s }
    { t = strip($0, " \t\r"); if (NR == 1 && substr(t, 1, 3) == "\357\273\277") t = substr(t, 4)
      if (substr(t, 1, 1) == "[") { i = index(t, "]"); sec = strip(i ? substr(t, 1, i - 1) : t, " \t[]"); next }
      i = index(t, "=")
      if (found || sec != "PROXY" || !i || strip(substr(t, 1, i - 1), " \t") != "EnableProxyLibrary") next
      v = strip(substr(t, i + 1), " \t")
      if (v == "") next
      j = index(v, ","); if (j) v = substr(v, 1, j - 1)
      found = 1 }
    END {
      on = v == "true" || v == "True" || v == "TRUE"
      if (!on && match(v, /^[+-]?[0-9]+/)) { d = substr(v, 1, RLENGTH); gsub(/[^0-9]/, "", d); on = d ~ /[1-9]/ }
      exit !on }' "$1"
}
# proxy_safe: ReShade won't look for arcdps where it isn't: the app's ReShade isn't d3d11.dll, or its
# keys are off, or they are on with arcdps at their path. Only reads; Play checks it before the
# start, since a game whose ReShade loads a missing file has no Direct3D 11.
proxy_safe() {
  local ini="$RS/ReShade.ini"
  our_reshade "$GAME_DIR/d3d11.dll" && [ -f "$ini" ] && proxy_enabled "$ini" || return 0
  chain_ok && is_arcdps "$GAME_DIR/$ARC_CHAIN" && ini_set "$ini" PROXY EnableProxyLibrary=1 "ProxyLibrary=$(proxy_path)" | cmp -s - "$ini"
}
# proxy_refusal <what stays>: the sentence for an ini that can't be written
proxy_refusal() { echo "$APP_NAME couldn't change ReShade's settings ($RS/ReShade.ini), so $1. Try again (details in $LOGS/install.log)."; }

# sync_arcdps: arcdps under the name addon_dll gives, and ReShade's [PROXY] keys to match the files
# (proxy_sync), before Play, at Install and at Repair; never while a session runs or starts. Keys
# that stay on with no arcdps at their path stop the start.
sync_arcdps() {
  [ -n "$DRY" ] || [ -x "$LOCKER" ] || return 0
  registry_lock || return 0
  if session_running; then registry_unlock; return 0; fi
  reshade_state
  arcdps_tidy "$([ "$RSH" = on ] && echo on || echo off)"
  if ! proxy_sync; then
    proxy_safe || die "$(proxy_refusal "ReShade would look for arcdps where it isn't, and the game would have no Direct3D 11")"
    warn "$(proxy_refusal "ReShade doesn't load arcdps this time")"
  fi
  registry_unlock
}

# set arcdps on|off (cmd_set): only while no session runs or starts (the session's lock, as the
# registry writes take it)
set_arcdps() {
  local dir="$CACHE/downloads/arcdps" sum want got n tmp gone=""

  arcdps_state
  [ "$ARC" != nogame ] || die "Guild Wars 2 is not installed yet: arcdps goes into its folder once it is."
  ! session_running || die "Quit Guild Wars 2 and Steam first: arcdps goes into or out of the game folder only while they are closed."
  registry_lock || die "A game session is starting. Try again once Guild Wars 2 and Steam have quit."
  if [ "$1" = off ]; then
    # (ReShade's keys off first: they never point at a file that is gone)
    proxy_sync off || die "$(proxy_refusal "arcdps stays in")"
    for n in $ARCDPS_DLLS; do
      [ "$n" != "$ARC_CHAIN" ] || chain_ok || continue
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
    on)
      proxy_sync || die "$(proxy_refusal "ReShade doesn't load arcdps")"
      registry_unlock; echo "@done arcdps is already in the game folder ($ARC_DLL)."; return 0 ;;
    foreign)
      reshade_state
      case "$RSH" in
        on) [ "$ADDONS_LAYOUT" != exclusive ] || die "ReShade is in the game folder as $RSH_DLL. Turn ReShade off first, then turn arcdps on." ;;
        foreign) die "The game folder has a ReShade that $APP_NAME didn't put there ($RSH_DLL). $APP_NAME leaves it alone, so it can't add arcdps: remove that file first." ;;
      esac
      die "The game folder has another $ARC_FOREIGN (Nexus or another addon?). $APP_NAME leaves it alone, so it can't add arcdps: remove that file, or add arcdps through that addon." ;;
  esac
  # (its place: ARC_CHAIN next to the app's ReShade in the together layout)
  reshade_state
  n=$(addon_dll arcdps "$([ "$RSH" = on ] && echo on || echo off)")
  [ "$n" != "$ARC_CHAIN" ] || chain_ok ||
    die "Next to ReShade, arcdps goes into addons/arcdps/chain in the game folder, and a folder on that path is a link to another folder. $APP_NAME doesn't put files there: make addons/arcdps a folder of its own, then try again."
  tmp="$GAME_DIR/$(dirname "$n")/.$(basename "$n").gw2om-new"
  if [ -n "$DRY" ]; then
    echo "[dry-run] download $ARCDPS_URL/d3d11.dll, check it against $ARCDPS_URL/d3d11.dll.md5sum, put it into $GAME_DIR/$n"
    echo "@done arcdps would be in the game folder."
    return 0
  fi
  trap 'safe_rm --quiet "$CACHE/downloads/arcdps" || true; unlock' EXIT
  step "Downloading arcdps from deltaconnected.com"
  safe_rm --quiet "$dir" && mkdir -p "$dir"
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
  [ "$ARC" = off ] && [ ! -e "$GAME_DIR/$n" ] && [ ! -L "$GAME_DIR/$n" ] && { [ "$n" != "$ARC_CHAIN" ] || chain_ok; } ||
    die "The game folder changed during the download ($ARC). Try again."
  [ -d "$(dirname "$tmp")" ] || run mkdir -p "$(dirname "$tmp")"
  run install -m 644 "$dir/d3d11.dll" "$tmp"
  run mv -f "$tmp" "$GAME_DIR/$n"
  log "arcdps: $ARCDPS_URL/d3d11.dll into $GAME_DIR/$n (md5 $got, sha256 $(sha256 "$GAME_DIR/$n"))"
  # (the file is in: now ReShade's keys; if they can't go on, arcdps goes out again)
  if ! proxy_sync; then
    run rm -f "$GAME_DIR/$n"
    die "$(proxy_refusal "arcdps stays out")"
  fi
  registry_unlock
  echo "@done arcdps is in the game folder ($n from deltaconnected.com). It loads the next time the game starts, and from then on it updates itself.$([ "$PROXY_ON" = 0 ] || echo " ReShade loads arcdps itself now, so both load.")"
}

# --- ReShade (crosire's post-processing; Settings › Interface): downloaded on request, never hosted
# or changed by the app. Three files go into the game folder: ReShade64.dll as d3d11.dll, where
# it loads first (the d3d11/dxgi order, rules_text) and passes the game's Direct3D 11 on to
# DXMT; Microsoft's d3dcompiler_47.dll, because Wine's own compiler can't compile ReShade's effects
# (under Wine ReShade loads it by name, so the game folder's copy wins with the native-first
# override, rules_text); and a ReShade.ini with only [INSTALL] BasePath, which ReShade reads
# next to the game's exe before anything else (get_base_path, source/dll_main.cpp at v6.8.0). It
# points at the ReShade folder in the app's folder, so ReShade's own ini, log, presets, shaders,
# textures and screenshots live outside the bottle: a new bottle, Repair or Steam's file check
# costs the player nothing, and Uninstall leaves them. One pinned version per app release: the
# ReShade in the game folder is the app's when it is that exact file, and any other DLL exporting
# ReShadeRegisterAddon is a ReShade the app didn't place (foreign), never touched.
RESHADE_VERSION=6.8.0
RESHADE_URL=https://reshade.me/downloads/ReShade_Setup_6.8.0.exe
RESHADE_SIZE=4075064
RESHADE_SHA256=207aea16205fbf952bc8fe1879966672454cf04002e7ad34237c7990a5b3c0b4
RESHADE_DLL_SHA256=b2945c29e7095491a901746b400e58db9b1592ab092bacf2a888ce37f02d08da
# Microsoft's compiler (10.0.17134.12, Microsoft-signed), when the game has no copy in bin64/cef
COMPILER_URL=https://raw.githubusercontent.com/mozilla/fxc2/9aba9b11079303d5577e0e3eb455f4d00f3b5946/dll/d3dcompiler_47.dll
COMPILER_SIZE=4346120
COMPILER_SHA256=4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3
# The two packs ReShade's installer picks by default, at fixed commits: crosire's standard effects
# (the slim branch: ReShade.fxh and ReShadeUI.fxh, which almost every effect includes) and SweetFX
RESHADE_SHADERS_URL=https://github.com/crosire/reshade-shaders/archive/fd0022170615ce0d8162d219bff07232fa6dd84f.zip
SWEETFX_URL=https://github.com/CeeJayDK/SweetFX/archive/93ddf39b357f5da534ed6d34ba4ec8cc7dcfa361.zip
PACK_DOWNLOAD_MAX=$((64 * 1048576))
PACK_LIMIT=$((256 * 1048576))
PACK_MAX_FILES=10000
if [ -n "$ROOT" ]; then
  RESHADE_URL="${GW2_ON_MAC_RESHADE_URL:-$RESHADE_URL}" RESHADE_SIZE="${GW2_ON_MAC_RESHADE_SIZE:-$RESHADE_SIZE}"
  RESHADE_SHA256="${GW2_ON_MAC_RESHADE_SHA256:-$RESHADE_SHA256}" RESHADE_DLL_SHA256="${GW2_ON_MAC_RESHADE_DLL_SHA256:-$RESHADE_DLL_SHA256}"
  COMPILER_URL="${GW2_ON_MAC_COMPILER_URL:-$COMPILER_URL}" COMPILER_SIZE="${GW2_ON_MAC_COMPILER_SIZE:-$COMPILER_SIZE}"
  COMPILER_SHA256="${GW2_ON_MAC_COMPILER_SHA256:-$COMPILER_SHA256}"
  RESHADE_SHADERS_URL="${GW2_ON_MAC_RESHADE_SHADERS_URL:-$RESHADE_SHADERS_URL}" SWEETFX_URL="${GW2_ON_MAC_SWEETFX_URL:-$SWEETFX_URL}"
  PACK_LIMIT="${GW2_ON_MAC_PACK_LIMIT:-$PACK_LIMIT}" PACK_MAX_FILES="${GW2_ON_MAC_PACK_MAX_FILES:-$PACK_MAX_FILES}"
fi
RS="$APPDIR/ReShade"                  # ReShade's folder (its BasePath)
RS_CACHE="$CACHE/reshade"             # its compiled effects (IntermediateCachePath)
RS_DOWNLOADS="$CACHE/downloads/reshade"   # the checked ReShade64.dll (and fxc2's compiler) for Play and Repair
RS_PACKS="$RS/.packs"                 # "SweetFX" once an On has brought it: not again after a player deleted it
# the sha256 of the d3dcompiler_47.dll the app put next to Gw2-64.exe (Off removes only that one)
RS_COMPILER_RECORD="$APPDIR/reshade-compiler"

pe_has_export() {   # <file> <name>
  local nl='
'
  case "$nl$(pe_export_names "$1")$nl" in *"$nl$2$nl"*) return 0 ;; esac
  return 1
}
pe_is64() {   # <file>: an x86_64 PE (PE32+)
  local pe
  [ "$(head -c 2 "$1" 2>/dev/null || true)" = MZ ] || return 1
  pe=$(pe32 "$1" 60)
  [ "$(bytes "$1" "${pe:-0}" 4 | od -An -tx1 | tr -d ' \n' || true)" = 50450000 ] &&
    [ "$(pe16 "$1" $((pe + 4)))" = 34404 ] && [ "$(pe16 "$1" $((pe + 24)))" = 523 ]
}
is_reshade() { [ -f "$1" ] && pe_has_export "$1" ReShadeRegisterAddon; }
# winpath <path>: the path as Wine sees it through Z: (a comma doubled, as ReShade's ini reads it)
winpath() { printf 'Z:%s' "$1" | tr '/' '\\' | sed 's/,/,,/g'; }
reshade_game_ini() { printf '[INSTALL]\nBasePath=%s\n' "$(winpath "$RS")"; }
# the game folder's ReShade.ini is the app's: the two lines it writes and nothing else
our_game_ini() {
  awk 'NR == 1 && $0 == "[INSTALL]" { a = 1 } NR == 2 && /^BasePath=/ { b = 1 } END { exit !(a && b && NR == 2) }' "$GAME_DIR/ReShade.ini" 2>/dev/null
}

# reshade_state: RSH (on: the app's ReShade is in the game folder, as d3d11.dll or dxgi.dll;
# foreign: another ReShade is; blocked: another program's d3d11.dll or dxgi.dll is in the way, arcdps
# too in the exclusive layout; off; nogame), RSH_DLL (the ReShade's file), RSH_BLOCKER (the other
# files' names)
reshade_state() {
  local n foreign=""
  RSH=off RSH_DLL="" RSH_BLOCKER=""
  game_state
  [ -n "$GAME_DIR" ] || { RSH=nogame; return 0; }
  for n in $ARCDPS_DLLS; do
    [ -f "$GAME_DIR/$n" ] || continue
    if [ "$n" != "$ARC_CHAIN" ] && our_reshade "$GAME_DIR/$n"; then RSH_DLL=${RSH_DLL:+$RSH_DLL }$n
    elif [ "$n" != "$ARC_CHAIN" ] && is_reshade "$GAME_DIR/$n"; then foreign=${foreign:+$foreign }$n
    elif [ "$ADDONS_LAYOUT" = together ] && is_arcdps "$GAME_DIR/$n"; then :
    else RSH_BLOCKER=${RSH_BLOCKER:+$RSH_BLOCKER }$n
    fi
  done
  if [ -n "$RSH_DLL" ]; then RSH=on
  elif [ -n "$foreign" ]; then RSH=foreign RSH_DLL=$foreign
  elif [ -n "$RSH_BLOCKER" ]; then RSH=blocked
  fi
  return 0
}
# reshade_refusal: why ReShade can't go in (foreign, blocked)
reshade_refusal() {
  case "$RSH" in
    foreign) echo "The game folder has a ReShade that $APP_NAME didn't put there ($RSH_DLL). $APP_NAME leaves it alone: remove that file to turn ReShade on here." ;;
    blocked)
      arcdps_state
      if [ "$ADDONS_LAYOUT" = exclusive ] && [ "$ARC" = on ]; then
        echo "arcdps is in the game folder as $ARC_DLL. Turn arcdps off first, then turn ReShade on."
      else
        echo "The game folder has another ${RSH_BLOCKER// / and } (Nexus or another addon?). $APP_NAME leaves it alone, so it can't add ReShade: remove that file first."
      fi ;;
  esac
}
reshade_lines() {   # (status, settings)
  reshade_state
  echo "reshade_state=$RSH"
  echo "reshade_version=$RESHADE_VERSION"
  echo "reshade_dll=$RSH_DLL"
  echo "reshade_blocker=$RSH_BLOCKER"
  echo "reshade_folder=$RS"
  echo "addons_layout=$ADDONS_LAYOUT"
}

# check_download <file> <label> <magic, hex> [<size> <sha256>]: a download is the file: not a web
# page or something else, and a pinned one is that exact file (else it is removed and the player
# told what failed)
check_download() {
  local f=$1 label=$2 magic=$3 size=${4:-} sha=${5:-} got start actual
  got=$(stat -f %z "$f")
  if [ "$(head -c $((${#magic} / 2)) "$f" | od -An -tx1 | tr -d ' \n')" != "$magic" ]; then
    start=$(head -c 200 "$f" | LC_ALL=C tr -c '[:print:]' ' ' | tr -s ' ')
    log "not the file: $got bytes starting with: $start"
    rm -f "$f"
    case "$start" in
      *[Hh][Tt][Mm][Ll]*|*'<?xml'*) die "The download of $label brought a web page instead of the file. A captive portal (hotel or public Wi-Fi), a proxy, a VPN or a content filter is in the way: log in to the network or turn it off, then try again." ;;
    esac
    die "The download of $label brought something else than the file. A proxy, VPN or content filter may be in the way. Try again."
  fi
  [ -n "$sha" ] || return 0
  actual=$(sha256 "$f")
  if [ "$got" != "$size" ] || [ "$actual" != "$sha" ]; then
    log "not the expected file: $got bytes (expected $size), sha256 $actual (expected $sha)"
    rm -f "$f"
    die "The download of $label is not the file $APP_NAME expects: $(thousands "$got") bytes with a sha256 starting ${actual:0:12}, instead of $(thousands "$size") bytes starting ${sha:0:12}. Something on the way changes it (a proxy, VPN, antivirus or content filter). Try again."
  fi
}

# unpack_pack <zip or folder> <pack> <into> [import]: a pack of ReShade effects into
# <into>/Shaders/<pack>/ and <into>/Textures/<pack>/, which must not exist yet (a staging folder of
# the caller's, moved into the ReShade folder afterwards): the contents of each folder named Shaders
# or Textures in it, at any depth, which is the layout of every pack on ReShade's list. Only regular
# files, and of those only .fx and .fxh from Shaders and images from Textures; at most PACK_LIMIT
# bytes, from a pack of at most PACK_MAX_FILES files. A path that climbs out (..), an absolute path
# or a link in a zip refuses the whole pack (what was written by then stays in <into>). Nothing is
# extracted by its own path: each file is read on its own (unzip -p) into a path made here.
# With import (reshade import), also the files outside those folders: .fx and .fxh into
# Shaders/<pack>/ and images into Textures/<pack>/ by their names, every .ini into <into>/Presets/
# by its name (for the caller to check), and no refusal of a pack without effects.
# PACK_FILES, PACK_IMAGES, PACK_PRESETS: the effect files, images and .ini files unpacked.
unpack_pack() {
  local src=$1 pack=$2 into=$3 mode=${4:-} list plan line kind rel name dest n rc left tab nl
  tab=$(printf '\t') nl='
'
  case "$pack" in ""|.*|*[!A-Za-z0-9._\ -]*) die "\"$pack\" can't be the name of a pack of effects: use letters, digits, spaces, dots, dashes and underscores." ;; esac
  # (made here, so no link in them leads elsewhere)
  for n in Shaders Textures; do
    [ ! -e "$into/$n/$pack" ] && [ ! -L "$into/$n/$pack" ] || die "$APP_NAME unpacks $pack only into a new folder, and $into/$n/$pack is there already."
  done
  # "<kind> <bytes> <path>" lines (kind f: a file, d: a folder, l: a link; "+" alone: more than
  # PACK_MAX_FILES files)
  if [ -d "$src" ] && [ ! -L "$src" ]; then
    # (find doesn't follow links, so a linked folder's files aren't in it; a name with a line break
    # would break the lines. Unreadable folders are left out.)
    list=$(cd "$src" && find . -type f ! -path "*$nl*" 2>>"$LOGFILE" |
      LC_ALL=C awk -v max="$PACK_MAX_FILES" 'NR > max { print "+"; exit } { sub(/^\.\//, ""); print "f 0 " $0 }') || true
  else
    n=$(unzip -Zt "$src" 2>>"$LOGFILE" | sed -n 's/^\([0-9][0-9]*\) files*,.*/\1/p') || true
    [ -n "$n" ] || die "$pack is not a zip archive $APP_NAME can read. Try again."
    if [ "$n" -gt "$PACK_MAX_FILES" ]; then list="+"
    else
      list=$(unzip -Z "$src" 2>>"$LOGFILE" | LC_ALL=C awk '$2 ~ /^[0-9]+\.[0-9]+$/ && NF >= 9 {
          name = $0; sub(/^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ /, "", name)
          k = substr($1, 1, 1)
          print (k == "l" ? "l" : (k == "d" || name ~ /\/$/) ? "d" : "f"), $4, name }') ||
        die "$pack is not a zip archive $APP_NAME can read. Try again."
    fi
  fi
  # what goes where: "<S|T|P> <bytes> <path in the pack's folder><tab><path>", after a "= <bytes>"
  # line; "x"/"l" and the path alone, or "+", for a refusal
  plan=$(printf '%s\n' "$list" | LC_ALL=C awk -v imp="$mode" '
    { k = $1; name = $0; sub(/^[^ ]+ [^ ]+ /, "", name)
      if (k == "") next
      if (k == "+") { refused = "+"; exit }
      if (substr(name, 1, 1) == "/" || index("/" name "/", "/../")) { refused = "x " name; exit }
      if (k == "l") { refused = "l " name; exit }
      if (k != "f") next
      # (unzip may take a backslash for an escape; control characters would break the lines)
      if (index(name, "\\") || name ~ /[[:cntrl:]]/) next
      n = split(name, p, "/"); d = ""
      for (i = 1; i <= n; i++) if (p[i] == "" || p[i] == ".") next
      if (index(p[n], ".") == 0) next
      e = tolower(p[n]); sub(/^.*\./, "", e)
      if (imp != "" && e == "ini") { total += $2; out = out "P " $2 " " p[n] "\t" name "\n"; next }
      for (i = 1; i < n; i++) { q = tolower(p[i]); if (q == "shaders" || q == "textures") { d = q; break } }
      if (d != "") { rel = p[i + 1]; for (j = i + 2; j <= n; j++) rel = rel "/" p[j] }
      else if (imp != "") { rel = p[n]; d = (e == "fx" || e == "fxh") ? "shaders" : "textures" }
      else next
      if (d == "shaders" && e != "fx" && e != "fxh") next
      if (d == "textures" && e !~ /^(png|jpg|jpeg|bmp|tga|dds|hdr)$/) next
      total += $2; out = out (d == "shaders" ? "S" : "T") " " $2 " " rel "\t" name "\n" }
    END { if (refused != "") print refused; else printf "= %.0f\n%s", total, out }')
  case "$plan" in
    +) die "$pack has more than $PACK_MAX_FILES files in it, so $APP_NAME doesn't unpack it." ;;
    x\ *) die "$pack has a file whose path leaves its folder (${plan#x }), so $APP_NAME doesn't unpack it." ;;
    l\ *) die "$pack has a link in it (${plan#l }), so $APP_NAME doesn't unpack it." ;;
  esac
  left=$PACK_LIMIT
  n=$(printf '%s\n' "$plan" | sed -n '1s/^= //p')
  [ "${n:-0}" -le "$left" ] || die "$pack unpacks to more than $(mb "$PACK_LIMIT") MB, so $APP_NAME doesn't unpack it."
  PACK_FILES=0 PACK_IMAGES=0 PACK_PRESETS=0
  while IFS= read -r line; do
    kind=${line%% *}
    case "$kind" in S) dest="$into/Shaders/$pack" ;; T) dest="$into/Textures/$pack" ;; P) dest="$into/Presets" ;; *) continue ;; esac
    line=${line#* }; line=${line#* }
    rel=${line%%"$tab"*} name=${line#*"$tab"}
    dest="$dest/$rel"
    mkdir -p "$(dirname "$dest")" 2>/dev/null || die "$pack has files $APP_NAME can't unpack ($name)."
    rc=0
    if [ -d "$src" ]; then
      head -c $((left + 1)) <"$src/$name" >"$dest" 2>>"$LOGFILE" || rc=$?
    else
      # (unzip takes the name for a pattern, and a leading dash for an option: each of those
      # characters in brackets matches only itself)
      unzip -p "$src" "$(printf '%s' "$name" | sed 's/[[*?]/[&]/g; s/^-/[-]/')" 2>>"$LOGFILE" | head -c $((left + 1)) >"$dest" || rc=$?
    fi
    n=$(stat -f %z "$dest")
    [ "$n" -le "$left" ] || die "$pack unpacks to more than $(mb "$PACK_LIMIT") MB, so $APP_NAME doesn't unpack it."
    [ "$rc" = 0 ] || die "$pack is damaged: $name could not be read. Try again."
    left=$((left - n))
    case "$kind" in S) PACK_FILES=$((PACK_FILES + 1)) ;; T) PACK_IMAGES=$((PACK_IMAGES + 1)) ;; P) PACK_PRESETS=$((PACK_PRESETS + 1)) ;; esac
  done <<EOF
$plan
EOF
  [ "$PACK_FILES" -gt 0 ] || [ -n "$mode" ] || die "$pack has no ReShade effects in it (no .fx or .fxh files in a Shaders folder)."
  log "unpacked $pack from $src: $PACK_FILES effect files, $PACK_IMAGES images, $PACK_PRESETS .ini files, $((PACK_LIMIT - left)) bytes in all"
}

# reshade_fetch: the checked ReShade64.dll in the cache, downloaded (the installer, checked, then the
# DLL out of the zip appended to it) unless it is there
reshade_dll_cached() { [ -f "$RS_DOWNLOADS/ReShade64.dll" ] && [ "$(sha256 "$RS_DOWNLOADS/ReShade64.dll")" = "$RESHADE_DLL_SHA256" ]; }
reshade_fetch() {
  local exe dll="$RS_DOWNLOADS/ReShade64.dll" rc=0
  exe="$RS_DOWNLOADS/$(basename "$RESHADE_URL")"
  if reshade_dll_cached; then say "ReShade: using the checked ReShade64.dll in the cache"; return 0; fi
  step "Downloading ReShade $RESHADE_VERSION from reshade.me"
  download "$RESHADE_URL" "$exe" ReShade "$RESHADE_SIZE"
  check_download "$exe" ReShade 4d5a "$RESHADE_SIZE" "$RESHADE_SHA256"
  # (unzip warns about the installer's own bytes in front of the zip: status 1)
  unzip -p "$exe" ReShade64.dll 2>>"$LOGFILE" | head -c 67108864 >"$dll.part" || rc=$?
  log "unzip ReShade64.dll: status $rc, $(stat -f %z "$dll.part") bytes"
  rm -f "$exe"
  [ -s "$dll.part" ] || { rm -f "$dll.part"; die "The ReShade installer from reshade.me has no ReShade64.dll in it. Try again later."; }
  if [ "$(sha256 "$dll.part")" != "$RESHADE_DLL_SHA256" ] || ! is_reshade "$dll.part"; then
    log "ReShade64.dll is not the expected one: sha256 $(sha256 "$dll.part")"
    rm -f "$dll.part"
    die "The ReShade64.dll in the installer from reshade.me is not the ReShade $RESHADE_VERSION $APP_NAME expects. Try again later."
  fi
  mv -f "$dll.part" "$dll"
  log "ReShade: $dll checked (sha256 $RESHADE_DLL_SHA256)"
}

# reshade_compiler [download]: COMPILER_SRC, the d3dcompiler_47.dll to put next to Gw2-64.exe: the
# game's own (bin64/cef, which comes with the game's Chromium) if it is an x86_64 DLL that exports
# D3DCompile, else mozilla/fxc2's in the cache, downloaded with "download"; empty without one
reshade_compiler() {
  local cef="$GAME_DIR/bin64/cef/d3dcompiler_47.dll" f="$RS_DOWNLOADS/d3dcompiler_47.dll"
  COMPILER_SRC=""
  if [ -f "$cef" ] && pe_is64 "$cef" && pe_has_export "$cef" D3DCompile; then COMPILER_SRC=$cef; return 0; fi
  if [ -f "$f" ] && [ "$(sha256 "$f")" = "$COMPILER_SHA256" ]; then COMPILER_SRC=$f; return 0; fi
  [ "${1:-}" = download ] || return 0
  step "Downloading Microsoft's shader compiler from github.com/mozilla/fxc2"
  download "$COMPILER_URL" "$f" "Microsoft's shader compiler" "$COMPILER_SIZE"
  check_download "$f" "Microsoft's shader compiler" 4d5a "$COMPILER_SIZE" "$COMPILER_SHA256"
  COMPILER_SRC=$f
}

# The ReShade folder, its compiled effects' folder (ReShade uses %TEMP% when that one is missing)
# and, if it has none, a starting ReShade.ini (ReShade's and the player's from then on; keys as
# ReShade 6.8.0 reads them, source/runtime.cpp and runtime_gui.cpp). Relative paths start at the
# folder. The overlay key is Home (fn + Left Arrow on a MacBook).
reshade_folder() {
  local d
  for d in "$RS" "$RS/Presets" "$RS/Shaders" "$RS/Textures" "$RS/Screenshots" "$RS_CACHE"; do
    [ -d "$d" ] || run mkdir -p "$d"
  done
  [ ! -e "$RS/ReShade.ini" ] || return 0
  {
    printf '[GENERAL]\n'
    printf '%s\n' 'EffectSearchPaths=.\Shaders\**' 'TextureSearchPaths=.\Textures\**' 'PresetPath=.\Presets\ReShadePreset.ini'
    printf 'IntermediateCachePath=%s\n' "$(winpath "$RS_CACHE")"
    printf '\n[INPUT]\nKeyOverlay=36,0,0,0\n\n[SCREENSHOT]\n'
    printf '%s\n' 'SavePath=.\Screenshots'
  } | put "$RS/ReShade.ini" 644
}

# reshade_place: what is missing of the three into the game folder, the DLL last (RSH, COMPILER_SRC
# set). A d3dcompiler_47.dll there stays as it is, the player's or the app's. The last steps move
# arcdps to its place next to ReShade (ARC_CHAIN), put ReShade's DLL in, and turn ReShade's
# [PROXY] keys on (proxy_sync); if a step fails, the ones before are undone.
reshade_place() {
  local n tmp
  if [ ! -e "$GAME_DIR/d3dcompiler_47.dll" ] && [ -n "$COMPILER_SRC" ]; then
    run install -m 644 "$COMPILER_SRC" "$GAME_DIR/.d3dcompiler_47.dll.gw2om-new"
    run mv -f "$GAME_DIR/.d3dcompiler_47.dll.gw2om-new" "$GAME_DIR/d3dcompiler_47.dll"
    [ -n "$DRY" ] || sha256 "$GAME_DIR/d3dcompiler_47.dll" >"$RS_COMPILER_RECORD"
    log "ReShade: $COMPILER_SRC into $GAME_DIR/d3dcompiler_47.dll"
  fi
  [ -e "$GAME_DIR/ReShade.ini" ] || reshade_game_ini | put "$GAME_DIR/ReShade.ini" 644
  [ "$RSH" = off ] || return 0
  n=$(addon_dll reshade on)
  tmp="$GAME_DIR/.$n.gw2om-new"
  arcdps_tidy on
  test_pause arcdps-moved
  # (checked one by one: errexit doesn't stop a failing step inside a condition)
  if { [ -z "$DRY" ] && { [ -e "$GAME_DIR/$n" ] || [ -L "$GAME_DIR/$n" ]; }; } ||
    ! run install -m 644 "$RS_DOWNLOADS/ReShade64.dll" "$tmp" || ! run mv -f "$tmp" "$GAME_DIR/$n"; then
    rm -f "$tmp"
    [ -z "$ARC_MOVED" ] || arcdps_move "$ARC_MOVED" "$(addon_dll arcdps off)" || true
    die "$APP_NAME couldn't put ReShade into the game folder as $n. Try again (details in $LOGS/install.log)."
  fi
  log "ReShade: ReShade64.dll $RESHADE_VERSION into $GAME_DIR/$n"
  if ! proxy_sync; then
    run rm -f "$GAME_DIR/$n"
    [ -z "$ARC_MOVED" ] || arcdps_move "$ARC_MOVED" "$(addon_dll arcdps off)" || true
    die "$(proxy_refusal "ReShade stays out of the game folder")"
  fi
}

# set reshade on|off (cmd_set): only while no session runs or starts (the session's lock, as set
# arcdps). On downloads and checks everything first, then makes the ReShade folder, and touches the
# game folder last.
set_reshade() {
  local stage="$RS_DOWNLOADS/packs" d p gone="" std sfx
  reshade_state
  [ "$RSH" != nogame ] || die "Guild Wars 2 is not installed yet: ReShade goes into its folder once it is."
  ! session_running || die "Quit Guild Wars 2 and Steam first: ReShade goes into or out of the game folder only while they are closed."
  registry_lock || die "A game session is starting. Try again once Guild Wars 2 and Steam have quit."
  if [ "$1" = off ]; then
    # (ReShade's keys off first: they never point at a file that is gone)
    proxy_sync off || die "$(proxy_refusal "ReShade stays in")"
    if [ "$RSH" = on ]; then
      for p in $RSH_DLL; do run rm -f "$GAME_DIR/$p"; gone=${gone:+$gone and }$p; done
    fi
    ! our_game_ini || run rm -f "$GAME_DIR/ReShade.ini"
    if [ -f "$RS_COMPILER_RECORD" ]; then
      if [ -f "$GAME_DIR/d3dcompiler_47.dll" ] && [ "$(sha256 "$GAME_DIR/d3dcompiler_47.dll")" = "$(cat "$RS_COMPILER_RECORD")" ]; then
        run rm -f "$GAME_DIR/d3dcompiler_47.dll"
      fi
      run rm -f "$RS_COMPILER_RECORD"
    fi
    write_settings reshade off
    # (last: arcdps back to the name it has alone)
    ARC_MOVED=""
    [ -z "$gone" ] || arcdps_tidy off
    registry_unlock
    if [ -n "$gone" ]; then
      say "ReShade removed from the game folder ($gone); its folder stays: $RS"
      echo "@done ReShade is off: its $gone is out of the game folder.$([ -z "$ARC_MOVED" ] || echo " arcdps is $ARC_MOVED again.") Your presets and shaders stay in $RS."
    elif [ "$RSH" = foreign ]; then
      echo "@done $APP_NAME didn't put the ReShade in the game folder ($RSH_DLL), so it stays as it is."
    elif [ "$RSH" = blocked ]; then
      echo "@done ReShade isn't in the game folder. The other ${RSH_BLOCKER// / and } there stays as it is."
    else
      echo "@done ReShade isn't in the game folder."
    fi
    return 0
  fi
  case "$RSH" in foreign|blocked) die "$(reshade_refusal)" ;; esac
  [ ! -e "$GAME_DIR/ReShade.ini" ] || our_game_ini ||
    die "The game folder has a ReShade.ini of its own. $APP_NAME leaves it alone, so it can't add ReShade: move that file away first (ReShade's settings go into $RS)."
  if [ "$RSH" = on ] && [ -e "$GAME_DIR/d3dcompiler_47.dll" ] && [ -e "$GAME_DIR/ReShade.ini" ]; then
    reshade_folder
    proxy_sync || die "$(proxy_refusal "ReShade doesn't load arcdps")"
    write_settings reshade on
    registry_unlock
    echo "@done ReShade is already in the game folder ($RSH_DLL)."
    return 0
  fi
  if [ -n "$DRY" ]; then
    echo "[dry-run] download $RESHADE_URL, check it, put its ReShade64.dll into $GAME_DIR/d3d11.dll with d3dcompiler_47.dll and ReShade.ini; the ReShade folder $RS"
    echo "@done ReShade would be in the game folder."
    return 0
  fi
  trap 'safe_rm --quiet "$RS_DOWNLOADS/packs" || true; rm -f "$RS_DOWNLOADS"/*.part "$RS_DOWNLOADS"/*.zip "$RS_DOWNLOADS"/*.exe; unlock' EXIT
  mkdir -p "$RS_DOWNLOADS"
  safe_rm --quiet "$stage"
  [ "$RSH" = on ] || reshade_fetch
  COMPILER_SRC=""
  [ -e "$GAME_DIR/d3dcompiler_47.dll" ] || reshade_compiler download
  # The standard effects whenever Shaders has no ReShade.fxh, which almost every effect includes
  # (an import may have filled Shaders before the first On); SweetFX only until an On has brought
  # it (RS_PACKS), so one a player deleted stays deleted. A pack's folder that is there stays as it is.
  std="" sfx=""
  [ -n "$(find "$RS/Shaders" -type f -iname ReShade.fxh 2>/dev/null | head -1)" ] || [ -e "$RS/Shaders/Standard" ] || std=1
  grep -qx SweetFX "$RS_PACKS" 2>/dev/null || [ -e "$RS/Shaders/SweetFX" ] || sfx=1
  case "$std$sfx" in
    11) p="ReShade's standard effects and SweetFX" ;;
    1) if [ -n "$std" ]; then p="ReShade's standard effects"; else p=SweetFX; fi ;;
    *) p="" ;;
  esac
  if [ -n "$p" ]; then
    mkdir -p "$stage"
    step "Downloading $p from github.com"
  fi
  if [ -n "$std" ]; then
    download "$RESHADE_SHADERS_URL" "$RS_DOWNLOADS/Standard.zip" "ReShade's standard effects" "$PACK_DOWNLOAD_MAX"
    check_download "$RS_DOWNLOADS/Standard.zip" "ReShade's standard effects" 504b0304
    unpack_pack "$RS_DOWNLOADS/Standard.zip" Standard "$stage"
  fi
  if [ -n "$sfx" ]; then
    download "$SWEETFX_URL" "$RS_DOWNLOADS/SweetFX.zip" SweetFX "$PACK_DOWNLOAD_MAX"
    check_download "$RS_DOWNLOADS/SweetFX.zip" SweetFX 504b0304
    unpack_pack "$RS_DOWNLOADS/SweetFX.zip" SweetFX "$stage"
  fi
  # Everything is here and checked: the ReShade folder, then the game folder (no session can start
  # meanwhile: this holds its lock)
  reshade_folder
  for d in Shaders Textures; do
    for p in "$stage/$d"/*; do
      [ -d "$p" ] || continue
      [ -e "$RS/$d/$(basename "$p")" ] || [ -L "$RS/$d/$(basename "$p")" ] || mv "$p" "$RS/$d/"
    done
  done
  reshade_state
  case "$RSH" in on|off) ;; *) die "The game folder changed during the download ($RSH). Try again." ;; esac
  ARC_MOVED=""
  reshade_place
  if ! grep -qx SweetFX "$RS_PACKS" 2>/dev/null && rs_safe "$RS_PACKS"; then
    { if [ -f "$RS_PACKS" ]; then cat "$RS_PACKS"; fi; echo SweetFX; } | put "$RS_PACKS" 644
  fi
  write_settings reshade on
  registry_unlock
  echo "@done ReShade $RESHADE_VERSION is in the game folder as d3d11.dll. It loads the next time the game starts.$([ "$PROXY_ON" = 0 ] || echo " ReShade loads arcdps itself now, so both load.")"
}

# sync_reshade [download]: with the setting on, puts ReShade's missing files back into the game
# folder (after Steam's file check or in a new bottle) from the cache, before Play, at Install and
# at Repair; only Repair ("download") downloads what the cache lacks. Never while a session runs
# or starts. A ReShade or another DLL the app didn't place keeps it out.
sync_reshade() {
  [ "$(setting reshade)" = on ] || return 0
  reshade_state
  case "$RSH" in
    nogame) return 0 ;;
    foreign|blocked) warn "ReShade stays out of the game folder. $(reshade_refusal)"; return 0 ;;
  esac
  if [ -e "$GAME_DIR/ReShade.ini" ] && ! our_game_ini; then
    warn "ReShade stays out of the game folder: it has a ReShade.ini of its own. Move that file away, then click Repair."
    return 0
  fi
  [ -n "$DRY" ] || [ -x "$LOCKER" ] || return 0
  registry_lock || { log "ReShade's files wait for the next start without a running session"; return 0; }
  if session_running; then registry_unlock; return 0; fi
  reshade_folder
  if [ "$RSH" = on ] && [ -e "$GAME_DIR/d3dcompiler_47.dll" ] && [ -e "$GAME_DIR/ReShade.ini" ]; then registry_unlock; return 0; fi
  reshade_compiler
  if { [ "$RSH" = off ] && ! reshade_dll_cached; } || { [ ! -e "$GAME_DIR/d3dcompiler_47.dll" ] && [ -z "$COMPILER_SRC" ]; }; then
    if [ "${1:-}" != download ]; then
      registry_unlock
      warn "ReShade's files are not in the cache any more, so the game starts without ReShade this time. Click Repair to download them again."
      return 0
    fi
    if [ -n "$DRY" ]; then echo "[dry-run] download ReShade and its compiler again"; registry_unlock; return 0; fi
    mkdir -p "$RS_DOWNLOADS"
    [ "$RSH" != off ] || reshade_fetch
    [ -e "$GAME_DIR/d3dcompiler_47.dll" ] || reshade_compiler download
  fi
  say "ReShade: its files back into the game folder"
  reshade_place
  registry_unlock
}

# --- ReShade's presets and shaders (reshade import; Settings › Interface: a drop on the Settings
# window or Add preset or shaders…): presets, zips and folders into the ReShade folder, whether
# ReShade is on, off or was never on, and while the game runs (it only adds files there, and never
# touches the game folder). Each source is unpacked into a staging folder in the cache first
# (unpack_pack and its rules: only effects, images and presets, no link, no path out, the size and
# file limits), then moved in, through real folders only. Shaders and textures go into
# Shaders/<name>/ and Textures/<name>/, named after the source; presets into Presets/, where a
# preset of the same name is replaced only by one from a source of the same name (RS_IMPORTS
# records where each came from), else kept. reshade use makes one ReShade's current preset.
RS_IMPORTS="$RS/.imports"   # "<preset><tab><source's name>" lines; the last one for a preset counts
RS_REPORT_NAMES=5           # the file names a sentence of the report lists before "and N more"

# import_name <file name>: a source's name for its folders: without .zip or .ini; letters, digits,
# spaces, dots, dashes and underscores (anything else becomes _); no dot or space at either end
# (Windows drops a trailing one); at most 64 characters
import_name() {
  local n=$1
  case "$n" in *.[Zz][Ii][Pp]|*.[Ii][Nn][Ii]) n=${n%.*} ;; esac
  n=$(printf '%s' "$n" | LC_ALL=C tr -c 'A-Za-z0-9._ -' '_' | LC_ALL=C cut -c 1-64 | sed 's/^[. ]*//; s/[. ]*$//')
  printf '%s\n' "${n:-Import}"
}
# preset_name <file name>: a preset's name in Presets: control characters and the characters
# Windows doesn't allow in a file name (<>:"\|?*) become _, and .INI .ini (ReShade takes a
# preset's extension only in lower case, resolve_preset_path)
preset_name() {
  local n
  n=$(printf '%s' "$1" | LC_ALL=C tr '\001-\037\177<>:"\\|?*' '_')
  case "$n" in *.[Ii][Nn][Ii]) n="${n%.*}.ini" ;; esac
  printf '%s\n' "$n"
}

# preset_effects <file>: the effect files (File.fx) its Techniques list names, once each; fails
# when the file is no preset, as ReShade tells (a Techniques key before any section,
# resolve_preset_path in source/runtime.cpp at v6.8.0; ini_file.cpp reads ",," as a comma)
preset_effects() {
  LC_ALL=C awk '
    function strip(s, c) {
      while (s != "" && index(c, substr(s, 1, 1))) s = substr(s, 2)
      while (s != "" && index(c, substr(s, length(s), 1))) s = substr(s, 1, length(s) - 1)
      return s }
    { line = $0; if (NR == 1 && substr(line, 1, 3) == "\357\273\277") line = substr(line, 4)
      line = strip(line, " \t\r"); c = substr(line, 1, 1)
      if (line == "" || c == ";" || c == "/" || c == "#") next
      if (c == "[") { i = index(line, "]"); sec = strip(i ? substr(line, 1, i - 1) : line, " \t[]"); next }
      i = index(line, "=")
      if (sec != "" || i == 0 || strip(substr(line, 1, i - 1), " \t") != "Techniques") next
      found = 1; v = strip(substr(line, i + 1), " \t")
      gsub(/,,/, "\001", v); n = split(v, t, ",")
      for (j = 1; j <= n; j++) {
        a = index(t[j], "@"); if (!a) continue
        f = substr(t[j], a + 1); gsub(/\001/, ",", f)
        if (f != "" && !(f in seen)) { seen[f] = 1; print f } } }
    END { exit !found }' "$1"
}

# imported_from <preset>: the name of the source a preset in Presets came from, or nothing
imported_from() {
  [ -f "$RS_IMPORTS" ] && [ ! -L "$RS_IMPORTS" ] || return 0
  N=$1 LC_ALL=C awk 'BEGIN { FS = "\t"; n = ENVIRON["N"] } $1 == n { s = $2 } END { print s }' "$RS_IMPORTS"
}

# rs_safe <path in the ReShade folder>: the ReShade folder and each folder on the way to it is a
# real folder (no link, no file), and it isn't a folder itself, nor a link to one (mv would move
# into it); RS_BAD: the first that isn't. rs_refuse: the sentence for it.
rs_safe() {
  local rest=${1#"$RS"/} at="$RS"
  RS_BAD_FILE=""
  if [ -L "$RS" ] || { [ -e "$RS" ] && [ ! -d "$RS" ]; }; then RS_BAD=$RS; return 1; fi
  while :; do
    case "$rest" in */*) at="$at/${rest%%/*}" rest=${rest#*/} ;; *) break ;; esac
    if [ -L "$at" ] || { [ -e "$at" ] && [ ! -d "$at" ]; }; then RS_BAD=$at; return 1; fi
  done
  if [ -d "$1" ]; then RS_BAD=$1 RS_BAD_FILE=1; return 1; fi
}
rs_refuse() {
  [ "$RS_BAD" != "$RS" ] || die "The ReShade folder is a link or a file ($RS), so $APP_NAME adds nothing to it. Put a folder in its place, then try again."
  [ -z "$RS_BAD_FILE" ] || die "${RS_BAD#"$RS"/} in the ReShade folder is a folder or a link to one, where $APP_NAME puts a file. Move it out of $RS, then try again."
  die "${RS_BAD#"$RS"/} in the ReShade folder is a link or a file where $APP_NAME puts a folder, so it adds nothing. Move it out of $RS, then try again."
}

# For the report: <lines> counted; listed ("a, b and c"; past <max> names, RS_REPORT_NAMES
# without one, "a, b, c, d, e and 3 more"); <count> <word> with an s unless 1
lines_count() { printf '%s' "$1" | LC_ALL=C awk '$0 != "" { n++ } END { print n + 0 }'; }
names_list() {
  printf '%s\n' "$1" | LC_ALL=C awk -v max="${2:-$RS_REPORT_NAMES}" '$0 != "" { a[++n] = $0 }
    END { m = n > max ? max : n
      for (i = 1; i <= m; i++) s = s (i == 1 ? "" : i == n ? " and " : ", ") a[i]
      if (n > max) s = s " and " (n - max) " more"
      print s }'
}
counted() { if [ "$1" = 1 ]; then echo "1 $2"; else echo "$1 $2s"; fi; }

# reshade import <path>...: each a preset (.ini), a zip or a folder. Refused as a whole when one
# can't be read or has nothing to add, or when a place in the ReShade folder is a link or a file.
# Prints "@preset <name>" for each preset that came in, and the report as @done.
reshade_import() {
  local p i=0 n kind base name stage="$RS_DOWNLOADS/import" d f pn rel files line from dest tab nl
  local parts="" moves="" presets="" kept="" records="" used have missing depth report s
  local -a names
  tab=$(printf '\t') nl='
'
  [ $# -gt 0 ] || die "Name the presets, zips or folders to add."
  open_log
  log "---- reshade import $*"
  if [ -n "$DRY" ]; then
    for p in "$@"; do echo "[dry-run] add $p to $RS"; done
    echo "@done Nothing was added (a dry run)."
    return 0
  fi
  lock
  trap 'safe_rm --quiet "$RS_DOWNLOADS/import" || true; unlock' EXIT
  safe_rm --quiet "$stage"
  mkdir -p "$stage"
  # Each source into its own staging folder, with only what it may bring
  for p in "$@"; do
    i=$((i + 1))
    # (a relative path with a leading dash isn't an option to unzip; the name in sentences without
    # control characters)
    while :; do case "$p" in ?*/) p=${p%/} ;; ?*/.) p=${p%/.} ;; *) break ;; esac; done
    case "$p" in -*) p="./$p" ;; esac
    base=$(printf '%s' "${p##*/}" | LC_ALL=C tr '\001-\037\177' '_')
    [ ! -L "$p" ] || die "$base is a link. Add the file or folder it leads to instead."
    [ -e "$p" ] || die "$base is not there any more."
    name=$(import_name "$base")
    names[i]=$name
    mkdir "$stage/$i"
    kind=other
    if [ -d "$p" ]; then kind=folder
    elif [ -f "$p" ]; then case "$base" in *.[Zz][Ii][Pp]) kind=zip ;; *.[Ii][Nn][Ii]) kind=preset ;; esac
    fi
    case "$kind" in
      folder|zip) unpack_pack "$p" "$name" "$stage/$i" import ;;
      preset)
        mkdir "$stage/$i/Presets"
        # (staged by its name in Presets: the moves are lines)
        f="$stage/$i/Presets/$(preset_name "$base")"
        head -c $((PACK_LIMIT + 1)) <"$p" >"$f" 2>>"$LOGFILE" || die "$base could not be read."
        [ "$(stat -f %z "$f")" -le "$PACK_LIMIT" ] || die "$base is larger than $(mb "$PACK_LIMIT") MB, which no ReShade preset is."
        preset_effects "$f" >/dev/null ||
          die "$base is not a ReShade preset: it has no Techniques line, which every preset has. $APP_NAME adds presets, and zips and folders of shaders."
        PACK_FILES=0 PACK_IMAGES=0 ;;
      *) die "$base is not a preset (.ini), a zip or a folder, so $APP_NAME doesn't add it." ;;
    esac
    # (an .ini that isn't a preset stays out)
    n=0
    for f in "$stage/$i/Presets"/*; do
      [ -f "$f" ] || continue
      if preset_effects "$f" >/dev/null; then n=$((n + 1)); else rm -f "$f"; fi
    done
    [ $((PACK_FILES + PACK_IMAGES + n)) -gt 0 ] || die "$base has no ReShade presets, shaders or textures in it."
  done
  # Where each staged file goes ("<staged file><tab><place>" lines), and what the report says
  n=$i i=0
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1)) name=${names[i]}
    for d in Shaders Textures; do
      [ -d "$stage/$i/$d/$name" ] || continue
      files=$(cd "$stage/$i/$d/$name" && find . -type f | sed 's|^\./||')
      while IFS= read -r rel; do
        [ -z "$rel" ] || moves="$moves$stage/$i/$d/$name/$rel$tab$RS/$d/$name/$rel$nl"
      done <<EOF
$files
EOF
      if [ "$d" = Shaders ]; then s="shader file"; else s=image; fi
      parts="$parts$(counted "$(lines_count "$files")" "$s") to $d/$name$nl"
    done
    for f in "$stage/$i/Presets"/*; do
      [ -f "$f" ] || continue
      pn=$(preset_name "${f##*/}")
      # (one of that name came in from an earlier source of this import)
      case "$nl$presets$kept" in *"$nl$pn$nl"*) continue ;; esac
      dest="$RS/Presets/$pn"
      if { [ -e "$dest" ] || [ -L "$dest" ]; } && [ "$(imported_from "$pn")" != "$name" ]; then
        kept="$kept$pn$nl"
        continue
      fi
      moves="$moves$f$tab$dest$nl" presets="$presets$pn$nl" records="$records$pn$tab$name$nl"
    done
  done
  # Nothing moves before every place is checked: no link and no file where a folder belongs
  while IFS= read -r line; do
    [ -z "$line" ] || rs_safe "${line#*"$tab"}" || rs_refuse
  done <<EOF
$moves
EOF
  [ -z "$records" ] || rs_safe "$RS_IMPORTS" || rs_refuse
  for d in Presets Shaders Textures Screenshots; do
    rs_safe "$RS/$d/-" || rs_refuse
  done
  reshade_folder
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    from=${line%%"$tab"*} dest=${line#*"$tab"}
    mkdir -p "$(dirname "$dest")"
    # (a link there is replaced, never written through)
    if [ -L "$dest" ]; then rm -f "$dest"; fi
    mv -f "$from" "$dest"
  done <<EOF
$moves
EOF
  if [ -n "$records" ]; then
    { if [ -f "$RS_IMPORTS" ] && [ ! -L "$RS_IMPORTS" ]; then cat "$RS_IMPORTS"; fi; printf '%s' "$records"; } | put "$RS_IMPORTS" 644
  fi
  # The report: what went where, what of Presets stayed, and what the presets need
  [ -z "$presets" ] || parts="$(counted "$(lines_count "$presets")" preset) to Presets$nl$parts"
  [ -z "$parts" ] || report="Added $(names_list "$parts" 100000)."
  if [ -n "$kept" ]; then
    if [ "$(lines_count "$kept")" = 1 ]; then s="kept it, not the new one"; else s="kept them, not the new ones"; fi
    report="${report:+$report }Presets already had $(names_list "$kept") from elsewhere, so $APP_NAME $s."
  fi
  if [ -n "$presets" ]; then
    used=""
    while IFS= read -r pn; do
      [ -z "$pn" ] || used="$used$(preset_effects "$RS/Presets/$pn" || true)$nl"
    done <<EOF
$presets
EOF
    used=$(printf '%s' "$used" | LC_ALL=C awk '$0 != "" && !seen[$0]++')
    have=$(cd "$RS/Shaders" && find . -type f 2>>"$LOGFILE" | sed 's|.*/||') || true
    missing=$(HAVE="$have" USED="$used" LC_ALL=C awk 'BEGIN { n = split(ENVIRON["HAVE"], h, "\n"); for (i = 1; i <= n; i++) got[h[i]] = 1
      n = split(ENVIRON["USED"], u, "\n"); for (i = 1; i <= n; i++) if (u[i] != "" && !(u[i] in got)) print u[i] }')
    n=$(lines_count "$presets")
    if [ "$n" = 1 ]; then s="This preset uses"; else s="These $n presets use"; fi
    n=$(lines_count "$used")
    if [ "$n" = 0 ]; then s="$s no effects."
    elif [ -z "$missing" ]; then
      if [ "$n" = 1 ]; then s="$s 1 effect, which is in Shaders."; else s="$s $n effects, all of them in Shaders."; fi
    else
      n=$(lines_count "$missing")
      if [ "$n" = 1 ]; then s="$s $(counted "$(lines_count "$used")" effect). 1 is missing: $(names_list "$missing")."
      else s="$s $(counted "$(lines_count "$used")" effect). $n are missing: $(names_list "$missing")."; fi
      say "Effects missing from $RS/Shaders: $(names_list "$missing" 100000)"
    fi
    report="$report $s"
    depth=$(printf '%s\n' "$used" | LC_ALL=C awk '{ l = tolower($0) } l ~ /mxao|dof|rtgi/ || l == "displaydepth.fx"')
    if [ -n "$depth" ]; then
      if [ "$(lines_count "$depth")" = 1 ]; then s="reads the depth buffer: it stays"; else s="read the depth buffer: they stay"; fi
      report="$report $(names_list "$depth") $s off in online games with this build of ReShade."
    fi
    if session_running; then report="$report Guild Wars 2 is running: pick the preset in ReShade's menu (Home key)."; fi
    while IFS= read -r pn; do [ -z "$pn" ] || echo "@preset $pn"; done <<EOF
$presets
EOF
  fi
  log "report: $report"
  echo "@done $report"
}

# ini_set <ini> <section> <key=value>...: the ini on stdout with those keys set in that section and
# nothing else changed (its other lines and line ends byte for byte). Keys and sections as
# ReShade's ini_file.cpp reads them: trimmed, ; / # start a comment. A missing key goes under the
# section's first header, and a missing section goes at the end, with the file's line ends.
ini_set() {
  local ini=$1 sec=$2 nl=0
  shift 2
  [ "$(tail -c 1 "$ini" | od -An -tx1 | tr -d ' \n')" != 0a ] || nl=1
  S=$sec KV="$(printf '%s\n' "$@")" NL=$nl LC_ALL=C awk '
    function strip(s, c) {
      while (s != "" && index(c, substr(s, 1, 1))) s = substr(s, 2)
      while (s != "" && index(c, substr(s, length(s), 1))) s = substr(s, 1, length(s) - 1)
      return s }
    BEGIN { s = ENVIRON["S"]; nl = ENVIRON["NL"]; n = split(ENVIRON["KV"], kv, "\n")
      for (k = 1; k <= n; k++) key[k] = substr(kv[k], 1, index(kv[k], "=") - 1) }
    { line = $0; cr = ""; out[NR] = $0
      if (substr(line, length(line), 1) == "\r") { cr = "\r"; line = substr(line, 1, length(line) - 1) }
      if (NR == 1) { firstcr = cr; if (substr(line, 1, 3) == "\357\273\277") line = substr(line, 4) }
      t = strip(line, " \t"); c = substr(t, 1, 1)
      if (c == "[") {
        i = index(t, "]"); sec = strip(i ? substr(t, 1, i - 1) : t, " \t[]")
        if (sec == s && !g) { g = NR; gcr = cr }
        next }
      if (sec != s || c == ";" || c == "/" || c == "#") next
      i = index(t, "=")
      if (!i) next
      name = strip(substr(t, 1, i - 1), " \t")
      for (k = 1; k <= n; k++) if (name == key[k]) { out[NR] = kv[k] cr; set[k] = 1 } }
    END {
      for (j = 1; j <= NR; j++) {
        printf "%s", out[j]
        if (j == g) for (k = 1; k <= n; k++) if (!set[k]) printf "\n%s%s", kv[k], gcr
        if (j < NR || nl) printf "\n" }
      if (!g) {
        if (NR && !nl) printf "\n"
        printf "[%s]%s\n", s, firstcr
        for (k = 1; k <= n; k++) printf "%s%s\n", kv[k], firstcr } }' "$ini"
}

# reshade use <preset>: PresetPath in the ReShade folder's ReShade.ini, the one key and nothing else
# of the file (ini_set); only while no session runs or starts, since ReShade writes its ini while it
# runs (the session's lock, as set reshade)
reshade_use() {
  local name=${1:-} f ini="$RS/ReShade.ini" value
  case "$name" in ""|*/*|.|..|*[[:cntrl:]]*) die "Name a preset in $RS/Presets." ;; esac
  f="$RS/Presets/$name"
  [ -f "$f" ] || die "$name is not in $RS/Presets."
  preset_effects "$f" >/dev/null || die "$name is not a ReShade preset: it has no Techniques line."
  # (relative to the ReShade folder, as ReShade writes it; a comma doubled)
  value=$(printf '.\\Presets\\%s' "$name" | sed 's/,/,,/g')
  open_log
  log "---- reshade use $name"
  if [ -n "$DRY" ]; then echo "[dry-run] PresetPath=$value in $ini"; echo "@done ReShade would start with $name."; return 0; fi
  lock
  trap 'unlock' EXIT
  ! session_running || die "Guild Wars 2 is running, and ReShade rewrites its settings while it runs. Pick $name in ReShade's menu (Home key) instead."
  registry_lock || die "A game session is starting. Pick $name in ReShade's menu (Home key) once the game runs."
  rs_safe "$ini" || rs_refuse
  reshade_folder
  ini_set "$ini" GENERAL "PresetPath=$value" | put "$ini" 644
  registry_unlock
  log "ReShade.ini: PresetPath=$value"
  echo "@done ReShade starts with $name the next time the game starts."
}

cmd_reshade() {
  case "${1:-}" in
    import) shift; reshade_import "$@" ;;
    use) shift; reshade_use "$@" ;;
    *) echo "@error Unknown command: reshade ${1:-}"; exit 2 ;;
  esac
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
  for d in "$OLD_BOTTLE/drive_c" \
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
    "$OLD_APPDIR/"*) echo "$OLD_LABEL" ;;
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
volume_of() { local d=$1; while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done; stat -L -f %d "$d"; }
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

# clone_tree <source> <destination> <what> <progress label> [<bytes>]: the folder cloned (same disk:
# no extra space) or copied (another disk, or GW2_ON_MAC_IMPORT_COPY), the copy after a free-space
# check and with progress. <destination> must not exist; its folder must. Links inside it stay
# links (cp -R). CLONE_HOW: cloned or copied.
clone_tree() {
  local src=$1 dst=$2 what=$3 label=$4 total=${5:-} pid free w
  CLONE_HOW=""
  if [ -n "$DRY" ]; then
    if same_volume "$src"; then CLONE_HOW=cloned; echo "[dry-run] clone $src to $dst"
    else CLONE_HOW=copied; echo "[dry-run] copy $src to $dst"
    fi
    return 0
  fi
  if same_volume "$src"; then
    say "Cloning $what from $src: the same disk, so it takes no extra space"
    if run cp -Rpc "$src" "$dst" 2>>"$LOGFILE"; then
      CLONE_HOW=cloned
      [ -z "$total" ] || echo "@progress $label $total $total"
      return 0
    fi
    log "cloning failed; copying instead"
    w=$(with_game)
    safe_rm --quiet ${w:+"$w"} "$dst" || die "$APP_NAME couldn't remove the clone that failed ($dst), so it doesn't copy over it (details in $LOGS/install.log)."
  fi
  [ -n "$total" ] || total=$(folder_bytes "$src")
  free=$(free_kb)
  [ "$(( ${free:-0} * 1024 ))" -ge "$((total + 1000000000))" ] ||
    die "Not enough free disk space to copy $what: they need $(( (total + 999999999) / 1000000000 )) GB (and 1 GB to spare), $(( ${free:-0} / 1000000 )) GB are free."
  say "Copying $what from $src ($(( (total + 500000000) / 1000000000 )) GB, from another disk)"
  { printf '+ cp -Rp %q %q\n' "$src" "$dst"; } >>"$LOGFILE"
  cp -Rp "$src" "$dst" 2>>"$LOGFILE" &
  pid=$!
  FETCH_PID=$pid
  while kill -0 "$pid" 2>/dev/null; do
    echo "@progress $label $(folder_bytes "$dst") $total"
    sleep 1
  done
  wait "$pid" || { FETCH_PID=; die "Copying $what failed (details in $LOGS/install.log)."; }
  FETCH_PID=
  echo "@progress $label $total $total"
  CLONE_HOW=copied
}

# import_game <source dir> <bottle's game dir>: the folder cloned (same disk) or copied (with a
# free-space check and progress). Left out, and named in LEFT: my own addon's files (version.dll
# with its mark, gw2-ui-scale.*), arcdps (d3d11.dll or dxgi.dll; addons are not cleared for this
# engine yet) and another program's d3d11.dll. A ReShade (its d3d11.dll or dxgi.dll, and the
# ReShade.ini next to Gw2-64.exe, which points into the other install) stays behind too, named in
# RESHADE_LEFT. Any other addon comes along as it is (ADDONS names them).
import_game() {
  local src=$1 dst=$2 total n out="" arc="" other=""
  RESHADE_LEFT=""
  total=$(folder_bytes "$src")
  LEFT=""
  if [ -f "$src/version.dll" ] && grep -aq "$UI_MARK" "$src/version.dll"; then
    out=" version.dll" LEFT=" The larger interface's version.dll stayed behind: this app has its own."
  fi
  for n in $ARCDPS_DLLS; do
    [ -f "$src/$n" ] || continue
    # (arcdps at ReShade's chain path only through real folders: a link there leads to the source's
    # or another folder, and the copy keeps the link, so a removal would reach that file)
    case "$n" in
      "$ARC_CHAIN") chain_ok "$src" || continue ;;
    esac
    if is_arcdps "$src/$n"; then out="$out $n" arc=yes
    elif is_reshade "$src/$n"; then :
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
  IMPORT_DST=$dst
  clone_tree "$src" "$dst" "the game's files" "Guild Wars 2" "$total"
  IMPORT_HOW=$CLONE_HOW
  # (the copy checked again: a link made on the chain path meanwhile keeps that file)
  for n in $out; do
    [ "$n" != "$ARC_CHAIN" ] || chain_ok "$dst" || continue
    run rm -f "$dst/$n"
  done
  run rm -f "$dst/gw2-ui-scale.ini" "$dst/gw2-ui-scale.log"
  for n in d3d11.dll dxgi.dll ReShade.ini; do
    if { [ "$n" = ReShade.ini ] && [ -f "$dst/$n" ]; } || is_reshade "$dst/$n"; then
      run rm -f "$dst/$n"
      RESHADE_LEFT=${RESHADE_LEFT:+$RESHADE_LEFT, }$n
    fi
  done
  [ -z "$RESHADE_LEFT" ] || say "ReShade stayed behind in $src ($RESHADE_LEFT): $APP_NAME puts in its own when you turn ReShade on in Settings › Interface"
  chmod -R u+w "$dst"
  ADDONS=$( (cd "$dst" && ls -d ./*.dll addons bin64/d3d9.dll 2>/dev/null || true) | sed 's|^\./||' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  [ -z "$ADDONS" ] || say "Addons that came along with the game's files: $ADDONS ($APP_NAME leaves them as they are)"
  log "game files $IMPORT_HOW: $src -> $dst ($total bytes)${out:+; left out:$out}"
}

# The bottle's Windows user: the name of its own folder in users/, else (a new bottle) crossover,
# the name 0.1.x's CrossOver engine gives every user. Mach9's Wine names the user after USER
# (dlls/ntdll/unix/loader.c), which wine_do and game_env pass, so a bottle keeps the name it was made
# with: crossover from this version on, the Mac's login in a bottle an earlier one made. The name
# is the profile folder's, and the key of what a program protected with CryptProtectData
# (dlls/crypt32/protectdata.c): a bottle moved from 0.1.x reads its own data only as crossover.
bottle_user() {
  local u
  for u in "$BOTTLE/drive_c/users"/*; do
    [ -d "$u" ] || continue
    case "$(basename "$u")" in Public|public) continue ;; esac
    basename "$u"; return
  done
  echo "$WIN_USER"
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
  backup="$to/$APP_FOLDER backup $(date '+%Y-%m-%d %H%M%S')"
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
    echo "@done Guild Wars 2 is ready: its files were $how$([ "$SETTINGS_IMPORTED" = yes ] && echo ", with your game settings").$([ -z "$ADDONS" ] || echo " Addons that came along: $ADDONS; $APP_NAME leaves them as they are.")$LEFT$([ -z "$RESHADE_LEFT" ] || echo " ReShade stayed behind: turn it on in Settings › Interface.")$([ "$route" = steam ] && echo " Steam may check the files at the first Play.") Press Play."
  else
    step "Steam opens: sign in, and it brings Guild Wars 2 up to date"
    launch "$STEAM_EXE" "steam://install/$GW2_APPID"
    set_state stage waiting_game
    IMPORT_DST="" IMPORT_ACF=""
    log "install import: Steam's record of the game is not complete; waiting for Steam"
    echo "@done Your game files were $how.$LEFT Steam is starting: sign in, and it brings the game up to date; this window follows it."
  fi
}

# --- install move: GW2 on Mac 0.1.x's install into a new bottle of this app (docs/adr/0019, 0020)
#
# At its first start the window runs it by itself when status says move=yes: this app has no
# install of its own (no manifest, no bottle), 0.1.x has one (old_install), and neither a move nor
# Start fresh happened here before (MOVE_RECORD). It waits while anything of 0.1.x runs (old_busy).
# The bottle is new, made by this engine, with 0.1.x's Windows user (crossover). 0.1.x's Steam
# folder (Steam's login, config, userdata and the library with the game) takes the place of the
# one Valve's installer just made, or on ArenaNet's route its game folder comes over: renamed on
# the same disk, which is instant and takes no space, and never copied (move_rename). Another disk
# is refused before anything is written. The small things are cloned: the profile's Steam files,
# the game's settings, the ReShade folder. The addons come as they were, in the game folder, and
# the finishing touches put them in order as at every Play; the addon files 0.1.x had there are
# kept (MOVE_ADDONS) for a failure and for Rollback. A failure at any step renames the folder back
# with those files, then removes what the move made (CREATED, on_install_exit).

# The game folder's files that the app or an addon keeps there: arcdps and ReShade at either name,
# arcdps at ReShade's chain path, ReShade's ini and compiler, the larger interface's files. A move
# brings them along, and a failure or Rollback puts back the ones 0.1.x had (addons_save,
# addons_restore). ADDON_DIRS: the folders of the chain path, deepest first.
ADDON_FILES="d3d11.dll dxgi.dll d3dcompiler_47.dll ReShade.ini version.dll gw2-ui-scale.ini gw2-ui-scale.log addons/arcdps/chain/d3d11.dll"
ADDON_DIRS="addons/arcdps/chain addons/arcdps addons"

# addon_dir <file>: the folder of an ADDON_FILES name, "." for one at the top
addon_dir() { case "$1" in */*) echo "${1%/*}" ;; *) echo . ;; esac; }
# addon_real <game dir> <file>: no folder on the way to <file> inside the game folder is a link
addon_real() {
  local d=${2%/*}
  [ "$d" != "$2" ] || return 0
  while [ -n "$d" ] && [ "$d" != . ]; do
    [ ! -L "$1/$d" ] || return 1
    case "$d" in */*) d=${d%/*} ;; *) d="" ;; esac
  done
}

# addons_save <game dir> <folder>: ADDON_FILES as the game folder has them, copied file by file into
# <folder> (made anew), and in <folder>/list what was there: "file", "link" (left as it is, as is a
# file behind a linked folder) or "dir" for ADDON_DIRS
addons_save() {
  local g=$1 d=$2 f
  if [ -n "$DRY" ]; then echo "[dry-run] keep the addon files of $g in $d"; return 0; fi
  safe_rm --quiet "$d"
  mkdir -p "$d/files"
  for f in $ADDON_FILES; do
    if [ -L "$g/$f" ] || ! addon_real "$g" "$f"; then
      { [ ! -e "$g/$f" ] && [ ! -L "$g/$f" ]; } || echo "link $f"
    elif [ -f "$g/$f" ]; then
      mkdir -p "$d/files/$(addon_dir "$f")"
      cp -p "$g/$f" "$d/files/$f"
      echo "file $f"
    fi
  done >"$d/list"
  for f in $ADDON_DIRS; do [ ! -d "$g/$f" ] || [ -L "$g/$f" ] || echo "dir $f"; done >>"$d/list"
}

# addons_links <game dir>: no ADDON_FILES name in the game folder is a link or behind a linked
# folder. Rollback and a failed move put back the files 0.1.x had at those names, and a link's file
# (which the move may rewrite, ReShade.ini) would not come back with them.
addons_links() {
  local f
  [ -z "$DRY" ] || return 0
  for f in $ADDON_FILES; do
    if [ -L "$1/$f" ] || ! addon_real "$1" "$f"; then
      { [ -e "$1/$f" ] || [ -L "$1/$f" ]; } || continue
      die "$1/$f is a link, so $APP_NAME couldn't put $OLD_LABEL's addon files back exactly, and doesn't move this install. Start fresh in Settings › Troubleshooting installs anew."
    fi
  done
}

# addons_restore <game dir> <folder> <root>: ADDON_FILES as addons_save found them: each file put
# back (cp -p: its content, mode and time), one that wasn't there removed, a link left as it is;
# then the folders of ADDON_DIRS that weren't there, if empty. Only inside <root>, the renamed
# folder, once links are resolved. A game folder that leads out of it gets nothing, and that is no
# failure: the move and Move in refuse such a folder (move_links, move_inside) before their first
# write into it, so nothing of theirs is there to undo.
addons_restore() {
  local g=$1 d=$2 r f
  if [ -n "$DRY" ]; then echo "[dry-run] put back the addon files of $g from $d"; return 0; fi
  [ -f "$d/list" ] || return 1
  r=$(cd "$3" 2>/dev/null && pwd -P) || return 1
  case "$(cd "$g" 2>/dev/null && pwd -P)/" in "$r/"*) ;; *) log "$g leads out of $3: nothing was written there, and nothing is put back"; return 0 ;; esac
  for f in $ADDON_FILES; do
    if grep -qxF "file $f" "$d/list"; then
      addon_real "$g" "$f" || continue
      # (a copy beside it, then a rename over it: the file is never missing)
      mkdir -p "$g/$(addon_dir "$f")" && cp -p "$d/files/$f" "$g/$f.gw2om-new.$$" && mv -f "$g/$f.gw2om-new.$$" "$g/$f" ||
        { rm -f "$g/$f.gw2om-new.$$"; return 1; }
    elif grep -qxF "link $f" "$d/list"; then
      :
    elif addon_real "$g" "$f" && { [ -f "$g/$f" ] || [ -L "$g/$f" ]; }; then
      rm -f "$g/$f" || return 1
    fi
  done
  for f in $ADDON_DIRS; do
    grep -qxF "dir $f" "$d/list" || [ -L "$g/$f" ] || ! addon_real "$g" "$f/x" || rmdir "$g/$f" 2>/dev/null || true
  done
  log "the addon files of $g as $OLD_LABEL had them ($d)"
}

# record_key <key>: old, new, game or inode from MOVE_RECORD; undo_key <key>: a line of MOVE_UNDO
record_key() { sed -n "s/^$1=//p" "$MOVE_RECORD" 2>/dev/null | tail -1; }
undo_key() { sed -n "s/^$1=//p" "$MOVE_UNDO" 2>/dev/null | tail -1; }
# move_pair <path> <path> [<game>]: one is a folder in 0.1.x's bottle's drive_c, the other in this
# app's, no ".." in either nor in the game folder's path inside: the only two places a rename read
# from MOVE_RECORD or MOVE_UNDO may join
in_drive_c() { path_under "$1" "$2/drive_c" && case "/$1/" in */../*|*/./*) return 1 ;; esac; }
move_pair() {
  case "/${3:-}/" in */../*|*/./*) return 1 ;; esac
  { in_drive_c "$1" "$OLD_BOTTLE" && in_drive_c "$2" "$BOTTLE"; } || { in_drive_c "$1" "$BOTTLE" && in_drive_c "$2" "$OLD_BOTTLE"; }
}

# no_link <folder>: a folder under the home folder with no link anywhere on the way from the home
# folder to it: its resolved path is its own path
no_link() {
  local h
  path_under "$1" "$H" && [ -d "$1" ] || return 1
  h=$(cd "$H" && pwd -P) || return 1
  [ "$(cd "$1" 2>/dev/null && pwd -P)" = "$h${1#"$H"}" ]
}

# same_disk <folder> <folder>: both on one volume, so a rename moves between them (not in the
# sandbox's other-disk test, GW2_ON_MAC_IMPORT_COPY)
same_disk() { [ -z "$IMPORT_COPY" ] && [ "$(stat -L -f %d "$1")" = "$(stat -L -f %d "$2")" ]; }

# rename_dir <from> <to>: rename(2) itself, through macOS's perl. Unlike mv it never copies (another
# volume fails with EXDEV) and never moves a folder into one that is there (rename fails, or
# replaces an empty folder). Its command line says gw2om-rename (backend_alive). Logged as "+ rename".
rename_dir() {
  { printf '+ rename'; printf ' %q' "$1" "$2"; printf '\n'; } >>"$LOGFILE"
  /usr/bin/perl -e 'rename($ARGV[1], $ARGV[2]) or die "rename: $!\n"' gw2om-rename "$1" "$2" 2>>"$LOGFILE"
}

# move_check <from> <to> <game>: the rename may go ahead, checked before anything changes: between
# the two bottles (move_pair), <from> a folder and <to>'s folder a folder with no link on the way
# from the home folder (no_link), <to> not there, both on one volume
move_check() {
  [ -z "$DRY" ] || return 0
  move_ok "$@" || die "$MOVE_WHY"
}
# move_ok <from> <to> <game>: move_check's checks without dying (recovery's renames take them too):
# 1, and MOVE_WHY says why
move_ok() {
  MOVE_WHY=""
  if ! move_pair "$1" "$2" "$3"; then MOVE_WHY="$APP_NAME moves the game only between $OLD_LABEL's bottle and its own, not $1 to $2."
  elif ! no_link "$1"; then MOVE_WHY="$1 isn't a folder, or is reached through a link, so $APP_NAME doesn't move it. Nothing changed."
  elif [ -e "$2" ] || [ -L "$2" ]; then MOVE_WHY="$2 is there already, so $APP_NAME doesn't move the game there. Nothing changed."
  elif ! no_link "${2%/*}"; then MOVE_WHY="${2%/*} isn't a folder, or is reached through a link, so $APP_NAME doesn't move the game there. Nothing changed."
  elif ! same_disk "$1" "${2%/*}"; then MOVE_WHY="$1 is on another disk than ${2%/*}. $APP_NAME moves the game only by renaming it, never by copying it, so nothing changed."
  fi
  [ -z "$MOVE_WHY" ]
}

# move_journal <kind> <from> <to> <game> <snapshot>: MOVE_UNDO, the transaction (kind install, rollback
# or move-in) before its first change: the folder's two places and its inode, the game folder's
# path in it, the addon files to put back if it is undone (a folder addons_save made), and what an
# install move makes (MOVE_MADE), removed when it is undone
move_journal() {
  [ -z "$DRY" ] || return 0
  printf 'kind=%s\nfrom=%s\nto=%s\ninode=%s\ngame=%s\nsnapshot=%s\ncreated=%s\n' "$1" "$2" "$3" "$(stat -f %i "$2")" "$4" "$5" "${MOVE_MADE:-}" |
    put "$MOVE_UNDO" 644
}

# move_rename <from> <to>: the folder renamed (rename_dir: instant, no space, the same inode), after
# move_check; the journal is written already
move_rename() {
  if [ -n "$DRY" ]; then echo "[dry-run] rename $1 to $2"; return 0; fi
  move_check "$1" "$2" "$(undo_key game)"
  say "Moving $1 to $2: a rename on the same disk, so it takes no extra space"
  rename_dir "$1" "$2" || die "$APP_NAME couldn't rename $1 to $2, so nothing changed (details in $LOGS/install.log)."
  [ "$(stat -f %i "$2")" = "$(undo_key inode)" ] || die "$2 isn't the folder $APP_NAME renamed (details in $LOGS/install.log)."
}

# move_where: where MOVE_UNDO's folder is, by its path and its inode: to, from, or empty (neither)
move_where() {
  local f t i
  f=$(undo_key from) t=$(undo_key to) i=$(undo_key inode)
  [ -n "$i" ] && move_pair "$f" "$t" "$(undo_key game)" || return 0
  if [ -d "$t" ] && [ ! -L "$t" ] && [ "$(stat -f %i "$t")" = "$i" ]; then echo to
  elif [ -d "$f" ] && [ ! -L "$f" ] && [ "$(stat -f %i "$f")" = "$i" ]; then echo from
  fi
}

# move_committed: MOVE_UNDO's transaction is done. An install move is, once MOVE_RECORD names its
# rename (the record is written after the rename and the addon steps); Rollback and Move in are
# done when MOVE_UNDO goes. The exit handlers and move_recover read it alike.
move_committed() {
  [ "$(undo_key kind)" = install ] && [ "$(head -1 "$MOVE_RECORD" 2>/dev/null || true)" = moved ] &&
    [ "$(record_key new)" = "$(undo_key to)" ] && [ "$(record_key inode)" = "$(undo_key inode)" ]
}

# move_undo: MOVE_UNDO's transaction undone (not committed): the folder found by its inode, the addon
# files of its snapshot put back into it (Rollback's wherever it is, since it changes them before
# the rename; the others' only once renamed), then renamed back if it was. 1 if it is at neither
# place, or can't be renamed back: then everything stays.
move_undo() {
  local f t g snap kind w
  [ -f "$MOVE_UNDO" ] || return 0
  f=$(undo_key from) t=$(undo_key to) g=$(undo_key game) snap=$(undo_key snapshot) kind=$(undo_key kind)
  w=$(move_where)
  case "$w" in
    to)
      # (the way back checked as the way there was, before anything changes)
      move_ok "$t" "$f" "$g" || { log "$t can't be renamed back to $f: $MOVE_WHY Everything stays."; return 1; }
      if [ "$kind" = rollback ]; then
        # (Rollback: back into this app's bottle first, then this app's addon files from its
        # snapshot; if they can't all come back, the snapshot and MOVE_UNDO stay)
        rename_dir "$t" "$f" || { log "$t couldn't be renamed back to $f; everything stays"; return 1; }
        log "renamed $t back to $f"
        [ -z "$snap" ] || addons_restore "$f${g:+/$g}" "$snap" "$f" || { log "the addon files of $f${g:+/$g} couldn't all be put back; $MOVE_UNDO stays"; return 1; }
      else
        # (a move or Move in: 0.1.x's addon files back while the folder is still in this app's
        # bottle, then the rename; if they can't all come back, everything stays for a retry)
        [ -z "$snap" ] || addons_restore "$t${g:+/$g}" "$snap" "$t" || { log "the addon files of $t${g:+/$g} couldn't all be put back; $MOVE_UNDO stays"; return 1; }
        rename_dir "$t" "$f" || { log "$t couldn't be renamed back to $f; everything stays"; return 1; }
        log "renamed $t back to $f"
      fi ;;
    from)
      if [ "$kind" = rollback ] && [ -n "$snap" ]; then
        # (no link on the way to it, checked again before every retry)
        no_link "$f" || { log "$f is reached through a link now; $MOVE_UNDO stays"; return 1; }
        addons_restore "$f${g:+/$g}" "$snap" "$f" || { log "the addon files of $f${g:+/$g} couldn't all be put back; $MOVE_UNDO stays"; return 1; }
      fi
      log "$f was not renamed" ;;
    *) log "the folder of $MOVE_UNDO is at neither $f nor $t with inode $(undo_key inode); everything stays"; return 1 ;;
  esac
}

# safe_rm [--with-game] [--quiet] <path>...: every recursive removal in this file goes through it. A
# folder with a game in it (a file named Gw2.dat or Gw2-64.exe anywhere inside, on its volume) stays,
# the log says why, and safe_rm returns 1 once it has done the rest; so does one find can't look
# through, and one with another volume mounted inside (rm -x doesn't cross into it, and find -xdev
# doesn't look there). A leftover folder can be removed later; a game moved from 0.1.x can't be had
# back. rm's own failure returns 1 too. --with-game removes a folder with a game anyway, only for an
# install that was never moved (never_moved), and only by its three callers: Uninstall
# (uninstall_files), the cleanup of a failed install of its own (on_install_exit), and an import's
# clone that failed, before the copy takes its place (clone_tree): the app's own copy, never the
# source. --quiet: no log line, and done in a dry run too (scratch folders).
safe_rm() {
  local with="" quiet="" p hit dev devs st=0
  while :; do
    case "${1:-}" in --with-game) with=yes; shift ;; --quiet) quiet=yes; shift ;; *) break ;; esac
  done
  for p in "$@"; do
    { [ -e "$p" ] || [ -L "$p" ]; } || continue
    if [ -d "$p" ] && [ ! -L "$p" ]; then
      # (every folder's device read to the end, a failure to read refused, then compared)
      dev=$(stat -f %d "$p")
      devs=$(find "$p" -xdev -type d -exec stat -f %d {} + 2>/dev/null) ||
        { log "$p stays: find couldn't look through all of it"; st=1; continue; }
      if printf '%s\n' "$devs" | awk -v d="$dev" '$0 != d { f = 1 } END { exit !f }'; then
        log "$p stays: another volume is mounted inside it"; st=1; continue
      fi
      if [ -z "$with" ]; then
        hit=$(find "$p" -xdev -type f \( -iname Gw2.dat -o -iname Gw2-64.exe \) -print -quit 2>/dev/null) ||
          { log "$p stays: find couldn't look through all of it for a game"; st=1; continue; }
        [ -z "$hit" ] || { log "$p stays: a game is in it ($hit)"; st=1; continue; }
      fi
    fi
    if [ -n "$quiet" ]; then rm -rfx "$p" || st=1; else run rm -rfx "$p" || st=1; fi
  done
  return $st
}

# never_moved: this install never came from a move of 0.1.x's: state origin not move or moved, no
# MOVE_UNDO, and no MOVE_RECORD in any form (a link, even a dangling one, counts) unless it is a
# file of exactly one line, Start fresh's "skipped". Only then may a removal take a game with it
# (safe_rm --with-game).
never_moved() {
  case "$(state origin)" in move|moved) return 1 ;; esac
  { [ ! -e "$MOVE_UNDO" ] && [ ! -L "$MOVE_UNDO" ]; } || return 1
  { [ ! -e "$MOVE_RECORD" ] && [ ! -L "$MOVE_RECORD" ]; } && return 0
  # (byte for byte: a shell's $(cat) would drop a NUL)
  [ -f "$MOVE_RECORD" ] && [ ! -L "$MOVE_RECORD" ] && printf 'skipped\n' | cmp -s - "$MOVE_RECORD"
}
# with_game: "--with-game" for never_moved, else nothing (safe_rm's first word)
with_game() { if never_moved; then echo --with-game; fi; }

# backend_alive: a rename helper (gw2om-rename) or another run of this backend that changes things
# is still running (pgrep -f): not this process, nor a subshell of it (same command line, its parent
# this process)
backend_alive() {
  local l
  l="$(pgrep -f 'gw2om-rename' 2>/dev/null || true) $(pgrep -f 'gw2om\.sh (install|rollback|move-in|start-fresh|uninstall)( |$)' 2>/dev/null || true)"
  l=$(printf '%s' "$l" | tr -s ' \n' ',,' | sed 's/^,//; s/,$//')
  [ -n "$l" ] || return 1
  ps -o pid=,ppid= -p "$l" 2>/dev/null | awk -v me="$$" '$1 != me && $2 != me { f = 1 } END { exit !f }'
}

# move_session: the session's lock taken (registry_lock, which a Play needs before it starts Wine) and
# held until move_session_end: SESSION_LOCKED=move, so the registry writes on the way don't let it
# go. Under it, nothing of this app's or 0.1.x's Wine runs (checked again).
move_session() {
  [ -z "$DRY" ] || return 0
  move_idle || die "$IDLE_WHY"
  stop_watcher
  registry_lock || die "A session of Guild Wars 2 is starting or ending, so $APP_NAME doesn't move the game now. Quit the game and Steam, then try again."
  SESSION_LOCKED=move
  move_idle || die "$IDLE_WHY"
}
# move_idle: nothing of this app's or 0.1.x's Wine runs (this app's leftovers are ended); else 1, and
# IDLE_WHY says what runs
move_idle() {
  local l b
  end_leftovers
  l=$(proc_list)
  b=$(busy_of "$l")
  case "$b" in game|steam|installer|session) IDLE_WHY=$(busy_message "$b" "$l"); return 1 ;; esac
  old_busy
  [ "$OLD_BUSY" = none ] || { IDLE_WHY="Something of $OLD_LABEL is running ($OLD_BUSY), so $APP_NAME doesn't move the game now. Quit it, then try again."; return 1; }
}
move_session_end() { [ "${SESSION_LOCKED:-}" != move ] || { SESSION_LOCKED=""; registry_unlock; }; }

# move_recover (lock, with the install lock held): a MOVE_UNDO here belongs to a run that was killed,
# since a running one would hold the lock. Nothing happens while its rename helper or another
# backend run is alive, or Wine runs, here or in 0.1.x (the next start tries again); else under the
# session's lock too: a committed transaction keeps its result; any other is undone (move_undo),
# and what that install made goes, but nothing that holds the game (safe_rm). MOVE_UNDO goes last,
# so a kill in the middle of this runs it again.
MOVE_MADE_NAMES="state install-manifest.json moved-from-0.1 settings.conf dxmt.conf compatdb.rules ReShade reshade-compiler engine bottle dev-switches.conf 0.1-addons"
move_recover() {
  local c created
  [ -z "$DRY" ] && [ -f "$MOVE_UNDO" ] || return 0
  log "a run that was stopped left $MOVE_UNDO"
  if backend_alive; then unlock; die "$APP_NAME is still finishing a move of the game. Try again in a few seconds."; fi
  move_idle || { unlock; die "$IDLE_WHY"; }
  registry_lock || { unlock; die "A session of Guild Wars 2 is starting or ending, so $APP_NAME finishes the stopped move of the game later."; }
  SESSION_LOCKED=move
  move_idle || { move_session_end; unlock; die "$IDLE_WHY"; }
  if move_committed; then
    log "its move was done; it stays"
  else
    move_undo || { move_session_end; unlock; die "A move of Guild Wars 2 didn't finish, and its folder isn't where it left it. $APP_NAME changes nothing until it is: details in $LOGS/install.log."; }
    created=$(undo_key created)
    set -f
    for c in $created; do
      in_list "$c" "$MOVE_MADE_NAMES" || continue
      safe_rm "$APPDIR/$c" && log "removed $c (the stopped install)" || true
    done
    set +f
  fi
  rm -f "$MOVE_UNDO"
  safe_rm --quiet "$MOVE_SNAP"
  move_session_end
}

# move_game: where the folder a move renamed is now: here (this app's bottle), 01 (back in 0.1.x's
# folder: Rollback) or empty (no such move, or the game is gone)
move_game() {
  local o n i
  [ "$(head -1 "$MOVE_RECORD" 2>/dev/null || true)" = moved ] || return 0
  o=$(record_key old) n=$(record_key new) i=$(record_key inode)
  [ -n "$i" ] && move_pair "$o" "$n" "$(record_key game)" || return 0
  # (the recorded inode at the place: another folder there isn't the moved game)
  if [ -d "$n" ] && [ ! -L "$n" ] && [ "$(stat -f %i "$n")" = "$i" ]; then echo here
  elif [ -d "$o" ] && [ ! -L "$o" ] && [ "$(stat -f %i "$o")" = "$i" ]; then echo 01
  fi
}

# old_place: the folder the move renames (Steam's on Steam's route, else the game's), after old_install
old_place() { if [ "$OLD_ROUTE" = steam ]; then echo "$OLD_STEAM"; else echo "$OLD_GAME"; fi; }
# move_target (after old_install): MOVE_SRC, the folder the move renames; MOVE_DST, its place in this
# app's bottle; MOVE_GAME, the game folder's path inside it (empty: the folder is the game's)
move_target() {
  MOVE_SRC=$(old_place) MOVE_GAME=""
  if [ "$OLD_ROUTE" = steam ]; then MOVE_DST=$STEAM_DIR MOVE_GAME=${OLD_GAME#"$OLD_STEAM/"}
  else MOVE_DST="$BOTTLE/drive_c/${OLD_GAME#"$OLD_BOTTLE/drive_c/"}"
  fi
}

# old_install: 0.1.x's install, if it has one to move: its manifest, its bottle, and a complete
# Guild Wars 2 (game_ok) where its state says: in its Steam folder's own library, or on ArenaNet's
# route at its game_dir. OLD_ROUTE, OLD_GAME. (A few stats: status runs it.)
old_install() {
  local route m dir
  OLD_ROUTE="" OLD_GAME=""
  [ -f "$OLD_APPDIR/install-manifest.json" ] && [ -f "$OLD_BOTTLE/system.reg" ] || return 1
  route=$(sed -n 's/^route=//p' "$OLD_APPDIR/state" 2>/dev/null | tail -1)
  case "$route" in
    steam)
      m="$OLD_STEAM/steamapps/appmanifest_$GW2_APPID.acf"
      [ -f "$m" ] || return 1
      dir="$OLD_STEAM/steamapps/common/$(acf "$m" installdir)" ;;
    arenanet)
      dir=$(sed -n 's/^game_dir=//p' "$OLD_APPDIR/state" 2>/dev/null | tail -1)
      case "$dir" in */../*|*/..) dir="" ;; "$OLD_BOTTLE/drive_c/"?*) ;; *) dir="" ;; esac
      [ -n "$dir" ] || dir="$OLD_BOTTLE/drive_c/Program Files/Guild Wars 2" ;;
    *) return 1 ;;
  esac
  case "$dir" in */) return 1 ;; esac
  game_ok "$dir" || return 1
  OLD_ROUTE=$route OLD_GAME=$dir
}

# move_lines (status, settings): old_install, move (yes: the window starts the move), the record,
# 0.1.x's route, and while move=yes what of 0.1.x runs and the sentence the window shows for it
move_lines() {
  local m=no
  if old_install; then
    echo "old_install=yes"
    [ -f "$MANIFEST" ] || [ -d "$BOTTLE" ] || [ -f "$MOVE_RECORD" ] || m=yes
  else
    echo "old_install=no"
  fi
  echo "move=$m"
  echo "move_record=$(head -1 "$MOVE_RECORD" 2>/dev/null || true)"
  echo "move_route=$OLD_ROUTE"
  OLD_BUSY=none OLD_WAIT=""
  [ "$m" != yes ] || old_busy
  echo "move_busy=$OLD_BUSY"
  echo "move_wait=$OLD_WAIT"
  echo "move_game=$(move_game)"
  # (the room a move or Move in needs: the engine and the bottle, as preflight checks; the game
  # moves by a rename)
  echo "move_disk_needed=3000000000"
  echo "rollback_version=$LAST_01"
  echo "rollback_dmg=$LAST_01_DMG"
}

# move_check_old: nothing of 0.1.x runs (before the rename and each tree the move clones, and after
# the last)
move_check_old() {
  old_busy
  [ "$OLD_BUSY" = none ] || die "$OLD_LABEL started while the move ran, so it stopped and undid what it had done. $OLD_WAIT"
}

# move_fail <point>: the sandbox's failure at that step of the move (GW2_ON_MAC_MOVE_FAIL)
move_fail() {
  [ -n "$ROOT" ] && [ "${GW2_ON_MAC_MOVE_FAIL:-}" = "$1" ] || return 0
  die "The move failed at $1 (GW2_ON_MAC_MOVE_FAIL, a test)."
}

# move_inside <dir> <base>: <dir> is a folder inside <base> once links are resolved. A rename and
# cp -R keep a link as a link, so a linked folder in 0.1.x's tree would lead the writes after the
# move (the addons, ReShade's ini) into 0.1.x's files or elsewhere.
move_inside() {
  local d b
  [ -z "$DRY" ] && [ -e "$1" ] || return 0
  d=$(cd "$1" 2>/dev/null && pwd -P) || d=""
  b=$(cd "$2" && pwd -P)
  case "$d/" in "$b/"?*) return 0 ;; esac
  die "$1 leads outside $2 (a link in $OLD_LABEL's folder?), so $APP_NAME doesn't move this install. Start fresh in Settings › Troubleshooting installs anew."
}

# path_under <path> <folder>: <path> is inside <folder> (a case of its own: bash 3.2 can't parse a
# case pattern's parenthesis inside a $(...))
path_under() { case "$1" in "$2/"?*) return 0 ;; esac; return 1; }

# move_links <folder>...: every link in what the move renamed, cloned or kept leads to a file
# inside this app's folder, its whole chain resolved (realpath). A rename and cp -R keep a link as a
# link, and what writes after the move (ReShade's ini, arcdps's renames, the addons, then Steam, the game and ReShade
# themselves) would write through it: into 0.1.x's folders, or into a folder elsewhere that 0.1.x
# links to as well, such as a ReShade folder on another disk. A link to a folder counts as leading
# out wherever it leads (what is in that folder isn't looked through), and so does one that leads
# nowhere.
move_links() {
  local d l p ap bad
  [ -z "$DRY" ] || return 0
  ap=$(cd "$APPDIR" && pwd -P)
  bad=$(for d in "$@"; do
      { [ -e "$d" ] || [ -L "$d" ]; } || continue
      find "$d" -type l 2>/dev/null | while IFS= read -r l; do
        p=$(realpath "$l" 2>/dev/null) || p=""
        [ -n "$p" ] && [ -f "$p" ] && path_under "$p" "$ap" || echo "$l"
      done
    done | head -1) || true
  [ -z "$bad" ] ||
    die "$bad is a link to a folder or out of the files the move brought, so $APP_NAME doesn't move this install: what it writes there would reach $OLD_LABEL's files. Start fresh in Settings › Troubleshooting installs anew."
}

# move_paths <ini>: 0.1.x's folders in it (or in the file it links to), as ReShade's ini spells them (Z:\...\GW2 on Mac, a
# comma doubled), now this app's: its BasePath, IntermediateCachePath (0.1.x's cache folder) and any
# path a player set by hand. A name is replaced where it ends: at a backslash, a quote, a comma,
# a semicolon or the line's end.
move_paths() {
  local f=$1 tmp
  [ -f "$f" ] || return 0
  # (a link: the file it leads to, which move_links has kept inside this app's folder; checked
  # again here, since this is the one write the move makes in a file it didn't create)
  if [ -L "$f" ]; then
    f=$(realpath "$f") || return 1
    path_under "$f" "$(cd "$APPDIR" && pwd -P)" || return 1
  fi
  if [ -n "$DRY" ]; then echo "[dry-run] $OLD_LABEL's folders in $f renamed to this app's"; return 0; fi
  tmp="$f.gw2om-new.$$"
  OA="$(winpath "$OLD_APPDIR")" NA="$(winpath "$APPDIR")" OC="$(winpath "$OLD_CACHE")" NC="$(winpath "$CACHE")" LC_ALL=C awk '
    function rep(s, a, b,   i, o, c) {
      o = ""
      while ((i = index(s, a)) > 0) {
        c = substr(s, i + length(a), 1)
        if (c == "" || c == "\\" || c == "\"" || c == "," || c == ";" || c == "\r") o = o substr(s, 1, i - 1) b
        else o = o substr(s, 1, i - 1 + length(a))
        s = substr(s, i + length(a))
      }
      return o s
    }
    { print rep(rep($0, ENVIRON["OA"], ENVIRON["NA"]), ENVIRON["OC"], ENVIRON["NC"]) }' "$f" >"$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  chmod 644 "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  log "$f: $OLD_LABEL's folders renamed to this app's"
}

# move_reshade: 0.1.x's ReShade folder (its ini, presets, shaders, textures, screenshots) cloned
# into this app's, with the record of the compiler 0.1.x put next to Gw2-64.exe. A ReShade folder
# this app has already (an earlier install's, which Uninstall left) stays as it is, and 0.1.x's
# stays where it is. Then ReShade's two inis name this app's folders (move_paths): else ReShade
# would write into 0.1.x's cache. MOVE_RS: moved, kept or empty.
move_reshade() {
  MOVE_RS=""
  if [ -d "$OLD_APPDIR/ReShade" ]; then
    if [ -e "$RS" ] || [ -L "$RS" ]; then
      say "$APP_NAME's ReShade folder is there already ($RS): it stays, and $OLD_LABEL's stays in $OLD_APPDIR/ReShade"
      MOVE_RS=kept
    else
      clone_tree "$OLD_APPDIR/ReShade" "$RS" "ReShade's folder" ReShade
      MOVE_RS=moved
    fi
  fi
  move_links "$RS"
  if [ -f "$OLD_APPDIR/reshade-compiler" ] && [ ! -e "$RS_COMPILER_RECORD" ]; then
    run cp -p "$OLD_APPDIR/reshade-compiler" "$RS_COMPILER_RECORD"
  fi
  move_paths "$RS/ReShade.ini" || die "$APP_NAME couldn't change ReShade's settings ($RS/ReShade.ini). Try again (details in $LOGS/install.log)."
  move_paths "$GAME_DIR/ReShade.ini" || die "$APP_NAME couldn't change $GAME_DIR/ReShade.ini. Try again (details in $LOGS/install.log)."
}

# install_moved <route>: install move after the engine, the settings (move_settings) and the
# bottle. Steam's route runs Valve's installer first, as for an install (its registry), then 0.1.x's
# Steam folder takes the new one's place.
install_moved() {
  local route=$1 u ou d dst what="" lost files steamline src
  ou="$OLD_BOTTLE/drive_c/users/$WIN_USER"
  [ -n "$DRY" ] || [ "$(bottle_user)" = "$WIN_USER" ] ||
    die "Wine made the new bottle's user $(bottle_user), not $WIN_USER, so $APP_NAME can't move $OLD_LABEL's install into it."
  u="$BOTTLE/drive_c/users/$WIN_USER"
  phase 3
  if [ "$route" = steam ]; then
    install_steam
    move_fail steam
    phase 4
  fi
  step "Your install, from $OLD_LABEL"
  src=$MOVE_SRC dst=$MOVE_DST
  # (from here to the record, the session's lock too: no Play, and no Wine of either app)
  move_session
  if [ "$route" = steam ]; then
    safe_rm "$STEAM_DIR" || die "$APP_NAME couldn't remove the Steam folder Valve's installer made (details in $LOGS/install.log)."
  else
    run mkdir -p "${dst%/*}"
  fi
  move_check "$src" "$dst" "$MOVE_GAME"
  # (the profile's folders are replaced below: the game must not be under them)
  ! path_under "$dst" "$u/AppData" || die "$OLD_LABEL's game folder is inside its profile ($OLD_GAME), so $APP_NAME doesn't move this install. Start fresh in Settings › Troubleshooting installs anew."
  # (the addon files 0.1.x has in the game folder, for a failure and for Rollback)
  addons_links "$OLD_GAME"
  CREATED="$CREATED 0.1-addons"
  addons_save "$OLD_GAME" "$MOVE_ADDONS"
  test_pause move-before-rename
  move_rename "$src" "$dst"
  test_pause move-renamed
  move_fail files
  # (the profile: Steam's files in AppData/Local on Steam's route, the game's settings folder)
  for d in "AppData/Local/Steam" "AppData/Roaming/Guild Wars 2"; do
    [ -d "$ou/$d" ] || continue
    [ "$route" = steam ] || [ "$d" != AppData/Local/Steam ] || continue
    move_check_old
    safe_rm "${u:?}/$d" || die "$APP_NAME kept $u/$d: a game is in it (details in $LOGS/install.log)."
    run mkdir -p "$(dirname "$u/$d")"
    clone_tree "$ou/$d" "$u/$d" "$(basename "$d")'s folder in AppData" "$(basename "$d")"
  done
  move_fail profile
  move_check_old
  move_links "$dst" "$u/AppData/Local/Steam" "$u/AppData/Roaming/Guild Wars 2"
  if [ -z "$DRY" ]; then
    set_state route "$route"
    set_state origin move
    [ "$route" = steam ] || set_state game_dir "$dst"
  fi
  game_state
  [ -n "$DRY" ] || [ -n "$GAME_DIR" ] || die "The game's folder isn't where $OLD_LABEL's Steam says it is. Start fresh in Settings › Troubleshooting installs anew."
  move_inside "$GAME_DIR" "$BOTTLE"
  move_reshade
  move_check_old
  move_fail reshade
  write_manifest
  if [ "$GAME" = yes ] || [ -n "$DRY" ]; then
    if [ "$route" = steam ]; then phase 5; else phase 4; fi
    step "Finishing touches"
    finish_touches
    move_fail finish
  else
    set_state stage waiting_game
  fi
  # (the commit: the record names both places of the renamed folder and its inode. Once it is
  # written the move is done, for the exit handler and move_recover alike (move_committed))
  printf 'moved\nold=%s\nnew=%s\ngame=%s\ninode=%s\n' "$src" "$dst" "$MOVE_GAME" "$( [ -n "$DRY" ] || undo_key inode)" |
    put "$MOVE_RECORD" 644
  test_pause move-done
  # (nothing of this install goes on a failure from here: the commit is written)
  CREATED="" IMPORT_DST=""
  [ -n "$DRY" ] || rm -f "$MOVE_UNDO"
  test_pause move-retired
  move_session_end
  log "install move complete ($src renamed to $dst)"
  if [ "$GAME" != yes ] && [ -z "$DRY" ]; then
    step "Steam opens: it brings Guild Wars 2 up to date"
    launch "$STEAM_EXE" "steam://install/$GW2_APPID"
  fi
  # (what came along: the addons as the game folder has them now)
  arcdps_state
  reshade_state
  [ "$ARC" != on ] || what="arcdps"
  [ "$RSH" != on ] || what="${what:+$what, }ReShade$([ "$MOVE_RS" != moved ] || echo " with your presets")"
  [ "$(uiscale_state)" != on ] || what="${what:+$what, }the larger interface"
  lost="" files="Guild Wars 2" steamline=""
  move_changes
  [ -z "$MOVE_LOST" ] || lost=" $MOVE_LOST"
  if [ "$route" = steam ]; then files="Steam with Guild Wars 2 in its library" steamline=" Steam may ask you to sign in once."; fi
  if [ "$GAME" = yes ] || [ -n "$DRY" ]; then
    echo "@done Your install moved from $OLD_LABEL: $files (moved on this disk, no extra space), your game settings${what:+, your addons as they were ($what)} and your settings.$lost$steamline To play on $OLD_LABEL again, choose Rollback to $LAST_01 in Settings › Troubleshooting. Press Play."
  else
    echo "@done Your install moved from $OLD_LABEL.$lost Steam is starting: it brings the game up to date, and may ask you to sign in once; this window follows it."
  fi
}

# rollback_game (with the install lock held): the folder the move renamed goes back where 0.1.x had
# it, a rename again. Under the session's lock (move_session) and only once the rename is checked
# (move_check: 0.1.x's place free, no link, one volume), this app's addon files in the game folder
# are kept (MOVE_SNAP, for an undo), 0.1.x's put back (MOVE_ADDONS), and the folder renamed, so
# 0.1.x finds its install as on the day of the move, with the game as this app left it. Done when
# MOVE_UNDO goes; a failure or a cancel before that undoes it (on_move_exit).
rollback_game() {
  local o n g
  o=$(record_key old) n=$(record_key new) g=$(record_key game)
  [ -f "$OLD_BOTTLE/system.reg" ] || die "$OLD_LABEL's bottle isn't there any more ($OLD_BOTTLE), so the game stays in $APP_NAME."
  move_session
  move_check "$n" "$o" "$g"
  # (0.1.x's addon files, kept at the move, must be there to go back: without their list, that is a
  # failed restore, and nothing changes)
  [ -n "$DRY" ] || [ -f "$MOVE_ADDONS/list" ] ||
    die "$APP_NAME didn't find $OLD_LABEL's addon files it kept ($MOVE_ADDONS/list), so the game stays here."
  # (the game itself must be in the folder that goes back, its resolved tree on its volume: Steam
  # may have moved it to another library in this app's bottle, and then that holds the only copy)
  [ -n "$DRY" ] || [ -n "$(find "$n" -xdev -type f -iname Gw2.dat -print -quit 2>/dev/null)" ] ||
    die "Guild Wars 2 isn't in the folder that came from $OLD_LABEL any more ($n), so $APP_NAME doesn't give that folder back. Move the game back into $n${g:+/$g} in Steam (Properties › Installed Files › Move install folder), then try again."
  # (this app's addon files are kept for an undo: none may be a link)
  addons_links "$n${g:+/$g}"
  MOVE_MADE=""
  addons_save "$n${g:+/$g}" "$MOVE_SNAP"
  move_journal rollback "$n" "$o" "$g" "$MOVE_SNAP"
  # (if they can't all go back, nothing goes: the undo puts this app's back from its snapshot)
  addons_restore "$n${g:+/$g}" "$MOVE_ADDONS" "$n" || die "$APP_NAME couldn't put back $OLD_LABEL's addon files, so the game stays here (details in $LOGS/install.log)."
  move_rename "$n" "$o"
  test_pause rollback-renamed
  [ -n "$DRY" ] || rm -f "$MOVE_UNDO"
  safe_rm --quiet "$MOVE_SNAP"
  move_session_end
  log "rollback: $n renamed back to $o"
}

# on_move_exit: Rollback's, Move in's and Start fresh's EXIT trap: after a failure or a cancel a
# transaction that isn't done is undone (MOVE_UNDO goes once it is), then the locks go
on_move_exit() {
  local st=$?
  if [ $st -ne 0 ] && [ -z "$DRY" ] && [ -f "$MOVE_UNDO" ]; then
    if move_undo; then rm -f "$MOVE_UNDO"; safe_rm --quiet "$MOVE_SNAP" || true; else log "the renamed folder isn't where it was left; $MOVE_UNDO stays for the next start"; fi
  fi
  move_session_end
  unlock
}

# rollback (Settings › Troubleshooting, Rollback to 0.1.x): rollback_game. This app's install stays
# without the game (status: move_game=01), and the window shows how to go back to 0.1.x and how to
# move the game in again (move-in). Refused while Steam or the game runs here.
cmd_rollback() {
  open_log
  log "---- rollback $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  CREATED=""
  check_not_running
  lock
  trap on_move_exit EXIT
  trap 'exit 143' TERM INT HUP
  [ "$(move_game)" = here ] || die "There is no game moved from $OLD_LABEL in $APP_NAME's bottle, so Rollback changed nothing."
  rollback_game
  echo "@done Guild Wars 2 is back in $OLD_LABEL's folder. To play on it, download GW2 on Mac $LAST_01, quit $APP_NAME, and drag GW2 on Mac $LAST_01 to Applications over it."
}

# move-in (the main window after a rollback): the folder renamed into this app's bottle again, as
# the move did it, under the session's lock to the end: the rename checked, 0.1.x's addon files kept
# (MOVE_ADDONS), the rename, the links checked, ReShade's ini in the game folder naming this app's
# folders, the finishing touches; or on Steam's route with a game Steam hasn't finished, the stage
# set to wait for Steam, which starts once the move-in is done. A failure or a cancel before the
# end renames it back (on_move_exit).
cmd_move_in() {
  local o n g
  open_log
  log "---- move-in $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  CREATED="" MOVE_MADE=""
  check_not_running
  lock
  trap on_move_exit EXIT
  trap 'exit 143' TERM INT HUP
  [ -f "$MANIFEST" ] || die "$APP_NAME is not installed."
  [ "$(move_game)" = 01 ] || die "The game isn't waiting in $OLD_LABEL's folder, so Move in changed nothing."
  o=$(record_key old) n=$(record_key new) g=$(record_key game)
  move_session
  move_check "$o" "$n" "$g"
  addons_links "$o${g:+/$g}"
  addons_save "$o${g:+/$g}" "$MOVE_ADDONS"
  move_journal move-in "$o" "$n" "$g" "$MOVE_ADDONS"
  move_rename "$o" "$n"
  move_links "$n"
  game_state
  [ -n "$DRY" ] || [ -n "$GAME_DIR" ] || die "The game's folder isn't where $APP_NAME's Steam says it is, so it goes back to $OLD_LABEL."
  [ -n "$DRY" ] || [ "$GAME" = yes ] || [ "$(state route)" = steam ] || die "The game in $OLD_LABEL's folder isn't complete, so it goes back there. Let $OLD_LABEL's launcher finish it first."
  move_inside "$GAME_DIR" "$BOTTLE"
  move_paths "$GAME_DIR/ReShade.ini" || die "$APP_NAME couldn't change $GAME_DIR/ReShade.ini. Try again (details in $LOGS/install.log)."
  if [ "$GAME" = yes ] || [ -n "$DRY" ]; then finish_touches; else set_state stage waiting_game; fi
  [ -n "$DRY" ] || rm -f "$MOVE_UNDO"
  move_session_end
  log "move-in: $o renamed to $n"
  if [ "$GAME" = yes ] || [ -n "$DRY" ]; then
    echo "@done Guild Wars 2 moved in from $OLD_LABEL again (on this disk, no extra space). Press Play."
  else
    # (Steam's record says the game isn't complete: Steam brings it up to date, the window follows)
    step "Steam opens: it brings Guild Wars 2 up to date"
    launch "$STEAM_EXE" "steam://install/$GW2_APPID"
    echo "@done Guild Wars 2 moved in from $OLD_LABEL again. Steam is starting: it brings the game up to date; this window follows it."
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
  trap 'safe_rm --quiet "$CHECK_TMP" || true' EXIT
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
  local free b l k f installed=no
  # (a rename that a killed install, Rollback or Move in left open is undone under the install lock,
  # in a process of its own (the lock's owner is its pid), before anything is reported:
  # move_recover. A run that holds the lock is still at work.)
  if [ -f "$MOVE_UNDO" ] && [ -z "$DRY" ]; then /bin/bash "$0" recover >/dev/null 2>&1 </dev/null || true; fi
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
  # (an engine of another release counts: Repair replaces it, engine_installed=old)
  [ -f "$MANIFEST" ] && [ -x "$ENG/bin/wine" ] && [ -f "$BOTTLE/system.reg" ] && installed=yes
  echo "installed=$installed"
  echo "installed_version=$(json_get "$MANIFEST" version)"
  echo "engine_installed=$(if engine_ok; then echo yes; elif engine_old; then echo old; else echo no; fi)"
  dxmt_look "$DXGI/dxmt"
  echo "graphics=$(graphics_state)"
  # (the DXMT Settings asks for, the one in the engine's tree now, and my fork's build)
  echo "dxmt=$(setting dxmt)"
  echo "dxmt_tree=$(dxmt_tree "$DXGI/dxmt")"
  echo "dxmt_version=$DXMT_VERSION"
  echo "dxmt_release=$DXMT_RELEASE"
  echo "dxmt_commit=$DXMT_COMMIT"
  # (the Metal my fork draws with at the next start: 3 or 4, the Metal row)
  echo "metal=$(setting metal)"
  # (my fork's present on Metal 4, metal_present: the game's rule's entry, or the entry and why it
  # stays out)
  b=$(metal_present)
  echo "metal_present=$(printf '%s\n' "$b" | sed -n 's/^in //p')"
  echo "metal_present_out=$(printf '%s\n' "$b" | sed -n 's/^out //p')"
  # (each of my unix libraries: the setting, the set Settings asks for (lib_state), the one in the
  # engine now (mine, engine, other, mix, none) with its commit and, if mine, its Wine release, and
  # my build's commit in this app)
  for k in $UNIX_LIBS; do
    f=$(lib_file "$k")
    echo "$k=$(setting "$k")"
    echo "${k}_ready=$(lib_state "$k")"
    echo "${k}_file=$f"
    echo "${k}_commit=$(lib_commit_of "$k" "$f")"
    echo "${k}_release=$(lib_release_of "$k" "$f")"
    echo "${k}_build=$(lib_commit "$k")"
  done
  # (my Mac driver's win32u.so: whether this app's build has one, and the engine's win32u.so now:
  # mine, engine, other or none)
  unix_lib macdrv
  echo "win32u_bundled=$(in_list win32u.so "$LIB_SET" && echo yes || echo no)"
  echo "win32u_file=$(lib_one win32u.so "$UNIX_DIR/win32u.so")"
  # (FEX the same way: the setting, its state, the FEX in the engine now (mine, engine, mix, other)
  # with its commit, and my build's commit in this app)
  f=$(fex_in_use)
  echo "fex=$(setting fex)"
  echo "fex_ready=$(fex_state)"
  echo "fex_file=$f"
  b=""
  if [ "$f" = mine ]; then b=$(fex_commit); elif [ "$f" = engine ]; then b=$ENGINE_FEX; fi
  echo "fex_commit=$b"
  echo "fex_build=$(fex_commit)"
  # (a development build's switches from dev-switches.conf: those the game's rule has now, and
  # those it leaves out, each with why; both empty in a release build)
  b=$(dev_lines)
  echo "dev_switches=$(printf '%s\n' "$b" | sed -n 's/^in //p' | tr '\n' ' ' | sed 's/ $//')"
  echo "dev_switches_out=$(printf '%s\n' "$b" | sed -n 's/^out //p' | tr '\n' ';' | sed 's/;$//')"
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
  echo "arcdps_dll=$ARC_DLL"
  echo "reshade=$(setting reshade)"
  reshade_lines
  echo "session=$(session_live)"
  # (GW2 on Mac 0.1.x's install, which the window moves into this app at its first start: move=yes,
  # and while something of 0.1.x runs, move_busy and move_wait say what)
  move_lines
}

settings() {
  local k
  echo "installed=$([ -f "$MANIFEST" ] && echo yes || echo no)"
  if session_running; then echo "running=yes"; else echo "running=no"; fi
  echo "route=$(state route)"
  # (reshade_state is the addon's, as for arcdps: reshade_lines)
  for k in $SETTING_KEYS; do
    echo "$k=$(setting "$k")"
    [ "$k" = reshade ] || echo "${k}_state=$(setting_state "$k")"
  done
  echo "uiscale_addon=$(uiscale_state)"
  arcdps_state
  echo "arcdps=$([ "$ARC" = on ] && echo on || echo off)"
  echo "arcdps_state=$ARC"
  echo "arcdps_foreign=$ARC_FOREIGN"
  echo "arcdps_dll=$ARC_DLL"
  reshade_lines
  echo "cpus=$CPU_MAX"
  echo "steam_login=$(steam_remembers_login && echo yes || echo no)"
  # (Troubleshooting's Start fresh: shown over the moved install, origin move or moved, or before
  # the move while 0.1.x has an install)
  echo "old_install=$(old_install && echo yes || echo no)"
  echo "origin=$(state origin)"
  echo "move_record=$(head -1 "$MOVE_RECORD" 2>/dev/null || true)"
  # (Troubleshooting's Rollback: shown while the game a move renamed is in this app's bottle)
  echo "move_game=$(move_game)"
  echo "rollback_version=$LAST_01"
  echo "rollback_dmg=$LAST_01_DMG"
}

cmd_set() {
  local key="${1:-}" value="${2:-}"
  # (arcdps: not kept in settings.conf; the game folder says whether it is on, arcdps_state.
  # reshade: the player's wish is kept there, set_reshade writes it)
  { [ "$key" = arcdps ] && { [ "$value" = on ] || [ "$value" = off ]; }; } || setting_valid "$key" "$value" ||
    { echo "@error Unknown setting: $key=$value"; exit 2; }
  case "$(setting_state "$key")" in off:*) echo "@error $(setting_state "$key" | cut -c5-)"; exit 1 ;; esac
  [ -f "$MANIFEST" ] || die "$APP_NAME is not installed."
  open_log
  log "---- set $key=$value"
  lock
  trap 'unlock' EXIT
  if [ "$key" = arcdps ]; then set_arcdps "$value"; return; fi
  if [ "$key" = reshade ]; then set_reshade "$value"; return; fi
  write_settings "$key" "$value"
  case "$key" in
    fpscap) write_dxmt_conf ;;
    uiscale|uiscale_size|uiscale_sans|uiscale_cinema) sync_uiscale ;;
    retina) apply_registry ;;
    dxmt) apply_engine_files; [ "$(graphics_state)" != other ] || warn "The engine's DXMT is neither its own nor mine. Click Repair." ;;
  esac
  if in_list "$key" "$UNIX_LIBS"; then
    apply_engine_files
    [ "$(lib_state "$key")" != other ] || warn "$(lib_neither "$key")"
  fi
  if [ "$key" = fex ]; then
    apply_engine_files
    [ "$(fex_state)" != other ] || warn "The engine's FEX is neither its own nor mine. Click Repair."
  fi
  # (each process reads the rules and dxmt.conf when it starts; the environment, the registry, the
  # DXMT tree, the unix libraries and FEX are the session's, fixed while Steam runs)
  if session_running && in_list "$key" "ncpu debug retina dxmt $UNIX_LIBS fex"; then
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
# lock: the install lock taken (lock_take), then a rename a killed run left open undone (move_recover)
lock() {
  lock_take
  move_recover
}
lock_take() {
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
  [ "$(cat "$APPDIR/.lock/pid" 2>/dev/null || true)" != "$$" ] || safe_rm --quiet "$APPDIR/.lock"
  unclaim
}

write_manifest() {
  put "$MANIFEST" 644 <<EOF
{
  "app": "$APP_FOLDER",
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
  "winemac_sha256": "$ENGINE_WINEMAC_SHA256",
  "win32u_sha256": "$ENGINE_WIN32U_SHA256",
  "dxmt_d3d11_sha256": "$ENGINE_D3D11_SHA256",
  "winemetal_sha256": "$ENGINE_WINEMETAL_SHA256",
  "fex_dll_sha256": "$ENGINE_FEX_DLL_SHA256",
  "fex_so_sha256": "$ENGINE_FEX_SO_SHA256",
  "dxmt_fork": "$DXMT_VERSION",
  "app_files": ["$(echo $APP_FILES | sed 's/ /", "/g')"],
  "logs": "$LOGS",
  "caches": ["$CACHE"]
}
EOF
}

# --- Install

on_install_exit() {
  local st=$? c kept="" w
  if [ $st -ne 0 ] && [ -z "$DRY" ]; then
    if [ -n "${FETCH_PID:-}" ]; then kill "$FETCH_PID" 2>/dev/null || true; fi
    stop_wine >/dev/null 2>&1 || true
    # (the folder the move renamed goes back first, before the bottle it is in goes; if it can't,
    # everything stays, MOVE_UNDO with it, for the next start)
    # (a move: done once its record is written, and then nothing goes; else the folder goes back
    # first, and if it can't, everything stays)
    if [ -f "$MOVE_UNDO" ] && move_committed; then
      rm -f "$MOVE_UNDO"
      log "install move stopped after it was done (status $st); it stays"
      unlock
      return
    fi
    if ! move_undo; then
      log "install failed (status $st); the renamed folder isn't back where the move found it, so everything stays"
      unlock
      return
    fi
    # all or nothing: what this run created goes again (an earlier engine or bottle stays)
    # (never a folder with a game in it, unless this install was never moved and the game is the
    # one it downloaded or copied itself: safe_rm, never_moved)
    w=""
    [ -n "$MOVING" ] || w=$(with_game)
    for c in $CREATED; do
      if [ -e "$APPDIR/$c" ] || [ -L "$APPDIR/$c" ]; then safe_rm ${w:+"$w"} "${APPDIR:?}/$c" && log "removed $c (install failed)" || kept=yes; fi
    done
    # the game's files this run cloned or copied (and Steam's record of them), if the bottle stays
    if [ -n "${FETCH_PID:-}" ]; then wait "$FETCH_PID" 2>/dev/null || true; fi
    if [ -n "${IMPORT_DST:-}" ] && [ -e "$IMPORT_DST" ]; then safe_rm ${w:+"$w"} "$IMPORT_DST" && log "removed $IMPORT_DST (install failed)" || true; fi
    if [ -n "${IMPORT_ACF:-}" ] && [ -e "$IMPORT_ACF" ]; then rm -f "$IMPORT_ACF"; fi
    safe_rm --quiet "$APPDIR"/*.new || true
    rm -f "$APPDIR"/*.new.$$ 2>/dev/null || true
    [ -n "$kept" ] || rm -f "$MOVE_UNDO"
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
    safe_rm "$BOTTLE" || die "The game's bottle has no system.reg, and a game is in it ($BOTTLE), so $APP_NAME doesn't make it anew. Move the game out of it first (details in $LOGS/install.log)."
    run mkdir -p "$BOTTLE"
    CREATED="$CREATED bottle"
    # (no Gecko and no prompt for Mono: the engine's built-in rules leave Gecko out for every process
    # and Mono out for rundll32.exe)
    wine_do wineboot --init || { stop_wine; die "Wine could not create the bottle (details in $LOGS/install.log)."; }
    stop_wine
    [ -n "$DRY" ] || [ -f "$BOTTLE/user.reg" ] || die "Wine did not create the bottle (details in $LOGS/install.log)."
  else
    say "The game's bottle is there (the game and its settings in it are kept)"
  fi
  [ -f "$SETTINGS" ] || CREATED="$CREATED settings.conf"
  [ -z "$DEV_ON" ] || [ -f "$DEV_FILE" ] || CREATED="$CREATED dev-switches.conf"
  dev_update
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
# (Collect Logs, the session report), with ReShade's keys (reshade_lines), arcdps (on, off) and the
# sha256 of the d3dcompiler_47.dll next to Gw2-64.exe, and each later game start in the session
# (Play with Steam still open, not Show Steam) updates the rules there
launch() {
  local e k f dev
  game_env
  write_rules
  # (a development build's switches: those that stay out, once in the log; those in, for
  # session.env)
  dev=$(dev_lines)
  if [ -n "$DRY" ]; then
    echo "[dry-run] environment:"; for e in "${E[@]}"; do printf '[dry-run]   %s\n' "$e"; done
    rules_text | sed 's/^/[dry-run] rule /'
    printf '%s\n' "$dev" | sed -n 's/^out /[dry-run] dev-switches.conf leaves out /p'
    echo "[dry-run] wine $*"
    return
  fi
  [ -z "$dev" ] || log "dev-switches.conf: in the game's rule: $(printf '%s\n' "$dev" | sed -n 's/^in //p' | tr '\n' ' ')"
  printf '%s\n' "$dev" | sed -n 's/^out //p' | while IFS= read -r e; do log "dev-switches.conf: left out $e"; done
  wine_allowed
  mkdir -p "$LOGS"
  if ! session_running; then
    rotate_logs
    { echo "STARTED=$(date '+%F %T')"; echo "APP=$VERSION"; echo "ROUTE=$(state route)"
      echo "ENGINE=$ENGINE_NAME"; echo "ENGINE_WINE=$ENGINE_WINE"; echo "ENGINE_FEX=$ENGINE_FEX"; echo "ENGINE_DXMT=$ENGINE_DXMT"
      # (the DXMT this session loads: the engine's tree as it is now)
      echo "DXMT_TREE=$(dxmt_tree "$DXGI/dxmt")"; echo "DXMT_FORK=$DXMT_VERSION"
      # (each unix library the session loads: <file> <mine|engine|other|none> <commit> <sha256>,
      # the sha256 of the file as it is in the engine)
      for k in $UNIX_LIBS; do
        unix_lib "$k"
        f=$(lib_file "$k")
        echo "LIB_$k=$LIB $f $(lib_commit_of "$k" "$f") $(sha256 "$UNIX_DIR/$LIB" 2>/dev/null || true)"
      done
      # (and my Mac driver's other file, win32u.so: <mine|engine|other|none> <sha256>)
      unix_lib macdrv
      echo "LIB_win32u=win32u.so $(lib_one win32u.so "$UNIX_DIR/win32u.so") $(sha256 "$UNIX_DIR/win32u.so" 2>/dev/null || true)"
      # (the FEX it loads: mine <commit> <sha256 of xtajit64.dll in the engine>, or engine; Play
      # starts no session on anything else)
      if [ "$(fex_in_place)" = mine ]; then
        echo "LIB_fex=mine $(fex_commit) $(sha256 "$FEX_DIR/aarch64-windows/xtajit64.dll")"
      else
        echo "LIB_fex=$(fex_in_place)"
      fi
      for k in $SETTING_KEYS; do echo "SETTING_$k=$(setting "$k")"; done
      # (ReShade and arcdps as the session starts with them: the session report's ReShade line)
      reshade_lines; arcdps_state; echo "arcdps=$([ "$ARC" = on ] && echo on || echo off)"; echo "arcdps_dll=$ARC_DLL"

      echo "d3dcompiler_47=$([ -z "$GAME_DIR" ] || [ ! -f "$GAME_DIR/d3dcompiler_47.dll" ] || sha256 "$GAME_DIR/d3dcompiler_47.dll")"
      printf '%s\n' "${E[@]}"
      dev_session_line "$dev"
      sed 's/^/RULE=/' "$RULES"; } >"$LOGS/session.env"
    printf '%s\n' "${E[@]}" | shasum | cut -c1-12 >"$LOGS/session.key"
  elif [ -f "$LOGS/session.env" ] && { [ "$1" = "${GAME_EXE:-}" ] || in_list -applaunch "$*"; }; then
    # (a game start in a running session, with Steam still open: this start's rules and dev
    # switches, the rest as the session started)
    { sed -e '/^RULE=/d' -e '/^DEV_SWITCHES=/d' -e '/^DEV_SWITCHES_OUT=/d' "$LOGS/session.env"; dev_session_line "$dev"; sed 's/^/RULE=/' "$RULES"; } >"$LOGS/session.env.new.$$"
    mv -f "$LOGS/session.env.new.$$" "$LOGS/session.env"
  fi
  echo "=== $(date '+%F %T') $*" >>"$LOGS/wine.log"
  if [ -n "${LAUNCH_WAIT:-}" ]; then
    # (the caller follows it: LAUNCH_PID is the process that becomes Wine; neither lock goes with it)
    ( cd "$BOTTLE" && exec env -u WINELOADER -u WINESERVER -u WINEDLLPATH -u DYLD_FALLBACK_LIBRARY_PATH "${COMPATDB_UNSET[@]}" "${E[@]}" \
        nohup "$ENG/bin/wine" "$@" </dev/null >>"$LOGS/wine.log" 2>&1 8>&- 9>&- ) &
    LAUNCH_PID=$!
  else
    ( cd "$BOTTLE" && env -u WINELOADER -u WINESERVER -u WINEDLLPATH -u DYLD_FALLBACK_LIBRARY_PATH "${COMPATDB_UNSET[@]}" "${E[@]}" \
        nohup "$ENG/bin/wine" "$@" </dev/null >>"$LOGS/wine.log" 2>&1 9>&- & )
  fi
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
open_lock() { [ ! -d "$WATCH_LOCK" ] || safe_rm --quiet "$WATCH_LOCK"; exec 9>>"$WATCH_LOCK"; }
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
  local route=${1:-} setup=${2:-} want src="" with_settings=yes moving="" a
  CREATED="" FETCH_PID="" IMPORT_DST="" IMPORT_ACF="" MOVE_MADE="" MOVING=""
  # a first install's state and manifest go too if it fails
  [ -f "$MANIFEST" ] || CREATED="state install-manifest.json"
  case "$route" in steam|arenanet|import|move) ;; *) echo "@error Usage: gw2om.sh install steam | install arenanet <Gw2Setup-64.exe> | install import <game folder> [--no-settings] | install move"; exit 2 ;; esac
  if [ "$route" = move ]; then
    old_install || { echo "@error There is no $OLD_LABEL install to move: $OLD_APPDIR has no bottle with a complete Guild Wars 2 in it."; exit 2; }
    old_busy
    [ "$OLD_BUSY" = none ] || { echo "@error $OLD_WAIT"; exit 1; }
    # (the move renames 0.1.x's Steam or game folder, so it must be a folder on this app's disk:
    # else nothing is written at all)
    src=$(old_place) a="$APPDIR"
    while [ ! -d "$a" ] && [ "$a" != "$H" ] && [ "$a" != / ]; do a=${a%/*}; done
    if ! no_link "$src" || ! no_link "$a" || ! same_disk "$src" "$a"; then
      echo "@error $OLD_LABEL's $([ "$OLD_ROUTE" = steam ] && echo "Steam folder" || echo "game folder") is on another disk than $APP_NAME's folder, or reached through a link ($src). $APP_NAME moves the game only by renaming it on one disk, never by copying it, so nothing changed. Start fresh in Settings › Troubleshooting installs anew."
      exit 1
    fi
    src=""
    moving=yes MOVING=yes route=$OLD_ROUTE
  fi
  if [ "$route" = import ]; then
    [ "${3:-}" != --no-settings ] || with_settings=no
    src=$(game_dir_of "$setup") || { echo "@error There is no Guild Wars 2 in ${setup:-that folder} (Gw2-64.exe and a Gw2.dat of more than 1 GB)."; exit 2; }
    case "$src/" in "$BOTTLE/"*) echo "@error That is $APP_NAME's own copy of the game."; exit 2 ;; esac
    route=$(game_route_of "$src")
    if game_runs_anywhere; then echo "@error Guild Wars 2 is running. Quit it first (in every app), so its files don't change while they are copied."; exit 1; fi
  fi
  if [ "$route" = arenanet ] && [ -z "$src" ] && [ -z "$moving" ]; then
    [ -n "$setup" ] || { echo "@error Drop Gw2Setup-64.exe from ArenaNet's site first."; exit 2; }
    want=$(cmd_check_setup "$setup") || true
    want=$(echo "$want" | tail -1)
    case "$want" in "@done "*) ;; *) echo "$want"; exit 1 ;; esac
  fi
  open_log
  log "---- install $route${src:+ import $src}${moving:+ move from $OLD_GAME} $VERSION (engine $ENGINE_NAME) root=${ROOT:-/} dry=${DRY:-0}"
  phase 1
  step "Checking your Mac"
  preflight ${src:+import}${moving:+import}
  lock
  # (a move goes only into a folder without an install, where no move or Start fresh happened
  # before: checked under the lock, before the rollback is armed, which would stop Wine in an
  # install that isn't the move's)
  if [ -n "$moving" ] && { [ -f "$MANIFEST" ] || [ -d "$BOTTLE" ] || [ -f "$MOVE_RECORD" ]; }; then
    unlock
    if [ -f "$MOVE_RECORD" ]; then
      echo "@error $APP_NAME doesn't move $OLD_LABEL's install again: $([ "$(head -1 "$MOVE_RECORD")" = skipped ] && echo "Start fresh was chosen here" || echo "it was moved here before") ($MOVE_RECORD)."
    else
      echo "@error $APP_NAME has an install of its own already, so it doesn't move $OLD_LABEL's."
    fi
    exit 1
  fi
  trap on_install_exit EXIT
  trap 'exit 143' TERM INT HUP   # Cancel in the app: roll back through the EXIT trap
  # (what a move creates in the app's folder is all it removes if it fails, a ReShade folder
  # Uninstall left included; the record of the move too, written last)
  if [ -n "$moving" ]; then
    CREATED="state install-manifest.json moved-from-0.1"
    # (not .session.lock: a lock file stays, held or not)
    for c in settings.conf dxmt.conf compatdb.rules ReShade reshade-compiler; do
      [ -e "$APPDIR/$c" ] || [ -L "$APPDIR/$c" ] || CREATED="$CREATED $c"
    done
    # (MOVE_UNDO from the first write on: what this move makes and will make, for the next start
    # if this run is killed before it is done; the rename joins it, move_rename)
    MOVE_MADE=$CREATED
    for c in engine bottle dev-switches.conf 0.1-addons; do
      [ -e "$APPDIR/$c" ] || [ -L "$APPDIR/$c" ] || MOVE_MADE="$MOVE_MADE $c"
    done
    move_target
    [ -n "$DRY" ] || { mkdir -p "$APPDIR"; move_journal install "$MOVE_SRC" "$MOVE_DST" "$MOVE_GAME" "$MOVE_ADDONS"; }
  fi
  [ -n "$DRY" ] || mkdir -p "$APPDIR"
  step "The Wine engine"
  install_engine
  apply_engine_files
  move_fail engine
  phase 2
  step "The game's own bottle"
  if [ -n "$moving" ]; then
    say "Your settings from $OLD_LABEL ($OLD_APPDIR/settings.conf)"
    move_settings
    move_fail settings
  fi
  install_bottle
  if [ -n "$moving" ]; then
    move_fail bottle
    install_moved "$route"
    return
  fi
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
  say "The shader cache: $(dxmt_cache) (DXMT fills it while you play)"
  run mkdir -p "$(dxmt_cache)"
  sync_uiscale
  sync_reshade
  sync_arcdps
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

# Repair: the engine (unpacked again if it isn't the expected one, or its DXMT tree, one of my
# unix libraries or FEX is neither its own nor mine), the DXMT tree and the files Settings asks for, the
# bottle's settings; Steam again if it is gone; the game and settings stay
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
  if engine_ok && { [ "$(graphics_state)" = other ] || libs_other || { [ "$ENGINE_CHECKS" = 1 ] && ! engine_matches "$ENG"; }; }; then
    warn "The engine's files changed; unpacking the engine again"
    install_engine force
  else
    install_engine
  fi
  apply_engine_files
  phase 2
  step "The game's own bottle"
  install_bottle
  phase 3
  # (not after Rollback: Steam's folder is in 0.1.x's bottle, and Move in brings it back)
  if [ "$(state route)" = steam ] && [ "$(move_game)" != 01 ]; then install_steam; fi
  phase 5
  step "Finishing touches"
  run mkdir -p "$(dxmt_cache)"
  sync_uiscale
  apply_registry
  write_manifest
  # (last: what it can't download fails the repair after the rest is done)
  sync_reshade download
  sync_arcdps
  log "repair complete"
  echo "@done Repaired: the engine and the bottle's settings are set up again. The game draws with $(dxmt_label "$(dxmt_in_use)")$(for k in $UNIX_LIBS; do printf ', with %s' "$(lib_label "$k" "$(lib_in_use "$k")")"; done), and runs on $(fex_label "$(fex_in_use)")."
}
# libs_other: one of my unix libraries or FEX has lost the engine's own file (lib_state or
# fex_state other)
libs_other() {
  local k
  for k in $UNIX_LIBS; do [ "$(lib_state "$k")" != other ] || return 0; done
  [ "$(fex_state)" = other ]
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
  apply_engine_files
  echo "@done The engine was unpacked again."
}

cmd_reset_shaders() {
  open_log
  log "---- reset-shaders"
  case "$(busy_of "$(proc_list)")" in game) die "Quit Guild Wars 2 first." ;; esac
  if [ -d "$DXMT_CACHE_ROOT" ] || [ -d "$FORK_CACHE_BASE" ]; then
    safe_rm "$DXMT_CACHE_ROOT" "$FORK_CACHE_BASE"
    run mkdir -p "$(dxmt_cache)"
  fi
  # (ReShade's compiled effects: emptied, the folder kept, since ReShade uses %TEMP% without it)
  if [ -d "$RS_CACHE" ]; then
    safe_rm "$RS_CACHE"
    run mkdir -p "$RS_CACHE"
    echo "@done DXMT's and ReShade's caches for the game are empty. The next sessions build them again."
    return 0
  fi
  echo "@done DXMT's caches for the game are empty. The next sessions build them again."
}

cmd_play() {
  local key k
  open_log
  log "---- play $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  ! { [ -f "$MANIFEST" ] && engine_old; } ||
    die "The engine here is $(engine_label "$(cat "$ENG/.gw2om-source" 2>/dev/null || true)"), and this version of $APP_NAME runs on $ENGINE_TITLE. Click Repair to put it in place."
  [ -f "$MANIFEST" ] && engine_ok || [ -n "$DRY" ] || die "$APP_NAME is not installed. Install it first."
  game_state
  # (an install that waits for Steam's download, a move's too, with no Steam running: Play starts
  # Steam on the game's install page, and the window follows the download)
  # (not in a dry run, which shows what a Play of the finished install would do, as before)
  if [ -z "$DRY" ] && [ "$(state stage)" = waiting_game ] && [ "$(state route)" = steam ] && [ "$GAME" != yes ] && [ "$(move_game)" != 01 ]; then
    # (under the session's lock, as a Rollback takes it: the stage, the route, Steam in this
    # bottle, the game and Wine checked again there. Steam doesn't inherit the lock, which goes once
    # this engine's Wine shows, so a Rollback after it sees Steam running)
    [ -n "$DRY" ] || registry_lock || die "$APP_NAME is moving the game or a session is starting. Try again in a few seconds."
    game_state
    { [ "$(state stage)" = waiting_game ] && [ "$(state route)" = steam ] && [ "$GAME" != yes ] &&
      [ "$(move_game)" != 01 ] && [ -f "$STEAM_DIR/steam.exe" ]; } ||
      { registry_unlock; die "Steam or the game isn't where it was a moment ago (Rollback?). Nothing started."; }
    k=$(busy_of "$(proc_list)")
    case "$k" in
      steam) registry_unlock; echo "@done Steam is running: it is bringing Guild Wars 2 up to date."; return 0 ;;
      game|installer|session) registry_unlock; die "$(busy_message "$k" "$(proc_list)")" ;;
    esac
    # (a starter that keeps the session's lock, on its fd 8, until this engine's Steam or wineserver
    # shows, or the process that becomes Wine has ended and is reaped. At LAUNCH_POLLS (2 minutes)
    # that process gets SIGKILL and is reaped. Every way out of the starter, a failure included,
    # runs that same cleanup (its EXIT trap, whose kill and wait may fail), so the lock never goes
    # while a launch is pending, a Play killed meanwhile included. launch runs with set -e, so a
    # failed write before or after the fork ends the starter with an error; only the watching
    # after it runs with set -e off. Wine itself doesn't get the lock: Steam would hold
    # it for its whole run, and the next Play needs it. A start that shows nothing is a failure.)
    if [ -z "$DRY" ]; then
      ( LAUNCH_WAIT=yes LAUNCH_PID="" seen=""
        trap '[ -n "$seen" ] || [ -z "$LAUNCH_PID" ] || { kill -KILL "$LAUNCH_PID" 2>/dev/null || true; wait "$LAUNCH_PID" 2>/dev/null || true; }' EXIT
        launch "$STEAM_EXE" "steam://install/$GW2_APPID"
        set +e
        [ -n "$LAUNCH_PID" ] || exit 1
        k=0
        while [ $k -lt "$LAUNCH_POLLS" ]; do
          case "$(busy_of "$(proc_list)")" in steam|session) seen=yes; exit 0 ;; esac
          # (ended, a zombie until reaped: what it started would show by now)
          case "$(ps -o stat= -p "$LAUNCH_PID" 2>/dev/null)" in
            ""|Z*) case "$(busy_of "$(proc_list)")" in steam|session) seen=yes; exit 0 ;; esac; exit 1 ;;
          esac
          sleep 0.1; k=$((k + 1))
        done
        exit 1 ) </dev/null >/dev/null 2>&1 &
      k=0; wait $! || k=$?
      registry_unlock
      [ "$k" = 0 ] || die "Steam didn't start (details in $LOGS/wine.log). Try Play again."
    else
      launch "$STEAM_EXE" "steam://install/$GW2_APPID"
    fi
    echo "@done Steam is starting: it finishes the game's download, and this window follows it."
    return 0
  fi
  [ "$(state stage)" = finished ] || [ -n "$DRY" ] || die "Guild Wars 2 is not installed yet."
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
  # (the first Play after a move from 0.1.x shows Steam's window: its login came along, but Steam
  # may ask for it once in the new bottle, and a hidden window would wait for it unseen)
  if [ "$route" = steam ]; then
    if [ "$(setting steambg)" = on ] && steam_remembers_login && [ "$(state origin)" != move ]; then silent=-silent window=hidden; else window=shown; fi
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
    # (the game checked again under the session's lock: a Rollback holds it while it moves the game)
    game_state
    [ "$GAME" = yes ] || die "Guild Wars 2 is not in the bottle any more. Rollback may have given it back to $OLD_LABEL."
  fi
  # This Play's own session (it holds the session's lock: no other Play, session or registry write
  # until its watcher takes over), with no Wine of the bottle running: the manifest follows this
  # version, a development build's switches (dev_update), ReShade's and arcdps's files
  # (sync_reshade, sync_arcdps), then the registry, the DXMT tree, my unix libraries and DXMT's
  # options. A Play that joined a session changes nothing; without the session
  # helper the registry and the engine's files wait.
  if [ "$fresh" = yes ] && [ -z "$DRY" ]; then SESSION_LOCKED=yes; fi
  if { [ "$fresh" = yes ] || [ -n "$DRY" ] || [ ! -x "$LOCKER" ]; } && ! session_running; then
    [ "$(json_get "$MANIFEST" version)" = "$VERSION" ] || [ -n "$DRY" ] || write_manifest
    dev_update
    sync_reshade
    sync_arcdps
    apply_registry
    apply_engine_files
    write_dxmt_conf
  fi
  dxmt_look "$DXGI/dxmt"
  if [ -z "$DRY" ]; then
    # (whatever the syncs above did or skipped: ReShade never starts looking for a missing arcdps)
    proxy_safe || die "ReShade's settings ($RS/ReShade.ini) point it at arcdps where arcdps isn't, and the game would have no Direct3D 11. Click Repair (with the game and Steam closed)."
    case "$(graphics_state)" in
      yes) ;;
      switch) echo "@notice Steam is still running with $(dxmt_label "$(dxmt_in_use)"); quit Steam to switch to $(dxmt_label "$(setting dxmt)")." ;;
      *) warn "The engine's DXMT is neither its own nor mine. Click Repair." ;;
    esac
    # (winemac.so and win32u.so of two builds never load together: no session on a mix, nor on
    # another build of my Mac driver, whose win32u.so nothing can prove is its pair: an earlier
    # version of the app may have been cut short between the two)
    for k in $UNIX_LIBS; do
      unix_lib "$k"
      case "$(lib_state "$k")/$(lib_file "$k")" in
        other/mix) die "The engine's ${LIB_FILES// / and } are a mix of mine and its own. Click Repair." ;;
        switch/mix) die "The engine's ${LIB_FILES// / and } are a mix of mine and its own, a switch cut short. Quit Steam and click Play again to finish it." ;;
        other/other) [ "$LIB_FILES" = "$LIB" ] || die "The engine's ${LIB_FILES// / and } are neither its own nor mine. Click Repair."
          warn "$(lib_neither "$k")" ;;
        switch/other) [ "$LIB_FILES" = "$LIB" ] || die "The engine's $LIB is another build of mine, and nothing proves its win32u.so is that build's. Quit Steam and click Play again to put this build's in."
          echo "@notice Steam is still running with $(lib_label "$k" "$(lib_in_use "$k")"); quit Steam to switch to $(lib_label "$k" "$(lib_want "$k")")." ;;
        switch/*) echo "@notice Steam is still running with $(lib_label "$k" "$(lib_in_use "$k")"); quit Steam to switch to $(lib_label "$k" "$(lib_want "$k")")." ;;
        other/*) warn "$(lib_neither "$k")" ;;
      esac
    done
    # (FEX runs every instruction of the game: never a session on a mix of two builds' files)
    case "$(fex_state)/$(fex_in_place)" in
      */mix) die "The engine's FEX files are a mix of mine and its own. Click Repair." ;;
      */other) die "The engine's FEX is neither its own nor mine. Click Repair." ;;
      switch/*) echo "@notice Steam is still running with $(fex_label "$(fex_in_place)"); quit Steam to switch to $(fex_label "$(fex_want)")." ;;
    esac
  fi
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
    [ "$(state origin)" != move ] || set_state origin moved
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
# display's rate (58 instead of 60); Unlimited with vsync keeps a steady 60. That steady 60 is my
# DXMT fork's display sync, so no hint while the Vsync row is off. Sets LIMIT (the Frame Limiter's
# value, or empty) and LIMIT_HINT (yes|no). The game's settings file is only read.
limiter_state() {
  local gfx vsync
  gfx="$BOTTLE/drive_c/users/$(bottle_user)/AppData/Roaming/Guild Wars 2/GFXSettings.Gw2-64.exe.xml"
  LIMIT=$(sed -n 's/.*<OPTION Name="frameLimit"[^>]*Value="\([^"]*\)".*/\1/p' "$gfx" 2>/dev/null | head -1 || true)
  vsync=$(sed -n 's/.*<OPTION Name="verticalSync"[^>]*Value="\([^"]*\)".*/\1/p' "$gfx" 2>/dev/null | head -1 || true)
  LIMIT_HINT=no
  if [ -n "$LIMIT" ] && [ "$LIMIT" != unlimited ] && [ "$vsync" = true ] && [ "$(setting vsync)" = on ]; then LIMIT_HINT=yes; fi
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
  open_log
  log "---- uninstall $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  phase 1
  step "Stopping the game's Wine"
  check_not_running
  lock
  # (the folder itself goes too once empty)
  trap 'unlock; rmdir "$APPDIR" 2>/dev/null || true' EXIT
  [ "$(move_game)" != here ] ||
    die "The game in $APP_NAME's bottle is the one moved from $OLD_LABEL, and its only copy. Choose Rollback to $LAST_01 in Settings › Troubleshooting first; then Uninstall removes the rest."
  # (the game goes with the bottle only in an install that was never moved: never_moved)
  UNINSTALL_WITH=$(with_game)
  uninstall_files
}

# uninstall_files: Uninstall's removal, with the install lock held (cmd_uninstall, Start fresh)
uninstall_files() {
  local c
  stop_watcher
  [ -n "$DRY" ] || stop_wine
  phase 2
  step "Removing the bottle (Steam and the game in it)"
  # (never with the game a move renamed in it: safe_rm)
  if [ -d "$BOTTLE" ]; then
    safe_rm ${UNINSTALL_WITH:+"$UNINSTALL_WITH"} "$BOTTLE" ||
      die "$APP_NAME kept its bottle ($BOTTLE): a game is in it and this install came from $OLD_LABEL's, or another volume is mounted inside it. After a move, choose Rollback to $LAST_01 in Settings › Troubleshooting first, or move the game out by hand (details in $LOGS/install.log)."
  fi
  phase 3
  step "Removing the engine, the settings and caches"
  for c in $APP_FILES; do
    if [ -e "$APPDIR/$c" ]; then safe_rm ${UNINSTALL_WITH:+"$UNINSTALL_WITH"} "${APPDIR:?}/$c" || die "$APP_NAME kept $APPDIR/$c: a game is in it (details in $LOGS/install.log)."; fi
  done
  # (DXMT's caches are in it: $CACHE/dxmt)
  if [ -d "$CACHE" ]; then safe_rm "$CACHE" && say "Removed the caches, DXMT's with them ($CACHE)" || true; fi
  log "uninstall complete"
  # (the ReShade folder holds the player's presets: it stays)
  if [ -d "$RS" ]; then
    say "The ReShade folder stays: $RS"
    echo "@done $APP_NAME is removed, with the bottle and the game in it. Logs stay in $LOGS, and your ReShade presets and shaders in $RS."
    return 0
  fi
  echo "@done $APP_NAME is removed, with the bottle and the game in it. Logs stay in $LOGS."
}

# start-fresh [--before-move|--moved] (Settings › Troubleshooting): the move from 0.1.x doesn't
# start by itself any more (MOVE_RECORD skipped), and the install it moved goes first, as Uninstall
# removes it; the window then shows the install choices. The intent is what I confirmed:
# --before-move while nothing was installed (if the move has finished since, nothing changes),
# --moved over the moved install (state origin move or moved: never another install), whose game goes
# back to 0.1.x first, as Rollback does it. One install lock covers the check, the rollback,
# Uninstall's removal (uninstall_files) and the record, so nothing installs or moves in between;
# while the game or Steam runs nothing changes. 0.1.x's install stays as it was on the day of the
# move, with its game as this app left it; the install choices still list its game.
cmd_start_fresh() {
  local want=${1:-} have=no back=""
  open_log
  log "---- start-fresh $want $VERSION root=${ROOT:-/} dry=${DRY:-0}"
  CREATED=""
  check_not_running
  lock
  trap on_move_exit EXIT
  trap 'exit 143' TERM INT HUP
  if [ -f "$MANIFEST" ] || [ -d "$BOTTLE" ]; then have=yes; fi
  [ -n "$want" ] || { if [ "$have" = yes ]; then want=--moved; else want=--before-move; fi; }
  if [ "$want" = --before-move ] && [ "$have" = yes ]; then
    die "The move from $OLD_LABEL has finished meanwhile, so Start fresh changed nothing. To remove the moved install, choose Start fresh again."
  fi
  if [ "$have" = yes ]; then
    case "$(state origin)" in move|moved) ;; *) die "This install isn't the one moved from $OLD_LABEL, so Start fresh leaves it. Uninstall removes it." ;; esac
    case "$(move_game)" in
      here)
        rollback_game
        back=" Guild Wars 2 went back to $OLD_LABEL's folder first." ;;
      01) ;;
      *)
        # (no record of where the game is, or one this app can't read: it can't be given back)
        die "$APP_NAME can't give the game back to $OLD_LABEL: $MOVE_RECORD doesn't name the folder it moved. Start fresh changed nothing." ;;
    esac
    uninstall_files
  fi
  [ -n "$DRY" ] || mkdir -p "$APPDIR"
  echo skipped | put "$MOVE_RECORD" 644
  log "start fresh: $OLD_LABEL's install doesn't move by itself any more"
  echo "@done $APP_NAME starts fresh: choose how to install Guild Wars 2 in the main window.$back $OLD_LABEL's game files are under Game files I already have."
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

# vmmap: the game's memory as macOS's vmmap reads it, for FEX's code buffers (the process's only
# regions that are rwx/rwx; how many says how often FEX threw its code away) and the footprint.
# Only for this bottle's Gw2-64.exe, proc_list's game. vmmap stops the game while it reads it, so
# it runs only when I ask: this command, or Collect Logs. It writes $LOGS/vmmap-<date>-<time>.txt:
#   Gw2-64.exe pid <pid>, running <s> s, vmmap took <s> s (the game stood still for at most that long)
# then vmmap's header through "Physical footprint (peak)", the region list's column line with its
# rwx/rwx regions only, and the summary from "==== Summary" on; or a line "vmmap failed …". A vmmap
# that hasn't finished after VMMAP_TIMEOUT s gets TERM, and KILL 5 s later, so Collect Logs always
# ends; I don't know whether macOS lets the game go on at once when vmmap dies while it holds it
# stopped. In a sandbox the vmmap is $ROOT/bin/vmmap (a test's), and without one nothing runs.
VMMAP=/usr/bin/vmmap
VMMAP_TIMEOUT=60
VMMAP_GRACE=5
if [ -n "$ROOT" ]; then VMMAP="$ROOT/bin/vmmap" VMMAP_TIMEOUT="${GW2_ON_MAC_VMMAP_TIMEOUT:-$VMMAP_TIMEOUT}"; fi
cmd_vmmap() {
  local pid secs f t took vp wd st=0
  pid=$(proc_list | awk '$1 == "game" { print $2; exit }')
  [ -n "$pid" ] || { echo "@done Guild Wars 2 isn't running, so there is no vmmap to take."; return 0; }
  [ -x "$VMMAP" ] || die "No $VMMAP to run."
  # (ps's elapsed time: [[dd-]hh:]mm:ss)
  secs=$(ps -o etime= -p "$pid" 2>/dev/null | awk '{ n = split($1, a, /[-:]/); s = a[n] + 60 * a[n - 1]
    if (n > 2) s += 3600 * a[n - 2]; if (n > 3) s += 86400 * a[n - 3]; print s }')
  mkdir -p "$LOGS"
  f="$LOGS/vmmap-$(date +%Y%m%d-%H%M%S).txt"
  t=$(mktemp -d)
  "$VMMAP" "$pid" >"$t/out" 2>"$t/err" </dev/null &
  vp=$!
  # (the deadline, as collect-logs.sh's gpu_errors has it: the mark says it ran out of time, and goes
  # again if the TERM finds no vmmap to end)
  ( sleep "$VMMAP_TIMEOUT" && : >"$t/timeout" && { kill "$vp" || { rm -f "$t/timeout"; exit 0; }; } &&
    sleep "$VMMAP_GRACE" && kill -KILL "$vp" ) </dev/null >/dev/null 2>&1 &
  wd=$!
  TIMEFORMAT=%R
  { time wait "$vp"; } 2>"$t/time" || st=$?
  # vmmap has ended: end the watchdog wherever it is, so it never signals that pid again
  kill -STOP "$wd" 2>/dev/null || true
  pkill -KILL -P "$wd" 2>/dev/null || true
  kill -KILL "$wd" 2>/dev/null || true
  wait "$wd" 2>/dev/null || true
  took=$(tail -1 "$t/time")
  { echo "Gw2-64.exe pid $pid, running ${secs:-?} s, vmmap took $took s (the game stood still for at most that long)"
    if [ -e "$t/timeout" ]; then
      echo "vmmap failed: it hadn't finished after $VMMAP_TIMEOUT s, so it was ended"
    elif [ "$st" != 0 ]; then
      echo "vmmap failed with status $st: $(head -3 "$t/err" | tr '\n' ' ')"
    else
      # (a header without the peak line ends at 40 lines: never the whole region list)
      LC_ALL=C awk '
        !head { print; if (/^Physical footprint \(peak\):/ || NR >= 40) head = 1; next }
        /^==== Summary/ { summary = 1; print "" }
        summary { print; next }
        /^REGION TYPE/ { print ""; print; next }
        / rwx\/rwx / { print }' "$t/out"
    fi
  } >"$f"
  [ ! -e "$t/timeout" ] || { safe_rm --quiet "$t" || true; die "vmmap hadn't finished after $VMMAP_TIMEOUT s, so it was ended (see $f)."; }
  safe_rm --quiet "$t" || true
  [ "$st" = 0 ] || die "vmmap failed with status $st (see $f)."
  echo "@done $f"
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
  start-fresh) shift; cmd_start_fresh "$@" ;;
  rollback) cmd_rollback ;;
  recover) open_log; lock; unlock ;;
  move-in) cmd_move_in ;;
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
  reshade) shift; cmd_reshade "$@" ;;
  rules) rules_text; [ ! -f "$RULES_LOCAL" ] || cat "$RULES_LOCAL" ;;
  vmmap) cmd_vmmap ;;
  *) sed -n '2,/^# Environment/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
