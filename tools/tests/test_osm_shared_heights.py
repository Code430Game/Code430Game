"""Touching carriageways share one height (update-shared-deck-heights 1.1, 1.2)."""

import dataclasses
import itertools
import math

import pytest

from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import apply_elevation
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from osm_import.shoulders import trim_shoulders
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


class Step:
    """Flat ground, `high` metres higher south of z = 0 (where the second carriageway runs)."""

    def __init__(self, low: float = 10.0, high: float = 10.5) -> None:
        self.low, self.high = low, high

    def sample(self, x: float, z: float) -> float:
        return self.high if z > 0 else self.low

    def describe(self) -> dict:
        return {"kind": "step"}


def build(ways, source, cfg=CFG):
    data = make_data(ways)
    fr = filter_ways(data, cfg)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), cfg)
    cluster_junctions(g, cfg)
    return g, apply_elevation(g, source, cfg)


def two_decks(spacing: float, layer_b: str = "1", cls: str = "secondary"):
    """Two one-way carriageways `spacing` apart (centre to centre), each a deck between two
    long approaches; the north one runs east, the south one west."""
    n, s = -spacing / 2.0, spacing / 2.0
    tags = {"highway": cls, "oneway": "yes", "lanes": "2"}
    xs = [-40.0, -20.0, 0.0, 20.0, 40.0]
    return [
        (1, [(-300.0, n), (-40.0, n)], tags),
        (2, [(x, n) for x in xs], {**tags, "bridge": "yes", "layer": "1"}),
        (3, [(40.0, n), (300.0, n)], tags),
        (4, [(300.0, s), (40.0, s)], tags),
        (5, [(x, s) for x in reversed(xs)], {**tags, "bridge": "yes", "layer": layer_b}),
        (6, [(-40.0, s), (-300.0, s)], tags),
    ]


def height_at(edge, x: float) -> float:
    """Height where the edge crosses x (clamped to its ends; local x is the drawn x to a few
    centimetres per hundred metres)."""
    pts = edge.polyline
    lo_x, hi_x = min(p[0] for p in pts), max(p[0] for p in pts)
    x = min(max(x, lo_x), hi_x)
    for a, b in itertools.pairwise(pts):
        lo, hi = sorted((a[0], b[0]))
        if lo - 1e-6 <= x <= hi + 1e-6:
            t = 0.0 if hi == lo else (x - a[0]) / (b[0] - a[0])
            return a[1] + (b[1] - a[1]) * t
    raise ValueError(x)


def grades(edge):
    pts = edge.polyline
    return [
        abs(pts[i + 1][1] - pts[i][1]) / math.dist(pts[i][::2], pts[i + 1][::2])
        for i in range(len(pts) - 1)
    ]


def test_touching_decks_with_a_half_metre_step_meet_at_one_height():
    g, stats = build(two_decks(7.5), Step())  # 7 m ribbons 0.5 m apart
    a, b = g.edges["w2.0"], g.edges["w5.0"]
    assert a.width_m == pytest.approx(7.0) and b.width_m == pytest.approx(7.0)
    for x in (-40.0, -20.0, 0.0, 20.0, 40.0):
        assert height_at(a, x) == pytest.approx(height_at(b, x), abs=0.01)
        assert height_at(a, x) == pytest.approx(10.5, abs=0.01)  # the higher deck sets it
    assert stats.shared_deck_vertices == 10
    assert stats.max_shared_step == pytest.approx(0.5, abs=0.01)


def test_the_change_blends_into_the_approaches():
    g, _stats = build(two_decks(7.5), Step())
    west = g.edges["w1.0"]  # (-300) .. (-40), the deck end
    assert west.polyline[-1][1] == pytest.approx(10.5, abs=0.01)  # meets the deck
    assert west.polyline[0][1] == pytest.approx(10.0, abs=1e-6)  # far end untouched
    limit = CFG.for_class("secondary").max_grade
    for eid in ("w1.0", "w2.0", "w3.0", "w4.0", "w5.0", "w6.0"):
        assert max(grades(g.edges[eid])) <= limit + 1e-6


def test_blend_fades_over_blend_m_on_a_finely_drawn_approach():
    ways = two_decks(7.5)
    ways[0] = (1, [(float(x), -3.75) for x in range(-300, -39, 10)], ways[0][2])
    g, _stats = build(ways, Step())
    west = g.edges["w1.0"]
    blend = CFG.shared_heights["blend_m"]
    for x, y, _z in west.polyline:
        d = -40.0 - x
        expected = 10.0 + 0.5 * max(0.0, 1.0 - d / blend)
        assert y == pytest.approx(expected, abs=0.01), x


def test_decks_further_apart_than_the_gap_keep_their_heights():
    g, stats = build(two_decks(12.0), Step())  # 5 m between the ribbons: parapets between
    assert stats.shared_deck_vertices == 0
    assert height_at(g.edges["w2.0"], 0.0) == pytest.approx(10.0, abs=0.01)
    assert height_at(g.edges["w5.0"], 0.0) == pytest.approx(10.5, abs=0.01)


