# Backlog: field reports from Deck drives

Things seen while driving that are not yet an OpenSpec change. Newest first.
Each entry names the place (local x,z where known) so a fresh session can go straight there.

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
- **Controls (human, 2026-10-02: "make R1 handbrake so I don't keep blipping to nowhere").**
  The blip was the car reset sharing RB with the handbrake; reset now sits on R3 as the doc
  said, with a test that driving actions never share a button. `update-controls-layout` holds
  the GTA V / IV / III and Cyberpunk 2077 reference table and the proposed layout (horn L3,
  look behind R3, hold R3 to reset, radio D-left, headlights D-right, remapping page).
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
- **Crossings and cycle tracks across roads were curb-high steps** (human, Deck shot 2026-10-02
  at x 930, z 932: "I drove straight into the bike lane"). Fixed in the importer: a pedestrian
  segment crossing a road ribbon gets vertices just inside each edge (flush) and a curb ramp
  just outside; Ottawa pack re-exported. Buses are all red now (OC Transpo). Day-night and
  buses archived after the human's Deck verdict.
- **Parking lots (human, 2026-10-02: "add parking lots to the specs").** Proposal
  `add-parking-lots`, after `add-vehicle-variety`: 695 lots, 650 aisles and 595 driveways in
  the bbox come back as class `parking` with parking-only lanes, stall markings, kerb bays,
  seeded parked cars by hour. Reverses the 2026-09-30 "aisles stay out" decision; needs a yes.
- **Traffic lights white at night** fixed 2026-10-02 (flat grey emission on the lamp material;
  now a shader glowing in the instance colour, night energy 2.2).
- **Surface detail (human, Deck drive 2026-10-02: "add textures and sidewalk line breaks;
  the cross walks should be striped like Abbey Road").** Proposal `add-surface-detail`:
  generated world-space detail textures, slab joints on sidewalks, zebra stripes on every
  crossing. Open: zebra everywhere or only at signals; slab length.
- **Bus signs (human, 2026-10-02).** Number on the back, number plus route name on the front
  like modern transit; folded into `add-bus-routes`. Buses and day-night stop gates ticked.
- **Two-wheelers (human asked 2026-10-02 whether to add motorcycles and bicycles).** Own
  change after `add-vehicle-variety`: bicycles on the imported cycleways, a motorcycle class
  with lane filtering, rider bodies from the character pipeline, a lean model on a capsule
  rather than four-wheel physics, both takeable. Design note from the human: they enjoy using
  the bike lane as a free passing lane, so cyclists must populate it without fencing it off
  from cars; squeezing between cars is hard, which is correct for OSM lane widths.
- **Clouds and weather (human, 2026-10-02).** Proposal `add-weather`: clear, overcast, rain,
  snow, fog as data with a seeded next-state table; scrolled noise clouds on a sky shader
  (deck one layer, high two plus cloud shadows), camera-following rain and snow particles,
  wetness and snow uniforms on the shared materials, traffic slowdown and grip per state,
  host-owned and sent with the clock. Open: snow before a season table, headlights auto in
  heavy weather, snow grip 0.55.
- **Vehicle variety (human, 2026-10-02).** Proposal `add-vehicle-variety`: a vehicle catalogue
  (`vehicles.v0.json`, packs may add) driving one parametric generator for eight classes with
  two LODs (LOD0 under 900 to 1300 tris, LOD1 under 260), a generated trim atlas, spawn weights
  by road and hour, player car from the catalogue with `--car=`. Open: eight classes or five
  first (draw calls 8 to 72), livery naming.
- **Trees and bushes (human, 2026-10-02).** Proposal `add-vegetation`: OSM trees, tree rows
  and wood/park/grass polygons scattered deterministically, per-chunk MultiMeshes with LODs
  driven by the streamer tier, deck cap 400 trees and 600 bushes per chunk, trunk collision
  only near roads. Open: collision on every tree, autumn palette.
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
- **Cars pinned against traffic cars fling things across the map** (human, 2026-10-04: "two
  cars got pinned and things flew to the other end of the map"). Likely the same cause as the
  pedestrian hard stop fixed in add-pedestrians 3.5: traffic bodies (`traffic_car.gd`) are
  frozen kinematic until `body_entered` unfreezes them, so the solver treats them as immovable;
  a car wedged between one and anything else gets pushed out with a huge velocity. Fix as a
  `fix/` change: unfreeze or sensor-switch like the pedestrians, and cap the depenetration
  speed. Reproduce with a lab scene first.
- **Flaky gdUnit crash (exit 134)**, about 2 in 14 full local runs on 2026-10-04 (GitHub CI
  passed every time). A worker thread hits `/root: The caller thread can't call the function
  propagate_notification()` and aborts during `test_report_store.gd`, which runs right after
  `test_testbed_menus.gd` (the full testbed, with chunk-streamer and radio tasks). Running only
  those two suites 6 times did not reproduce it. Suspect a WorkerThreadPool task from the
  testbed outliving its teardown. Rerunning CI passes.
  **Mitigated 2026-10-04:** became 3 in 5 runs once traffic grew; ignoring the testbed suite
  gave 4 of 4 clean runs, confirming it as the source. Letting the freed testbed settle for 60
  frames in its `after()` gave 5 of 5 clean. The thread itself is still unnamed.
  **Fixed 2026-10-05** (`fix/audio-generator-teardown`): the thread is the dummy audio
  driver's mixer, and the `/root` error is the crash handler's `NOTIFICATION_CRASH` sent from
  it. Godot's `AudioStreamGeneratorPlayback` holds a raw pointer to its stream and reads it
  every mix; freeing a player dropped the stream before the mixer saw the stop. `Synth`
  now keeps each generator for 0.5 s after its player leaves the tree.
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
