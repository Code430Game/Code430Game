#!/usr/bin/env bash
# Rebuilds game/assets/people/*.glb and people.json from the kit sources with tools/people_kit
# and renders build/people_kit/lineup-men.png and lineup-women.png. Needs Blender
# (BLENDER=/path/to/blender, else the macOS app or PATH).
#   scripts/build-people.sh          # both packs
#   scripts/build-people.sh women    # just these packs
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLENDER="${BLENDER:-}"
if [[ -z "$BLENDER" ]]; then
  if [[ -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
    BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
  else
    BLENDER="$(command -v blender || true)"
  fi
fi
[[ -x "$BLENDER" ]] || { echo "Blender not found: set BLENDER=/path/to/blender" >&2; exit 1; }
"$BLENDER" -b --factory-startup -P "$ROOT/tools/people_kit/build_people.py" -- "$ROOT" "$@" 2>&1 \
  | grep -E "people_kit|Error|Traceback|^  File" || true
mkdir -p "$ROOT/build/people_kit"
for pack in men women; do
  "$BLENDER" -b --factory-startup -P "$ROOT/tools/people_kit/render_lineup.py" -- \
    "$ROOT/build/people_kit/lineup-$pack.png" "$ROOT/game/assets/people/$pack.glb" >/dev/null 2>&1
done
echo "people_kit: lineups in build/people_kit/lineup-men.png and lineup-women.png"
