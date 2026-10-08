#!/usr/bin/env bash
# Regenerates the Double Cross proving ground: the generator writes the district's OSM-shaped
# inputs under regions/proving-ground/, then the importer builds packs/proving-ground from
# them with the synthetic elevation (no network). Run it after any change to the generator or
# to tools/osm_import, then commit the result; CI runs the same check and fails on a diff.
# Usage: scripts/regen-proving-ground.sh [--check]
#   --check  regenerate into a temporary folder and diff against the committed files (exit 1 on a diff)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK=false
[ "${1:-}" = "--check" ] && CHECK=true
OUT="$ROOT/packs/proving-ground"
INPUTS="$ROOT/regions/proving-ground"
REGION="$ROOT/regions/proving-ground.json"
if $CHECK; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  INPUTS="$TMP/proving-ground"
  REGION="$TMP/proving-ground.json"
  OUT="$TMP/pack"
fi
( cd "$ROOT/tools" && uv run python -m proving_ground --out "$INPUTS" --region "$REGION" >/dev/null )
( cd "$ROOT/tools" && uv run python -m osm_import --region "$REGION" --pack-out "$OUT" --pack-version 0.1.0 )
if $CHECK; then
  status=0
  diff -r -q "$ROOT/regions/proving-ground" "$INPUTS" || status=1
  diff -q "$ROOT/regions/proving-ground.json" "$REGION" || status=1
  diff -r -q --exclude=chunks --exclude=build.json "$ROOT/packs/proving-ground" "$OUT" || status=1
  if [ $status -ne 0 ]; then
    echo "proving ground: the committed files differ from a fresh regeneration; run scripts/regen-proving-ground.sh and commit" >&2
    exit 1
  fi
  echo "proving ground: committed files match a fresh regeneration"
fi
