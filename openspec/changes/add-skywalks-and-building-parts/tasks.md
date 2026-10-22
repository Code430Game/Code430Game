## 1. Importer
- [ ] 1.1 Pedestrian ways keep `bridge`, `layer`, `covered`; footbridge heights from the bridge rule with ramps; schema; tests on a fixture footbridge over a road and over water
- [ ] 1.2 Buildings export `min_height_m`, `bridge`, `spans_road`, `clearance_y`; schema; tests on a min_level part and on a footprint spanning a sunken road; golden files re-baked; Ottawa pack re-exported (counts of footbridges, raised parts and spanning buildings in the validation report)

## 2. Game
- [ ] 2.1 `building_builder.gd`: raised parts with undersides, spanning buildings with a clearance opening and collision; tests
- [ ] 2.2 Footbridge ribbons with deck, parapets, optional roof strip, collision; tests
- [ ] 2.3 Mac screenshots: Place du Centre over Maisonneuve from the road, NAC over Freiman Lane, a canal footbridge, Place du Portage skywalks

## 3. Verification
- [ ] 3.1 Deck benchmark on the usual route and a drive under Place du Centre; no regression
- [ ] 3.2 **Stop: human drives Boulevard Maisonneuve under Place du Centre and walks a footbridge on the Deck**
  - 2026-10-22 Deck, on the Mackenzie King Bridge (human): "now i remember the complexity because the building has two levels and there are entrances at bridge level". The Rideau Centre meets the bridge deck at its upper level: entrances at bridge height as well as at street level.
