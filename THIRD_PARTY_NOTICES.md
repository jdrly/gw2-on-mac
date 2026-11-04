# Third-party notices

GW2 on Mac's own code (the app in `src/native`, `gw2om.sh`, `collect-logs.sh`,
`session-report.sh`, `procpaths`, the build, test and release scripts, and the interface addon
`version.dll` from this repository's `addon/ui-scale`) is under the [zlib license](LICENSE),
copyright (c) 2026 Jan Drlý. The patches to Wine in this repository's [`patches/`](../patches)
(`ntdll-heat.patch`, `wineserver-msync-unregister.patch`, `winemac-gw2-launcher.patch`) and SWTOR
on Mac's `ntdll-msync-alert-fd.patch` are changes to Wine and under Wine's LGPL-2.1-or-later.

The app bundles a few components and downloads the Wine engine at install time. Guild Wars 2,
its installer and launcher, its files and Steam are never bundled or downloaded from anywhere but
their publishers: Steam's installer comes from Valve's CDN, the game from Steam or ArenaNet's own
installer, which the player downloads from ArenaNet's site.

## Bundled in the app

| Component | Where in the app | License | License text in the app |
|---|---|---|---|
| **DXMT** `v0.80-439-g684f428`, the [jdrly/dxmt](https://github.com/jdrly/dxmt) fork of [3Shain/dxmt](https://github.com/3Shain/dxmt) (Feifan He for CodeWeavers, and contributors), built by this repository's `scripts/build-dxmt.zsh` | `Contents/Resources/components/dxmt/` (`d3d11.dll`, `dxgi.dll`, `d3d10core.dll`, `winemetal.dll` for x86_64 and i386, `winemetal.so`) | LGPL-2.1-or-later. Complete source: [jdrly/dxmt at `684f428`](https://github.com/jdrly/dxmt/tree/684f428) | `Resources/Licenses/dxmt/LICENSE`, `COPYING.LIB` |
| **Wine's ntdll and wineserver** (the x86_64 unix `ntdll.so` and `wineserver`) from the Wine sources of the app's engine: CodeWeavers' CrossOver 26.3 sources (<https://www.codeweavers.com/crossover/source>) with athei's patches, [athei/wine `d23b397`](https://github.com/athei/wine/tree/d23b39774528237cafe49f9a073286f854b779c0), changed by SWTOR on Mac's `ntdll-msync-alert-fd.patch`, [`patches/ntdll-heat.patch`](../patches/ntdll-heat.patch) and [`patches/wineserver-msync-unregister.patch`](../patches/wineserver-msync-unregister.patch) (dappermint/winecx `8df1826853`), built by `scripts/build-ntdll-heat.zsh` at -O0 as the engine | `Contents/Resources/components/heat/` | LGPL-2.1-or-later. Complete source: those sources plus the patches (also in the app) | `Resources/Licenses/wine/COPYING.LIB`, `LICENSE`, the patches, `ntdll-VERSION.txt`, `wineserver-VERSION.txt` |
| **Wine's Mac driver and win32u** (the x86_64 unix `winemac.so` and `win32u.so`) from the same sources, `winemac.so` changed by [`patches/winemac-gw2-launcher.patch`](../patches/winemac-gw2-launcher.patch) (the launcher's flashing), `win32u.so` with its layered-window drawing built at -O2, by `scripts/build-winemac.zsh` | `Contents/Resources/components/winemac/` | LGPL-2.1-or-later. Complete source: those sources plus the patch | `Resources/Licenses/wine/COPYING.LIB`, `LICENSE`, `winemac-gw2-launcher.patch`, `winemac-win32u-VERSION.txt` |
| **Sparkle** 2.10.0, <https://sparkle-project.org> (app updates, off until there is a feed; with bsdiff, sais, and other notices) | `Contents/Frameworks/Sparkle.framework` | MIT | `Resources/Licenses/sparkle/LICENSE` |
| **Cinzel** (variable, `wght` 400 to 900), copyright 2020 The Cinzel Project Authors, <https://github.com/NDISCOVER/Cinzel>, from [google/fonts `ofl/cinzel`](https://github.com/google/fonts/tree/main/ofl/cinzel) (`Cinzel[wght].ttf`, sha256 `f4d83d34…2a4e0f34`), unmodified | `Contents/Resources/Fonts/Cinzel-Variable.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/Cinzel-OFL.txt` |
| **Marcellus**, copyright 2012 Brian J. Bonislawsky DBA Astigmatic (AOETI), from [google/fonts `ofl/marcellus`](https://github.com/google/fonts/tree/main/ofl/marcellus) (`Marcellus-Regular.ttf`, sha256 `1cf0cd10…4abb2f81`), unmodified | `Contents/Resources/Fonts/Marcellus-Regular.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/Marcellus-OFL.txt` |
| **Alegreya Sans** (Regular, Medium, Bold), copyright 2013 The Alegreya Sans Project Authors, <https://github.com/huertatipografica/Alegreya-Sans>, from [google/fonts `ofl/alegreyasans`](https://github.com/google/fonts/tree/main/ofl/alegreyasans) (sha256 `8fab6341…1b14ea10`, `4b89fe78…44815b43`, `a3055a18…92c9fb8e`), unmodified | `Contents/Resources/Fonts/AlegreyaSans-*.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/AlegreyaSans-OFL.txt` |
| **Lucide** icons (lucide-static 0.460.0), <https://lucide.dev>, drawn from their SVG path data (`src/icons`, `src/native/LucideData.swift`) | in the app's binary | ISC (portions from Feather, MIT) | `Resources/Licenses/lucide/LICENSE.txt` |

The artwork (the ink strokes behind the header, the painting, the app icon's ensō) is the
design's own (`docs/design`), made for GW2 on Mac; no ArenaNet or NCSOFT logo, font or art is in
the app.

The bundled DXMT, Wine and addon files are not in this repository: `app/scripts/stage-components.sh`
copies them from this repository's builds in `work/` into the ignored `app/prebuilt/`, checked
against their build records. Sparkle is downloaded by `app/build.sh` at a pinned version and
sha256.

## Downloaded at install time (not in the app, not redistributed)

`gw2om.sh` downloads these from their publishers onto your Mac when you click Install:

| Component | Source | License |
|---|---|---|
| **Wine engine** `cx-26.3.0-8`: Wine 11.0 from CodeWeavers' CrossOver 26.3 sources with athei's patches ([athei/wine](https://github.com/athei/wine), commit `d23b397`), built and bundled by [athei/wine-build](https://github.com/athei/wine-build), the engine SWTOR on Mac and SWGL on Mac use; checked against its pinned size and sha256 | [athei/wine-build cx-26.3.0-8](https://github.com/athei/wine-build/releases/tag/cx-26.3.0-8) | LGPL-2.1-or-later ([Wine](https://www.winehq.org); CrossOver sources: <https://www.codeweavers.com/crossover/source>) |
| Inside that engine, as athei/wine-build bundles it: its libraries in `lib/external`, DXMT v0.80, mtld3d, x87sidecar and Apple's D3DMetal (Game Porting Toolkit redistributables) | the same release | each component's own license, as published there. GW2 on Mac draws with its own DXMT build instead of the engine's, and turns x87sidecar off |
| **Steam** (the Windows client, Steam route only): Valve's `SteamSetup.exe` | `https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe` (Valve) | Valve's Steam Subscriber Agreement |

The installer changes its copy of the engine in these places (and leaves out its SDK: headers,
Wine's tests, man pages): the bundled DXMT goes over the engine's `lib/wine/dxgi/dxmt` tree (its
`d3d10.dll` and `d3d10_1.dll` stay), and the bundled `ntdll.so`, `wineserver`, `winemac.so` and
`win32u.so` replace the engine's, which are kept as `<name>.stock`.

## Trademarks

GW2 on Mac is an unofficial fan project, not made, endorsed or supported by ArenaNet or NCSOFT.
Guild Wars 2 is a trademark of NCSOFT Corporation. Steam is a trademark of Valve Corporation. Mac
is a trademark of Apple Inc.
