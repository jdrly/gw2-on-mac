# The move renames the game into 0.2, and Rollback renames it back

Decided on 2026-11-19 at 08:30, mine. Status: accepted. `arm64` only. It supersedes the clone and
"only reads" parts of ADR 0019, and decision 8 of the update plan (GW2 on Mac workspace
`advisor-plans/2026-11-19-update-path/PLAN.md`, "Changed on 2026-11-19 at 08:30").

ADR 0019 had the move clone 0.1.x's Steam or game folder into the new bottle. A clone costs nothing
on the day of the move, but the first Guild Wars 2 patch on 0.2 gives the patched blocks new space
while 0.1.x keeps the old ones. If Steam writes a new `Gw2.dat`, that's about 70 GB more until
0.1.x's folder goes. On a 256 or 512 GB Mac that can fill the disk. My rule: the update never takes
double space, not even for a moment.

## Decision

- **The game moves (#291).** The move renames 0.1.x's Steam folder (on ArenaNet's route its game
  folder) into the new bottle with `mv` on the same volume. A rename is instant, needs no space and
  keeps the inode. If the folder is on another volume than this app's folder, or reached through a
  link, the move refuses before it writes anything. It never copies. The small things stay clones,
  so 0.1.x keeps its own: the profile's Steam files, the game's settings, the ReShade folder,
  0.1.x's settings file.
- **0.1.x's folders are written once.** ADR 0019's "only reads 0.1.x's folders" becomes "renames
  its Steam or game folder and writes nothing else". Before the rename the app copies the few addon
  files 0.1.x has in the game folder (`version.dll`, `ReShade.ini`, arcdps and ReShade at either
  name, the compiler, the chain path) into `0.1-addons`.
- **A failure renames it back.** `move-undo` names the rename before it happens, with the folder's
  inode. A failed or cancelled move puts 0.1.x's addon files back, renames the folder back, and only
  then removes the bottle. If the folder isn't where the rename left it, nothing is removed. A
  `move-undo` left by a run that was killed is undone under the next install lock: `status` takes
  it at the window's start, and so does every command that takes the lock, before it removes
  anything.
- **Rollback to 0.1.4 in Troubleshooting (decision 8 replaced).** No copy is kept for 0.1.x.
  Rollback refuses while 0.2's Wine runs, renames the folder back to where 0.1.x had it, puts back
  0.1.x's addon files, and shows a window with a button that opens 0.1.4's DMG in the browser
  (0.1.x releases are notarized) and says to quit this app and drag 0.1.4 over it. The version and
  the URL come from one line of `gw2om.sh`, `LAST_01`, so when 0.1.5 ships the row and the window
  name it and fetch its DMG. This app keeps its install without the game, and its main window
  offers *Move it in again*, the same rename the other way.
- **Start fresh after a move gives the game back first**, as Rollback does, then removes the moved
  install. Uninstall stays as it was: it removes the bottle with the game, and its confirmation says
  to choose Rollback first.
- **#282 is superseded.** With the game moved, 0.1.x's leftovers are its engine, its bottle without
  Steam or the game, and its small files. A row that removes them can come later. It isn't needed
  for space.

## Consequences

- The move's summary says the game was moved on this disk, and points to Rollback instead of
  saying 0.1.x stays as it was.
- The space check of the move is the one of an import: the engine's and the bottle's 3 GB. The game
  needs none.
- A 0.1.x install whose Steam or game folder sits on another volume can't move. Start fresh
  installs anew, and *Game files I already have* can still copy it, which is my choice to make for
  that disk, not the update's.
- After Rollback, Repair doesn't reinstall Steam into the bottle on Steam's route, so the place
  stays free for Move in.
- A move that 0.1.x's player rolls back and moves in again saves 0.1.x's addon files anew each time
  it moves in, so Rollback puts back what 0.1.x last had.

## Alternatives I rejected

- **Clones (ADR 0019).** Free on the day, but the first patch on either side splits the blocks.
- **A copy kept for 0.1.x on request.** Double space for as long as the player keeps it.
- **Moving the game back on Uninstall.** Uninstall says it removes the game, and has since 0.1.0.
  Its confirmation names Rollback instead.

## Evidence

- #291 and its pull request: the sandbox suite's section "Move GW2 on Mac 0.1's install", with the
  inode of 0.1.x's Steam or game folder before and after a finished move, a cancelled one, one that
  fails at each step and one killed after the rename; a refusal from another disk and through a
  link; Rollback, a second Rollback, Rollback killed after its rename, and Move in; and a check
  that `install.log` has no `cp` of either folder.
