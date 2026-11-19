# A dev build starts with every switch on

Decided 2026-11-12, narrowed 2026-11-15. Status: accepted.

My forks merge every new behaviour with its switch off. A dev build therefore started with most of
the night's work inactive, and turning it on meant collecting variable names from a dozen pull
requests. I debug the other way round. When the dispatcher advised a careful first start with every
row off, I asked for dev.11 to ship with an updater that sets everything on, because I debug from
the end back to the start. So a development build starts with every behaviour switch of my forks on,
from one file I can take lines out of.

## Consequences

- `dev-switches.conf` in the app's folder, read only with `CHANNEL=dev`. One switch a line, with a
  comment above it saying what it does and which piece reads it. A line I comment out or delete is a
  switch that is off.
- The updater adds new switches switched on when the build's table is newer than the file. It keeps
  what I commented out and never deletes a line I added.
- The rows that are switches go on once in a dev build. A row I turn off afterwards stays off.
- Only what the installed files have: a line whose variable the file's `switches:` record doesn't
  name is left out of the rule and reported once.
- `status` and the session report's header list the dev switches that were on.
- A release build ignores the file and keeps its defaults. The forks still merge new behaviour off.
- Not in the file: diagnostics, a switch whose "on" is a number only I can choose, and anything that
  caps the frame rate below 60. `DXMT_PRESENT_QUEUE=two` stayed out because it can latch 30 fps.
  Four more were taken out when the table was written, as costing frames in crowds or throttling a
  covered game: the DXMT thread, compile and render priorities and `DXMT_BG_POLICY=occlusion`.
- Narrowed on 2026-11-15. A correctness fix that adds work on the game's hot path, for a problem
  nobody has seen in play, stays out of dev builds and isn't dispatched in the first place. The case
  was `FEX_CONDBACKEDGESUSPEND`, two instructions more per taken conditional back-edge. I asked why
  we were adding something that costs frames. The same evening I called the game's exit crashes
  marginal, twice in more than 100 runs, and they were not filed. A symptom seen in play comes
  first, then the fix.
- When a fork deletes a switch, its row leaves the table first (#212). A row whose switch became
  the default in a fork leaves too. The rows of the three Metal 4 switches that jdrly/dxmt #301
  turned on by default left in #243 (PR #244). A line I had commented out to turn one of them off
  now sets it to `0`. On 2026-11-17 `DXMT_MTL4_SHOWN_WAIT=write` left the same way (#258), after
  jdrly/dxmt #332 made `write` the default. Its off value is `next`, not `0`, so a line I had
  commented out becomes `DXMT_MTL4_SHOWN_WAIT=next`. On 2026-11-19 `FEX_DISPATCHERL1LOOKUP=1` and
  `FEX_ENTRYHEADERLOOKUP=1` left the same way (#267), after my FEX fork made both its defaults
  (#266). Their off value is `0`.
- `FEX_ENTRYHEADERLOOKUP` is off while the rule can start my Wine fork's sampler (#170). Until #267
  the app left the table's line out. Since my FEX has it on by default, the game's rule says
  `FEX_ENTRYHEADERLOOKUP=0` while my FEX, whose `VERSION` names the switch, is in the engine, in a
  release too.

## Alternatives I rejected

- **A first session with every row off, then one switch per session.** The dispatcher's habit until
  then. I debug from the end to the start.
- **Holding work out of a dev build for caution.** The dispatcher's note turns that into a rule for
  itself: give me the fallback build and the order of suspects instead.

## Evidence

- #129 (PR #137, `2c24b37`), #170, #178, #202, #212, #243 (PR #244, `5d957c3`), #258, #266, #267.
- The dispatcher's note `dev-builds-everything-on` (what I said on 2026-11-12 and 2026-11-15).
- GW2 on Mac workspace `plans/night/2026-11-11-plan.md`, 2026-11-12 22:10 and 22:40 (the four taken
  out), 2026-11-15 23:50.
- The dispatch project file `gw2-on-mac.md`, "Dev builds".
