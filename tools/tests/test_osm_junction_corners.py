"""Terrain flattened into junction corners (update-junction-surfaces 2.3)."""

import math

from osm_import.graph import RoadEdge, RoadGraph, RoadNode
from osm_import.pack import JUNCTION_CORNER_MAX_HW, _junction_corners, _road_footprints


def _edge(eid, a, b, pts, width=7.0, bridge=False, tunnel=False):
    return RoadEdge(
        eid, a, b, pts, "residential", 1, 1, False, 40, width, 0, bridge, tunnel, eid, 1, []
    )


def _cross(y_slope=0.0, junction_type="junction", bridge_arm=False):
    """A four-way crossing at the origin, 7 m roads, rising `y_slope` per metre to the east."""
    nodes = {"c": RoadNode("c", (0.0, 0.0, 0.0), [1], junction_type=junction_type)}
    edges = {}
    for name, (x, z) in {"e": (100, 0), "w": (-100, 0), "n": (0, -100), "s": (0, 100)}.items():
        nodes[name] = RoadNode(name, (x, x * y_slope, z), [2])
        edges[name] = _edge(
            name,
            "c",
            name,
            [(0.0, 0.0, 0.0), (x, x * y_slope, z)],
            bridge=bridge_arm and name == "e",
        )
    return RoadGraph(nodes, edges, [])


def test_each_corner_of_a_crossing_gets_a_segment_to_where_the_edges_meet():
    corners = _junction_corners(_cross())
    assert len(corners) == 4
    for ax, az, bx, bz, ay, by, hw, _margin in corners:
        assert (ax, az) == (0.0, 0.0)
        # Edges 3.5 m either side of each road meet 3.5 * sqrt(2) out, on the diagonal.
        assert math.isclose(math.hypot(bx, bz), 3.5 * math.sqrt(2.0), rel_tol=1e-6)
        assert math.isclose(abs(bx), abs(bz), rel_tol=1e-6)
        assert hw == 0.5


def test_a_corner_on_a_slope_ends_at_its_arms_height():
    corners = _junction_corners(_cross(y_slope=0.05))
    reach = 3.5 * math.sqrt(2.0)
    for _ax, _az, bx, _bz, ay, by, _hw, _m in corners:
        assert ay == 0.0
        # The mean of the two arms' heights that far out: east rises, west falls, the cross
        # street is level, so each corner sits half way to the east or west arm's height.
        expected = math.copysign(reach * 0.05 / 2.0, bx)
        assert math.isclose(by, expected, abs_tol=1e-6)


def test_forks_and_junctions_on_a_bridge_get_no_corners():
    assert _junction_corners(_cross(junction_type="fork")) == []
    assert _junction_corners(_cross(bridge_arm=True)) == []


def test_corners_join_the_ground_footprints():
    ground, _bridges = _road_footprints(_cross(), include_pedestrian=False)
    assert len(ground) == 4 + 4  # one segment per arm, one per corner


def test_a_sharp_corner_is_capped():
    nodes = {
        "c": RoadNode("c", (0.0, 0.0, 0.0), [1]),
        "a": RoadNode("a", (100.0, 0.0, 0.0), [2]),
        "b": RoadNode("b", (100.0, 0.0, 8.0), [3]),
        "d": RoadNode("d", (-100.0, 0.0, 0.0), [4]),
    }
    edges = {
        "a": _edge("a", "c", "a", [(0.0, 0.0, 0.0), (100.0, 0.0, 0.0)]),
        "b": _edge("b", "c", "b", [(0.0, 0.0, 0.0), (100.0, 0.0, 8.0)]),
        "d": _edge("d", "c", "d", [(0.0, 0.0, 0.0), (-100.0, 0.0, 0.0)]),
    }
    for _ax, _az, bx, bz, *_ in _junction_corners(RoadGraph(nodes, edges, [])):
        assert math.hypot(bx, bz) <= JUNCTION_CORNER_MAX_HW * 3.5 + 1e-6
