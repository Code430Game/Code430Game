## Context
First change in an empty repo. The human tests on a Steam Deck, so Linux exports and controller input must work from the first build.

## Goals / Non-Goals
- Goals: reproducible builds, enforced performance presets, working CI, pack manifest schema to build against.
- Non-Goals: any gameplay, the pack loader itself (Phase 4), the pack registry.

## Decisions
- **Godot version:** latest stable 4.x at bootstrap time (must be 4.4+ for built-in Jolt). Recorded in `.godot-version`; CI downloads that exact version.
- **Renderer:** Forward+ for both presets. The `deck` preset disables SDFGI, SSR, and volumetric fog by default, lowers shadow resolution, and enables FSR upscaling as an option.
- **Deck detection:** check OS is Linux and the display is 1280×800 and/or the `SteamDeck` environment variable is set; the player can override.
- **Testing:** gdUnit4 for Godot, pytest for tools.
- **CI export:** official Godot headless binary and export templates, cached by version.

## Risks / Trade-offs
- Deck detection heuristics may misfire → always allow a manual override in settings.
- Export templates are large → cache in CI.

## Open Questions
- **License** for code (recommendation: MIT, matching Godot) and for first-party assets (recommendation: CC BY-SA 4.0). Ask the human before adding LICENSE files.
- **Final project name.** "Streetlevel" is a working title.
