# Pack format

Every pack is a folder with a `pack.json` manifest at its root. Packs load into their own namespace and never overwrite base game files. Schemas in this folder are validated in CI by `tools/pack_tools`.

## Pack types

| Type | Contains | Code allowed |
|---|---|---|
| `map` | Road graph, terrain, generated city meshes, points of interest | No |
| `character` | Models, animations, voices, behavior parameters, routines | No |
| `story` | Characters placed on a map, dialogue, missions (declarative) | No |
| `system` | New mechanics, vehicles with custom logic, tools | Yes, marked trusted |

## Data-only rules (map, character, story)
Data-only packs may contain **only** these file types:

- Data: `.json`, `.yaml`, `.yml`, `.txt`, `.md`, `.csv`
- Models: `.gltf`, `.glb`, `.bin`
- Textures: `.png`, `.jpg`, `.jpeg`, `.ktx2`, `.webp`
- Audio: `.ogg`, `.wav`

Anything else is rejected, in particular Godot resource formats (`.tres`, `.res`, `.tscn`, `.scn`), scripts (`.gd`, `.gdshader`, `.cs`), and archives (`.pck`, `.zip`). Godot resources can embed executable scripts, which is why they are banned rather than scanned.

## System packs
System packs ship as a `.pck` next to their `pack.json`, must set `"trusted": true`, and the game warns the player before enabling them. Data-only packs must not set `trusted` to true.

## Manifest fields (`pack.schema.v0.json`)

| Field | Required | Meaning |
|---|---|---|
| `schema_version` | yes | Always `0` for this schema. |
| `id` | yes | Unique id, lowercase with dots, for example `code430.ottawa-centretown`. |
| `name` | yes | Display name. |
| `version` | yes | Semantic version, for example `0.1.0`. |
| `type` | yes | `map`, `character`, `story`, or `system`. |
| `engine_api` | yes | Pack API major version the pack targets. Currently `0`. |
| `license` | yes | SPDX identifier for the pack's own content. Map packs derived from OpenStreetMap use `ODbL-1.0`. |
| `attribution` | yes | Credit lines shown in-game. Map packs must include `© OpenStreetMap contributors`. |
| `description` | no | Short text. |
| `authors` | no | List of names or handles. |
| `dependencies` | no | Packs this pack needs: `[{"id": "...", "version": "^1.0"}]`. |
| `trusted` | system only | Must be `true` for system packs and absent or `false` otherwise. |
| `homepage` | no | URL. |
| `map` | map only | `crs` (for example `EPSG:32618`), `origin` (`easting`, `northing`, `lat`, `lon`), optional `bbox`. |

| `supported_modes` | no | Tone modes the pack's content supports, for example `["clean", "gritty", "dystopia"]`. The game warns when the active mode is missing. |
| `max_descriptors` | no | Strongest level per content descriptor anywhere in the pack, for registry filtering. |

## Tone modes and content descriptors
The same world plays in different tones. Modes are data (`game/core/content/modes/*.json`,
schema `tone-mode.schema.v0.json`): each lists the maximum level per descriptor, mechanic
flags, and the variant key items use. Descriptors are the closed list in
`game/core/content/content-descriptors.v0.json`; every level is `none`, `mild` or `strong`
(`stylized` is an alias of `mild` for violence). Content never leaks upward: a `clean`
session never shows anything above the `clean` maximums. The validator rejects unknown
descriptors and any variant whose descriptors exceed the mode it is keyed to, and warns
when a supported mode would hide an item entirely.

Items carry `variants` keyed by mode plus a required `fallback`. The game picks the active
mode's variant when it exists and is allowed, else the fallback when allowed, else hides the
item (a billboard goes blank). First item type: billboard ads in `ads.v0.json`
(schema `ads.schema.v0.json`): text, a background colour and descriptors per variant.

## Map pack files
| File | Required | Contents |
|---|---|---|
| `road_graph.v0.json` | yes | Nodes and edges with polylines, plus pedestrian ways with kind and width; schema `road_graph.schema.v0.json`. |
| `terrain.json` + `terrain/*.png` | yes | 256 m chunks of 65×65 height samples at 4 m, height in the R and G bytes, min/max per chunk. |
| `water.v0.json` | no | Pre-triangulated water polygons with a surface height; schema `water.schema.v0.json`. |
| `buildings.v0.json` | no | Building footprints with height and ground height, roof pre-triangulated; schema `buildings.schema.v0.json`. |
| `ads.v0.json` | no | Billboard ads with per-mode variants; schema `ads.schema.v0.json`. |
| `parking.v0.json` | no | Parking lots (rings, kind, capacity, operator, stall direction, aisles inside, entrances, ground height) and street-side bays along edges; schema `parking.schema.v0.json`. |
| `vehicles.v0.json` | no | Vehicles merged after the base catalogue (same id replaces): body class, dimensions, mass and handling, palette, spawn weights by road group and hour, liveries with per-mode variants; schema `vehicles.schema.v0.json`. Any pack type may ship one. |
| `overrides.json` | no | Hand fixes applied on top of the generated data (empty for now). |
| `chunks/*.glb` + `chunks/build.json` | no | Pre-built meshes from the Godot pack builder. `build.json` holds a hash of the inputs; the game ignores chunks whose hash no longer matches and generates meshes at load instead. |

## Validating locally
```
cd tools
uv run python -m pack_tools.validate ../packs
```
Exit code is non-zero on any error. Each error names the pack and the field or file.
