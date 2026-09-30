<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# AGENTS.md — Project Constitution

Every agent (and human) working in this repo follows these rules. If a task conflicts with this file, stop and raise it instead of working around it. Read VISION.md for the why.

## Workflow
- **Spec first.** All non-trivial work goes through OpenSpec: proposal → specs → design → tasks → implement → archive. Changes live in `openspec/changes/<change-id>/`. Run `openspec validate <change-id> --strict` before implementing.
- **Small changes.** One OpenSpec change per coherent capability. If a change grows past what one PR can review, split it.
- **Clean context.** Start implementation of each change with a fresh context. Read the change folder, this file, and only the code you need.
- **Tasks are truth.** Tick tasks in `tasks.md` as you finish them. Do not mark a task done if its tests do not pass.
- **Ask before:** choosing or changing licenses, adding any paid service or dependency with fees, changing a pack format that has already shipped, or deleting data files you did not create.

## Engine and languages
- **Godot 4.x**, pinned to one exact stable version recorded in `.godot-version`. Do not upgrade without an OpenSpec change.
- **GDScript** is the default for all game code, with static typing everywhere (`var speed: float`, typed function signatures).
- **GDExtension (C++)** only for proven hot paths, with a profiling result attached to the proposal.
- **Python 3.11+** for offline tools (`tools/`). Use `uv` or a pinned `requirements.txt`. Tools must be runnable headless in CI.
- **Physics:** Jolt (built into Godot 4.4+).
- Units: 1 Godot unit = 1 meter. Y is up. Map coordinates are projected (UTM zone 18N, EPSG:32618, for Ottawa) and offset to a local origin stored in the map pack manifest.

## Repo layout
```
game/                 Godot project (res:// root)
  core/               engine-level systems (streaming, pack loader, input, settings)
  world/              roads, terrain, city generation at runtime
  actors/             player, vehicles, NPCs
  ui/
  tests/              gdUnit4 tests
tools/
  osm_import/         Python OSM → road graph pipeline
packs/                first-party packs (each is a self-contained pack folder)
docs/
  pack-format/        schemas and docs for every pack type
openspec/             specs and changes
.github/workflows/    CI
```

## Performance budget (Steam Deck is the baseline)
- Resolution 1280×800. Frame-time floor 33.3 ms (30 fps), target 25 ms (40 fps).
- Two graphics presets from day one: `deck` and `high`. Every rendering feature must declare its behavior in both.
- No SDFGI in the `deck` preset. Prefer baked lighting, VoxelGI only if profiled within budget.
- Every mesh generator must produce LODs. Every world system must support chunked streaming (256 m chunks).
- A change that regresses Deck frame time must say so in its proposal and justify it.

## Pack rules (security matters)
- **Data-only packs** (map, character, story) contain only: JSON/YAML, glTF/GLB, PNG/JPG/KTX2 textures, OGG/WAV audio, plain text. **No Godot resource formats** (`.tres`, `.res`, `.tscn`, `.scn`) and no scripts, because Godot resources can embed executable scripts. The loader must reject them.
- **System packs** may contain code, are distributed as `.pck`, must be marked `"trusted": true` in their manifest, and the game warns the player before enabling them.
- Packs load into their own namespace and must never overwrite base game files.
- Every pack has a `pack.json` manifest with a schema version. Schemas live in `docs/pack-format/` and are validated in CI.

## Map data and licensing
- Road and map data from OpenStreetMap is licensed under ODbL. Every map pack credits "© OpenStreetMap contributors" in its manifest and in-game credits. Derived map databases are shared under ODbL.
- Elevation data from Natural Resources Canada (or other open sources) is credited per its license.
- Never commit raw `.osm.pbf` extracts or DEM tiles to git. Tools download and cache them; record the source URL and timestamp in the generated output.
- No Rockstar (or other studio) names, logos, assets, radio stations, or close brand parodies.

## Co-op readiness (from Phase 2 on)
- The game targets small-group co-op (up to 4 players). Every proposal for a gameplay system (player, vehicles, traffic, pedestrians, missions, economy) states its **authority model**: which peer owns each piece of state, what is replicated, and what happens when the owner leaves.
- Do not write gameplay code that assumes exactly one player. No global "the player" singleton; look players up by peer id or slot.
- Physics is not deterministic across machines. Design for host-authoritative world simulation with peer-owned player bodies, not lockstep.
- Networking itself lands in its own change. Until then, single-player is the only tested path; the rules above keep the retrofit small.

## Tone modes and content tagging
- Every authored content item (billboard ads, dialogue, NPC archetypes, radio, missions, vehicle liveries) carries **content descriptors** from the shared list in `docs/pack-format/` (for example `violence`, `drugs`, `sex_work`, `profanity`, `gore`).
- Content that should differ by tone provides **per-mode variants** or a fallback. Missing variants degrade to the fallback; they never crash and never leak a higher-rated variant into a lower-rated mode.
- Systems read the active mode's flags (for example `allows("violence")`) instead of hard-coding a tone. No mode-specific `if` chains scattered through gameplay code; tone decisions live in the mode definition and the content data.
- The default mode is `gritty`. Other modes are supported but not promoted until the tone system has shipped.

## Content policy
- The base game is Mature: violence, drugs, sex work, homelessness, mental illness, crime, profanity are all in scope.
- Never: sexual content involving minors; real, identifiable living people (by name or likeness); content that facilitates real-world harm (e.g., working drug synthesis instructions).
- The pack registry enforces the same rules.

## Code quality
- Every system has tests: `pytest` for tools, gdUnit4 for game code. Pipeline outputs have golden-file tests on a small fixture area.
- Deterministic generation: the same input data and seed must produce byte-identical output.
- No magic numbers in systems. Tunables go in config resources or pack data.
- Public functions get a one-line doc comment. Complex algorithms get a short explanation of the approach at the top of the file.
- Log clearly, fail loudly in tools, degrade gracefully in the game.

## Commits and PRs
- Conventional Commits (`feat:`, `fix:`, `chore:` …), referencing the OpenSpec change id.
- AI-authored contributions are welcome and expected. PRs are judged on specs, tests, and CI, not on who or what wrote them.
