# Releases start on my FEX from 0.2.2

Decided 2026-11-26. Status: accepted, on a condition. `arm64` only. Issue #362. The workspace's
ADR 0015 (its extended section) records the decision for all of my forks; this is the app's part.

Until 0.2.1 the setting `fex` starts at `engine`, so a release runs the engine's own FEX and none
of my FEX topics reaches a player. A development build with my FEX has started on it since its
first switch rows (ADR 0009), and the counters' fix needs it too (ADR 0024).

## Decision

From 0.2.2 on, a release starts on my FEX, if the dev build with the pinned FEX, 0.2.2-dev.4,
plays as well as 0.2.1. The workspace's ADR 0015 named dev.1. The pin moved after it (below), so
the build I play is the first one with that FEX. The pull request that does it merges only after
I have played that build.

- `fex` defaults to `mine`. It takes effect only in a build that carries my FEX
  (`components/fex`). A build without one keeps the engine's own, as before.
- `SETTINGS_RESETS` version 4 resets `fex` (version 3 is `fastlocks`, ADR 0027). Every release's
  `settings.conf` until then says `fex=engine`, because Install and Repair write every key, so an
  update from 0.2.1 reads `mine` and the next Play or Repair puts my FEX in. A `set fex engine`
  after that stays.
- `fex=mine` leaves the development build's switch rows (`DEV_ROWS`), whose value is now the
  default. A release reads those rows at their defaults over a development build's file, so with
  `fex` still among them it would drop a `fex=engine` I set in a development build.
- `prebuilt.lock` pins my FEX (`fex_url=`, `fex_sha256=`), as it pins my KosmicKrisp (ADR 0023):
  first `jdrly/FEX` `537a2281c`, the FEX 0.2.2-dev.1 carries, then `9085ab554ec`, which 0.2.2-dev.4
  carries: the same series after the drops of jdrly/FEX#28 (suspend-fix) and #29
  (entry-compile-lock, codegen-cuts and singlestep-fix). `scripts/stage-components.sh --fetch`
  stages it with the refusals it already has for my FEX.
- `scripts/release.sh` refuses a release from 0.2.2 on whose app carries no FEX of mine, or one of
  another commit than the pin, before it signs anything. I build releases on my Mac, where
  `stage-components.sh` takes FEX from the workspace unless I pass `--fetch`, so without this
  check the pin would bind nothing. Development builds and release candidates may go without.

## Consequences

- A release runs my FEX with its own defaults: the block lookups (#161, #162, on in my FEX since
  #266), and with my `ntdll.so` and Debug logging FEX's counters (ADR 0024). The FEX lines of
  `dev-switches.conf`, such as the return lookup and the AVX hiding, stay off in a release: a
  release never reads that file. Each needs a row or a default of its own to reach a player.
- A 0.2.1 player who ran `set fex engine` from Terminal gets my FEX once. The key has no row in
  Settings, and the file can't tell that choice from the default.
- Each new FEX commit for a release is a new pin in `prebuilt.lock`, as `9085ab554ec` was.
- The Dev build still takes my FEX only with `fex_commit`. Without it, a dev build has none.
- Checks now stage my real FEX instead of the stand-in, and the sandbox's fresh installs end on
  it.

## If 0.2.2-dev.4 doesn't play as well as 0.2.1

The pull request doesn't merge, and 0.2.2 ships as 0.2.1 did, on the engine's own FEX. I file
what I saw against my FEX fork first.
