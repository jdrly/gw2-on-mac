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
  folder) into the new bottle with a rename on the same volume. A rename is instant, needs no space
  and keeps the inode. If the folder is on another volume than this app's folder, or a link sits on
  the way to either, the move refuses before it writes anything. It never copies. The small things stay clones,
  so 0.1.x keeps its own: the profile's Steam files, the game's settings, the ReShade folder,
  0.1.x's settings file.
- **0.1.x's folders are written once.** ADR 0019's "only reads 0.1.x's folders" becomes "renames
  its Steam or game folder and writes nothing else". Before the rename the app copies the few addon
  files 0.1.x has in the game folder (`version.dll`, `ReShade.ini`, arcdps and ReShade at either
  name, the compiler, the chain path) into `0.1-addons`.
- **Nothing removes a folder that holds a game.** Every recursive removal in `gw2om.sh` goes through
  `safe_rm`, and a suite check finds any other. It leaves a folder with a file named `Gw2.dat` or
  `Gw2-64.exe` in it (on that volume), one with another volume mounted inside (`rm -x` doesn't
  cross into it), or one `find` can't look through, and the log says why. `--with-game` removes a
  game anyway, only for an install that never came from a move (no move origin, no `move-undo`,
  no record but Start fresh's one line), and only at Uninstall, in a failed install's own cleanup
  and for an import's own failed clone. A leftover bottle can be removed later; a lost game can't
  be had back. The decision is by content, not by the move's records, so a path that forgets to
  read them can't lose the game.
- **The game's place is the state.** A rename is atomic, so the folder is at 0.1.x's place or at
  0.2's. `move-undo`, written before the first change, names both places, the inode and what the
  move makes. The commit is the move's record, written after the rename and the addon steps;
  Rollback and Move in are done when `move-undo` goes. The exit handler and the recovery at the
  next start read that alike: a transaction that isn't done is undone (the folder found by its
  inode, renamed back), then what it made is removed under the rule above. The threat is a crash or
  a kill, not a power cut in the middle of a write.
- **No link on either path.** Both places and every folder from the home folder down to them must
  resolve to themselves, and both must be on one volume, before anything is written. The rename
  is `rename(2)` through macOS's `perl`, which fails on another volume and never moves a folder
  into one that is there, where `mv` would copy or nest.
- **One exclusion.** The install lock for the whole transaction, and the session's lock, which a
  Play needs before it starts Wine, from the rename's checks to the commit or the end of recovery,
  with Wine checked again under both. Recovery also waits while the killed run's rename helper or
  another run of the backend is alive.
- **Rollback to 0.1.4 in Troubleshooting (decision 8 replaced).** No copy is kept for 0.1.x.
  Rollback refuses while 0.2's Wine runs, when a `Gw2.dat` isn't in the folder that would go back
  (Steam may have moved the game to another library), or when an addon file there is a link, and
  checks that 0.1.x's place is free before it changes
  anything. It keeps this app's addon files for an undo, puts back 0.1.x's, renames the folder back
  to where 0.1.x had it, and shows a window with a button that opens 0.1.4's DMG in the browser
  (0.1.x releases are notarized) and says to quit this app and drag 0.1.4 over it. The version and
  the URL come from one line of `gw2om.sh`, `LAST_01`, so when 0.1.5 ships the row and the window
  name it and fetch its DMG. This app keeps its install without the game, and its main window
  offers *Move it in again*, the same rename the other way.
- **Start fresh after a move gives the game back first**, as Rollback does, then removes the moved
  install. If it can't, or the record that names the moved folder is missing, it removes nothing.
  Uninstall refuses while the moved game is in the bottle, and names Rollback.
- **#282 is superseded.** With the game moved, 0.1.x's leftovers are its engine, its bottle without
  Steam or the game, and its small files. A row that removes them can come later. It isn't needed
  for space.

## Consequences

- The move's summary says the game was moved on this disk, and points to Rollback instead of
  saying 0.1.x stays as it was.
- The space check of the move is the one of an import: the engine's and the bottle's 3 GB. The game
  needs none.
- A 0.1.x install whose Steam or game folder sits on another volume can't move. Start fresh
  installs anew.
- *Game files I already have* doesn't take 0.1.x's game (#293): it refuses anything in 0.1.x's
  folders, by its own path or resolved. It still clones or copies another app's game, since that
  is the player's choice: only after a yes to that folder at that size, which the window asks with
  the space it takes, and the backend refuses a yes to another path or size. A folder that is a
  link, or has one leading out, is refused.
- After Rollback, Repair doesn't reinstall Steam into the bottle on Steam's route, so the place
  stays free for Move in.
- A move that 0.1.x's player rolls back and moves in again saves 0.1.x's addon files anew each time
  it moves in, so Rollback puts back what 0.1.x last had.

## Alternatives I rejected

- **Clones (ADR 0019).** Free on the day, but the first patch on either side splits the blocks.
- **A copy kept for 0.1.x on request.** Double space for as long as the player keeps it.
- **Moving the game back on Uninstall.** Uninstall says it removes what this app made. It refuses
  while the moved game is in the bottle and names Rollback, which is one click and says what it
  does.
- **Proving ownership of every file a move made, with a journal state for each step.** Each review
  round found a new window. Looking for a game's files in every folder before it is removed covers
  every one of them with one check. A check by the move's records missed the paths that don't read
  them (round 3), so the check is by content.

## Evidence

- #291 and its pull request: the sandbox suite's section "Move GW2 on Mac 0.1's install", with the
  inode of 0.1.x's Steam or game folder before and after a finished move, a cancelled one, one that
  fails at each step and one killed after the rename; a refusal from another disk and through a
  link; Rollback, a second Rollback, Rollback killed after its rename, and Move in; and a check
  that `install.log` has no `cp` of either folder.
