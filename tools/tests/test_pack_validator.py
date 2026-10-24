import json
from pathlib import Path

import pytest

from pack_tools.validate import OSM_CREDIT, REPO_ROOT, validate_root

GOOD = {
    "schema_version": 0,
    "id": "test.pack",
    "name": "Test",
    "version": "1.0.0",
    "type": "story",
    "engine_api": 0,
    "license": "CC-BY-SA-4.0",
    "attribution": ["Test by tests"],
}


def write_pack(
    root: Path, name: str, manifest: dict, files: dict[str, bytes] | None = None
) -> Path:
    pack = root / name
    pack.mkdir(parents=True)
    (pack / "pack.json").write_text(json.dumps(manifest), encoding="utf-8")
    for rel, data in (files or {}).items():
        target = pack / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return pack


def errors_for(root: Path) -> list[str]:
    reports = validate_root(root)
    assert len(reports) == 1
    return reports[0].errors


def test_valid_manifest_passes(tmp_path: Path) -> None:
    write_pack(tmp_path, "good", GOOD)
    assert errors_for(tmp_path) == []


def test_missing_type_names_the_field(tmp_path: Path) -> None:
    manifest = {k: v for k, v in GOOD.items() if k != "type"}
    write_pack(tmp_path, "notype", manifest)
    errors = errors_for(tmp_path)
    assert any("'type' is a required property" in e for e in errors)


def test_unknown_field_rejected(tmp_path: Path) -> None:
    write_pack(tmp_path, "extra", {**GOOD, "colour": "red"})
    assert any("colour" in e for e in errors_for(tmp_path))


def test_bad_id_rejected(tmp_path: Path) -> None:
    write_pack(tmp_path, "badid", {**GOOD, "id": "Not Valid"})
    assert any(e.startswith("id:") for e in errors_for(tmp_path))


def test_data_only_pack_cannot_be_trusted(tmp_path: Path) -> None:
    write_pack(tmp_path, "trusted", {**GOOD, "trusted": True})
    assert any("trusted" in e for e in errors_for(tmp_path))


def test_system_pack_must_be_trusted(tmp_path: Path) -> None:
    write_pack(tmp_path, "sys", {**GOOD, "type": "system"})
    assert any("trusted" in e for e in errors_for(tmp_path))


def test_system_pack_trusted_passes_and_may_contain_code(tmp_path: Path) -> None:
    write_pack(tmp_path, "sys", {**GOOD, "type": "system", "trusted": True}, {"pack.pck": b"x"})
    assert errors_for(tmp_path) == []


@pytest.mark.parametrize(
    "bad_file",
    ["evil.tscn", "evil.tres", "evil.res", "evil.scn", "evil.gd", "sub/evil.gdshader", "evil.pck"],
)
def test_data_only_pack_rejects_godot_formats_and_scripts(tmp_path: Path, bad_file: str) -> None:
    write_pack(tmp_path, "data", GOOD, {bad_file: b"x", "ok.png": b"x"})
    errors = errors_for(tmp_path)
    assert len(errors) == 1
    assert bad_file in errors[0]


def test_data_only_pack_accepts_allowed_files(tmp_path: Path) -> None:
    files = {f"a{ext}": b"x" for ext in [".json", ".glb", ".png", ".ogg", ".ktx2", ".md"]}
    write_pack(tmp_path, "data", GOOD, files)
    assert errors_for(tmp_path) == []


def test_map_pack_requires_osm_credit_and_map_block(tmp_path: Path) -> None:
    write_pack(tmp_path, "map", {**GOOD, "type": "map", "license": "ODbL-1.0"})
    errors = errors_for(tmp_path)
    assert any(OSM_CREDIT in e for e in errors)
    assert any("'map' is a required property" in e for e in errors)


def test_map_pack_valid(tmp_path: Path) -> None:
    manifest = {
        **GOOD,
        "type": "map",
        "license": "ODbL-1.0",
        "attribution": [OSM_CREDIT, "Elevation: Natural Resources Canada"],
        "map": {
            "crs": "EPSG:32618",
            "origin": {"easting": 445000.0, "northing": 5028000.0, "lat": 45.42, "lon": -75.695},
            "bbox": [45.405, -75.715, 45.435, -75.675],
        },
    }
    write_pack(tmp_path, "map", manifest)
    assert errors_for(tmp_path) == []


def test_a_generated_map_pack_under_another_licence_needs_no_osm_credit(tmp_path: Path) -> None:
    manifest = {
        **GOOD,
        "type": "map",
        "map": {
            "crs": "EPSG:32618",
            "origin": {"easting": 445000.0, "northing": 5028000.0, "lat": 45.42, "lon": -75.695},
            "bbox": [45.405, -75.715, 45.435, -75.675],
        },
    }
    write_pack(tmp_path, "map", manifest)
    assert errors_for(tmp_path) == []


