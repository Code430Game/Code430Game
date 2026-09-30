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

Fields for tone modes (`supported_modes`, `max_descriptors`) arrive with the `add-content-modes` change.

## Validating locally
```
cd tools
uv run python -m pack_tools.validate ../packs
```
Exit code is non-zero on any error. Each error names the pack and the field or file.
