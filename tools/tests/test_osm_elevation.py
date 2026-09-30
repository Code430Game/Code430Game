import math

import pytest

from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, GridSource, SyntheticSource, apply_elevation
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


def build(ways, source):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    return g, apply_elevation(g, source, CFG)


def grades(edge):
    pts = edge.polyline
    return [
        abs(pts[i + 1][1] - pts[i][1]) / math.dist(pts[i][::2], pts[i + 1][::2])
        for i in range(len(pts) - 1)
    ]


OVERPASS = [
    (1, [(-400, 0), (-30, 0)], {"highway": "secondary", "name": "West approach"}),
    (
        2,
        [(-30, 0), (30, 0)],
        {"highway": "secondary", "bridge": "yes", "layer": "1", "name": "Deck"},
    ),
    (3, [(30, 0), (400, 0)], {"highway": "secondary", "name": "East approach"}),
    (4, [(0, -300), (0, 300)], {"highway": "residential", "name": "Below"}),
]


def test_flat_terrain_gives_zero_heights():
    g, stats = build([(1, [(0, 0), (100, 0), (200, 0)], {"highway": "residential"})], FlatSource())
    assert stats.fixed_vertices == 0
    assert all(p[1] == 0.0 for e in g.edges.values() for p in e.polyline)


def test_bridge_on_flat_ground_rises_by_clearance_and_approaches_ramp():
    g, stats = build(OVERPASS, FlatSource(10.0))
    deck = g.edges["w2.0"]
    assert all(
        p[1] == pytest.approx(10.0 + CFG.bridge_clearance_m, abs=1e-6) for p in deck.polyline
    )
    below = g.edges["w4.0"]
    assert all(p[1] == pytest.approx(10.0) for p in below.polyline)  # does not touch the bridge
    limit = CFG.for_class("secondary").max_grade
    for eid in ("w1.0", "w3.0"):
        e = g.edges[eid]
        assert max(grades(e)) <= limit + 1e-6
        far_end = e.polyline[0] if eid == "w1.0" else e.polyline[-1]
        assert far_end[1] == pytest.approx(10.0)  # 370 m is enough to return to ground
    assert stats.bound_conflicts == 0 and stats.edges_over_grade == []


def test_bridge_over_a_trench_stays_level_with_its_abutments():
    class Trench:
        def sample(self, x, z):
            return 20.0 if abs(x) < 15 else 30.0  # 10 m deep trench under the deck

        def describe(self):
            return {"kind": "trench"}

    g, stats = build(OVERPASS, Trench())
    deck = g.edges["w2.0"]
    assert all(p[1] == pytest.approx(30.0) for p in deck.polyline)
    assert stats.vertices_clamped == 0


def test_tunnel_sinks_below_ground():
    ways = [
        (1, [(-400, 0), (-30, 0)], {"highway": "primary"}),
        (2, [(-30, 0), (30, 0)], {"highway": "primary", "tunnel": "yes", "layer": "-1"}),
        (3, [(30, 0), (400, 0)], {"highway": "primary"}),
    ]
    g, _ = build(ways, FlatSource(50.0))
    tunnel = g.edges["w2.0"]
    assert all(p[1] == pytest.approx(50.0 - CFG.bridge_clearance_m) for p in tunnel.polyline)


def test_steep_natural_slope_is_limited_to_class_grade():
    class Cliff:
        def sample(self, x, z):
            return 0.0 if x < 0 else 30.0

        def describe(self):
            return {"kind": "cliff"}

    ways = [(1, [(-300, 0), (-10, 0), (10, 0), (300, 0)], {"highway": "residential"})]
    g, stats = build(ways, Cliff())
    e = g.edges["w1.0"]
    assert max(grades(e)) <= CFG.for_class("residential").max_grade + 1e-3
    assert stats.edges_over_grade == []


def test_grid_source_bilinear():
    import numpy as np

    heights = np.array([[0.0, 10.0], [20.0, 30.0]], dtype=np.float32)
    src = GridSource(heights, min_x=0.0, min_z=0.0, res=10.0)
    assert src.sample(0, 0) == pytest.approx(0.0)
    assert src.sample(5, 0) == pytest.approx(5.0)
    assert src.sample(0, 5) == pytest.approx(10.0)
    assert src.sample(5, 5) == pytest.approx(15.0)
    assert src.sample(-100, -100) == pytest.approx(0.0)  # clamped to the grid


def test_shared_node_is_continuous_across_edges():
    ways = [
        (1, [(-200, 0), (0, 0), (200, 0)], {"highway": "secondary"}),
        (2, [(0, -200), (0, 0), (0, 200)], {"highway": "residential"}),
    ]
    g, _ = build(ways, SyntheticSource())
    centre = g.nodes["n1001"].position[1]
    for e in g.edges.values():
        for nid, p in ((e.from_node, e.polyline[0]), (e.to_node, e.polyline[-1])):
            if nid == "n1001":
                assert p[1] == centre
    assert centre == pytest.approx(SyntheticSource().sample(0, 0), abs=0.5)


def test_elevation_is_deterministic():
    g1, _ = build(OVERPASS, SyntheticSource())
    g2, _ = build(OVERPASS, SyntheticSource())
    for eid in g1.edges:
        assert g1.edges[eid].polyline == g2.edges[eid].polyline
