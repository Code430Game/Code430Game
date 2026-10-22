#!/usr/bin/env bash
# Exports the Linux build for the Steam Deck: scripts/package.sh linux, kept for the scripts and
# docs that call it. Usage: scripts/package-linux.sh [--with-chunks] [--zip]
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/package.sh" linux "$@"
