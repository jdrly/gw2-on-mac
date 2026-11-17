# Dev builds of 0.2 come from GitHub's runners, ad hoc signed, and can never become latest

Decided 2026-11-11. Status: accepted.

By day the agents work on my Linux server, which can't build the app, and the Mac is mine to use. So
a workflow builds each 0.2 dev build on GitHub's runners. It is ad hoc signed, without my Developer
ID and without notarization, and published as a pre-release that can never become `releases/latest`.
The app reads its update feed from `releases/latest/download/appcast.xml`, so a dev build must never
be what that address serves.

## Consequences

- `devbuild.yml` takes the commits of my DXMT, Wine and FEX forks as inputs and fetches their
  published archives (`dxmt-arm64-<sha>`, `ntdll-arm64-<sha>`, `macdrv-arm64-<sha>`,
  `fex-arm64-<sha>`) from each fork's `arm64-builds`. A build's record names all of them with their
  sha256.
- The DMG isn't notarized, so I download it with `gh` or clear the quarantine attribute.
- A dev build has the dev channel and an empty feed. It doesn't update itself.
- Releases for players, Sparkle's key, Developer ID signing and notarization stay on my Mac (ADR
  0002).
- A dev build carries everything that has merged. On 2026-11-13 I held one back so a change would
  come in a build of its own, and took that back.
- Developer ID signing and notarization on the runner is #51. It waits for my secrets.

## Alternatives I rejected

- **Building dev builds on my Mac.** The agents work on the server and can't build there, and I had
  asked the same day to move what can move to GitHub, so it doesn't load my Mac.
- **Notarized dev builds from the runner.** That needs my signing secrets in the repository. Open as
  #51, not rejected for good.

## Evidence

- #48 (the workflow; `0.2.0-dev.4` was its first build), #49, #50, #51, #122.
- GW2 on Mac workspace `plans/night/2026-11-11-plan.md`, 2026-11-11 19:08 ("My four decisions"),
  2026-11-12 00:14 (dev.4 published), 2026-11-13 08:20 (a dev build carries everything).
- The dispatch project file `gw2-on-mac.md`, "Dev builds"; the dispatcher's note
  `arm64-0-2-line-and-ci` (my request to move checks to GitHub).
