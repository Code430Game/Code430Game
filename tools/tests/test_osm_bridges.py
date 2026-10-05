"""Bridges: grouping, walkways on decks, piers clear of what is below, abutments (add-bridge-structures 1.1, 1.2)."""

import math

from osm_import.bridges import build_bridges, edge_distance
from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, apply_elevation, apply_pedestrian_elevation
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from osm_import.water import WaterPolygon, WaterResult
from tests.osm_helpers import BBOX, ll, make_data

CFG = load_config()
GROUND = 10.0


def graph_for(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    apply_elevation(g, FlatSource(GROUND), CFG)
    apply_pedestrian_elevation(g, FlatSource(GROUND), CFG)
    return g


def ground(_x, _z):
    return GROUND


OVERPASS = [
    # A primary bridge over a residential street, approaches at grade.
    (1, [(-150, 0), (-40, 0)], {"highway": "primary", "width": "10"}),
    (2, [(-40, 0), (40, 0)], {"highway": "primary", "bridge": "yes", "layer": "1", "width": "10"}),
    (3, [(40, 0), (150, 0)], {"highway": "primary", "width": "10"}),
    (4, [(0, -150), (0, 150)], {"highway": "residential", "width": "8"}),
]


def test_an_overpass_is_one_bridge_over_a_road_with_two_abutments():
    g = graph_for(OVERPASS)
    r = build_bridges(g, ground, CFG.bridges)
    assert len(r.bridges) == 1
    b = r.bridges[0]
    assert b.kind == "over_road"
    assert b.edges == ["w2.0"]
    assert len(b.ends) == 2
    assert 0.8 <= b.depth_m <= 1.8
    deck_y = max(p[1] for p in g.edges["w2.0"].polyline)
    assert deck_y - GROUND >= CFG.bridge_clearance_m - 0.1


def test_no_pier_stands_in_the_street_underneath():
    g = graph_for(OVERPASS)
    b = build_bridges(g, ground, CFG.bridges).bridges[0]
    street = g.edges["w4.0"]
    for p in b.piers:
        assert edge_distance(street, p.x, p.z) >= street.width_m / 2.0 + 1.5
        assert p.bottom_y < GROUND and p.top_y < max(q[1] for q in g.edges["w2.0"].polyline)


def test_a_divided_highway_shares_one_deck():
    ways = [
        (
            1,
            [(-60, 0), (60, 0)],
            {"highway": "motorway", "oneway": "yes", "bridge": "yes", "layer": "1", "width": "10"},
        ),
        (
            2,
            [(60, 13), (-60, 13)],
            {"highway": "motorway", "oneway": "yes", "bridge": "yes", "layer": "1", "width": "10"},
        ),
        (3, [(0, -150), (0, 150)], {"highway": "residential", "width": "8"}),
    ]
    g = graph_for(ways)
    r = build_bridges(g, ground, CFG.bridges)
    assert len(r.bridges) == 1
    assert sorted(r.bridges[0].edges) == ["w1.0", "w2.0"]


def test_far_apart_bridges_stay_apart():
    ways = [
        (1, [(-60, 0), (60, 0)], {"highway": "primary", "bridge": "yes", "layer": "1"}),
        (2, [(-60, 200), (60, 200)], {"highway": "primary", "bridge": "yes", "layer": "1"}),
    ]
    assert len(build_bridges(graph_for(ways), ground, CFG.bridges).bridges) == 2


def _outline(points, name):
    geom = [{"lat": ll(x, z)[0], "lon": ll(x, z)[1]} for x, z in points]
    return {
        "elements": [
            {"type": "way", "id": 9, "tags": {"man_made": "bridge", "name": name}, "geometry": geom}
        ]
    }


def test_a_canal_bridge_takes_the_outline_name_and_stands_on_columns():
    ways = [
        (1, [(-150, 0), (-90, 0)], {"highway": "secondary", "width": "10"}),
        (
            2,
            [(-90, 0), (0, 0)],
            {"highway": "secondary", "bridge": "yes", "layer": "1", "width": "10"},
        ),
        (
            3,
            [(0, 0), (90, 0)],
            {"highway": "secondary", "bridge": "yes", "layer": "1", "width": "10", "lanes": "3"},
        ),
        (4, [(90, 0), (150, 0)], {"highway": "secondary", "width": "10"}),
    ]
    g = graph_for(ways)
    proj = Projector.for_bbox(BBOX)
    outline = _outline([(-92, -9), (92, -9), (92, 9), (-92, 9), (-92, -9)], "Test Canal Bridge")
    canal = WaterResult(
        [
            WaterPolygon(
                "water0", "Canal", "canal", 8.0, [(-70, -60), (70, -60), (70, 60), (-70, 60)], [], 1
            )
        ]
    )
    # The deck sits well above the water (the importer lifts decks over water by the clearance).
    for eid in ("w2.0", "w3.0"):
        g.edges[eid].polyline = [(x, GROUND + 6.0, z) for x, _y, z in g.edges[eid].polyline]
    r = build_bridges(g, lambda _x, _z: 6.5, CFG.bridges, outline, proj, canal)
    assert len(r.bridges) == 1
    b = r.bridges[0]
    assert b.name == "Test Canal Bridge" and b.kind == "over_water"
    assert b.piers and all(p.kind == "column" for p in b.piers if abs(p.x) < 70)


def test_a_walkway_beside_the_deck_is_lifted_onto_it_and_widens_it():
    ways = OVERPASS + [
        # The bridge's own sidewalk, mapped separately and left at ground height by the data.
        (
            5,
            [(-40, -7), (40, -7)],
            {"highway": "footway", "footway": "sidewalk", "bridge": "yes", "layer": "1"},
        ),
        # The street's sidewalk below the deck: stays on the ground.
        (6, [(6, -150), (6, 150)], {"highway": "footway", "footway": "sidewalk"}),
    ]
    g = graph_for(ways)
    walk = next(w for w in g.pedestrian if w.osm_way_id == 5)
    for i, (x, _y, z) in enumerate(walk.polyline):
        walk.polyline[i] = (x, GROUND, z)  # as the survey found: on the ground under the deck
    r = build_bridges(g, ground, CFG.bridges)
    b = r.bridges[0]
    assert walk.id in b.walkways
    deck = g.edges["w2.0"]
    for x, y, z in walk.polyline:
        assert abs(y - max(p[1] for p in deck.polyline)) < 0.6 or abs(x) > 35
    assert r.walkways_lifted >= 1
    street_walk = next(w for w in g.pedestrian if w.osm_way_id == 6)
    assert street_walk.id not in b.walkways
    assert all(abs(p[1] - GROUND) < 0.6 for p in street_walk.polyline)
    road_deck = next(d for d in b.decks if d.source == "w2.0")
    # The sidewalk is north of the eastbound road: the left side widens past the 5 m half width.
    assert max(road_deck.left_m) > 6.0 and max(road_deck.right_m) < 5.5


def test_a_footbridge_over_a_road_is_its_own_bridge():
    ways = [
        (1, [(0, -150), (0, 150)], {"highway": "primary", "width": "10"}),
        (
            2,
            [(-30, 0), (30, 0)],
            {"highway": "footway", "bridge": "yes", "layer": "1", "width": "3"},
        ),
    ]
    g = graph_for(ways)
    w = next(p for p in g.pedestrian if p.osm_way_id == 2)
    w.polyline = [(x, GROUND + 6.0, z) for x, _y, z in w.polyline]
    r = build_bridges(g, ground, CFG.bridges)
    assert [b.kind for b in r.bridges] == ["footbridge"]
    assert len(r.bridges[0].ends) == 2


def test_bridges_export_round_trips_as_plain_data():
    g = graph_for(OVERPASS)
    d = build_bridges(g, ground, CFG.bridges).to_dict()
    assert d["schema_version"] == 0
    b = d["bridges"][0]
    assert {
        "id",
        "kind",
        "edges",
        "walkways",
        "span_m",
        "depth_m",
        "decks",
        "piers",
        "ends",
    } <= set(b)
    assert all(len(s["points"]) == len(s["left_m"]) == len(s["right_m"]) for s in b["decks"])
    assert not math.isnan(b["span_m"])


def test_export_matches_the_schema():
    import json
    from pathlib import Path

    from jsonschema import Draft202012Validator

    schema = json.loads(
        (Path(__file__).parents[2] / "docs" / "pack-format" / "bridges.schema.v0.json").read_text()
    )
    ways = OVERPASS + [
        (
            5,
            [(-40, -7), (40, -7)],
            {"highway": "footway", "footway": "sidewalk", "bridge": "yes", "layer": "1"},
        )
    ]
    d = build_bridges(graph_for(ways), ground, CFG.bridges).to_dict()
    errors = list(Draft202012Validator(schema).iter_errors(d))
    assert not errors, errors[0].message
