import json
from pathlib import Path

import numpy as np
import pytest

from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, SyntheticSource, apply_elevation
from osm_import.export import graph_to_dict
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.pack import (
    CHUNK_SIZE_M,
    SAMPLES_PER_CHUNK,
    TERRAIN_RES_M,
    build_terrain,
    carve_bridges,
    flatten_roads,
    sample_chunk,
    write_pack,
)
from osm_import.png import decode_heights, encode_heights, read_rgb8, write_rgb8
from osm_import.projection import Projector
from osm_import.validation import validate
from pack_tools.validate import validate_root
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


def graph_for(ways, source):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    proj = Projector.for_bbox(BBOX)
    g = build_graph(data, fr.drivable, fr.pedestrian, proj, CFG)
    cluster_junctions(g, CFG)
    apply_elevation(g, source, CFG)
    return g, proj


def test_png_round_trip():
    rgb = (np.arange(4 * 5 * 3, dtype=np.uint32) % 256).astype(np.uint8).reshape(4, 5, 3)
    assert np.array_equal(read_rgb8(write_rgb8(rgb)), rgb)


def test_height_encoding_precision():
    h = np.linspace(40.0, 90.0, 65 * 65, dtype=np.float32).reshape(65, 65)
    back = decode_heights(encode_heights(h, 40.0, 90.0), 40.0, 90.0)
    assert np.abs(back - h).max() < 0.001


def test_png_is_deterministic():
    h = np.random.default_rng(1).random((65, 65)).astype(np.float32)
    a = write_rgb8(encode_heights(h, 0.0, 1.0))
    b = write_rgb8(encode_heights(h, 0.0, 1.0))
    assert a == b


def test_sample_chunk_shape_and_edges():
    src = SyntheticSource()
    chunk = sample_chunk(src, 0, 0)
    assert chunk.heights.shape == (SAMPLES_PER_CHUNK, SAMPLES_PER_CHUNK)
    assert chunk.heights[0, 0] == pytest.approx(src.sample(0, 0))
    assert chunk.heights[-1, -1] == pytest.approx(src.sample(CHUNK_SIZE_M, CHUNK_SIZE_M))
    neighbour = sample_chunk(src, 1, 0)
    assert np.array_equal(chunk.heights[:, -1], neighbour.heights[:, 0])  # shared edge


def test_flatten_puts_terrain_under_road():
    g, _ = graph_for(
        [(1, [(-100, 20), (200, 20)], {"highway": "residential", "width": "12"})], FlatSource(50.0)
    )
    from osm_import.pack import _road_footprints

    ground, _ = _road_footprints(g)
    chunk = sample_chunk(FlatSource(50.0), 0, 0)
    chunk.heights += 5.0  # terrain 5 m above the road
    changed = flatten_roads(chunk, ground)
    assert changed > 0
    row = int(20 / TERRAIN_RES_M)  # z = 20 is on the centreline
    assert chunk.heights[row, 10] == pytest.approx(50.0 - 0.03, abs=1e-3)
    assert chunk.heights[row + 4, 10] == pytest.approx(
        55.0
    )  # 16 m: beyond half width 6 + margin 4 + shoulder 3
    assert chunk.heights[row + 2, 10] == pytest.approx(
        50.0 - 0.03, abs=1e-3
    )  # 8 m: inside the flat margin
    assert 50.0 < chunk.heights[row + 3, 10] < 55.0  # 12 m: in the shoulder blend


def test_carve_removes_bridge_deck_ridge():
    g, _ = graph_for(
        [
            (1, [(-100, 20), (0, 20)], {"highway": "primary"}),
            (
                2,
                [(0, 20), (120, 20)],
                {"highway": "primary", "bridge": "yes", "layer": "1", "width": "10"},
            ),
            (3, [(120, 20), (250, 20)], {"highway": "primary"}),
        ],
        FlatSource(50.0),
    )
    from osm_import.pack import _road_footprints

    _, bridges = _road_footprints(g)
    chunk = sample_chunk(FlatSource(50.0), 0, 0)
    row = int(20 / TERRAIN_RES_M)
    chunk.heights[row - 1 : row + 2, 0:32] = 58.0  # the DTM's deck ridge
    changed = carve_bridges(chunk, bridges)
    assert changed > 0
    assert chunk.heights[row, 15] == pytest.approx(50.0, abs=0.5)


def test_write_pack_validates_and_round_trips(tmp_path: Path):
    ways = [
        (1, [(-300, 0), (0, 0), (300, 0)], {"highway": "secondary", "name": "Main"}),
        (2, [(0, -300), (0, 0), (0, 300)], {"highway": "residential", "name": "Cross"}),
    ]
    g, proj = graph_for(ways, SyntheticSource())
    bounds = proj.bbox_local(BBOX)
    report = validate(g, CFG, bounds)
    chunks, stats = build_terrain(g, SyntheticSource(), bounds)
    assert stats["chunks"] == len(chunks) > 0
    gd = graph_to_dict(g, BBOX, proj.frame, [{"kind": "synthetic"}], "test", {"kind": "synthetic"})
    out = tmp_path / "pack"
    paths = write_pack(
        out,
        "code430.test-map",
        "Test Map",
        "0.1.0",
        gd,
        report.to_dict(),
        "# r\n",
        chunks,
        proj.frame,
        BBOX,
        None,
    )
    reports = validate_root(out)
    assert reports and all(r.ok for r in reports), [r.errors for r in reports]
    index = json.loads(paths["terrain"].read_text())
    first = index["chunks"][0]
    rgb = read_rgb8((out / first["file"]).read_bytes())
    heights = decode_heights(rgb, first["min_y"], first["max_y"])
    assert heights.shape == (SAMPLES_PER_CHUNK, SAMPLES_PER_CHUNK)
    assert np.abs(heights - chunks[0].heights).max() < 0.01
    assert json.loads(paths["overrides"].read_text()) == {
        "schema_version": 0,
        "edges": {},
        "nodes": {},
    }


def test_lower_road_owns_terrain_where_roads_cross_without_a_node():
    """An embankment road at 71 m crossing an underpass street at 68 m must not wall off the street."""
    from osm_import.pack import _road_footprints

    data = make_data(
        [
            (1, [(-120, 40), (120, 40)], {"highway": "secondary", "name": "Under", "width": "10"}),
            (2, [(40, -120), (40, 200)], {"highway": "motorway", "name": "Over", "width": "14"}),
        ]
    )
    fr = filter_ways(data, CFG)
    proj = Projector.for_bbox(BBOX)
    g = build_graph(data, fr.drivable, fr.pedestrian, proj, CFG)

    class TwoLevels:
        def sample(self, x, z):
            return 71.0 if abs(x - 40) < 12 else 68.0  # DTM shows the embankment

        def describe(self):
            return {"kind": "two-levels"}

    apply_elevation(g, TwoLevels(), CFG)
    ground, _ = _road_footprints(g)
    chunk = sample_chunk(TwoLevels(), 0, 0)
    flatten_roads(chunk, ground)
    row, col = int(40 / TERRAIN_RES_M), int(40 / TERRAIN_RES_M)  # the crossing cell
    assert chunk.heights[row, col] < 69.0
    assert chunk.heights[row, col - 4] < 69.0  # still on Under, 16 m west, inside Over's shoulder
