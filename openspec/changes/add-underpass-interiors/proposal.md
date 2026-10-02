# Change: Underpass interiors

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts; the loose ends were listed by add-underpasses).**

## Why
The 19 underpasses are dug and walkable, but they are bare concrete boxes: dim inside, the
cuttings leading down have raw terrain sides, and the tunnel by the Chateau Laurier that
people shelter in is empty. The first pass left lighting, retaining walls and the sheltering
population for after the tone system; the tone system has shipped.

## What Changes
- **Lighting:** every tunnel gets an emissive ceiling strip (unlit material, no real light) in
  both presets. The `deck` preset adds up to two `OmniLight3D` per tunnel (12 m range, no
  shadows); the `high` preset adds one every 10 m. Lights are children of the chunk under a
  new `underpass_lights` NEAR role and are always on regardless of the time of day.
- **Trench walls:** ways with the `trench` profile get retaining walls on both sides where the
  cut is deeper than 0.4 m, from the ramp floor to the terrain, with a coping on top, drawn
  by a board-formed-concrete shader using metre UVs (no textures, like the facades).
- **Drainage:** a grate strip across the tunnel floor at its low point and a dark puddle quad
  beside it, both presets.
- **Sheltering population:** a new content descriptor `homelessness` (levels none / mild /
  strong) joins the closed list; `clean` allows none, `gritty` and `dystopia` allow strong.
  When `ContentMode.allows("homelessness")`, tunnels get shelter spots along their walls
  (one per 8 m, up to `shelter.max_per_tunnel`) with belongings props (bedroll, bags, a cart)
  built from pack data, and the host spawns `sheltering` pedestrians at a share of the spots
  who sit or lie there in new rig poses. They are ordinary agents: snapshot-replicated,
  despawned when far, out of the walking lanes so walkers pass by, never struck by traffic
  because no traffic enters tunnels.
- **Not in this change:** dialogue or interaction with sheltering people, begging or giving,
  police or mission hooks, lighting outside tunnels, trench walls for road cuttings.

## Impact
- Affected specs: `street-dressing` (Underpasses modified), `pedestrians` (new requirement),
  `content-modes` (new descriptor requirement).
- Affected code: `game/world/roads/underpass_builder.gd` (strip, grate, puddle, walls, light
  positions), `underpass_wall.gdshader` (new), `game/world/packs/map_pack.gd` and
  `game/world/build/pack_builder.gd` (`underpass_lights` role, preset-gated light count),
  `game/core/content/content-descriptors.v0.json` and `modes/*.json`,
  `docs/pack-format/content-descriptors.v0.json` and `README.md` (migration note),
  `tools/pack_tools` validator, `game/world/pedestrians/pedestrian.gd` (`SHELTERING` state),
  `pedestrian_manager.gd` (shelter spots, spawn, snapshot pose), `pedestrian_config.json`
  (`shelter` block), `game/actors/character/character_rig.gd` (sit and lie poses),
  `game/world/dressing/shelter_props.gd` (new), `game/tests/test_underpasses.gd`,
  `test_pedestrians.gd`, `test_content_mode.gd`.
- Co-op: the host decides which spots are occupied and simulates the people; the snapshot
  stride gains a pose index so clients draw them seated or lying. Props are deterministic
  from pack data and the session's tone mode, which the host already sets for everyone.
- Tone: one `allows("homelessness")` check in the pedestrian manager and the props builder;
  no mode ids in gameplay code. The clean mode shows lit, empty tunnels.
- Performance: at most 38 OmniLights district-wide on the Deck, only in NEAR chunks, never
  more than a few in view; walls add about 200 triangles per trench. Deck measured.
