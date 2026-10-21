# Code 430

A free, open-source, AI-built open-world crime game framework in the spirit of GTA III–IV, set on real city road networks from OpenStreetMap. Codename Code 430. Read `VISION.md` for the why and `AGENTS.md` for the rules. Want to help? See `CONTRIBUTING.md` and the list of ready work in `docs/open-work.md`.

Status (2026-10-06): a playable sandbox in one district, central Ottawa, built from OpenStreetMap and NRCan elevation. It has:
- roads, bridges, buildings, water, parking and garages;
- traffic and pedestrians, with a day-night cycle;
- an on-foot player with a character creator, and cars to drive or take, each with a radio;
- weapons and fists in three tone modes, with a weapon wheel;
- police with a wanted level and a helicopter, and ambulances;
- an in-game issue reporter;
- LAN co-op (in progress).

Not yet built: missions, a pack browser, and an economy. `docs/open-work.md` lists what is next.

## Requirements
- Godot `4.7.2-stable` (see `.godot-version`). macOS: `brew install --cask godot`. Others: https://godotengine.org/download.
- Python 3.11+ and [uv](https://docs.astral.sh/uv/) for the tools.

## Get the packs
The Ottawa map lives in its own repository,
[Code430Packs/Location-OttawaOnCa](https://github.com/Code430Packs/Location-OttawaOnCa). The
game pins the release it uses in `packs.lock.json`; fetch it once after cloning, and again
when the lock changes (CI and packaging do this themselves):
```
scripts/fetch-packs.sh
```

## Open the project
```
godot --path game --editor
```
Or open `game/project.godot` from the Godot project manager. Press F5 to run the play testbed: it loads the Ottawa map pack from `packs/`, builds the city, and puts you on foot beside a car on the Queensway.

For a quick try of a change there is also the Double Cross proving ground, a small generated test district with one of everything and a figure-eight track: `godot --path game -- --pack=code430.proving-ground --drive` starts on its start line (or save the pack under `[map] pack` in `user://settings.cfg`). It is rebuilt from `tools/proving_ground` by `scripts/regen-proving-ground.sh`; CI checks the committed pack matches.

Controls for controller and keyboard are in `docs/controls.md`, generated from the game's input map; the pause menu's Controls tab shows the same list and rebinds them.

Benchmark from the command line (vsync off, prints a frame-time summary and quits):
```
godot --path game -- --benchmark=60 --autodrive --preset=deck --screenshot=/tmp/shot.png   # --drive starts in the car without autodrive
```
More testbed flags: `--traffic=N` caps traffic cars (0 disables), `--spawn=x,z` starts on the nearest road to a local coordinate (`--spawn=x,y,z` puts the player on foot exactly there, such as a garage floor), `--topdown=<height>` looks straight down, `--graph` shows the road graph overlay, `--telemetry` prints the car state every second, `--junction-report` prints junctions whose surface bulges into the grass, leaves part of a road uncovered, falls back to a hull or has terrain above it, with x, z (headless: `godot --headless --path game -s res://world/build/junction_report.gd`).

## Build a map pack
Map packs are built in their own repositories (start one from
[Code430Packs/PackTemplate](https://github.com/Code430Packs/PackTemplate)). From this
checkout, rebuild a district of one of them with its region file:
```
cd tools
uv run python -m osm_import --region <Location repo>/regions/centretown.json \
  --pack-out <Location repo>/packs/centretown --pack-version <next version> --build-stamp
```
That fetches OpenStreetMap roads, water, and buildings plus NRCan elevation data (cached, gitignored; set `CODE430_OSM_CACHE=/path` to keep the cache on a shared volume, or pass `--cache-dir`), and writes the road graph, terrain heightmaps, water and building files, manifest, and validation report. Optionally pre-build the chunk meshes as GLB so the game loads faster:
```
godot --headless --path game -s res://world/build/pack_builder.gd -- code430.ottawa-centretown
```
To play a new release here, tag it in the pack's repository, then update its entry in
`packs.lock.json` (tag, commit, sha256 from the release's `.sha256` file) and run
`scripts/fetch-packs.sh`.

Debug overlay: press F3, or hold Back (View) and press X on a gamepad. It shows fps, frame time, draw calls, and the active preset.

## Run the tests
Godot (gdUnit4, vendored under `game/addons/gdUnit4`):
```
cd game
godot --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests
```
The editor also has a gdUnit4 panel for running tests interactively.

Python tools:
```
cd tools
uv sync
uv run pytest
uv run python -m pack_tools ../packs      # validate pack manifests
```

## Export a Linux build
Install the export templates for the pinned version once (Editor > Manage Export Templates), then:
```
mkdir -p build/linux
godot --headless --path game --export-release "Linux" ../build/linux/code430.x86_64
```
CI does the same on every push to `main` and uploads `build/linux` as an artifact named `code430-linux-<sha>`.

## Put a build on a Steam Deck
With SSH enabled on the Deck and your key installed, `scripts/package-linux.sh && scripts/deploy-deck.sh` exports and syncs the build to `~/Games/code430` on the Deck in one go. A benchmark can then be run remotely while the Deck is in Game Mode:
```
ssh deck@steamdeck.local 'cd ~/Games/code430 && DISPLAY=:0 ./code430.x86_64 -- --benchmark=40 --autodrive --preset=deck'
```
Or let `scripts/deck-bench.sh` do all of it: package, deploy, run the benchmark N times in Game Mode (it outlives the SSH session through `systemd-run`) and print the measured render times, with medians. It can compare two refs (`--ref main --ref change/x`) and note the result under a task (`--change <id> --task 3.1`). `--dry-run` shows what it would do, and `--help` lists the flags. It won't start while the game is running on the Deck.
To get it into the Game Mode library without Desktop Mode, `uv run scripts/deck-add-shortcut.py` writes the non-Steam shortcut over SSH; restart the Deck afterwards and it shows up under the Non-Steam tab.

Manual route:
1. Run `scripts/package-linux.sh` (or download the `code430-linux-*` artifact from GitHub Actions). You get `build/linux/` with `code430.x86_64`, `code430.pck`, and a `packs/` folder. The game looks for packs next to the executable, in `~/.local/share/Code 430/packs`, or in the repo when run from the editor. Every pack found is listed on the pause menu's Packs tab, where data-only packs (characters, stories) can be enabled or disabled for the next load; `--packs=id,id` pins the enabled set for one run. The format is documented in `docs/pack-format/README.md`.
2. On the Deck, switch to Desktop Mode (Power menu > Switch to Desktop).
3. Copy both files to the Deck, for example with a USB stick, or from a Mac over the network:
   ```
   scp -r build/linux/ deck@steamdeck.local:~/Games/code430/
   ```
   (Enable SSH on the Deck first: in Konsole, `passwd` then `sudo systemctl enable --now sshd`.)
4. In Konsole on the Deck: `chmod +x ~/Games/code430/code430.x86_64`.
5. In Steam (Desktop Mode): Games > Add a Non-Steam Game to My Library > Browse to `code430.x86_64`. Optional: in its properties, set Launch Options to `--fullscreen`.
6. Switch back to Game Mode and launch it from the Non-Steam tab. The `deck` graphics preset is selected automatically; F3 has no key on the Deck, so use Back + X for the overlay.

## Repo layout
```
game/                 Godot project (res:// root)
  core/               audio, content modes, input, net (co-op), settings, streaming, debug, report
  world/              packs loader, roads, terrain, buildings, water, barriers, dressing,
                      traffic, pedestrians, vegetation, services, sky; build/ holds the pack builder
  actors/             player, character, vehicles, combat, police, emergency
  ui/                 HUD, maps, pause menu, character creator, report form
  scenes/             the play testbed
  tests/              gdUnit4 tests
tools/                Python tools (uv project): osm_import, pack_tools, report_relay,
                      region_picker, controls_doc.py; tests/ with the golden fixture
packs/                first-party packs (the Ottawa map pack)
regions/              region definitions for the importer
scripts/              CI, Linux packaging, Steam Deck deploy and shortcut, build stamp
docs/                 controls, backlog, open work, graphics presets, licensing
  pack-format/        pack schemas and docs
  report-format/      issue report format
openspec/             specs and changes
.github/workflows/    CI
```

## Licensing
Three-way split, see `docs/licensing-options.md` for the reasoning:
- Code, schemas, and tools: MIT (`LICENSE`).
- First-party assets: CC BY-SA 4.0 (`LICENSE-ASSETS`).
- Map data derived from OpenStreetMap: ODbL 1.0, credited "© OpenStreetMap contributors". Elevation from Natural Resources Canada under the Open Government Licence – Canada.

## Run the CI checks locally
`scripts/ci-local.sh` runs the same steps as `.github/workflows/ci.yml` on this machine: ruff, pytest, pack validation, `openspec validate --strict --all` (skipped with a note if the OpenSpec CLI isn't installed; the version CI uses is in `.openspec-version`), gdUnit4 (orphan nodes fail the run), and optionally the Linux export (`--export`, needs the export templates installed).
