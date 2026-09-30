## 1. Repository
- [ ] 1.1 Create folder layout from AGENTS.md
- [ ] 1.2 Add `.gitignore` (Godot `.godot/`, exports, Python caches, OSM/DEM download caches)
- [ ] 1.3 Add `.godot-version` with the exact pinned version
- [ ] 1.4 Ask human about licenses; add LICENSE files once decided

## 2. Godot project
- [ ] 2.1 Create project in `game/`, Forward+ renderer, Jolt physics
- [ ] 2.2 Settings autoload with `deck` and `high` presets, auto-detection, manual override
- [ ] 2.3 Controller-first input map (move, look, sprint, jump, interact/enter vehicle, accelerate, brake, handbrake, pause)
- [ ] 2.4 Debug overlay: fps, frame time, draw calls, preset name (toggle with a button combo)
- [ ] 2.5 Empty test scene (ground plane, sky, light) that boots on the Deck

## 3. Pack manifest
- [ ] 3.1 Write `docs/pack-format/pack.schema.v0.json` (id, name, version, type, engine_api, dependencies, license, attribution, trusted)
- [ ] 3.2 Write `docs/pack-format/README.md` explaining the fields and data-only rules
- [ ] 3.3 Add a validator script in `tools/` and an example manifest in `packs/example/`

## 4. CI
- [ ] 4.1 GitHub Actions: pytest for `tools/`
- [ ] 4.2 GitHub Actions: gdUnit4 headless
- [ ] 4.3 GitHub Actions: headless Linux export uploaded as artifact
- [ ] 4.4 GitHub Actions: pack manifest validation

## 5. Docs
- [ ] 5.1 README: how to open the project, run tests, export, and copy a build to a Steam Deck (Desktop Mode, add as non-Steam game)
