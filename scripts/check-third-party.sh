#!/usr/bin/env bash
# Third-party art: a CC0 receipt and sha256 list for every pack in art/, a SOURCE.md beside
# every built model in game/assets/, and the art size budget. See tools/third_party_check.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/tools" && uv run python third_party_check.py "$ROOT"
