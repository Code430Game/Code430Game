## 1. Format and validator
- [x] 1.1 `pack.schema.v1.json`, `character-palettes.schema.v1.json`, `character-presets.schema.v1.json`; README sections for v1, `content[]`, character and story packs
  - 2026-10-08: v1 is v0 plus `content[]` (eleven types), `character` and `story` sections (required for those pack types), `supported_modes` and `max_descriptors` required; v0 untouched. README gains Manifest versions, Namespaces and the registry, Character packs, Enabled packs.
- [x] 1.2 `validate.py`: schema by version, `content[]` path and type checks, dependency resolution within the root, descriptor and variant checks on every content file; tests on a v0 pack, a v1 pack, a bad path, a disallowed file, an unresolved dependency
  - 2026-10-08: `manifest_validator` picks v0 or v1 by `schema_version` (unknown versions named); `content_index` synthesises the v0 index from known file names; `validate_content` checks every indexed file (inside the pack, exists, parses, its type's schema, descriptor and variant checks through `item_content_checks`, presets against palettes); `validate_dependencies` across the root with `semver_satisfies` (exact, `^`, `~`, comparators, `*`): missing is a warning, out of range an error. 24 new pytest cases.

## 2. Loader
- [ ] 2.1 `pack_loader.gd`: discovery over `PackLocator.search_dirs`, manifest check, file rules, dependency order, namespaces and `resolve()`, `user://packs.cfg`, `--packs=`; tests on fixtures under `game/tests/fixtures/packs/`
- [ ] 2.2 Registry: `items(type)` with ContentMode filtering and refresh; billboards read ads from it; test that a disabled pack's ads vanish and a story pack's ads join the map's
- [ ] 2.3 Co-op: `manifest_summary()` over the set; `hello`/`welcome` carry the list; `mismatch_reason` names the first difference; tests

## 3. Character pack and UI
- [ ] 3.1 `packs/code430-characters`: palettes and six presets; `CharacterProfile` reads palettes through the registry with the built-in fallback; creator lists the pack presets under the player's own; tests
- [ ] 3.2 Pause menu "Packs" list with controller toggles, warnings for system packs and two map packs; Mac screenshots of the list and of the creator with pack presets

## 4. Verification
- [ ] 4.1 CI green (`scripts/ci-local.sh`): pack validator over `packs/`, gdUnit, pytest
- [ ] 4.2 Deck: package, deploy, benchmark; start-up time with the loader against the previous build; frame unchanged
- [ ] 4.3 **Stop: human opens the Packs list on the Deck, disables the character pack, restarts and sees the built-in palette**
