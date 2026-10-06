"""Touching carriageways share one height (update-shared-deck-heights 1.1, 1.2)."""

import dataclasses
import itertools
import math

import pytest

from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import apply_elevation, clearance_shortfalls
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
    assert stats.shared_step_left < 0.01  # measured again after sharing


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


def test_overlapping_motorway_carriageways_merge_down_to_the_lower_height_on_the_ground():
    """Merge-down fix: ground carriageways take the lower height (they used to take the higher,
    which lifted the ends of merges and bowed the road between)."""
    g, stats = build(motorway_pair(9.5), Step(10.0, 10.3))
    a, b = g.edges["w1.0"], g.edges["w2.0"]
    assert a.width_m == pytest.approx(10.5)  # 7 m of lanes, 1 m left and 2.5 m right shoulder
    assert stats.shared_ground_vertices == 2 * 21
    for x in (-200.0, -100.0, 0.0, 100.0, 200.0):
        assert height_at(a, x) == pytest.approx(10.0, abs=0.01)
        assert height_at(b, x) == pytest.approx(10.0, abs=0.01)


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
    # Away from the deck too: ground carriageways merge down (merge-down fix; was the higher).
    assert height_at(a, 200.0) == pytest.approx(10.0, abs=0.01)


def test_partners_on_either_side_of_a_deck_footprint_meet_instead_of_swapping():
    """Review fix: the rule belongs to the pair. The north carriageway lies under a parallel deck
    (its vertices take the lowest), the south one doesn't; before, the north dropped to the south's
    height while the south rose to the north's, and the step stayed, swapped."""
    over = {"highway": "secondary", "name": "Over"}
    ways = [
        *motorway_pair(9.5),
        (3, [(-300.0, -18.0), (-60.0, -18.0)], over),
        (4, [(-60.0, -18.0), (60.0, -18.0)], {**over, "bridge": "yes", "layer": "1"}),
        (5, [(60.0, -18.0), (300.0, -18.0)], over),
    ]
    g, stats = build(ways, Step(10.6, 10.0))  # the north carriageway (z < 0) is the higher
    a, b = g.edges["w1.0"], g.edges["w2.0"]
    assert stats.shared_ground_vertices > 0
    for x in range(-200, 201, 20):  # one height all along, switching where the footprint ends
        assert height_at(a, x) == pytest.approx(height_at(b, x), abs=0.01), x
    # The parallel deck runs beside the north carriageway at its height, within the shared-deck
    # gap, so it joins the same groups: a group with a deck never goes down, and the whole cross
    # section takes the deck's height (it is beside the road, not over it, so no clearance is
    # lost; a deck crossing over is covered by the test above).
    deck = g.edges["w4.0"]
    assert height_at(a, 0.0) == pytest.approx(height_at(deck, 0.0), abs=0.01)
    # Away from the deck the ground carriageways merge down (merge-down fix; was the higher).
    assert height_at(a, 200.0) == pytest.approx(10.0, abs=0.01)
    assert not stats.share_rounds_exhausted


def test_a_street_lifted_by_the_blend_keeps_its_clearance_under_a_deck():
    """Review fix: the north deck rises 0.5 m to its partner; the blend lifts its east approach
    and the street that leaves it 15 m from the deck end, which passes under another deck 11 m
    further on. That deck was set to exactly its clearance before sharing; it rises again."""
    ways = two_decks(7.5)
    n = -3.75
    tags = ways[2][2]
    ways[2] = (3, [(40.0, n), (55.0, n), (300.0, n)], tags)
    street = {"highway": "residential", "name": "Side"}
    over = {"highway": "secondary", "name": "Cross"}
    ways += [
        (7, [(55.0, n), *((55.0, n - d) for d in range(5, 100, 5))], street),
        (8, [(-300.0, -15.0), (45.0, -15.0)], over),
        (9, [(45.0, -15.0), (100.0, -15.0)], {**over, "bridge": "yes", "layer": "1"}),
        (10, [(100.0, -15.0), (300.0, -15.0)], over),
    ]
    g, stats = build(ways, Step())
    assert stats.shared_deck_vertices > 0
    assert stats.clearance_raised  # the scenario does lift the street
    assert not stats.clearance_short
    assert clearance_shortfalls(g, CFG) == []


