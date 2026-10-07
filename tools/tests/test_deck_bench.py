"""scripts/deck-bench.sh and tools/deck_bench.py: parsing a Deck benchmark log, the medians,
the task note, and the script end to end against a stub ssh (no network, no Deck)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import date
from pathlib import Path

import deck_bench

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "deck-bench.sh"
SAMPLE = Path(__file__).parent / "fixtures" / "deck_bench_sample.log"


def test_the_log_parser_reads_every_benchmark_line():
    r = deck_bench.parse_log(SAMPLE.read_text())
    assert r["frames"] == 4799
    assert r["avg_ms"] == 8.34 and r["p99_ms"] == 8.33 and r["max_ms"] == 12.41
    assert r["draw_calls"] == 719 and r["travelled_m"] == 655
    assert r["render_cpu_ms"] == 2.05 and r["render_gpu_ms"] == 5.71
    assert r["physics_mean_ms"] == 6.40 and r["physics_max_ms"] == 14.10
    assert r["traffic_agents"] == 150 and r["pedestrians"] == 100
    assert r["first_playable_ms"] == 1450


def test_a_log_without_benchmark_lines_parses_empty():
    assert deck_bench.parse_log("ERROR: crashed before the benchmark\n") == {}


def test_medians_across_runs():
    runs = [
        {"render_gpu_ms": 5.0, "avg_ms": 8.33},
        {"render_gpu_ms": 6.0},
        {"render_gpu_ms": 7.0, "avg_ms": 5.56},
    ]
    m = deck_bench.median_of(runs)
    assert m["render_gpu_ms"] == 6.0
    assert m["avg_ms"] == (8.33 + 5.56) / 2  # only the runs that have it


def _group(ref: str, gpu: float) -> dict:
    run = {**deck_bench.parse_log(SAMPLE.read_text()), "render_gpu_ms": gpu}
    return {
        "ref": ref,
        "commit": "abcdef1234",
        "flags": "--benchmark=40 --autodrive --preset=deck",
        "runs": [run],
        "median": run,
    }


def test_the_table_has_a_row_per_run_and_a_median_per_ref():
    table = deck_bench.format_table([_group("main", 5.71), _group("change/x", 6.10)])
    lines = table.splitlines()
    assert lines[0].split()[:3] == ["ref", "run", "avg"]
    assert sum("median" in line for line in lines) == 2
    assert "5.71" in table and "6.10" in table and "1450" in table


def test_the_task_note_goes_under_its_task_without_ticking_it(tmp_path):
    tasks = tmp_path / "tasks.md"
    tasks.write_text(
        "## 2. Verification\n"
        "- [ ] 2.1 Deck benchmark on the usual route: no change\n"
        "  - an earlier note\n"
        "- [ ] 2.2 Human tries it\n"
    )
    note = deck_bench.task_note(
        [_group("main", 5.71), _group("change/x", 6.10)], today=date(2026, 10, 7)
    )
    deck_bench.append_task_note(tasks, "2.1", note)
    lines = tasks.read_text().splitlines()
    assert lines[1] == "- [ ] 2.1 Deck benchmark on the usual route: no change"  # not ticked
    assert lines[2] == "  - an earlier note"
    assert lines[3].startswith("  - 2026-10-07 Deck benchmark")
    assert "main abcdef1: render cpu 2.05 / gpu 5.71 ms measured" in lines[3]
    assert "change/x abcdef1" in lines[3]
    assert lines[4] == "- [ ] 2.2 Human tries it"


def test_an_unknown_task_is_refused(tmp_path):
    tasks = tmp_path / "tasks.md"
    tasks.write_text("- [ ] 1.1 Something\n")
    try:
        deck_bench.append_task_note(tasks, "9.9", "  - note")
    except SystemExit as e:
        assert "9.9" in str(e)
    else:
        raise AssertionError("an unknown task must be refused")


# --- the script, end to end against a stub ssh -------------------------------------------

STUB = r"""#!/usr/bin/env bash
# Stands in for ssh: skips options and the host, then answers the remote command.
while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift 2; done
shift  # the host
cmd="$*"
echo "$cmd" >> "$STUB_LOG"
case "$STUB_MODE" in
  unreachable) exit 255 ;;
