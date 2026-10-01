## 0. Preconditions
- [x] 0.1 Human approved the change on 2026-09-30; mode names clean / gritty / dystopia and the descriptor list shipped as proposed (rename is a data change)
- [x] 0.2 Pack manifest schema v0 exists

## 1. Schemas and docs
- [x] 1.1 `game/core/content/content-descriptors.v0.json` (closed list with levels; `stylized` aliases `mild` for violence)
- [x] 1.2 `docs/pack-format/tone-mode.schema.v0.json` and the three base mode files in `game/core/content/modes/`
- [x] 1.3 Pack manifest schema: `supported_modes[]` and `max_descriptors{}`
- [x] 1.4 Creator doc: tagging and variants with the billboard example (docs/pack-format/README.md)

## 2. Validator
- [x] 2.1 Descriptor validation for ads (unknown descriptor, level)
- [x] 2.2 Upward-leak check on mode-keyed variants
- [x] 2.3 Warning when a claimed supported mode hides an item
- [x] 2.4 pytest coverage on fixture packs

## 3. Runtime
- [x] 3.1 `ContentMode` autoload: modes, `current`, `allows()`, `flag()`, `pick_variant()`, settings persistence; pause menu Tone row; co-op host lock
- [x] 3.2 Warning when the pack does not list the active mode (pause status and log)
- [x] 3.3 gdUnit4 tests: default mode, persistence, allowances, variant selection, hidden items

## 4. Billboards
- [x] 4.1 Ad definition format: `ads.v0.json` with text, colour and descriptors per variant (textures later)
- [x] 4.2 `Billboards` node: posts and panels as MultiMeshes, Label3D text, deterministic per board id and session seed, refresh on mode change
- [x] 4.3 First-party ad set: eight ads with clean, dystopia and fallback variants in the Ottawa pack
- [x] 4.4 gdUnit4 tests: determinism, mode switch changes ads

## 5. Verification
- [ ] 5.1 **Stop: human drives past the same billboards in all three modes on the Deck**
