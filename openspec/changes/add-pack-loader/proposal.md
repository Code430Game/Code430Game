# Change: Pack loader and pack format v1

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts). Phase 4 start; `add-story-pack` depends on it.**

**Needs the human's approval before implementation:** AGENTS.md says to ask before changing a
pack format that has shipped. v0 stays valid and keeps loading unchanged; v1 is a second schema
that only adds fields. Say so explicitly when approving.

## Why
The vision is a platform: the base game is a loader and the packs are the content. Today the
testbed loads exactly one map pack by hard-coded id (`play_testbed.gd` `PACK_ID`), billboards
read ads straight off `MapPack`, the creator's palettes live in GDScript constants, and co-op
verifies one manifest. Nothing can ship a character pack or a story pack. A loader that finds,
validates, namespaces and indexes every enabled pack is the step the next four changes stand on.

## What Changes
- **Pack format v1** (`docs/pack-format/pack.schema.v1.json`, `schema_version: 1`): everything in
  v0 plus a `content[]` index (`{"type", "path", "id"?}` per content file, for example
  `{"type": "ads", "path": "ads.v0.json"}`), a `character` section (palette and preset files)
  and a `story` section (map pack id the stories are placed on, mission files). `supported_modes`
  and `max_descriptors` become required in v1. v0 manifests still load; the loader infers a
  `content[]` index for them from the known v0 file names.
- **`PackLoader` autoload** (`game/core/packs/pack_loader.gd`): discovers pack folders in the
  `PackLocator` search dirs, validates each manifest against the schema for its version, rejects
  data-only packs containing any file outside the allowed list (`.tres`, `.res`, `.tscn`, `.scn`,
  `.gd`, `.gdshader`, `.cs`, `.pck`, `.zip` and anything unknown) and system packs that are not
  marked trusted, resolves `dependencies` by id and semver range, orders packs so dependencies
  load first, and loads each into its own namespace: every path a pack refers to is addressed as
  `pack_id:relative/path` and resolved by `PackLoader.resolve()`. A pack never overwrites another
  pack's or the base game's files; same-id packs in two search dirs take the most specific dir
  and log the shadowed one.
- **Content registry:** `PackLoader.items(type)` returns every item of a content type across the
  enabled packs, tagged with its `pack_id`, filtered by `ContentMode.allows_descriptors` and
  refreshed on `mode_changed`. Billboards move from `MapPack.ads` to `items("ads")`; the radio,
  missions and characters changes read the same registry.
- **Enabled set and settings UI:** `user://packs.cfg` lists enabled pack ids (all first-party
  packs enabled by default; a newly found pack is enabled and announced once). The pause menu
  gains a "Packs" row that opens a list: name, version, type, trusted warning for system packs,
  toggled with the controller; non-map changes apply on the next load, and the row says so. The
  active map pack is the one map pack in the enabled set; two enabled map packs is an error
  named in the list.
- **Pack set for co-op:** `PackLoader.manifest_summary()` returns the enabled packs sorted by id
  with version and content hash (`MapPack.content_hash` generalised to any pack dir). `Session`
  sends the whole list in `hello` and `welcome`; `mismatch_reason` names the first pack that
  differs, or is missing on either side.
- **First character pack** `packs/code430-characters` (type `character`, v1): the creator's skin,
  hair, cloth and shoe palettes and six named starting presets as data (`palettes.v1.json`,
  `presets.v1.json`, schemas in `docs/pack-format/`). `CharacterProfile` reads palettes from the
  registry when a character pack is enabled and keeps its built-in constants as the fallback, so
  nothing breaks with the pack disabled.
- **Validator** (`tools/pack_tools/validate.py`): v1 schema, per-type file rules, every
  `content[]` path must exist and match its type's schema, dependency ids must resolve within the
  packs root (warning otherwise), the descriptor and variant checks run on every content item
  that carries `descriptors` or `variants`, not only ads. Runs in CI as today.
- **Not in this change:** missions, radio stations, a pack browser or registry download (Phase 6),
  system pack loading of `.pck` files (manifest validation only; enabling one is refused with a
  "not supported yet" message), per-pack settings, hot reload.

## Impact
- Affected specs: `packs` (new), `project-foundation` (modified requirement: Pack Manifest Schema).
  The pending `content-modes` (Pack Mode Support) and `coop-session` (Pack Set Verification)
  requirements are satisfied over the whole pack set instead of one manifest; their text stands.
- Affected code: `game/core/packs/pack_loader.gd` (new, autoload in `project.godot`),
  `game/world/packs/map_pack.gd` (`content_hash` moves to the loader; `ads` removed),
  `game/world/packs/pack_locator.gd` (lists every pack, not one id), `game/world/dressing/billboards.gd`,
  `game/actors/character/character_profile.gd`, `game/core/net/session.gd`, `game/ui/pause/pause_menu.gd/.tscn`,
  `game/ui/packs/pack_list.gd/.tscn` (new), `game/scenes/play_testbed.gd` (`--packs=` flag to
  pin the enabled set for automation), `docs/pack-format/README.md`, `pack.schema.v1.json`,
  `character-palettes.schema.v1.json`, `character-presets.schema.v1.json`, `packs/code430-characters/`
  (new), `tools/pack_tools/validate.py`, tests (`test_pack_loader.gd`, `test_pack_validator.py`).
- Performance: load-time only (manifest parsing and a directory walk per pack at start; the
  content hash is computed once). No per-frame work. Deck measured to confirm start-up time and
  an unchanged frame.
- Authority: the host's enabled set is the session's; a client whose set differs is refused.
  Tone: the registry filters through `ContentMode`; it never widens what a mode allows.
