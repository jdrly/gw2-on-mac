# Release notes

`<version>.md` here are the notes of each release, in SWTOR on Mac's format (its
`release-notes/README.md`). `scripts/release.sh` puts them, unchanged, into the GitHub release
and the update window (Sparkle). Nothing is published yet: GW2 on Mac has no GitHub release and
no feed (see the [README](../README.md), *Releasing*).

```markdown
## GW2 on Mac 0.1.1

One sentence that says what this release is about.

### First change, as a short headline
What changed and what it means for the player, in a short paragraph. Technical references
go in inline code, e.g. DXMT `684f428`.

### Second change
- Bullets are fine when a change has several parts.
- Keep each bullet to one or two sentences.

### After updating
Open GW2 on Mac and click *Repair* in the window (with the game and Steam closed).

### Support
GW2 on Mac is an unofficial project, not made, endorsed or supported by ArenaNet or NCSOFT, and
you use it at your own risk. Please send questions and bug reports to Pharaphobia on
[Discord](https://discord.gg/AnV3fZWz2b) or as a [GitHub issue](https://github.com/jdrly/gw2-on-mac/issues),
never to ArenaNet's support.
```

| Part | Required |
|---|---|
| `## GW2 on Mac <version>` | yes, the first line |
| Summary | yes, the first paragraph after the title, one sentence |
| `### <change>` | at least one |
| `### After updating` | only when the player has to do something |
| `### Support` | yes, last, with the wording above |

- No other `##` headings and nothing below `###`: the update window styles `###` as a change and
  nothing deeper.
- Inline code (`` `684f428` ``) for technical references. Code blocks only in development builds;
  the update window doesn't format them.
- Development builds (`<version>-dev.N`) use the same structure, with `(development build)` after
  the version in the title.
- Support links both [Discord](https://discord.gg/AnV3fZWz2b) (the server SWTOR on Mac and
  gw2onmac.com use) and the GitHub issues: not everybody who plays has a GitHub account.
