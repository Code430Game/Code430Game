# Open work

Every change below is ready to pick up: an OpenSpec change in `openspec/changes/<id>/` with a
`proposal.md`, `tasks.md` and spec deltas that pass `openspec validate --strict`. Read
`CONTRIBUTING.md` first, then the change's folder. Claim a change before starting
(`CONTRIBUTING.md`, Claiming work).

Updated 2026-10-10.

## Ready to build

Medium:

| Change | What | Depends on | Touches |
|---|---|---|---|
| `add-play-log` | the game logs what happened (ambulance arrived, rain started, traffic lights at night) so Deck checks are confirmed from the log; testers can attach it to reports | nothing | new `game/core/playlog/`, one-line calls in the gameplay systems, `tools/playlog`, the report form |
| `update-parking` | lot layout passes, street-side parking lanes | the maintainer's lot screenshots for the layout half | importer parking, lot builder, lanes and markings |
| `add-district-edge` | proper closures and a fog fade at the map edge | nothing | importer barriers, edge builder, traffic |
| `add-underpass-interiors` | lights, retaining walls, tone-gated shelters | nothing | underpass builder, pedestrians, content modes |
| `add-skywalks-and-building-parts` | footbridges and buildings over roads | nothing | importer pedestrian/buildings, building builder |
| `add-fire-response` | small fires and fire trucks | ambulance dispatch (merged) | new `fires.gd`, emergency dispatch, crash hook |

Large:

| Change | What | Depends on | Touches |
|---|---|---|---|
| `adopt-art-kit` | Quaternius CC0 kit for vehicles, people, trees and props, and building facades, in four stages | nothing (licence receipts first) | third-party assets, vehicle catalogue, character pipeline and walk shader, vegetation, building builder |
| `update-houses-and-yards` | house types with doors and porches, front lawns, fenced backyards | nothing | importer buildings and a new yards stage, building builder, dressing |
| `update-commercial-buildings` | office facades with a base and a top, business signs (generic names), posters by tone | nothing | importer businesses, building builder and shader, dressing, content modes |
| `add-landmarks` | custom landmark models replacing generated buildings; Parliament first | nothing | pack format, a landmark builder, building builder, vegetation |
| `add-hover-cars` | dystopia flying cars | helicopter (merged) | new hover car, catalogue, controls, traffic, police |
| `add-two-wheelers` | bicycles and motorcycles | nothing | importer bike lanes, traffic, vehicles, character rig |
| `add-bus-routes` | numbered routes, signs, shelters | nothing | importer routes, traffic, bus mesh, dressing |
| `add-rail` | the Confederation Line with trains | nothing | importer rail, track builder, trains, co-op |
| `add-character-features` | more clothes and hair, crowd LODs | `add-character-detail` (built, awaiting its Deck try) | character profile/mesh/rig, pedestrian shader |
| `add-story-pack` | the first mission, "First Ride", with the Double Cross crew as the antagonist | `add-pack-loader` (merged #100), `add-hostile-gang` (merged #97) | missions, markers, co-op |
| `add-pack-repositories` | (Ottawa moved to Code430Packs/Location-OttawaOnCa, pinned in packs.lock.json; left: ads-generic, same-id replacement, placements, install-pack.sh, Deck) each location (city, one pack per district), story and ads pack in its own repository in `Code430Packs` (`Location-OttawaOnCa`); the game pins them in a lock file; install a pack from a repository | organisations created and the game moved (`Code430Game/Code430Game`); `add-pack-loader` (merged #100) | CI, packaging, pack tools, docs; moves `packs/ottawa-centretown` out |
| `add-district-stitching` | neighbouring districts of one city played as one map: chunks from the district that owns them, roads joined at borders, one minimap | `add-pack-repositories` (shared origin, borders on the chunk grid) | `PackLoader`, `MapPack`, chunk streamer, road graph, lane paths, wayfinding, importer |
| `update-audio-pass` | positional city sound, engine per class | the maintainer schedules an audio round | audio, traffic, emergency managers |

## Files several changes touch

Coordinate (or land one before the other) when two changes share these:

- `game/actors/character/character_rig.gd`: `add-two-wheelers`, `add-character-features`.
- `tools/osm_import/elevation.py`, `barriers.py`, `bridges.py`, `pack.py` and the golden
  fixture: `update-junction-surfaces`, `add-district-edge`, `add-skywalks-and-building-parts`,
  `update-parking`, `add-bus-routes`, `add-rail`. Any of these re-exports the pack, so build
  one at a time, rebase, and regenerate the pack and golden last.
- `game/world/traffic/lane_graph.gd` and `marking_builder.gd`: `update-parking`,
  `update-junction-surfaces`, `add-two-wheelers`, `add-bus-routes`.
- `game/scenes/play_testbed.gd`: almost everything; keep edits small and rebase often.

## Waiting on the maintainer's Deck try

Built and merged; each is archived once it has been played on the Deck. The Deck benchmark
tasks among them can be run with `scripts/deck-bench.sh --change <id> --task <n.n>` (it needs
the Deck on the network and the game closed); the "human tries it" tasks still need the
maintainer:
- `add-weapons-and-combat` 3.2
- `add-police` 3.2
- `add-police-helicopter` 2.2
- `add-emergency-services` 3.1
- `add-ambulance-response` 2.2
- `add-road-shoulders` 3.2 (now with the 1.4 infill and gores)
- `update-radio-per-car` 2.1
- `update-garage-polish` 2.1 (`--spawn=97,62.6,-377` starts on the NAC garage floor)
- `add-unarmed-combat` 2.1 and 2.2
- `add-weapon-selector` 2.1 (Deck benchmark; the human's try is in)
- `update-junction-surfaces` 3.1 and 3.2
- `update-police-pursuit` 4.2 and 4.3 (the human's first notes are in)
- `add-police-combat` 3.2 and 3.3
- `update-menu-design` 3.2
- `add-map-legend` 3.1
- `add-flyable-helicopter` 4.2 and 4.3
- `update-shared-deck-heights` 2.1
- `update-proving-ground-dressing` 2.3 (now with the density pass #104: smaller blocks, frontage roads)
- `add-hostile-gang` 4.2
- `add-pack-loader` 4.2 (Deck benchmark) and 4.3
- `add-weather` 4.1 (Deck benchmark, `--extra "--weather=rain"`) and 4.2
- `update-traffic-headlights` 2.1 (Deck benchmark, `--extra "--time=22"`) and 2.2

`add-coop-multiplayer` still needs:
- the tone sent on join (1.3);
- mission state (3.4), once missions exist;
- a hosting profile (5.1);
- a four-player session (5.2).

## Small fixes (no proposal needed, open a `fix/` PR)

- **Signs (billboards) in the middle of roads:** check the rule from `19d8c7f` holds wherever
  the human reports more.
- **On-screen keyboard on the Deck:** resolved 2026-10-08, the human reports Steam's keyboard now shows for the report form; no Steamworks dependency needed. Re-open only if it stops.
- More in `docs/backlog.md`.
