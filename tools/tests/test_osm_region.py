"""Region rules (add-pack-repositories 1.6 and 1.2c): a pinned origin that a re-export can't
move by accident, and district borders on the chunk grid that don't overlap."""

import json
from pathlib import Path

import pytest

from osm_import import __main__ as importer
from osm_import.osm_data import BBox
from osm_import.pack import CHUNK_SIZE_M
from osm_import.projection import Projector
from osm_import.region import (
    RegionError,
    border_bbox,
    check_origin,
    check_siblings,
    projector_for,
)

REPO = Path(__file__).resolve().parents[2]
OTTAWA_BBOX = BBox(45.405, -75.715, 45.435, -75.675)
OTTAWA = {"lat": 45.4200027, "lon": -75.6950007}


def test_ottawas_pinned_origin_is_the_frame_it_was_built_with():
    pack = json.loads((REPO / "packs/ottawa-centretown/pack.json").read_text())
    region = json.loads((REPO / "regions/ottawa-centretown.json").read_text())
    proj, bbox = projector_for(region, OTTAWA_BBOX)
    assert bbox == OTTAWA_BBOX
    o = pack["map"]["origin"]
    assert (proj.frame.origin_easting, proj.frame.origin_northing) == (o["easting"], o["northing"])
    assert proj.frame.crs == pack["map"]["crs"]
    assert proj.frame == Projector.for_bbox(OTTAWA_BBOX).frame


def test_a_wider_box_keeps_a_pinned_origin():
    wider = BBox(45.40, -75.73, 45.44, -75.67)
    assert Projector.for_bbox(wider).frame != Projector.for_bbox(OTTAWA_BBOX).frame
    proj, _ = projector_for({"bbox": wider.as_list(), "origin": OTTAWA}, wider)
    assert proj.frame == Projector.for_bbox(OTTAWA_BBOX).frame


def test_a_border_gives_the_box_around_its_chunks():
    region = {"origin": OTTAWA, "border": {"chunks": [-2, -1, 3, 2]}}
    proj, bbox = projector_for(region, None)
    for x in (-2, 3):
        for z in (-1, 2):
            lat, lon = proj.to_latlon(x * CHUNK_SIZE_M, z * CHUNK_SIZE_M)
            assert bbox.south - 1e-6 <= lat <= bbox.north + 1e-6
            assert bbox.west - 1e-6 <= lon <= bbox.east + 1e-6
            back = proj.to_local(lat, lon)
            assert back == pytest.approx((x * CHUNK_SIZE_M, z * CHUNK_SIZE_M), abs=0.01)
    assert border_bbox((-2, -1, 3, 2), proj) == bbox


@pytest.mark.parametrize(
    "region, message",
    [
        ({"border": {"chunks": [0, 0, 2, 2]}}, "needs a pinned origin"),
        ({"origin": OTTAWA, "bbox": [1, 2, 3, 4], "border": {"chunks": [0, 0, 2, 2]}}, "not both"),
        ({"origin": OTTAWA, "border": {"chunks": [0, 0, 0, 2]}}, "is empty"),
        ({"origin": OTTAWA, "border": {"chunks": [0, 0, 1.5, 2]}}, "whole chunks"),
        ({"origin": {"lat": 45.0}}, "origin must be"),
    ],
)
def test_bad_regions_are_refused(region, message):
    with pytest.raises(RegionError, match=message):
        projector_for(region, OTTAWA_BBOX if "bbox" not in region else None)


def _write(path: Path, data: dict) -> Path:
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def test_sibling_districts_must_not_share_chunks(tmp_path):
    _write(tmp_path / "centretown.json", {"origin": OTTAWA, "border": {"chunks": [-6, -6, 6, 6]}})
    _write(
        tmp_path / "elsewhere.json",
        {"origin": {"lat": 45.0, "lon": -75.0}, "border": {"chunks": [0, 6, 4, 10]}},
    )
    glebe = {"origin": OTTAWA, "border": {"chunks": [-2, 6, 4, 12]}}
    check_siblings(_write(tmp_path / "glebe.json", glebe), glebe)  # touches, doesn't overlap
    glebe["border"]["chunks"] = [-2, 5, 4, 12]
    with pytest.raises(RegionError, match="overlaps centretown.json"):
        check_siblings(_write(tmp_path / "glebe.json", glebe), glebe)


def test_a_re_export_that_moves_the_origin_is_refused(tmp_path):
    pack = tmp_path / "pack"
    pack.mkdir()
    frame = Projector.for_bbox(OTTAWA_BBOX).frame
    _write(pack / "pack.json", {"map": {"crs": frame.crs, "origin": frame.to_dict()}})
    check_origin(pack, frame, allow_new=False)
    moved = Projector.for_bbox(BBox(45.40, -75.73, 45.44, -75.67)).frame
    with pytest.raises(RegionError, match="move the pack's origin"):
        check_origin(pack, moved, allow_new=False)
    check_origin(pack, moved, allow_new=True)
    check_origin(tmp_path / "new", moved, allow_new=False)  # a first export has nothing to move


def test_the_importer_pins_the_origin_and_refuses_moving_it(tmp_path, monkeypatch):
    """The proving ground with its origin pinned builds byte for byte the same pack; a second
    export with another origin into it stops before doing any work."""
    pg_region = REPO / "regions/proving-ground.json"
    region = json.loads(pg_region.read_text())
    committed = json.loads((REPO / "packs/proving-ground/pack.json").read_text())
    o = committed["map"]["origin"]
    region["origin"] = {"lat": o["lat"], "lon": o["lon"]}
    base = pg_region.parent
    region["inputs"] = {k: str(base / v) for k, v in region["inputs"].items()}
    region["extras"] = [str(base / v) for v in region["extras"]]
    path = _write(tmp_path / "proving-ground.json", region)
    out = tmp_path / "pack"
    argv = ["--region", str(path), "--pack-out", str(out), "--pack-version", "0.1.0"]
    assert importer.main(argv) == 0
    assert (out / "pack.json").read_bytes() == (
        REPO / "packs/proving-ground/pack.json"
    ).read_bytes()
    assert (out / "road_graph.v0.json").read_bytes() == (
        REPO / "packs/proving-ground/road_graph.v0.json"
    ).read_bytes()
    region["origin"] = {"lat": o["lat"] + 0.001, "lon": o["lon"]}
    _write(path, region)
    with pytest.raises(SystemExit, match="move the pack's origin"):
        importer.main(argv)
