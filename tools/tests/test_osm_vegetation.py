"""Trees, bushes and green areas (add-vegetation 1.1)."""

import itertools
import math

from shapely.geometry import LineString, Point

from osm_import.buildings import Building, BuildingsResult
from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, apply_elevation
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from osm_import.vegetation import build_vegetation
from tests.osm_helpers import BBOX, ll, make_data

CFG = load_config()
GROUND = 10.0
PROJ = Projector.for_bbox(BBOX)


class Flat:
    def sample(self, _x, _z):
        return GROUND


ROAD = (1, [(-200, 0), (200, 0)], {"highway": "residential", "width": "8"})
SIDEWALK = (2, [(-200, 6), (200, 6)], {"highway": "footway", "footway": "sidewalk"})


def _graph(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, PROJ, CFG)
    cluster_junctions(g, CFG)
    apply_elevation(g, FlatSource(GROUND), CFG)
    return g


def _node(nid, x, z, tags):
    lat, lon = ll(x, z)
    return {"type": "node", "id": nid, "lat": lat, "lon": lon, "tags": tags}


def _way(wid, pts, tags):
    return {
        "type": "way",
        "id": wid,
        "tags": tags,
        "geometry": [{"lat": ll(x, z)[0], "lon": ll(x, z)[1]} for x, z in pts],
    }


def _house(bid, x0, z0, x1, z1):
    ring = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    return Building(bid, "house", None, 7.0, GROUND, [ring], ring, [0, 1, 2, 0, 2, 3], 1, "default")


def _build(payload, buildings=None):
    g = _graph([ROAD, SIDEWALK])
    return g, build_vegetation(
        payload, BBOX, PROJ, g, buildings, None, Flat(), CFG.__dict__.get("vegetation")
    )


def test_a_mapped_street_tree_keeps_its_spot_on_the_sidewalk_strip_but_not_on_the_road():
    payload = {
        "elements": [
            _node(
                11, 50, 7, {"natural": "tree", "genus": "Picea", "height": "12"}
            ),  # in the sidewalk strip
            _node(12, 60, 0, {"natural": "tree"}),  # in the road
        ]
    }
    _g, v = _build(payload)
    assert len(v.trees) == 1
    t = v.trees[0]
    assert t.source == "tagged" and t.archetype == "conifer" and abs(t.height - 12.0) < 1e-6
    assert abs(t.x - 50) < 0.5 and abs(t.z - 7) < 0.5 and t.y == GROUND
    assert v.skipped


def test_a_tree_row_is_planted_at_its_spacing():
    payload = {"elements": [_way(21, [(-80, 40), (80, 40)], {"natural": "tree_row"})]}
    _g, v = _build(payload)
    assert len(v.trees) == 20  # 160 m at 8 m
    assert all(t.source == "row" for t in v.trees)
    xs = sorted(t.x for t in v.trees)
    assert all(abs((b - a) - 8.0) < 0.5 for a, b in itertools.pairwise(xs))


def test_a_park_scatter_keeps_off_the_road_through_it_and_gets_edge_bushes():
    park = [(-100, -60), (100, -60), (100, 60), (-100, 60), (-100, -60)]
    payload = {"elements": [_way(31, park, {"leisure": "park", "name": "Test Park"})]}
    _g, v = _build(payload)
    assert v.areas and v.areas[0].kind == "park" and v.areas[0].name == "Test Park"
    scatter = [t for t in v.trees if t.source == "scatter"]
    assert len(scatter) > 20
    road = LineString([(-200, 0), (200, 0)])
    for t in scatter:
        assert road.distance(Point(t.x, t.z)) > 4.0 + 2.0 - 0.01  # half width plus margin
        for a in scatter:
            if a is not t:
                assert math.dist((a.x, a.z), (t.x, t.z)) >= 14.0 - 1e-6
    assert any(b.source == "edge" for b in v.bushes)


def test_frontage_bushes_line_a_house_and_keep_off_it():
    _g, v = _build({"elements": []}, BuildingsResult([_house("w9.0", -10, 30, 10, 45)]))
    front = [b for b in v.bushes if b.source == "frontage"]
    assert len(front) >= 8
    for b in front:
        assert not (-10 <= b.x <= 10 and 30 <= b.z <= 45)


def test_mapped_trees_come_first_in_their_chunk_and_output_is_repeatable():
    park = [(-100, 20), (100, 20), (100, 120), (-100, 120), (-100, 20)]
    payload = {
        "elements": [_way(41, park, {"landuse": "grass"}), _node(42, 10, 10, {"natural": "tree"})]
    }
    _g, a = _build(payload)
    _g, b = _build(payload)
    assert a.to_dict() == b.to_dict()
    same_chunk = [t for t in a.trees if t.x >= 0 and t.z >= 0]
    assert same_chunk[0].source == "tagged"
