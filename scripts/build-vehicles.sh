#!/usr/bin/env bash
# Rebuilds game/assets/vehicles/*.glb from the kit sources with tools/vehicle_kit, copies the
# measured dims into the vehicle catalogue and renders build/vehicle_kit/lineup.png (and
# lineup-rear.png). Needs Blender (BLENDER=/path/to/blender, else the macOS app or PATH).
#   scripts/build-vehicles.sh            # every recipe
#   scripts/build-vehicles.sh ambulance  # just these ids
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
run() { "$BLENDER" -b --factory-startup -P "$@" 2>&1 | grep -E "vehicle_kit|Error|Traceback|^  File" || true; }
run "$ROOT/tools/vehicle_kit/build_vehicles.py" -- "$ROOT" "$@"
python3 "$ROOT/tools/vehicle_kit/apply_dims.py" "$ROOT"
ids=$(python3 -c "import json,sys; print(' '.join(r['id'] for r in json.load(open(sys.argv[1]))['vehicles']))" "$ROOT/tools/vehicle_kit/recipes.json")
glbs=(); for id in $ids; do glbs+=("$ROOT/game/assets/vehicles/$id.glb"); done
"$BLENDER" -b --factory-startup -P "$ROOT/tools/vehicle_kit/render_lineup.py" -- "$ROOT/build/vehicle_kit/lineup.png" "${glbs[@]}" >/dev/null 2>&1
"$BLENDER" -b --factory-startup -P "$ROOT/tools/vehicle_kit/render_lineup.py" -- "$ROOT/build/vehicle_kit/lineup-rear.png" --rear "${glbs[@]}" >/dev/null 2>&1
echo "vehicle_kit: lineup in build/vehicle_kit/lineup.png and lineup-rear.png"
