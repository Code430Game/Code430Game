## 1. Hitting officers
- [x] 1.1 Officer capsule body on a `police` layer; `Shooter.hit()` (rays, paintballs, melee sweep, fists) routes to `PoliceManager.hit_officer()`; tests that each weapon kind reaches an officer and that shots still hit pedestrians and walls
  - 2026-10-06: `OfficerBody` (an `AnimatableBody3D` on physics layer 4, value 8, with an empty mask) rides on each officer, so the player and cars still pass through officers as before. `Shooter.hit()` hands an `OfficerBody` to `PoliceManager.hit_officer()`, and the melee sweep picks officers in the fight as well as walkers.
  - Found on the way: paintballs only had the world in their mask, so they could never land on a walker either. Their mask is now world + pedestrians + police.
  - Tests in `test_police_combat.gd`: a ray finds the body and the hit reaches the police; the sweep's shape query finds officers; the ball mask; an officer out of the fight can't be hit again. The pedestrian and wall paths are still covered by `test_weapons` and `test_unarmed_combat`.
- [x] 1.2 Toughness per impact in `police_config.json`; `outcomes.officer` in the mode files and schema; reactions: stagger, knock-down through `CharacterRagdoll` (gritty and dystopia), tag-out and sit with hands up then walk back (clean); fists by the unarmed rules; tests in every tone
  - 2026-10-06: `officer_combat` sets toughness 100. Damage per hit: bullet 40, energy 50, blade 50, paint 25, fist 34, kick 100. Toughness comes back after 3 s without hits.
  - Hits to finish an officer:

    | tone | weapon | hits |
    |---|---|---|
    | gritty | pistol | 3 |
    | dystopia | blaster | 2 |
    | clean | paintball gun | 4 |
    | violence allowed | punches in a streak | 3 |
    | violence allowed | kick | 1 |

  - `outcomes.officer` is `knock_down` in gritty and dystopia and `tag_out` in clean. It's in the tone-mode schema, so that v0 schema gains a key. `PoliceManager.outcome()` also refuses a knock-down where `violence` is off, whatever the data says.
  - Reactions:
    - stagger: the officer leans back with arms out for 0.5 s, then takes cover;
    - down: a `CharacterRagdoll` on the officer node that settles after 3 s and stays until the chase ends;
    - tagged out: the officer sits (rig lowered by 0.72 × height, thighs level, shins out) with hands overhead for 8 s, then walks back to the car at half speed and gets in.
  - Blood only for a lethal knock-down where `allows("gore")`. Paint lands on the ground by a painted officer.
- [x] 1.3 A testbed flag for screenshots: `--officer=stagger|down|tagged` puts an officer 5 m ahead of the player and hits them with the tone's gun into that state (`PoliceManager.demo_officer`)

## 2. Heat and backup
- [x] 2.1 `assault_officer` (one star at once, always seen) and `officer_down` (another star); a downed or tagged-out officer stops seeing the player; tests
  - 2026-10-06: `Wanted.report(kind, pos, seen)` skips the witness check when the police saw it themselves. Officers out of the fight move to `PoliceManager.downed`, off the list that moves, sees, busts and shows on the minimap, so the seen badge follows.
  - Tests: three pistol hits on an unwatched officer go from 0 to 3 stars; a downed officer no longer counts as seeing and drops off the minimap.
- [x] 2.2 Backup toward a downed officer from the nearest graph point, officers ready to get out; a hit officer takes cover by their car for a while; tests
  - 2026-10-06: each officer down or tagged out spawns one patrol car, allowed `backup_extra` (1) over `max_police`. It comes from the usual spawn ring around the scene, not the player, and is marked `backup_to`. Within `backup_arrive_m` (15 m) it lets its officer out at once, then chases the player as usual.
  - A hit officer shelters 2 m beyond their car on the side away from the player for 3 s, still firing; they stand still and hold fire only while staggering.
  - Tests: backup's target and spawn distance; backup letting its officer out at the scene; the cover point and the walk to it; no moving or firing while staggered.

## 3. Check
- [x] 3.1 Mac screenshots: an officer staggering, down (gritty) and tagged out (clean)
  - 2026-10-06, with a fixed side camera:
    - stagger: the body leaning back with the head tipped. The first try leaned forward because the spine's sign was wrong; fixed.
    - down: a ragdoll flat on the road; the HUD goes to three stars with the helicopter mark, and backup shows on the minimap.
    - tagged out: sitting on the road with both hands up.
- [ ] 3.2 Deck benchmark: a 3-star firefight within budget
  - Mac, deck preset, 40 s autodrive:

    | run | render CPU | physics mean |
    |---|---|---|
    | normal route | 0.43 ms | 4.07 ms |
    | `--wanted=3` | 0.47 ms | 5.26 ms |

    That's in line with today's main (render about 0.4–0.5 ms, physics about 4–5 ms).
- [ ] 3.3 Human fights the police on the Deck in clean and gritty and says whether it's fun and fair