MAP_MANIFEST = {
    **GOOD,
    "type": "map",
    "license": "ODbL-1.0",
    "attribution": [OSM_CREDIT],
    "map": {
        "crs": "EPSG:32618",
        "origin": {"easting": 445000.0, "northing": 5028000.0, "lat": 45.42, "lon": -75.695},
        "bbox": [45.405, -75.715, 45.435, -75.675],
    },
}


def _barriers(*ids: str) -> bytes:
    wall = {"kind": "curb", "height_m": 0.12, "edge_id": "w1.0", "points": [[0, 0, 0], [1, 0, 0]]}
    doc = {"schema_version": 0, "units": "m", "barriers": [{**wall, "id": i} for i in ids]}
    return json.dumps(doc).encode()


def test_generated_files_are_checked_against_their_schemas(tmp_path: Path) -> None:
    """Review fix: barriers, road graph, buildings and water were never schema-checked."""
    write_pack(tmp_path, "map", MAP_MANIFEST, {"barriers.v0.json": _barriers("wall-1")})
    errors = errors_for(tmp_path)
    assert any(e.startswith("barriers.v0.json: barriers/0/id") for e in errors), errors


def test_duplicate_ids_in_a_generated_file_are_errors(tmp_path: Path) -> None:
    ids = ("b:curb:w1.0:0", "b:curb:w1.0:1", "b:curb:w1.0:0")
    write_pack(tmp_path, "map", MAP_MANIFEST, {"barriers.v0.json": _barriers(*ids)})
    errors = errors_for(tmp_path)
    assert errors == ["barriers.v0.json: barriers/id: 'b:curb:w1.0:0' is not unique"]


def test_duplicate_deck_sources_across_bridges_are_errors(tmp_path: Path) -> None:
    deck = {"source": "infill:w1.0:w2.0", "points": [], "left_m": [], "right_m": []}
    doc = {"bridges": [{"id": "bridge0", "decks": [deck]}, {"id": "bridge1", "decks": [deck]}]}
    from pack_tools.validate import duplicate_ids

    errors = duplicate_ids(
        "bridges.v0.json", doc, [("bridges", "id"), ("bridges", "decks", "source")]
    )
    assert errors == ["bridges.v0.json: bridges/decks/source: 'infill:w1.0:w2.0' is not unique"]


def test_invalid_json_reported(tmp_path: Path) -> None:
    pack = tmp_path / "broken"
    pack.mkdir()
    (pack / "pack.json").write_text("{not json", encoding="utf-8")
    assert any("invalid JSON" in e for e in errors_for(tmp_path))


def test_first_party_packs_are_valid() -> None:
    reports = validate_root(REPO_ROOT / "packs")
    assert reports, "expected at least the example pack"
    for report in reports:
        assert report.ok, f"{report.path}: {report.errors}"


def _ads(variants_by_item: dict) -> bytes:
    return json.dumps(
        {"ads": [{"id": k, "variants": v} for k, v in variants_by_item.items()]}
    ).encode()


def test_ads_unknown_descriptor_is_an_error(tmp_path: Path):
    manifest = {**GOOD, "supported_modes": ["gritty"]}
    write_pack(
        tmp_path,
        "p",
        manifest,
        {
            "ads.v0.json": _ads(
                {"ad.x": {"fallback": {"text": "hi", "descriptors": {"spiders": "mild"}}}}
            )
        },
    )
    (report,) = validate_root(tmp_path)
    assert any("unknown descriptor 'spiders'" in e for e in report.errors)


def test_ads_clean_variant_may_not_leak_strong_content(tmp_path: Path):
    manifest = {**GOOD, "supported_modes": ["clean", "gritty"]}
    write_pack(
        tmp_path,
        "p",
        manifest,
        {
            "ads.v0.json": _ads(
                {
                    "ad.x": {
                        "clean": {"text": "ouch", "descriptors": {"gore": "strong"}},
                        "fallback": {"text": "ok"},
                    }
                }
            )
        },
    )
    (report,) = validate_root(tmp_path)
    assert any("ad.x/clean" in e and "gore" in e for e in report.errors)


