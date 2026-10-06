## 1. Ambulances
- [x] 1.1 `downed` signal from the pedestrian manager; calls with merge, queue and the two-ambulance cap; hold the body while a call is open; tests
- [x] 1.2 Ambulance body (catalogue entry, light bar, siren), dispatch from the nearest post or hospital, routing; tests
- [x] 1.3 On scene: paramedics, the result by tone, return and free; minimap cross; tests

Notes from building it (2026-10-05):
- Routing moved to a shared `RoadRoute` (police use it too). A point snaps to the road at its own height first, so someone under a deck is reached from the road below.
- An ambulance leaves its base 20 m down the road (a base's road node is often its own driveway) and never starts on top of another one. It backs out when it stalls, creeps when a car or person is right ahead, and parks and walks over when the person is within 45 m but the road goes the long way round.
- Traffic stops for ambulances like a player's car. Walkers don't step onto a crossing an ambulance on a call is heading for.
- Found on the way: a car told to brake at a standstill reverses. A new `override_hold` puts the handbrake on, and police cars pulling up beside a player on foot now use it too (they were backing away). Police cars were also drawn in the default red; they now get the catalogue's white.
- Ramming the ambulance with the player's car is an offence ("assault"). Paramedics have no bodies yet, so hitting them is not.
- Co-op: ambulances run on the host only for now, like the police.

## 2. Verification
- [x] 2.1 Deck benchmark with two calls open (2026-10-05, idle Deck, deck preset, standing at the start: `--knockdown-every=8` kept two ambulances out, avg 14.16 ms, p99 18.53, physics mean 12.33 ms, max frame 80 ms; the same run without knockdowns, so no ambulances, was avg 13.20, p99 16.67, physics 10.43. The difference includes the ragdolls from the knockdowns.)
- [ ] 2.2 Human knocks someone down on the Deck and watches the ambulance arrive
