# Change: The proving ground, a small test district

**Status: proposed 2026-10-07 (human: "a smaller area we can use for testing ... like a race track + other things ... a police, hospital, etc ... some light story ... a baddie that wants to attack us on sight, a gang").**

## Why
Every change is tested on the whole of Centretown: a pack re-export takes minutes, a Deck
run means driving to find the one junction or pad a change touches, and a feature that
needs a hospital, a helipad and a bus lane in one place has nowhere to go. The Ottawa pack
also comes from live OpenStreetMap, so it drifts under the tests. A small district with one
of everything, generated from code so it is byte-identical every time, gives a change a
place to be proved in minutes, a loop to drive laps on, and somewhere to put the first story
(`add-hostile-gang`, `add-story-pack`).

## What Changes
- **A generator, not a download.** `tools/proving_ground/` writes an OpenStreetMap-shaped
  dataset in local metres (the `tests/osm_helpers.py` pattern: ways, nodes, tags), saved as
  the same JSON the importer reads with `--osm-json`, plus one file per extra layer
  (buildings, water, parking, services, vegetation). The normal pipeline then builds the
  pack with a synthetic elevation source: every stage runs (roads, clustering, forks, gores,
  shoulders, elevation, crossings, bridges, underpasses, barriers, water, buildings,
  parking, garages, services, bus lanes, vegetation) and the output is deterministic. The
  importer gains the file inputs it is missing (`--services-json`, `--vegetation-json`).
- **The layout** (the human's sketch, 2026-10-08: a figure eight; "the loop would be
  highway, in the city it could come down to ground level, maybe do a little roundabout";
  "the middle where they meet to be straights on having a bridge"; exits in the lower right
  "as it goes down, and then as it comes back up which gives access to residential areas";
  "the top is city, the top left is the main city"; edge streets "turn back into the grid").
  A fictional town, working name **Double Cross** (track and gang share the name; the town's
  own name is still open), about 2.4 km by 1.6 km with a river across the middle and a
  greenbelt along the top and left edges:
  - the **loop** is a figure eight of roughly 2.7 km made of two straights at right angles:
    the **highway** runs west to east along the river's north bank at grade, and a
    **vertical** road crosses the highway and the river together on one bridge at the map
    centre. North of the crossing the loop runs at street level through the main city as a
    two-lane `secondary` with a small roundabout on its west side, and returns east along
    the highway line to the crossing. South of it the highway continues east along the
    river, crosses it at the far right on a second bridge, loops round the lower right as
    elevated `motorway` (no junctions, the flat-out half of the lap) and comes back north up
    the vertical straight over the centre bridge;
  - the **crossing**: the vertical road is `bridge=yes layer=1` over the highway (at grade)
    and the river in one span, with a footbridge beside it, so one structure exercises
    piers, abutments, lane layers and the river in a single place;
  - **four ways on and off**, one per quarter of the map (human: "good access to escape the
    police"): the roundabout top left; a new exit and entry pair off the river highway into
    the city grid top right; the far-right descent exit into the bottom right; and the exit
    on the vertical ascent aimed west into the bottom left. Each exit is an off and on pair
    with gores, so the lap can be rejoined from every quarter; an underpass where a path
    crosses under a ramp;
  - the **main city** grid, top left, around and through the small lobe: signals where the
    avenues cross the loop, stops elsewhere, a one-way pair, a bus loop with a reserved lane
    and stops, sidewalks, crossings, shopfronts, a multi-storey garage with an underground
    entrance, a surface lot, kerb parking; the police station with its helipad and the
    hospital with its ambulance bay on their own blocks;
  - the **city** grid, top right, between the river and the greenbelt: the fire station, an
    office block row, the rail stub with a station (tagged for `add-rail`, inert until then);
  - the **residential** grid across the whole south, under the big lobe: houses with
    driveways, the gang's turf on a block the human picks, a park with trees, a tree row,
    grass and paths;
  - every **edge street** curls back into the grid instead of dead-ending; one deliberate
    dead end at the map edge keeps the edge closure testable;
  - the **spawn** on the vertical straight just north of the centre bridge, facing the
    start line.
  Street and place names are generic and invented; no real people, brands or parodies.
- **A committed pack.** The generated pack `packs/proving-ground` (id
  `code430.proving-ground`, region `regions/proving-ground.json` with `"dem": "synthetic"`
  and `"osm_json"` pointing at the generator's output) is committed, small (under 5 MB
  without chunks; chunk GLBs built at first run as for Ottawa). CI regenerates it and fails
  on a diff, so the generator and the importer stay in step; `scripts/regen-proving-ground.sh`
  rebuilds it after an importer change (the golden fixture rule, applied to a pack).
- **Picking the pack.** `--pack=<id>` on the testbed and a `map_pack` entry in settings
  replace the `PACK_ID` constant; the Ottawa pack stays the default. `scripts/deck-bench.sh`
  takes `--pack` and a `--route loop` preset that spawns on the start line.
- **Lap timer.** Crossing the start line on the loop starts a lap; crossing it again ends
  one. The HUD shows the current lap and the best lap of the session while the player is on
  the loop, and hides them elsewhere. A small gameplay hook, not a race mode.
- **Not in this change:** opponents or a race mode, checkpoints, a persistent best lap, a
  second test district, custom buildings beyond the generator's primitives, any change to the
  Ottawa pack.

## Co-op authority
The pack is data; the host's pack set is checked on join as today. The lap timer is local
to each player (their own laps).

## Tone
Billboards, shopfronts and radio already read the mode. Nothing new here is tone content;
`add-hostile-gang` adds the first tone-variant content to this district.

## Impact
- Affected specs: `proving-ground` (new), `road-network` (ADDED: layer inputs from files).
- Affected code:
  - `tools/proving_ground/` (new: `layout.py` for the geometry, `emit.py` for the OSM-shaped
    JSON files, `__main__.py`), `tools/tests/test_proving_ground.py`;
  - `tools/osm_import/__main__.py` (`--services-json`, `--vegetation-json`), `osm_data.py`
    (nothing new if the fixture format already round-trips);
  - `regions/proving-ground.json`, `packs/proving-ground/` (generated, committed),
    `scripts/regen-proving-ground.sh`, `.github/workflows/ci.yml` (regenerate and diff);
  - `game/scenes/play_testbed.gd` (`--pack`, lap timer HUD line), `game/core/settings/`
    (`map_pack`), `scripts/deck-bench.sh` (`--pack`, `--route loop`);
  - `game/world/lap_timer.gd` (new) and a `lap.v0.json` start line in the pack
    (`docs/pack-format/lap.schema.v0.json`), tests.
- Performance: the district is a tenth of Ottawa; the Deck benchmark on the loop becomes the
  quick check for every later change, with Ottawa as the full run.
