# A pull request's dry run runs the settings group alone, and no renders

Decided 2026-11-19. Status: accepted. `arm64` only. It narrows two lines of earlier records for a
pull request's dry run: 0013's "a dev build runs `renders`" and 0015's "`package` waits for all
the groups". A dev build I dispatch keeps both.

A pull request that changes a build script or a workflow starts Checks and a Dev build dry run on
the same commit. Both ran the four sandbox groups and `renders`, five macOS jobs each, and my
account runs five at once. In the five dry runs since #286 the jobs waited 44:53 for a runner in
the median, and such a push went green after 31:29 against 16:32 with Checks alone.

The two runs mostly checked the same things. On one commit, dry run 44557321338 and Checks
44557321348 shared about 905 checks. The dry run's app has my real DXMT and none of my `ntdll.so`,
`winemac.so` or FEX, so it ran 22 checks Checks doesn't, 20 of them in `settings`. Its suite went
red where Checks was green four times, each time for the test and never for the app.

So `devbuild.yml` passes `checks.yml` two inputs on a pull request: `groups` `["settings"]` and
`renders` false. The dry run still proves what only it can: the plan, my real DXMT staged with its
refusals, the build from it, `settings` on an app without my other three files, and the package.
Checks runs every group and `renders` on the same commit. A run I dispatch, with publish false or
not, runs every group and `renders`, as before.

## Consequences

- Two checks in `sessions` run in no pull request run, and in no build dispatched with all my
  components: "repair unpacks the engine again and puts the ntdll.so Settings asks for in:
  engine" and "repair unpacks the engine again and puts the winemac.so Settings asks for in:
  engine, and the ntdll.so: engine". Checks runs both with `mine`. A build dispatched without
  `wine_commit` and `macdrv_commit` still runs them with `engine`.
- A pull request no longer runs `sessions`, `rest` and `move` against my real DXMT. The next dev
  build I dispatch does, before it publishes anything.
- `groups` is a JSON array, because an expression can't split a string. Empty, or Checks run on
  its own, is all four.
- The dry run's `settings` job is a sixth macOS job, so it can wait for a runner while Checks
  holds five.

## Alternatives I rejected

- **No sandbox group in the dry run.** That saves the sixth job, but then the 20 checks for an app
  without my files run in no pull request run. No build I ship is such an app today, and I'd
  still rather keep them.
- **Keeping the dry run whole.** Its extra coverage is 22 checks, and it doubled the wait on 15 of
  my last 27 pull requests.

## Evidence

- #318. Dry run 44557321338 and Checks 44557321348 on one commit: the `sessions` logs differ by
  the two checks above, run with `engine` in the dry run and with `mine` in Checks.
- `advisor-plans/2026-11-19-ci-audit/AUDIT.md` in my workspace, recommendation 1.
