# Regions

Each file here is a region picked with `tools/region_picker/index.html` (open it in a browser,
no server needed): `{"name", "bbox": [S, W, N, E], "pack_id", "dem"}`. Import one with

    cd tools && uv run python -m osm_import --region ../regions/<name>.json --pack-out ../packs/<name>

Keep the box under about 20 km². Ottawa Centretown (`ottawa-centretown.json`) is the reference.

A region can also be built entirely from files, with no network: `"inputs"` names an Overpass
JSON file per layer (`osm`, `water`, `buildings`, `parking`, `bridges`, `services`,
`vegetation`, relative to the region file), `"extras"` lists pack files to copy in as they are
(a lap timer, a gang's turf), `"spawn"` fixes where the game starts (`x`, `z` in local metres,
`heading_deg` with 0 north and 90 east), and with `"dem": "synthetic"` a `"synthetic"` object
sets the analytic terrain (`base`, `slope_x`, `hill_height`, `hill_radius`, `hill_x`, `hill_z`).

The Double Cross proving ground (`proving-ground.json`, inputs under `proving-ground/`) is such
a region: `tools/proving_ground` writes the inputs and `scripts/regen-proving-ground.sh`
rebuilds `packs/proving-ground` from them. Never edit the inputs by hand; change the generator
and regenerate (CI checks that the committed files match a fresh run).
