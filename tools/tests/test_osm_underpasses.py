from osm_import.graph import PedestrianWay, RoadEdge, RoadGraph, RoadNode
from osm_import.pack import FLAT_MARGIN_M, _road_footprints
from osm_import.underpasses import (
    CEILING_SLAB_M,
    CLEARANCE_M,
    RAMP_GRADE,
    TERRAIN_MARGIN_M,
    TUNNEL_MARGIN_M,
    dig_underpasses,
)


def _way(wid, pts, kind="footway", covered=False):
    return PedestrianWay(
        wid, [(x, y, z) for x, y, z in pts], "footway", 1, None, kind, 2.0, covered
    )


def _graph(ways, road_y=None):
    edges = {}
    nodes = {}
    if road_y is not None:
        nodes = {
            "a": RoadNode("a", (10, road_y, -50), [1]),
            "b": RoadNode("b", (10, road_y, 50), [2]),
        }
        edges["r"] = RoadEdge(
            "r",
            "a",
            "b",
            [(10, road_y, -50), (10, road_y, 50)],
            "secondary",
            1,
            1,
            False,
            50,
            14.0,
            0,
            False,
            False,
            "Over",
            9,
            [],
        )
    return RoadGraph(nodes, edges, ways)


def test_covered_way_under_a_road_becomes_a_tunnel_with_ramps():
    west = _way("p1", [(-60, 70, 0), (0, 70, 0)])
    tunnel = _way("p2", [(0, 70, 0), (20, 70, 0)], covered=True)
    east = _way("p3", [(20, 70, 0), (24, 70, 0)], kind="steps")
    g = _graph([west, tunnel, east], road_y=70.0)
    stats = dig_underpasses(g, lambda x, z: 70.0)
    assert stats == {"tunnels": 1, "uncovered": 0}
    floor = 70.0 - CLEARANCE_M
    assert tunnel.profile == "tunnel"
    assert [round(p[1], 3) for p in tunnel.polyline] == [round(floor, 3)] * 2
    assert tunnel.top == [70.0 - CEILING_SLAB_M] * 2
    # The long approach meets the floor, tops out after rise / grade, and keeps its far end.
    assert west.profile == "trench"
    assert west.polyline[-1][1] == floor
    assert len(west.polyline) == 3
    top_out = west.polyline[1]
    assert abs(top_out[0] - (0 - CLEARANCE_M / RAMP_GRADE)) < 1e-6
    assert abs(top_out[1] - 70.0) < 1e-6
    assert west.polyline[0][1] == 70.0
    # Short stairs climb at the stairs grade and stay below their own heights.
    assert east.polyline[0][1] == floor
    assert floor < east.polyline[1][1] <= 70.0


def test_covered_way_with_nothing_above_is_opened_and_its_approaches_meet_it():
    west = _way("p1", [(-30, 66, 0), (0, 66, 0)])
    under = _way("p2", [(0, 63, 0), (20, 63.5, 0)], kind="path", covered=True)
    g = _graph([west, under])
    stats = dig_underpasses(g, lambda x, z: 63.0)
    assert stats == {"tunnels": 0, "uncovered": 1}
    assert under.covered is False and under.profile == ""
    assert west.polyline[-1][1] == 63.0
    assert west.polyline[0][1] == 66.0


def test_covered_way_joining_nothing_is_left_alone():
    lone = _way("p2", [(0, 70, 0), (20, 70, 0)], covered=True)
    g = _graph([lone], road_y=70.0)
    assert dig_underpasses(g, lambda x, z: 70.0) == {"tunnels": 0, "uncovered": 0}
    assert lone.covered and lone.profile == ""


def test_terrain_margin_is_narrow_for_dug_ways_and_default_elsewhere():
    west = _way("p1", [(-60, 70, 0), (0, 70, 0)])
    tunnel = _way("p2", [(0, 70, 0), (20, 70, 0)], covered=True)
    other = _way("p9", [(100, 70, 0), (140, 70, 0)])
    g = _graph([west, tunnel, other], road_y=70.0)
    dig_underpasses(g, lambda x, z: 70.0)
    ground, _bridges = _road_footprints(g)
    margins = {seg[0]: seg[7] for seg in ground}
    assert margins[0] == TUNNEL_MARGIN_M  # the tunnel
    assert margins[-60] == TERRAIN_MARGIN_M  # its ramp
    assert margins[100] == FLAT_MARGIN_M
