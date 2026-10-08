"""The base weather table validates against its schema and its transitions are consistent."""

import json
from pathlib import Path

from jsonschema import Draft202012Validator

REPO = Path(__file__).resolve().parents[2]
SCHEMA = REPO / "docs" / "pack-format" / "weather.schema.v0.json"
BASE = REPO / "game" / "world" / "sky" / "weather.v0.json"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_base_weather_matches_the_schema():
    validator = Draft202012Validator(_load(SCHEMA))
    errors = [e.message for e in validator.iter_errors(_load(BASE))]
    assert errors == []


def test_every_transition_names_a_state_and_rows_have_weight():
    data = _load(BASE)
    states = data["states"]
    assert data["start"] in states
    for sid, s in states.items():
        assert sum(s["next"].values()) > 0, sid
        for target in s["next"]:
            assert target in states, f"{sid} -> {target}"
        assert s["duration_s"][0] <= s["duration_s"][1], sid
        assert s["wind"][0] <= s["wind"][1], sid


def test_the_five_base_states_are_present_with_the_agreed_grip():
    states = _load(BASE)["states"]
    assert set(states) == {"clear", "overcast", "rain", "snow", "fog"}
    assert states["rain"]["grip"] == 0.8
    assert states["snow"]["grip"] == 0.55
    assert states["snow"]["temp_c"][1] <= 0
