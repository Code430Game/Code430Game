# Change: A hostile gang

**Status: proposed 2026-10-07 (human: "a smaller area we can use for testing ... like a race track + other things ... a police, hospital, etc ... some light story ... a baddie that wants to attack us on sight, a gang"). Depends on `add-weapons-and-combat` and `add-police-combat` (built), and on `add-proving-ground` for its first turf; the gang itself must also work in Ottawa.**

## Why
Nothing in the city wants the player. Pedestrians flee, officers answer crimes, and the
only fights are the ones the player starts. A faction that recognises the player on its
turf and comes for them gives the proving ground something to drive into, the weapons an
opponent that fights back, and the first story pack its antagonist: "First Ride" needs
someone to deliver against. Built as data, it is also the first content a pack can add
beyond ads and radio.

## What Changes
- **Factions as tagged data.** `docs/pack-format/factions.schema.v0.json`; the base game
  ships `game/core/content/factions.v0.json` with one gang, and a pack's `factions.v0.json`
  adds or overrides. A faction has an id, a name, descriptors (`violence`, `crime`, both
  `strong`), per-mode `variants` with a required fallback (clean: a prank crew with the
  foam bat, the paintball marker and water balloons, who "tag" rather than hurt; gritty:
  knives and a pistol for some; dystopia: sabres and blasters with a neon livery), the
  member look (a palette and garments drawn through the character profile), a gang car
  from the vehicle catalogue with a livery, group size, aggression, sight range and the
  threat tunables, with defaults in `faction_config.json`.
- **Turf.** A polygon per faction placed by the map pack: `turf.v0.json` in the proving
  ground around the warehouse blocks past the canal, and for Ottawa a turf in
  `overrides.json` so the gang can be tried in the Market. The map legend shows turf as a
  hatched fill; the minimap shows its edge.
- **Members on the ground.** The host spawns members in the turf up to a cap: pairs walking
  the turf's streets on the pedestrian walk graph and one gang car cruising its roads with
  two aboard, using the traffic lanes. Members are pedestrians with a faction, so the
  pedestrian pools, LODs and snapshots carry them (a faction index in the snapshot), and
  the Shooter's hit path reaches them through a `faction` collision layer.
- **Recognition and the threat machine.** Inside the turf, a member who sees the player
  (sight range, line of sight, the police's seen rules) goes `alert`, calls nearby members,
  and after a short warning (a shout, a hand up) the group goes `attack`: melee from the
  nearest, the mode's ranged variant from the others at range, with the police-combat
  reactions reused in reverse (the player's health and down rules from `add-weapons-and-
  combat`). `flee` when outnumbered, hurt past a threshold, or when the police arrive on a
  gunfire report; `regroup` at the turf's centre, then back to `patrol`. Outside the turf
  members ignore the player unless hit. Downed members respawn at the turf after a cooldown.
- **Gang heat.** A faction meter, separate from the wanted stars: it rises while members
  can see the player in turf, shows as a glyph on the HUD beside the seen badge, and drains
  after the player has been out of the turf for a configured time; at full it sends the
  gang car. No stars for being attacked; the player's own crimes still report as today.
- **Police.** Gunfire by members reports `gunfire` from the shooter's position like any
  other, so officers come to a gang fight; a configurable flag decides whether officers
  treat members as hostile (they do by default: officers fight the gang, the gang fights
  back, the player can watch or join) or ignore them.
- **Not in this change:** missions, dialogue, a gang hideout interior, recruiting or
  bribing, gang territory changing hands, more than one faction, gang vehicles that chase
  outside the turf, drive-by fire.

## Co-op authority
Host-authoritative like the police: the host simulates members, their state machine, the
heat meter per player and the respawns; members ride the pedestrian snapshots with a
faction index and a state code; a peer's hits on members go through the shared
`report_shot` path and the host adjudicates; the gang car is host-owned traffic.

## Tone
Variants and the `lethal_weapons` flag decide the weapons; reactions come from the mode
data (`outcomes.gang`: `knock_down` in gritty and dystopia, `tag_out` in clean) like
`outcomes.officer`. Clean never downs a member and never shows blood. Descriptors on the
faction keep it out of a pack that does not support the mode.

## Impact
- Affected specs: `factions` (new), `police` (ADDED: officers and the gang).
- Affected code:
  - `game/actors/factions/` (new: `faction_manager.gd`, `gang_member.gd` on the pedestrian
    body, `threat.gd` state machine, `faction_config.json`), `game/core/content/factions.v0.json`;
  - `game/world/pedestrians/pedestrian_manager.gd` and `pedestrian.gd` (faction index,
    states, snapshot stride), `game/world/traffic/traffic_manager.gd` (the gang car);
  - `game/actors/combat/shooter.gd` (hits reach members), `game/actors/police/police_manager.gd`
    and `wanted.gd` (gang gunfire, officers against members), `game/core/net/world_sync.gd`;
  - `game/ui/hud/` (gang glyph), `game/ui/map/` (turf fill and edge);
  - `docs/pack-format/factions.schema.v0.json` and `turf.schema.v0.json`, `tools/pack_tools`
    (descriptor and variant checks), the mode files and tone schema (`outcomes.gang`);
  - `packs/proving-ground/turf.v0.json` (via the generator), `packs/ottawa-centretown/overrides.json`;
  - `game/scenes/play_testbed.gd` (`--gang=N` spawns the gang around the player, `--turf-log`);
  - tests.
- Performance: members share the pedestrian pools and bodies; the cap keeps a fight to a
  dozen on screen. Deck benchmark in the proving ground turf during a fight.
