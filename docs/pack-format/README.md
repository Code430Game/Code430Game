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

## Manifest versions

Two manifest schemas exist. `pack.schema.v0.json` is frozen: a v0 manifest keeps validating
and loading unchanged. `pack.schema.v1.json` is v0 plus a `content[]` index and the
`character` and `story` sections, with `supported_modes` and `max_descriptors` required. The
loader picks the schema by `schema_version` and refuses any other value, naming the folder
and the version. A v0 pack gets a synthesised content index from its known file names
(`ads.v0.json` is `ads`, `vehicles.v0.json` is `vehicles`, and so on), so systems that read
the content registry see v0 and v1 packs alike.

### v1 additions

| Field | Required | Meaning |
|---|---|---|
| `schema_version` | yes | `1`. |
| `supported_modes` | yes | As in v0, now required. |
| `max_descriptors` | yes | As in v0, now required (may be `{}`). |
| `content` | no | Index of the pack's content files: `[{"type": "ads", "path": "ads.v0.json"}, ...]`. Types: `ads`, `vehicles`, `weapons`, `factions`, `turf`, `lap`, `radio`, `music`, `palettes`, `presets`, `missions`. Every path is relative to the pack folder, inside it, and must validate against the type's schema. |
| `character` | character packs | `palettes` (path of a `character-palettes.schema.v1.json` file) and optional `presets` (`character-presets.schema.v1.json`). List the same files in `content[]` as `palettes` and `presets`. |
| `story` | story packs | `map` (id of the map pack the stories are placed on; also a dependency) and `missions` (paths, add-story-pack). |

### Namespaces and the registry

Every file a pack refers to is addressed as `pack_id:relative/path` and resolved by the
loader only inside that pack's folder; `..` and absolute paths are refused. Nothing in a
pack is ever copied under the game's own files, and a pack never overwrites another pack's.
The content registry (`PackLoader.items(type)`) returns every item of a content type across
the enabled packs, each tagged with its `pack_id` and `source` file, filtered by the active
tone mode's descriptor limits. Billboards draw their ads from it, so a story pack can add ads
to the map it depends on.

### Character packs

A character pack ships palettes (`skin`, `hair_colour`, `cloth`, `shoes`: named colours in
0..1 RGB) and named presets (profiles whose colour fields index the pack's palettes). Profiles
store indices, so a pack that replaces the palettes keeps the built-in colours first, in the
built-in order, and appends; a saved character then still looks right. With no character pack
enabled the game uses its built-in palettes. The first-party `code430-characters` pack is the
reference.

### Enabled packs

`user://packs.cfg` lists the enabled pack ids; first-party packs are enabled by default and a
newly found pack is enabled and announced once. Map packs are not toggled there: the active
map is chosen by `--pack=<id>`, the `[map] pack` setting, or the Ottawa default, and the
other map packs stay available. The Packs tab in the pause menu toggles the rest; changes
apply at the next load. For co-op the host's enabled set is the session's: `hello` and
`welcome` carry every enabled pack's id, version and content hash, and a join is refused
naming the first pack that differs or is missing on either side.

## Manifest fields (`pack.schema.v0.json`)

| Field | Required | Meaning |
|---|---|---|
| `schema_version` | yes | Always `0` for this schema. |
| `id` | yes | Unique id, lowercase with dots, for example `code430.ottawa-centretown`. |
| `name` | yes | Display name. |
| `version` | yes | Semantic version, for example `0.1.0`. Bumped by the rules in [Pack versions](#pack-versions). |
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
| `build` | no | Written by the importer with `--build-stamp`: `importer` (the game commit it ran from, `-dirty` when `tools/osm_import` had local changes) and `inputs` (per layer, the OpenStreetMap snapshot time or the input file's name), so a diff shows whether the data or the code changed. |

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
| `buildings.v0.json` | no | Building footprints with height and ground height, roof pre-triangulated; houses carry a `house` hint (type, front wall, door, setback, party walls); schema `buildings.schema.v0.json`. |
| `ads.v0.json` | no | Billboard ads with per-mode variants; schema `ads.schema.v0.json`. |
| `parking.v0.json` | no | Parking lots (rings, kind, capacity, operator, stall direction, aisles inside, entrances, ground height) and street-side bays along edges; schema `parking.schema.v0.json`. |
| `yards.v0.json` | no | Per house: front lawn, backyard and side-yard polygons, a path from the door, the lawn's frontage along the street; fence lines where backyards meet; schema `yards.schema.v0.json` (update-houses-and-yards). |
| `vehicles.v0.json` | no | Vehicles merged after the base catalogue (same id replaces): body class, dimensions, mass and handling, palette, spawn weights by road group and hour, liveries with per-mode variants; schema `vehicles.schema.v0.json`. Any pack type may ship one. |
| `turf.v0.json` | no | Ground a faction holds: rings in local metres, optionally the faction id and a centre; schema `turf.schema.v0.json` (add-hostile-gang). |
| `factions.v0.json` | no | Factions merged after the base game's (`game/core/content/factions.v0.json`, same id replaces): crew size, look, car, per-mode weapon variants by weapon id, threat and heat tunables; schema `factions.schema.v0.json`. Any pack type may ship one. |
| `overrides.json` | no | Hand fixes applied on top of the generated data. A `turf` key (the same shape as `turf.v0.json`'s `turfs`) is written out as `turf.v0.json` at export, so a city pack can place a faction's turf by hand. |
| `chunks/*.glb` + `chunks/build.json` | no | Pre-built meshes from the Godot pack builder. `build.json` holds a hash of the inputs; the game ignores chunks whose hash no longer matches and generates meshes at load instead. |

## Validating locally
```
cd tools
uv run python -m pack_tools.validate ../packs
```
Exit code is non-zero on any error. Each error names the pack and the field or file.

The validator also checks sizes against GitHub's limits: a file over 40 MB is a warning and one
over 90 MB an error (GitHub refuses files over 100 MB), and a pack over 250 MB is a warning.
`chunks/` isn't counted. When a district gets near these, split it.

## Pack versions
A pack's `version` tells packs built on it what changed. Compare with the last release:

| Bump | When |
|---|---|
| major | Something a pack built on this one can break on: an id is removed or renamed (buildings, turf, ads, parking, yards, ...), the map origin moves, or `engine_api` changes. |
| minor | New ids, nothing removed: a re-export with more buildings, a new ad. |
| patch | Files changed but no ids were added or removed: a wrong height, a moved bench. |

While a pack is `0.x`, the minor number counts as the major one, as semver's `^0.2` does: a
breaking change goes from `0.2.x` to `0.3.0`, anything else from `0.2.0` to `0.2.1`. Packs that
depend on a map name a range (`"^0.2"`) so they get its fixes and new content but not its
breaking releases. Changing only `version` or `build` in `pack.json` isn't a content change.

```
cd tools
uv run python -m pack_tools version check ../packs/centretown --ref centretown-v0.2.0 --tag centretown-v0.2.1
```
`--ref` is the last release's git tag (or `--old DIR` a copy of it); leave both out for a first
release. `--tag` checks the tag being made reads `<pack folder>-v<version>`. It fails when the
pack changed without the bump it needs and says which version would do.
