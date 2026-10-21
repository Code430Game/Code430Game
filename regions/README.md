# Regions

Each file here is a region picked with `tools/region_picker/index.html` (open it in a browser,
no server needed): `{"name", "bbox": [S, W, N, E], "pack_id", "dem"}`. Import one with

    cd tools && uv run python -m osm_import --region ../regions/<name>.json --pack-out ../packs/<name>

Keep the box under about 20 km². Ottawa Centretown (`ottawa-centretown.json`) is the reference.

**Pin the origin.** Every map coordinate is metres from the pack's origin, which is the bbox
centre unless the region gives `"origin": {"lat": ..., "lon": ...}`. Pin it, so a wider box
later doesn't move everything stories have placed. Re-exporting into a pack whose origin would
change is refused; `--new-origin` allows it, and the pack then needs a breaking version bump.

**Districts of a city.** A district can give its extent as `"border": {"chunks": [x0, z0, x1,
z1]}` instead of a bbox: 256 m chunks x0..x1-1 by z0..z1-1 on the grid of the city's pinned
origin (x east, z south). The import box is the lat/lon box around it, and the pack's
`map.border` records it. A border needs an origin, and the importer refuses one that overlaps
a sibling region file with the same origin, so every chunk belongs to one district and
neighbouring districts can be played together later (`add-district-stitching`).

A region can also be built entirely from files, with no network: `"inputs"` names an Overpass
JSON file per layer (`osm`, `water`, `buildings`, `parking`, `bridges`, `services`,
`vegetation`, relative to the region file), `"extras"` lists pack files to copy in as they are
(a lap timer, a gang's turf), `"spawn"` fixes where the game starts (`x`, `z` in local metres,
`heading_deg` with 0 north and 90 east), and with `"dem": "synthetic"` a `"synthetic"` object
sets the analytic terrain (`base`, `slope_x`, `hill_height`, `hill_radius`, `hill_x`, `hill_z`).
A region that isn't OpenStreetMap data names its own `"license"` and `"attribution"` (and its
`"description"` then goes on the pack); without them a pack is ODbL 1.0 and credits
OpenStreetMap.

The Double Cross proving ground (`proving-ground.json`, inputs under `proving-ground/`) is such
a region, licensed CC BY-SA 4.0 like the game's other assets since our own code generates
it: `tools/proving_ground` writes the inputs and `scripts/regen-proving-ground.sh`
rebuilds `packs/proving-ground` from them. Never edit the inputs by hand; change the generator
and regenerate (CI checks that the committed files match a fresh run).
