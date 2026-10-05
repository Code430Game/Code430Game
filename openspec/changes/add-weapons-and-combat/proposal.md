# Change: Weapons, first pass (a melee weapon and a gun in every tone)

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts). Human's brief: "shooting people with various devices and stabbing; paintball vs bullets for the different tones."**

**Scoped down 2026-10-05 (human: "I wonder if we add a knife and pistol (gritty) or sabre and blaster (dystopian), or paint brush and paintball gun (pg)" ... "Do the simple weapons and then add the police!").** This first pass carries two weapons, each with a variant per tone. The rest of the original slate (more weapons, traffic damage, player health, co-op shots) moves to follow-ups; police are their own change next.

## Why
The game has cars, people and a city but no way to act on them beyond driving. Weapons are
the first GTA-shaped mechanic and the first mechanic the tone system has to carry: `clean`
already sets `lethal_weapons: false` and `violence: false` in `game/core/content/modes/clean.json`,
but nothing reads those flags yet. Building the mechanic tone-neutral from the start, with the
weapon, its projectile, its impact and the victim's reaction all coming from tagged data, means
a paintball marker in `clean` and a pistol in `gritty` share every line of aiming, firing and
hit code.

## What Changes
- **Weapons as data.** `docs/pack-format/weapons.schema.v0.json`; a weapon has a slot, a
  mechanic (`melee`, `hitscan`, `projectile`), rate, magazine, reload time, range, spread and
  per-mode `variants` with a required `fallback`. A variant names the thing in hand, its
  `impact` (`blade`, `bullet`, `energy`, `paint`), whether it is `lethal`, and may override the
  mechanic. First-party set in `game/actors/combat/weapons.v0.json`, two weapons:

  | weapon | clean | gritty (fallback) | dystopia |
  |---|---|---|---|
  | melee | paint brush (paint, a splat) | knife (blade) | sabre (energy, glowing) |
  | gun | paintball gun (paint projectile) | pistol (bullet, hitscan) | blaster (energy bolt, hitscan with a glowing tracer) |

  `ContentMode.pick_variant` chooses; a variant marked `lethal` is refused when
  `flag("lethal_weapons")` is false.
- **Carrying and firing.** On foot only. LB (Tab) cycles empty hands, melee, gun; LT / right
  mouse aims, pulling the camera over the shoulder with a reticle; RT / left mouse fires or
  swings; B / R reloads. Guns raycast from the camera through the reticle; paintballs are small
  pooled bodies with gravity; melee is a short sweep in front of the player. One hit path for
  all three. Unlimited reserve ammo in this pass (magazines and reloads only).
- **Impacts.** Pooled decals on world geometry (paint splats, bullet holes, scorch marks) with
  a per-preset cap and oldest-first recycling; a muzzle flash or bolt glow; synthesised shot,
  zap, swish and splat voices from `Synth`.
- **Pedestrian reactions.** A lethal hit knocks the pedestrian down through
  `PedestrianManager.knock_down` (the ragdoll hook built for this), with a blood mark only when
  `ContentMode.allows("gore")`. A non-lethal hit tints the body with paint and sends it
  fleeing: running away from the shooter for a configured time, then walking again. Walkers
  within earshot of a gunshot flee in every mode. Nobody goes down in `clean`.
- **Not in this change:** more weapons (SMG, shotgun, water balloons), traffic damage and shot
  tyres, player health and respawn (with the police change), co-op shots (a guest's shots are
  local in this pass; host-authoritative hits follow), weapon shops, ammo pickups, NPCs that
  fight back, explosions, drive-by firing.

## Co-op authority
First pass: shots, decals and reactions run on the shooter's machine; on a host that is the
authoritative simulation. A guest's hits do not yet reach the host (follow-up: `report_shot`
through `WorldSync`, the host applies reactions and snapshots carry them).

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
