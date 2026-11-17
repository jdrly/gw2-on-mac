# The x86_64 Wine engine is hosted in jdrly/wine-engine

Decided 2026-11-11. Status: accepted.

0.1.x downloads its Wine engine at install: athei's `cx-26.3.0-8` build, pinned by sha256. On
2026-11-11 that download broke for every new install. athei had renamed `athei/wine-build` to
`athei/mach9`, an arm64 Wine, and the `cx-*` releases no longer existed. The pinned source commit
`d23b397` was on no branch of his any more. I decided to host the engine myself, in
jdrly/wine-engine, release `cx-26.3.0-8`: the same archive byte for byte, with its Wine source next
to it. With the original gone I had no other choice.

## Consequences

- The app downloads from jdrly/wine-engine and checks the same sha256 as before (`1976c331…60456d`,
  234,978,748 bytes). 0.1.3 shipped the new address.
- The engine itself did not change. I wouldn't move 0.1.x to athei's arm64 Wine that day, because
  nobody had tested it under the game. That move became the 0.2 line (ADR 0003, on the `arm64`
  branch).
- The archive carries Apple's D3DMetal, whose licence allows distribution for non-commercial
  purposes only. Hosting it rests on the apps staying free and open source, which I committed to the
  same day. That is my reading of the licence text, not legal advice.
- Every project of mine on this engine needed the address: SWTOR on Mac (released as 0.1.7.1), SWGL
  on Mac (its build only), the GW2 and CS2 workspaces' scripts.
- SWTOR on Mac's ADR 0002 had said "no engine mirror, for licensing reasons". Its ADR 0006 reverses
  that for the same event.

## Alternatives I rejected

- **Moving 0.1.x to athei's new arm64 engine.** I don't put untested Wine under a released app.
- **No mirror, for licensing reasons.** That was SWTOR on Mac's ADR 0002. With the original gone it
  meant no engine at all.

## Evidence

- jdrly/gw2-on-mac #18, PR #19, release 0.1.3.
- jdrly/wine-engine, release `cx-26.3.0-8`.
- The dispatcher's note `wine-engine-host` (what I said on 2026-11-11).
- GW2 on Mac workspace `AGENTS.md`, "Tooling".
