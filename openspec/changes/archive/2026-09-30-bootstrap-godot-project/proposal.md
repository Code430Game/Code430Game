## Why
There is no project yet. Every later change needs a pinned engine, a predictable layout, CI that builds for Linux (Steam Deck), and graphics presets that enforce the Deck performance budget from day one.

## What Changes
- Create the Godot 4.x project under `game/`, pinned to the latest stable version, recorded in `.godot-version`.
- Create the repo layout defined in AGENTS.md, including `tools/`, `packs/`, and `docs/pack-format/`.
- Add `deck` and `high` graphics presets with a settings system that selects `deck` automatically on Steam Deck hardware.
- Add a controller-first input map (Steam Deck / Xbox layout), with keyboard and mouse as secondary.
- Add a debug overlay showing frame time, draw calls, and active preset.
- Add CI (GitHub Actions): Python tool tests, gdUnit4 tests, headless Linux export as a build artifact.
- Add a `pack.json` manifest schema v0 (JSON Schema) and a CI check that validates any manifests under `packs/`.

## Impact
- Affected specs: `project-foundation` (new).
- Affected code: entire repo (initial).
- No user-facing gameplay yet.
