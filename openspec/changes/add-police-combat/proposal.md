# Change: Fighting the police

**Status: proposed 2026-10-06 (human, Deck session: "I don't think I can shoot them to get away… so… but that was fun"; chosen as the next feature the same evening).**

## Why
Officers chase, arrest and fire at the player, but nothing the player does reaches them:
- they are a plain `Node3D` with a `CharacterRig` and no collider (`police_manager.gd:355`);
- `Shooter.hit()` only knows pedestrians.

So shots pass through officers, and the only answers to a chase are running and hiding. A
crime sandbox needs fighting back as a choice, with a price: more heat.

## What Changes
- **Officers can be hit.**
  - Each officer gets a capsule body on a `police` collision layer, which the Shooter's rays,
    paintballs, melee sweep and fists already query.
  - `Shooter.hit()` routes an officer to a new `PoliceManager.hit_officer()`.
- **Officers take hits by tone.** Each officer has toughness (hits to go down, per weapon
  impact) in `police_config.json`. Reactions come from mode data (`outcomes.officer` in
  `core/content/modes/*.json`, read through `ContentMode`, the same pattern as
  `outcomes.ambulance`), not mode ids.
  - **gritty and dystopia:** a hit staggers the officer; enough hits knock them down through
    `CharacterRagdoll`, the same as pedestrians. A downed officer stays down until the chase
    ends, then is collected with their car. A blood mark only where `allows("gore")`.
  - **clean:** paint and the net. Enough paint "tags out" an officer: they sit on the kerb
    with their hands up for a configured time, then walk back to their car. Never a
    knock-down.
  - **Fists** use the unarmed rules: a streak or a kick floors an officer in gritty and
    dystopia; in clean it's a shove.
- **Heat.**
  - Hitting an officer reports `assault_officer`: it always counts (the officer sees it),
    adds one star at once and never lowers.
  - Downing or tagging out an officer reports `officer_down`: another star, up to the
    maximum.
  - A downed officer can't see the player; the seen badge from `update-police-pursuit`
    follows.
- **Backup.** When an officer goes down or is tagged out, the next patrol car comes from the
  nearest point on the road graph toward that spot, not from the usual spawn ring, and its
  officers get out ready. The helicopter's rules don't change.
- **Officers fight smarter only a little:** an officer who was hit takes cover behind their
  car door (stays by the car) for a short time before advancing again. Tunable.
- **Not in this change:**
  - damage to patrol cars, or shot tyres;
  - SWAT, roadblocks or armour;
  - the player's armour;
  - a kill count or an economy.

## Co-op authority
Host-authoritative, like `add-police`:
- officers, their toughness and their reactions run on the host;
- a guest's hits on officers stay local in this pass, the same as their hits on pedestrians
  today. The follow-up is the shared `report_shot` path through `WorldSync`, planned in
  `add-weapons-and-combat`.

## Tone
- Reactions come from `outcomes.officer` in the mode data.
- Clean never knocks an officer down and never shows blood.
- Officers keep the tone weapons they already have: the net in clean, the pistol in gritty,
  the blaster in dystopia.

## Impact
- Affected specs: `police` (ADDED: Fighting The Police).
- Affected code:
  - `game/actors/police/police_manager.gd` (officer body, `hit_officer`, toughness,
    reactions, backup, taking cover);
  - `police_config.json`;
  - `game/actors/combat/shooter.gd` (routing hits to officers; melee and fists reach
    officers);
  - `game/actors/police/wanted.gd` (`assault_officer`, `officer_down`);
  - `game/core/content/modes/*.json` and `docs/pack-format/tone-mode.schema.v0.json`
    (`outcomes.officer`);
  - `game/scenes/play_testbed.gd` (crime wiring; small);
  - tests.
- Performance: one capsule per officer (at most a few on screen) and no per-frame work beyond
  the existing officer update.