class Slope:
    """Ground rising `grade` along x, plus `step` metres more south of z = 0."""

    def __init__(self, grade: float = 0.02, step: float = 0.4) -> None:
        self.grade, self.step = grade, step

    def sample(self, x: float, z: float) -> float:
        return 10.0 + self.grade * x + (self.step if z > 0 else 0.0)

    def describe(self) -> dict:
        return {"kind": "slope"}


class Bands:
    """Three bands of ground across z: 10.0 north, 10.15 in the middle, 10.3 south."""

    def sample(self, x: float, z: float) -> float:
        return 10.0 + (0.3 if z > 5 else 0.15 if z > -5 else 0.0)

    def describe(self) -> dict:
        return {"kind": "bands"}


def _step_between(a, b, x: float) -> float:
    return abs(height_at(a, x) - height_at(b, x))


def test_carriageways_drawn_with_vertices_at_different_stations_meet_and_settle():
    """Shared-height-steps fix: partners compared by interpolation crept up round after round and
    never settled. With vertices aligned to matching stations, sharing pairs vertex with vertex,
    settles at once and leaves no step, on a slope too."""
    tags = {"highway": "motorway", "oneway": "yes", "lanes": "2"}
    n, s = -5.0, 5.0
    ways = [  # north drawn every 20 m, south every 27 m: few vertices line up across
        (1, [(float(x), n) for x in range(-200, 201, 20)], tags),
        (2, [(float(x), s) for x in range(200, -201, -27)] + [(-200.0, s)], tags),
    ]
    g, stats = build(ways, Slope())
    a, b = g.edges["w1.0"], g.edges["w2.0"]
    assert stats.aligned_vertices > 0
    assert not stats.share_rounds_exhausted
    for x in range(-160, 161, 7):
        assert _step_between(a, b, float(x)) < 0.05, x  # pairs snap within pair_snap_m
    assert stats.shared_step_left < 0.05


def test_sharing_never_creeps_above_the_highest_input():
    """Three carriageways side by side at different heights end at the highest of them, not above
    it (the interpolated rounds used to ratchet upwards)."""
    tags = {"highway": "motorway", "oneway": "yes", "lanes": "2"}
    ways = [
        (1, [(float(x), -10.0) for x in range(-200, 201, 20)], tags),
        (2, [(float(x), 0.0) for x in range(200, -201, -23)] + [(-200.0, 0.0)], tags),
        (3, [(float(x), 10.0) for x in range(-200, 201, 31)] + [(200.0, 10.0)], tags),
    ]
    g, stats = build(ways, Bands())
    assert not stats.share_rounds_exhausted
    limit = CFG.for_class("motorway").max_grade
    for e in g.edges.values():
        assert max(p[1] for p in e.polyline) <= 10.3 + 1e-6, e.id
        assert max(grades(e)) <= limit + 1e-6, e.id


def test_the_grade_pass_keeps_shared_carriageways_tied():
    """A deck end pins one carriageway high and the grade limit lifts the road beside it. Before,
    only that road rose and the step to its partner reopened; now the partner rises with it."""
    ways = two_decks(11.5, cls="motorway")
    tags = ways[3][2]
    s = 5.75
    ways[3] = (4, [(300.0, s), (20.0, s)], tags)  # the south deck starts 20 m later
    ways[4] = (5, [(20.0, s), (0.0, s), (-40.0, s)], {**tags, "bridge": "yes", "layer": "1"})
    g, stats = build(ways, Slope(grade=0.0, step=-0.6))  # the south ground 0.6 m lower
    north, south = g.edges["w2.0"], g.edges["w4.0"]
    for x in (25.0, 30.0, 40.0):
        assert _step_between(north, south, x) < 0.02, x
    assert stats.shared_step_left < 0.05
    assert not stats.clearance_short


