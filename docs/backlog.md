# Backlog: field reports from Deck drives

Things seen while driving that are not yet an OpenSpec change. Newest first.
Each entry names the place (local x,z where known) so a fresh session can go straight there.

## 2026-09-30

- **Traffic cars are ghosts and pile up.** Player walks through traffic bodies, traffic drives
  through the player, and stopped cars stack 6+ deep with no way out. Wanted: real collision
  with the player (on foot and in the car), traffic that queues behind a stopped car instead
  of piling into it, and the ability to take a traffic car. Next traffic round.
- **Rideau Street by the Rideau Centre.** Bus-lane ways may be producing odd ribbons or lane
  counts; check `lanes:bus`, `busway=*` and `psv` tags in that stretch.
- **Off-ramp at the default spawn.** Two-lane off-ramp leaves the 417 in front of the start
  position without a merge taper; traffic behaves badly there. Consider a merge/taper rule
  for `_link` edges joining wider roads (relates to the intersection taper follow-up).
- **Rideau to Wellington past Sussex, turning south: one roadway over another, drivable
  into.** A scan of the whole district found no pair of non-bridge roads crossing in 2D
  without a shared junction, and the Colonel By / Mackenzie loop by the Chateau Laurier
  (around x 185, z -505) looks sane from above. Needs the HUD x,z from the Deck to find
  the exact spot; suspect a steep grade difference between adjacent carriageways leaving
  a terrain step between them.
- **Covered multi-use path under the Portage approaches** (about x -1430, z -195) now
  imports as `covered` and is not drawn; a real tunnel portal and passage are future work.
- Parking aisles and driveways are still dropped by the importer (earlier round).
