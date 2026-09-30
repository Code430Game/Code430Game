import pytest

from osm_import.config import load_config
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


def build(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    return build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)


def test_crossing_ways_split_into_four_edges():
    g = build(
        [
            (1, [(-100, 0), (0, 0), (100, 0)], {"highway": "residential", "name": "East West"}),
            (2, [(0, -100), (0, 0), (0, 100)], {"highway": "residential", "name": "North South"}),
        ]
    )
    assert len(g.edges) == 4
    assert sorted(g.edges) == ["w1.0", "w1.1", "w2.0", "w2.1"]
    centre = g.nodes["n1001"]
    assert centre.junction_type == "junction"
    assert sum(1 for n in g.nodes.values() if n.junction_type == "dead_end") == 4
    e = g.edges["w1.0"]
    assert e.length_m == pytest.approx(100.0, abs=0.5)
    assert e.polyline[0][1] == 0.0  # y is zero until elevation


def test_local_frame_axes():
    g = build(
        [
            (1, [(0, 0), (100, 0)], {"highway": "residential"}),
            (2, [(0, 0), (0, 100)], {"highway": "residential"}),
        ]
    )
    east = g.edges["w1.0"].polyline[-1]
    south = g.edges["w2.0"].polyline[-1]
    # UTM grid convergence at Ottawa tilts the axes by about half a degree.
    assert east[0] > 90 and abs(east[2]) < 2
    assert south[2] > 90 and abs(south[0]) < 2


def test_oneway_reverse_flips_polyline():
    g = build([(1, [(0, 0), (100, 0)], {"highway": "residential", "oneway": "-1"})])
    e = g.edges["w1.0"]
    assert e.oneway is True
    assert e.from_node == "n1001" and e.to_node == "n1000"
    assert e.polyline[0][0] > e.polyline[-1][0]


def test_defaults_recorded():
    g = build([(1, [(0, 0), (100, 0)], {"highway": "primary"})])
    e = g.edges["w1.0"]
    assert e.lanes_forward == 2 and e.lanes_backward == 2
    assert e.speed_kph == CFG.for_class("primary").speed_kph
    assert e.width_m == pytest.approx(4 * CFG.lane_width_m)
    assert sorted(e.defaulted_fields) == ["lanes", "speed_kph", "width"]


def test_tagged_values_not_defaulted():
    g = build(
        [
            (
                1,
                [(0, 0), (100, 0)],
                {
                    "highway": "primary",
                    "lanes": "3",
                    "lanes:forward": "2",
                    "width": "11",
                    "maxspeed": "60",
                },
            )
        ]
    )
    e = g.edges["w1.0"]
    assert (e.lanes_forward, e.lanes_backward) == (2, 1)
    assert e.width_m == 11.0 and e.speed_kph == 60
    assert e.defaulted_fields == []


def test_motorway_implies_oneway_and_records_it():
    g = build([(1, [(0, 0), (100, 0)], {"highway": "motorway", "lanes": "2"})])
    e = g.edges["w1.0"]
    assert e.oneway is True and e.lanes_forward == 2 and e.lanes_backward == 0
    assert "oneway" in e.defaulted_fields


def test_roundabout_is_oneway_without_default_note():
    g = build(
        [
            (
                1,
                [(0, 0), (20, 0), (20, 20), (0, 20), (0, 0)],
                {"highway": "residential", "junction": "roundabout"},
            )
        ]
    )
    e = next(iter(g.edges.values()))
    assert e.oneway is True and "oneway" not in e.defaulted_fields


def test_bridge_layer_tunnel_and_access():
    g = build(
        [
            (
                1,
                [(0, 0), (100, 0)],
                {"highway": "secondary", "bridge": "yes", "layer": "1", "access": "destination"},
            )
        ]
    )
    e = g.edges["w1.0"]
    assert e.bridge and not e.tunnel and e.layer == 1 and e.access == "destination"


def test_pedestrian_ways_kept_separately():
    g = build(
        [
            (1, [(0, 0), (100, 0)], {"highway": "residential"}),
            (2, [(0, 5), (100, 5)], {"highway": "footway"}),
        ]
    )
    assert len(g.edges) == 1
    assert [p.osm_way_id for p in g.pedestrian] == [2]
