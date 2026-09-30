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
    write_pack(tmp_path, "map", {**GOOD, "type": "map"})
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
