## 1. Importer
- [x] 1.1 Fetch entrance nodes and underground parking points (already in the query) and cluster them into garages; footprint from an outline, then a served building, then capacity; tests on fixtures (named cluster, building footprint, bare entrance)
- [x] 1.2 Tier per garage (door, or garage for public and overridden ones); garage level, ramps from each entrance on its driveway node, terrain holes for the ramp cut; export, schema and `pack_tools`; Ottawa re-export with the garage count and the NAC and Museum of Nature garages noted here
  - 2026-10-05 Ottawa re-export: 99 entrances on the road graph make 92 garages, 16 at the garage tier and 76 at the door tier. Open garages include the NAC (3 entrances, capacity 200, under the NAC footprint), the Victoria Memorial Museum Building (by override; its entrance is 25.3 m from the footprint, so the building reach is 30 m), World Exchange (500), City Hall P1 and P2, the National Gallery, Rideau Centre, Minto Place, Dalhousie and Portage II. Ramps and floors are exported; the terrain cut for each ramp is made by the game from the ramp strip (2.0/2.1), as for underpasses

## 2. Game
- [ ] 2.0 Door portals at every entrance: ramp, roll-up door, portal, collision; tests (a driveway reaches the door with no terrain wall)
- [ ] 2.1 Garage box: floor, ceiling, walls, columns on the grid, lights; ramps through the underpass builder; NEAR tier and collision; tests (drive from the street down the ramp onto the floor with no step; the terrain hole matches the ramp)
- [ ] 2.2 Stalls and parked cars in garages with the `garage` occupancy; take a garage car; tests
- [ ] 2.3 Garages on the maps; Mac screenshots driving into the NAC garage and the museum garage

## 3. Verification
- [ ] 3.1 Deck benchmark against main, including a drive into a garage
- [ ] 3.2 Human tries it on the Deck (not a merge gate; feedback goes to the backlog)
