# Open work

Every change below is ready to pick up: an OpenSpec change in `openspec/changes/<id>/` with a
`proposal.md`, `tasks.md` and spec deltas that pass `openspec validate --strict`. Read
`CONTRIBUTING.md` first, then the change's folder. Claim a change before starting
(`CONTRIBUTING.md`, Claiming work).

Updated 2026-10-06.

## Ready to build

Small and self-contained:

| Change | What | Depends on | Touches |
|---|---|---|---|
| `update-radio-per-car` | each car keeps its own station | nothing | radio, car, testbed enter/exit |
| `update-garage-polish` | minimap inside garages, clean ramp terrain cuts | nothing | minimap, garage builder |
| `add-unarmed-combat` | punches and kicks for empty hands | nothing | shooter, held weapon, character rig |
| `update-shared-deck-heights` | one height for touching bridge carriageways | nothing | importer elevation, golden, pack |

Medium:

| Change | What | Depends on | Touches |
|---|---|---|---|
| `update-junction-surfaces` | point-like junctions, curbs inside junctions, terrain through | the maintainer's junction locations help | importer cluster/forks/barriers/pack, junction builder, lane graph |
| `update-parking` | lot layout passes, street-side parking lanes | the maintainer's lot screenshots for the layout half | importer parking, lot builder, lanes and markings |
| `add-road-shoulders` 1.4 | concrete infill between carriageways, paved gores | `update-shared-deck-heights` first | importer bridges/barriers, golden, pack |
| `add-district-edge` | proper closures and a fog fade at the map edge | nothing | importer barriers, edge builder, traffic |
| `add-underpass-interiors` | lights, retaining walls, tone-gated shelters | nothing | underpass builder, pedestrians, content modes |
| `add-skywalks-and-building-parts` | footbridges and buildings over roads | nothing | importer pedestrian/buildings, building builder |
| `add-fire-response` | small fires and fire trucks | ambulance dispatch (merged) | new `fires.gd`, emergency dispatch, crash hook |

Large:

| Change | What | Depends on | Touches |
|---|---|---|---|
| `add-weather` | sky, rain, snow, fog, wet roads | nothing | sky shader, materials, traffic and grip factors |
| `add-hover-cars` | dystopia flying cars | helicopter (merged) | new hover car, catalogue, controls, traffic, police |
| `add-two-wheelers` | bicycles and motorcycles | nothing | importer bike lanes, traffic, vehicles, character rig |
| `add-bus-routes` | numbered routes, signs, shelters | nothing | importer routes, traffic, bus mesh, dressing |
| `add-rail` | the Confederation Line with trains | nothing | importer rail, track builder, trains, co-op |
| `add-character-features` | more clothes and hair, crowd LODs | `add-character-detail` (built, awaiting its Deck try) | character profile/mesh/rig, pedestrian shader |
| `add-pack-loader` | v1 pack format and a Packs menu | nothing | pack tools, loader, registry, co-op handshake |
| `add-story-pack` | the first mission, "First Ride" | `add-pack-loader` | missions, markers, co-op |
| `update-audio-pass` | positional city sound, engine per class | the maintainer schedules an audio round | audio, traffic, emergency managers |

## Files several changes touch

Coordinate (or land one before the other) when two changes share these:

- `game/actors/character/character_rig.gd`: `add-unarmed-combat`, `add-two-wheelers`,
  `add-character-features`.
- `tools/osm_import/elevation.py`, `barriers.py`, `bridges.py` and the golden fixture:
  `update-shared-deck-heights`, `add-road-shoulders` 1.4, `update-junction-surfaces`,
  `add-district-edge`, `add-skywalks-and-building-parts`. Any of these re-exports the pack, so
  merge them one at a time and rebase.
- `game/world/traffic/lane_graph.gd` and `marking_builder.gd`: `update-parking`,
  `update-junction-surfaces`, `add-two-wheelers`, `add-bus-routes`.
- `game/scenes/play_testbed.gd`: almost everything; keep edits small and rebase often.

## Waiting on the maintainer's Deck try

Built and merged; each is archived once it has been played on the Deck:
- `add-weapons-and-combat` 3.2
- `add-police` 3.2
- `add-police-helicopter` 2.2
- `add-emergency-services` 3.1
- `add-ambulance-response` 2.2
- `add-road-shoulders` 3.2
- `add-character-detail` 2.2 and 2.3

`add-coop-multiplayer` still needs:
- the tone sent on join (1.3);
- mission state (3.4), once missions exist;
- a hosting profile (5.1);
- a four-player session (5.2).

## Small fixes (no proposal needed, open a `fix/` PR)

- The README's pack-builder command points at a file that does not exist.
- The high preset's fog hides the city beyond about 50 m at noon (check the volumetric fog
  density).
- More in `docs/backlog.md`; the junction and parking items there now have proposals.
