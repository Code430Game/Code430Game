#!/usr/bin/env bash
# Creates the labels in-game issue reports use (run once; safe to re-run).
# Usage: scripts/setup-report-labels.sh [owner/name]   (default: the current repo)
set -euo pipefail
REPO_ARGS=()
[ -n "${1:-}" ] && REPO_ARGS=(--repo "$1")
label() { gh label create "$1" --color "$2" --description "$3" --force "${REPO_ARGS[@]}" >/dev/null && echo "label $1"; }
label in-game-report 1d76db "Filed from the game's Report a problem form"
label needs-triage fbca04 "Not looked at yet"
for area in roads traffic pedestrians vehicles world visuals performance controls audio crash other; do
  label "area:$area" c5def5 "Report area: $area"
done
label severity:cosmetic e4e669 "Looks wrong, plays fine"
label severity:annoying f9d0c4 "Gets in the way"
label severity:blocks_play d93f0b "Cannot carry on"
label severity:crash b60205 "The game crashed or froze"
