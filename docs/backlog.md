# Backlog: field reports from Deck drives

Things seen while driving that are not yet an OpenSpec change. Newest first.
Each entry names the place (local x,z where known) so a fresh session can go straight there.

## 2026-10-02

- **Proposal slate (human asked 2026-10-02: write proposals so other agents can work in parallel).**
  Nine changes scaffolded and validated, none approved yet: `add-rail`, `add-district-edge`,
  `add-underpass-interiors`, `add-weapons-and-combat` (paintball in clean, bullets in gritty),
  `add-car-radio` (chip music synthesised in-engine, stations as tagged pack data),
  `add-bus-routes`, `add-pack-loader` (pack format v1, needs the human's yes), `add-story-pack`
  (depends on the loader), `add-character-features`. Decisions each proposal leaves to the
  human are listed in its proposal or design. Groups that can run at the same time without
  touching the same files: rail / district edge / underpass interiors; combat / radio / bus
  routes; pack loader then story pack / character features. Rail and bus routes both add
  importer stages; land one before the other.
- **Region picker** is built (`tools/region_picker/index.html`, importer `--region`); the two
  older region picker notes below are done except `--place` and `--radius-km`.

- **Rail (human asked 2026-10-02).** OSM maps rail as `railway=*` ways (light_rail, subway, rail, tram) with stations; the importer only queries `highway=*`. The Confederation Line runs in a tunnel under Queen Street downtown (Lyon, Parliament, Rideau stations) and surfaces east of uOttawa and west of Pimisi. A rail round would fetch railway ways, build track ribbons and the surface stations, and run trains on a timetable. Albert and Slater lost their bus lanes when the line opened in 2019, which is why OSM has them plain.
- **Buses** built (add-buses): bus-only streets kept, reserved lanes painted red, buses with stops. Routes, timetables and shelters remain. Only Lyon Street North, the Transitway and one Waller Street lane are tagged in OSM; Albert and Slater have no bus-lane tags in the extract.

## 2026-10-01

- **Character detail (human, 2026-10-01: "would love to see improved detail").** Next creator round: rounded head and limbs, separate forearms and shins with a walk cycle, more hair styles, beards, glasses, jackets over tops, and the same body on pedestrians.
- **Testbed sometimes starts on foot despite `--drive`** on Mac screenshot runs (seen 2026-10-01, roughly one run in three; the Deck build is unaffected). Suspect a race between the spawn-in-car and the first collision frame. Unfixed.
- **Visibility ranges on city-wide MultiMeshes** are measured to the bounding box centre; removed from signal heads and billboards. Any future city-wide MultiMesh must be chunked or range-free.
- **Character creator plan (from the human).** First start spawns a randomised character so
  nothing blocks play; the creator then tweaks that body's features; presets are saved,
  including "last created". The creator is a later change; this is its brief.
- **Region picker plan.** A local Leaflet page under `tools/region_picker/` (no server): drag a
  rectangle, see km², UTM zone, elevation coverage (HRDEM or worldwide fallback) and a live
  Overpass building count; copy the import command or save `regions/<name>.json` for `--region`.

- **Region picker.** The Ottawa bbox is not quite the area wanted. Before importing a
  friend's region, build a small visual picker (a local HTML page over OpenStreetMap tiles,
  or Overpass Turbo's bbox export) that shows the exact rectangle and prints the import
  command; also pick the UTM zone from the bbox centre and a DEM source outside HRDEM cover
  (Copernicus GLO-30, else flat). Importer pieces: `--place`, `--radius-km`, `--dem auto`.

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
  is handled by `add-fork-geometry`. Cut roads now end in an orange roadblock across their
  width (importer kind `roadblock`, 108 in Ottawa); a subtler end-of-district marker is future.
- **Rideau to Wellington past Sussex, turning south: one roadway over another, drivable
  into.** A scan of the whole district found no pair of non-bridge roads crossing in 2D
  without a shared junction, and the Colonel By / Mackenzie loop by the Chateau Laurier
  (around x 185, z -505) looks sane from above. Needs the HUD x,z from the Deck to find
  the exact spot; suspect a steep grade difference between adjacent carriageways leaving
  a terrain step between them.
- **Pedestrian underpasses and tunnels** (first pass built 2026-10-01, add-underpasses: 19 dug,
  19 opened; lighting inside, trench retaining walls and the sheltering population remain). Original note: 100 covered or tunnel pedestrian ways import as
  `covered` and are not drawn: the multi-use path under the Portage approaches (x -1430,
  z -195), the footway tunnel under Rideau Street beside the Chateau Laurier (OSM way
  362678275, x 106..116, z -576..-561; the one people shelter in), Canal Lane under Plaza
  Bridge, the Rideau LRT mezzanine. Future change: dig the passage (box through terrain or
  road), portal and interior meshes, lighting, and a sheltering population for them
  (homelessness is in scope for the base game; the sanitized tone mode would drop it).
- Parking aisles and driveways are still dropped by the importer (earlier round).
