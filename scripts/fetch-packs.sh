#!/usr/bin/env bash
# Puts the packs pinned in packs.lock.json into packs/: downloads each release zip, checks its
# sha256, and unpacks it (keeping the local chunks/ cache). Packs already at their locked hash
# are skipped, so it is cheap to run before every build or test. Public releases need no token.
# Usage: scripts/fetch-packs.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
( cd "$ROOT/tools" && uv run python -m pack_tools lock fetch )
