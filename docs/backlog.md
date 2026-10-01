# Backlog: field reports from Deck drives

Things seen while driving that are not yet an OpenSpec change. Newest first.
Each entry names the place (local x,z where known) so a fresh session can go straight there.

## 2026-09-30

- **Physics budget.** After the profiling pass the Deck physics tick is about 6.4 ms with 150
  cars and 75 to 115 people: traffic scripts 2 ms, pedestrians 0.7 ms, the rest is the Jolt step
  (24 pooled car bodies, 16 people bodies, chunk collision). Next levers if it creeps again:
  smaller body pools, let far kinematic bodies sleep, and collision shapes spread over frames
  on chunk adds (the remaining 25 ms spikes).

- **Traffic cars are ghosts and pile up.** Addressed by `add-traffic-interaction` (traffic
  keeps headway from player bodies, hit cars queue and recover, taking a traffic car with Y).
  The ghosting came from the 24-body pool running dry: hit cars kept their bodies until the
  player was 380 m away. Awaiting the Deck drive gate.
- **Rideau Street by the Rideau Centre.** Bus-lane ways may be producing odd ribbons or lane
  counts; check `lanes:bus`, `busway=*` and `psv` tags in that stretch.
- **Off-ramp at the old default spawn.** That stub is the import bounding box cutting the 417
  and the Bronson ramp (x -530, z 1666); the spawn moved mid-district. Ramp geometry itself
  is handled by `add-fork-geometry`. Open: a clean map-edge treatment for cut roads.
- **Rideau to Wellington past Sussex, turning south: one roadway over another, drivable
  into.** A scan of the whole district found no pair of non-bridge roads crossing in 2D
  without a shared junction, and the Colonel By / Mackenzie loop by the Chateau Laurier
  (around x 185, z -505) looks sane from above. Needs the HUD x,z from the Deck to find
  the exact spot; suspect a steep grade difference between adjacent carriageways leaving
  a terrain step between them.
- **Pedestrian underpasses and tunnels.** 100 covered or tunnel pedestrian ways import as
  `covered` and are not drawn: the multi-use path under the Portage approaches (x -1430,
  z -195), the footway tunnel under Rideau Street beside the Chateau Laurier (OSM way
  362678275, x 106..116, z -576..-561; the one people shelter in), Canal Lane under Plaza
  Bridge, the Rideau LRT mezzanine. Future change: dig the passage (box through terrain or
  road), portal and interior meshes, lighting, and a sheltering population for them
  (homelessness is in scope for the base game; the sanitized tone mode would drop it).
- Parking aisles and driveways are still dropped by the importer (earlier round).
