## 1. The helicopter on its pad
- [ ] 1.1 The police helicopter parks on its helipad when idle and after landing (no longer freed); lifts off from it when called; the legend's helipad entry says it's there; tests

## 2. Flying
- [ ] 2.1 `FlyableHelicopter`: arcade flight (stick moves with bank and pitch, climb and descend, turn, hold and level when let go, top speed, ceiling, soft district boundary), tunables in `helicopter_flight.json`; tests on the flight maths (holds when let go, top speed, ceiling, boundary)
- [ ] 2.2 `fly` controls context (pad and keyboard), Controls tab and `docs/controls.md` regenerated; get in at the pad (Y / E); get out only landed or within 2 m ("Land first" hint); tests
- [ ] 2.3 Landing on flat solid surfaces (ground, decks, roofs); a parked stolen helicopter stays put; collisions by tone from `outcomes.aircraft` (damage and auto-rotate down to disabled in gritty and dystopia; bounce and gentle auto-land in clean); tests in every tone
- [ ] 2.4 Camera (aircraft chase mode), altitude on the HUD, streamer look-ahead by speed and height (capped on deck); tests on the anchor look-ahead

## 3. Police and co-op
- [ ] 3.1 `aircraft_theft` (two stars, always seen); no police air unit while the player has it; a new one back at the pad after the configured time; ground units' aircraft sight range; tests
- [ ] 3.2 Co-op: the pilot owns the body through the vehicle sync; the host owns it parked or under AI; the pilot leaving parks or auto-lands it; tests

## 4. Check
- [ ] 4.1 Mac screenshots: parked on the pad, lifting off, over downtown, landed on a roof
- [ ] 4.2 Deck benchmark flying over downtown
- [ ] 4.3 Human steals and flies it on the Deck and says how it handles
