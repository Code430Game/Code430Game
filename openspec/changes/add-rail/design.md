# Design: rail

## Data
- Rail is a separate dataset. `rail.v0.json` sits beside `road_graph.v0.json`; `RoadGraph`,
  `LaneGraph` and `WalkGraph` never see it, so no traffic or pedestrian code path changes.
- Tracks keep OSM topology (shared nodes become track joins) but are not clustered into
  junctions; a `lines[]` entry is a connected component of one kind with its stations ordered
  by distance along the component's longest simple path. Branches shorter than
  `rail.min_branch_m` (a yard stub) are dropped with a note in the validation report.
- Heights: surface tracks sample the DEM like roads and flatten the terrain within
  `rail.flatten_margin_m` (3 m) of the centreline; bridge tracks keep the bridge rule;
  `tunnel=yes` or `layer<0` tracks take the road-tunnel depth rule and are flagged `tunnel`.
  Where a tunnel track joins a surface track, the surface end ramps to the tunnel depth over
  `rail.portal_ramp_m` so a train slides into the ground at a portal rather than popping.
- The timetable is data: each line has `headway_s` (300), `dwell_s` (20), `speed_kph` (60)
  from `osm_import/config.json` defaults, overridable per line in `overrides.json`.

## Crossings
- A node shared by a track and a road (`railway=level_crossing`, or any shared node as a
  fallback) is a level crossing. The road ribbon is already there; the track builder drops
  the ballast and ties inside the road ribbon's width plus 0.5 m and lays the two rails at
  road surface height plus the marking lift, so a car rolls over them. Nothing else stops
  traffic or the player.
- Grade-separated crossings need nothing: the tunnel is not drawn and bridges keep their
  deck height.

## Trains
- `RailManager` holds `Train` records (line, direction, distance along the line, dwell left)
  and steps them at the line speed with a constant-deceleration approach to each station.
  Trains spawn at `t = 0` spaced one headway apart along the line in each direction, so the
  pattern is deterministic from the world clock the host already broadcasts.
- Each train is one `train.tscn`: `cars` `AnimatableBody3D` nodes placed along the track by
  arc length with `train_mesh.gd` (box body, windows band, doors, a single colour per line).
  No MultiMesh and no body pool: a line never has more than `line_length / headway` trains.
- A train whose head and tail are both inside tunnel track is hidden (`visible = false`);
  bodies stay so a player in a future underground station is not run through.
- Clients: `world_sync.gd` sends one `PackedFloat32Array` of (line, direction, distance) per
  train at the traffic snapshot rate; `apply_snapshot` sets positions and lets the local
  manager place cars. Collisions on a client happen against the mirrored bodies.

## Stations
- A surface station draws a platform slab per `platforms[]` polyline (OSM `railway=platform`),
  or a synthesised 90 m x 3 m slab on the station's side of the track when OSM has none, a
  canopy on posts along the slab, and a `Label3D` name sign at each end. Underground stations
  are listed in the data and skipped by the builder.

## Budget
- Track LOD0 (ballast, ties every 0.6 m, rails) within the sidewalk visible range; LOD1 a flat
  dark strip to the road LOD1 range. Deck preset: ties merged into a striped ballast strip,
  no per-tie geometry.
