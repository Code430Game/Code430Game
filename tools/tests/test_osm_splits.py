"""A two-way road dividing into one-way carriageways (update-junction-surfaces, #78)."""

import math

from osm_import.config import load_config
from osm_import.forks import shape_splits
from osm_import.graph import RoadEdge, RoadGraph, RoadNode


def _edge(eid, a, b, pts, oneway, width):
    return RoadEdge(
        eid,
        a,
        b,
        pts,
        "secondary",
        1,
        0 if oneway else 1,
        oneway,
        50,
        width,
        0,
        False,
        False,
        "Colonel By Drive",
        1,
        [],
    )


def _split(angle_deg=4.3, leave_on_right=True, arrive_oneway=True):
    """A two-way road from the west ends at c; two carriageways leave east, `angle_deg` either
    side of due east, both drawn from c. The carriageway carrying traffic away from c is drawn
    on the right of east (+z) unless `leave_on_right` is False."""
    t = math.radians(angle_deg)
    right = (100 * math.cos(t), 0.0, 100 * math.sin(t))
    left = (100 * math.cos(t), 0.0, -100 * math.sin(t))
    leave_to, arrive_from = (right, left) if leave_on_right else (left, right)
    nodes = {
        "w": RoadNode("w", (-100.0, 0.0, 0.0), [1]),
        "c": RoadNode("c", (0.0, 0.0, 0.0), [2]),
        "l": RoadNode("l", leave_to, [3]),
        "r": RoadNode("r", arrive_from, [4]),
    }
    edges = {
        "two": _edge("two", "w", "c", [(-100.0, 0.0, 0.0), (0.0, 0.0, 0.0)], False, 7.0),
        "leave": _edge("leave", "c", "l", [(0.0, 0.0, 0.0), leave_to], True, 3.5),
        "arrive": _edge("arrive", "r", "c", [arrive_from, (0.0, 0.0, 0.0)], arrive_oneway, 3.5),
    }
    return RoadGraph(nodes, edges, [])


def test_the_carriageways_start_on_their_own_side_of_the_two_way_road():
    g = _split()
    stats = shape_splits(g, load_config())
    assert stats.splits == 1
    start = g.edges["leave"].polyline[0]
    end = g.edges["arrive"].polyline[-1]
    # Traffic leaving keeps right (+z when heading east); each outer edge meets the two-way's.
    assert math.isclose(start[2], 1.75, abs_tol=1e-6)
    assert math.isclose(end[2], -1.75, abs_tol=1e-6)
    assert math.isclose(start[2] + 1.75, 3.5, abs_tol=1e-6)
    # The move fades out: the far ends stay where OSM put them.
    assert g.edges["leave"].polyline[-1] == _split().edges["leave"].polyline[-1]
    assert g.edges["arrive"].polyline[0] == _split().edges["arrive"].polyline[0]


def test_a_pair_drawn_on_the_wrong_sides_is_left_alone():
    g = _split(leave_on_right=False)
    stats = shape_splits(g, load_config())
    assert stats.splits == 0
    assert stats.skipped_sides == 1
    assert g.edges["leave"].polyline[0] == (0.0, 0.0, 0.0)


def test_a_two_way_road_meeting_two_two_way_roads_is_not_a_split():
    g = _split(arrive_oneway=False)
    assert shape_splits(g, load_config()).splits == 0
    assert g.edges["leave"].polyline[0] == (0.0, 0.0, 0.0)


def test_carriageways_leaving_too_far_apart_are_not_a_split():
    g = _split(angle_deg=30.0)  # 60 degrees between them: a fork in the road, not one dividing
    assert shape_splits(g, load_config()).splits == 0
