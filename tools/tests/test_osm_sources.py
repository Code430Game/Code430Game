"""Every Overpass layer in a pack records where it came from (AGENTS.md, map data)."""

import json
from pathlib import Path

from osm_import.__main__ import main
from osm_import.bridges import bridges_query
from osm_import.buildings import buildings_query
from osm_import.fetch import _cache_paths, overpass_query
from osm_import.osm_data import BBox
from osm_import.parking import parking_query
from osm_import.services import services_query
from osm_import.vegetation import vegetation_query
from osm_import.water import water_query
from tests.osm_helpers import BASE_LAT, BASE_LON, make_data

LAYERS = ["roads", "water", "buildings", "bridges", "parking", "vegetation", "services"]


def _cache(cache: Path, bbox: BBox) -> None:
    """A download cache holding every query the import makes, so it runs offline."""
    roads = make_data([(1, [(-60.0, 0.0), (60.0, 0.0)], {"highway": "residential"})])
    queries = [
        overpass_query(bbox),
        water_query(bbox),
        buildings_query(bbox),
        bridges_query(bbox),
        parking_query(bbox),
        vegetation_query(bbox),
        services_query(bbox),
    ]
    cache.mkdir()
    for n, (layer, query) in enumerate(zip(LAYERS, queries, strict=True)):
        data_path, meta_path = _cache_paths(cache, query)
        payload = roads.to_overpass_json() if layer == "roads" else {"elements": []}
        data_path.write_text(json.dumps(payload), encoding="utf-8")
        meta = {
            "kind": "overpass",
            "url": "https://overpass.example/api/interpreter",
            "query": query,
            "bbox": bbox.as_list(),
            "fetched_at": f"2026-10-0{n + 1}T00:00:00+00:00",
            "license": "ODbL-1.0",
            "attribution": "© OpenStreetMap contributors",
        }
        meta_path.write_text(json.dumps(meta), encoding="utf-8")


def test_each_layer_records_its_source_url_and_time(tmp_path: Path):
    """Review fix: only the roads query was recorded; water, buildings, bridges, parking,
    vegetation and services dropped theirs, though each is its own snapshot of the map."""
    bbox = BBox(BASE_LAT - 0.001, BASE_LON - 0.0015, BASE_LAT + 0.001, BASE_LON + 0.0015)
    _cache(tmp_path / "cache", bbox)
    pack = tmp_path / "pack"
    argv = [
        "import",
        "--bbox",
        ",".join(str(v) for v in bbox.as_list()),
        "--pack-out",
        str(pack),
        "--pack-id",
        "test.sources",
        "--dem",
        "flat",
        "--cache-dir",
        str(tmp_path / "cache"),
    ]
    assert main(argv) == 0
    meta = json.loads((pack / "road_graph.v0.json").read_text(encoding="utf-8"))["meta"]
    assert [s["layer"] for s in meta["sources"]] == LAYERS
    for n, s in enumerate(meta["sources"]):
        assert s["url"] == "https://overpass.example/api/interpreter"
        assert s["fetched_at"] == f"2026-10-0{n + 1}T00:00:00+00:00"