def test_ads_item_hidden_in_a_supported_mode_is_a_warning(tmp_path: Path):
    manifest = {**GOOD, "supported_modes": ["clean", "gritty"]}
    write_pack(
        tmp_path,
        "p",
        manifest,
        {
            "ads.v0.json": _ads(
                {"ad.bail": {"fallback": {"text": "bail", "descriptors": {"crime": "strong"}}}}
            )
        },
    )
    (report,) = validate_root(tmp_path)
    assert report.ok
    assert any("ad.bail" in w and "'clean'" in w for w in report.warnings)


def test_unknown_supported_mode_is_an_error(tmp_path: Path):
    write_pack(tmp_path, "p", {**GOOD, "supported_modes": ["grimdark"]})
    (report,) = validate_root(tmp_path)
    assert any("unknown mode 'grimdark'" in e for e in report.errors)


BASE_VEHICLES = REPO_ROOT / "game" / "actors" / "vehicles" / "vehicles.v0.json"


def _vehicles(**changes) -> bytes:
    base = json.loads(BASE_VEHICLES.read_text(encoding="utf-8"))
    entry = {**base["vehicles"][0], "id": "pack.limo", "name": "Long Car", **changes}
    return json.dumps({"schema_version": 0, "vehicles": [entry]}).encode()


def test_base_vehicle_catalogue_matches_the_schema() -> None:
    from pack_tools.validate import (
        VEHICLES_SCHEMA_PATH,
        load_content_rules,
        load_schema,
        validate_vehicles,
    )

    desc, _ = load_content_rules()
    data = json.loads(BASE_VEHICLES.read_text(encoding="utf-8"))
    assert validate_vehicles(data, desc, load_schema(VEHICLES_SCHEMA_PATH)) == []
    assert {v["body_class"] for v in data["vehicles"]} == {
        "sedan",
        "hatchback",
        "coupe",
        "suv",
        "pickup",
        "van",
        "box_truck",
        "taxi",
        "bus",
    }


def test_pack_vehicle_passes(tmp_path: Path) -> None:
    write_pack(tmp_path, "p", GOOD, {"vehicles.v0.json": _vehicles()})
    assert errors_for(tmp_path) == []


def test_pack_vehicle_with_unknown_body_class_is_rejected(tmp_path: Path) -> None:
    write_pack(tmp_path, "p", GOOD, {"vehicles.v0.json": _vehicles(body_class="hovercraft")})
    errors = errors_for(tmp_path)
    assert any("vehicles.v0.json" in e and "body_class" in e for e in errors)


def test_pack_vehicle_unknown_descriptor_is_rejected(tmp_path: Path) -> None:
    write_pack(
        tmp_path, "p", GOOD, {"vehicles.v0.json": _vehicles(descriptors={"spiders": "mild"})}
    )
    assert any("unknown descriptor 'spiders'" in e for e in errors_for(tmp_path))


# --- pack format v1 (add-pack-loader 1.2) ---

GOOD_V1 = {
    **GOOD,
    "schema_version": 1,
    "supported_modes": ["clean", "gritty", "dystopia"],
    "max_descriptors": {},
    "content": [{"type": "ads", "path": "ads.v0.json"}],
    "story": {"map": "code430.ottawa-centretown"},
    "dependencies": [{"id": "code430.ottawa-centretown", "version": "^0.1"}],
}
PALETTES = {
    "schema_version": 1,
    "palettes": {
        "skin": [{"name": "tone 1", "colour": [0.9, 0.8, 0.7]}],
        "hair_colour": [{"name": "black", "colour": [0.1, 0.08, 0.07]}],
        "cloth": [
            {"name": "red", "colour": [0.8, 0.2, 0.18]},
            {"name": "blue", "colour": [0.2, 0.42, 0.85]},
        ],
        "shoes": [{"name": "black", "colour": [0.12, 0.1, 0.09]}],
    },
}
PRESET_PROFILE = {
    "skin": 0,
    "hair": 1,
    "hair_colour": 0,
    "top": 1,
    "bottom": 0,
    "shoes": 0,
    "hat": 0,
    "beard": 0,
    "glasses": 0,
    "jacket": 0,
    "jacket_colour": 0,
    "height": 1.0,
    "build": 1.0,
}
CHARACTER_V1 = {
    **GOOD,
    "schema_version": 1,
    "type": "character",
    "supported_modes": ["clean", "gritty", "dystopia"],
    "max_descriptors": {},
    "character": {"palettes": "palettes.v1.json", "presets": "presets.v1.json"},
    "content": [
        {"type": "palettes", "path": "palettes.v1.json"},
        {"type": "presets", "path": "presets.v1.json"},
    ],
}
OK_ADS = _ads({"ad.x": {"fallback": {"text": "hi"}}})


def _presets(profile: dict, name: str = "Courier") -> bytes:
    return json.dumps(
        {"schema_version": 1, "presets": [{"name": name, "profile": profile}]}
    ).encode()