def test_a_merge_on_the_ground_meets_low_and_lifts_nothing_above_its_ground():
    """Merge-down fix: a ramp runs beside the motorway for 240 m and splits away at both ends,
    on ground 0.3 m higher. They meet at the lower height, and no vertex of either road ends
    above its own ground: taking the higher lifted the motorway where they met and left it bowed
    between the raised ends once the raise faded out over blend_m."""
    tags = {"highway": "motorway", "oneway": "yes", "lanes": "2"}
    n, s = -4.75, 4.75
    xs = [float(x) for x in range(-300, 301, 20)]
    ramp = [(-300.0, 60.0), (-200.0, 30.0)] + [(float(x), s) for x in range(-120, 121, 20)]
    ramp += [(200.0, 30.0), (300.0, 60.0)]
    ways = [(1, [(x, n) for x in reversed(xs)], tags), (2, ramp, tags)]
    ground = Step(10.0, 10.3)
    g, stats = build(ways, ground)
    a, b = g.edges["w1.0"], g.edges["w2.0"]
    assert stats.shared_ground_vertices > 0
    for x in range(-100, 101, 20):
        assert height_at(a, float(x)) == pytest.approx(10.0, abs=0.01), x
        assert _step_between(a, b, float(x)) < 0.02, x
    for e in g.edges.values():
        for p in e.polyline:
            assert p[1] <= ground.sample(p[0], p[2]) + 1e-6, (e.id, p)
    limit = CFG.for_class("motorway").max_grade
    for e in g.edges.values():
        assert max(grades(e)) <= limit + 1e-6, e.id


def test_three_ground_carriageways_merge_down_together_and_settle():
    """Three motorway carriageways side by side on ground 10.0, 10.15 and 10.3 end at the lowest,
    without running out of rounds."""
    tags = {"highway": "motorway", "oneway": "yes", "lanes": "2"}
    ways = [
        (1, [(float(x), -10.0) for x in range(-200, 201, 20)], tags),
        (2, [(float(x), 0.0) for x in range(200, -201, -23)] + [(-200.0, 0.0)], tags),
        (3, [(float(x), 10.0) for x in range(-200, 201, 31)] + [(200.0, 10.0)], tags),
    ]
    g, stats = build(ways, Bands())
    assert not stats.share_rounds_exhausted
    for x in (-100.0, 0.0, 100.0):
        for e in g.edges.values():
            assert height_at(e, x) == pytest.approx(10.0, abs=0.02), (e.id, x)


def test_a_deck_never_drops_to_meet_a_ground_carriageway_beside_it():
    """Merge-down applies to ground carriageways only: beside a deck end the ground road still
    rises to the deck, and the deck keeps at least the height it has without the neighbour."""
    s = 5.75
    ways = two_decks(11.5, cls="motorway")
    tags = ways[3][2]
    ways[3] = (4, [(300.0, s), (20.0, s)], tags)
    ways[4] = (5, [(20.0, s), (0.0, s), (-40.0, s)], {**tags, "bridge": "yes", "layer": "1"})
    alone = [w for w in ways if w[0] in (1, 2, 3)]
    g_alone, _ = build(alone, Step())
    g, _stats = build(ways, Step())
    deck, deck_alone = g.edges["w2.0"], g_alone.edges["w2.0"]
    for x in (-20.0, 0.0, 20.0, 40.0):
        assert height_at(deck, x) >= height_at(deck_alone, x) - 1e-6, x
    for x in (25.0, 30.0, 40.0):
        assert height_at(g.edges["w4.0"], x) == pytest.approx(height_at(deck, x), abs=0.01), x
