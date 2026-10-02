# Design: underpass interiors

## Lights and presets
- The emissive strip carries the look; real lights only add a glow on the walls and the
  player. `presets.json` gains `underpass_lights_per_tunnel` (deck 2, high 0 meaning one per
  10 m) so each preset declares the behaviour, per the constitution.
- Lights are plain nodes under the chunk, created when the chunk is built at the NEAR tier
  and freed with it, so streaming owns their lifetime; nothing is city-wide.

## Shelter spots
- Spots are derived at load from the tunnel ways: walk the centreline, every 8 m place a spot
  against alternating walls at `half_width - 0.6 m`, skip the first and last 6 m so portals
  stay clear. Seeded by the way id so every peer gets the same spots.
- Props per spot are chosen from a small set (bedroll, bags, cart, none) by the same seed and
  drawn as vertex-coloured meshes under a `shelter_props_lod0` NEAR role; they exist only when
  the mode allows the descriptor.
- The host fills `shelter.occupancy` (0.5) of the spots in tunnels within the pedestrian spawn
  radius with `SHELTERING` agents; they count against `max_agents`, never move, and despawn
  with the usual far rule so a spot can be refilled later.

## Poses and snapshots
- `CharacterRig` gains `set_pose(pose)` with `WALK`, `SIT` and `LIE`; the walk cycle is frozen
  at zero and the hip, knee and spine bones take fixed angles.
- The pedestrian snapshot stride grows from 5 to 6 floats with a pose index; `apply_snapshot`
  reads it. Both sides are in this change, so the protocol stays consistent.

## Descriptor migration
- `content-descriptors.v0.json` is a closed list by its own note; adding `homelessness` is a
  pack-format change at schema version 0 with a migration note in `docs/pack-format/README.md`:
  packs that omit the descriptor are read as `none`, so nothing already shipped changes.
