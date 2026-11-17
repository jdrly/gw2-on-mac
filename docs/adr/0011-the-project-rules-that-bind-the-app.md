# The project's rules that bind the app

Recorded 2026-11-17. Each rule has its own date in the workspace ADR it points to. Status: accepted.

The app is one of four repositories of GW2 on Mac, next to my DXMT, Wine and FEX forks, and some of
my rules hold across all of them. Their full records are ADRs in the project's workspace, which is
not public. So that a reader of this repository finds them, each rule is stated here in a sentence,
with the workspace ADR that holds the reasons.

## Consequences

- **Nothing caps the game below 60 fps.** Nobody proposes a frame cap below 60, or anything that
  trades frame rate for heat or power, and no dev build turns one on. Heat and power come down by
  removing work from each frame. Workspace ADR `0001-no-frame-cap-below-60`.
- **No D3DMetal comparison runs.** A rendering bug is diagnosed in my DXMT fork, not by switching
  the app to D3DMetal. Workspace ADR `0002-no-d3dmetal-comparisons`.
- **Changes are validated in my normal play.** A change is judged from the session report and the
  logs of sessions I play anyway. An issue's UAT names that session and is mine to play. Workspace
  ADR `0003-changes-are-validated-in-my-normal-play`.
- **A regression gets its root cause, not a workaround.** When 0.2 is worse than 0.1.x, the
  difference between the stacks is the bug. No setting is added that only hides it. Workspace ADR
  `0011-a-regression-gets-its-root-cause-not-a-workaround`.
- **Nothing goes upstream.** The app has no upstream. Nothing from its work goes to the upstreams of
  the forks it bundles: 3Shain/dxmt, athei's repositories, WineHQ or FEX-Emu/FEX. Each fork has that
  rule as an ADR of its own.
- **Runner time.** One push per pull request after its review, and no push to see what the runner
  says. In the forks it is also one run at a time, and each push on the dispatcher's go. Workspace
  ADR `0010-one-run-at-a-time-and-each-push-needs-a-go`.
- **No reruns.** A job that failed a test or a build is never rerun. A new push starts a new run.
  One rerun is allowed for a job that a GitHub outage killed, that never got a runner, or that
  failed only in a GitHub-provided action's network call. Workspace ADRs `0006` to `0009`.
- The workspace has five more ADRs that touch this repository: everything is written in my first
  person (`0004`), checks run on GitHub's runners (`0005`), my builds are named arm64 (`0012`), the
  weekly upstream watch (`0013`), and design decisions are recorded as ADRs (`0014`).

## Alternatives I rejected

- **Keeping these rules only in the workspace.** The workspace has no remote, so a reader of this
  repository can't open it. The sentence here is the rule, and the workspace ADR is the full record
  with its reasons.
- **A full copy of each ADR in every repository.** I asked for a short ADR that states each rule in
  a sentence and points to the workspace.

## Evidence

- GW2 on Mac workspace `docs/adr/0001`, `0002`, `0003`, `0006` to `0011`.
- My answer of 2026-11-17 on the form of the ADR backfill, relayed by the dispatcher
  (`advisor-plans/2026-11-17-adr-backfill/README.md` in the workspace).
- This repository's ADRs 0004 and 0009, on the `arm64` branch.
- jdrly/dxmt ADR 0006, jdrly/wine ADR 0001, jdrly/FEX ADR 0001.
