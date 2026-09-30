#!/usr/bin/env bash
# Exports the Linux build and puts the first-party packs next to it, ready to copy to a Steam Deck.
# Usage: scripts/package-linux.sh [--with-chunks]
#   --with-chunks  also copy pre-built GLB chunks (about 70 MB for Ottawa; otherwise the game generates them at load).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
OUT="$ROOT/build/linux"
WITH_CHUNKS=false
[ "${1:-}" = "--with-chunks" ] && WITH_CHUNKS=true

rm -rf "$OUT"
mkdir -p "$OUT/packs"
( cd "$ROOT/game" && "$GODOT" --headless --path . --export-release "Linux" "$OUT/code430.x86_64" 2>&1 | tail -1 )
for pack in "$ROOT"/packs/*/; do
  name="$(basename "$pack")"
  [ "$name" = "example" ] && continue
  mkdir -p "$OUT/packs/$name"
  for item in "$pack"*; do
    base="$(basename "$item")"
    if [ "$base" = "chunks" ] && ! $WITH_CHUNKS; then continue; fi
    cp -R "$item" "$OUT/packs/$name/"
  done
done
chmod +x "$OUT/code430.x86_64"
echo "packaged to $OUT:"
du -sh "$OUT" "$OUT"/packs/* 2>/dev/null
