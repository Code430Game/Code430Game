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


def test_carve_never_leaves_a_hillside_above_a_deck():
    # A deck at 50 m through a 70 m hill: the refill seeds from the hill, so the ground under
    # the deck must be forced below the deck or the road is buried at the abutment.
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
    from osm_import.pack import BRIDGE_UNDER_DECK_M, _road_footprints

    _, bridges = _road_footprints(g)
    chunk = sample_chunk(FlatSource(50.0), 0, 0)
    chunk.heights[:, :] = 70.0
    carve_bridges(chunk, bridges)
    row = int(20 / TERRAIN_RES_M)
    deck_y = g.edges["w2.0"].polyline[0][1]
    assert chunk.heights[row, 15] <= deck_y - BRIDGE_UNDER_DECK_M + 0.01
    assert chunk.heights[row, 60] == pytest.approx(70.0)  # well off the deck: untouched


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


def test_a_turf_in_the_overrides_becomes_the_packs_turf_file(tmp_path: Path):
    """A hand-placed turf (add-hostile-gang 1.2) rides from overrides.json into turf.v0.json."""
    ways = [
        (1, [(-300, 0), (0, 0), (300, 0)], {"highway": "secondary", "name": "Main"}),
        (2, [(0, -300), (0, 0), (0, 300)], {"highway": "residential", "name": "Cross"}),
    ]
    g, proj = graph_for(ways, SyntheticSource())
    bounds = proj.bbox_local(BBOX)
    report = validate(g, CFG, bounds)
    chunks, _stats = build_terrain(g, SyntheticSource(), bounds)
    gd = graph_to_dict(g, BBOX, proj.frame, [{"kind": "synthetic"}], "test", {"kind": "synthetic"})
    out = tmp_path / "pack"
    out.mkdir()
    turf = {
        "id": "market",
        "name": "the Market crew",
        "faction": "double-cross",
        "ring": [[-50.0, -50.0], [50.0, -50.0], [50.0, 50.0], [-50.0, 50.0]],
    }
    (out / "overrides.json").write_text(
        json.dumps({"schema_version": 0, "edges": {}, "nodes": {}, "turf": [turf]}),
        encoding="utf-8",
    )
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
    assert json.loads(paths["turf"].read_text()) == {"schema_version": 0, "turfs": [turf]}
    reports = validate_root(out)
    assert reports and all(r.ok for r in reports), [r.errors for r in reports]


def test_a_lower_sidewalk_beside_a_road_does_not_pull_the_road_edge_down():
    """A corner where the street climbs away from the junction: the sidewalk 1 m lower than the
    road beside it used to win the cells at the road's edge, leaving a 1 m wheel trap."""
    from osm_import.pack import PEDESTRIAN

    road = (-100.0, 20.0, 200.0, 20.0, 52.0, 52.0, 4.0)  # 8 m wide at 52 m: edge at z = 24
    sidewalk = (-100.0, 26.0, 200.0, 26.0, 51.0, 51.0, 1.0, 4.0, 3.0, PEDESTRIAN)
    chunk = sample_chunk(FlatSource(50.0), 0, 0)
    flatten_roads(chunk, [road, sidewalk])
    edge_row = int(24 / TERRAIN_RES_M)
    assert chunk.heights[edge_row, 10] == pytest.approx(52.0 - 0.03, abs=1e-3)
    assert chunk.heights[int(20 / TERRAIN_RES_M), 10] == pytest.approx(52.0 - 0.03, abs=1e-3)


def test_a_road_under_a_sidewalk_still_owns_the_ground_it_covers():
    """The lower-surface rule still holds where one surface is over another: a road under a
    curb-height sidewalk keeps the ground at the road."""
    from osm_import.pack import PEDESTRIAN

    road = (-100.0, 20.0, 200.0, 20.0, 50.0, 50.0, 4.0)
    sidewalk = (-100.0, 21.0, 200.0, 21.0, 50.12, 50.12, 1.0, 4.0, 3.0, PEDESTRIAN)
    chunk = sample_chunk(FlatSource(49.0), 0, 0)
    flatten_roads(chunk, [road, sidewalk])
    assert chunk.heights[int(20 / TERRAIN_RES_M), 10] == pytest.approx(50.0 - 0.03, abs=1e-3)


def test_paths_the_finished_terrain_buries_are_lifted_onto_it():
    from types import SimpleNamespace

    from osm_import.pack import LIFT_ABOVE_M, lift_buried_paths

    buried = SimpleNamespace(
        covered=False, profile="", kind="sidewalk", polyline=[(0.0, 51.0, 0.0), (10.0, 52.0, 0.0)]
    )
    tunnel = SimpleNamespace(
        covered=False, profile="tunnel", kind="footway", polyline=[(0.0, 45.0, 0.0)]
    )
    steps = SimpleNamespace(covered=False, profile="", kind="steps", polyline=[(0.0, 40.0, 0.0)])
    graph = SimpleNamespace(pedestrian=[buried, tunnel, steps])
    assert lift_buried_paths(graph, lambda x, z: 52.0) == 1
    assert buried.polyline[0][1] == pytest.approx(52.0 + LIFT_ABOVE_M)
    assert buried.polyline[1][1] == pytest.approx(52.0)  # level with the ground already
    assert tunnel.polyline[0][1] == 45.0 and steps.polyline[0][1] == 40.0
