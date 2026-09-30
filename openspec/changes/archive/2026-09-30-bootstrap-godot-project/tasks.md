## 1. Repository
- [x] 1.1 Create folder layout from AGENTS.md
- [x] 1.2 Add `.gitignore` (Godot `.godot/`, exports, Python caches, OSM/DEM download caches)
- [x] 1.3 Add `.godot-version` with the exact pinned version
- [x] 1.4 Ask human about licenses; add LICENSE files once decided (decided 2026-09-30: MIT code, CC BY-SA 4.0 assets)

## 2. Godot project
- [x] 2.1 Create project in `game/`, Forward+ renderer, Jolt physics
- [x] 2.2 Settings autoload with `deck` and `high` presets, auto-detection, manual override
- [x] 2.3 Controller-first input map (move, look, sprint, jump, interact/enter vehicle, accelerate, brake, handbrake, pause)
- [x] 2.4 Debug overlay: fps, frame time, draw calls, preset name (toggle with a button combo)
- [x] 2.5 Empty test scene (ground plane, sky, light) that boots on the Deck

## 3. Pack manifest
- [x] 3.1 Write `docs/pack-format/pack.schema.v0.json` (id, name, version, type, engine_api, dependencies, license, attribution, trusted)
- [x] 3.2 Write `docs/pack-format/README.md` explaining the fields and data-only rules
- [x] 3.3 Add a validator script in `tools/` and an example manifest in `packs/example/`

## 4. CI
- [x] 4.1 GitHub Actions: pytest for `tools/`
- [x] 4.2 GitHub Actions: gdUnit4 headless
- [x] 4.3 GitHub Actions: headless Linux export uploaded as artifact (export verified locally 2026-09-30; CI itself runs on first push to GitHub)
- [x] 4.4 GitHub Actions: pack manifest validation

## 5. Docs
- [x] 5.1 README: how to open the project, run tests, export, and copy a build to a Steam Deck (Desktop Mode, add as non-Steam game)
