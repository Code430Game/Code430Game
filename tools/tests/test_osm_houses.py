"""House hints: types, the front wall toward the street, doors, party walls, heights."""

import json

import pytest
from jsonschema import Draft202012Validator

from osm_import.buildings import build_buildings
from osm_import.config import load_config
from osm_import.elevation import FlatSource
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.houses import EAVE_M, build_house_hints, house_type
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, ll, make_data
from tests.test_osm_buildings import SCHEMA

CFG = load_config()
STREET = [(1, [(-200.0, 0.0), (200.0, 0.0)], {"highway": "residential", "name": "Test St"})]
LANE = [(2, [(-200.0, 60.0), (200.0, 60.0)], {"highway": "service", "service": "alley"})]


def _house(wid, x0, z0, x1, z1, **tags):
    pts = [ll(x0, z0), ll(x1, z0), ll(x1, z1), ll(x0, z1)]
    pts.append(pts[0])
    return {
        "type": "way",
        "id": wid,
        "tags": tags,
        "geometry": [{"lat": a, "lon": b} for a, b in pts],
    }


def _run(houses, ways=STREET):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    proj = Projector.for_bbox(BBOX)
    graph = build_graph(data, fr.drivable, fr.pedestrian, proj, CFG)
    result = build_buildings({"elements": houses}, BBOX, proj, FlatSource(30.0), CFG.buildings)
    return result, build_house_hints(result, graph)


def _front_mid(result, hints, bid):
    b = next(b for b in result.buildings if b.id == bid)
    ring = b.rings[0]
    i = hints[bid].front_edge
    a, c = ring[i], ring[(i + 1) % len(ring)]
    return ((a[0] + c[0]) / 2.0, (a[1] + c[1]) / 2.0)


def test_front_faces_the_street_not_the_lane():
    # South of the street (z grows south), 8 m back from it; an alley runs behind at z = 60.
    result, hints = _run([_house(1, -5, 8, 5, 20, building="detached")], STREET + LANE)
    h = hints["w1.0"]
    assert _front_mid(result, hints, "w1.0")[1] == pytest.approx(8.0, abs=0.5)
    assert h.street is not None and h.setback_m == pytest.approx(8.0 - 3.0, abs=1.5)
    assert h.door[1] == pytest.approx(8.0, abs=0.5) and h.door[0] == pytest.approx(0.0, abs=0.5)
    assert h.party_walls == []


def test_house_across_the_street_faces_it_too():
    result, hints = _run([_house(1, -5, -20, 5, -8, building="house")])
    assert _front_mid(result, hints, "w1.0")[1] == pytest.approx(-8.0, abs=0.5)


def test_terrace_row_shares_party_walls_and_each_unit_has_a_door():
    row = [_house(10 + k, k * 6.0, 6, k * 6.0 + 6.0, 18, building="terrace") for k in range(4)]
    result, hints = _run(row)
    assert {hints[f"w{10 + k}.0"].type for k in range(4)} == {"terrace"}
    # Untagged units in a row are terraces too, the end units included.
    plain = [_house(40 + k, k * 6.0, 6, k * 6.0 + 6.0, 18, building="house") for k in range(3)]
    assert {h.type for h in _run(plain)[1].values()} == {"terrace"}
    assert [len(hints[f"w{10 + k}.0"].party_walls) for k in range(4)] == [1, 2, 2, 1]
    for k in range(4):
        h = hints[f"w{10 + k}.0"]
        assert h.front_edge not in h.party_walls
        assert _front_mid(result, hints, f"w{10 + k}.0")[1] == pytest.approx(6.0, abs=0.5)
        assert k * 6.0 < h.door[0] < k * 6.0 + 6.0


def test_a_pair_of_houses_is_semi_detached():
    pair = [_house(20, 0, 6, 7, 18, building="house"), _house(21, 7, 6, 14, 18, building="house")]
    _, hints = _run(pair)
    assert hints["w20.0"].type == hints["w21.0"].type == "semi"
    # A gap of 3 m is two detached houses, not a pair.
    apart = [_house(22, 0, 6, 9, 18, building="house"), _house(23, 12, 6, 21, 18, building="house")]
    _, hints = _run(apart)
    assert hints["w22.0"].party_walls == hints["w23.0"].party_walls == []


def test_defaulted_heights_take_the_type_tagged_ones_stay():
    result, hints = _run(
        [
            _house(30, -40, 6, -30, 18, building="detached"),
            _house(31, 40, 6, 50, 18, building="detached", height="11"),
            _house(32, 80, 6, 92, 18, building="bungalow"),
        ]
    )
    by_id = {b.id: b for b in result.buildings}
    assert by_id["w30.0"].height_m == pytest.approx(EAVE_M[hints["w30.0"].type])
    assert by_id["w31.0"].height_m == pytest.approx(11.0)
    assert hints["w32.0"].type == "bungalow" and by_id["w32.0"].height_m == pytest.approx(3.0)


def test_types_vary_on_a_street_of_untagged_houses():
    street = [
        _house(100 + k, k * 15.0 - 150, 8, k * 15.0 - 140, 18, building="house") for k in range(20)
    ]
    _, hints = _run(street)
    types = {h.type for h in hints.values()}
    assert "detached" in types and len(types) >= 2
    assert types <= {"detached", "cottage", "bungalow"}


def test_type_rules():
    from osm_import.buildings import Building

    def b(kind, levels=0.0):
        return Building(
            "w1.0",
            kind,
            None,
            6.4,
            0.0,
            [[(0, 0), (1, 0), (1, 1)]],
            [],
            [],
            1,
            "default",
            levels=levels,
        )

    assert house_type(b("terrace"), 0, 60.0) == "terrace"
    assert house_type(b("house"), 2, 60.0) == "terrace"
    assert house_type(b("semidetached_house"), 0, 80.0) == "semi"
    assert house_type(b("house", levels=1), 0, 100.0) == "bungalow"
    assert house_type(b("detached", levels=2), 0, 100.0) == "detached"
    assert house_type(b("house"), 1, 60.0) == "semi"
    assert house_type(b("house"), 1, 60.0, in_row=True) == "terrace"


def test_hints_export_and_validate():
    result, _ = _run(
        [_house(1, -5, 8, 5, 20, building="detached"), _house(2, 50, 8, 60, 20, building="yes")]
    )
    data = result.to_dict()
    by_id = {b["id"]: b for b in data["buildings"]}
    assert by_id["w1.0"]["house"]["type"] in ("detached", "cottage", "bungalow")
    assert "house" not in by_id["w2.0"]
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    assert list(Draft202012Validator(schema).iter_errors(data)) == []
