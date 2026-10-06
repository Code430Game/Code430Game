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


def test_path_under_a_bridge_is_cut_but_deck_sidewalk_kept():
    from osm_import.elevation import split_pedestrian_under_bridges
    from osm_import.graph import PedestrianWay

    g, _ = build(
        [
            (1, [(-100, 0), (-30, 0)], {"highway": "primary"}),
            (
                2,
                [(-30, 0), (30, 0)],
                {"highway": "primary", "bridge": "yes", "layer": "1", "width": "10"},
            ),
            (3, [(30, 0), (100, 0)], {"highway": "primary"}),
        ],
        FlatSource(10.0),
    )
    path = PedestrianWay(
        "p1",
        [(0.0, 4.0, -40.0), (0.0, 4.0, -3.0), (0.0, 4.0, 3.0), (0.0, 4.0, 40.0)],
        "footway",
        1,
        None,
        "path",
        1.5,
    )
    deck_walk = PedestrianWay(
        "p2", [(-30.0, 16.1, 4.5), (30.0, 16.1, 4.5)], "footway", 2, None, "sidewalk", 2.0
    )
    g.pedestrian = [path, deck_walk]
    assert split_pedestrian_under_bridges(g) == 1
    ids = sorted(w.id for w in g.pedestrian)
    assert ids == ["p2"]  # the path had no piece with two vertices left outside the deck


def test_cycleway_across_a_street_is_flush_with_it_and_ramps_at_the_curb():
    from osm_import.elevation import apply_pedestrian_elevation
    from osm_import.graph import PedestrianWay

    g, _ = build(
        [(1, [(-100, 0), (100, 0)], {"highway": "residential", "width": "8"})], FlatSource(10.0)
    )
    track = PedestrianWay(
        "p1", [(0.0, 0.0, -20.0), (0.0, 0.0, 20.0)], "cycleway", 1, None, "cycleway", 2.0
    )
    g.pedestrian = [track]
    apply_pedestrian_elevation(g, FlatSource(10.0), CFG)
    pts = track.polyline
    curb = float(CFG.pedestrian.get("curb_height_m", 0.12))
    # terrain, curb ramp, flush, flush, curb ramp, terrain: the step sits at the road edge.
    ys = [round(p[1], 3) for p in pts]
    assert ys == [10.0, round(10.0 + curb, 3), 10.02, 10.02, round(10.0 + curb, 3), 10.0], pts
    zs = [p[2] for p in pts]
    assert zs == sorted(zs)
    assert 0.3 < zs[2] - zs[1] < 0.5 and 0.3 < zs[4] - zs[3] < 0.5, zs
    assert pts[0][2] == -20.0 and pts[-1][2] == 20.0


def test_sidewalks_follow_roads_on_their_own_layer():
    """Issue #14: a bridge's sidewalk crossing right above the street below took that street's
    height and lay across it; a street's sidewalk passing under a bridge must not ride the deck."""
    from osm_import.elevation import apply_pedestrian_elevation
    from osm_import.graph import PedestrianWay

    g, _ = build(OVERPASS, FlatSource(10.0))
    deck = next(e for e in g.edges.values() if e.bridge)
    below = next(e for e in g.edges.values() if e.name == "Below")
    deck_y = max(p[1] for p in deck.polyline)
    below_y = min(p[1] for p in below.polyline)
    assert deck_y - below_y > 4.0  # the deck clears the street
    hw = deck.width_m / 2.0
    on_deck = PedestrianWay(
        "p1",
        [(-25.0, 0.0, hw + 1.0), (0.0, 0.0, hw + 1.0), (25.0, 0.0, hw + 1.0)],
        "footway",
        1,
        None,
        "sidewalk",
        2.0,
        layer=1,
    )
    at_street = PedestrianWay(
        "p2",
        [(6.0, 0.0, -40.0), (6.0, 0.0, 0.0), (6.0, 0.0, 40.0)],
        "footway",
        2,
        None,
        "sidewalk",
        2.0,
    )
    g.pedestrian = [on_deck, at_street]
    apply_pedestrian_elevation(g, FlatSource(10.0), CFG)
    over_street = min(on_deck.polyline, key=lambda p: abs(p[0]))
    assert over_street[1] > deck_y - 0.5, on_deck.polyline
    under_deck = min(at_street.polyline, key=lambda p: abs(p[2]))
    assert under_deck[1] < below_y + 1.0, at_street.polyline


def test_a_sidewalk_does_not_climb_onto_a_road_overhead_on_its_own_layer():
    """The 417 over Metcalfe: the motorway's approach segments are layer 0 like the street, but
    6 m above it, and nearer to the sidewalk under them than the street is. The sidewalk keeps
    to the street's level rather than jumping up to theirs."""
    from osm_import.elevation import apply_pedestrian_elevation
    from osm_import.graph import PedestrianWay

    g, _ = build(
        [
            (1, [(0, -300), (0, 300)], {"highway": "secondary", "name": "Street"}),
            (2, [(-300, 0), (300, 0)], {"highway": "motorway", "name": "Overhead"}),
        ],
        FlatSource(10.0),
    )
    over = [e for e in g.edges.values() if e.name == "Overhead"]
    for e in over:
        e.polyline = [(x, 16.0, z) for x, _y, z in e.polyline]
    walk = PedestrianWay(
        "p1", [(7.0, 0.0, float(z)) for z in range(-40, 41, 5)], "footway", 1, None, "sidewalk", 2.0
    )
    g.pedestrian = [walk]
    apply_pedestrian_elevation(g, FlatSource(10.0), CFG)
    ys = [p[1] for p in walk.polyline]
    assert max(ys) < 11.0, walk.polyline


def test_bridge_tag_puts_a_pedestrian_way_on_layer_one():
    g, _ = build(
        [
            (1, [(-100, 0), (100, 0)], {"highway": "residential"}),
            (
                2,
                [(-50, 5), (50, 5)],
                {"highway": "footway", "footway": "sidewalk", "bridge": "yes"},
            ),
            (3, [(-50, -5), (50, -5)], {"highway": "footway", "footway": "sidewalk"}),
            (4, [(-50, 9), (50, 9)], {"highway": "footway", "bridge": "yes", "layer": "2"}),
        ],
        FlatSource(10.0),
    )
    layers = {w.osm_way_id: w.layer for w in g.pedestrian}
    assert layers == {2: 1, 3: 0, 4: 2}
