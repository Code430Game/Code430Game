#!/usr/bin/env bash
# Exports one Ottawa district with the importer as it stands, swaps it into packs/ for the
# length of the checks, and reports the three numbers that judge a terrain change:
#   - wheel traps: EdgeDropReport spots (ground past a road's edge over 25 cm below it);
#   - junction pokes: test_junction_terrain (terrain through a junction surface);
#   - Metcalfe under the 417: test_terrain_collision (no invisible step; Centretown only).
# Then it puts the locked pack back (stamps cleared, so fetch-packs really fetches).
#
# Usage: scripts/terrain-trial.sh [centretown|glebe|hintonburg] [out dir]
# Needs: GODOT_BIN, the Location-OttawaOnCa repo beside this one (or LOCATION_REPO), and the
# OSM cache (CODE430_OSM_CACHE, e.g. /Volumes/downloads/OSMCache) so the export is offline.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
DISTRICT="${1:-centretown}"
OUT="${2:-$(mktemp -d)/$DISTRICT}"
LOCATION_REPO="${LOCATION_REPO:-$ROOT/../Code430Packs/Location-OttawaOnCa}"
FOLDER="ottawa-$DISTRICT"

restore() {
  rm -f "$ROOT/packs/.fetched/$FOLDER.sha256"
  "$ROOT/scripts/fetch-packs.sh" >/dev/null 2>&1 || echo "warning: fetch-packs failed; run it before CI" >&2
}
trap restore EXIT

echo "== exporting $DISTRICT to $OUT"
( cd "$ROOT/tools" && uv run --quiet python -m osm_import \
    --region "$LOCATION_REPO/regions/$DISTRICT.json" --pack-out "$OUT" \
    --pack-version 0.0.0 --build-stamp > "$OUT.log" 2>&1 ) || { echo "export failed: see $OUT.log" >&2; exit 1; }
rsync -a --delete "$OUT/" "$ROOT/packs/$FOLDER/"

echo "== wheel traps"
( cd "$ROOT/game" && "$GODOT" --headless --path . -s res://world/build/edge_drop_report.gd -- "code430.$FOLDER" 15 2>&1 \
    | grep -E "edge drop report| m  x" ) || true

if [ "$DISTRICT" = "centretown" ]; then
  echo "== junction pokes and Metcalfe"
  ( cd "$ROOT/game" && "$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c \
      -a res://tests/test_junction_terrain.gd -a res://tests/test_terrain_collision.gd 2>&1 \
      | sed 's/\x1b\[[0-9;]*m//g' | grep -aE "junction terrain:|FAILED|ground at|terrain stands|Overall Summary" | cut -c1-240 ) || true
fi
echo "== export kept at $OUT; packs/$FOLDER goes back to the locked release"
