import math

from osm_import.config import load_config
from osm_import.forks import shape_forks
from osm_import.graph import build_graph
from osm_import.cluster import cluster_junctions
from osm_import.filter import filter_ways
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


def graph_for(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    return g


def _dist_to_line(p, a, d):
    """Distance from point p (x, z) to the line through a with unit direction d."""
    rx, rz = p[0] - a[0], p[2] - a[2]
    return abs(rx * d[1] - rz * d[0])


def test_off_ramp_peels_from_the_outer_edge():
    hw = {"highway": "motorway", "oneway": "yes", "width": "14"}
    g = graph_for(
        [
            (1, [(-300, 0), (0, 0), (300, 0)], hw),
            (2, [(0, 0), (150, 30), (300, 80)], {"highway": "motorway_link", "oneway": "yes", "width": "5"}),
        ]
    )
    stats = shape_forks(g, CFG)
    assert (stats.forks, stats.merges) == (1, 0)
    node = next(n for n in g.nodes.values() if n.junction_type == "fork")
    link = next(e for e in g.edges.values() if e.road_class == "motorway_link")
    through = next(e for e in g.edges.values() if e.road_class == "motorway" and e.from_node == node.id)
    d = through.polyline[1][0] - through.polyline[0][0], through.polyline[1][2] - through.polyline[0][2]
    n = math.hypot(*d)
    d = (d[0] / n, d[1] / n)
    # The link's start now sits 7 - 2.5 = 4.5 m off the through centreline: inner edge on the outer edge.
    assert abs(_dist_to_line(link.polyline[0], node.position, d) - 4.5) < 0.05
    # It is on the ramp's side (positive z here), and the far end has not moved.
    assert link.polyline[0][2] > node.position[2]
    assert abs(link.polyline[-1][0] - 300.0) < 1.0 or abs(link.polyline[-1][2] - 80.0) < 1.5
    # A vertex was inserted where the blend ends, 40 m along.
    lengths = [math.dist(a[::2], b[::2]) for a, b in zip(link.polyline, link.polyline[1:])]
    assert any(abs(sum(lengths[: i + 1]) - 40.0) < 1.0 for i in range(len(lengths)))


def test_on_ramp_is_a_merge_and_sharp_side_streets_are_not_forks():
    hw = {"highway": "motorway", "oneway": "yes", "width": "14"}
    g = graph_for(
        [
            (1, [(-300, 0), (0, 0), (300, 0)], hw),
            (2, [(-300, 80), (-150, 30), (0, 0)], {"highway": "motorway_link", "oneway": "yes", "width": "5"}),
            (3, [(-300, 0), (-300, 200)], {"highway": "residential", "width": "7"}),  # a right-angle street
        ]
    )
    stats = shape_forks(g, CFG)
    assert (stats.forks, stats.merges) == (0, 1)
    kinds = sorted(n.junction_type for n in g.nodes.values())
    assert "merge" in kinds and "fork" not in kinds
    link = next(e for e in g.edges.values() if e.road_class == "motorway_link")
    node = g.nodes[link.to_node]
    assert node.junction_type == "merge"
    assert abs(link.polyline[-1][2] - node.position[2]) > 4.0  # the arriving end moved sideways
