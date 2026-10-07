"""Service place addresses for the map's places list (add-map-legend 1.1)."""

import json
from pathlib import Path
from types import SimpleNamespace

import jsonschema

from osm_import.services import (
    address_for,
    addressed_buildings,
    build_services,
    format_address,
)

SCHEMA = Path(__file__).resolve().parents[2] / "docs/pack-format/services.schema.v0.json"
RULES = {"building_near_m": 15.0, "street_near_m": 120.0}


class FlatProjector:
    """1 degree = 100,000 m on both axes, z south: enough for placing test geometry."""

    def to_local(self, lat: float, lon: float) -> tuple[float, float]:
        return lon * 1e5, -lat * 1e5

    def bbox_local(self, bbox) -> tuple[float, float, float, float]:
        return -1e9, -1e9, 1e9, 1e9


class FlatGround:
    def sample(self, x: float, z: float) -> float:
        return 0.0


def _graph(*edges):
    """A road graph stand-in: named edges as ((x, z), (x, z)) polylines, one node per end."""
    nodes, out = {}, {}
    for i, (name, a, b) in enumerate(edges):
        out[f"e{i}"] = SimpleNamespace(name=name, polyline=[(a[0], 0.0, a[1]), (b[0], 0.0, b[1])])
        nodes[f"n{i}a"] = SimpleNamespace(position=(a[0], 0.0, a[1]))
        nodes[f"n{i}b"] = SimpleNamespace(position=(b[0], 0.0, b[1]))
    return SimpleNamespace(nodes=nodes, edges=out)


def _square(cx: float, cz: float, half: float) -> list[tuple[float, float]]:
    return [
        (cx - half, cz - half),
        (cx + half, cz - half),
        (cx + half, cz + half),
        (cx - half, cz + half),
    ]


def _building_way(way_id: int, ring: list[tuple[float, float]], tags: dict) -> dict:
    # FlatProjector: x = lon * 1e5, z = -lat * 1e5
    return {
        "type": "way",
        "id": way_id,
        "tags": tags,
        "geometry": [{"lat": -z / 1e5, "lon": x / 1e5} for x, z in ring],
    }


def test_an_address_reads_number_street_and_unit():
    assert (
        format_address({"addr:housenumber": "474", "addr:street": "Elgin Street"})
        == "474 Elgin Street"
    )
    assert (
        format_address(
            {"addr:housenumber": "240", "addr:street": "Catherine Street", "addr:unit": "Suite 100"}
        )
        == "240 Catherine Street, Suite 100"
    )
    assert format_address(
        {"addr:housenumber": "130", "addr:street": "Albert Street", "addr:unit": "1201"}
    ) == ("130 Albert Street, Unit 1201")
    assert format_address({"addr:street": "Elgin Street"}) is None
    assert format_address({"addr:housenumber": "474"}) is None


def test_a_place_with_its_own_address_keeps_it():
    graph = _graph(("Bank Street", (0, 0), (100, 0)))
    buildings = [("1 Other Street", _square(10, 10, 20))]
    tags = {"addr:housenumber": "530", "addr:street": "King Edward Avenue"}
    assert address_for(tags, 10, 10, buildings, graph, RULES) == ("530 King Edward Avenue", "tags")


def test_a_place_without_tags_takes_the_building_it_stands_in():
    graph = _graph(("Bank Street", (0, 0), (100, 0)))
    buildings = [("9 Near Street", _square(40, 10, 5)), ("474 Elgin Street", _square(10, 10, 20))]
    assert address_for({}, 10, 10, buildings, graph, RULES) == ("474 Elgin Street", "building")


def test_a_place_just_outside_a_building_takes_the_nearest_within_reach():
    graph = _graph(("Bank Street", (0, 0), (500, 0)))
    buildings = [
        ("464 Metcalfe Street", _square(100, 100, 10)),
        ("2 Far Street", _square(200, 100, 10)),
    ]
    # 6 m east of the first building's edge, 84 m from the second
    assert address_for({}, 116, 100, buildings, graph, RULES) == ("464 Metcalfe Street", "building")


