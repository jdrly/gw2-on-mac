# Release notes

Each `<version>.md` here holds the notes for one release. I use the same format as SWTOR on Mac,
whose `release-notes/README.md` this follows. `scripts/release.sh` copies the file unchanged into
the GitHub release and into the update window that Sparkle shows. Releases so far are 0.1.0 and
0.1.1, both on the [releases page](https://github.com/jdrly/gw2-on-mac/releases).

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
Open GW2 on Mac and click *Repair* in the window, with the game and Steam closed.

### Support
GW2 on Mac is an unofficial project. ArenaNet and NCSOFT don't make, endorse or support it, and
you use it at your own risk. Please send questions and bug reports to me, Pharaphobia, on
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

Rules for the notes:

- Use no other `##` headings and nothing below `###`. The update window styles `###` as a change
  and nothing deeper.
- Put technical references in inline code, like `` `684f428` ``. Code blocks only belong in
  development builds, because the update window doesn't format them.
- Development builds, `<version>-dev.N`, use the same structure with `(development build)` after
  the version in the title.
- The support section links both [Discord](https://discord.gg/AnV3fZWz2b) and the GitHub issues.
  The Discord server is the one SWTOR on Mac and gw2onmac.com use, and not everybody who plays has
  a GitHub account.
