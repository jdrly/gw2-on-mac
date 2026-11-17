# Checks skip renders and addon when the change can't reach them

A Linux job, `changes`, reads the pull request's files and decides two macOS jobs. `renders` is
skipped when every file is on a short list the pictures and the Swift model can't depend on:
`src/gw2om.sh`, `src/collect-logs.sh`, `scripts/test-sandbox.sh`, `scripts/session-report.sh`,
`scripts/compatdb-check/`, `release-notes/`, any `.md`, `addon/` and `scripts/build-addon.sh`.
`scripts/ui-render.swift` draws made-up states and starts no `gw2om.sh`; the sandbox suite pins
the backend's texts. `addon` runs only when the pull request touches `addon/`,
`scripts/build-addon.sh` or `checks.yml`. A dev build skips `addon`, because its `components`
job has run `scripts/build-addon.sh` with its test on the same commit, and runs `renders`. A push
to `main`, or a pull request whose files can't be read, runs both.

Of my last 20 pull requests, 9 changed only files on the list and none touched `addon/`. The two
jobs took about 2.8 macOS runner minutes per pull request, and one of my five macOS runners for
four minutes of every run.

I didn't use `on.pull_request.paths`. It skips the whole workflow, and `lint`, `build` and
`sandbox` run on every pull request. The list names what `renders` can't depend on, not what it
needs, so a new file nobody listed runs it. That is the safe side.

`changes` gets only `contents: read`, the workflow's default. `devbuild.yml` calls `checks.yml`
from a job that grants no more, and a called workflow's job can't ask for more than its caller,
so `pull-requests: read` would stop every dev build from starting. The repository is public, and
a contents-only token reads its pull requests' files. Giving `devbuild.yml`'s `checks` job
`pull-requests: read` was the other way; I kept that file as it is.

## Consequences

- A wrong list skips a job that would have failed. Keep it short. If the app's name or version
  ever comes from `src/gw2om.sh` into a window, take `src/gw2om.sh` off it.
- If the read fails, the job writes a warning on the run and both jobs run. A backend-only pull
  request that still runs `renders` with that warning means the token lost its read.
- Homebrew's mingw-w64 can move without any pull request. Every pull request used to notice that.
  Now the next addon change or the next dev build does.
- A pull request that edits `checks.yml` runs both jobs, so its own run can't show a skip. Its
  dev build dry run shows `addon` skipped.
- `main`'s `checks.yml` is another file and keeps running both. I port this to it after a week
  on `arm64` without a wrong skip.

Source: `advisor-plans/2026-11-17-ci/005-app-renders-addon-only-when-reached.md` in my
workspace, for #236.
