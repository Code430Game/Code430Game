"""The base tone modes against their schema (AGENTS.md: schemas are validated in CI)."""

import json
from pathlib import Path

from pack_tools.validate import DESCRIPTORS_PATH, MODES_DIR, REPO_ROOT, load_schema

TONE_SCHEMA_PATH = REPO_ROOT / "docs" / "pack-format" / "tone-mode.schema.v0.json"


def _modes() -> dict[Path, dict]:
    return {p: json.loads(p.read_text(encoding="utf-8")) for p in sorted(MODES_DIR.glob("*.json"))}


def test_the_three_base_modes_exist():
    assert {m["id"] for m in _modes().values()} == {"clean", "gritty", "dystopia"}


def test_every_mode_validates_against_the_schema():
    validator = load_schema(TONE_SCHEMA_PATH)
    for path, mode in _modes().items():
        errors = [e.message for e in validator.iter_errors(mode)]
        assert errors == [], f"{path.name}: {errors}"


def test_mode_id_matches_its_file_name():
    for path, mode in _modes().items():
        assert mode["id"] == path.stem


def test_every_max_names_a_known_descriptor():
    known = set(json.loads(DESCRIPTORS_PATH.read_text(encoding="utf-8"))["descriptors"])
    for path, mode in _modes().items():
        assert set(mode["max"]) <= known, f"{path.name}: {set(mode['max']) - known}"


def test_a_mode_missing_a_flag_is_refused():
    validator = load_schema(TONE_SCHEMA_PATH)
    mode = json.loads((MODES_DIR / "gritty.json").read_text(encoding="utf-8"))
    del mode["flags"]["lethal_weapons"]
    assert list(validator.iter_errors(mode))
