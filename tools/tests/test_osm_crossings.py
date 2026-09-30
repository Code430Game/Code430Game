from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.crossings import infer_bridges
from osm_import.elevation import FlatSource, apply_elevation
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


class RampDeck:
    """Flat ground with a 6 m high ridge along the ramp (z = 0), like a DTM that keeps the deck."""

    def sample(self, x, z):
        return 50.0 + (6.0 if abs(z) < 5.0 else 0.0)

    def describe(self):
        return {"kind": "rampdeck"}


def build(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    return g


def test_untagged_ramp_crossing_is_inferred_as_bridge_by_dtm():
    ways = [
        (1, [(-300, 0), (300, 0)], {"highway": "motorway_link", "oneway": "yes"}),  # no bridge tag
        (2, [(0, -300), (0, 300)], {"highway": "residential", "name": "Kent"}),
    ]
    g = build(ways)
    src = RampDeck()
    result = infer_bridges(g, src.sample)
    assert len(result.inferred) == 1
    ib = result.inferred[0]
    assert (
        ib.over_class == "motorway_link" and ib.under_class == "residential" and ib.reason == "dtm"
    )
    ramp = g.edges["w1.0"]
    assert ramp.bridge and ramp.layer == 1 and "bridge" in ramp.defaulted_fields
    apply_elevation(g, src, CFG)
    street = g.edges["w2.0"]
    ys = [p[1] for p in street.polyline]
    assert max(ys) - min(ys) < 0.5  # the street no longer jumps up onto the deck
    assert min(p[1] for p in ramp.polyline) >= 50.0 + CFG.bridge_clearance_m - 0.01


def test_crossing_with_shared_node_is_not_a_crossing():
    ways = [
        (1, [(-300, 0), (0, 0), (300, 0)], {"highway": "secondary"}),
        (2, [(0, -300), (0, 0), (0, 300)], {"highway": "residential"}),
    ]
    g = build(ways)
    assert infer_bridges(g, FlatSource(10.0).sample).inferred == []


def test_flat_tie_falls_back_to_class_priority():
    ways = [
        (1, [(-300, 0), (300, 0)], {"highway": "primary"}),
        (2, [(0, -300), (0, 300)], {"highway": "service"}),
    ]
    g = build(ways)
    result = infer_bridges(g, FlatSource(10.0).sample)
    assert len(result.inferred) == 1
    assert result.inferred[0].over_class == "primary" and result.inferred[0].reason == "class"
