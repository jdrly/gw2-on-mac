# A release candidate is a dev build by another name

Decided 2026-11-19. Status: accepted. `arm64` only.

Since 0.2.0-dev.23 (Mach9 0.4.0) 0.2 plays as well as 0.1.x, so the builds that lead up to 0.2.0
are release candidates: `0.2.0-rc.1`, `0.2.0-rc.2` and so on. A release candidate is built and
published exactly as a dev build is (ADR 0004): by the Dev build workflow, ad hoc signed, not
notarized, as a pre-release that can never become `releases/latest`. It has the dev channel, so it
has no feed, compiles the dev-only UI in and starts with every switch on (ADR 0009). Only its name
differs:

- the version is `X.Y.Z-rc.N`, where a dev build's is `X.Y.Z-dev.N`
- the chip in the window's header says "Release candidate · 0.2.0-rc.1", and About says
  "(release candidate)"
- the pre-release's title, its generated notes and the build's record say "release candidate"

`CFBundleVersion`, which Sparkle compares, puts a release candidate above every dev build of the
same version and below the release: `0.2.0-dev.N` is `0.1.9999.(1000+N)`, `0.2.0-rc.N` is
`0.1.9999.(2000+N)`. N stays below 1000 in both, so the two ranges can't meet. `build.sh` stops at
any other form of version, and the workflow's plan job refuses it before anything is built.

## Consequences

- `release.sh --adhoc` still refuses a version below `build.sh`'s default. `sort -V` puts every
  `-dev.N` before `-rc.1`, so once that default is a release candidate, no dev build of the same
  version can follow it. Today the default stays `0.2.0-dev.5` and I give the version with
  `-f version=`.
- The notes of a release candidate count the DXMT changes since the previous pre-release, dev build
  or release candidate.
- The release itself, 0.2.0, is out of this decision. It needs my Developer ID, notarization and
  the feed (ADR 0002 on `main`), as 0.1.x's releases do.

## Alternatives I rejected

- **A dev build numbered on, `0.2.0-dev.24`.** It works, but the version wouldn't say that this is
  the build I mean to release.
- **A release candidate with a feed.** Sparkle could offer the next candidate, but that needs a
  signed, notarized build and a second appcast. A pre-release I download with `gh` is enough for
  the few builds before 0.2.0.

## Evidence

- #267 and its pull request.
- #21's comment of 2026-11-19: 0.2 matches 0.1.x since 0.2.0-dev.23.
