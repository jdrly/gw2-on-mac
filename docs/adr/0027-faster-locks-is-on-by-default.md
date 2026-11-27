# Faster locks is on by default

Decided 2026-11-27. Status: accepted. `arm64` only.

*Faster locks* (`fastlocks`) has my `ntdll.so` spin for a few microseconds before the game thread
sleeps on a busy lock or an event (`WINE_HEAT_SPIN=lock=20:game,event=30:game`). Since #45 it was
off in a release. #105 named the rule that would turn it on: a session of mine where the lock
spin's hits beat its misses and no frame is lost.

Every session since dev.13 meets that rule. The topic analysis of 2026-11-26 checked it clause by
clause against dev.23-long, which ran 48 minutes on my M5 Max with Debug logging:

| The game thread | Without the spin (dev.8) | With it (dev.23-long) |
|---|---|---|
| Lock sleeps a second | 3,411 | 34.9 |
| Lock spin hits and misses, the session | none | 3,543,852 and 77,457 |
| Time spinning a second | 0 | 5.3 ms |

The job workers stay out of it, as `:game` means. Their event spins are 0, and their lock spins have
no hit and one miss on six of the seven in those 48 minutes. The frames are grade B: dev.23-long held
a median of 60 in every band, but the evening it's compared with had the spin too, and no session
since dev.10 ran without it on the same build. dev.10 ran the
row's own value on Mach9 0.3.1, with 891,594 hits against 29,334 misses and a median of 60 fps.
#45 asked for under 50 ms of spinning a second, and the sessions show 4 to 13. The one profile of
this engine without the spin, 0.2.1's trace, has the lock sleep call at 25 ms of the game thread's
CPU a second. The spin trades that for about 5 ms. That trace and dev.23-long ran at different
places, so that comparison isn't an A/B. The counts inside each session are.

The event half is about even, 1.4 hits to a miss in dev.23-long, with more misses than hits in four
sessions. #105's rule names the lock counters, and I keep the event spin in the row's value as it
ran in every one of those sessions.

The worker spin of 2026-11-27 changes none of this: the job workers stay out of the spin (ADR 0026,
#370).
So *Faster locks* is on by default in a release (#372).

## Consequences

- `setting_default` gives `fastlocks` on, and `SETTINGS_RESETS` gets version 3 for it. 0.2.0 and
  0.2.1 wrote `fastlocks=off` into every `settings.conf`, so a file older than version 3 reads on,
  and its next write keeps on. An off I set afterwards stays.
- An off a player chose on 0.2.0 or 0.2.1 reads on once too. The file can't tell a chosen off from
  the default those versions wrote. The row is in Settings to turn it off again.
- A move from 0.1.x gives *Faster locks* this version's default, on, as before. 0.1.x's own default
  was on, so the move's summary names the row only for a player who had it off there.
- The row still needs my `ntdll.so`. With the engine's own it stays greyed and the spin stays out of
  the rule.
- A dev build already had the row on (`DEV_ROWS`), and its `dev-switches.conf` line has the row's
  value. A dev build never resets a key of `DEV_ROWS`. Its file is either older than the row, which
  turns it on, or holds the row's on or an off I set afterwards.
- My Wine fork's `docs/gw2/SERIES.md` still says the `spins` row waits for #105's session and is
  "never a default", and its ADR 0005 still says *Fast locks* is off on 0.2. That's a follow-up in
  the fork. This decision changes no Wine code.

## Alternatives I rejected

- **Leaving 0.2.1's files at off and only changing the default for new installs.** Install and
  Repair wrote off into every file, so almost no player would get the spin.

## Evidence

- `advisor-plans/2026-11-26-topic-analysis/ANALYSIS-wine-mesa.md` in the GW2 on Mac workspace,
  section `spins`, and `DECISIONS.md` there, section 2.
- #105 (the rule), #45 (the row, off), #370 and ADR 0026 (the workers stay out of the spin).
