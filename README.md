# Code 430

A free, open-source, AI-built open-world crime game framework in the spirit of GTA III–IV, set on real city road networks from OpenStreetMap. Codename Code 430. Read `VISION.md` for the why and `AGENTS.md` for the rules.

Status: Phase 0 (foundations). The project boots to an empty testbed with a controller-driven camera.

## Requirements
- Godot `4.7.2-stable` (see `.godot-version`). macOS: `brew install --cask godot`. Others: https://godotengine.org/download.
- Python 3.11+ and [uv](https://docs.astral.sh/uv/) for the tools.

## Open the project
```
godot --path game --editor
```
Or open `game/project.godot` from the Godot project manager. Press F5 to run the play testbed: it loads the Ottawa map pack from `packs/`, builds the city, and puts you on foot beside a car on the Queensway.

On foot: left stick walks, L3 runs, A jumps, right stick orbits the camera, Y gets into a nearby car. In the car, Y gets out again when you are slower than 18 km/h.

Driving: right trigger accelerates, left trigger brakes or reverses from a stop, left stick steers, RB is the handbrake, right stick orbits the camera. A minimap sits in the corner. Back opens the full map (left stick pans, right stick moves a cursor that names the road under it, triggers zoom, Back closes). Back+Y puts the car back on the nearest road, Back+B draws the road graph, Back+X shows frame stats, Start quits. Keyboard: W/S/A/D, Space handbrake, M map, R reset, F4 graph, F3 stats.

Benchmark from the command line (vsync off, prints a frame-time summary and quits):
```
godot --path game -- --benchmark=60 --autodrive --preset=deck --screenshot=/tmp/shot.png   # --drive starts in the car without autodrive
```
More testbed flags: `--traffic=N` caps traffic cars (0 disables), `--spawn=x,z` starts on the nearest road to a local coordinate, `--topdown=<height>` looks straight down, `--graph` shows the road graph overlay, `--telemetry` prints the car state every second.

## Build the map pack
```
cd tools
uv run python -m osm_import --bbox 45.405,-75.715,45.435,-75.675 --pack-out ../packs/ottawa-centretown \
  --pack-id code430.ottawa-centretown --pack-name "Ottawa Centretown" --title "Ottawa Centretown starter district"
```
That fetches OpenStreetMap roads, water, and buildings plus NRCan elevation data (cached, gitignored), and writes the road graph, terrain heightmaps, water and building files, manifest, and validation report. Optionally pre-build the chunk meshes as GLB so the game loads faster:
```
godot --headless --path game -s res://world/build/pack_builder.gd -- code430.ottawa-centretown
```

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
To get it into the Game Mode library without Desktop Mode, `uv run scripts/deck-add-shortcut.py` writes the non-Steam shortcut over SSH; restart the Deck afterwards and it shows up under the Non-Steam tab.

Manual route:
1. Run `scripts/package-linux.sh` (or download the `code430-linux-*` artifact from GitHub Actions). You get `build/linux/` with `code430.x86_64`, `code430.pck`, and a `packs/` folder. The game looks for packs next to the executable, in `~/.local/share/Code 430/packs`, or in the repo when run from the editor.
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
  core/               settings, input, debug overlay
  scenes/             testbed
  tests/              gdUnit4 tests
tools/                Python tools (uv project): pack validator, later OSM import
packs/                first-party packs
docs/pack-format/     pack manifest schema and docs
openspec/             specs and changes
.github/workflows/    CI
```

## Licensing
Three-way split, see `docs/licensing-options.md` for the reasoning:
- Code, schemas, and tools: MIT (`LICENSE`).
- First-party assets: CC BY-SA 4.0 (`LICENSE-ASSETS`).
- Map data derived from OpenStreetMap: ODbL 1.0, credited "© OpenStreetMap contributors". Elevation from Natural Resources Canada under the Open Government Licence – Canada.

## Run the CI checks locally
`scripts/ci-local.sh` runs the same steps as `.github/workflows/ci.yml` on this machine: ruff, pytest, pack validation, gdUnit4, and optionally the Linux export (`--export`, needs the export templates installed).