def test_v1_manifest_with_content_index_passes(tmp_path: Path) -> None:
    write_pack(tmp_path, "story", GOOD_V1, {"ads.v0.json": OK_ADS})
    (report,) = validate_root(tmp_path)
    assert report.errors == []
    # The map it depends on is not beside it: a warning, never an error.
    assert any("code430.ottawa-centretown" in w and "not found" in w for w in report.warnings)


def test_v1_requires_supported_modes_and_max_descriptors(tmp_path: Path) -> None:
    manifest = {k: v for k, v in GOOD_V1.items() if k not in ("supported_modes", "max_descriptors")}
    write_pack(tmp_path, "p", manifest, {"ads.v0.json": OK_ADS})
    errors = errors_for(tmp_path)
    assert any("'supported_modes' is a required property" in e for e in errors)
    assert any("'max_descriptors' is a required property" in e for e in errors)


def test_unknown_schema_version_is_named(tmp_path: Path) -> None:
    write_pack(tmp_path, "p", {**GOOD, "schema_version": 7})
    assert errors_for(tmp_path) == ["schema_version: unknown version 7 (known: 0, 1)"]


def test_v0_manifest_still_validates_against_v0(tmp_path: Path) -> None:
    write_pack(tmp_path, "old", GOOD, {"ads.v0.json": OK_ADS})
    assert errors_for(tmp_path) == []


def test_content_path_that_is_missing_is_an_error(tmp_path: Path) -> None:
    manifest = {**GOOD_V1, "content": [{"type": "missions", "path": "missions/first.json"}]}
    write_pack(tmp_path, "p", manifest)
    assert "content: missions/first.json: file not found" in errors_for(tmp_path)


def test_content_path_may_not_leave_the_pack(tmp_path: Path) -> None:
    (tmp_path / "ads.v0.json").write_bytes(OK_ADS)
    manifest = {**GOOD_V1, "content": [{"type": "ads", "path": "sub/../../ads.v0.json"}]}
    write_pack(tmp_path, "p", manifest)
    errors = errors_for(tmp_path)
    assert any("sub/../../ads.v0.json" in e for e in errors), errors


def test_content_file_is_checked_against_its_types_schema(tmp_path: Path) -> None:
    manifest = {**GOOD_V1, "content": [{"type": "ads", "path": "promo.json"}]}
    files = {"promo.json": json.dumps({"ads": [{"id": "x"}]}).encode()}
    write_pack(tmp_path, "p", manifest, files)
    errors = errors_for(tmp_path)
    assert any(e.startswith("promo.json") and "variants" in e for e in errors), errors


def test_v1_known_file_outside_the_index_is_a_warning(tmp_path: Path) -> None:
    write_pack(tmp_path, "p", {**GOOD_V1, "content": []}, {"ads.v0.json": OK_ADS})
    (report,) = validate_root(tmp_path)
    assert report.ok
    assert any("ads.v0.json" in w and "content[]" in w for w in report.warnings)


def test_disallowed_file_in_a_v1_story_pack_is_rejected(tmp_path: Path) -> None:
    write_pack(tmp_path, "p", GOOD_V1, {"ads.v0.json": OK_ADS, "mod/evil.gd": b"x"})
    assert any("mod/evil.gd" in e for e in errors_for(tmp_path))


def test_dependency_present_but_out_of_range_is_an_error(tmp_path: Path) -> None:
    old_map = {**MAP_MANIFEST, "id": "code430.ottawa-centretown", "version": "0.2.0"}
    write_pack(tmp_path, "map", old_map)
    needs_newer = {
        **GOOD_V1,
        "dependencies": [{"id": "code430.ottawa-centretown", "version": "^0.3"}],
    }
    write_pack(tmp_path, "story", needs_newer, {"ads.v0.json": OK_ADS})
    reports = {r.path.name: r for r in validate_root(tmp_path)}
    assert reports["map"].ok
    assert any("is 0.2.0, this pack needs ^0.3" in e for e in reports["story"].errors)


def test_dependency_in_range_resolves_without_a_warning(tmp_path: Path) -> None:
    write_pack(
        tmp_path, "map", {**MAP_MANIFEST, "id": "code430.ottawa-centretown", "version": "0.1.4"}
    )
    write_pack(tmp_path, "story", GOOD_V1, {"ads.v0.json": OK_ADS})
    reports = {r.path.name: r for r in validate_root(tmp_path)}
    assert reports["story"].ok
    assert not any("dependencies" in w for w in reports["story"].warnings)


