import hashlib
from pathlib import Path

import third_party_check as tpc


def _pack(repo: Path, files: dict[str, bytes], source: str | None) -> Path:
    folder = repo / "art" / "someone" / "pack"
    folder.mkdir(parents=True)
    for name, data in files.items():
        (folder / name).write_bytes(data)
    if source is not None:
        (folder / "SOURCE.md").write_text(source, encoding="utf-8")
    return folder


def _listing(files: dict[str, bytes]) -> str:
    return "\n".join(f"{hashlib.sha256(d).hexdigest()}  {n}" for n, d in files.items())


def test_a_receipted_pack_passes(tmp_path):
    files = {"Car.glb": b"car"}
    _pack(tmp_path, files, f"License: CC0\n## Receipt\nhttps://example.org\n{_listing(files)}\n")
    assert tpc.check(tmp_path) == []


def test_the_packs_own_licence_file_counts_as_the_receipt(tmp_path):
    files = {"Car.glb": b"car"}
    folder = _pack(tmp_path, files, f"License: CC0\n{_listing(files)}\n")
    (folder / "License.txt").write_text("CC0 1.0 Universal", encoding="utf-8")
    assert tpc.check(tmp_path) == []


def test_missing_source_md_fails(tmp_path):
    _pack(tmp_path, {"Car.glb": b"car"}, None)
    assert any("no SOURCE.md" in p for p in tpc.check(tmp_path))


def test_a_licence_other_than_cc0_fails(tmp_path):
    files = {"Car.glb": b"car"}
    _pack(tmp_path, files, f"License: CC-BY 4.0\n## Receipt\n{_listing(files)}\n")
    assert any("License: CC0" in p for p in tpc.check(tmp_path))


def test_no_receipt_fails(tmp_path):
    files = {"Car.glb": b"car"}
    _pack(tmp_path, files, f"License: CC0\n{_listing(files)}\n")
    assert any("Receipt" in p for p in tpc.check(tmp_path))


def test_an_unlisted_or_changed_file_fails(tmp_path):
    files = {"Car.glb": b"car"}
    folder = _pack(tmp_path, files, f"License: CC0\n## Receipt\n{_listing(files)}\n")
    (folder / "Extra.glb").write_bytes(b"extra")
    (folder / "Car.glb").write_bytes(b"swapped")
    problems = tpc.check(tmp_path)
    assert any("Extra.glb: not listed" in p for p in problems)
    assert any("Car.glb: sha256 differs" in p for p in problems)


def test_built_models_need_a_source_md(tmp_path):
    out = tmp_path / "game" / "assets" / "vehicles"
    out.mkdir(parents=True)
    (out / "sedan.glb").write_bytes(b"x")
    assert any("models without a SOURCE.md" in p for p in tpc.check(tmp_path))
    (out / "SOURCE.md").write_text("Built by tools/vehicle_kit", encoding="utf-8")
    assert tpc.check(tmp_path) == []


def test_the_budget(tmp_path, monkeypatch):
    files = {"Car.glb": b"x" * 2048}
    _pack(tmp_path, files, f"License: CC0\n## Receipt\n{_listing(files)}\n")
    monkeypatch.setattr(tpc, "BUDGET_BYTES", 1024)
    assert any("art budget" in p for p in tpc.check(tmp_path))


def test_the_repository_passes():
    assert tpc.check(Path(__file__).resolve().parents[2]) == []
