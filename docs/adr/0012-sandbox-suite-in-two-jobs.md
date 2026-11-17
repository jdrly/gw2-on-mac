# The sandbox suite runs as two groups in two jobs

`scripts/test-sandbox.sh` stays one file, and `GROUP` cuts it where it starts from nothing again,
after `Uninstall`. `steam` is the life of one Steam install, from the dry runs to `Uninstall`.
`rest` is what follows: the ArenaNet route, a failed install, existing game files and a
development build's switches. The Checks workflow runs the two as a matrix of two jobs, each with
a 20-minute limit. Without `GROUP` the suite runs both, as it always did. Before this, one job ran
about 760 checks in a row, 14 to 15 minutes on a pull request and 26 to 30 in a dev build, and
dev.20 hit the job's 30-minute limit.

I didn't run the two groups side by side in one job. The watch-session checks wait on short
clocks, a 2 s grace and a look every 0.2 s, and the runner has 3 CPUs. #190 was a flake of exactly
those checks. I didn't split the file either. Almost every open pull request edits it, and the two
`if` blocks leave its lines unindented, so those pull requests still rebase. A cut inside `steam`
needs an install the second part can start from, which is a change of its own.

## Consequences

- A run holds one more macOS runner while both groups run, three with `renders` where it held
  two. My account gets five at once across all my repositories, so a busy hour queues jobs
  sooner.
- `rest` may use only what the shared part before the gates makes. That part now builds the
  stand-in PEs, arcdps.dll and nexus.dll, and the sleeper, which `rest` copies too. They used to
  be made in the arcdps and Busy checks sections. `play_cmd` moved there as well.
- A new section goes into the group whose install it uses. A section that starts from nothing goes
  into `rest`, or into a group of its own once `rest` passes 8 minutes.
- The suite prints the seconds each section took at its end, and on a runner it adds them to the
  job's summary. The next slow section shows in the run that has it.
- The dev build calls the same jobs through `checks.yml`, and its `package` job waits for both.
  The first `ok`, the stand-in engine's, counts in both groups, so their two counts add up to one
  more than a full run's.

Source: `advisor-plans/2026-11-17-ci/002-app-sandbox-two-groups-and-section-seconds.md` in my
workspace, for #230.
