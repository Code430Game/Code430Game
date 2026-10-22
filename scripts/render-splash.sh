#!/usr/bin/env bash
# Renders game/ui/splash/splash_card.tscn to game/assets/splash/boot_splash.png (the boot
# splash in project.godot) at 1920x1200, the Deck's 16:10 at twice its size.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
cd "$ROOT/game"
"$GODOT" --path . res://ui/splash/splash_card.tscn -- \
  --render-to="$ROOT/game/assets/splash/boot_splash.png"
