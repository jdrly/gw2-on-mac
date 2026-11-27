# The job workers stay out of the lock spin

Decided 2026-11-27. Status: accepted. `arm64` only.

The job-worker study found GW2's job workers sleeping on GW2's own critical sections tens of
thousands of times a second, 80% of the sleeps shorter than 20 µs. Under my Wine each sleep costs a
kernel wait and a kernel wake. So I gave the workers the lock spin my Wine fork already gives the
game thread (`lock=20`). Dev build 0.2.2-dev.3 spun every other worker (#368, jdrly/wine#59), and a
third session spun all of them. All three sessions ran on my M5 Max with Debug logging and #365's
per-thread counters.

| | dev.2, no worker spin | dev.3, half the workers spin | dev.3 + `lock=20` on every worker |
|---|---|---|---|
| Session | 390 s | 245 s | 235 s |
| Workers' lock sleeps a second | 37,800 | 32,900 | 7,600 |
| Workers' CPU, user + kernel | 1.36 cores | 2.25 | 2.82 |
| Workers' CPU per job handed on | 0.112 ms | 0.089 | 0.115 |
| Game thread asleep on locks | 16 ms a second | 24 | 41 |
| Hitches over 50 ms, a minute | 2.9 | 7.1 | 4.3 |
| Median fps / 10th percentile | 57.5 / 45.0 | 59.8 / 50.5 | 59.9 / 45.3 |

Inside the dev.3 session, the 9 spinning workers slept 88% less than the 8 others and handed on 38%
more jobs, at 11% less CPU a job. With every worker spinning, the CPU a job is back where it was
without the spin, because the kernel time saved goes into spinning. The game thread, which sets the
frame, sleeps 2.5 times as long on the same locks: the spinning workers take them first. The
sessions ran at different places with different crowds, so the table isn't an A/B. But the rows
that matter for the frame point the same way, and I felt more drops below 60 on dev.3.

The workers' lock cost is GW2's own contention, and a spin only moves it onto the game thread. A dev
build's `WINE_HEAT_SPIN` line is `lock=20:game,event=30:game` again, the *Faster locks* row's own
value (#370).

## Consequences

- The dev table goes to version 14. A `dev-switches.conf` with version 13's line as that build wrote
  it gets the new line at the end, and so does one still at version 12 with that build's `sem=5`
  line. A value I changed, a line I commented out and a line I deleted stay as they are.
- `dev_gone` and `dev_update` keep one entry per row of the list of lines taken out, not one per
  variable, since `WINE_HEAT_SPIN` now has two rows there.
- My Wine fork keeps the `halfworkers` scope. It does nothing while no line names it, and it's how I
  would test a worker spin again.
- #365's per-thread counters stay. They measured this.
- The study's lever 2, a spin count on GW2's critical sections, is the same mechanism and is dropped
  too.
- The release row is unchanged.

## Alternatives I rejected

- **Keeping half the workers spinning.** It was a comparison inside one session, and that session
  had the most hitches of the three.

## Evidence

- GW2 on Mac workspace: `docs/research/worker-spin-2026-11-27.md`, and the three Collect Logs
  bundles in `work/player-logs/2026-11-27/`.
- `advisor-plans/2026-11-26-job-workers/STUDY.md` in the workspace, for the sleeps and lever 2.
- #368 and jdrly/wine#59 (the `halfworkers` scope), #365 and jdrly/wine#58 (the counters).
