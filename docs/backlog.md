# Backlog: field reports from Deck drives

Things seen while driving that are not yet an OpenSpec change. Newest first.
Each entry names the place (local x,z where known) so a fresh session can go straight there.

## 2026-10-05

- **Punching and kicking** (human, 2026-10-05, while planning weapons: "another could be punching and kicking. Or that could be a different ticket"). Empty hands are already a slot in the weapon cycle; fists and kicks would fill it, with a non-lethal shove in clean.
- **Side-by-side bridge carriageways at different heights** (issue #45, Mackenzie King Bridge at x 517, z -523): the 2-lane way runs about 0.48 m above the 3-lane one where their ribbons touch, so the step shows as a low strip (the deck's side face) between them. The parapets that stood in that gap were removed in the #45 fix. Proper fix: the elevation stage should give touching carriageways of one bridge a shared height, blending into the approaches.

## 2026-10-04

- **Radio per car (human, 2026-10-04, Deck drive for `add-car-radio`).** Today the radio follows
  the player into any car. Idea: the player's own car keeps their chosen station, and a stolen or
  taken car plays whatever station its owner had on (a random one). Not started.

## 2026-10-03

- **Curb inside a junction at a curved road join (human, 2026-10-03, Deck drive for
  `update-cluster-junction-arms`).** A curb stands on the interior of the junction where a
  curved road joins; not the clustered-X issue, which the drive confirmed fixed. Location not
  recorded yet; get x,z from the HUD next time. Likely the barrier importer's curb lines
  (`barriers.py`, `curb_classes`) not being cut back to the junction polygon at curved arms.
- **Grass through road surfaces (human, 2026-10-03).** `update-cluster-junction-arms` fans
  junction surfaces from their node (167 junctions sagging > 5 cm on main, 14 after), but
  terrain can still show through ribbons and the remaining ear-clipped junctions. Fold into a
  small proposal with road surface textures: flatten terrain under junction polygons in the
  importer, not just under edge ribbons.

## 2026-10-02

- **Clustered junctions bend every arm to the centroid (human, Deck shot 2026-10-02 at x 237,
  z 18, Elgin at Nepean).** Both Elgin carriageways and Nepean meet at one point: X-shaped
  ribbons and lines, the same X on the minimap, traffic aiming at the centre. 76 clusters in
  Ottawa. Proposal `update-cluster-junction-arms` (straight arms past the centroid, junction
  builder on real edge ends). Earlier "wonky junctions" reports are probably this.
- **Portage underpass walk (Deck shots 2026-10-02 morning, x -1208 z 141 to x -1176 z 83):**
  a large flat slab and bare headwalls read as floating geometry at the approach; the
  retaining walls and lighting in `add-underpass-interiors` should cover it, worth a look there.
- **Skywalks and raised building parts (human, 2026-10-02: "a connector between buildings,
  more than a car height above the roadway").** Pedestrian ways drop `bridge`/`layer` (about
  60 footbridges drawn at grade); buildings ignore `min_height`/`building:min_level` (about 90
  raised parts become ground blocks); a footprint spanning a sunken road floats on its median
  ground: Place du Centre over Maisonneuve (x -1463, z -825) 10.8 m up, the NAC over Lawrence
  Freiman Lane (x 91, z -411) 9.1 m up. Proposal `add-skywalks-and-building-parts`.
- **Audio polish is a later focused project (human, 2026-10-02: "I'd rather leave this until we
  want to improve the audio across the board").** Sound archived as good. When that project
  comes: engine character per vehicle class, positional traffic audio, horns and sirens,
  pedestrian voices, reverb in underpasses, radio from `add-car-radio`.
- **Junctions that extend out awkwardly (human, Deck 2026-10-02, after fork geometry: "some
  intersections are still odd ... there are some odd ones where it extends out awkwardly").**
  Fork geometry archived; the remaining cases are the merged-junction arms, see
  `update-cluster-junction-arms`. Chunk streaming and car model archived on the same drive.
- **Character body fixes (human, Deck 2026-10-02: jacket looked under the shirt with a tie-like
  strip; shirt stopped short of the neck; long hair covered the eyes; waist too low, "diaper or
  onesie").** Fixed: shirt capsule to the neck ending at the natural waist, trouser pelvis
  below it, open jacket as panels with a collar, hair caps with a hairline above the brows.
  Beard still jagged ("fine for now"); a nicer beard belongs in `add-character-features`.
- **Walk cycle knees bent backwards (human, Deck 2026-10-02: "walks a bit like a bird").**
  Fixed: shin and forearm rotation signs flipped in `walk_pose`; test pins heel behind the
  knee and hand in front of the elbow.
- **Engine idle audible on foot anywhere (human: "sound has a bit of a fart to it in the open
  world").** Fixed: engine and tyre voices only fill while the local player drives; impacts
  still sound. Character creator and traffic interaction archived on the human's verdict.
- **Portage underpass approach fights a garage ramp (human, Deck 2026-10-02, standing at
  x -1208, z 142: "the tunnel works, ish; bent; through the first half then can get up but
  it's work; or maybe that's parking lot related").** The Ottawa River Pathway tunnel
  (`p39635225`, floor 46.2, top 49.3) is straight with 15 % approach trenches, so the climb
  itself is within the character's limit. Service road `w107633329.0` (layer 0, y 47 to 58,
  the ramp into the garage whose layer -2 stub `w39674788.0` is already treated as a tunnel)
  descends through the west portal area at x -1197, z 136, and its road cut crosses the
  pathway trench: slabs and walls in the trench, a step mid-climb. Fix belongs with
  `add-underpass-interiors` (trench retaining walls) or a small importer rule: a service
  ramp into a tunnel stub is itself a tunnel approach and should not flatten terrain across
  a pedestrian trench.
- **Bus signs (human, 2026-10-02).** Number on the back, number plus route name on the front
  like modern transit; folded into `add-bus-routes`. Buses and day-night stop gates ticked.
- **Two-wheelers (human asked 2026-10-02 whether to add motorcycles and bicycles).** Own
  change after `add-vehicle-variety`: bicycles on the imported cycleways, a motorcycle class
  with lane filtering, rider bodies from the character pipeline, a lean model on a capsule
  rather than four-wheel physics, both takeable. Design note from the human: they enjoy using
  the bike lane as a free passing lane, so cyclists must populate it without fencing it off
  from cars; squeezing between cars is hard, which is correct for OSM lane widths.
- **Rail (human asked 2026-10-02).** OSM maps rail as `railway=*` ways (light_rail, subway, rail, tram) with stations; the importer only queries `highway=*`. The Confederation Line runs in a tunnel under Queen Street downtown (Lyon, Parliament, Rideau stations) and surfaces east of uOttawa and west of Pimisi. A rail round would fetch railway ways, build track ribbons and the surface stations, and run trains on a timetable. Albert and Slater lost their bus lanes when the line opened in 2019, which is why OSM has them plain.
- **Buses** built (add-buses): bus-only streets kept, reserved lanes painted red, buses with stops. Routes, timetables and shelters remain. Only Lyon Street North, the Transitway and one Waller Street lane are tagged in OSM; Albert and Slater have no bus-lane tags in the extract.

## 2026-10-01

- **Character detail (human, 2026-10-01: "would love to see improved detail").** Next creator round: rounded head and limbs, separate forearms and shins with a walk cycle, more hair styles, beards, glasses, jackets over tops, and the same body on pedestrians.
- **Testbed sometimes starts on foot despite `--drive`** on Mac screenshot runs (seen 2026-10-01, roughly one run in three). Could not reproduce 2026-10-04: ten runs, windowed and headless, all started driving; likely fixed by the spawn and streaming work since. Reopen if seen.
- **Visibility ranges on city-wide MultiMeshes** are measured to the bounding box centre; removed from signal heads and billboards. Any future city-wide MultiMesh must be chunked or range-free.
## 2026-09-30

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
- **Garage follow-ups** (add-underground-parking, 2026-10-05): the minimap should show the garage floor while the player is inside; beside some ramps the 4 m terrain cut leaves black triangles past the coping (the museum ramp), so cut the terrain to the ramp strip itself or widen the coping per cell.
- **Parking lot fill needs more passes** (human, 2026-10-05 Deck round: "we probably need to do some more passes with the fill in algorithm"). They will send screenshots of the lots that look wrong; start from those (stall layout in `parking_lot_builder.gd`: rows, aisles, `_row_only`, `_clear_of_streets`).
- **Street-side parking bays are exported but not populated** (add-parking-lots, 2026-10-04):
  256 bays in `parking.v0.json`, but road meshes and traffic lanes have no parking lane, so a
  kerbside car would sit in the travel lane. Needs road widths that include the parking lane
  (or a lane offset for traffic) before bays get cars.
  **One cause found and fixed 2026-10-04:** the headless (dummy) renderer's mesh storage is not
  thread-safe, and chunk build tasks creating meshes at once corrupted it ("Attempting to
  initialize the wrong RID", "Parameter mem is null"). The streamer now builds synchronously
  under the headless renderer, and collision shapes are made on the main thread everywhere
  (the physics server isn't thread-safe either). The rarer abort (signal 11) after
  `test_testbed_menus` was the audio mixer, fixed in #25 (see the entry above).
- **Junctions where terrain still shows through** (add-surface-detail 1.2, 2026-10-04): 16 of 915
  by `test_junction_terrain.gd`, including n14141327481 (+10.5 m), n472497779 (+10.7 m),
  n472558217 (+2.9 m), n4991525553 (+0.4 m), n2609373961 (+0.18 m), c1236845823 (+0.17 m).
  The big ones look like junctions in cuttings or at tunnel mouths, not the corner problem.
  Look at each in game; the test guards the share. With add-parking-lots' pack it is 47 of
  1,936 (2.4%): many driveway and aisle junctions on slopes add to it.
- **README's pack-builder command is stale:** `godot ... -s res://world/build/pack_builder.gd`
  points at a file that does not exist (and `build/` is gitignored, which also swallowed new
  files placed under `game/world/build/` once).
- **High preset fog is very heavy:** on the Mac, the high preset's fog hides the city beyond
  about 50 m at noon (every screenshot today used the deck preset to see anything). Check the
  volumetric fog density.

## Done

Finished or now tracked by an OpenSpec change; kept so their history is easy to find (details in git history and the archived changes).

- Proposal slate (human asked 2026-10-02: write proposals so other agents can work in parallel) (proposals written 2026-10-02)
- Controls (human, 2026-10-02: "make R1 handbrake so I don't keep blipping to nowhere") (update-controls-layout, archived 2026-10-05)
- Crossings and cycle tracks across roads were curb-high steps (fixed 2026-10-02)
- Parking lots (human, 2026-10-02: "add parking lots to the specs") (add-parking-lots, archived 2026-10-05)
- Traffic lights white at night (fixed 2026-10-02)
- Surface detail (human, Deck drive 2026-10-02: textures and sidewalk line breaks) (add-surface-detail, archived 2026-10-05)
- Clouds and weather (human, 2026-10-02) (tracked by the add-weather proposal)
- Vehicle variety (human, 2026-10-02) (add-vehicle-variety, archived 2026-10-04)
- Trees and bushes (human, 2026-10-02) (tracked by the add-vegetation proposal)
- Region picker (built)
- Character creator plan (from the human) (built: the character creator)
- Region picker plan (built)
- Region picker (built)
- Physics budget (profiling pass 2026-09-30)
- Traffic cars are ghosts and pile up (add-traffic-interaction)
- Pedestrian underpasses and tunnels (add-underpasses, archived 2026-10-05; interiors are add-underpass-interiors)
- Cars pinned against traffic cars fling things across the map (fixed in add-vehicle-variety 3.4)
- Flaky gdUnit crash (exit 134) (fixed 2026-10-05, #25)
- gdUnit orphan count of about 2,200 (fixed 2026-10-05: the two whole-testbed suites flush the streamer's built-but-unadded chunks and queued meshes after each test; 0 orphans)
- Co-op tab in the pause menu (done 2026-10-05: Host, Join, the address and the session status moved off the Game tab)
