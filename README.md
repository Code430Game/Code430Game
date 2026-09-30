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
Or open `game/project.godot` from the Godot project manager. Press F5 to run the testbed. Left stick moves, right stick looks, L3 sprints, Start quits.

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
1. Download the `code430-linux-*` artifact from the GitHub Actions run (or export locally) and unzip it. You get `code430.x86_64` and `code430.pck`.
2. On the Deck, switch to Desktop Mode (Power menu > Switch to Desktop).
3. Copy both files to the Deck, for example with a USB stick, or from a Mac over the network:
   ```
   scp build/linux/code430.* deck@steamdeck.local:~/Games/code430/
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
Not decided yet. See `docs/licensing-options.md`. Map data derived from OpenStreetMap is ODbL and credited "© OpenStreetMap contributors".
