# Design: weapons and combat

## Variants carry the tone
A weapon definition is tone-neutral: slot, mechanic, rate, magazine, reload, range, spread.
Everything a player sees or a victim feels is in the variant that `ContentMode.pick_variant`
returns for the active mode:

```json
{"id": "sidearm", "slot": 2, "mechanic": "hitscan", "rate_s": 0.35, "magazine": 12,
 "reload_s": 1.4, "range_m": 60, "spread_deg": 2.0,
 "descriptors": {"violence": "strong"},
 "variants": {
   "fallback": {"name": "Pistol", "impact": "bullet", "lethal": true,
                "descriptors": {"violence": "strong"}},
   "clean":    {"name": "Paint marker", "mechanic": "projectile", "impact": "paint",
                "lethal": false, "descriptors": {"violence": "stylized"}}}}
```

`fallback` is the gritty weapon; `dystopia` inherits it unless a pack adds a variant. A variant
with `lethal: true` is refused when `flag("lethal_weapons")` is false even if its descriptors
pass, so a pack cannot slip a bullet into `clean` by mislabelling it `stylized`. Each `impact`
kind maps to a decal, a sound, a victim reaction and a vehicle effect in `combat_config.json`;
adding an impact kind is a code change, adding a weapon is data.

## Hitscan for guns, bodies for paint
Guns raycast from the camera through the reticle, up to `range_m`, with spread, against world,
traffic bodies, pedestrian bodies and remote players. Paintballs, balloons and foam darts are
pooled `RigidBody3D` spheres with gravity and a 2 s life, launched along the same ray, that call
the same `_on_hit(target, position, normal, impact)` on contact. Melee is a short capsule sweep
in front of the player. One hit path for all three.

Pedestrians and traffic cars only have physics bodies within the body radius of a player, which
is the same reach a shot needs; a hit beyond that reach is rare and is resolved by the host
against the agent nearest the hit position, as `hit_near` already does for car hits.

Since `add-pedestrians` (addendum 2026-10-04): walking pedestrians sit on physics layer 3, so
shot rays and projectiles must include it in their mask. A lethal impact goes to
`PedestrianManager.knock_down(agent, impulse, point)`, which starts the ragdoll fall with the
impulse on the nearest bone. Pool meshes use `INSTANCE_CUSTOM.xy` for the walk cycle, which
leaves `.zw` for paint. A downed player can fall with the same `CharacterRagdoll`
(`game/actors/character/`): `begin`, then `apply_impulse` at the hit point.

## Reactions
- Pedestrians gain `FLEEING` between `WALKING` and `HIT`: speed 3.2 m/s away from the threat
  along the ribbon for `flee_s`, then back to walking. `DOWN` is reached from a lethal impact
  through the existing `HIT` physics window. A non-lethal impact writes a splat colour into the
  MultiMesh custom data so the paint shows on the body.
- Traffic agents gain `damage` 0..1; the body shader tints by damage and impact kind. Above
  `disable_damage` the car becomes `resting`. A shot tyre (lethal only) pulls the agent to a
  stop over a second.
- Players: health 100, `down_s` 4, respawn at the spawn transform. Non-lethal hits paint the
  character's body colour slots and nothing else.

## Decal budget
A pool of `Decal` nodes sized per preset (48 `deck`, 160 `high`), oldest recycled, none on
MultiMesh instances (cars and people are tinted instead). Decals are 0.1 m to 0.4 m, no normal
maps on `deck`. A mode switch clears the pool so no gore survives into `clean`.

## Networking
`report_shot(kind_id, position, normal, impact, target_kind)` unreliable to the host; the host
applies damage and the result rides the next snapshot, which gains one float per agent for state
and tint. `shot_fired(peer, origin, direction, impact)` is broadcast unreliable to peers within
`replicate_radius_m` for flash, sound and decals. Player damage: `report_player_hit(victim_peer,
amount)` to the host, host sends `take_damage(amount)` to the victim, who owns its own death and
respawn. Projectile bodies exist only on the shooter; peers see the impact, not the ball.

## Content policy
Generic weapon names only (pistol, SMG, shotgun), no manufacturer names, no real models. The
clean set is toys; the gritty set is the mature content the policy allows.
