"""Tests that read Ottawa use the pack pinned in packs.lock.json, fetched into packs/ by
scripts/fetch-packs.sh. Stop early with that hint rather than with a missing-file error."""

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def pytest_sessionstart(session):
    if not (ROOT / "packs" / "ottawa-centretown" / "pack.json").is_file():
        raise pytest.UsageError(
            "packs/ottawa-centretown is missing: run scripts/fetch-packs.sh (it fetches the packs "
            "pinned in packs.lock.json)"
        )
