# Contributing to Code 430

Code 430 is built mostly by AI agents, and contributions from anyone, written by you, your
agent or both, are welcome. A PR is judged on its spec, its tests and CI, not on who or what
wrote it (see `AGENTS.md`).

## Start here

1. Read `VISION.md` (what we're building), `AGENTS.md` (the rules every contributor and agent
   follows) and `openspec/AGENTS.md` (how changes are specified).
2. Set up the project with the README: Godot 4.7.2 (pinned in `.godot-version`), Python 3.11+
   with `uv`, and the OpenSpec CLI (`npm install -g @fission-ai/openspec@latest`).
3. Pick something from `docs/open-work.md`. Every item there is a ready OpenSpec change under
   `openspec/changes/<id>/` with a proposal, tasks and spec deltas, written so an agent can pick
   it up cold.

If you use an agent, point it at this file, `AGENTS.md` and the change folder, and have it
start from a fresh context for each change.

## Claiming work

Open an issue titled `claim: <change-id>` (or comment on an existing one) before you start,
so two people don't build the same thing. If a claim sits for two weeks with no draft PR, it is
free again. Bug fixes don't need a claim; just open the PR.

New ideas start as a proposal: run `openspec` to scaffold a change in
`openspec/changes/<id>/`, make sure `openspec validate <id> --strict` passes, and open a PR
with only the proposal. The maintainer approves the direction before code is written.

## Making the change

- **Branch:** `change/<id>` for a change, `fix/<topic>` for a bug fix.
- **Tasks:** work through `tasks.md`. Tick a task only when its tests pass, and write what you
  found under it. Leave the maintainer's tasks (the Steam Deck benchmark and the "human tries
  it" gate) unticked.
- **Tests:** every behaviour gets a test. gdUnit4 for the game (`game/tests/`, no orphan nodes),
  pytest for the tools (`tools/tests/`). Run `scripts/ci-local.sh` before every push; set
  `GODOT_BIN` if `godot` isn't on your path. CI runs the same steps.
- **Screenshots:** anything visible needs before and after screenshots in the PR. The testbed
  takes them from the command line:
  ```
  godot --path game --resolution 1280x800 -- --benchmark=8 --preset=deck \
    --camera=px,py,pz,tx,ty,tz --screenshot=/tmp/shot.png
  ```
  Useful flags:
  - `--spawn=x,z`, `--time=HH`, `--tone=clean|gritty|dystopia`
  - `--traffic=0 --peds=0` to clear the streets
  - `--wanted=N` (plus `--police-log`) for chases
  - `--weapon=1|2 --shoot=N` for weapons
  - `--knockdown-every=S` (plus `--ambulance-log`) for ambulances
- **Performance:** the Steam Deck is the baseline (`AGENTS.md`, performance budget). Run
  `--benchmark=40 --autodrive --preset=deck` on main and on your branch, back to back on the
  same machine, and quote both in the PR. If you have a Deck, say so and include its numbers;
  otherwise the maintainer runs the Deck pass before the change closes. Ignore baseline
  numbers written in older `tasks.md` files.
- **Map data:** changes under `tools/osm_import` mean re-exporting the Ottawa pack (command in
  the README) and regenerating the golden fixture in `tools/tests/golden/`. Overpass can be
  slow or fail. Set `CODE430_OSM_CACHE` to a directory of your choice to cache its responses
  between runs.
- **Content:** original content only, with generic names (no real brands or trademarks).
  Anything that differs by tone reads `ContentMode` instead of hard-coding a tone.
- **Shared files:** some files are touched by several open changes (listed in
  `docs/open-work.md`). Keep edits there small and rebase often.

## Opening the PR

- Title in Conventional Commits form with the change id, for example
  `feat(add-unarmed-combat): punches and kicks (1.1-1.2)`.
- In the body say:
  - what changed and why;
  - which tasks are done;
  - the tests you added;
  - the local CI result;
  - benchmark numbers (main against your branch);
  - before and after screenshots.
- The maintainer reviews, plays it on the Deck when it needs that, and merges. Once a change
  is fully done and tried, it's archived with `openspec archive <id>`.

## Reporting bugs

Use the in-game reporter (it files a GitHub issue with a screenshot, the place and
diagnostics) or open an issue with the x, z from the HUD. Field notes that aren't changes yet
live in `docs/backlog.md`.
