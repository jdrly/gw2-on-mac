# Third-party notices

My own code for GW2 on Mac is under the [zlib license](LICENSE), copyright (c) 2026 Jan Drlý.
That covers the app in `src/native`, `gw2om.sh`, `collect-logs.sh`, `session-report.sh`,
`procpaths`, `sessionlock`, the build, test and release scripts, and the interface addon
`version.dll` from [`addon/ui-scale`](addon/ui-scale).

The patches to Wine in [`patches/`](patches) belong to 0.1.x. This app doesn't build or ship them.
They're changes to Wine, so they're under Wine's LGPL-2.1-or-later. Three are mine: `ntdll-heat.patch`, `wineserver-msync-unregister.patch` and
`winemac-gw2-launcher.patch`. Three come from SWTOR on Mac: `ntdll-msync-alert-fd.patch`,
`winemac-physical-keys.patch` and `winemac-swtor-mouse.patch`. Two are SWGL on Mac's,
`winemac-swgl-relative-mouse.patch` and `winemac-swgl-input-thread.patch`, as SWTOR on Mac
carries them.

The app bundles a few components and downloads the Wine engine at install time. On this line it
bundles my DXMT fork built for the engine and, in builds that have them, two files of Wine, my
`ntdll.so` and my Mac driver's `winemac.so`, and my build of FEX's x86_64 half, all built for the
engine. It never bundles
Guild Wars 2, its installer, its launcher, its files or Steam, and never downloads them from
anywhere but their publishers. Steam's installer comes from Valve's CDN. The game comes from Steam,
or from ArenaNet's own installer, which you download from ArenaNet's site.

## Bundled in the app

