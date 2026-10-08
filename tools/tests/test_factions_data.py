"""First-party factions file and the faction checks (add-hostile-gang 1.1)."""

import copy
import json
from pathlib import Path

from pack_tools.validate import (
    FACTIONS_SCHEMA_PATH,
    load_base_weapons,
    load_content_rules,
    load_schema,
    validate_factions,
)

FACTIONS = Path(__file__).parents[2] / "game" / "core" / "content" / "factions.v0.json"
TURF_SCHEMA = Path(__file__).parents[2] / "docs" / "pack-format" / "turf.schema.v0.json"
PROVING_TURF = Path(__file__).parents[2] / "packs" / "proving-ground" / "turf.v0.json"


def _load():
    return json.loads(FACTIONS.read_text(encoding="utf-8"))


def _check(data):
    desc, _modes = load_content_rules()
    return validate_factions(data, load_base_weapons(), desc, load_schema(FACTIONS_SCHEMA_PATH))


def test_first_party_factions_validate():
    assert _check(_load()) == []


def test_the_double_cross_is_five_and_a_leader_with_a_variant_per_tone():
    f = {x["id"]: x for x in _load()["factions"]}["double-cross"]
    assert f["crew"]["members"] == 5
    assert f["crew"]["leader_health"] > 1.0
    for key in ("fallback", "clean", "dystopia"):
        assert f["variants"][key]["melee"] == "melee"
        assert f["variants"][key]["ranged"] == "gun"
    assert f["variants"]["clean"]["descriptors"]["violence"] == "mild"


def test_a_clean_variant_may_not_arm_the_crew_with_a_lethal_weapon():
    data = copy.deepcopy(_load())
    weapons = load_base_weapons()
    # Make the gun's clean variant lethal in a copy of the weapons, then the faction's clean
    # variant that names it must be refused.
    weapons = copy.deepcopy(weapons)
    for w in weapons["weapons"]:
        if w["id"] == "gun":
            w["variants"]["clean"]["lethal"] = True
    desc, _modes = load_content_rules()
    errors = validate_factions(data, weapons, desc, load_schema(FACTIONS_SCHEMA_PATH))
    assert any("lethal in a mode without lethal weapons" in e for e in errors)


def test_unknown_weapons_and_descriptors_are_refused():
    data = copy.deepcopy(_load())
    data["factions"][0]["variants"]["fallback"]["ranged"] = "rocket"
    data["factions"][0]["descriptors"]["spice"] = "strong"
    errors = _check(data)
    assert any("unknown weapon 'rocket'" in e for e in errors)
    assert any("unknown descriptor 'spice'" in e for e in errors)


def test_turf_schema_takes_a_faction_and_a_centre():
    schema = load_schema(TURF_SCHEMA)
    turf = json.loads(PROVING_TURF.read_text(encoding="utf-8"))
    turf["turfs"][0]["faction"] = "double-cross"
    turf["turfs"][0]["centre"] = [650.0, 475.0]
    assert list(schema.iter_errors(turf)) == []
    turf["turfs"][0]["faction"] = "Not An Id"
    assert list(schema.iter_errors(turf)) != []
