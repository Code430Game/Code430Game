#!/usr/bin/env bash
# Benchmarks a build on the Steam Deck and records the result: packages and deploys the ref
# (optional), runs the testbed benchmark N times back to back in Game Mode, and prints the
# measured render times. gamescope paces frames on the Deck, so the frame-time numbers sit on
# pacing steps; the "render cpu / gpu (measured)" line is the one to quote.
#
# Usage: scripts/deck-bench.sh [--ref <git-ref>]... [--runs N] [--seconds S] [--extra "<flags>"]
#                              [--change <id> --task <n.n>] [--no-deploy] [--dry-run] [--host H]
#   --ref       a git ref to package and benchmark (default: the working tree). Give two to
#               compare them back to back (main against a branch, say). A ref other than the
#               working tree is built in a temporary worktree, removed afterwards. The Deck
#               keeps the last ref's build, so give the branch to play last.
#   --runs      runs per ref (default 2); --seconds benchmark length (default 40)
#   --extra     more testbed flags, e.g. "--wanted=3" (the base is --autodrive --preset=deck)
#   --change/--task  append a dated note with the medians under that task in
#               openspec/changes/<id>/tasks.md (the task is not ticked)
#   --pack      map pack id to start on (passed as --pack=<id>; default the Ottawa pack)
#   --route     a named run: "loop" is the Double Cross proving ground's lap from its start
#               line (sets --pack code430.proving-ground; the pack's own spawn is the line)
#   --no-deploy benchmark what is on the Deck now (one ref only)
#   --dry-run   print what would run, touch nothing
#   --host      ssh target (default deck@steamdeck.local, or $DECK_HOST)
# It refuses when the Deck is unreachable (asleep: wake it) or when the game is already running
# there (a player's session would skew the numbers, and two copies would fight over the screen).
# Results land in build/deck-bench/<timestamp>/ ($DECK_BENCH_OUT overrides build/deck-bench).
# $DECK_SSH overrides the ssh command and $DECK_BENCH_POLL the poll interval in seconds (tests).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${DECK_HOST:-deck@steamdeck.local}"
SSH="${DECK_SSH:-ssh}"
GODOT="${GODOT_BIN:-godot}"
# tools/deck_bench.py needs Python 3.11 (the tools' uv environment); macOS python3 is 3.9.
if [[ -z "${PYTHON:-}" ]] && command -v uv >/dev/null 2>&1; then
  PYTHON="uv run --project $ROOT/tools python"
fi
PYTHON="${PYTHON:-python3}"
DEST="Games/code430"
REFS=()
RUNS=2
SECONDS_LEN=40
EXTRA=""
PACK=""
ROUTE=""
CHANGE=""
TASK=""
DEPLOY=true
DRY=false

die() { echo "deck-bench: $*" >&2; exit 1; }
# Dry-run lines go to the original stdout even where a real command's output is discarded.
exec 3>&1

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REFS+=("${2:?--ref needs a value}"); shift 2 ;;
    --runs) RUNS="${2:?}"; shift 2 ;;
    --seconds) SECONDS_LEN="${2:?}"; shift 2 ;;
    --extra) EXTRA="${2:?}"; shift 2 ;;
    --change) CHANGE="${2:?}"; shift 2 ;;
    --task) TASK="${2:?}"; shift 2 ;;
    --host) HOST="${2:?}"; shift 2 ;;
    --pack) PACK="${2:?--pack needs a pack id}"; shift 2 ;;
    --route) ROUTE="${2:?--route needs a name}"; shift 2 ;;
    --no-deploy) DEPLOY=false; shift ;;
    --dry-run) DRY=true; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || die "--runs must be a positive whole number"
