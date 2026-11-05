# GW2 on Mac

A small macOS app that sets up [Guild Wars 2](https://www.guildwars2.com) on Apple silicon and
starts it. It installs the game, through **Steam** or **ArenaNet's own installer**, or brings in
the **game files the Mac already has** (another Wine app's install, cloned without a download), into
a Wine engine and bottle of its own (CrossOver 26.3 with Wine 11), with the game's Direct3D 11 going
straight to Metal through our build of [DXMT](https://github.com/jdrly/dxmt), macOS Game Mode,
Retina rendering and a Wine tuned for the game's busy maps. It changes nothing you already have
installed. Website: [gw2onmac.com](https://gw2onmac.com).

> **GW2 on Mac is an unofficial fan project.** It is not made, endorsed or supported by ArenaNet
> or NCSOFT. ArenaNet doesn't support third-party tools or compatibility layers, so you use it at
> your own risk.
>
> **It doesn't host or change the game.** Steam comes from Valve and the game from Steam or
> ArenaNet. GW2 on Mac only provides the compatibility layer the game runs on (Wine, plus DXMT
> for Direct3D 11 on Metal), the same kind of software as CrossOver or Proton. The one exception
> is the optional *Larger interface* addon (off by default; it asks first), which changes the
> game's memory for a sharper interface at 4K.
>
> **All support for GW2 on Mac comes from its developer, Jan Drlý (Pharaphobia).** For help,
> contact Pharaphobia on [Discord](https://discord.gg/AnV3fZWz2b) or open a
> [GitHub issue](https://github.com/jdrly/gw2-on-mac/issues). Please don't send logs or bug
> reports about GW2 on Mac to ArenaNet's support.
>
> Guild Wars 2 is a trademark of NCSOFT Corporation. Steam is a trademark of Valve Corporation.
> Mac is a trademark of Apple Inc.

## About the app

A SwiftUI app for macOS 26 and later on Apple silicon. It reuses SWTOR on Mac's app (its
structure, installer conventions, Collect Logs, session report, release system and Sparkle
wiring), restyled to the approved design.

Unlike SWTOR on Mac it changes no existing install. It creates its own engine and bottle and
installs the game into them, through **Steam** (Valve's installer; you sign in and install the
game in Steam) or **ArenaNet's own installer** (`Gw2Setup-64.exe`, which you download from
ArenaNet's site and drop into the window), or from **game files you already have**: another Wine
app's Guild Wars 2 (CrossOver, Whisky, an app wrapper), cloned or copied into the bottle while the
original stays as it is. Every download of the game or Steam comes from Valve or ArenaNet; GW2 on
Mac hosts nothing of the game.

Status: version 0.1.0, built and tested in a sandbox. Nobody has run a real install yet (Jan
does the first one), and nothing is published.

## The window

- **Main window**, three states: choose the route (Steam, ArenaNet installer, or game files I
  already have) → the install's steps with progress and Cancel → Ready (Play, Repair, Settings,
  Uninstall…). After Play, Ready gives way to Starting and Playing (see *While the game starts*).
  - The chosen route's card opens; the others keep one line. The painting gives way when the
    panel needs its room (the list of found installs, a long message).
  - *This Mac* checks Rosetta, the engine, the graphics (DXMT), Game Mode, the game and disk space
    (a warning under 75 GB).
  - Light and dark follow the system, each with its own header stroke.
- **Settings** (⌘, or the main window's Settings), one pane each: Graphics, Performance,
  Interface, Game, Updates, Troubleshooting. Changes take effect the next time the game starts.
  - There is no Keyboard or Mouse pane: SWTOR on Mac's game-keys-by-position and raw mouse-look
    are patches of Wine's Mac driver that our `winemac.so` doesn't carry yet (a follow-up).
- **Menus**: About, Check for Updates… (off until there is a feed), Settings…, Collect Logs…, and
  Help (Discord, GitHub issues).

## Install, step by step

`Resources/gw2om.sh install <route>` runs these, all or nothing for what this run created (a
failed or cancelled first install leaves nothing behind):

1. **The Wine engine**: athei's `cx-26.3.0-8` (CrossOver 26.3, Wine 11), the same pinned
   archive as SWTOR on Mac's (size and sha256, resumed and retried, a second GitHub address),
   unpacked and checked. GW2 on Mac's pieces then go into it:
   - DXMT `e02a4d6` over the engine's `dxgi/dxmt` tree
   - the heat `ntdll.so` and `wineserver`
   - `winemac.so` (the launcher fix) and `win32u.so` (its drawing at -O2)

   The engine's own files stay as `<name>.stock`, checked against their known sha256 first.
2. **The game's own bottle**: `wineboot`, then Retina mode (`RetinaMode` in `user.reg`),
   `settings.conf`, `dxmt.conf` and the Game Mode bundle.
3. **Steam, from Valve** (`SteamSetup.exe` from Valve's CDN, `/S`), or **ArenaNet's installer**,
   checked by `gw2om.sh check-setup` before anything changes:
   - it must be a PE x86_64 executable
   - its Authenticode signature must be valid: the signer's signature over the signed attributes,
     whose message digest covers the SpcIndirectData content
   - the signature must cover this very file (the PE hash, recomputed)
   - the signer's certificate must be ArenaNet's

   It uses macOS's own `/usr/bin/openssl` and nothing else. Not checked: the chain up to
   Windows' root certificates, which macOS doesn't have.
4. **The game's download**: Steam starts with `steam://install/1284210` (you sign in; the login
   stays in Steam), or ArenaNet's installer starts. The install command ends here with
   `stage=waiting_game`. The window follows the download from its status:
   - Steam: `appmanifest_1284210.acf`, `BytesDownloaded`/`BytesToDownload`, done at
     `StateFlags` 4.
   - ArenaNet's installer gives no completion record: the game counts as there once `Gw2.dat`
     has more than 1 GB and neither the installer nor `Gw2-64.exe` runs.

   This picks up again after the app restarts. *Stop waiting* keeps the engine and the bottle.
5. **Finishing touches** (`gw2om.sh finish`, which the window starts by itself):
   - DXMT's cache folder, `~/Library/Caches/GW2 on Mac/dxmt/Gw2-64.exe/`
   - the interface addon, if it's on
   - the registry settings
   - `stage=finished`, then Ready

### Using game files you already have

`gw2om.sh install import <folder> [--no-settings]`, the window's *Game files I already have*:

- **Where it looks** (`gw2om.sh scan`, read-only): CrossOver's bottles
  (`~/Library/Application Support/CrossOver/Bottles/*`), Whisky's
  (`~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/*` and `…/Data/Bottles/*`, named from the
  bottle's `Metadata.plist`), app wrappers such as Sikarugir, Kegworks, Wineskin or Porting Kit
  (`~/Applications/**/*.app` and `/Applications/**/*.app`: `Contents/SharedSupport/prefix`,
  `Contents/drive_c`, `Contents/Resources/drive_c`), Heroic's prefixes (`~/Games/Heroic/Prefixes`) and
  `~/.wine`. In each `drive_c`: Steam's library (`Program Files (x86)/Steam/steamapps/common/Guild
  Wars 2`) and ArenaNet's default (`Program Files/Guild Wars 2`, also under `Program Files (x86)`).
  GameHub doesn't document where it keeps its bottles: its folders in `~/Library/Application
  Support` and `~/Library/Containers` are looked through a few levels deep, and *Choose folder…*
  covers the rest. *Choose folder…* (or a folder dropped on the card) takes the game folder, or a
  bottle or wrapper app with one in it (`gw2om.sh check-game`).
- **What counts**: `Gw2-64.exe` and a `Gw2.dat` of more than 1 GB. The list shows the source app,
  the path, the size and the route it implies: Steam if Steam's record
  (`steamapps/appmanifest_1284210.acf`) is next to it, else ArenaNet.
- **The files**: on the same disk as the app's folder they are cloned (APFS `clonefile`, `cp -c`):
  instant, and they take no extra space until either copy changes. From another disk they are
  copied, after a free-space check (their size and 1 GB to spare), with progress. The source is
  only read. GW2 on Mac's own addon files (`version.dll` with its mark, `gw2-ui-scale.*`) are left
  out; any other addon (an arcdps `d3d11.dll`, an `addons` folder…) comes along as it is and the
  summary names it.
- **Steam route**: the engine, the bottle and Steam as usual, then the folder goes to the
  bottle's `steamapps/common/` with Steam's record next to it, before Steam ever starts, and the
  finishing touches follow. Steam may check the files at the first Play. If its record says the
  game isn't complete, Steam's install step follows as usual and continues from the files.
- **ArenaNet route**: the engine and the bottle, the folder to the bottle's `Program
  Files/Guild Wars 2`, the finishing touches.
- **Also bring my game settings** (on by default): `GFXSettings.Gw2-64.exe.xml` and `Local.dat`
  (the options and the remembered login) from the source bottle's newest
  `users/*/AppData/Roaming/Guild Wars 2`. Any the bottle had already go to `GW2 on Mac backup
  <date>/` next to them.
- Refused while a Guild Wars 2 runs anywhere (its files could change during the copy). A failed or
  cancelled import removes what it cloned or copied.

**Play** (`gw2om.sh play`) starts `steam.exe -applaunch 1284210 <launch options>` (Steam route),
or the game's own launcher `Gw2-64.exe <launch options>` (ArenaNet route), detached, with the
settings as its environment. Once Steam remembers a login (its `config/loginusers.vdf` has a
user with `"RememberPassword" "1"`), it starts Steam with `-silent` too: no Steam window, Steam
signs in and starts the game (*Start Steam in the background*, Settings › Game). Before the first
sign-in, Steam's window shows. It also:
- makes the Game Mode link
- writes `session.env`
- rotates the logs (when no session runs)

If the game runs, Play brings it to the front instead. If Steam still runs from before with
other settings, Play says Steam must quit first, because the game gets Steam's environment.

**Steam quits after the game** (*Quit Steam when the game quits*, Settings › Game, on by default).
Play records the session in `session` (next to `state`) and starts `gw2om.sh watch-session`
detached, one per session, so it doesn't need the window. One per session: a kernel lock
(`flock`, through macOS's `/usr/bin/perl`) on `.session.lock`, which Play takes and the watcher
inherits, and which ends with the watcher (nothing stale to clean up; without perl, Play starts no
watcher and Steam stays open). After Play's first version of `session`, the watcher is its only
writer: others append a request to `session.req` (`join` from a Play, `shown` from Show Steam),
which it applies in order.
- It follows the session through the engine's own processes: it waits up to 15 minutes for
  `Gw2-64.exe` (Steam may update itself and sign in first), then for it to quit, plus a
  30-second grace, since the game's patcher or a restart starts it again.
- Then, if this Play started Steam itself in the background (`-silent`), it asks Steam to quit
  (`steam.exe -shutdown`, through the engine's Wine with the game's environment). If Steam is
  still running 20 seconds later, it ends the bottle's Wine (`wineserver -k`, this bottle only).
- It leaves Steam alone if Steam was already running before Play, if Steam's window showed
  (before the first sign-in, or with *Start Steam in the background* off), if the setting is
  off, if Steam's window was brought up during the session, and if the game never started
  (the timeout, or Steam closed first). Whether Steam is the session's is decided by Play, from
  the bottle's processes before it starts Steam: the bottle's Steam starts only through Play, so
  a `steam.exe` replaced without a request is Steam restarting itself (after an update).
- A second Play while a session runs (while Steam starts the game, or in the grace after it quit)
  joins that session and waits until the watcher has it: the watcher waits for the game again,
  and if no Steam ran before that Play, Steam is that Play's. Once the watcher has decided to
  quit Steam, or if it doesn't answer, Play starts nothing and asks to try again in a few
  seconds.
- It logs to `install.log` under `---- session`. Uninstall stops it. The `session` file's
  `stage` (`waiting_game`, `playing`, `grace`, `closing_steam`, `done`) and `result` say where
  the session is.

### While the game starts

After Play the panel shows **Starting**: the start's stages, done, current and waiting as the
install's steps, with the time so far. The window polls `gw2om.sh session-status` every second
while a session runs and stops when it ends. It prints `stage`, `detail`, `progress`, `elapsed`,
`game_elapsed`, `steam` (bg, window or none), `game`, `closing`, `quit_steam` and `limiter_hint`
from these:

| Stage | Detected by |
|---|---|
| Starting Steam | the start is under way (the session's watcher waits for the game), no Steam sign-in yet |
| Updating Steam (only when it happens) | Steam's `logs/bootstrap_log.txt` verifies Steam's own files, or downloads or installs an update (with its percent) |
| Signing in | `steamwebhelper.exe` runs and `logs/connection_log.txt` isn't logged on since the start |
| Checking game files (only when it happens) | `logs/content_log.txt` has app 1284210 validating or updating (an update's percent from its appmanifest) |
| Starting Guild Wars 2 | Steam is signed in, or `Gw2-64.exe` runs |
| Loading | DXMT's log of this session has the device, no frame yet |
| Playing | DXMT's first `Present pacing` line |

- **Only the session's lines count:** Steam's logs from the session's start on, and only their
  state lines. Nothing of them is printed, so no account name or ID leaves `session-status`.
- **The ArenaNet route** starts at Starting Guild Wars 2; the launcher's own window takes over.
- **The window picks a session up when it opens** (`status` prints `session=live` while the
  watcher waits for the game, follows it, waits through a restart's grace or closes Steam after
  it; the window keeps polling while `session-status` says `watching=yes`), not a Steam idling on
  its own.
  A Play that joins a running session starts the stages again (`session-status --since <its
  time>`).
- **Show Steam** (`gw2om.sh show-steam`: `steam.exe steam://open/main` through the engine) brings
  Steam's window up, for a sign-in Steam asks for. After 2 minutes without a sign-in in the
  background, the tip says so. The chip says *Steam in the background* or *Steam window*. A
  Steam whose window the user brought up stays open after the game: Show Steam asks the watcher
  (a `shown` request) and waits for its answer; while Steam already quits, the window stays shut.
- **Playing** shows how long the game has run, **Bring to Front** (the game's app, as Play does
  when the game runs) and *Steam closes by itself when you quit the game* when the watcher will
  close it (`quit_steam=yes` in its session file, `<app dir>/session`).
- **A steadier 60:** while the game's own Frame Limiter (`frameLimit` in the bottle's
  `GFXSettings.Gw2-64.exe.xml`, only read) is set to a value and `verticalSync` is on, Playing
  suggests Unlimited with vsync: under Wine the two together land at about 58 instead of 60.
  *Don't show again* keeps it away (the app's own preference).
- **When the game quits** the panel is Ready again. While the watcher closes Steam, the tip says
  *Steam is closing…* and Play waits.

**Repair** sets up the engine (unpacked again if its loader changed), GW2 on Mac's pieces, the
bottle's settings, Game Mode and Steam (if gone) again. It keeps the game and the settings.

**Game Mode**: macOS turns it on only for a process whose executable belongs to a bundle with
`LSSupportsGameMode`, and every Wine process runs Wine's loader. As SWGL on Mac and Jan's
development setup do it:
- `gamemode/GW2.app` (`cz.jandrly.gw2onmac.game`) holds an unsigned copy of the loader named
  `Gw2-64.exe` and an `ntdll.so` link.
- With `WINEDLLPATH` set, CrossOver's ntdll starts the game from `$TMPDIR/winetemp-…/Gw2-64.exe`,
  which Play points at that bundle.

## What it changes on disk

Everything lives in these places; nothing else on the Mac is touched (no launch agents, no login
items, nothing in `/Applications` besides the app itself):

| Path | What | Uninstall |
|---|---|---|
| `~/Library/Application Support/GW2 on Mac/engine/` | the Wine engine with GW2 on Mac's pieces (about 1 GB) | removed |
| `…/GW2 on Mac/bottle/` | the game's Wine prefix: Steam, **the game's files** (about 75 GB; an APFS clone of your own when they came from the same disk, which takes no extra space until either changes), the game's own settings (and `GW2 on Mac backup <date>/` next to them after an import that replaced some) | removed, with the game |
| `…/GW2 on Mac/gamemode/GW2.app` | the Game Mode bundle | removed |
| `…/GW2 on Mac/settings.conf`, `state`, `install-manifest.json`, `dxmt.conf`, `session` | the settings, the route and stage, what was installed, DXMT's options, the last Play's session (its watcher's stage) | removed |
| `~/Library/Caches/GW2 on Mac/downloads/` | the engine archive, `SteamSetup.exe`, a copy of `Gw2Setup-64.exe` | removed |
| `~/Library/Caches/GW2 on Mac/dxmt/Gw2-64.exe/` | DXMT's shader cache, pipeline archives and recorded pipelines for the game (`DXMT_CACHE_DIR` points DXMT here; another process, such as the launcher's `CefHost.exe`, gets its own folder next to it) | removed; *Reset the shader cache* empties it too |
| `$(getconf DARWIN_USER_TEMP_DIR)winetemp-…/Gw2-64.exe` | the Game Mode link | removed |
| `~/Library/Logs/GW2 on Mac/` | `install.log`, `wine.log`, DXMT's `Gw2-64_d3d11.log`, `session.env`, `gamemode.log`, heat logs (Debug logging) | **kept** |

Other Wine apps' bottles and wrappers are only ever read (*Game files I already have*), never
changed, and Uninstall leaves them alone.

The game folder gets `version.dll` and `gw2-ui-scale.ini` only while *Larger interface* is on.
Another program's `version.dll` there is never touched. The app's own preferences (the chosen
route, the Settings pane, *Quit after launching*, the frame-limiter hint's *Don't show again*) are in its defaults domain,
`cz.jandrly.gw2onmac`.

## Settings

`gw2om.sh settings` prints them and `gw2om.sh set <key> <value>` changes one. They are kept in
`settings.conf` and applied at each game start (`gw2om.sh env` prints the environment Play would
use). The defaults are the mix Jan plays with.

| Pane | Setting (key) | Default | What it does |
|---|---|---|---|
| Graphics | Retina (`retina`) | on | `RetinaMode` in the bottle (Wine's High Resolution Mode) |
| | Frame cap (`fpscap`) | off | `d3d11.preferredMaxFrameRate` in `dxmt.conf` (30, 40, 60, 120) |
| | MetalFX for Subsample (`metalfx`) | off | `DXMT_SUBSAMPLE_METALFX=1` (experimental) |
| | Metal HUD (`hud`) | off | `WINE_HEAT_METAL_HUD=1`: the heat `ntdll.so` sets `MTL_HUD_ENABLED=1` in `Gw2-64.exe` only, at its start, so Steam's windows don't show the HUD |
| Performance | Shader warming (`warm`) | on | `DXMT_WARM=all`: pipelines built ahead by recent use, up to 8,192 |
| | Cooler job workers (`coolworkers`) | 3 | `WINE_HEAT_QOS=1=utility:<n>`: the first n ABOVE_NORMAL job workers on the cooler cores; off |
| | Faster locks (`fastlocks`) | on | `WINE_HEAT_SPIN=lock=20:game,event=30:game` |
| | CPUs the game sees (`ncpu`) | 8 | `WINENCPU`: 2 up to the Mac's logical CPUs (`sysctl hw.logicalcpu`) in steps of 1, or all. The game starts one job worker per CPU, minus one |
| Interface | Larger interface (`uiscale`) | off | the addon in the game folder, and `version=native,builtin` for `Gw2-64.exe`. Turning it on asks first: it changes the game's memory and patches one piece of its code (the cinema text), which ArenaNet doesn't support |
| | Interface Size "Larger" (`uiscale_size`) | 1.75 | the ini's `scale` (1.5, 1.75, 1.8, 2.0) |
| | Small text in Cronos (`uiscale_sans`) | on | the ini's `sans=cronos` (else `keep`) |
| | Cinematic dialogue (`uiscale_cinema`) | on | the ini's `cinema=1` |
| Game | Game Mode (`gamemode`) | on | the bundle and link above |
| | Start Steam in the background (`steambg`) | on | Steam route: `-silent` once Steam remembers a login (see Play) |
| | Quit Steam when the game quits (`quitsteam`) | on | the Steam Play started in the background quits once the game has quit (see Play). Shown only while *Start Steam in the background* is on |
| | Launch options (`launchopts`) | none | arguments for `Gw2-64.exe` (letters, digits, `-_.:=,/+` only) |
| | Quit GW2 on Mac after launching | off | the app's own preference |
| Updates | Check automatically (`updates`) | on | Sparkle's automatic checks, once there is a feed |
| Troubleshooting | Debug logging (`debug`) | off (on in development builds) | `DXMT_LOG_LEVEL=debug`, the heat counters (`WINE_HEAT_COUNT`), `WINEDEBUG=err+all,fixme-all` |

Always set: `WINEMSYNC=1`, `ROSETTA_X87_PATH=` (x87sidecar off), `WINEDLLOVERRIDES=winemenubuilder.exe=d`,
the compatdb rule that gives every process DXMT (`dxgi=dxmt`, the game launcher's `CefHost.exe`
too), `DXMT_CONFIG_FILE`, `DXMT_LOG_PATH`, `DXMT_CACHE_DIR` (the app's cache folder), `DXMT_DEPENDENCY_COMPRESSION=1`, and the heat ntdll's
`WINE_HEAT_EVPOOL=1`, `WINE_HEAT_WAKE=one,skip`, `WINE_HEAT_LAZYCLOCK=1`,
`WINE_HEAT_MSYNC_UNREG=1`, `WINE_HEAT_MSYNC_PORTFIX=1`.

Registry settings (Retina, the addon's override) are written straight into the bottle's
`user.reg`, as SWTOR on Mac does, and only while no Wine session of the bottle runs. Otherwise
they wait for the next Play that finds none.

## Logs and bug reports

- **Collect Logs…** (menu and Settings › Troubleshooting) zips the logs to the Desktop. It is
  SWTOR on Mac's `collect-logs.sh` for this app's files, with the same redaction, crash reports,
  unified-log GPU errors and leak check. In the zip:
  - GW2 on Mac's logs (`wine.log` and DXMT's `Gw2-64_d3d11.log`, each with the 4 sessions
    before), the newest heat logs, `session.env`, the settings and state files
  - `session-report.txt`
  - from the game: `ArenaNet.log` and `GFXSettings.Gw2-64.exe.xml`
  - Steam's bootstrap, content, gameprocess and shader logs
  - crash reports of the last 7 days, the GPU errors of the last 2 hours, `system-info.txt`

  Redacted on the way in: account, persona and Mac names, Steam IDs, e-mail addresses, home
  folders, tokens, the crash log's machine, account and address fields. Never in it: `Local.dat`,
  Steam's config and its login and connection logs. A file that still has one of those after
  redaction is left out (`left-out.txt`).
- **Session report** (`Resources/session-report.sh [--keep] [log]`, `--compare A B`) sums up the
  last session from DXMT's own lines:
  - frame rate (median, 10th percentile, minimum), frame times, hitches and DXMT's share of them
  - compiles and the render thread's waits for them
  - shader warming, presentation, Metal 4 errors
- **Debug logging** (Settings › Troubleshooting): more detail for a bug report, at some cost.

Support: Pharaphobia on [Discord](https://discord.gg/AnV3fZWz2b) or a
[GitHub issue](https://github.com/jdrly/gw2-on-mac/issues), never ArenaNet's support.

## Building

Needs Xcode 27 (the macOS 27 SDK; the app targets macOS 26.0).

```sh
scripts/stage-components.sh    # copy DXMT, the heat Wine pieces, winemac and the addon into prebuilt/
./build.sh                     # → dist/GW2 on Mac.app, ad-hoc signed
```

- **Where the bundled binaries come from.** DXMT and the four Wine pieces (`ntdll.so`,
  `wineserver`, `winemac.so`, `win32u.so`) are built today only in Jan's private development
  workspace, whose build scripts are not in this repository. `stage-components.sh` copies them
  from that workspace: `GW2_ON_MAC_WORKSPACE` (default `../gw2-on-mac`, next to this
  repository), and in it the builds the app ships (`work/dxmt-rollback/e02a4d6-install`,
  `work/heat/install-r7c`, `work/winemac/install`, `work/ui-scale/build`; override with
  `DXMT_INSTALL`, `HEAT_INSTALL`, `WINEMAC_INSTALL`, `UISCALE_BUILD`). It changes nothing in the
  workspace and checks each file against its build record and this repository's
  [`patches/`](patches). `prebuilt/` is ignored by git.
- **Their complete corresponding source** (LGPL-2.1-or-later) is public: the pinned upstreams
  plus this repository's patches. DXMT is [jdrly/dxmt at `e02a4d6`](https://github.com/jdrly/dxmt/tree/e02a4d6);
  the Wine pieces are [athei/wine `d23b397`](https://github.com/athei/wine/tree/d23b39774528237cafe49f9a073286f854b779c0)
  (CodeWeavers' CrossOver 26.3 sources with athei's patches, the engine's own sources) with
  [`patches/ntdll-msync-alert-fd.patch`](patches/ntdll-msync-alert-fd.patch) (from SWTOR on Mac),
  [`patches/ntdll-heat.patch`](patches/ntdll-heat.patch),
  [`patches/wineserver-msync-unregister.patch`](patches/wineserver-msync-unregister.patch) and
  [`patches/winemac-gw2-launcher.patch`](patches/winemac-gw2-launcher.patch), configured as the
  engine. Each component's `VERSION` record (also in the app, `Resources/Licenses`) names its
  sources, patches and sha256. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- The interface addon is this repository's own code, [`addon/ui-scale`](addon/ui-scale):
  `scripts/build-addon.sh` builds `version.dll` with Homebrew's mingw-w64
  (`brew install mingw-w64`) into `work/ui-scale/build` and runs its native test. Staging still
  takes the workspace's build of the same sources (the same but for the link timestamps).
- `build.sh` checks `prebuilt/` again and compiles `src/native/*.swift` (arm64) and the
  `procpaths` helper. It bundles the components, fonts, art and licences (`Resources/Licenses`,
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)), downloads Sparkle at a pinned version and
  sha256, and compiles the Icon Composer icon (`src/AppIcon.icon`) with actool into
  `Assets.car` plus the fallback `AppIcon.icns`.
  - `GW2_ON_MAC_VERSION` sets the version (0.1.0; `X.Y.Z-dev.N` makes a development build, as
    SWTOR on Mac's).
  - `GW2_ON_MAC_FEED_URL` and `GW2_ON_MAC_ED_PUBLIC_KEY` turn updates on.
- The icon's layers: `swift src/make-icon.swift layers src/AppIcon.icon` (the wordmark; the
  ensō, `Assets/icon-ring.png`, is the approved design's artwork), and
  `… preview src/AppIcon.icon <sheet.png>` for a review sheet of every appearance and size.
- The icons in the window are Lucide's, drawn from path data: after adding an SVG to
  `src/icons`, run `python3 -I scripts/gen-icons.py`.

## Testing

Never against a real install, and never with Wine, Steam or the game running on Jan's screen.

- `scripts/test-sandbox.sh` tests the backend of a built app end to end in
  `work/app-sandbox/test` (256 checks). It uses a stand-in engine archive whose `bin/wine` only
  pretends, plays Steam's and ArenaNet's downloads itself, and uses a clone of the game's own
  ArenaNet-signed `Gw2-64.exe` as the installer to check (`SIGNED_PE`, by default the one in
  the development workspace's bottle; without one those checks are skipped). It covers:
  - dry runs, both routes, finish, every setting and what it does, the addon
  - play, the busy checks, repair, reset-shaders, reinstall-engine, the lock
  - Collect Logs' redaction, uninstall, a failed install's rollback
  - Steam's `-silent` with and without a remembered login, the CPU counts
  - the session's watcher, with stand-in Steam and game processes (the busy checks' signed
    sleepers) and shortened times (`GW2_ON_MAC_WATCH_TIMEOUT`, `…_GRACE`, `…_QUITWAIT`,
    `…_POLL`): Steam quits after the game (`-shutdown` in the stand-in's log), a restart within
    the grace, an already-running Steam, the setting off, Steam's window shown, the timeout,
    Steam closed before the game, Steam restarting itself, a `shown` request, Play in the grace
    (also after Steam quit, and with its game within the grace), Play while Steam quits, one
    watcher per session (also two Plays at once, a lock file left behind, and a held lock that
    doesn't answer), the `wineserver -k` fallback, and uninstall stopping it
  - existing game files: stand-in CrossOver, Whisky and wrapper bottles (sparse `Gw2.dat`), the
    scan, check-game, the clone (Steam and ArenaNet routes), the settings and their backup, a real
    copy from an attached disk image (`hdiutil`, when it can attach one) and a forced copy
    (`GW2_ON_MAC_IMPORT_COPY`), the free-space refusal (`GW2_ON_MAC_FREE_KB`), the refusal while the
    game runs, and that the sources never change
- `scripts/ui-render.sh` renders every window state, light and dark, headlessly into
  `work/app-renders/`. Nothing is shown on screen and the app never activates. With the approved
  design's exports (`DESIGN_EXPORTS`, by default the development workspace's; the design file is
  not in this repository) it also writes `compare-*.png`: the design's export next to the render.
- By hand, `GW2_ON_MAC_ROOT=/abs/dir` puts every path `gw2om.sh` and `collect-logs.sh` use under
  that folder, and `GW2_ON_MAC_DRY_RUN=1` prints what would change without changing anything:

  ```sh
  R="dist/GW2 on Mac.app/Contents/Resources"
  GW2_ON_MAC_ROOT=$PWD/work/app-sandbox/try GW2_ON_MAC_DRY_RUN=1 "$R/gw2om.sh" install steam
  ```

  The app passes both variables on, so the window can run against a sandbox too. In a sandbox,
  `gw2om.sh` refuses to run the real engine's Wine (`GW2_ON_MAC_ALLOW_WINE=1` overrides it, for a
  deliberate test only).

## Uninstall

*Uninstall…* in the window asks first, and says that the game's files go with the bottle. It
then removes everything in the table above except the logs. Steam and the game have to be
closed. Removing it by hand:

```sh
rm -rf ~/Library/"Application Support/GW2 on Mac" ~/Library/Caches/"GW2 on Mac"
rm -rf ~/Library/Logs/"GW2 on Mac"      # the logs, if you want them gone too
```

Then move the app to the Bin.

## Releasing

Not yet: GW2 on Mac publishes nothing so far. The pieces are SWTOR on Mac's, ready:

- `scripts/release.sh` signs with Developer ID inside out (the bundled Mach-O components and
  `procpaths`, Sparkle, the app; `src/entitlements/app.plist`), builds and notarizes the DMG, and
  builds and checks the Sparkle feed (`scripts/check-appcast.swift`, delta updates).
  - Every mode that creates or changes a GitHub release stops unless `GW2_ON_MAC_PUBLISH=1`.
  - The feed needs an app built with `GW2_ON_MAC_FEED_URL` (the latest release's `appcast.xml`)
    and `GW2_ON_MAC_ED_PUBLIC_KEY`.
  - `--sign-only` and `--no-notarize` work locally today.
  - Untested: `wineserver` under the hardened runtime.
- Release notes: [`release-notes/`](release-notes) in SWTOR on Mac's format (`0.1.0.md`).
- Versioning: `X.Y.Z` for releases, `X.Y.Z-dev.N` for development builds, with SWTOR on Mac's
  bundle-version scheme. The `release/` output is ignored by git.

## Layout

```
build.sh                 the app bundle (see Building)
src/native/              SwiftUI: App (model, menus), MainWindow, Settings, Play, Updates
                         (Sparkle), Brand (the design's tokens and pieces), Lucide (+ LucideData)
src/gw2om.sh             the backend (bash 3.2)
src/collect-logs.sh      Collect Logs…
src/helpers/procpaths.c  every process's real executable, for gw2om.sh's busy checks
src/fonts/, src/art/, src/icons/, src/AppIcon.icon, src/make-icon.swift, src/Info.plist
addon/ui-scale/          the interface addon's source (version.dll) and its native test
patches/                 the patches to Wine in the bundled ntdll.so, wineserver and winemac.so
scripts/                 stage-components, build-addon, test-sandbox, ui-render, session-report,
                         release, check-appcast, gen-icons
release-notes/           the notes of each release
prebuilt/, dist/, release/, work/, .cache/   build and test output (ignored)
```

## Known limits and follow-ups

- The first real install hasn't run yet: Jan does it, after which the Steam route's `StateFlags`
  and the ArenaNet route's completion heuristic should be checked against what really happens.
- No Keyboard or Mouse pane until SWTOR on Mac's winemac patches are ported to our build.
- DXMT's caches live in the app's own cache folder (`DXMT_CACHE_DIR`, jdrly/dxmt #134), so they
  are no longer shared with another DXMT setup of the game on the same Mac. Caches an older
  build left in `$(getconf DARWIN_USER_CACHE_DIR)dxmt/Gw2-64.exe/` are not moved or removed
  (another setup may use them); the first sessions build the app's own cache from scratch.
- A Steam library added outside the bottle (Steam › Settings › Storage) is not removed by
  Uninstall.
- Blish HUD and macOS 28's Rosetta changes are not covered.
- *Game files I already have*: GameHub's bottle location is a guess (its folders, searched a few
  levels deep); Choose folder… is the sure way. An addon's `d3d11.dll` (arcdps) in the source
  folder comes along as it is; whether it works with DXMT is untested.