def test_a_real_level_difference_is_kept():
    g, stats = build(two_decks(7.5), Step(10.0, 12.0))  # 2 m: one deck over the other's ramp
    assert stats.shared_deck_vertices == 0
    assert height_at(g.edges["w2.0"], 0.0) == pytest.approx(10.0, abs=0.01)
    assert height_at(g.edges["w5.0"], 0.0) == pytest.approx(12.0, abs=0.01)


def test_decks_on_different_layers_are_not_shared():
    _g, stats = build(two_decks(7.5, layer_b="2"), Step())
    assert stats.shared_deck_vertices == 0


def motorway_pair(spacing: float):
    """Two ground carriageways of one motorway, `spacing` apart, drawn every 20 m; driving on
    the right, so the north one runs west and their left (median) shoulders face each other."""
    n, s = -spacing / 2.0, spacing / 2.0
    xs = [float(x) for x in range(-200, 201, 20)]
    tags = {"highway": "motorway", "oneway": "yes", "lanes": "2"}
    return [
        (1, [(x, n) for x in reversed(xs)], tags),
        (2, [(x, s) for x in xs], tags),
    ]


def test_overlapping_motorway_carriageways_share_the_higher_height_on_the_ground():
    g, stats = build(motorway_pair(9.5), Step(10.0, 10.3))
    a, b = g.edges["w1.0"], g.edges["w2.0"]
    assert a.width_m == pytest.approx(10.5)  # 7 m of lanes, 1 m left and 2.5 m right shoulder
    assert stats.shared_ground_vertices == 2 * 21
    for x in (-200.0, -100.0, 0.0, 100.0, 200.0):
        assert height_at(a, x) == pytest.approx(10.3, abs=0.01)
        assert height_at(b, x) == pytest.approx(10.3, abs=0.01)


def test_shoulders_dropped_only_for_the_step_come_back():
    g, _stats = build(motorway_pair(9.5), Step(10.0, 10.3))
    assert trim_shoulders(g) == 0
    assert all(e.shoulder_left_m == pytest.approx(1.0) for e in g.edges.values())
    # Without the shared height, the 0.3 m step drops both median shoulders.
    off = dataclasses.replace(CFG, shared_heights={**CFG.shared_heights, "max_step_m": 0.0})
    g2, _ = build(motorway_pair(9.5), Step(10.0, 10.3), off)
    assert trim_shoulders(g2) == 2


def test_other_classes_on_the_ground_are_not_shared():
    ways = [
        (w, pts, {**tags, "highway": "primary"}) for w, pts, tags in motorway_pair(6.5)
    ]  # 7 m primary ribbons overlapping by half a metre
    g, stats = build(ways, Step(10.0, 10.3))
    assert stats.shared_ground_vertices == 0
    assert height_at(g.edges["w1.0"], 0.0) == pytest.approx(10.0, abs=0.01)


def test_shared_heights_are_deterministic():
    g1, _ = build(two_decks(7.5), Step())
    g2, _ = build(two_decks(7.5), Step())
    assert [e.polyline for e in g1.edges.values()] == [e.polyline for e in g2.edges.values()]


def test_a_deck_beside_the_other_carriageways_approach_shares_too():
    s = 5.75
    ways = two_decks(11.5, cls="motorway")  # 10.5 m ribbons (shoulders included) 1 m apart
    tags = ways[3][2]
    ways[3] = (4, [(300.0, s), (20.0, s)], tags)  # the south deck starts 20 m later
    ways[4] = (5, [(20.0, s), (0.0, s), (-40.0, s)], {**tags, "bridge": "yes", "layer": "1"})
    g, _stats = build(ways, Step())
    north, south_ground = g.edges["w2.0"], g.edges["w4.0"]
    for x in (25.0, 30.0, 40.0):  # beside the north deck's end, the south road is on the ground
        assert height_at(south_ground, x) == pytest.approx(height_at(north, x), abs=0.01)
    limit = CFG.for_class("motorway").max_grade
    for e in g.edges.values():
        assert max(grades(e)) <= limit + 1e-6, e.id


def test_ground_carriageways_under_a_deck_take_the_lower_height():
    over = {"highway": "secondary", "name": "Over"}
    ways = [
        *motorway_pair(9.5),
        (3, [(0.0, -300.0), (0.0, -30.0)], over),
        (4, [(0.0, -30.0), (0.0, 30.0)], {**over, "bridge": "yes", "layer": "1"}),
        (5, [(0.0, 30.0), (0.0, 300.0)], over),
    ]
    g, stats = build(ways, Step(10.0, 10.3))
    a, b = g.edges["w1.0"], g.edges["w2.0"]
    assert stats.shared_ground_vertices > 0
    assert height_at(a, 0.0) == pytest.approx(10.0, abs=0.01)  # both at the lower one
    assert height_at(b, 0.0) == pytest.approx(10.0, abs=0.01)
    assert height_at(a, 200.0) == pytest.approx(10.3, abs=0.01)  # the higher away from the deck
