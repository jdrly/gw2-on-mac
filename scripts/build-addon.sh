#!/bin/zsh
# Builds the interface-scale addon from addon/ui-scale with Homebrew mingw-w64
# (brew install mingw-w64) into work/ui-scale/build, with the same flags as the development
# workspace's build, and runs the addon's native test (addon/ui-scale/test/test.c). Installs
# nothing. scripts/stage-components.sh stages the workspace's build of the same sources.
#
#   scripts/build-addon.sh    version.dll          the addon (a version.dll proxy)
#                             gw2-ui-scale.ini     its settings, as shipped
#                             ui-scale-probe.exe   reads GW2's interface scale state while the
#                                                  game runs (read-only; a development tool)
#
# Env: OUT (default work/ui-scale/build), GW2_EXE (the game's Gw2-64.exe, only read: the test
#      also checks the cinema detour's patterns against its code; without it that part is skipped)
emulate -L zsh
setopt err_exit pipe_fail no_unset

ROOT="${0:A:h:h}"
SRC="$ROOT/addon/ui-scale"
OUT="${OUT:-$ROOT/work/ui-scale/build}"
CC=x86_64-w64-mingw32-gcc
die() { print -r -- "build-addon: $*" >&2; exit 1 }
whence -p $CC >/dev/null || die "$CC not found (brew install mingw-w64)"
mkdir -p "$OUT"

rm -f "$OUT/ui-scale-probe.exe" "$OUT/version.dll"
$CC -O2 -Wall -Wextra -static -o "$OUT/ui-scale-probe.exe" "$SRC/probe.c"
$CC -O2 -Wall -Wextra -shared -static-libgcc -o "$OUT/version.dll" \
  "$SRC/proxy.c" "$SRC/ui_scale.c" "$SRC/version.def"
x86_64-w64-mingw32-strip "$OUT/version.dll"
grep -aq 'gw2-on-mac ui-scale' "$OUT/version.dll" || die "$OUT/version.dll has no addon marker"
# the checks and writes against a fake FontContext, natively
cc -O1 -Wall -Wno-unused-function -I "$SRC/test/win" -o "$OUT/test" "$SRC/test/test.c"
GW2_EXE="${GW2_EXE:-}" "$OUT/test" >"$OUT/test.log" || { cat "$OUT/test.log"; die "addon test failed" }
print -r -- "addon test: $(tail -1 "$OUT/test.log")"
cp "$SRC/gw2-ui-scale.ini" "$OUT/"
print -r -- "built $OUT/version.dll and $OUT/ui-scale-probe.exe"
