# An approved release ships without coming back to me

Decided 2026-11-11. Status: accepted.

When a fix I approved to ship is merged, the dispatcher that merged it does the whole release:
build, Developer ID signing, notarization, the DMG, the Sparkle feed, the draft, its checks and the
publish. It doesn't hand the build and the publishing back to me. On 2026-11-11 the 0.1.3 hotfix for
the engine download (#18) was merged and the release was left for me, while new installs were broken
for every player. I asked why that was on me. It should have been automated, with the build already
on its way.

## Consequences

- The release runs from a clean `main` at the merged commit, with the same feed URL and Sparkle
  public key as the releases before it. Without them Sparkle is off.
- `scripts/release.sh` signs, notarizes, builds the DMG and the feed with deltas, checks the feed
  and makes a draft `v<version>`. It needs `release-notes/<version>.md`.
- The draft is checked before it is published: five assets, target `main`, the version in the feed.
  After publishing, `releases/latest/download/appcast.xml` must serve the new version and the DMG's
  sha256 must match the local file.
- Signing and notarization need my Mac. A dispatcher on my Linux server can't release, so a release
  waits for a chat on the Mac.
- This covers work I already approved to ship. A release nobody asked for still needs my word. That
  limit is the dispatcher's reading. I didn't say it in those words.
- Dev builds are a different path and never become `latest` (ADR 0004, on the `arm64`
  branch).
- Other projects have their own release kits. A version there is named from that project's plan, not
  from this rule.

## Alternatives I rejected

- **Handing the release to me after the merge.** New installs were broken for every player
  meanwhile, and I expected this to be automated.

## Evidence

- The dispatcher's note `app-releases-are-mine-to-ship` (what I said on 2026-11-11, and the steps).
- jdrly/gw2-on-mac #18, PR #19, release `v0.1.3`.
- `scripts/release.sh`, `build.sh`.
