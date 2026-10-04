"""The car radio's data: tracks and stations match their schemas and each other, and every loop
is 30 to 60 seconds with channels that line up at the loop point."""

import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

REPO = Path(__file__).resolve().parents[2]
SCHEMAS = REPO / "docs" / "pack-format"
RADIO = REPO / "game" / "core" / "audio" / "radio"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


MUSIC = load(RADIO / "music.v0.json")
STATIONS = load(RADIO / "radio.v0.json")


@pytest.mark.parametrize(
    ("doc", "schema"), [(MUSIC, "music.schema.v0.json"), (STATIONS, "radio.schema.v0.json")]
)
def test_matches_schema(doc, schema):
    validator = Draft202012Validator(load(SCHEMAS / schema))
    Draft202012Validator.check_schema(validator.schema)
    assert [e.message for e in validator.iter_errors(doc)] == []


def test_every_station_names_a_track():
    ids = {t["id"] for t in MUSIC["tracks"]}
    for station in STATIONS["stations"]:
        for variant in station["variants"].values():
            assert variant["track"] in ids, station["id"]


@pytest.mark.parametrize("track", MUSIC["tracks"], ids=lambda t: t["id"])
def test_loop_length_and_alignment(track):
    lens = [len(c["pattern"].split()) for c in track["channels"]]
    longest = max(lens)
    assert all(longest % n == 0 for n in lens), f"channels do not line up at the loop: {lens}"
    seconds = longest * 60.0 / (track["tempo_bpm"] * track["steps_per_beat"])
    assert 30.0 <= seconds <= 60.0, f"{seconds:.1f} s"


@pytest.mark.parametrize("track", MUSIC["tracks"], ids=lambda t: t["id"])
def test_channels_use_defined_instruments(track):
    for channel in track["channels"]:
        assert channel["instrument"] in track["instruments"]