def test_story_map_must_be_a_dependency(tmp_path: Path) -> None:
    write_pack(tmp_path, "p", {**GOOD_V1, "dependencies": []}, {"ads.v0.json": OK_ADS})
    assert any(e.startswith("story.map") for e in errors_for(tmp_path))


def test_character_pack_palettes_and_presets_validate(tmp_path: Path) -> None:
    files = {
        "palettes.v1.json": json.dumps(PALETTES).encode(),
        "presets.v1.json": _presets(PRESET_PROFILE),
    }
    write_pack(tmp_path, "chars", CHARACTER_V1, files)
    assert errors_for(tmp_path) == []


def test_preset_index_outside_the_palette_is_an_error(tmp_path: Path) -> None:
    files = {
        "palettes.v1.json": json.dumps(PALETTES).encode(),
        "presets.v1.json": _presets({**PRESET_PROFILE, "top": 5}),
    }
    write_pack(tmp_path, "chars", CHARACTER_V1, files)
    errors = errors_for(tmp_path)
    assert any("Courier" in e and "top index 5" in e for e in errors), errors


def test_character_section_file_must_be_indexed(tmp_path: Path) -> None:
    manifest = {**CHARACTER_V1, "content": [{"type": "palettes", "path": "palettes.v1.json"}]}
    files = {"palettes.v1.json": json.dumps(PALETTES).encode(), "presets.v1.json": b"{}"}
    write_pack(tmp_path, "chars", manifest, files)
    assert any(e.startswith("character.presets") for e in errors_for(tmp_path))


def test_character_pack_requires_its_section(tmp_path: Path) -> None:
    manifest = {k: v for k, v in CHARACTER_V1.items() if k != "character"}
    files = {
        "palettes.v1.json": json.dumps(PALETTES).encode(),
        "presets.v1.json": _presets(PRESET_PROFILE),
    }
    write_pack(tmp_path, "chars", manifest, files)
    assert any("'character' is a required property" in e for e in errors_for(tmp_path))


@pytest.mark.parametrize(
    ("version", "spec", "ok"),
    [
        ("1.2.3", "1.2.3", True),
        ("1.2.4", "1.2.3", False),
        ("1.2.3", "1.2", True),
        ("1.9.0", "^1.2", True),
        ("2.0.0", "^1.2", False),
        ("0.3.5", "^0.3", True),
        ("0.4.0", "^0.3", False),
        ("0.0.2", "^0.0.2", True),
        ("0.0.3", "^0.0.2", False),
        ("1.2.9", "~1.2.3", True),
        ("1.3.0", "~1.2.3", False),
        ("1.5.0", ">=1.0 <2.0", True),
        ("2.0.0", ">=1.0 <2.0", False),
        ("3.1.0", "*", True),
        ("nope", "*", False),
    ],
)
def test_semver_ranges(version: str, spec: str, ok: bool) -> None:
    from pack_tools.validate import semver_satisfies

    assert semver_satisfies(version, spec) is ok


def test_a_retaining_wall_needs_a_top_per_point(tmp_path: Path) -> None:
    manifest = {
        **GOOD,
        "type": "map",
        "license": "ODbL-1.0",
        "attribution": [OSM_CREDIT],
        "map": {"crs": "EPSG:32618", "origin": {"easting": 0, "northing": 0}, "bbox": [0, 0, 1, 1]},
    }

    def wall(wid: str, tops: list) -> dict:
        return {
            "id": wid,
            "edge_id": "w1.0",
            "height_m": 2.0,
            "points": [[0, 50, 0], [10, 50, 0], [20, 50, 0]],
            "tops_m": tops,
        }

    good = {"schema_version": 0, "units": "m", "walls": [wall("w:w1.0:l0", [2.0, 1.5, 1.0])]}
    write_pack(tmp_path, "walls", manifest, {"retaining_walls.v0.json": json.dumps(good).encode()})
    assert not [e for e in errors_for(tmp_path) if "retaining_walls" in e]
    bad = {
        "schema_version": 0,
        "units": "m",
        "walls": [
            wall("w:w1.0:l0", [2.0, 1.5]),
            {**wall("w:w1.0:r0", [1.0, 1.0, 1.0]), "tops_m": None},
        ],
    }
    (tmp_path / "walls" / "retaining_walls.v0.json").write_text(json.dumps(bad), encoding="utf-8")
    errors = [e for e in errors_for(tmp_path) if "retaining_walls" in e]
    assert any("'w:w1.0:l0' has 2 tops_m for 3 points" in e for e in errors)
    assert any("tops_m" in e and "w:w1.0:r0" in e or "None is not of type" in e for e in errors)
