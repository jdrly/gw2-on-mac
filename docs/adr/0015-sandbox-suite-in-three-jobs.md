# The sandbox suite runs as three groups in three jobs

Decided 2026-11-17. Status: accepted. `arm64` only. It changes 0012, which made two groups.

0012's `steam` group was the life of one Steam install, and it set the run's length: 646 s on a
pull request (run 43873442914), with no place to start over. Its second half, from "Steam in the
background after the first login" to `Uninstall`, worked on the install and the settings its first
half left. Now `GROUP` cuts `scripts/test-sandbox.sh` there too, and the second half makes its own
install. `settings` is the dry runs to Collect Logs on one Steam install. `sessions` is Steam in
the background to `Uninstall`, and when it runs alone it starts with `fixture_install`. `rest` is
unchanged: what starts from nothing after `Uninstall`. The Checks workflow runs the three as a
matrix of three jobs with a limit of 15 minutes, 20 for `sessions` since #269. Without `GROUP` the
suite runs as it always did and never calls the fixture.

`fixture_install` is the install from "Install through Steam" and "Steam downloads the game", then
the few lines the first half's other sections leave behind and the session checks read: launch
options, `ncpu` below 8 CPUs, the interface scale, Metal 3 with debug off, and Steam's `config/`
folder. I found each by copying the sandbox at the cut once after the first half and once after the
fixture, and comparing the two.

In the pull request run 44123244664, on a slow runner, the suite's own seconds were 577, 435 and
382 for `settings`, `sessions` and `rest`, and the jobs took about 10, 8 and 7 minutes. In the dev
build dry run of the same commit the three groups took 254, 270 and 411 s.

## Consequences

- For about six minutes a run holds four macOS runners, the three groups and `renders`. My account
  gets five at once across all my repositories.
- A section before Collect Logs that leaves state the session checks read needs the same line in
  `fixture_install`, or `GROUP=sessions` starts from another install than the full run. The
  full run never calls the fixture, so only the `sessions` job shows the difference.
- The stand-in engine's `ok` counts in each group, so the three counts add up to two more than a
  full run's.
- The dev build calls the same jobs through `checks.yml`, and its `package` job waits for all
  three.
- On 2026-11-19 I gave `sessions` 20 minutes and kept 15 for `settings` and `rest` (#269). After
  #278 brought ReShade's sections from `main`, `sessions` took 13 min 58 s (Checks run
  44448554814), about 226 s of that in ReShade's sections.
- 0012's rule for a new section still holds: it goes into the group whose install it uses, and a
  section that starts from nothing goes into `rest`, or into a group of its own once `rest` passes
  8 minutes.
- On 2026-11-19 the move of 0.1's install (#281) got that group of its own, `move` (#285): `rest`
  ran out of its 15 minutes in the 0.2.0-rc.1 dev build (run 44464935469). Each group's limit is
  now about 1.7 times its slowest job, as `checks.yml` says. The stand-in engine's `ok` isn't a
  pass in `move`, so the four counts still add up to two more than a full run's.

## Alternatives I rejected

- **Cutting `steam` without a fixture.** The second half then needs the first half's install, so the
  two can't run side by side.

## Evidence

- #250, PR #255 (`6d3e44b`): the three pass counts on the rented M1 (412, 213 and 143, the whole
  suite's 766 plus 2) and `GROUP=sessions` five times in a row.
- Checks run 44123244664 and Dev build dry run 44123244879, both at PR #255's last commit.

Source: `advisor-plans/2026-11-17-ci/003-app-sandbox-sessions-group-own-install.md` in my
workspace, for #250.
