# Backlog: field reports from Deck drives

Things seen while driving that are not yet an OpenSpec change. Newest first.
Each entry names the place (local x,z where known) so a fresh session can go straight there.

## 2026-10-21

Deck session answers (the human, on the clean-clone build of the rewritten history):

- **Traffic has no headlights at night (human: "Night is fine only you have headlights iirc").**
  Checked on the Deck: they do. The pools are ahead of each car, so cars driving the player's
  way hide theirs, and they are faint beside the player's beams. Brighter pools, or lit
  headlamp glow on the car bodies, if the human wants them to read more.
- **No gang seen (human: "No gang"; then "I played the proving ground and they were not
  there ... I drove through it [the striped area] and nothing happened").** `add-hostile-gang`
  4.2 open. Two causes:
  - Fixed on `fix/turf-hatch-and-credit`: the map drew the turf's stripes *outside* its ring
    (`clip_polyline_with_polygon` keeps what's outside; `intersect_...` was meant), so the
    striped land beside the turf looked like the turf and the turf itself looked plain.
  - Centretown has no turf at all; the only crew is Double Cross's on the proving ground
    (x 550..750, z 400..550). Ottawa's first turf belongs in a story pack (lat/lon turf,
    `add-pack-repositories` 1.7).
  - Open question: a crew sees 28 m and warns for 2 s before it attacks, so a car driving
    through never sets it off. Decide whether a crew reacts to a passing car (shouts, throws,
    shoots at it in gritty).
- **No helicopter to fly (human: "No heli").** `add-flyable-helicopter` 4.3 open. Not a bug:
  it parks on Centretown's one helipad by the river (about x -939, z -1009), far from the start;
  the legend lists it under Helipad. A "Go to" in the legend would make it quick to reach.
- **No rain or snow during play.** `add-weather` 4.2 open. Not a bug: clear lasts 15 to 40 min
  and is followed by clear 60% of the time, and rain only follows overcast, so most sessions
  end dry. A weather choice in the pause menu would let a player bring it on.
- **Proving ground credit ran into the HUD** (seen in a screenshot after #133): the long credit
  line overlapped the coordinates. Fixed on `fix/turf-hatch-and-credit`: "Double Cross by
  Code 430 contributors".
- **The police helicopter is very hard to hide from (human: "hiding from heli really hard").**
  Balance: cover under bridges, garages and tunnels, and how fast it loses sight.
- **Police "issues but for later"** (human); ask for details at the next police round.
- **Proving ground still has gaps** (human: "iirc there were still gaps") after the density pass.
- **Garages other than the NAC had issues**, already reported by the human.

## 2026-10-08

- **The gang was underground on the Deck (human: "I did not see the gang in the marked area").**
  Fixed on `fix/gang-spawns-in-play`: the turf's ground height came from a physics ray at
  load, before the turf's chunk (a kilometre from the spawn) had collision, so the crew stood
  at y 0 under a street at 62.6. `MapPack.ground_height(x, z)` now reads the pack's heightmap
  with no physics; the ray only refines within 3 m (from 60 m up it found the viaduct deck).
  Anything else that places actors far from the player at load should use the same sampler.

- **Proving ground is sparse (human, Deck 2026-10-08: "that world seems to work. It's a little
  sparse so we might come back to spruce it up").** Archived on that verdict. A spruce-up
  round for Double Cross: houses on every residential block, shopfronts and a few taller
  blocks in the main city, trees along the bank road and the greenbelt edge, street
  furniture, the gang's turf dressed once `add-hostile-gang` lands, and a town name (still
  open). Physics on the loop measured 8.8 ms mean against Ottawa's 6.4; look at how many
  traffic agents sit near the player on the elevated lap.

- **Windowed runs crashed after about 55 s** (fixed 2026-10-08, `fix/windowed-worker-crash`).
  Not a worker-thread bug: Godot 4.7's `AudioStreamWAV` `LOOP_FORWARD` wrap crashes the audio
  thread (`/root: The caller thread can't call propagate_notification()`, then signal 11 in the
  CoreAudio thread) once the loop point is past about 1.2 million samples. Hilltop's loop is
  1,245,176 samples (56.47 s at 22050 Hz) and is the default station, so every windowed run
  with the radio on died at its first wrap; `--radio=off` or `--radio=crypt` (45.7 s) ran
  fine, and a bare 1,245,176-sample looping WAV crashed the same way while 1,200,000 did not.
  The radio now feeds its loops through an `AudioStreamGenerator` and wraps them itself, so
  no looping WAV reaches the mixer. Probe script: a `SceneTree` that plays a synthetic
  looping WAV of N samples from 3 s before its end.
- **Proving ground built** (`add-proving-ground`, PR #92): `--pack=code430.proving-ground`
  starts on the Double Cross start line; the lap readout and the four access points are in.
  The gang's turf (`turf.v0.json`) is the block 8 Lane to 9 Lane, Park Road to Mid Road,
  under the viaduct's south straight (x 550 to 750, z 400 to 550).

## 2026-10-07

- **Relay needs a redeploy for report tags** (done 2026-10-07 from the Mac that has Cloudflare: deployed version fcb4e14b, `/health` ok, a tagged report now passes the schema, `tag:*` labels created; left for the human: resend from Saved reports on the Deck) (human, 2026-10-07:
  "I will have the other machine fix that later"). Tagged reports from the Deck fail with
  "refused 400 … unknown key tags": the deployed Worker predates the optional `tags` field
  (4db283b). The reports wait in the game's Saved reports queue. Cloudflare isn't logged in on
  the work Mac. On the machine that is:
  1. `cd tools/report_relay && uv run pywrangler deploy` (use `nvm exec 22` if needed);
  2. check `/health`;
  3. run `scripts/setup-report-labels.sh` with an account that can admin the repository (creates the `tag:*` labels);
  4. resend from Saved reports on the Deck.
- **Ramp lane markings woven into the motorway's** (human: "I wonder if some of those off
  ramps need to be laid under the main road way since the on ramp's lane markings are displayed
  interwoven with the highways lane markings"; seen at the 417 merges, for example (842, 898)
  and the fork at (279, 1229)).
  - Fixed on `fix/ramp-markings-under-highway`.
  - Cause: links sat 1.5 cm *above* every other road (`LINK_EXTRA_LIFT_M`, from the first
    road import), so a ramp's ribbon lay over the motorway where OSM draws it from the
    centreline. All markings also shared one height, so both sets of lines showed, crossed.
  - Now links sit 1.5 cm *under* other roads (`RoadMeshBuilder.LINK_UNDER_M`; gores went under
    them). A ramp's markings stop at the through road's ribbon edge, and the through road's
    edge line turns to dashes across the ramp's mouth (`MarkingBuilder`, the `cover_*` rules).
  - Ottawa: ramp-marking vertices on through roads went from 795 to 10. The 10 are single line
    corners at a cover edge.

## 2026-10-06

Deck session on ed2ee5a (dystopia tone). The human's verdict: "the cops are fun".

- **Three-way splits make a blob junction** → `update-junction-surfaces` (issues #78, #79). The
  "ball" junction, but for a T or Y: where a lane leaves the main road three ways, the junction
  asphalt is a rounded hull that bulges into the grass, and the lane lines stop short of it.
  - #78: Colonel By Drive, x 998, z 1041, junction `n901218147`: "junction turns into ball".
  - #79: a parking entrance off a street, x 1098, z 935, junction `n6020506072`. A ragged wedge
    of asphalt where the driveway meets the sidewalk, and a sign standing inside it.
  - The X-intersection case was fixed earlier (`update-cluster-junction-arms`, fa34b3d). The
    three-arm case wasn't covered. The importer review (2026-10-06) also found clusters with no
    size limit (`cluster.py:113-151`, up to 8 nodes and arm offsets of 21 m): start there.
- **Signs in the middle of roads** (fixed in `19d8c7f`: boards keep off roads, junctions and bridges) (human, 2026-10-06; one in #78's screenshot, another in the
  underpass under the 417 by the Museum of Nature). `game/world/dressing/billboards.gd:28-60`
  puts a board every 220 m, 3.5 m out from every trunk, primary or secondary road. It checks
  nothing else, so boards land:
  - on side streets, in junctions and on sidewalks;
  - on the road under an overpass;
  - in mid-air beside bridge decks.

  Fix (a `fix/`): skip bridge roads, keep clear of junctions, drop any site whose post lands on
  a road or sidewalk ribbon, and test that no board stands on a road.
- **The report form's text box can't be typed on the Deck** (#79 went in without a
  description). The form only focuses the text box and relies on Steam to show its keyboard,
  which Steam does only for games that ask through Steamworks. Steam + X didn't bring it up
  either. When the human pressed the Steam button, the keyboard flashed as it hid behind the
  Steam menu, so it had opened but stayed behind the game. The co-op Join address box has the
  same problem. Options:
  - a small built-in on-screen keyboard (no new dependency);
  - Steamworks through GodotSteam (a new dependency; the human decides).
- **Driverless patrol car** (fixed in `update-police-pursuit`, `aa69377`: parked empty cars): when an officer gets out, the car is marked `officer_out`
  (`police_manager.gd:295`), but `_drive` never checks the mark, so the empty car keeps chasing
  once the player moves. Fix: park it with the handbrake on until the officer is back or the
  chase ends.
- **The helicopter can't be shaken off** → `update-police-pursuit` (`aa69377`: escapable helicopter, canopy cover, seen badge) (human: "I still think it might be impossible to drive
  away from the copter"). It flies at 45 m/s (about 160 km/h, `helicopter.gd:19`) in a straight
  line and sees 150 m. The only escape is cover, and nothing in the game says so.
  - Make it slower than a fast car (about 35 m/s).
  - Let it lose a player who gets past its sight range in the open.
  - Add a "find cover" hint.
  - Move its constants into config.
- **Shooting the police** → `add-police-combat` (`86131f1`) (human: "I don't think I can shoot them to get away"). Officers can't
  be hit; the police change never covered it. This needs a proposal: officer reactions by tone,
  more stars, backup arriving.
- **R3 hold resets the car mid-chase** (human: "It was the R3 trap, it's fine for now"). Holding
  R3 to look behind for a second resets the car, which can drop it at the start.
  - Decided 2026-10-07, no change: "It's not an issue for now… eventually though we should
    hopefully have less cases where we NEED the reset button. So lets not worry if it's game
    breaking or anything right now."
  - The aim is fewer places where a reset is needed (stuck spots, falling through), not
    changing the button.
- **A reset keeps the wanted level.** After an R3 reset to the start (by Catherine Street and the
  417), new patrol cars spawned around the player there. Left as is, under the same decision.
- **Weapon wheel: hold not yet tried.** The human tapped LB to cycle and didn't open the wheel.
  Holding LB for more than 0.2 s opens it; confirm on the Deck.
- **Fell under the floor after being busted.** Probably the respawn landed before that area's
  ground had loaded. f555839 now builds the ground at the arrival point first. Unconfirmed,
  because the place wasn't recorded; watch for it.
- **Report form on the Deck: quick tags and a keyboard test** (human, 2026-10-06: an on-screen
  keyboard is premature; "users expect" Steam's keyboard).
  - Done 2026-10-07 (`fix/report-quick-tags`): the description is optional, and six quick tags
    are picked with Left / Right and A (or a click), from `game/ui/report/report_tags.json`.
    Tags go into the report's optional `tags` field, the title ("· Stuck, Police"), the issue
    body and `tag:<id>` labels. Redeploy the relay and re-run `scripts/setup-report-labels.sh`
    before a build with tags reaches players (`tools/report_relay/README.md`).
  - Keyboard: no debugging needed. The human, 2026-10-07: "The steam deck's keyboard did open
    fine the last time I loaded the game. So maybe it was an isolated issue." How text entry
    works is now written down in `docs/controls.md` ("Typing on the Steam Deck"), so later
    changes keep it working.
  - Steamworks' gamepad text input (GodotSteam) is for the Steam release work.
- **Map legend and places list** → built 2026-10-07 as `add-map-legend` (human, 2026-10-06: "include a legend in the map and also a
  method of viewing items from each location ... a little more plain search engine and instead
  of toggling through we click in or back"). On the full map (`game/ui/map/overview_map.gd`),
  a legend panel lists each kind of place as its icon, then its name:

  ```
  [hospital icon] Hospital
  [police icon]   Police
     -> 2125 Bronson Ave
     -> 134 St Other Street
  ```

  - A (or click) on a kind opens its list of places; B goes back.
  - Picking a place centres the map on it. A waypoint or route there could follow later.
  - No cycling through places with a button, unlike GTA's map.
  - Addresses should be real. `services.v0.json` has names but no addresses today (6 kinds:
    ambulance 3, fire_station 2, police 2, hospital 2, security 2, helipad 1). The importer
    should keep OSM's `addr:housenumber` and `addr:street`, and fall back to "on <nearest
    street>" from the road graph. OSM addresses are ODbL like the rest of the map data.
  - The minimap's icons and the legend's should be the same set.
  - Later: parking garages, shops and mission markers in the same list.
- **Every moving thing gets a sound** (human: "Maybe all items can get sounds in one feature
  ticket"). Folded into `update-audio-pass`, which already planned positional sirens and rotor.
- **Fixed (fix/police-stop-and-shadow, 2026-10-07):**
  - **Patrol cars stopped short and respawned.** A route ended at the player, so from its last
    node the car drove straight at them and hit a pier or wall under the deck, stopping about
    40–55 m short. `_unstick` (far and slow) then took it away. Cars spawned facing the player
    rather than along the road could wedge at once too. Now:
    - routes end on the road nearest the player;
    - a car blocked within `officer_out_blocked_m` (70 m) of a player on foot or stopped lets
      its officer out instead of vanishing;
    - a car parked on purpose (officer out, or pulled up) is never taken away;
    - cars spawn facing along their route.
  - **The helicopter casts a ground shadow by day:** a soft blob on the first solid surface below
    it, sized and faded by height and gone at night (the searchlight's job), tuned in
    `police_config.json`'s `helicopter` block.
- **Fixed during the session:**
  - hold R3 on foot goes back to the start (f555839);
  - the police and the helicopter show on the minimap (ed2ee5a).

## 2026-10-05

- **Punching and kicking** → proposal `add-unarmed-combat` (human, 2026-10-05, while planning weapons: "another could be punching and kicking. Or that could be a different ticket"). Empty hands are already a slot in the weapon cycle; fists and kicks would fill it, with a non-lethal shove in clean.
- **Side-by-side bridge carriageways at different heights** → proposal `update-shared-deck-heights` (issue #45, Mackenzie King Bridge at x 517, z -523): the 2-lane way runs about 0.48 m above the 3-lane one where their ribbons touch, so the step shows as a low strip (the deck's side face) between them. The parapets that stood in that gap were removed in the #45 fix. Proper fix: the elevation stage should give touching carriageways of one bridge a shared height, blending into the approaches.

## 2026-10-04

- **Radio per car** → proposal `update-radio-per-car` (human, 2026-10-04, Deck drive for `add-car-radio`).** Today the radio follows
  the player into any car. Idea: the player's own car keeps their chosen station, and a stolen or
  taken car plays whatever station its owner had on (a random one). Not started.

## 2026-10-03

- **Curbs that still stop the car** (human, 2026-10-22, Deck, after `add-vehicle-and-building-damage` 1.1-1.3).**
  "There are still some curbs that stop the car"; since car damage, they dent it too. Not
  located yet: a report from the spot (the issue reporter records x, z) or the HUD's x, z next
  time. Check them against `BarrierBuilder.clip_curbs` (update-junction-surfaces 2.2).
- **Curb inside a junction at a curved road join** → proposal `update-junction-surfaces` (human, 2026-10-03, Deck drive for
  `update-cluster-junction-arms`).** A curb stands on the interior of the junction where a
  curved road joins; not the clustered-X issue, which the drive confirmed fixed. Location not
  recorded yet; get x,z from the HUD next time. Likely the barrier importer's curb lines
  (`barriers.py`, `curb_classes`) not being cut back to the junction polygon at curved arms.
- **Grass through road surfaces** → proposal `update-junction-surfaces` (human, 2026-10-03). `update-cluster-junction-arms` fans
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
- **Audio polish is a later focused project** → proposal `update-audio-pass` (human, 2026-10-02: "I'd rather leave this until we
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
  2026-10-07: the 10-02 open jacket still showed the shirt as an 8 cm strip between the
  fronts, which read as a tie. The fronts now stand 24 cm apart (`CharacterMesh.JACKET_FRONT`),
  and a test keeps any jacket off the front within 10 cm of the centre line.
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
- **Two-wheelers** → proposal `add-two-wheelers` (human asked 2026-10-02 whether to add motorcycles and bicycles).** Own
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
- **Garage follow-ups** → proposal `update-garage-polish` (add-underground-parking, 2026-10-05): the minimap should show the garage floor while the player is inside; beside some ramps the 4 m terrain cut leaves black triangles past the coping (the museum ramp), so cut the terrain to the ramp strip itself or widen the coping per cell.
- **Parking lot fill needs more passes** → proposal `update-parking` (human, 2026-10-05 Deck round: "we probably need to do some more passes with the fill in algorithm"). They will send screenshots of the lots that look wrong; start from those (stall layout in `parking_lot_builder.gd`: rows, aisles, `_row_only`, `_clear_of_streets`).
- **Street-side parking bays are exported but not populated** → proposal `update-parking` (add-parking-lots, 2026-10-04):
  256 bays in `parking.v0.json`, but road meshes and traffic lanes have no parking lane, so a
  kerbside car would sit in the travel lane. Needs road widths that include the parking lane
  (or a lane offset for traffic) before bays get cars.
  **One cause found and fixed 2026-10-04:** the headless (dummy) renderer's mesh storage is not
  thread-safe, and chunk build tasks creating meshes at once corrupted it ("Attempting to
  initialize the wrong RID", "Parameter mem is null"). The streamer now builds synchronously
  under the headless renderer, and collision shapes are made on the main thread everywhere
  (the physics server isn't thread-safe either). The rarer abort (signal 11) after
  `test_testbed_menus` was the audio mixer, fixed in #25 (see the entry above).
- **Junctions where terrain still shows through** → proposal `update-junction-surfaces` (add-surface-detail 1.2, 2026-10-04): 16 of 915
  by `test_junction_terrain.gd`, including n14141327481 (+10.5 m), n472497779 (+10.7 m),
  n472558217 (+2.9 m), n4991525553 (+0.4 m), n2609373961 (+0.18 m), c1236845823 (+0.17 m).
  The big ones look like junctions in cuttings or at tunnel mouths, not the corner problem.
  Look at each in game; the test guards the share. With add-parking-lots' pack it is 47 of
  1,936 (2.4%): many driveway and aisle junctions on slopes add to it.
- **README's pack-builder command is stale:** `godot ... -s res://world/build/pack_builder.gd`
  points at a file that does not exist (and `build/` is gitignored, which also swallowed new
  files placed under `game/world/build/` once).
- **High preset fog is very heavy:** on the Mac, the high preset's fog hides the city beyond
  about 50 m at noon (every screenshot today used the deck preset to see anything). Fixed
  2026-10-07 (`fix/fog-and-jackets`). The preset turned volumetric fog on but never set its
  density, so Godot's default of 0.05 per metre applied, leaving about 8 % visibility at 50 m.
  The presets now carry `volumetric_fog_density`: 0.002 on high (a light haze), unused on deck.

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
