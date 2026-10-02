# Design: pack loader

## Two schemas, one loader
- `pack.schema.v0.json` is frozen. `pack.schema.v1.json` is a copy with `schema_version: 1`,
  the `content[]` index, the `character` and `story` sections, and `supported_modes` and
  `max_descriptors` required. The loader picks the schema by `schema_version` and refuses
  anything else with the version named.
- A v0 pack gets a synthesised index: `road_graph.v0.json` → `map`, `ads.v0.json` → `ads`,
  `buildings.v0.json` → `buildings`, and so on from a table in the loader. New content types
  exist only in v1, so v0 packs are never asked for things they cannot describe.
- Manifest validation in the game is a small hand-written check (required fields, enum values,
  id pattern, version parse), not a JSON Schema engine: the full schema check is the validator's
  job in CI and the game only has to refuse broken packs readably.

## Namespaces
- `PackLoader.resolve("code430.ottawa-centretown:chunks/build.json")` returns an absolute path,
  or "" with a logged error when the pack is not enabled or the path escapes the pack folder
  (`..` and absolute paths are rejected). Nothing in a pack is ever copied under `res://`.
- `MapPack.load(dir)` is unchanged; `play_testbed.gd` asks the loader for the enabled map pack's
  dir instead of `PackLocator.find_pack(PACK_ID)`. `--packs=id,id` pins the enabled set for a
  run without touching `user://packs.cfg`, which keeps benchmarks and screenshots reproducible.

## Registry
- `items(type) -> Array[Dictionary]`: each item is the JSON object plus `pack_id` and `source`
  (the file it came from). Items with `descriptors` are dropped when
  `ContentMode.allows_descriptors` says no; variant choice stays with `ContentMode.pick_variant`
  so the no-upward-leak rule lives in one place. The registry caches per type and clears on
  `mode_changed` and on load.
- Billboards call `PackLoader.items("ads")` once at setup; a story pack can therefore add ads to
  a map it depends on, which is the first cross-pack content case.

## Dependencies and order
- Semver ranges: `^1.2`, `~1.2`, `>=1.0 <2.0`, exact. A missing or out-of-range dependency
  disables the dependent pack with a message naming both packs and the range; it does not stop
  the game.
- Load order is a topological sort by dependencies, ties by id, so the order is deterministic
  and the pack set hash is too.

## Co-op
- `manifest_summary()` is the sorted list `[{"id", "version", "hash"}]`. `hello` and `welcome`
  carry the list; `Session.mismatch_reason` walks both lists together and returns the first
  difference: `pack X: host 1.2.0, you 1.1.0`, `pack X missing on your side`, `pack Y not
  enabled on the host`. Hashes skip `chunks/` as they do today.

## Character pack
- `palettes.v1.json`: named colour lists for `skin`, `hair_colour`, `cloth`, `shoes`.
  `presets.v1.json`: named profiles. `CharacterProfile` loads palettes through the registry at
  `_ready` of the first user and falls back to its constants; profile indices stay indices, so a
  saved character made with the built-in palette still looks right as long as the pack's palette
  is a superset, which the first-party pack guarantees by starting with the built-in colours.
- Pedestrians use the same palettes, so a palette-only pack already changes the look of the city.

## Pause menu packs list
- One row per pack: `[x] Ottawa Centretown  map  0.3.0`, toggled with accept, navigated with the
  stick, works with the Deck's controller in Game Mode. System packs show "runs code: trusted"
  in a warning colour and cannot be enabled in this change. Map packs show "active map" and
  cannot be disabled while the session is in that map. A footer says "changes apply at next load".
