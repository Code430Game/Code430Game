"""District borders (add-district-stitching 1.1): the graph is cut at the border, each road
that leaves ends on the border line as a crossing, and two neighbouring districts' crossings
on their shared line pair up (same place, opposite heading, lanes out = lanes in)."""

import json
import math
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

from osm_import.border import clip_polyline, side_of
from osm_import.config import load_config
from osm_import.elevation import FlatSource
from osm_import.osm_data import BBox, OsmData
from osm_import.pipeline import DEFAULT_CONFIG_PATH, run_pipeline
from osm_import.projection import Projector

REPO = Path(__file__).resolve().parents[2]
PG = REPO / "regions" / "proving-ground"
SCHEMA = REPO / "docs" / "pack-format" / "border.schema.v0.json"
RECT = (0.0, 0.0, 100.0, 100.0)


def test_a_polyline_is_cut_where_it_leaves_and_comes_back():
    pl = [(-50.0, 0.0, 50.0), (50.0, 2.0, 50.0), (150.0, 4.0, 50.0)]
    runs = clip_polyline(pl, RECT)
    assert len(runs) == 1
    pts, starts, ends = runs[0]
    assert not starts and not ends
    assert pts[0] == pytest.approx((0.0, 1.0, 50.0)) and pts[-1] == pytest.approx(
        (100.0, 3.0, 50.0)
    )
    # Out and back in: two runs; the inside ends keep their own points.
    loop = [(50.0, 0, 50.0), (150.0, 0, 50.0), (150.0, 0, 80.0), (50.0, 0, 80.0)]
    runs = clip_polyline(loop, RECT)
    assert [(r[1], r[2]) for r in runs] == [(True, False), (False, True)]
    assert clip_polyline([(200.0, 0, 0), (300.0, 0, 0)], RECT) == []


def test_side_of_names_the_nearest_border_line():
    assert side_of((0.0, 40.0), RECT) == "west"
    assert side_of((100.0, 40.0), RECT) == "east"
    assert side_of((40.0, 0.0), RECT) == "north"
    assert side_of((40.0, 100.0), RECT) == "south"


def _district(chunks):
    """The proving ground's roads as one district of a split (origin at its centre)."""
    region = json.loads((REPO / "regions" / "proving-ground.json").read_text())
    s, w, n, e = region["bbox"]
    bbox = BBox(s, w, n, e)
    data = OsmData.load(PG / "osm.json")
    cfg = load_config(DEFAULT_CONFIG_PATH)
    proj = Projector.for_bbox(bbox)
    return run_pipeline(
        data, bbox, cfg, DEFAULT_CONFIG_PATH.name, FlatSource(), proj, border_chunks=chunks
    )


def test_two_neighbouring_districts_cut_every_road_at_the_same_place():
    # Split at x = 256 m: the generated district has a road along x = 0, which real data doesn't.
    west = _district((-3, -4, 1, 4)).border
    east = _district((1, -4, 3, 4)).border
    w_out = [c for c in west.crossings if c.side == "east"]
    e_out = [c for c in east.crossings if c.side == "west"]
    assert w_out, "the proving ground has roads across x = 256"
    assert len(w_out) == len(e_out)
    for c in w_out:
        assert c.position[0] == pytest.approx(256.0, abs=1e-6)
        match = [
            d
            for d in e_out
            if math.dist((c.position[0], c.position[2]), (d.position[0], d.position[2])) < 1.0
            and d.osm_way_id == c.osm_way_id
        ]
        assert len(match) == 1, f"no partner for {c.edge} at {c.position}"
        d = match[0]
        assert c.heading[0] * d.heading[0] + c.heading[1] * d.heading[1] < -math.cos(
            math.radians(15)
        )
        assert (c.lanes_out, c.lanes_in) == (d.lanes_in, d.lanes_out)
        assert abs(c.position[1] - d.position[1]) < 0.05  # heights graded the same either side


def test_the_cut_graph_stays_inside_and_ends_on_border_nodes():
    result = _district((-3, -4, 0, 4))
    x0, z0, x1, z1 = result.border.rect
    g = result.graph
    for e in g.edges.values():
        assert e.from_node in g.nodes and e.to_node in g.nodes
        for p in e.polyline:
            assert x0 - 1e-6 <= p[0] <= x1 + 1e-6 and z0 - 1e-6 <= p[2] <= z1 + 1e-6
    for c in result.border.crossings:
        assert g.nodes[c.node].junction_type == "dead_end"
        assert c.edge in g.edges
    for w in g.pedestrian:
        assert all(x0 - 1e-6 <= p[0] <= x1 + 1e-6 for p in w.polyline)
    Draft202012Validator(json.loads(SCHEMA.read_text())).validate(result.border.to_dict())
    # The graph file still validates with the border's ids.
    road_schema = json.loads(
        (REPO / "docs" / "pack-format" / "road_graph.schema.v0.json").read_text()
    )
    errors = list(Draft202012Validator(road_schema).iter_errors(result.graph_dict))
    assert not errors, errors[0].message


def test_without_a_border_nothing_is_cut():
    assert _district(None).border is None


def test_a_road_along_a_border_line_belongs_to_one_district():
    along = [(100.0, 0.0, 20.0), (100.0, 0.0, 80.0)]  # on the east line
    assert clip_polyline(along, RECT) == []
    assert len(clip_polyline([(0.0, 0.0, 20.0), (0.0, 0.0, 80.0)], RECT)) == 1  # west line: ours


def test_roadblocks_at_the_cut_ends_are_tagged_with_their_side():
    from osm_import.barriers import build_barriers

    result = _district((-3, -4, 1, 4))
    cfg = load_config(DEFAULT_CONFIG_PATH)
    barriers = build_barriers(
        result.graph, FlatSource(), None, cfg, result.border.rect, [], border=True
    )
    blocks = [b for b in barriers.barriers if b.kind == "roadblock"]
    assert blocks and all(b.border_side in ("west", "east", "north", "south") for b in blocks)
    crossing_edges = {c.edge for c in result.border.crossings if c.side == "east"}
    east_blocks = {b.edge_id for b in blocks if b.border_side == "east"}
    assert east_blocks <= crossing_edges and east_blocks
    out = barriers.to_dict()["barriers"]
    assert any(b.get("border_side") == "east" for b in out)
    schema = json.loads((REPO / "docs" / "pack-format" / "barriers.schema.v0.json").read_text())
    Draft202012Validator(schema).validate(barriers.to_dict())
