#!/usr/bin/env bash
# Runs the same checks as .github/workflows/ci.yml on this machine.
# Usage: scripts/ci-local.sh [--export]
#   --export  also export the Linux build (needs export templates for the pinned Godot version).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
PINNED="$(cat "$ROOT/.godot-version")"
DO_EXPORT=false
[ "${1:-}" = "--export" ] && DO_EXPORT=true

step() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

step "Godot version check (pinned $PINNED)"
ACTUAL="$("$GODOT" --version | head -1)"
case "$ACTUAL" in
  "${PINNED%-stable}".stable*) echo "ok: $ACTUAL" ;;
  *) echo "WARNING: godot reports '$ACTUAL', expected $PINNED" ;;
esac

step "Python tools: ruff + pytest"
( cd "$ROOT/tools" && uv sync --frozen --quiet && uv run ruff check . && uv run ruff format --check . && uv run pytest -q )

step "Third-party art (receipts, budget)"
"$ROOT/scripts/check-third-party.sh"

step "Pack manifests"
( cd "$ROOT/tools" && uv run python -m pack_tools ../packs )

step "OpenSpec (validate --strict --all)"
if command -v openspec >/dev/null 2>&1; then
  ( cd "$ROOT" && openspec validate --strict --all --no-interactive )
else
  echo "SKIPPED: openspec is not installed (npm install -g @fission-ai/openspec@$(cat "$ROOT/.openspec-version")); CI runs this step"
fi

step "gdUnit4 (headless)"
# gdUnit exits 0 on success, 101 when tests passed but left orphan nodes, and 100 or higher
# otherwise for failures. Orphans fail the run: they once piled up to 2,197 unnoticed.
( cd "$ROOT/game" && "$GODOT" --headless --path . --import --quit >/dev/null 2>&1 )
set +e
GD_OUT="$(cd "$ROOT/game" && "$GODOT" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://tests 2>&1)"
GD_STATUS=$?
set -e
printf "%s\n" "$GD_OUT" | grep -vE "remote port number|Remote Debugger" | grep -E "Overall Summary|FAILED|ERROR|Executed test" || true
case "$GD_STATUS" in
  0) ;;
  101) echo "gdUnit: tests passed but left orphan nodes; free them (auto_free) and rerun"; exit 101 ;;
  *) echo "gdUnit failed with exit code $GD_STATUS"; exit "$GD_STATUS" ;;
esac

if $DO_EXPORT; then
  step "Linux export"
  mkdir -p "$ROOT/build/linux"
  ( cd "$ROOT/game" && "$GODOT" --headless --path . --export-release "Linux" ../build/linux/code430.x86_64 2>&1 | tail -2 )
  ls -la "$ROOT/build/linux"
fi

step "All checks passed"
