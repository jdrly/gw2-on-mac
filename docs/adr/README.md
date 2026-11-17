# Decisions

One file per design decision, numbered in one series for the whole repository. `main` (0.1.x)
holds the ones that bind it. The 0.2 line's ADRs, 0003 to 0010, 0012 and 0013, live on the
`arm64` branch. The numbers follow the order I wrote them down, not the dates I decided.

| ADR | One line |
|---|---|
| [0001](0001-the-x86-64-engine-is-hosted-in-jdrly-wine-engine.md) | athei's `cx-*` releases vanished, so the 0.1.x engine and its source are hosted in jdrly/wine-engine, byte for byte the same file. |
| [0002](0002-an-approved-release-ships-without-coming-back-to-me.md) | After a fix I approved merges, the dispatcher builds, signs, notarizes and publishes the release. |
| [0011](0011-the-project-rules-that-bind-the-app.md) | The project-wide rules in a sentence each, pointing to the workspace ADRs. Binds both lines. |
| [0014](0014-cooler-job-workers-are-off-by-default-on-0.1.x.md) | *Cooler job workers* defaults to off from 0.1.5, and an untouched 3 from an older install reads as off. |
