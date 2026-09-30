#!/usr/bin/env bash
# Copies build/linux to the Steam Deck over SSH (key-based login as `deck`).
# Usage: scripts/deploy-deck.sh [host]   (default host: steamdeck.local)
# Requires a prior scripts/package-linux.sh. Uses rsync when the Deck has it, scp otherwise.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-steamdeck.local}"
DEST="Games/code430"
SRC="$ROOT/build/linux/"
[ -x "$SRC/code430.x86_64" ] || { echo "no build at $SRC; run scripts/package-linux.sh first" >&2; exit 1; }
ssh -o ConnectTimeout=10 "deck@$HOST" "mkdir -p ~/$DEST" || { echo "Deck at $HOST not reachable" >&2; exit 1; }
if ssh "deck@$HOST" 'command -v rsync >/dev/null'; then
  rsync -az --delete "$SRC" "deck@$HOST:$DEST/"
else
  scp -r "$SRC"* "deck@$HOST:$DEST/"
fi
ssh "deck@$HOST" "chmod +x ~/$DEST/code430.x86_64 && ls -la ~/$DEST && du -sh ~/$DEST"
echo "deployed to deck@$HOST:~/$DEST"
