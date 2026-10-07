#!/usr/bin/env bash
# Writes game/build_info.json (commit, branch, build date, dirty flag) before an export, so the
# exported game can name the build it came from in issue reports. The file is gitignored.
# Usage: scripts/stamp-build.sh [output path]   (default: game/build_info.json)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/game/build_info.json}"
cd "$ROOT"
COMMIT="$(git rev-parse --short=12 HEAD)"
# CI checks out a detached HEAD; GITHUB_HEAD_REF (pull requests) or GITHUB_REF_NAME names the branch there.
BRANCH="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}}"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Only tracked files count: untracked scratch files do not make a build dirty.
if git diff --quiet HEAD -- 2>/dev/null; then DIRTY=false; else DIRTY=true; fi
# The JSON goes through python so a branch name with a quote or backslash cannot break the
# file; the game would otherwise read commit "unknown" and reports would carry no build id.
BRANCH="$BRANCH" COMMIT="$COMMIT" DATE="$DATE" DIRTY="$DIRTY" python3 - > "$OUT" <<'PY'
import json
import os

env = os.environ
print(json.dumps({
    "branch": env["BRANCH"],
    "commit": env["COMMIT"],
    "date": env["DATE"],
    "dirty": env["DIRTY"] == "true",
    "source": "export",
}))
PY
echo "stamped $OUT: $COMMIT ($BRANCH, dirty=$DIRTY)"
