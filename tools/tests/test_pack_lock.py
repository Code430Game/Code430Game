"""packs.lock.json and the fetch (add-pack-repositories 2.1): a release zip is checked against
its sha256, unpacked into packs/<folder> keeping the chunk cache, skipped when current, and
`check` catches a missing, stale or mismatched pack."""

import hashlib
import io
import json
import zipfile
from pathlib import Path

import pytest

from pack_tools import lock

REPO = Path(__file__).resolve().parents[2]


def _manifest(version: str = "0.2.0") -> dict:
    return {
        "schema_version": 0,
        "id": "code430.test-town",
        "name": "Test Town",
        "version": version,
        "type": "map",
        "engine_api": 0,
        "license": "ODbL-1.0",
        "attribution": ["© OpenStreetMap contributors"],
        "map": {
            "crs": "EPSG:32618",
            "origin": {"easting": 1.0, "northing": 2.0, "lat": 45.0, "lon": -75.0},
        },
    }


def _release(tmp_path: Path, version: str = "0.2.0", top: str = "town") -> dict:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr(f"{top}/pack.json", json.dumps(_manifest(version)))
        zf.writestr(f"{top}/overrides.json", "{}")
    data = buf.getvalue()
    asset = f"town-v{version}.zip"
    (tmp_path / "releases").mkdir(exist_ok=True)
    (tmp_path / "releases" / asset).write_bytes(data)
    return {
        "id": "code430.test-town",
        "folder": "test-town",
        "repo": "Code430Packs/Location-TestTown",
        "tag": f"town-v{version}",
        "commit": "0" * 40,
        "asset": asset,
        "sha256": hashlib.sha256(data).hexdigest(),
    }


@pytest.fixture
def releases(tmp_path, monkeypatch):
    monkeypatch.setenv("CODE430_PACK_BASE_URL", (tmp_path / "releases").as_uri())
    return tmp_path


def test_the_game_lock_file_is_valid_and_its_packs_are_fetched():
    entries = lock.load_lock()
    assert [e["folder"] for e in entries] == [
        "ottawa-centretown",
        "ottawa-glebe",
        "ottawa-hintonburg",
    ]
    assert lock.check(entries) == []


def test_fetch_unpacks_checks_and_skips_when_current(releases):
    entry = _release(releases)
    packs = releases / "packs"
    logs: list[str] = []
    assert lock.fetch([entry], packs, logs.append) == 1
    assert json.loads((packs / "test-town" / "pack.json").read_text())["version"] == "0.2.0"
    assert lock.check([entry], packs) == []
    assert lock.fetch([entry], packs, logs.append) == 0
    assert logs[-1].startswith("ok")


def test_a_new_release_replaces_the_folder_but_keeps_the_chunk_cache(releases):
    packs = releases / "packs"
    lock.fetch([_release(releases)], packs, lambda _m: None)
    (packs / "test-town" / "chunks").mkdir()
    (packs / "test-town" / "chunks" / "chunk_0_0.glb").write_bytes(b"glb")
    (packs / "test-town" / "stale.json").write_text("{}")
    newer = _release(releases, version="0.2.1")
    assert lock.fetch([newer], packs, lambda _m: None) == 1
    assert (packs / "test-town" / "chunks" / "chunk_0_0.glb").read_bytes() == b"glb"
    assert not (packs / "test-town" / "stale.json").exists()
    assert lock.check([newer], packs) == []


def test_a_wrong_sha256_is_refused_and_nothing_is_unpacked(releases):
    entry = {**_release(releases), "sha256": "f" * 64}
    with pytest.raises(lock.LockError, match="does not match"):
        lock.fetch([entry], releases / "packs", lambda _m: None)
    assert not (releases / "packs" / "test-town").exists()


def test_check_names_a_missing_or_mismatched_pack(releases):
    entry = _release(releases)
    packs = releases / "packs"
    assert "run scripts/fetch-packs.sh" in lock.check([entry], packs)[0]
    lock.fetch([entry], packs, lambda _m: None)
    wrong_tag = {**entry, "tag": "town-v0.3.0"}
    (packs / ".fetched" / "test-town.sha256").write_text(entry["sha256"])
    assert any("doesn't match tag" in e for e in lock.check([wrong_tag], packs))


def test_a_zip_without_one_top_folder_is_refused(releases):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("pack.json", "{}")
    data = buf.getvalue()
    (releases / "releases").mkdir(exist_ok=True)
    (releases / "releases" / "flat.zip").write_bytes(data)
    entry = {**_release(releases), "asset": "flat.zip", "sha256": hashlib.sha256(data).hexdigest()}
    with pytest.raises(lock.LockError, match="one folder"):
        lock.fetch([entry], releases / "packs", lambda _m: None)


def test_a_bad_lock_file_is_refused(tmp_path):
    bad = tmp_path / "packs.lock.json"
    bad.write_text(json.dumps({"schema_version": 0, "packs": [{"id": "x"}]}))
    with pytest.raises(lock.LockError):
        lock.load_lock(bad)
