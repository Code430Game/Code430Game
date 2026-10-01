import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

from osm_import.buildings import build_buildings, building_height
from osm_import.config import load_config
from osm_import.elevation import FlatSource, SyntheticSource
from osm_import.osm_data import BBox
from osm_import.pack import flatten_buildings, sample_chunk
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, ll

HERE = Path(__file__).parent
FIXTURE = HERE / "fixtures" / "buildings_centretown_subset.osm.json"
DISTRICT = BBox(45.405, -75.715, 45.435, -75.675)
SCHEMA = HERE.parents[1] / "docs" / "pack-format" / "buildings.schema.v0.json"
RULES = load_config().buildings


def test_height_rules():
    assert building_height({"height": "24"}, RULES) == (24.0, "tag")
    assert building_height({"height": "40 ft"}, RULES)[0] == pytest.approx(12.192)
    assert building_height({"building:levels": "3"}, RULES) == (pytest.approx(9.6), "levels")
    assert building_height({"building": "apartments"}, RULES) == (pytest.approx(6 * 3.2), "default")
    assert building_height({"building": "shed"}, RULES) == (3.2, "default")
    assert building_height({"building": "mystery"}, RULES) == (pytest.approx(2 * 3.2), "default")
    assert building_height({"height": "1"}, RULES)[0] == 3.0  # minimum


def _way(way_id, cx, cz, half, tags):
    pts = [
        ll(cx - half, cz - half),
        ll(cx + half, cz - half),
        ll(cx + half, cz + half),
        ll(cx - half, cz + half),
    ]
    pts.append(pts[0])
    return {
        "type": "way",
        "id": way_id,
        "tags": tags,
        "geometry": [{"lat": a, "lon": b} for a, b in pts],
    }


def test_synthetic_footprints_clip_and_ground():
    payload = {
        "elements": [
            _way(1, 0, 0, 10, {"building": "house"}),
            _way(2, 5000, 5000, 10, {"building": "house"}),  # outside
            _way(3, 0, -445, 10, {"building": "yes", "height": "12"}),  # straddles the bbox edge
            _way(4, 50, 50, 10, {"building": "no"}),
        ]
    }
    proj = Projector.for_bbox(BBOX)
    result = build_buildings(payload, BBOX, proj, FlatSource(30.0), RULES)
    ids = [b.id for b in result.buildings]
    assert ids == ["w1.0", "w3.0"]
    house = result.buildings[0]
    assert (
        house.kind == "house"
        and house.height_m == pytest.approx(6.4)
        and house.ground_y == pytest.approx(30.0)
    )
    assert len(house.rings) == 1 and len(house.rings[0]) == 4
    assert len(house.roof_triangles) == 6
    assert house.roof_vertices == house.rings[0]  # single ring: roof indices address the ring
    assert result.to_dict()["buildings"][0]["roof_vertices"] == []
    _min_x, min_z, _max_x, _max_z = proj.bbox_local(BBOX)
    assert min(z for _, z in result.buildings[1].rings[0]) >= min_z - 1e-6


def test_real_fixture_validates_and_is_deterministic():
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    proj = Projector.for_bbox(DISTRICT)
    result = build_buildings(payload, DISTRICT, proj, SyntheticSource(), RULES)
    assert len(result.buildings) >= 10
    assert result.skipped == []
    data = result.to_dict()
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    assert list(Draft202012Validator(schema).iter_errors(data)) == []
    assert build_buildings(payload, DISTRICT, proj, SyntheticSource(), RULES).to_dict() == data
    assert set(result.height_sources) <= {"tag", "levels", "default"}


def test_flatten_buildings_sets_ground_inside_only():
    from osm_import.buildings import Building, BuildingsResult

    b = Building(
        "w1.0",
        "house",
        None,
        6.0,
        42.0,
        [[(20.0, 20.0), (60.0, 20.0), (60.0, 60.0), (20.0, 60.0)]],
        [(20.0, 20.0), (60.0, 20.0), (60.0, 60.0), (20.0, 60.0)],
        [0, 1, 2, 0, 2, 3],
        1,
        "default",
    )
    chunk = sample_chunk(FlatSource(50.0), 0, 0)
    changed = flatten_buildings(chunk, BuildingsResult([b]))
    assert changed > 0
    assert chunk.heights[10, 10] == pytest.approx(42.0)  # (40, 40) inside
    assert chunk.heights[2, 2] == pytest.approx(50.0)  # outside


def test_material_colour_roof_and_shopfront_come_through():
    payload = {
        "elements": [
            _way(
                1,
                0,
                0,
                12,
                {
                    "building": "apartments",
                    "building:material": "Brick",
                    "building:colour": "#aabbcc",
                    "roof:shape": "gabled",
                    "building:levels": "5",
                    "roof:levels": "1",
                },
            ),
            _way(2, 100, 0, 12, {"building": "yes", "shop": "bakery"}),
            _way(3, 200, 0, 12, {"building": "yes", "amenity": "cafe"}),
            _way(4, 300, 0, 12, {"building": "retail"}),
            _way(5, 400, 0, 12, {"building": "house"}),
        ]
    }
    proj = Projector.for_bbox(BBOX)
    result = build_buildings(payload, BBOX, proj, FlatSource(30.0), RULES)
    by_id = {b.id: b for b in result.buildings}
    a = by_id["w1.0"]
    assert (a.material, a.colour, a.roof_shape, a.levels, a.roof_levels) == (
        "brick",
        "#aabbcc",
        "gabled",
        5.0,
        1.0,
    )
    assert [by_id[f"w{i}.0"].shopfront for i in (1, 2, 3, 4, 5)] == [False, True, True, True, False]
    d = result.to_dict()["buildings"][0]
    assert d["material"] == "brick" and d["shopfront"] is False
