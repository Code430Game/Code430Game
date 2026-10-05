"""Parking lots and street bays: kinds, stall direction from aisles, entrances, bays by side."""

import json

import jsonschema
import pytest

from osm_import.config import load_config
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.parking import build_parking
from osm_import.projection import Projector
from pack_tools.validate import PARKING_SCHEMA_PATH
from tests.osm_helpers import BBOX, ll, make_data

CFG = load_config()


class Flat:
    def sample(self, x: float, z: float) -> float:
        return 70.0


def _ring(pts):
    geom = [{"lat": ll(x, z)[0], "lon": ll(x, z)[1]} for x, z in pts]
    return geom + [geom[0]]


def _lot(wid, pts, **tags):
    return {
        "type": "way",
        "id": wid,
        "tags": {"amenity": "parking", **tags},
        "geometry": _ring(pts),
    }


def _run(ways, lots):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    proj = Projector.for_bbox(BBOX)
    graph = build_graph(data, fr.drivable, fr.pedestrian, proj, CFG)
    return build_parking({"elements": lots}, BBOX, proj, graph, Flat(), data)


STREETS = [
    (1, [(-200, 0), (30, 0), (200, 0)], {"highway": "residential", "name": "Lot Street"}),
    (2, [(30, 0), (30, 45)], {"highway": "service", "service": "parking_aisle"}),
]


def test_lot_with_an_aisle_takes_its_direction_and_an_entrance_at_the_street():
    r = _run(
        STREETS,
        [
            _lot(
                10,
                [(0, 10), (60, 10), (60, 50), (0, 50)],
                capacity="40",
                operator="City Lots",
                fee="yes",
            )
        ],
    )
    (lot,) = r.lots
    assert lot.kind == "surface"
    assert lot.capacity == 40 and lot.operator == "City Lots" and lot.fee == "yes"
    assert lot.stall_dir == pytest.approx(
        (0.0, 1.0), abs=0.02
    )  # along the aisle (UTM grid convergence tilts it about 0.5 degrees)
    assert lot.aisles == ["w2.0"]
    assert len(lot.entrances) == 1
    assert lot.entrances[0][0] == pytest.approx(30.0, abs=0.5)
    assert lot.entrances[0][2] == pytest.approx(0.0, abs=0.5)
    assert lot.ground_y == pytest.approx(70.0)


def test_lot_without_an_aisle_lies_along_its_longest_side():
    r = _run(STREETS, [_lot(11, [(100, 20), (140, 20), (140, 30), (100, 30)])])
    (lot,) = r.lots
    assert lot.aisles == [] and lot.entrances == []
    assert lot.stall_dir == pytest.approx((1.0, 0.0), abs=0.02)


def test_kinds_orientation_and_small_or_open_rings():
    lots = [
        _lot(12, [(-100, 20), (-60, 20), (-60, 60), (-100, 60)], orientation="diagonal"),
        _lot(13, [(-160, 20), (-120, 20), (-120, 60), (-160, 60)], parking="multi-storey"),
        _lot(14, [(150, 60), (153, 60), (153, 63), (150, 63)]),  # 9 m2: too small
        {
            "type": "way",
            "id": 15,
            "tags": {"amenity": "parking"},
            "geometry": _ring([(0, 80), (10, 80), (10, 90)])[:-1],
        },
    ]
    r = _run(STREETS, lots)
    by_id = {lot.id: lot for lot in r.lots}
    assert by_id["w12.0"].orientation == "diagonal"
    assert by_id["w13.0"].kind == "multi-storey"
    assert "w14.0" not in by_id
    assert any(s["id"] == "w15" for s in r.skipped)


def test_street_bays_by_side_in_both_tagging_schemes():
    ways = [
        (
            1,
            [(-200, 0), (200, 0)],
            {
                "highway": "residential",
                "parking:right": "lane",
                "parking:right:orientation": "diagonal",
            },
        ),
        (2, [(-200, 100), (200, 100)], {"highway": "residential", "parking:lane:both": "parallel"}),
        # Drawn east to west and one-way backwards: the edge runs west to east, so sides swap.
        (
            3,
            [(200, 200), (-200, 200)],
            {"highway": "residential", "oneway": "-1", "parking:left": "lane"},
        ),
        (4, [(-200, 300), (200, 300)], {"highway": "residential", "parking:both": "no"}),
    ]
    r = _run(ways, [])
    bays = {(b.osm_way_id, b.side): b.orientation for b in r.bays}
    assert bays[(1, "right")] == "diagonal" and (1, "left") not in bays
    assert bays[(2, "left")] == "parallel" and bays[(2, "right")] == "parallel"
    assert not any(k[0] == 4 for k in bays)
    way3 = [b for b in r.bays if b.osm_way_id == 3]
    assert way3, "the reversed one-way's bay is exported"
    assert {b.side for b in way3} == {"right"}  # left of the OSM way is right of the edge


def test_output_matches_the_schema():
    r = _run(STREETS, [_lot(10, [(0, 10), (60, 10), (60, 50), (0, 50)])])
    schema = json.loads(PARKING_SCHEMA_PATH.read_text(encoding="utf-8"))
    jsonschema.validate(r.to_dict(), schema)
