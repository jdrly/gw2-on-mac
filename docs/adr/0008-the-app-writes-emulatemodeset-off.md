# The app writes `EmulateModeset` off, as 0.1.x's setup has it

Decided 2026-11-12, reason corrected the same day. Status: accepted.

The 0.2 app wrote the registry value `EmulateModeset`=`Y` under `HKCU\Software\Wine\X11 Driver`,
because Mach9's own launcher writes it. 0.1.x never did. With `Y`, win32u fakes the game's mode set
and swallows its gamma ramp, so the game's Gamma slider does nothing. The app now writes `N`.

I first recorded this as the fix for the cursor stutter on 0.2, and that was wrong. The session I
took as its confirmation also had `DXMT_METAL4=0` in `compatdb.local`. On dev.10 with `N` in both
registry places, Metal 4 stuttered with the cursor and Metal 3 didn't. The stutter was in my DXMT
fork's Metal 4 present (jdrly/dxmt #223). The value stays for what it does: 0.1.x's behaviour, and a
Gamma slider that works.

## Consequences

- `apply_registry` writes `"EmulateModeset"="N"` under `$REG_X11`. A bottle that has `Y` from an
  earlier 0.2 build gets `N` at its next start, not while a session runs, like `RetinaMode`.
- A per-program value I set by hand under `AppDefaults\Gw2-64.exe\X11 Driver` stays as it is.
- Full-Screen Gamma works: 3.50 washes out the picture and the frame line stays flat.
- The issue's text still gives the stutter as the cause. Its last comment corrects it.
- Which half of `EmulateModeset` matters to the window server, the gamma ramp or the faked mode set,
  was never split. Nothing needs it now.

## Alternatives I rejected

- **Keeping Mach9's launcher value.** It differs from the setup 0.1.x runs right on, and it disables
  the Gamma slider.
- **Reverting to `Y` once it was clear the stutter had another cause.** `N` is what 0.1.x has, and I
  compare 0.2 with 0.1.x.

## Evidence

- #90 and its comments of 2026-11-12 (the UAT, then the correction), PR #91 (`a432ea1`).
- GW2 on Mac workspace: `AGENTS.md` ("I got this wrong first");
  `docs/research/arm64-cursor-present-2026-11-12.md`,
  `docs/research/arm64-direct-flip-macdrv-2026-11-12.md`; `plans/night/2026-11-11-plan.md`,
  2026-11-12 18:15, 23:00 and 23:15.
