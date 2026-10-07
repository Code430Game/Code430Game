"""Reads Steam Deck benchmark logs written by scripts/deck-bench.sh and reports them.

The game's `--benchmark=S` run prints `benchmark: ...` lines when it ends (see
game/scenes/play_testbed.gd). On the Deck, gamescope paces frames, so the frame-time numbers
land on pacing steps (5.56, 8.33 ms ...); the measured render line is the one to quote. This
module parses those lines, takes medians across runs, prints a compact table, and can append a
dated note under a task in an OpenSpec change's tasks.md (without ticking it).

Results layout (written by the script): <results>/<n>-<label>/meta.json with "ref", "commit",
"flags", and run-<i>.log for each run. Standard library only, so the script can call it with a
plain python3.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from datetime import date, datetime
from pathlib import Path

# Each pattern names the fields it fills; a missing line leaves its fields out.
_PATTERNS: list[tuple[re.Pattern[str], tuple[str, ...]]] = [
    (
        re.compile(
            r"benchmark: (\d+) frames, avg ([\d.]+) ms, p50 ([\d.]+) ms, p95 ([\d.]+) ms, "
            r"p99 ([\d.]+) ms, max ([\d.]+) ms.*?travelled (\d+) m, draw calls (\d+)"
        ),
        ("frames", "avg_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms", "travelled_m", "draw_calls"),
    ),
    (
        re.compile(r"benchmark: render cpu ([\d.]+) ms gpu ([\d.]+) ms"),
        ("render_cpu_ms", "render_gpu_ms"),
    ),
    (
        re.compile(
            r"benchmark: traffic agents (\d+), physics process mean ([\d.]+) ms max ([\d.]+) ms"
        ),
        ("traffic_agents", "physics_mean_ms", "physics_max_ms"),
    ),
    (re.compile(r"benchmark: pedestrians (\d+),"), ("pedestrians",)),
    (re.compile(r"benchmark: chunks in scene .*first playable (\d+) ms"), ("first_playable_ms",)),
]

# Columns of the table, in order: (field, heading).
COLUMNS: list[tuple[str, str]] = [
    ("avg_ms", "avg"),
    ("p99_ms", "p99"),
    ("render_cpu_ms", "cpu"),
    ("render_gpu_ms", "gpu"),
    ("physics_mean_ms", "phys"),
    ("physics_max_ms", "phys max"),
    ("first_playable_ms", "first play"),
]


def parse_log(text: str) -> dict[str, float]:
    """The benchmark numbers in one run's log; empty when the run printed none."""
    out: dict[str, float] = {}
    for line in text.splitlines():
        for pattern, names in _PATTERNS:
            m = pattern.search(line)
            if m:
                for name, value in zip(names, m.groups(), strict=True):
                    out[name] = float(value)
    return out


def median_of(runs: list[dict[str, float]]) -> dict[str, float]:
    """Per-field median across runs (a field only some runs have uses those runs)."""
    keys = {k for r in runs for k in r}
    return {k: statistics.median([r[k] for r in runs if k in r]) for k in sorted(keys)}


def load_results(results: Path) -> list[dict]:
    """Every ref's meta and parsed runs under `results`, in run order."""
    groups = []
    for d in sorted(p for p in results.iterdir() if p.is_dir()):
        meta = json.loads((d / "meta.json").read_text())
        logs = sorted(d.glob("run-*.log"), key=lambda p: int(p.stem.split("-")[1]))
        runs = [parse_log(p.read_text(errors="replace")) for p in logs]
        groups.append({**meta, "runs": runs, "median": median_of([r for r in runs if r])})
    return groups


def _cell(value: float | None, field: str) -> str:
    if value is None:
        return "-"
    return f"{value:.0f}" if field == "first_playable_ms" else f"{value:.2f}"


def format_table(groups: list[dict]) -> str:
    """A compact table: one row per run and a median row per ref (ms throughout)."""
    head = ["ref", "run"] + [h for _f, h in COLUMNS]
    rows = [head]
    for g in groups:
        label = f"{g['ref']} ({g['commit'][:7]})"
        for i, r in enumerate(g["runs"], 1):
            rows.append([label, str(i)] + [_cell(r.get(f), f) for f, _h in COLUMNS])
        rows.append([label, "median"] + [_cell(g["median"].get(f), f) for f, _h in COLUMNS])
    widths = [max(len(row[c]) for row in rows) for c in range(len(head))]
    lines = [
        "  ".join(cell.ljust(widths[c]) for c, cell in enumerate(row)).rstrip() for row in rows
    ]
    lines.insert(1, "  ".join("-" * w for w in widths))
    return "\n".join(lines)


def task_note(groups: list[dict], today: date | None = None) -> str:
    """The note appended under a task: date, flags, and each ref's medians."""
    day = (today or datetime.now().astimezone().date()).isoformat()
    flags = groups[0]["flags"] if groups else ""
    parts = []
    for g in groups:
        m = g["median"]
        parts.append(
            f"{g['ref']} {g['commit'][:7]}: render cpu {_cell(m.get('render_cpu_ms'), 'x')} / "
            f"gpu {_cell(m.get('render_gpu_ms'), 'x')} ms measured, physics mean "
            f"{_cell(m.get('physics_mean_ms'), 'x')} ms (max {_cell(m.get('physics_max_ms'), 'x')}), "
            f"frame avg {_cell(m.get('avg_ms'), 'x')} / p99 {_cell(m.get('p99_ms'), 'x')} ms (paced), "
            f"first playable {_cell(m.get('first_playable_ms'), 'first_playable_ms')} ms"
        )
    runs = len(groups[0]["runs"]) if groups else 0
    return (
        f"  - {day} Deck benchmark (scripts/deck-bench.sh, median of {runs}, `{flags}`): "
        + "; ".join(parts)
        + "."
    )


def append_task_note(tasks: Path, task: str, note: str) -> None:
    """Inserts `note` under task `task` (after its existing notes); never ticks it."""
    lines = tasks.read_text().splitlines()
    start = next(
        (
            i
            for i, line in enumerate(lines)
            if re.match(rf"- \[[ x]\] {re.escape(task)}(\s|$)", line)
        ),
        None,
    )
    if start is None:
        raise SystemExit(f"deck-bench: task {task} not found in {tasks}")
    end = start + 1
    while end < len(lines) and lines[end].startswith((" ", "\t")) and lines[end].strip():
        end += 1
    lines.insert(end, note)
    tasks.write_text("\n".join(lines) + "\n")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("results", type=Path)
    ap.add_argument("--tasks-file", type=Path)
    ap.add_argument("--task")
    args = ap.parse_args(argv)
    groups = load_results(args.results)
    if not groups:
        print("deck-bench: no results", file=sys.stderr)
        return 1
    print(format_table(groups))
    empty = [g["ref"] for g in groups if not any(g["runs"])]
    if empty:
        print(
            f"deck-bench: no benchmark lines for {', '.join(empty)}; see the logs", file=sys.stderr
        )
        return 1
    if args.tasks_file and args.task:
        note = task_note(groups)
        append_task_note(args.tasks_file, args.task, note)
        print(f"noted under {args.task} in {args.tasks_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
