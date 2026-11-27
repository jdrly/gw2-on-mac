# The present fences and the 128 MB code buffer are on in every build

Decided 2026-11-27. Status: accepted. `arm64` only.

Two lines of `dev-switches.conf` have earned a place in every build. A release reads none of that
file, so until now neither reached a player.

**`DXMT_MTL4_PRESENT_FENCES=1`** (jdrly/dxmt#358, for jdrly/dxmt#353). At Metal 4 the game's
rule presents through a Metal 3 command buffer (`DXMT_MTL4_PRESENT=mtl3`, ADR 0010). That present
encoded no fences but stayed in the fence chain, so Metal 4's waits on it ordered nothing. With the
switch an empty Metal 4 encoder each frame carries the present's fences. It's the candidate fix for the
texture flashing at the Lion's Arch aerodrome on macOS 27 and the GPU hang on macOS 26. It has been
on in every dev build since 0.2.2-dev.1. On 0.2.2-dev.4 (2026-11-27, a crowded hour) the session
had 0 lost presents and no GPU errors, and I saw no flashing. The macOS 26 hang stays unproven until
a player on 26 plays with it.

**`FEX_INITIALCODEBUFFERMB=128`** (#112). FEX starts its code buffer at 16 MB, and each time the
buffer fills it throws every translation away and starts again in one twice the size. At 16 MB GW2
does that twice in the first minutes of every session, on my Mac and on a player's M2 Max. At 128 MB
the buffer never moved in 20 session reports, and held 57.8 MB at most. Since ADR 0025 a release
runs my FEX, so the value can reach players.

So the game's rule has both, in release and development builds alike (#379).

## Consequences

- At Metal 4 the rule has `DXMT_MTL4_PRESENT_FENCES=1` right after `DXMT_MTL4_PRESENT=mtl3`, and
  `CefHost.exe`'s rule unsets it. At Metal 3, or with the engine's own DXMT, neither is there.
- With my FEX in place the rule has `FEX_INITIALCODEBUFFERMB=128` after FEX's other entries, and
  `CefHost.exe`'s rule unsets it. With `fex=engine` it isn't there. Steam keeps FEX's 16 MB, as
  before.
- Each entry still needs the build in place to have its switch, as its dev line did, and each is
  gated on its own: the fences on Metal 4 and the tree, the code buffer on my FEX. The fences
  need my DXMT fork's tree in the engine to name `DXMT_MTL4_PRESENT_FENCES`, and the code buffer
  needs my FEX's `VERSION` to name `FEX_INITIALCODEBUFFERMB` on its `switches:` line. My fork's
  `gw2-on-mac`, which my builds stage, has the fences since jdrly/dxmt#358, and the FEX
  `prebuilt.lock` pins has the code buffer. An older build of mine without a switch doesn't get its
  entry. That is narrower than #379's "whenever the rule sets Metal 4 with `mtl3`" and "whenever the
  game runs my FEX", and with today's builds it changes nothing.
- Neither has a setting or a row in Settings. A `compatdb.local` line of mine comes last and wins,
  in a release too. `FEX_INITIALCODEBUFFERMB=16` or `DXMT_MTL4_PRESENT_FENCES=0` there turns one
  off.
- The dev table goes to version 16, and both rows move to `DEV_GONE`. A file at version 15 loses
  each line as that build wrote it, with its comment. A line I changed stays, and since the file's
  lines come after the rule's entries, it wins. A line I commented out becomes
  `DXMT_MTL4_PRESENT_FENCES=0` or `FEX_INITIALCODEBUFFERMB=16` under a comment, so it stays off.
  16 is FEX's own first size, and FEX logs an error for any number but 16, 32, 64 and 128. A line I
  deleted leaves nothing to keep, so the new default goes in, as it did for `DXMT_MTL4_PRESENT=mtl3`
  at version 4.
- A line kept or written this way goes in as it is, as a line of mine that isn't in the table does,
  whatever FEX or DXMT is in place. Neither the engine's FEX nor a tree without the switch reads it.

## Alternatives I rejected

- **Changing the defaults in the forks.** My FEX at 128 by default would give Steam's processes
  128 MB of address space too. The fences act only with the `mtl3` present, which is the app's
  choice (ADR 0010), so the app sets them next to it. The rule sets both for `Gw2-64.exe` alone.
- **A row in Settings for either.** Neither is a choice a player can judge, and `compatdb.local`
  already turns one off for me.

## Evidence

- jdrly/dxmt#358 (the fences), jdrly/dxmt#353 (the aerodrome's flashing and the hang), the
  0.2.2-dev.4 session of 2026-11-27.
- #112 and `advisor-plans/2026-11-26-topic-analysis/ANALYSIS-fex.md` in the GW2 on Mac workspace,
  section `code-buffer`.
- ADR 0010 (Metal 4 with the `mtl3` present), ADR 0025 (releases run my FEX), #364.
