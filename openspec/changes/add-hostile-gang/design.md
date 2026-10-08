# Design: a hostile gang

## Data shapes
- `factions.v0.json`: `[{id, name, descriptors{}, variants{clean, gritty, dystopia, fallback},
  look{palette, garments}, car{catalogue_id, livery}, group_size, aggression, sight_m,
  warning_s, flee_health, respawn_s, heat{rise_per_s, fall_per_s, out_of_turf_s}}]`.
  A variant names the melee and ranged weapon ids from `weapons.v0.json` and a `tag` word for
  the shout. The validator checks descriptors against the modes and refuses a lethal weapon
  in a variant keyed to a mode whose flag is off, as it does for weapons.
- `turf.v0.json`: `[{faction, name, ring: [[x, z], ...], centre: [x, z]}]`. The proving
  ground's generator writes it; Ottawa gets one through `overrides.json` (a new `turf` key)
  so the importer copies it into the pack.

## Members are pedestrians
- A member is a `Pedestrian` with `faction >= 0` and a threat state; the manager spawns them
  only inside turf, from the faction's look, with a weapon in hand drawn from the held-weapon
  code the player uses. Pools and LODs are shared; the snapshot gains one float (faction and
  state packed), and `apply_snapshot` sets the look and pose.
- Melee and ranged attacks reuse the officer's fists and fire code (`_officer_fists`,
  the officer weapon file pattern) parameterised by the faction, so one combat path serves
  both; the player's damage and down rules are untouched.

## Threat machine
`patrol -> alert -> attack -> (flee | regroup) -> patrol`, stepped on the host:
- `alert` on sight within `sight_m` and line of sight, in turf only; a warning for
  `warning_s` (a shout from the ambience synth, a raised arm pose) during which leaving the
  turf ends it;
- `attack` after the warning or at once if the player hits a member: the nearest two close
  to melee, the rest hold at range and fire the ranged variant at the officers' rate;
  members never fire across each other (a simple friendly-line check);
- `flee` when the group's standing members are fewer than half, or a member's health is
  under `flee_health`, or officers arrive; run to the turf centre;
- `regroup` at the centre for a few seconds, then `patrol`.
Outside the turf a member only reacts if hit (one `attack` burst, then `regroup`).

## Heat
Per player, host-held: rises while any member sees the player in turf, falls after
`out_of_turf_s` outside, full sends the gang car toward the player once. Shown as a glyph
with a fill ring next to the seen badge; the legend explains it.

## Police
Decided by the human (2026-10-07): "the police can fight the gang, if they see a crime."
Officers never engage members on sight. A member's crime in view of an officer (gunfire,
a melee hit on the player or a bystander, a gang car ramming) calls
`wanted.report(kind, from=member)` with the member as the offender; officers path to that
offender and treat members of the same crew as targets using the existing officer fire and
fists until the crew flees or is down. Out of an officer's view the gang and police ignore
each other. The player in the middle is still wanted only for their own crimes.

## Decisions for the human
- Group size: decided by the human, a crew of six: five members and one leader (the leader
  has more health, carries the ranged variant in gritty and drives the gang car); the cap
  per turf is that crew plus respawns in flight. Aggression (warning 2 s) still open.
- Whether members use guns in gritty (proposed: one in three carries the pistol) or
  knives only.
- (decided) Officers fight the gang only after witnessing a crime; see Police above.
