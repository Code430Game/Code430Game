import json
from pathlib import Path

import numpy as np
import pytest
from jsonschema import Draft202012Validator

from osm_import.elevation import FlatSource, SyntheticSource
from osm_import.osm_data import BBox
from osm_import.pack import lower_water, sample_chunk
from osm_import.projection import Projector
from osm_import.water import WaterPolygon, WaterResult, assemble_rings, build_water
from tests.osm_helpers import BBOX, ll

HERE = Path(__file__).parent
FIXTURE = HERE / "fixtures" / "water_ottawa_subset.osm.json"
DISTRICT = BBox(45.405, -75.715, 45.435, -75.675)
SCHEMA = HERE.parents[1] / "docs" / "pack-format" / "water.schema.v0.json"


def geom(points):
    return [{"lat": lat, "lon": lon} for lat, lon in points]


def test_assemble_rings_joins_pieces_in_any_direction():
    a, b, c, d = (0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)
    members = [
        {"type": "way", "role": "outer", "geometry": geom([a, b])},
        {"type": "way", "role": "outer", "geometry": geom([c, b])},  # reversed piece
        {"type": "way", "role": "outer", "geometry": geom([c, d, a])},
        {
            "type": "way",
            "role": "inner",
            "geometry": geom([(0.2, 0.2), (0.2, 0.4), (0.4, 0.4), (0.2, 0.2)]),
        },
    ]
    outers, inners, unclosed = assemble_rings(members)
    assert unclosed == 0
    assert len(outers) == 1 and len(inners) == 1
    assert outers[0][0] == outers[0][-1]
    assert set(outers[0]) == {a, b, c, d}


def test_assemble_rings_reports_unclosed():
    members = [{"type": "way", "role": "outer", "geometry": geom([(0, 0), (0, 1), (1, 1)])}]
    outers, _, unclosed = assemble_rings(members)
    assert outers == [] and unclosed == 1


def _square_way(way_id, cx, cz, half, tags):
    pts = [
        ll(cx - half, cz - half),
        ll(cx + half, cz - half),
        ll(cx + half, cz + half),
        ll(cx - half, cz + half),
    ]
    pts.append(pts[0])
    return {"type": "way", "id": way_id, "tags": tags, "geometry": geom(pts)}


def test_synthetic_lake_with_island_is_triangulated_and_clipped():
    outer = _square_way(1, 0, 0, 200, {})
    island = _square_way(2, 0, 0, 30, {})
    relation = {
        "type": "relation",
        "id": 10,
        "tags": {"natural": "water", "water": "lake", "name": "Test Lake"},
        "members": [
            {"type": "way", "role": "outer", "geometry": outer["geometry"]},
            {"type": "way", "role": "inner", "geometry": island["geometry"]},
        ],
    }
    proj = Projector.for_bbox(BBOX)
    result = build_water({"elements": [relation]}, BBOX, proj, FlatSource(12.0))
    assert result.skipped == []
    assert len(result.polygons) == 1
    p = result.polygons[0]
    assert p.id == "r10.0" and p.name == "Test Lake" and p.kind == "lake"
    assert p.surface_y == pytest.approx(12.0)
    tri = np.array(p.triangles).reshape(-1, 3)
    v = np.array(p.vertices)
    area = 0.0
    for a, b, c in tri:
        area += (
            abs(
                (v[b][0] - v[a][0]) * (v[c][1] - v[a][1])
                - (v[c][0] - v[a][0]) * (v[b][1] - v[a][1])
            )
            / 2.0
        )
    assert area == pytest.approx(400 * 400 - 60 * 60, rel=0.02)


def test_polygon_outside_bbox_is_dropped_and_crossing_one_is_clipped():
    far = _square_way(3, 5000, 5000, 100, {"natural": "water"})
    edge = _square_way(4, 0, -450, 100, {"natural": "water"})  # bbox is about +-445 m in z
    proj = Projector.for_bbox(BBOX)
    result = build_water({"elements": [far, edge]}, BBOX, proj, FlatSource(1.0))
    ids = [p.id for p in result.polygons]
    assert ids == ["w4.0"]
    zs = [z for _, z in result.polygons[0].vertices]
    _min_x, min_z, _max_x, _max_z = proj.bbox_local(BBOX)
    assert min(zs) >= min_z - 1e-6


def test_real_fixture_assembles_and_validates_schema():
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert payload["code430_source"]["attribution"] == "© OpenStreetMap contributors"
    proj = Projector.for_bbox(DISTRICT)
    result = build_water(payload, DISTRICT, proj, SyntheticSource())
    assert result.skipped == []
    names = {p.name for p in result.polygons}
    assert "Patterson's Creek" in names and "Rideau Canal" in names
    data = result.to_dict()
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    assert list(Draft202012Validator(schema).iter_errors(data)) == []
    again = build_water(payload, DISTRICT, proj, SyntheticSource()).to_dict()
    assert again == data


def test_lower_water_lowers_cells_inside_only():
    water = WaterResult(
        polygons=[
            WaterPolygon(
                "w1.0",
                None,
                "pond",
                40.0,
                [(20.0, 20.0), (100.0, 20.0), (100.0, 100.0), (20.0, 100.0)],
                [0, 1, 2, 0, 2, 3],
                1,
            )
        ]
    )
    chunk = sample_chunk(FlatSource(50.0), 0, 0)
    changed = lower_water(chunk, water, 1.5)
    assert changed > 0
    assert chunk.heights[10, 10] == pytest.approx(38.5)  # (40, 40) inside
    assert chunk.heights[2, 2] == pytest.approx(50.0)  # (8, 8) outside
