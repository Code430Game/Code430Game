# Regions

Each file here is a region picked with `tools/region_picker/index.html` (open it in a browser,
no server needed): `{"name", "bbox": [S, W, N, E], "pack_id", "dem"}`. Import one with

    cd tools && uv run python -m osm_import --region ../regions/<name>.json --pack-out ../packs/<name>

Keep the box under about 20 km². Ottawa Centretown (`ottawa-centretown.json`) is the reference.