def test_with_no_building_near_it_falls_back_to_the_nearest_street():
    graph = _graph(
        ("Bronson Avenue", (0, 0), (0, 300)),
        (None, (40, 0), (40, 300)),
        ("Far Road", (500, 0), (500, 300)),
    )
    buildings = [("1 Away Street", _square(300, 300, 5))]
    assert address_for({}, 60, 100, buildings, graph, RULES) == ("on Bronson Avenue", "street")


def test_with_nothing_in_reach_there_is_no_address():
    graph = _graph(("Far Road", (1000, 0), (1000, 300)))
    assert address_for({}, 0, 0, [], graph, RULES) == (None, "none")


def test_buildings_without_a_full_address_are_skipped():
    payload = {
        "elements": [
            _building_way(2, _square(0, 0, 5), {"building": "yes", "addr:housenumber": "5"}),
            _building_way(
                1,
                _square(50, 0, 5),
                {"building": "yes", "addr:housenumber": "50", "addr:street": "Rideau Street"},
            ),
            {"type": "relation", "id": 3, "tags": {"addr:housenumber": "1", "addr:street": "X"}},
        ]
    }
    out = addressed_buildings(payload, FlatProjector())
    assert [a for a, _ring in out] == ["50 Rideau Street"]


def test_built_places_carry_addresses_and_match_the_schema():
    graph = _graph(("Elgin Street", (0, 0), (0, 400)))
    station = {
        "type": "way",
        "id": 207590986,
        "center": {"lat": -100 / 1e5, "lon": 20 / 1e5},
        "tags": {"amenity": "police", "name": "Ottawa Police Headquarters"},
    }
    post = {
        "type": "node",
        "id": 5,
        "lat": -300 / 1e5,
        "lon": 60 / 1e5,
        "tags": {"emergency": "ambulance_station", "name": "Ambulance Post"},
    }
    pad = {
        "type": "node",
        "id": 6,
        "lat": -100 / 1e5,
        "lon": 900 / 1e5,
        "tags": {"aeroway": "helipad"},
    }
    buildings = {
        "elements": [
            _building_way(
                68710184,
                _square(20, 100, 15),
                {"building": "public", "addr:housenumber": "474", "addr:street": "Elgin Street"},
            )
        ]
    }
    res = build_services(
        {"elements": [pad, post, station]},
        None,
        FlatProjector(),
        graph,
        FlatGround(),
        buildings,
        {"building_near_m": 15.0, "street_near_m": 120.0, "_comment": "ignored"},
    )
    by_id = {p.id: p for p in res.places}
    assert by_id["w207590986"].address == "474 Elgin Street"
    assert by_id["n5"].address == "on Elgin Street"
    assert by_id["n6"].address is None
    assert res.address_sources() == {"tags": 0, "building": 1, "street": 1, "none": 1}
    doc = res.to_dict()
    jsonschema.validate(doc, json.loads(SCHEMA.read_text(encoding="utf-8")))
    exported = {p["id"]: p for p in doc["places"]}
    assert "address" not in exported["n6"], "no address is left out, not written as null"
    assert "address_source" not in exported["w207590986"]


def test_the_ottawa_pack_has_real_addresses_for_its_places():
    pack = Path(__file__).resolve().parents[2] / "packs/ottawa-centretown/services.v0.json"
    places = json.loads(pack.read_text(encoding="utf-8"))["places"]
    by_name = {p["name"]: p.get("address") for p in places}
    assert by_name["Ottawa Police Headquarters"] == "474 Elgin Street"
    assert by_name["Ottawa Fire Station 11"] == "135 Preston Street"
    with_address = [p for p in places if p.get("address")]
    assert len(with_address) >= len(places) - 1
