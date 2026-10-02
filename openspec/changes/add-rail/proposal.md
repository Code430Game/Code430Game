# Change: Rail

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts; rail was asked for on 2026-10-02).**

## Why
Ottawa's downtown is stitched together by the Confederation Line: a tunnel under Queen Street
with Lyon, Parliament and Rideau stations, surfacing at Pimisi on the Flats to the west and
past uOttawa to the east. The importer only queries `highway=*`, so none of it exists: no
tracks on the Flats, no platforms, nothing moving on the line. Trains crossing the view every
few minutes are the kind of texture that makes a real city read as real.

## What Changes
- **Importer stage `rail`:** a second Overpass query for `railway` ways (`rail`, `light_rail`,
  `subway`, `tram`), `railway=platform` ways and `railway=station` / `public_transport=station`
  nodes. Tracks are projected and height-sampled like roads (surface tracks flatten the terrain
  under a narrow margin; `tunnel=yes` or `layer<0` tracks sit below ground at the road-tunnel
  depth rule) and exported to a new `rail.v0.json`: `tracks[]` (polyline, kind, layer, tunnel,
  bridge, name, service, osm_way_id), `stations[]` (position, name, underground, platforms),
  `lines[]` (connected track components of one kind with their stations in order, a default
  headway, dwell and speed). Rail never enters the road graph or the lane graph.
- **Game:** `TrackBuilder` draws surface track ribbons per chunk (ballast bed, two rails, ties
  at LOD0; a flat strip at LOD1) under a new `rail_lod0` NEAR role; tunnel tracks are not
  drawn. `StationBuilder` draws surface platforms (slab, canopy, name sign) at surface
  stations; underground stations get nothing yet. Where a track and a road share a node
  (`railway=level_crossing`) the rails are laid flush across the road surface and the ballast
  is dropped inside the ribbon.
- **Trains:** a `RailManager` (host-simulated, like `TrafficManager`) runs trains along each
  line in both directions at the line's headway, dwelling at stations. Each train is one
  scene (`train.tscn`: N car bodies from `train_mesh.gd`, `AnimatableBody3D` per car) since
  there are only a handful; trains inside tunnels are hidden. Trains stop for nothing; a
  player car on a level crossing is hit like hitting a bus. Trains cannot be entered or taken.
  Clients receive train state in a snapshot alongside traffic.
- **Not in this change:** underground stations and their entrances, riding trains, timetable
  editing, crossing gates and warning lights, platform crowds, tram street-running rules.

## Impact
- Affected specs: `rail` (new).
- Affected code: `tools/osm_import/fetch.py` (second query), `rail.py` (new), `pipeline.py`,
  `pack.py` (flatten under surface tracks, write `rail.v0.json`), `docs/pack-format/rail.schema.v0.json`
  (new), `tools/tests/test_osm_rail.py`; `game/world/rail/` (new: `rail_data.gd`, `track_builder.gd`,
  `station_builder.gd`, `rail_manager.gd`, `train_mesh.gd`, `train.tscn`), `map_pack.gd`
  (role `rail_lod0`), `pack_builder.gd`, `core/net/world_sync.gd` (train snapshot),
  `play_testbed.gd`, `game/tests/test_rail.gd`; the Ottawa pack re-exported.
- Co-op: the host owns every train; clients mirror from the snapshot. A train is never owned
  by a client, and nothing changes when a peer leaves.
- Tone: rail carries no authored content and reads no mode flags. Station names come from OSM.
- Performance: one more ribbon role per chunk and at most six train scenes of four cars each,
  about 2k triangles per car. The Confederation Line adds roughly 3 km of surface track in the
  district. Deck measured before the gate.
