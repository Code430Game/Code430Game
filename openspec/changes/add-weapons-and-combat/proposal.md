# Change: Weapons and combat, paintball in clean

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts). Human's brief: "shooting people with various devices and stabbing; paintball vs bullets for the different tones."**

## Why
The game has cars, people and a city but no way to act on them beyond driving. Weapons are
the first GTA-shaped mechanic and the first mechanic the tone system has to carry: `clean`
already sets `lethal_weapons: false` and `violence: false` in `game/core/content/modes/clean.json`,
but nothing reads those flags yet. Building the mechanic tone-neutral from the start, with the
weapon, its projectile, its impact and the victim's reaction all coming from tagged data, means
a paintball marker in `clean` and a pistol in `gritty` share every line of aiming, firing and
hit code.

## What Changes
- **Weapons as data.** `docs/pack-format/weapons.schema.v0.json`: a weapon has a slot, a
  mechanic (`melee`, `hitscan`, `projectile`), rate, magazine, reload time, range, spread,
  descriptors and per-mode `variants` with a required `fallback`. A variant names the thing in
  hand, its `impact` kind (`bullet`, `blade`, `blunt`, `paint`, `water`, `foam`), whether it is
  `lethal`, and may override the mechanic. First-party set in `game/actors/combat/weapons.v0.json`:
  fists, knife, pistol, SMG, shotgun with `clean` variants foam gloves, foam bat, paintball marker,
  paintball repeater, water balloon launcher. `ContentMode.pick_variant` chooses; a variant marked
  `lethal` is only usable when `ContentMode.flag("lethal_weapons")` is true, and a weapon whose
  allowed variant has no `impact` the mode permits leaves its slot empty.
- **Carrying and firing.** Five slots on the layout `update-controls-layout` settled (and
  reserved in the input map): LB tapped for the next weapon and held for the weapon wheel / Tab,
  the mouse wheel and number keys; aim on LT / right mouse, fire on RT / left mouse, reload on
  B / R (on foot only; those inputs stay the driving actions in a car). Aiming tightens the
  chase camera over the shoulder with a reticle. Melee swings on fire. Guns are hitscan;
  paintballs, balloons and other `projectile` variants are small physics bodies with a short
  life that call the same hit callback. A debug refill on the debug menu is the only ammo
  source.
- **Impacts.** Pooled decals on world geometry (bullet holes, paint splats, wet marks) with a
  per-preset cap and oldest-first recycling; muzzle flash and a synthesised shot or pop from
  `Synth`. Traffic cars take a per-agent damage value shown as a body tint (dents or paint
  smears by impact kind); past a threshold a car stops and stays put (`resting`). Tyres can be
  shot out only when `lethal_weapons` is on.
- **Victim reactions** (`pedestrians`): a lethal impact sends a pedestrian to `DOWN` as a car
  hit does, with a blood decal only when `ContentMode.allows("gore")`; a non-lethal impact
  marks the body (paint colour, wet) and sends it `FLEEING`, running off the ribbon for a
  configured time before walking again. Pedestrians within earshot of gunfire flee in every
  mode. Nobody is ever `DOWN` in `clean`.
- **Player health.** 100 points, damaged by lethal impacts from other players (co-op) and by
  vehicle hits; at zero the player is down for a few seconds and respawns at the spawn point
  with slots refilled. In `clean` players are painted, never down.
- **Not in this change:** wanted level and police response (own change), weapon shops and the
  economy, ammo pickups in the world, NPCs that fight back, fire and explosions, missions, a
  hospital point of interest for respawn (spawn point for now), drive-by firing from a car.

## Co-op authority
The shooter owns its projectiles and hit tests and reports hits to the host through
`WorldSync` (`report_shot`, next to `report_hit` in `game/core/net/world_sync.gd`); the host
applies pedestrian and traffic damage and replicates the result through the existing snapshots,
which gain a state code per agent. Player health is host-authoritative: a hit on another player
goes to the host, which tells the victim. Decals, flashes and sounds are local cosmetics
triggered by an unreliable shot event broadcast to everyone in range. Hosts use the same path
with no round trip.

## Tone
Weapons read `ContentMode` only through `pick_variant`, `allows("gore")` and
`flag("lethal_weapons")`; no mode ids appear in gameplay code. Changing mode mid-session swaps
every slot to the new variant and clears decals.

## Impact
- Affected specs: `combat` (new), `pedestrians` (new requirement), `traffic` (new requirement).
- Affected code: `game/actors/combat/` (new: `weapon_set.gd`, `weapon.gd`, `shooter.gd`,
  `projectile.gd`, `impact_decals.gd`, `weapons.v0.json`, `combat_config.json`),
  `game/actors/player/player.gd` and `player_config.gd` (slots, aim, health),
  `game/actors/vehicles/chase_camera.gd` (aim framing), `game/ui/` (reticle, health, slot HUD),
  `game/world/pedestrians/pedestrian.gd`, `pedestrian_manager.gd`, `pedestrian_body.gd`,
  `pedestrian_config.json` (reactions), `game/world/traffic/traffic_agent.gd`,
  `traffic_manager.gd`, `traffic_config.json` (damage), `game/core/net/world_sync.gd`,
  `game/core/audio/synth.gd` (shot voice), `game/project.godot` (input actions),
  `docs/pack-format/weapons.schema.v0.json`, `tools/pack_tools` (schema check), tests.
- Performance: decals are the only new per-frame cost; capped at 48 on `deck` and 160 on `high`.
  Projectiles are a handful of small bodies. Deck measured in a firefight on Bank Street.
- Content policy: no real weapon brands or model names; weapon names are generic. Nothing here
  widens what a mode allows.