[[ "$SECONDS_LEN" =~ ^[1-9][0-9]*$ ]] || die "--seconds must be a positive whole number"
[ ${#REFS[@]} -le 2 ] || die "at most two --ref values"
if [ -n "$CHANGE" ] || [ -n "$TASK" ]; then
  [ -n "$CHANGE" ] && [ -n "$TASK" ] || die "--change and --task go together"
  TASKS_FILE="$ROOT/openspec/changes/$CHANGE/tasks.md"
  [ -f "$TASKS_FILE" ] || die "no $TASKS_FILE"
fi
[ ${#REFS[@]} -gt 0 ] || REFS=("WORKTREE")
if ! $DEPLOY && [ ${#REFS[@]} -gt 1 ]; then die "--no-deploy benchmarks one build; give at most one --ref"; fi

# The game's process as the player or this script starts it, anchored so it never matches the
# ssh shell running the check.
RUNNING_PATTERN='^(/home/deck/Games/code430/|\./)code430\.x86_64'
case "${ROUTE:-}" in
  "") ;;
  loop) PACK="${PACK:-code430.proving-ground}" ;;
  *) die "unknown route: $ROUTE (known: loop)" ;;
esac
FLAGS="--benchmark=$SECONDS_LEN --autodrive --preset=deck${PACK:+ --pack=$PACK}${EXTRA:+ $EXTRA}"

remote() {
  if $DRY; then echo "[dry-run] $SSH $HOST $*" >&3; return 0; fi
  "$SSH" -o ConnectTimeout=10 -o BatchMode=yes "$HOST" "$@"
}

run() {
  if $DRY; then echo "[dry-run] $*" >&3; return 0; fi
  "$@"
}

check_deck() {
  if $DRY; then remote true; remote "pgrep -f '$RUNNING_PATTERN'"; return 0; fi
  remote true >/dev/null 2>&1 || die "the Deck at $HOST is unreachable (asleep or off the network?); wake it and retry"
  if remote "pgrep -f '$RUNNING_PATTERN'" >/dev/null 2>&1; then
    die "the game is running on the Deck; close it first (a benchmark would fight the player's session)"
  fi
}

STAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS="${DECK_BENCH_OUT:-$ROOT/build/deck-bench}/$STAMP"
POLL="${DECK_BENCH_POLL:-5}"
TMP_WORKTREES=()
cleanup() {
  for t in "${TMP_WORKTREES[@]+"${TMP_WORKTREES[@]}"}"; do
    git -C "$ROOT" worktree remove --force "$t" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# Packages `ref` and deploys it; echoes nothing. The working tree is packaged in place.
deploy_ref() {
  local ref="$1" tree="$ROOT"
  if [ "$ref" != "WORKTREE" ]; then
    if $DRY; then
      tree="<temporary worktree of $ref>"
      run git -C "$ROOT" worktree add --detach "$tree" "$ref"
      run "$GODOT" --headless --path "$tree/game" --import --quit
    else
      tree="$(mktemp -d "${TMPDIR:-/tmp}/deck-bench.XXXXXX")"
      git -C "$ROOT" worktree add --detach "$tree" "$ref" >/dev/null
      TMP_WORKTREES+=("$tree")
      # A fresh checkout has no imported assets; the export needs them.
      "$GODOT" --headless --path "$tree/game" --import --quit >/dev/null 2>&1 || true
    fi
  fi
  run "$tree/scripts/package-linux.sh" >/dev/null
  if $DRY; then
    echo "[dry-run] $tree/scripts/deploy-deck.sh ${HOST#*@}"
  else
    "$tree/scripts/deploy-deck.sh" "${HOST#*@}" >/dev/null
  fi
}

# One benchmark run in Game Mode. systemd-run keeps it alive past this ssh session; stdbuf
# line-buffers the game's output into the log.
bench_once() {
  local out="$1" unit="code430-bench-$STAMP-$2"
  local log="/tmp/$unit.log"
  remote "systemd-run --user --collect --unit=$unit --setenv=DISPLAY=:0 bash -c 'cd ~/$DEST && stdbuf -oL -eL ./code430.x86_64 --resolution 1280x800 -- $FLAGS > $log 2>&1'" >/dev/null
  if $DRY; then
    remote "systemctl --user is-active $unit"
    remote "cat $log"
    return 0
  fi
  local waited=0 limit=$((SECONDS_LEN + 240))
  sleep "$POLL"
  while [ "$(remote "systemctl --user is-active $unit" 2>/dev/null || true)" = "active" ]; do
    [ $waited -lt $limit ] || { remote "systemctl --user stop $unit" || true; die "run $2 still going after ${limit}s; stopped it"; }
    sleep "$POLL"
    waited=$((waited + POLL + 1))
  done
  remote "cat $log" > "$out"
  remote "rm -f $log" || true
}

check_deck
$DRY || mkdir -p "$RESULTS"
n=0
for ref in "${REFS[@]}"; do
  n=$((n + 1))
  if [ "$ref" = "WORKTREE" ]; then
    label="working-tree"
    commit="$(git -C "$ROOT" rev-parse HEAD)"
    git -C "$ROOT" diff --quiet HEAD -- || commit="$commit+dirty"
  else
    label="$ref"
    commit="$(git -C "$ROOT" rev-parse --verify "$ref^{commit}")" || die "unknown ref $ref"
  fi
  if $DEPLOY; then
    echo "deck-bench: packaging and deploying $label ($commit)"
    deploy_ref "$ref"
  else
    echo "deck-bench: benchmarking what is on the Deck now (labelled $label)"
  fi
  dir="$RESULTS/$n-${label//\//_}"
  $DRY || mkdir -p "$dir"
  $DRY || printf '{"ref": "%s", "commit": "%s", "flags": "%s"}\n' "$label" "$commit" "$FLAGS" > "$dir/meta.json"
  for i in $(seq 1 "$RUNS"); do
    echo "deck-bench: $label run $i of $RUNS ($FLAGS)"
    bench_once "$dir/run-$i.log" "$n-$i"
  done
done

if $DRY; then
  echo "[dry-run] $PYTHON $ROOT/tools/deck_bench.py $RESULTS${TASK:+ --tasks-file $ROOT/openspec/changes/$CHANGE/tasks.md --task $TASK}"
  exit 0
fi
args=("$RESULTS")
[ -n "$TASK" ] && args+=(--tasks-file "$TASKS_FILE" --task "$TASK")
$PYTHON "$ROOT/tools/deck_bench.py" "${args[@]}"  # unquoted: may be "uv run ... python"
echo "deck-bench: logs in $RESULTS"
