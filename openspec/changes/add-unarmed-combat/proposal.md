# Change: Punching and kicking

**Status: proposed 2026-10-06 from the backlog (human, 2026-10-05: "another could be punching and kicking. Or that could be a different ticket").**

## Why
Empty hands are a slot in the weapon cycle (LB / Tab) that does nothing. Fists and a kick
fill it, give the clean tone a scuffle without paint, and reuse the held-weapon arm poses.

## What Changes
- **Slot 0 gets moves.** Fire is a punch, alternating hands. Holding fire for 0.4 s and
  releasing is a kick with more reach and push.
- **Poses.** Punches use `CharacterRig.bone_override` like `HeldWeapon` (a jab on either
  arm). The kick adds a leg override (`thigh_r`, `shin_r`) to the rig.
- **Hits** go through `Shooter.hit()` with a new impact kind `fist` in `combat_config.json`.
  - gritty and dystopia: a walker is knocked down by the third punch in a short window, or
    by one kick;
  - clean: a shove that makes them stumble and run off, never a knock-down.
  Punching counts as `assault` for the wanted level; a knock-down counts as `assault_down`.
- **Officers** answer a player on foot with fists only when they have no tone weapon allowed.
- **Not in this change:** blocking, combos past three, grappling, melee against cars.

## Impact
- Affected specs: `combat` (ADDED: Unarmed Moves).
- Affected code: `game/actors/combat/shooter.gd` (slot 0), `held_weapon.gd` (arm poses with no
  model), `game/actors/character/character_rig.gd` (leg override), `combat_config.json`,
  `docs/pack-format/weapons.schema.v0.json` (impact `fist`); tests.
- Builds on `add-weapons-and-combat` 2.6 (held weapons). No dependency on other open changes.
