"""First-party weapons file (add-weapons-and-combat 1.1)."""

import json
from pathlib import Path

from pack_tools.validate import WEAPONS_SCHEMA_PATH, load_schema, validate_weapons

WEAPONS = Path(__file__).parents[2] / "game" / "actors" / "combat" / "weapons.v0.json"


def _load():
    return json.loads(WEAPONS.read_text(encoding="utf-8"))


def test_first_party_weapons_validate():
    assert validate_weapons(_load(), load_schema(WEAPONS_SCHEMA_PATH)) == []


def test_every_tone_has_a_melee_and_a_gun():
    w = {x["id"]: x for x in _load()["weapons"]}
    assert w["melee"]["variants"]["clean"]["name"] == "Paint brush"
    assert w["melee"]["variants"]["fallback"]["name"] == "Knife"
    assert w["melee"]["variants"]["dystopia"]["name"] == "Sabre"
    assert w["gun"]["variants"]["clean"]["mechanic"] == "projectile"
    assert w["gun"]["variants"]["fallback"]["impact"] == "bullet"
    assert w["gun"]["variants"]["dystopia"]["tracer"] is True


def test_a_lethal_clean_variant_is_refused():
    data = _load()
    data["weapons"][1]["variants"]["clean"]["lethal"] = True
    errors = validate_weapons(data, load_schema(WEAPONS_SCHEMA_PATH))
    assert any("lethal in a mode without lethal weapons" in e for e in errors)
