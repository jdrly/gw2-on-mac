# Architecture decision records

One decision per file. The files go by number, not by date. 0001 to 0011 record older decisions. I
wrote them down on 2026-11-17, after 0012 and 0013 had landed, and kept their numbers below
those two. Their dates don't follow their numbers. A new decision takes the next free number.

0001, 0002 and 0014 are about 0.1.x and live on `main`. 0003 to 0010, 0012, 0013 and 0015 to 0018
are about the 0.2 line on this branch, `arm64`. 0011 is on both. The two branches share one set of
numbers, so a number taken on one is not used on the other.

| File | Decided | One line |
|---|---|---|
| `0001-the-x86-64-engine-is-hosted-in-jdrly-wine-engine.md`, on `main` | 2026-11-11 | athei's `cx-*` releases vanished, so the 0.1.x engine and its source are hosted in jdrly/wine-engine, byte for byte the same file. |
| `0002-an-approved-release-ships-without-coming-back-to-me.md`, on `main` | 2026-11-11 | After a fix I approved merges, the dispatcher builds, signs, notarizes and publishes the release. |
| [0003](0003-0.1.x-is-the-stable-rosetta-line-and-0.2.x-the-arm64-line.md) | 2026-11-11 | 0.1.x gets fixes and its own app features, and nothing of the arm64 engine. My DXMT fork is shared. 0.2.x runs on Mach9's arm64 Wine, step by step, each compared with 0.1.x. |
| [0004](0004-dev-builds-come-from-github-runners-ad-hoc-signed.md) | 2026-11-11 | 0.2 dev builds are built on GitHub's runners, ad hoc signed, as pre-releases that can never become latest. |
| [0005](0005-the-0.2-settings-have-no-dxmt-wine-or-mac-driver-choice.md) | 2026-11-12 | The DXMT, Wine and Mac driver rows left the 0.2 Settings. The app runs my pieces, and the keys stay in the backend. |
| [0006](0006-0.2-has-no-cooler-job-workers.md) | 2026-11-12 | The Cooler job workers row and its port to the arm64 engine are dropped. 0.1.x keeps the row, off by default from its next release (#248). |
| [0007](0007-0.2-shows-itself-as-gw2-on-mac-and-keeps-its-own-name-on-disk.md) | 2026-11-12, superseded by 0018 | Nothing shown says "arm64". The bundle id and folders keep it, so 0.2 installs beside 0.1.x. |
| [0008](0008-the-app-writes-emulatemodeset-off.md) | 2026-11-12 | `EmulateModeset`=`N`, for 0.1.x's behaviour and the Gamma slider. Not the cursor stutter's fix, as first recorded. |
| [0009](0009-a-dev-build-starts-with-every-switch-on.md) | 2026-11-12, narrowed 2026-11-15 | Dev builds turn every fork switch on from `dev-switches.conf`. Not a cap below 60, and not a hot-path cost without a symptom seen in play. |
| [0010](0010-0.2-defaults-to-metal-4-with-the-metal-3-present.md) | 2026-11-13 | The *Metal* row defaults to Metal 4 with `DXMT_MTL4_PRESENT=mtl3`. Supersedes the Metal 3 default of the day before. |
| [0011](0011-the-project-rules-that-bind-the-app.md) | recorded 2026-11-17 | The project-wide rules in a sentence each, pointing to the workspace ADRs. |
| [0012](0012-sandbox-suite-in-two-jobs.md) | 2026-11-17 | The sandbox suite stays one file and runs as two groups in two jobs, each with a 20-minute limit. |
| [0013](0013-checks-skip-renders-and-addon-by-change.md) | 2026-11-17 | A pull request skips `renders` when every file it changes is on a list the pictures can't depend on, and runs `addon` only when it touches the addon. |
| `0014-cooler-job-workers-are-off-by-default-on-0.1.x.md`, on `main` | 2026-11-17 | *Cooler job workers* defaults to off from 0.1.5, and an untouched 3 from an older install reads as off. |
| [0015](0015-sandbox-suite-in-three-jobs.md) | 2026-11-17 | The suite's `steam` group splits into `settings` and `sessions`, and `sessions` starts from an install it makes itself. Three jobs, 15 minutes each, `sessions` 20 since #269. |
| [0016](0016-an-engine-of-another-release-is-replaced-by-repair.md) | 2026-11-17 | An engine an earlier version of the app installed counts as installed. Play refuses and names Repair, which replaces it with the pinned one. |
| [0017](0017-a-release-candidate-is-a-dev-build-by-another-name.md) | 2026-11-19 | A release candidate, `X.Y.Z-rc.N`, is built and published as a dev build is. Only its name and the chip differ, and it sorts above every dev build of its version. |
| [0018](0018-0.2-is-the-same-app-as-0.1.x-and-keeps-its-own-folders.md) | 2026-11-19 | 0.2 takes 0.1.x's file name, bundle id and feed, so 0.1.4 updates to it. Its folders keep "GW2 on Mac arm64". 0.1.5 is the last 0.1.x I plan, and the minimum macOS is 26.4. |
