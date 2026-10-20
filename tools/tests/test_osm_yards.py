"""Yards: front lawns toward the street, backyards behind, paths, frontage, fences."""

import json
from pathlib import Path

from jsonschema import Draft202012Validator
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

from osm_import.yards import build_yards
from tests.test_osm_houses import LANE, STREET, _build, _house

SCHEMA = Path(__file__).parents[2] / "docs" / "pack-format" / "yards.schema.v0.json"


def _yards(houses, ways=STREET):
    result, hints, graph = _build(houses, ways)
    yards = build_yards(result, graph)
    return result, hints, yards, {y.house: y for y in yards.yards}


def _union(polys):
    return unary_union([Polygon(p.exterior) for p in polys])


def test_front_lawn_faces_the_street_and_the_backyard_lies_behind():
    # South of an east-west street (z grows south): front toward smaller z.
    _, hints, _, by = _yards([_house(1, -5, 10, 5, 20, building="detached")])
    y = by["w1.0"]
    front, back = _union(y.front), _union(y.back)
    assert front.area > 20 and back.area > 50
    assert front.centroid.y < 10.5 and back.centroid.y > 19.5
    # Nothing of the yard is on the street or its sidewalk (carriageway half width + 2 m).
    assert front.bounds[1] > 2.0
    # The path leaves the door toward the street, across the lawn.
    assert len(y.path) == 2
    assert Point(y.path[0]).distance(Point(hints["w1.0"].door)) < 0.01
    assert y.path[1][1] < y.path[0][1] - 1.0
    # The frontage runs along the street side of the lawn.
    assert y.frontage and all(max(p[1] for p in line) < 10.0 for line in y.frontage)


def test_neighbours_get_a_fence_between_backyards_not_between_front_lawns():
    houses = [
        _house(1, -12, 10, -2, 20, building="detached"),
        _house(2, 2, 10, 12, 20, building="detached"),
    ]
    _, _, yards, by = _yards(houses)
    assert len(yards.fences) >= 1
    f = yards.fences[0]
    assert set(f.houses) == {"w1.0", "w2.0"}
    line = LineString(f.points)
    assert abs(line.centroid.x) < 1.5  # midway between the two houses
    assert min(p[1] for p in f.points) >= 19.0  # starts at the backs, not in the front lawns
    front = _union(by["w1.0"].front).union(_union(by["w2.0"].front))
    assert line.intersection(front).length < 0.5


def test_a_terrace_row_fences_every_backyard():
    row = [_house(10 + k, k * 6.0, 8, k * 6.0 + 6.0, 18, building="terrace") for k in range(4)]
    _, _, yards, by = _yards(row)
    pairs = {tuple(sorted(f.houses)) for f in yards.fences}
    for k in range(3):
        assert (f"w{10 + k}.0", f"w{11 + k}.0") in pairs
    assert all(by[f"w{10 + k}.0"].path for k in range(4))


def test_no_fence_or_yard_across_a_driveway_or_a_lane():
    drive = [(3, [(0.0, 0.0), (0.0, 40.0)], {"highway": "service", "service": "driveway"})]
    houses = [
        _house(1, -12, 10, -3, 20, building="detached"),
        _house(2, 3, 10, 12, 20, building="detached"),
    ]
    _, _, yards, by = _yards(houses, STREET + drive)
    driveway = LineString([(0.0, 0.0), (0.0, 40.0)]).buffer(1.0, cap_style="flat")
    for f in yards.fences:
        assert LineString(f.points).intersection(driveway).length < 0.2
    for y in by.values():
        for p in y.front + y.back + y.side:
            assert p.intersection(driveway).area < 1.0
    # A lane behind: the backyard stops at it.
    _, _, _, by = _yards([_house(1, -5, 30, 5, 40, building="detached")], STREET + LANE)
    assert _union(by["w1.0"].back).bounds[3] < 60.0


def test_yards_export_and_validate():
    houses = [
        _house(1, -12, 10, -2, 20, building="detached"),
        _house(2, 2, 10, 12, 20, building="detached"),
    ]
    _, _, yards, _ = _yards(houses)
    data = yards.to_dict()
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    assert list(Draft202012Validator(schema).iter_errors(data)) == []
    assert [y["house"] for y in data["yards"]] == ["w1.0", "w2.0"]
    assert _yards(houses)[2].to_dict() == data  # deterministic
