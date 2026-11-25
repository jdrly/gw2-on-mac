# FEX's counters only with my FEX that names the slot fix

Decided 2026-11-26. Status: accepted. `arm64` only.

Debug logging put `FEX_PROFILESTATS=1` into the game's rule whenever my `ntdll.so` was in place,
whichever FEX was. On 2026-11-20 my M5 Max ran 0.2.1 with my `ntdll.so` and the engine's own FEX
(`fex=engine`, 0.2.1's default and its only choice), and the game crashed at start twice in a row
(#344). The engine's FEX keeps the counters in a shared memory object with slots for 35 threads. On
macOS the object can't grow, and the 37th thread faults in `StatAllocBase::AllocateSlot`. My FEX's
builds since #117 and #139 have room for about 29,000 threads, and a thread past them gets no slot
instead of a fault.

Now `heat_entries` puts `FEX_PROFILESTATS=1` in only when three things hold: Debug logging is on,
my `ntdll.so` is in place, and my FEX is in place and names `profilestats-slots` on its `VERSION`'s
`fixes:` line (jdrly/FEX ADR 0011). `WINE_HEAT_COUNT`, `WINE_HEAT_LOG` and `FEX_SILENTLOG=0` stay as
they were.

## Consequences

- A release that, like 0.2.1, pins no FEX of mine in `prebuilt.lock` writes my `ntdll.so`'s own
  counters with Debug logging and no FEX counters. The session report then has no "FEX's counters"
  lines. A release that pins my FEX gets them once that FEX names the fix.
- A dev build with my FEX gets FEX's counters back once its FEX was built after jdrly/FEX's `fixes:`
  line. My builds since #117 and #139 have the fix but not the line, and run without them.
- A fix of mine that a rule depends on goes onto that line. The app checks the line with
  `fex_fixed <id>`.

## Alternatives I rejected

- **My FEX in place, without the line.** A dev build can name any commit on jdrly/FEX's
  `gw2-on-mac`, including ones from before #117, and the app can't tell their age from the files.
- **Dropping FEX's counters from Debug logging.** My FEX's counters are what the session report
  reads for compile time and lookup misses. Only the engine's FEX crashes with them.

## Evidence

- #344: the crash address in the engine's `libarm64ecfex.dll`, the compatdb lines with
  `FEX_PROFILESTATS=1` and `fex=engine`, and a native reproduction on macOS 26.7.3.
- jdrly/FEX ADR 0011 and jdrly/FEX#26.
