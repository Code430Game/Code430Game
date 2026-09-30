from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


def build(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    return g, cluster_junctions(g, CFG)


def dual_carriageway(cross_tags: dict[str, str], gap_m: float = 12.0):
    """Two one-way secondary carriageways gap_m apart, crossed by a two-way street."""
    return [
        (
            1,
            [(-200, 0), (0, 0), (200, 0)],
            {"highway": "secondary", "oneway": "yes", "name": "Main East"},
        ),
        (
            2,
            [(200, gap_m), (0, gap_m), (-200, gap_m)],
            {"highway": "secondary", "oneway": "yes", "name": "Main West"},
        ),
        (
            3,
            [(0, -200), (0, 0), (0, gap_m), (0, 200)],
            {"highway": "residential", "name": "Cross", **cross_tags},
        ),
    ]


def test_dual_carriageway_crossing_merges_into_one_junction():
    g, stats = build(dual_carriageway({}))
    assert stats.clusters == 1 and stats.nodes_merged == 2 and stats.edges_removed == 1
    cluster = [n for n in g.nodes.values() if n.id.startswith("c")]
    assert len(cluster) == 1
    assert abs(cluster[0].position[2] - 6.0) < 1.0  # centroid between z=0 and z=12
    assert cluster[0].junction_type == "junction"
    touching = [e for e in g.edges.values() if cluster[0].id in (e.from_node, e.to_node)]
    assert len(touching) == 6
    for e in touching:
        end = e.polyline[-1] if e.to_node == cluster[0].id else e.polyline[0]
        assert end == cluster[0].position


def test_wide_median_is_not_merged():
    g, stats = build(dual_carriageway({}, gap_m=40.0))
    assert stats.clusters == 0
    assert not any(n.id.startswith("c") for n in g.nodes.values())


def test_bridge_over_street_never_merges():
    ways = [
        (1, [(-200, 0), (0, 0), (200, 0)], {"highway": "primary", "name": "Below"}),
        (
            2,
            [(0, -200), (0, 0), (0, 200)],
            {"highway": "primary", "bridge": "yes", "layer": "1", "name": "Above"},
        ),
        (3, [(0, 0), (60, 60)], {"highway": "residential"}),
        (4, [(0, 0), (-60, 60)], {"highway": "residential"}),
    ]
    _g, stats = build(ways)
    # Way 1 and 2 share OSM node at (0,0) in this synthetic data on purpose; the bridge flag blocks contraction.
    assert stats.clusters == 0


def test_short_edge_between_junctions_on_different_layers_is_kept():
    ways = [
        (1, [(-100, 0), (0, 0), (100, 0)], {"highway": "secondary", "layer": "1", "bridge": "yes"}),
        (2, [(0, 0), (5, 0)], {"highway": "secondary"}),
        (3, [(5, 0), (5, 100)], {"highway": "residential"}),
        (4, [(5, 0), (5, -100)], {"highway": "residential"}),
        (5, [(0, 0), (0, 100)], {"highway": "residential", "layer": "1"}),
    ]
    _g, stats = build(ways)
    assert (
        stats.clusters == 1
    )  # n(0,0) has layers {1} via ways 1,5 and {0} via way 2; n(5,0) has {0}: they intersect via way 2
