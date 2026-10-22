# Change: Vehicle and building damage

**Status: proposed 2026-10-22 (human, after the helicopter unstick fix: "We can also look at
vehicle and building damage"; "Yes, lets write it up."). The choices marked _(to confirm)_
are the open questions; the rest follows the helicopter's damage and the tone outcomes.**

## Why
Crashes and gunfire leave no trace. A car hit at 80 km/h drives on as new, shooting a car
does nothing, and a building only takes a bullet-hole decal. The helicopter already has
health and outcomes by tone (`outcomes.aircraft`); cars and buildings should answer the same
way, so a chase leaves a car that looks like it was in one.

## What Changes
- **Car damage.** Every drivable car (the player's, a taken traffic car, a parked car once
  disturbed) gets health, 100 to 0, lost to:
  - crashes, by closing speed above a threshold (the `impacted` speed the car already emits);
  - weapon hits, by a new per-weapon `vehicle_damage` in the weapons data (fists do little).
  It shows in stages:
  - **Scuffed** (below 80): scrape marks near the hit.
  - **Dented** (below 50): the body pushed in around each hard hit, a cracked windscreen, and a
    headlight or tail light out on a front or rear hit.
  - **Smoking** (below 25): smoke from the engine, top speed and pull cut by half.
  - **Wrecked** (0): what happens comes from the tone's new `outcomes.vehicle` (below). The
    car can't be driven; the player gets out.
- **Tone** (`outcomes.vehicle`, like `outcomes.aircraft`):
  - **clean, `conk_out`:** dents and cartoon puffs of smoke, never flames. A wreck stalls and
    can be driven again after a reset (hold R3).
  - **gritty, `burn`:** a wreck smokes, then burns for a while and leaves a blackened shell.
  - **dystopia, `burn`:** the same, with sparks instead of the engine smoke _(to confirm)_.
  - No explosions in this change _(to confirm: a burning wreck could blow after some seconds
    in gritty and dystopia, hurting what is near)_.
- **Repair.** Holding reset (R3) puts a damaged car on the road as now and keeps its damage;
  a wreck in clean is the exception (it is mended). Driving into one of the map's garages
  mends it fully _(to confirm: free, or only when not wanted)_.
- **Traffic.** Traffic cars take the same damage when hit or shot. A traffic car wrecked with
  its driver aboard stops, the driver gets out and runs. Wrecks are removed by the normal
  traffic despawn once out of sight.
- **Buildings.** Buildings stay solid (chunks are merged, cached meshes; nothing breaks off):
  - **Glass breaks.** A shot or a hard hit on a glass facade breaks that pane: shards, a
    sound, and a broken-pane mark over the window.
  - **Crash marks.** A car hitting a wall hard leaves a scrape or a dent mark there, as bullet
    holes do now, through `CombatEffects.mark` and its cap.
  - Scorch marks on the ground and walls beside a burning wreck.
  - Marks and broken panes are visual only and fade with the existing mark cap and chunk
    unload; they are not saved.
- **Police.** Wrecking someone else's car where the police see it is a crime
  (`property_damage`, one star). Damage to the player's own car is not.
- **Fire trucks.** `add-fire-response` gets its fires from here: a burning wreck is a fire it
  can answer. That change still brings the trucks.
- **Co-op.** The driver owns their car's health and sends its stage and its dents (a few hit
  points) with the vehicle state; the host owns traffic and parked cars. Panes and marks are
  local to each player.
- **Play log** (`add-play-log`): `vehicle_damaged` (stage changes), `vehicle_wrecked`,
  `vehicle_repaired`, `pane_broken`.

## Not in this change
Buildings breaking apart, street furniture knocked over, explosions (unless confirmed),
tyres bursting, damage saved between sessions.

## Impact
- Affected specs: `vehicles` (ADDED: Vehicle Damage, Wrecks By Tone), `map-buildings`
  (ADDED: Building Damage Marks).
- Affected code:
  - new `game/actors/vehicles/vehicle_damage.gd` (health, stages, dents) and
    `vehicle_damage.json` (thresholds, crash and weapon scales);
  - `placeholder_car.gd`, `traffic_car.gd`, `parked_cars.gd` (taking damage, the stage's
    effects, getting out of a wreck);
  - `vehicle_mesh.gd`: a damaged car gets its own copy of the shared mesh (only then), so
    undamaged traffic keeps sharing it; at most a few dented copies at once on the Deck preset;
  - `game/core/content/modes/*.json` and the mode schema (`outcomes.vehicle`);
  - the weapons data (`vehicle_damage`), `shooter.gd` (hits on cars and glass);
  - `combat_effects.gd` (scrape, dent, broken pane, scorch marks; smoke and shards);
  - `building_builder.gd` (which faces are glass, for the pane hit);
  - `police_config.json` (`property_damage`), `wanted`;
  - `world_sync.gd` / `player_sync.gd` (damage state); `docs/`; tests.
- Performance: smoke and fire particles capped (two burning wrecks on the Deck preset);
  dented mesh copies capped; Deck benchmark of a pile-up against main.
