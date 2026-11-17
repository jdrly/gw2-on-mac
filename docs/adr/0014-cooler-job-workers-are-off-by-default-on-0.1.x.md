# Cooler job workers are off by default on 0.1.x

Decided 2026-11-17. Status: accepted. 0.1.x on `main`, from 0.1.5.

*Cooler job workers* (`coolworkers`) sets `WINE_HEAT_QOS=1=utility:<n>`, and the heat `ntdll.so`
puts the first n of the game's ABOVE_NORMAL job workers at utility QoS, on the efficiency cores.
It existed to save power: moving all of them saves 4 to 5 W. The app shipped 3 as the default
since 0.1.0. At a quiet spot the full move held 60. At the busy Lion's Arch spot it cost 3 to 6
fps, because GW2's group wait runs every job no worker has claimed yet on the game thread itself,
and slower workers claim fewer. My rule is that nothing takes the game below 60 for heat or
power, so the setting is off in my own play: my 0.1.x install has had it off since 2026-11-04,
an hour after I tried 4. No session of mine has measured the 3 that other players got. On
2026-11-17 I left this call to my dispatcher, since it follows from that rule, and it turned the
default off.

## Consequences

- A new install starts the game without `WINE_HEAT_QOS`, and Settings › Performance shows Off.
  The row, its values 1 to 15 and the switch in the heat `ntdll.so` stay. A player who wants the
  watts picks a number.
- Install and repair write every key into `settings.conf`, so every install of 0.1.4 or earlier
  has `coolworkers=3` in it, picked or not. From 0.1.5 the backend reads a 3 as off unless
  `install.log` has the line `---- set coolworkers=3`, which it writes when the player picks 3 in
  Settings. The next write of `settings.conf`, a change in Settings or a repair, puts `off` in the
  file. Any other value, off or 1, 2 and 4 to 15, stays as it is.
- A player who picked 3 and since deleted `~/Library/Logs/GW2 on Mac` gets off and has to pick 3
  again.
- The line counts a pick from any earlier install too. Uninstall keeps the logs, so a player who
  picked 3 once, then uninstalled and installed 0.1.4 or earlier again, keeps 3.
- Players who kept the default lose what moving three workers saved. Nobody measured that. The
  full move saves 4 to 5 W.
- 0.2 has no such setting at all (ADR 0006, on the `arm64` branch).

## Alternatives I rejected

- **Keeping 3.** It is a default I don't play with, never measured, of a switch that costs frames
  at the busy spot when it moves them all.
- **Turning every 3 off, picked or not.** Simpler, with no read of `install.log`, but it undoes a
  player's own choice when the log can tell.
- **Off for new installs only.** Every current player would keep a default I turned off.
- **Dropping the row, as 0.2 did.** That takes the choice from players who want the watts. The
  decision was about the default.

## Evidence

- GW2 on Mac workspace `AGENTS.md`, the heat `ntdll.so`'s defaults, the `HEAT_QOS` paragraph: 4 to
  5 W saved, 60 held at a quiet spot, 3 to 6 fps lost at the busy spot, and why.
- GW2 on Mac workspace `advisor-plans/2026-11-17-adr-backfill/README.md`, item 29 (my install's
  `install.log` and `settings.conf` in the 0.1.3 session's logs of 2026-11-16, and the 0.1.1 log
  of 2026-11-08) and "Settled on 2026-11-17, 15:10".
- Workspace ADR `0001-no-frame-cap-below-60`, stated in this repository's ADR 0011.
- #248. On `arm64`: ADR 0006, #92 and #46.
