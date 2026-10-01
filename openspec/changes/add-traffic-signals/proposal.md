# Change: Traffic signals and stop signs

**Status: proposed 2026-09-30 (next item after the Deck photos showed junction gridlock).**

## Why
Every junction is first-come-first-served, so a busy crossing turns into a scrum and a player
sitting in one freezes it. OSM tags the signalised and stop-controlled junctions, so the
city's real control layout is available for free. Signals also give the streets rhythm:
platoons of cars, gaps to cross in, lights at night later.

## What Changes
- **Importer:** the Overpass query fetches node tags; each graph node exports a `control`
  (`signals`, `stop`, `give_way`, `none`) that survives junction clustering.
- **Signal controller:** every signalised junction with three or more arms runs a two-phase
  cycle: arms are grouped by axis, phases alternate green, amber, all-red, with per-junction
  offsets so the city does not blink in unison. Tunables in `traffic_config.json`.
- **Traffic:** an agent approaching a red or amber light holds at the stop line (the junction
  trim) and goes on green; at a stop sign it comes to a full stop before taking its turn under
  the existing first-come priority. Give-way junctions keep the current priority rule.
- **Signal heads:** one MultiMesh of poles and one of heads at each approach's right-hand
  corner; the head's instance colour is the current light.
- **Not in this change:** pedestrian walk phases, turn arrows, sensors or adaptive timing,
  night emission, police for red-light running.

## Impact
- Affected specs: `traffic` (new requirements).
- Affected code: `tools/osm_import/fetch.py`, `graph.py`, `export.py`, schema;
  `game/world/traffic/signal_controller.gd` (new), `traffic_manager.gd`, `lane_graph.gd`,
  `road_graph.gd`, testbed, tests. Ottawa pack refetched (node tags).
- Performance: one cycle timer per signalised junction (hundreds), negligible; two MultiMeshes.
