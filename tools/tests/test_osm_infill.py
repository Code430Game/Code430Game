"""Concrete infill between carriageways of one bridge, and no parapets facing it
(add-road-shoulders 1.4)."""

import math

import pytest

from osm_import.barriers import build_barriers
from osm_import.bridges import INFILL_PREFIX, build_bridges
from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, apply_elevation, apply_pedestrian_elevation
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()
GROUND = 10.0
DECK = {"highway": "motorway", "oneway": "yes", "bridge": "yes", "layer": "1", "width": "10"}


def graph_for(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    apply_elevation(g, FlatSource(GROUND), CFG)
    apply_pedestrian_elevation(g, FlatSource(GROUND), CFG)
    return g


def ground(_x, _z):
    return GROUND


def two_decks(spacing: float):
    """Two 10 m one-way decks `spacing` apart centre to centre, over a street."""
    return [
        (1, [(-60, 0), (60, 0)], DECK),
        (2, [(60, spacing), (-60, spacing)], DECK),
        (3, [(0, -150), (0, 150)], {"highway": "residential", "width": "8"}),
    ]


def z_on(g, edge_id, x):
    pl = g.edges[edge_id].polyline
    a, b = (pl[0], pl[-1]) if pl[0][0] < pl[-1][0] else (pl[-1], pl[0])
    return a[2] + (b[2] - a[2]) * (x - a[0]) / (b[0] - a[0])


def infill(r):
    return [d for b in r.bridges for d in b.decks if d.source.startswith(INFILL_PREFIX)]


def test_a_gap_between_decks_gets_a_floor_at_deck_height():
    g = graph_for(two_decks(15.0))  # 5 m between the deck edges
    r = build_bridges(g, ground, CFG.bridges)
    strips = infill(r)
    assert len(strips) == 1 and r.infill_strips == 1
    s = strips[0]
    deck_y = g.edges["w1.0"].polyline[0][1]
    for (x, y, z), half in zip(s.points, s.left_m, strict=True):
        assert y == pytest.approx(deck_y, abs=0.01)
        assert abs(z - (z_on(g, "w1.0", x) + z_on(g, "w2.0", x)) / 2.0) < 0.3
        assert half == pytest.approx(2.5 + CFG.bridges["infill_overlap_m"], abs=0.2)
        assert -61.0 <= x <= 61.0  # never past the decks' ends
    assert s.left_m == s.right_m
    length = sum(math.dist(a[::2], b[::2]) for a, b in zip(s.points, s.points[1:], strict=False))
    assert length > 110.0  # the whole span


def test_decks_too_far_apart_get_no_floor():
    g = graph_for(two_decks(20.0))  # 10 m between the deck edges
    assert infill(build_bridges(g, ground, CFG.bridges)) == []


def test_decks_at_different_layers_get_no_floor():
    ways = two_decks(15.0)
    ways[1] = (2, ways[1][1], {**DECK, "layer": "2"})
    assert infill(build_bridges(graph_for(ways), ground, CFG.bridges)) == []


def test_no_parapet_faces_the_floor_but_the_outer_ones_stay():
    g = graph_for(two_decks(15.0))
    r = build_bridges(g, ground, CFG.bridges)
    with_floor = build_barriers(g, FlatSource(GROUND), None, CFG, None, r.infill())
    without = build_barriers(g, FlatSource(GROUND), None, CFG, None, [])

    def inner(barriers):
        out = []
        for b in barriers.barriers:
            for x, _y, z in b.points if b.kind == "parapet" else []:
                lo, hi = sorted((z_on(g, "w1.0", x), z_on(g, "w2.0", x)))
                if lo + 1.0 < z < hi - 1.0 and -50.0 < x < 50.0:
                    out.append((x, z))
        return out

    assert inner(without)  # the facing parapets stood in the gap before
    assert inner(with_floor) == []
    outer = [b for b in with_floor.barriers if b.kind == "parapet"]
    assert len(outer) >= 2  # the two outside edges keep theirs


def test_a_ramp_splitting_from_a_deck_is_floored_up_to_the_limit():
    ramp = {**DECK, "highway": "motorway_link", "width": "6"}
    ways = [
        (1, [(-60, 0), (0, 0), (60, 0)], DECK),
        (2, [(0, 0), (60, 12)], ramp),  # splits off at x 0 and drifts away
        (3, [(30, -150), (30, 150)], {"highway": "residential", "width": "8"}),
    ]
    g = graph_for(ways)
    r = build_bridges(g, ground, CFG.bridges)
    strips = infill(r)
    assert strips
    limit = CFG.bridges["infill_max_m"]
    for s in strips:
        for half in s.left_m:
            assert half <= limit / 2.0 + CFG.bridges["infill_overlap_m"] + 1e-6
