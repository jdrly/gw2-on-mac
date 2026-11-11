#!/bin/bash
# Prints every file of an app bundle with its sha256, and every symbolic link with its target,
# sorted by path. build.sh writes the list next to the app it built; scripts/release.sh --adhoc
# compares the app inside the finished DMG with it.
#
#   scripts/app-files.sh <app>
set -euo pipefail
[ -d "${1:-}" ] || { echo "usage: scripts/app-files.sh <app>" >&2; exit 2; }
cd "$1"
find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then echo "link $(readlink "$f")  $f"
  else echo "$(shasum -a 256 "$f" | cut -d' ' -f1)  $f"; fi
done
