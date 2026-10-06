> **History.** The note that started the project on 2026-09-30, kept for the record. New contributors start at `CONTRIBUTING.md`.

# HANDOFF — Start Here (for the local agent)

You are starting a new project from zero. A human planned it with Claude in chat; this file hands it to you.

## Read first
1. `VISION.md` — what we're building and why.
2. `AGENTS.md` — the rules. Follow them exactly.
3. `openspec/changes/bootstrap-godot-project/` — your first change.
4. `openspec/changes/add-osm-road-import/` — your second change.

## Setup steps
1. `git init` in the project root (if not already a repo). Keep `VISION.md`, `AGENTS.md`, `HANDOFF.md` at the root.
2. Install OpenSpec if missing: `npm install -g @fission-ai/openspec@latest`.
3. Run `openspec init` and select Claude Code (or whatever tool you are). If init creates its own project-context file, fill it with a short summary of `VISION.md` and a pointer to `AGENTS.md`. Do not duplicate the whole constitution.
4. The two prepared change folders under `openspec/changes/` were written by hand. If the installed OpenSpec version expects a different layout or headings, adapt them to that format without changing their meaning.
5. Run `openspec validate bootstrap-godot-project --strict` and `openspec validate add-osm-road-import --strict`. Fix format issues until both pass.
6. Show the human `openspec list` and summarize both changes in a few lines before writing any code.

## Then implement, in order
1. **bootstrap-godot-project.** Stop after it's done and tell the human how to run the project and the CI build, and how to copy a Linux build to a Steam Deck.
2. **add-osm-road-import.** Work through `tasks.md` section by section. After section 3 (graph validation), show the human the validation report before generating meshes. After the drivable testbed works, stop so the human can test on the Deck.

## Stop and ask the human when
- A decision is listed under "Open Questions" in a design.md.
- You need to pick a license, a paid service, or anything with a cost.
- A task can't meet the Deck performance budget.
- Real OSM data contradicts an assumption in the design (e.g., ramp tagging is messier than expected). Report what you found with examples.

## About the human
- Owns the vision; wants the game fully AI-coded.
- Uses OpenSpec at work, so knows the workflow.
- Tests mostly on a Steam Deck. Give Deck-friendly instructions (Linux builds, controller input, Desktop Mode file copying).
- Cares most about roads that make sense. The road import is the heart of Phase 1; don't rush it.

## Definition of done for this session
Both changes validated. Bootstrap implemented and CI green. Road import at least through graph validation, with a report showing the Ottawa district's road network connectivity.

## Addendum (local agent, 2026-09-30)
- The codename is **Code 430**. VISION.md updated; "Streetlevel" is retired as the working title.
- Two new proposals were added after the human asked for them: `add-content-modes` (tone modes: clean / gritty / dystopia, tagged content, tone-aware billboards) and `add-coop-multiplayer` (up to 4 players, drop-in co-op). Both are **proposed, not approved**, and neither is scheduled before Phases 0–1. Read their `design.md` for the cost assessment.
- AGENTS.md gained two sections, "Co-op readiness" and "Tone modes and content tagging", so Phase 2+ work is built to accommodate both without a rewrite.
- Godot is not installed on the dev Mac. Latest stable at this date is `4.7.2-stable`; that is the intended pin for `.godot-version`.
