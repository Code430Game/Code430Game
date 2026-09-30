## 0. Preconditions
- [ ] 0.1 Human approves mode names and the closed descriptor list
- [ ] 0.2 Pack manifest schema v0 exists (from `bootstrap-godot-project`)

## 1. Schemas and docs
- [ ] 1.1 `docs/pack-format/content-descriptors.v0.json` (closed list with levels)
- [ ] 1.2 `docs/pack-format/tone-mode.schema.v0.json` and the three base mode files
- [ ] 1.3 Pack manifest schema: add `supported_modes[]` and `max_descriptors{}`
- [ ] 1.4 Creator doc: how to tag content and write variants, with the billboard example

## 2. Validator
- [ ] 2.1 Descriptor validation for pack items (unknown descriptor, level)
- [ ] 2.2 Upward-leak check on mode-keyed variants
- [ ] 2.3 Warning when a claimed supported mode has items with nothing allowed
- [ ] 2.4 pytest coverage for all of the above on a fixture pack

## 3. Runtime
- [ ] 3.1 `ContentMode` autoload: load mode files, `current`, `allows()`, `pick_variant()`, settings persistence
- [ ] 3.2 Warning on unsupported pack at session start
- [ ] 3.3 gdUnit4 tests: default mode, persistence, variant selection matrix, leak prevention

## 4. Billboards
- [ ] 4.1 Ad definition format in map and story packs
- [ ] 4.2 `Billboard` node with deterministic per-id selection and LOD-friendly material swap
- [ ] 4.3 First-party ad set: at least three ads with `clean`, `dystopia`, and fallback variants
- [ ] 4.4 gdUnit4 tests: determinism, mode switch changes ads

## 5. Verification
- [ ] 5.1 **Stop: human drives past the same billboards in all three modes on the Deck**