| Component | Where in the app | License | License text in the app |
|---|---|---|---|
| **DXMT**, my fork [jdrly/dxmt](https://github.com/jdrly/dxmt) of [3Shain/dxmt](https://github.com/3Shain/dxmt), built for Mach9 0.3.1's engine (`aarch64-windows`, `i386-windows`, `aarch64-unix/winemetal.so`); `VERSION` names the commit, whose source is the complete corresponding source. `gw2om.sh` puts it into the engine's DXMT tree | `Contents/Resources/components/dxmt` | LGPL-2.1-or-later | `Resources/Licenses/dxmt/COPYING.LIB`, `LICENSE`, `VERSION` |
| **Wine's `ntdll.so`**, my build from my fork [jdrly/wine](https://github.com/jdrly/wine) of [athei/wine](https://github.com/athei/wine), the Wine Mach9 0.3.1's engine is built from, for that engine; only in builds that have it. `VERSION` names the commit, whose source is the complete corresponding source. `gw2om.sh` puts it into the engine's `lib/wine/aarch64-unix`, the engine's own kept next to it | `Contents/Resources/components/ntdll` | LGPL-2.1-or-later | `Resources/Licenses/wine/COPYING.LIB`, `LICENSE`, `VERSION` |
| **Wine's Mac driver, `winemac.so`**, my build from the same fork for the same engine, with my `win32u.so` when that build has one; only in builds that have it. `VERSION` names the commit, whose source is the complete corresponding source. `gw2om.sh` puts them into the engine's `lib/wine/aarch64-unix` as one set, the engine's own kept next to each | `Contents/Resources/components/macdrv` | LGPL-2.1-or-later | `Resources/Licenses/macdrv/COPYING.LIB`, `LICENSE`, `VERSION` |
| **FEX**, my build from my fork [jdrly/FEX](https://github.com/jdrly/FEX) of [athei/FEX](https://github.com/athei/FEX), the FEX Mach9 0.3.1's engine is built from, for that engine: its x86_64 half, `libarm64ecfex.dll` and `libarm64ecfex.so`; only in builds that have it. `VERSION` names the commit, whose source is the complete corresponding source. `gw2om.sh` puts it into the engine's `lib/wine` after `set fex mine` from Terminal, the engine's own kept next to it. It includes or links statically the code listed below this table | `Contents/Resources/components/fex` | MIT, with the licences below | `Resources/Licenses/fex/LICENSE`, `NOTICES`, `VERSION` |
| **Sparkle** 2.10.0, <https://sparkle-project.org> (app updates, off in builds without a feed; with bsdiff, sais, and other notices) | `Contents/Frameworks/Sparkle.framework` | MIT | `Resources/Licenses/sparkle/LICENSE` |
| **Cinzel** (variable, `wght` 400 to 900), copyright 2020 The Cinzel Project Authors, <https://github.com/NDISCOVER/Cinzel>, from [google/fonts `ofl/cinzel`](https://github.com/google/fonts/tree/main/ofl/cinzel) (`Cinzel[wght].ttf`, sha256 `f4d83d34…2a4e0f34`), unmodified | `Contents/Resources/Fonts/Cinzel-Variable.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/Cinzel-OFL.txt` |
| **Marcellus**, copyright 2012 Brian J. Bonislawsky DBA Astigmatic (AOETI), from [google/fonts `ofl/marcellus`](https://github.com/google/fonts/tree/main/ofl/marcellus) (`Marcellus-Regular.ttf`, sha256 `1cf0cd10…4abb2f81`), unmodified | `Contents/Resources/Fonts/Marcellus-Regular.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/Marcellus-OFL.txt` |
| **Alegreya Sans** (Regular, Medium, Bold), copyright 2013 The Alegreya Sans Project Authors, <https://github.com/huertatipografica/Alegreya-Sans>, from [google/fonts `ofl/alegreyasans`](https://github.com/google/fonts/tree/main/ofl/alegreyasans) (sha256 `8fab6341…1b14ea10`, `4b89fe78…44815b43`, `a3055a18…92c9fb8e`), unmodified | `Contents/Resources/Fonts/AlegreyaSans-*.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/AlegreyaSans-OFL.txt` |
| **Lucide** icons (lucide-static 0.460.0), <https://lucide.dev>, drawn from their SVG path data (`src/icons`, `src/native/LucideData.swift`) | in the app's binary | ISC (portions from Feather, MIT) | `Resources/Licenses/lucide/LICENSE.txt` |

FEX's files include or link statically, each under its own licence, whose text is in
`Resources/Licenses/fex/NOTICES` as it is in FEX's tree at the commit `VERSION` names: SoftFloat
3e (BSD-3-Clause), cephes (BSD), fmt (MIT), range-v3 (Boost Software License 1.0, with parts under
libc++'s, Stepanov and McJones' and the SGI STL's licences), rpmalloc (a permission notice with no
conditions), tiny-json (MIT), unordered_dense (MIT) and xxHash (BSD-2-Clause).

The artwork is my design's own, made for GW2 on Mac. That's the ink strokes behind the header,
the painting and the app icon's ensō. The app has no ArenaNet or NCSOFT logo, font or art in it.

DXMT's, `ntdll.so`'s, `winemac.so`'s, FEX's and the addon's binaries aren't in this repository.
`scripts/stage-components.sh` copies them from my development workspace's `work/` folder into the
ignored `prebuilt/`, or takes them from the downloads that `prebuilt.lock` pins. The workspace is
`GW2_ON_MAC_WORKSPACE`, by default `../gw2-on-mac`. DXMT is the fork's CI build for this engine,
and its source is the fork's commit that `VERSION` names. `ntdll.so` is my Wine fork's CI build,
the release asset `ntdll-arm64-<commit>.tar.xz` of jdrly/wine's `arm64-builds`, and its source is
the commit its `VERSION` names. `winemac.so` is the same, from the asset
`macdrv-arm64-<commit>.tar.xz`. FEX is my FEX fork's CI build, the release asset
`fex-arm64-<commit>.tar.xz` of jdrly/FEX's `arm64-builds`, and its source is the commit its
`VERSION` names. The addon's source is [`addon/ui-scale`](addon/ui-scale), and
`scripts/build-addon.sh` builds it. `build.sh` downloads Sparkle at a pinned version and sha256.

## Downloaded at install time

The app doesn't contain or redistribute these. When you click Install, `gw2om.sh` downloads them
onto your Mac from their publishers:

| Component | Source | License |
|---|---|---|
| **Wine engine**, athei's Mach9 0.3.1, `wine-v0.3.1-macos-arm64.tar.xz`: an arm64 Wine 11.21 that runs x86_64 Windows code with FEX. Its release page lists what it's built from: Wine `athei/wine@53def89293a` (wine-11.21-37), FEX `9d4fa4b46b1`, DXMT `athei/dxmt@d903db89036`, Mesa `b9a4007c72c`, vkd3d-proton `364e47ac08c` and GStreamer 1.28.8. The loader `wine.app` is signed by its author with Developer ID and notarized. The app checks the archive against its pinned size and sha256, and the loader against its sha256 and signature | [athei/mach9 v0.3.1](https://github.com/athei/mach9/releases/tag/v0.3.1), with the sources of each component in the repositories it names | each component's own license, as published by its project. Wine is LGPL-2.1-or-later |
| **Steam** (the Windows client, Steam route only): Valve's `SteamSetup.exe` | `https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe` (Valve) | Valve's Steam Subscriber Agreement |

The installer leaves out the engine's SDK, meaning its headers, its x86_64 link libraries, Wine's
tests and man pages, and takes the quarantine attribute off what it unpacks. Then it moves the
engine's DXMT tree, `lib/wine/dxgi/dxmt`, aside unchanged as `dxmt.engine` and puts my DXMT fork's
tree in its place, and moves the engine's `lib/wine/aarch64-unix/ntdll.so` and `winemac.so` aside
unchanged as `ntdll.so.engine` and `winemac.so.engine` and puts mine in their place, with
`win32u.so` as `win32u.so.engine` when my driver's build has one; a setting switches back to
each. After `set fex mine` it does the same with FEX's
`lib/wine/aarch64-windows/xtajit64.dll`, `libarm64ecfex.dll` and
`lib/wine/aarch64-unix/libarm64ecfex.so`. It changes nothing else in the engine, and nothing
inside `wine.app` is touched.

## Trademarks

GW2 on Mac is an unofficial fan project. ArenaNet and NCSOFT don't make, endorse or support it.
Guild Wars 2 is a trademark of NCSOFT Corporation. Steam is a trademark of Valve Corporation. Mac
is a trademark of Apple Inc.
