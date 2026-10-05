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


def test_covered_and_tunnel_paths_are_flagged():
    g = build(
        [
            (1, [(0, 0), (100, 0)], {"highway": "residential"}),
            (2, [(0, 5), (100, 5)], {"highway": "path", "covered": "yes"}),
            (3, [(0, 9), (100, 9)], {"highway": "footway", "tunnel": "yes"}),
            (4, [(0, 12), (100, 12)], {"highway": "footway", "tunnel": "building_passage"}),
            (5, [(0, 15), (100, 15)], {"highway": "cycleway"}),
        ]
    )
    flags = {p.osm_way_id: p.covered for p in g.pedestrian}
    assert flags == {2: True, 3: True, 4: False, 5: False}


def test_node_control_comes_from_node_tags_and_survives_clustering():
    from osm_import.cluster import cluster_junctions
    from osm_import.osm_data import OsmNode

    data = make_data(
        [
            (1, [(0, 0), (100, 0)], {"highway": "residential"}),
            (2, [(100, 0), (200, 0)], {"highway": "residential"}),
            (3, [(100, -100), (100, 0), (100, 100)], {"highway": "residential"}),
        ]
    )
    # Tag the node shared by all three ways as signalised.
    from collections import Counter

    counts = Counter(n for w in data.ways.values() for n in w.nodes)
    shared_id = counts.most_common(1)[0][0]
    assert counts[shared_id] == 3
    node: OsmNode = data.nodes[shared_id]
    node.tags["highway"] = "traffic_signals"
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    controls = sorted(n.control for n in g.nodes.values())
    assert controls.count("signals") == 1
    assert all(c in ("none", "signals") for c in controls)


def test_stop_on_the_approach_applies_to_that_end_only():
    from collections import Counter

    from osm_import.osm_data import OsmNode

    data = make_data(
        [
            (1, [(0, 0), (60, 0), (100, 0)], {"highway": "residential"}),
            (2, [(100, -100), (100, 0), (100, 100)], {"highway": "secondary"}),
        ]
    )
    # The middle vertex of way 1 (at 60 m, before the crossing) carries a forward stop.
    counts = Counter(n for w in data.ways.values() for n in w.nodes)
    way1 = data.ways[1]
    interior = way1.nodes[1]
    assert counts[interior] == 1
    node: OsmNode = data.nodes[interior]
    node.tags.update({"highway": "stop", "direction": "forward"})
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    e = next(x for x in g.edges.values() if x.osm_way_id == 1)
    assert (e.control_to, e.control_from) == ("stop", "none")
    assert all(x.control_to == "none" for x in g.edges.values() if x.osm_way_id == 2)


def test_projector_picks_the_utm_zone_of_the_region():
    from osm_import.projection import Projector, utm_crs_for

    assert utm_crs_for(45.42, -75.69) == "EPSG:32618"  # Ottawa
    assert utm_crs_for(49.28, -123.12) == "EPSG:32610"  # Vancouver
    assert utm_crs_for(-33.87, 151.21) == "EPSG:32756"  # Sydney, southern hemisphere
    from osm_import.osm_data import BBox

    van = Projector.for_bbox(BBox(49.26, -123.14, 49.30, -123.10))
    assert van.frame.crs == "EPSG:32610"
    x, z = van.to_local(49.28, -123.12)
    assert abs(x) < 5.0 and abs(z) < 5.0  # the centre is the origin


def test_parking_aisles_and_driveways_become_class_parking_joined_to_the_street():
    g = build(
        [
            (1, [(-100, 0), (0, 0), (100, 0)], {"highway": "residential", "name": "Street"}),
            (2, [(0, 0), (0, 60)], {"highway": "service", "service": "parking_aisle"}),
            (3, [(50, 0), (50, -30)], {"highway": "service", "service": "driveway"}),
            (4, [(-50, 0), (-50, -30)], {"highway": "service", "service": "drive-through"}),
            (
                5,
                [(80, 0), (80, 40)],
                {"highway": "service", "service": "parking_aisle", "width": "7"},
            ),
        ]
    )
    aisle = g.edges["w2.0"]
    assert aisle.road_class == "parking"
    assert aisle.speed_kph == 15
    assert aisle.width_m == pytest.approx(5.5)
    assert aisle.lanes_forward == 1 and aisle.lanes_backward == 1
    assert "width" in aisle.defaulted_fields
    assert g.edges["w3.0"].width_m == pytest.approx(3.5)
    assert g.edges["w5.0"].width_m == pytest.approx(7.0)  # a tagged width wins
    assert not any(e.osm_way_id == 4 for e in g.edges.values())  # drive-throughs still dropped
    # The aisle shares the street's node: it splits the street there.
    assert aisle.from_node in {
        e.to_node for e in g.edges.values() if e.road_class == "residential"
    } | {e.from_node for e in g.edges.values() if e.road_class == "residential"}
