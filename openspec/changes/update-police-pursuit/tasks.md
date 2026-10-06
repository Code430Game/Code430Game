## 1. Read the chase
- [ ] 1.1 `Wanted` exposes who sees the player (helicopter, ground units) and the hidden progress (`unseen_s / lose_s[stars]`); tests at each star level
- [ ] 1.2 Seen badge beside the stars: solid eye with who-has-you marks while seen, blinking hollow eye with a filling ring while hidden, hidden while not wanted; accent colour; tests on the states and the ring
- [ ] 1.3 Minimap: police markers solid while that unit sees the player, hollow otherwise; the helicopter's ring dashed while it searches; tests on the marker states

## 2. Escape the helicopter
- [ ] 2.1 Helicopter tunables to `police_config.json`; speed 35 m/s by default; lost in the open beyond sight range for `lost_s`; tests (a car at a fast car's speed in a straight line gets away; one standing still in the open does not)
- [ ] 2.2 Dense tree canopy blocks the helicopter's sight (a canopy query, not physics bodies); street-tree rows don't; tests

## 3. Patrol cars
- [ ] 3.1 A patrol car whose officer is out parks (handbrake, no steering) until the officer is back or the chase ends; test that it doesn't move when the player drives off

## 4. Check
- [ ] 4.1 Mac screenshots: the badge seen (helicopter, ground units), hidden mid-ring, and the minimap marker states; day and night
- [ ] 4.2 Deck benchmark: no change while not wanted; a 3-star chase within budget
- [ ] 4.3 Human plays a chase on the Deck by day and by night and says whether the badge reads, whether hiding and outrunning feel fair, and whether a daytime helicopter cue is still needed
