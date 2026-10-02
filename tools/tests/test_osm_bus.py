from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


def _build(ways, node_tags=None):
    data = make_data(ways)
    for nid, tags in (node_tags or {}).items():
        data.nodes[nid].tags.update(tags)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    return g


def test_bus_only_way_survives_access_no_and_is_marked():
    g = _build(
        [
            (
                1,
                [(-200, 0), (200, 0)],
                {"highway": "tertiary", "access": "no", "bus": "designated", "oneway": "yes"},
            ),
            (2, [(-200, 50), (200, 50)], {"highway": "tertiary", "access": "no"}),
        ]
    )
    kinds = {e.osm_way_id: e.bus for e in g.edges.values()}
    assert kinds == {1: "only"}


def test_designated_lane_index_follows_bus_lanes_tag():
    g = _build(
        [
            (
                1,
                [(-200, 0), (200, 0)],
                {
                    "highway": "primary",
                    "lanes": "3",
                    "oneway": "yes",
                    "bus:lanes": "designated|yes|yes",
                },
            ),
            (
                2,
                [(-200, 50), (200, 50)],
                {"highway": "primary", "lanes": "2", "oneway": "yes", "busway:right": "lane"},
            ),
        ]
    )
    by_way = {e.osm_way_id: (e.bus, e.bus_lane) for e in g.edges.values()}
    assert by_way[1] == ("lane", 0)
    assert by_way[2] == ("lane", 1)


def test_bus_stops_attach_to_their_edge():
    g = _build(
        [(1, [(-200, 0), (0, 0), (200, 0)], {"highway": "secondary", "oneway": "yes"})],
        node_tags={1001: {"public_transport": "stop_position", "bus": "yes"}},
    )
    assert len(g.bus_stops) == 1
    stop = g.bus_stops[0]
    assert stop["edge"] in g.edges
    assert abs(stop["position"][0]) < 1.0
