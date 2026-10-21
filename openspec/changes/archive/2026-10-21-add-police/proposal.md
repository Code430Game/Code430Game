# Change: Police (wanted level, pursuit, busted)

**Status: proposed 2026-10-05 (human: "Do the simple weapons and then add the police!"; on clean: "sticky bullets to stick you to the floor or a net gun for the police on pg — but then again is there crime in the pg one?").**

## Why
Weapons and car theft now exist but nothing answers them. Police are the GTA loop: you do
something, the city notices, someone comes for you, and you escape or get caught. The tone
system decides how that feels: a slapstick chase in `clean`, a manhunt in `gritty`.

## What Changes
- **Crimes and witnesses.** A crime raises the wanted level only when an officer or a
  bystander walker within `witness_m` sees it:
  - hitting a person with a car, or with a weapon (+1, +2 if they go down)
  - firing a gun (+1)
  - taking a traffic or parked car (+1, only if police see it)
  - hitting a police car (+1)
  - in `clean`, paint-tagging people, swiping cars and ramming count as mischief, at the
    same values
- **Wanted level.** 0 to 3 stars, shown on the HUD. Each star has a search radius. With no
  officer seeing you for `lose_s` (shorter at fewer stars), the level drops a star; zero
  ends the chase.
- **Police cars.** A `police` catalogue vehicle (sedan body, police livery, a light bar that
  flashes red and blue, a synthesised siren). With a wanted level, `police_per_star` cars
  spawn out of view on lanes near the player and chase. They drive toward the player along
  the road graph, cutting straight across when close, ram and box in at 2+ stars, and are
  taken back out of view when the level clears.
- **Officers.** When the player is on foot within 25 m of a stopped police car, officers get
  out and run at them. The officer's weapon comes from the tone, as weapons do:

  | tone | officer weapon | effect on the player |
  |---|---|---|
  | clean | net gun | stuck in place for 3 s, can't move or shoot |
  | gritty | pistol, at 3 stars | damage |
  | dystopia | blaster, at 3 stars | damage |

- **Busted and wasted.**
  - Stopped (a car under 2 km/h boxed in by police, or on foot) with an officer within 3 m
    for 2 s: busted. A fade, a fine message, wanted cleared, respawn at the spawn point.
  - In lethal modes, the player gets health (100, from police fire and hard crashes). Zero
    is "wasted": a fade, then the same respawn.
  - `clean` never wastes; the net gun only sticks.
- **Not in this change:** police stations and jail, bribes, helicopters, roadblocks,
  pursuit music, co-op wanted levels (host-local in this pass), fines as an economy.

## Co-op authority
First pass: the wanted level, police cars and officers run on the host for the host's player;
guests are not pursued yet (follow-up: a wanted level per peer, police in the snapshots).

## Tone
Officer weapons and the busted/wasted wording come from tone variants. No mode ids appear in
gameplay code: the net gun is the `clean` variant of the officer weapon, as the paint brush
is for the knife.

## Impact
- Affected specs: `police` (new).
- Affected code: `game/actors/police/` (new: `wanted.gd`, `police_manager.gd`,
  `police_car.gd`, `officer.gd`, `police_config.json`), `vehicles.v0.json` (police entry and
  livery), `VehicleMesh` (light bar), `Synth` (siren), `weapons.v0.json` (officer weapon with
  a net gun variant), the testbed (HUD stars, busted and wasted flow, player health), tests.
- Performance: a cap of 4 police cars and 4 officers; Deck benchmark during a 3-star chase.
