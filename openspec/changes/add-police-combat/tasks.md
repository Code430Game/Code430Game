## 1. Hitting officers
- [ ] 1.1 Officer capsule body on a `police` layer; `Shooter.hit()` (rays, paintballs, melee sweep, fists) routes to `PoliceManager.hit_officer()`; tests that each weapon kind reaches an officer and that shots still hit pedestrians and walls
- [ ] 1.2 Toughness per impact in `police_config.json`; `outcomes.officer` in the mode files and schema; reactions: stagger, knock-down through `CharacterRagdoll` (gritty and dystopia), tag-out and sit with hands up then walk back (clean); fists by the unarmed rules; tests in every tone

## 2. Heat and backup
- [ ] 2.1 `assault_officer` (one star at once, always seen) and `officer_down` (another star); a downed or tagged-out officer stops seeing the player; tests
- [ ] 2.2 Backup toward a downed officer from the nearest graph point, officers ready to get out; a hit officer takes cover by their car for a while; tests

## 3. Check
- [ ] 3.1 Mac screenshots: an officer staggering, down (gritty) and tagged out (clean)
- [ ] 3.2 Deck benchmark: a 3-star firefight within budget
- [ ] 3.3 Human fights the police on the Deck in clean and gritty and says whether it's fun and fair
