# An engine of another release is replaced by Repair

Decided 2026-11-17. Status: accepted. `arm64` only.

The engine pin moves with an app update: 0.2's first dev build pinned Mach9 0.3.1, and #261 moves
it to 0.4.0. It is the first move on a Mac that already has the app installed. The engine there is
then one of another release. Its `.gw2om-source` names the old tarball, and its wineserver speaks
another protocol (972 against 0.4.0's 973), so neither the app's files of mine nor the game may run
on it.

Before this decision the app took that engine for none at all: `status` said `installed=no`, the
window showed the install chooser over a bottle with the game in it, Play said "not installed",
and Repair could not be reached from the window.

Now an engine of another release still counts as installed:

- `status` prints `installed=yes` and `engine_installed=old`.
- The *Ready* panel's chip and the *This Mac* panel's Engine cell say "Repair to update".
- Play refuses and names both engines and Repair. `set` keeps my files out of the old engine and
  says why (the guard of #261).
- Repair downloads the pinned engine and replaces the old one, which `install_engine` already did
  for any engine whose `.gw2om-source` isn't the pin. It refuses while Steam, the game or the
  bottle's Wine runs, as it always has. A failed download or unpack leaves the old engine in place,
  and the error says so and names Repair.
- My DXMT tree, `ntdll.so`, Mac driver and FEX go into the new engine as at every Repair.

## Consequences

- An engine move costs me one click on Repair and the engine's download after the app update.
- The bottle stays. Wine updates the prefix at its first start on the new engine.
- The next engine move needs nothing new in the app: the pin and the files' hashes move, and the
  `Mach9 0.3.1` name in `engine_label` gets the release before it.
- This is the first step. Automatic replacement follows in its own issue: the app replaces an old
  engine by itself through the same Repair, waits while Steam or the game runs, and Play waits for
  it. An engine move always comes with an app update, and a manual step only delays me. It needs
  about 100 to 150 lines of Swift that no CI check runs, so it didn't go into tonight's dev build.

## Alternatives I rejected

- **Play downloading the engine.** Play would wait on a 130 MB download with no progress shown.

## Evidence

- #261 and its pull request: the sandbox checks for an old engine (status, Play's refusal, Repair
  refused while the old engine's Wine runs, a failed download that keeps the old engine, and the
  replacement).
- `git log -G'^ENGINE_(SHA256|URL|NAME)=' -- src/gw2om.sh` on both branches: no earlier move of an
  installed engine.
