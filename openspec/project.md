# Project Context

## Purpose
Code 430 (codename) is a free, open-source, AI-built open-world crime game in the spirit of GTA III–IV, set on real city road networks imported from OpenStreetMap. The base game is a platform: community map, character, and story packs are the real content. Same city, author-chosen tone (`clean`, `gritty`, `dystopia`), and small-group co-op for up to 4 players. See `VISION.md` for the full vision and `AGENTS.md` for the rules every agent follows. This file is a summary; it does not replace either.

## Tech Stack
- Godot 4.x, pinned in `.godot-version` (target: 4.7.2-stable). Forward+ renderer, Jolt physics.
- GDScript with static typing for all game code. GDExtension (C++) only for profiled hot paths.
- Python 3.11+ with `uv` for offline tools under `tools/` (OSM import, validators).
- gdUnit4 for game tests, pytest for tools.
- GitHub Actions for CI: tool tests, gdUnit4, headless Linux export, pack manifest validation.

## Project Conventions

### Code Style
- Static typing everywhere in GDScript. One-line doc comment on public functions. Short "approach" comment at the top of complex algorithm files.
- No magic numbers in systems; tunables live in config resources or pack data.
- Python: `ruff` formatting, type hints, tools runnable headless.

### Architecture Patterns
- Repo layout is fixed in `AGENTS.md` (`game/`, `tools/`, `packs/`, `docs/pack-format/`, `openspec/`).
- 1 Godot unit = 1 metre, Y up. Map coordinates are UTM 18N (EPSG:32618) offset to a local origin stored in the map pack manifest.
- World systems are chunked (256 m) and produce LODs. Two graphics presets, `deck` and `high`, from day one.
- Data-only packs contain no Godot resource formats and no scripts. System packs carry code, are `.pck`, and are marked trusted.
- Gameplay systems from Phase 2 on declare an authority model (co-op readiness) and read tone-mode flags instead of hard-coding tone.

### Testing Strategy
- Every system has tests. Pipeline outputs have golden-file tests on a small fixture area. Generation is deterministic: same input and seed give byte-identical output.
- Do not tick a task in `tasks.md` unless its tests pass.

### Git Workflow
- `main` is the integration branch. Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`) referencing the OpenSpec change id, for example `feat(bootstrap-godot-project): add deck preset`.
- One OpenSpec change per coherent capability; split anything larger than one reviewable PR.
- Commit at the end of each working round.

## Domain Context
- Starter district: Ottawa Centretown, ByWard Market / Lowertown, and a stretch of Highway 417 with at least one interchange.
- OSM gives road topology (connectivity, one-ways, lanes, layers) but weak geometry; the import pipeline turns it into drivable meshes without breaking topology.
- Canadian conventions: right-hand traffic, km/h.
- Steam Deck is the performance baseline: 1280×800, 33.3 ms frame-time floor, 25 ms target.

## Important Constraints
- Licensing: OSM data is ODbL and must be credited in every map pack. Never commit raw `.osm.pbf` or DEM tiles. Code and asset licenses are an open question for the human.
- Content policy: mature content is in scope; sexual content involving minors, real identifiable living people, and real-world-harm instructions are never in scope. No Rockstar names, logos, assets, or close parodies.
- Ask the human before: licenses, paid services or dependencies, changing a shipped pack format, deleting data files you did not create, upgrading Godot.

## External Dependencies
- OpenStreetMap via Overpass API (development) or Geofabrik `.osm.pbf` extracts (reproducible builds).
- Elevation: Natural Resources Canada HRDEM / CDEM.
- Godot export templates, downloaded in CI by pinned version.
- gdUnit4 addon.
