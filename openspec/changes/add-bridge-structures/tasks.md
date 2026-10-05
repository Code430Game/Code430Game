## 1. Importer
- [x] 1.1 Fetch `man_made=bridge` outlines; `bridges.py` groups bridge edges (shared nodes, parallel carriageways within the merge gap, outlines first) into bridges with span, level, kind and ends; tests on fixtures: a two-way overpass, a divided highway, a canal bridge with an outline, a footbridge
- [x] 1.2 Walkways: mark the pedestrian ways that belong to a bridge and give them the deck's heights; sidewalk tags on bridge roads become deck walkways; ground sidewalks never join a deck; tests (including the 5 walkways found under decks in the survey)
- [x] 1.3 `bridges.v0.json` and schema; `pack_tools` validates it; Ottawa pack re-exported with the bridge and walkway counts noted here
  - 2026-10-05 Ottawa re-export: 33 bridges from 62 bridge edges (16 over a road, 10 over water, 4 over ground, 3 footbridges), including the Alexandra, Mackenzie King, Portage, Queensway, Booth Street, Plaza and Laurier bridges by their outline names; 55 walkways on decks, 12 of them lifted onto the deck (all 5 found under decks in the survey); 98 piers placed, 7 left out for want of a clear spot; 95 abutment ends. The bbox has no `man_made=bridge` relations, only ways

## 2. Game
- [ ] 2.1 `bridge_builder.gd`: deck slab, soffit, fascia; part of the NEAR tier and collision; tests that a ray from below hits the soffit and a ray from above still hits the road at its height
- [ ] 2.2 Piers clear of the roads and sidewalks underneath, columns over water; abutments; terrain clamp under decks; tests (no pier within 1.5 m of a ribbon underneath; terrain below the soffit by the clearance)
- [ ] 2.3 Deck walkways drawn at deck height with the parapet outside them; the under-road keeps its own sidewalks; tests
- [ ] 2.4 Mac screenshots from under the 417 at Metcalfe, a canal crossing and a footbridge, before and after

## 3. Verification
- [ ] 3.1 Deck benchmark on the usual route against main, idle Deck
- [ ] 3.2 **Stop: human drives under the 417 and over a canal bridge, and walks a bridge walkway, on the Deck**
