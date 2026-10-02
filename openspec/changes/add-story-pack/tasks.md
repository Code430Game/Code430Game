## 1. Format
- [ ] 1.1 `mission.schema.v1.json`, README section; validator: schema, generic descriptor and variant checks, positions inside the dependency map's bbox; tests
- [ ] 1.2 `packs/code430-story-first-ride`: manifest (v1, story section, dependency on the Ottawa pack, `supported_modes` all three), "First Ride" with clean, gritty and dystopia variants; validator green

## 2. Runner
- [ ] 2.1 `mission.gd`: parse a definition, pick the variant, step evaluators with unit tests on a fake world (positions, driving, timer, deadline, abandonment)
- [ ] 2.2 `mission_runner.gd`: registry load, giver placement with `PlacedCharacter`, interact and dialogue, HUD line and countdown, success and failure, re-offer; `--mission=` flag; tests
- [ ] 2.3 Markers: map renderer overlay, minimap edge-clamped ring, overview map ring, world beam; tests on the clamping maths
- [ ] 2.4 Co-op: host-owned state, reliable `mission_state`, `mission_interact`, holder-leaves fails; test with two sessions in the existing coop test harness

## 3. Verification
- [ ] 3.1 Mac screenshots: giver in the Market, dialogue box, beam over the drop-off, minimap ring; the same mission in all three tones
- [ ] 3.2 Deck: package, deploy, benchmark unchanged; deadline checked with `--autodrive`
- [ ] 3.3 **Stop: human plays First Ride end to end on the Deck, then once more in `clean`**
