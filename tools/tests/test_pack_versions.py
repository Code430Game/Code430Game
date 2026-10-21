"""Pack versions (add-pack-repositories 1.2b), the build stamp (1.2) and the size limits."""

import json
import subprocess
from pathlib import Path

import pytest

from osm_import.__main__ import build_stamp, importer_commit
from pack_tools import validate, versions

ORIGIN = {"easting": 445625.0, "northing": 5029844.0, "lat": 45.42, "lon": -75.695}


def make_pack(root: Path, version: str = "0.2.0", buildings=("w1", "w2"), origin=ORIGIN, **extra):
    root.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": 0,
        "id": "code430.ottawa-centretown",
        "name": "Centretown",
        "version": version,
        "type": "map",
        "engine_api": 0,
        "license": "ODbL-1.0",
        "attribution": ["© OpenStreetMap contributors"],
        "map": {"crs": "EPSG:32618", "origin": dict(origin), "bbox": [45.4, -75.7, 45.43, -75.67]},
        **extra,
    }
    (root / "pack.json").write_text(json.dumps(manifest), encoding="utf-8")
    data = {"buildings": [{"id": b, "height_m": 6.0} for b in buildings]}
    (root / "buildings.v0.json").write_text(json.dumps(data), encoding="utf-8")
    return root


def test_an_unchanged_pack_needs_no_bump(tmp_path):
    old = make_pack(tmp_path / "old" / "centretown")
    new = make_pack(tmp_path / "new" / "centretown")
    assert versions.compare(old, new).level == "none"
    assert versions.check(old, new) == []


def test_a_new_build_stamp_or_version_alone_is_no_content_change(tmp_path):
    old = make_pack(tmp_path / "old" / "centretown")
    new = make_pack(
        tmp_path / "new" / "centretown", version="0.2.1", build={"importer": "abc", "inputs": {}}
    )
    assert versions.compare(old, new).level == "none"


def test_changed_files_without_a_bump_fail_and_say_which_bump(tmp_path):
    old = make_pack(tmp_path / "old" / "centretown")
    new = make_pack(tmp_path / "new" / "centretown")
    (new / "buildings.v0.json").write_text(
        json.dumps({"buildings": [{"id": "w1", "height_m": 7.0}, {"id": "w2", "height_m": 6.0}]})
    )
    errors = versions.check(old, new)
    assert len(errors) == 1
    assert "needs a patch bump" in errors[0] and "0.2.1" in errors[0]
    make_pack(new, version="0.2.1")
    (new / "buildings.v0.json").write_text(
        json.dumps({"buildings": [{"id": "w1", "height_m": 7.0}, {"id": "w2", "height_m": 6.0}]})
    )
    assert versions.check(old, new) == []


def test_new_ids_need_minor_and_in_0x_a_patch_step_is_enough(tmp_path):
    old = make_pack(tmp_path / "old" / "centretown")
    new = make_pack(tmp_path / "new" / "centretown", version="0.2.1", buildings=("w1", "w2", "w3"))
    assert versions.compare(old, new).level == "minor"
    assert versions.check(old, new) == []


def test_after_1_0_new_ids_need_a_minor_step(tmp_path):
    old = make_pack(tmp_path / "old" / "centretown", version="1.4.2")
    new = make_pack(tmp_path / "new" / "centretown", version="1.4.3", buildings=("w1", "w2", "w3"))
    errors = versions.check(old, new)
    assert errors and "needs a minor bump" in errors[0] and "1.5.0" in errors[0]
    make_pack(new, version="1.5.0", buildings=("w1", "w2", "w3"))
    assert versions.check(old, new) == []


@pytest.mark.parametrize(
    "kwargs, reason",
    [
        ({"buildings": ("w1",)}, "buildings.v0.json:buildings/id w2"),
        ({"origin": {**ORIGIN, "easting": 445700.0}}, "map.origin moved"),
    ],
)
def test_removed_ids_or_a_moved_origin_are_breaking(tmp_path, kwargs, reason):
    old = make_pack(tmp_path / "old" / "centretown")
    new = make_pack(tmp_path / "new" / "centretown", version="0.2.1", **kwargs)
    errors = versions.check(old, new)
    assert (
        errors
        and "needs a major bump" in errors[0]
        and "0.3.0" in errors[0]
        and reason in errors[0]
    )
    make_pack(new, version="0.3.0", **kwargs)
    assert versions.check(old, new) == []


