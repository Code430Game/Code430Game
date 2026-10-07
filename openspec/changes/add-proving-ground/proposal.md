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
- **The layout** (human: "when I say race track, that's like the main road, but I am
  thinking of having other streets come off of it, so like a larger track with a city grid
  inside"). A fictional town, working name Harbourline, about 1.6 km by 1.2 km: a ring road
  is the track, and the town grid sits inside it with side streets branching off the ring
  at real junctions, so the ring is both the fast lap and the way into town.
  - the **loop**: a two-lane ring road of roughly 2.5 km with two long sweepers, a straight
    along the water, a chicane, and one grade-separated crossing where it bridges over the
    highway stub; a start line on the straight. The grid's avenues meet the ring at
    signalled junctions, its small streets at stop signs; the sweepers have no junctions;
  - a **bridge** on the loop over a canal that cuts the district in two, with a footbridge
    beside it and a boat-sized gap of water under it;
  - a **town grid** of three by three blocks inside the loop, its two avenues running out to
    the ring on both sides: signals at the centre crossing and where the avenues meet the
    ring, stop signs elsewhere, one-way pair, bus lane, sidewalks, crossings, shopfronts, a
    multi-storey garage with an underground entrance, a surface lot, kerb parking;
  - a **highway stub** with an on and an off ramp joining the loop, a gore at each, and an
    underpass where a path crosses under it;
  - **services**: a police station with a helipad, a hospital with an ambulance bay, a fire
    station, each on its own block with its driveway;
  - a **park** with trees, a tree row, grass, a path network and the footbridge;
  - **residential streets** with houses and driveways on the far side of the canal;
  - a **dead end** at the map edge for the edge closure, and a bus loop with stops and a
    reserved lane;
  - a **rail stub** with a station, tagged for `add-rail`, inert until that lands;
  - the **spawn** on the loop's straight, facing the start line.
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