esac
case "$cmd" in
  true) exit 0 ;;
  pgrep*) [ "$STUB_MODE" = running ] && { echo 4242; exit 0; }; exit 1 ;;
  systemd-run*) echo "Running as unit"; exit 0 ;;
  "systemctl --user is-active"*) echo inactive; exit 3 ;;
  cat\ /tmp/*) cat "$STUB_SAMPLE"; exit 0 ;;
  rm\ *) exit 0 ;;
esac
exit 0
"""


def _run_script(tmp_path: Path, mode: str, *args: str) -> tuple[subprocess.CompletedProcess, Path]:
    stub = tmp_path / "fake-ssh"
    stub.write_text(STUB)
    stub.chmod(0o755)
    log = tmp_path / "ssh.log"
    env = {
        **os.environ,
        "DECK_SSH": str(stub),
        "STUB_MODE": mode,
        "STUB_LOG": str(log),
        "STUB_SAMPLE": str(SAMPLE),
        "DECK_BENCH_OUT": str(tmp_path / "out"),
        "DECK_BENCH_POLL": "0",
        "PYTHON": sys.executable,
    }
    proc = subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
        check=False,
    )
    return proc, log


def test_the_script_benchmarks_and_reports_without_deploying(tmp_path):
    proc, log = _run_script(
        tmp_path, "ok", "--no-deploy", "--runs", "2", "--seconds", "20", "--extra", "--wanted=3"
    )
    assert proc.returncode == 0, proc.stderr
    assert "median" in proc.stdout and "5.71" in proc.stdout
    sent = log.read_text()
    assert "pgrep -f '^(/home/deck/Games/code430/|\\./)code430\\.x86_64'" in sent  # anchored check
    runs = [line for line in sent.splitlines() if line.startswith("systemd-run")]
    assert len(runs) == 2
    assert "--setenv=DISPLAY=:0" in runs[0] and "stdbuf -oL -eL" in runs[0]
    assert "-- --benchmark=20 --autodrive --preset=deck --wanted=3" in runs[0]
    (out,) = (tmp_path / "out").iterdir()
    (group,) = out.iterdir()
    meta = json.loads((group / "meta.json").read_text())
    assert meta["ref"] == "working-tree" and meta["flags"].endswith("--wanted=3")
    assert sorted(p.name for p in group.glob("run-*.log")) == ["run-1.log", "run-2.log"]


def test_the_script_refuses_while_the_game_runs(tmp_path):
    proc, log = _run_script(tmp_path, "running", "--no-deploy")
    assert proc.returncode != 0
    assert "the game is running on the Deck" in proc.stderr
    assert "systemd-run" not in log.read_text()


def test_the_script_says_when_the_deck_is_asleep(tmp_path):
    proc, _log = _run_script(tmp_path, "unreachable", "--no-deploy")
    assert proc.returncode != 0
    assert "unreachable" in proc.stderr and "wake it" in proc.stderr


def test_a_dry_run_shows_the_plan_and_touches_nothing(tmp_path):
    proc, log = _run_script(tmp_path, "ok", "--dry-run", "--ref", "HEAD", "--runs", "1")
    assert proc.returncode == 0, proc.stderr
    assert "[dry-run]" in proc.stdout
    assert "worktree add --detach" in proc.stdout and "package-linux.sh" in proc.stdout
    assert "deploy-deck.sh" in proc.stdout and "systemd-run" in proc.stdout
    assert not log.exists()  # the stub ssh was never called
    assert not (tmp_path / "out").exists()


def test_bad_arguments_are_refused(tmp_path):
    proc, _ = _run_script(tmp_path, "ok", "--runs", "zero")
    assert proc.returncode != 0 and "--runs" in proc.stderr
    proc, _ = _run_script(tmp_path, "ok", "--change", "add-weapon-selector")
    assert proc.returncode != 0 and "go together" in proc.stderr
    proc, _ = _run_script(tmp_path, "ok", "--no-deploy", "--ref", "HEAD", "--ref", "HEAD~1")
    assert proc.returncode != 0 and "one build" in proc.stderr
