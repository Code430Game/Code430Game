#!/usr/bin/env bash
# Exports a build and puts the first-party packs next to it.
# Usage: scripts/package.sh linux|windows [--with-chunks] [--zip]
#   linux          build/linux/code430.x86_64, ready to copy to a Steam Deck (scripts/deploy-deck.sh)
#   windows        build/windows/code430.exe (unsigned: Windows SmartScreen asks "Run anyway")
#   --with-chunks  also copy pre-built GLB chunks (about 70 MB for Ottawa; otherwise the game generates them at load)
#   --zip          also zip the folder to build/code430-<platform>-<commit>.zip, to hand to people
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
PLATFORM="${1:-}"
shift || true
case "$PLATFORM" in
  linux) PRESET="Linux"; BIN="code430.x86_64" ;;
  windows) PRESET="Windows"; BIN="code430.exe" ;;
  *) echo "usage: scripts/package.sh linux|windows [--with-chunks] [--zip]" >&2; exit 2 ;;
esac
WITH_CHUNKS=false
ZIP=false
for arg in "$@"; do
  case "$arg" in
    --with-chunks) WITH_CHUNKS=true ;;
    --zip) ZIP=true ;;
    *) echo "unknown option $arg" >&2; exit 2 ;;
  esac
done
OUT="$ROOT/build/$PLATFORM"

"$ROOT/scripts/fetch-packs.sh"  # the packs pinned in packs.lock.json
rm -rf "$OUT"
mkdir -p "$OUT/packs"
"$ROOT/scripts/stamp-build.sh"
# The stamp is for the export only; runs from source must keep reporting themselves as dev builds.
trap 'rm -f "$ROOT/game/build_info.json"' EXIT
( cd "$ROOT/game" && "$GODOT" --headless --path . --export-release "$PRESET" "$OUT/$BIN" 2>&1 | tail -1 )
[ -f "$OUT/$BIN" ] || { echo "export failed: no $OUT/$BIN" >&2; exit 1; }
for pack in "$ROOT"/packs/*/; do
  name="$(basename "$pack")"
  [ "$name" = "example" ] && continue
  mkdir -p "$OUT/packs/$name"
  for item in "$pack"*; do
    base="$(basename "$item")"
    [ "$base" = ".DS_Store" ] && continue
    if [ "$base" = "chunks" ] && ! $WITH_CHUNKS; then continue; fi
    cp -R "$item" "$OUT/packs/$name/"
  done
done
find "$OUT" -name .DS_Store -delete
[ "$PLATFORM" = linux ] && chmod +x "$OUT/$BIN"
echo "packaged to $OUT:"
du -sh "$OUT" "$OUT"/packs/* 2>/dev/null
if $ZIP; then
  commit="$(git -C "$ROOT" rev-parse --short=8 HEAD)"
  zip_path="$ROOT/build/code430-$PLATFORM-$commit.zip"
  rm -f "$zip_path"
  ( cd "$ROOT/build" && mv "$PLATFORM" code430 && zip -qr "$zip_path" code430 && mv code430 "$PLATFORM" )
  echo "zipped to $zip_path ($(du -h "$zip_path" | cut -f1))"
fi