def test_a_version_must_go_up(tmp_path):
    old = make_pack(tmp_path / "old" / "centretown", version="0.3.0")
    new = make_pack(tmp_path / "new" / "centretown", version="0.2.9")
    assert "is not above" in versions.check(old, new)[0]


def test_the_release_tag_names_the_folder_and_version(tmp_path):
    new = make_pack(tmp_path / "centretown")
    assert versions.check(None, new, tag="centretown-v0.2.0") == []
    assert "should be 'centretown-v0.2.0'" in versions.check(None, new, tag="v0.2.0")[0]


def test_bump_of_counts_0x_minor_steps_as_major():
    assert versions.bump_of("0.2.0", "0.3.0") == "major"
    assert versions.bump_of("0.2.0", "0.2.1") == "minor"
    assert versions.bump_of("1.2.0", "2.0.0") == "major"
    assert versions.bump_of("1.2.0", "1.3.0") == "minor"
    assert versions.bump_of("1.2.0", "1.2.1") == "patch"
    assert versions.bump_of("1.2.0", "1.1.0") is None


def test_check_against_a_git_tag(tmp_path):
    repo = tmp_path / "Location-OttawaOnCa"
    pack = make_pack(repo / "packs" / "centretown")
    git = lambda *a: subprocess.run(["git", *a], cwd=repo, check=True, capture_output=True)
    git("init", "-q")
    git("-c", "user.email=t@example.invalid", "-c", "user.name=t", "add", ".")
    git("-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-qm", "first")
    git("tag", "centretown-v0.2.0")
    make_pack(pack, buildings=("w1",))
    assert versions.main([str(pack), "--ref", "centretown-v0.2.0"]) == 1
    make_pack(pack, version="0.3.0", buildings=("w1",))
    assert (
        versions.main([str(pack), "--ref", "centretown-v0.2.0", "--tag", "centretown-v0.3.0"]) == 0
    )


def test_size_limits_warn_then_fail(tmp_path, monkeypatch):
    pack = make_pack(tmp_path / "centretown")
    monkeypatch.setattr(validate, "FILE_WARN_BYTES", 40)
    monkeypatch.setattr(validate, "FILE_FAIL_BYTES", 1000)
    monkeypatch.setattr(validate, "PACK_WARN_BYTES", 1500)
    (pack / "chunks").mkdir()
    (pack / "chunks" / "big.glb").write_bytes(b"x" * 5000)  # built by the game: not counted
    errors, warnings = validate.size_problems(pack)
    assert errors == [] and any("buildings.v0.json" in w for w in warnings)
    (pack / "road_graph.v0.json").write_bytes(b"{}" + b" " * 2000)
    errors, warnings = validate.size_problems(pack)
    assert len(errors) == 1 and "road_graph.v0.json" in errors[0]
    assert any("the pack is" in w for w in warnings)


def test_the_build_stamp_records_the_importer_and_input_snapshots():
    stamp = build_stamp(
        [
            {"layer": "roads", "osm_base_timestamp": "2026-10-01T00:00:00Z"},
            {"layer": "water", "kind": "file", "path": "water.json"},
        ],
        "abc123",
    )
    assert stamp == {
        "importer": "abc123",
        "inputs": {"roads": "2026-10-01T00:00:00Z", "water": "water.json"},
    }
    assert importer_commit() not in ("", None)


def test_the_build_stamp_validates_in_a_manifest(tmp_path):
    pack = make_pack(
        tmp_path / "centretown", build={"importer": "abc123", "inputs": {"roads": None}}
    )
    (pack / "buildings.v0.json").unlink()  # the stand-in file isn't a full buildings file
    report = validate.validate_pack(pack)
    assert report.ok, report.errors
