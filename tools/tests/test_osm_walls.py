"""Retaining walls (add-retaining-walls): where the finished terrain rises steeply beside a
road's outer edge, a wall line with a top per point, broken where a way leaves the road; the
ground in front held at the edge's level; the file the game and the validator read."""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest
from jsonschema import Draft202012Validator

from osm_import.config import load_config
from osm_import.elevation import FlatSource
from osm_import.graph import PedestrianWay, RoadEdge, RoadGraph, RoadNode
from osm_import.pack import ROAD_SURFACE_DROP_M, TERRAIN_RES_M, ChunkSampler, sample_chunk
from osm_import.walls import build_walls, hold_in_front_of_walls

CFG = load_config()
SCHEMA = Path(__file__).parents[2] / "docs" / "pack-format" / "retaining_walls.schema.v0.json"
ROAD_Y = 50.0
CURB = 0.12
SIDEWALK_Z = -5.5  # north of a 7 m street along z = 0: 1 m off the ribbon edge, 2 m wide
SIDEWALK_W = 2.0
OUTER_Z = SIDEWALK_Z - SIDEWALK_W / 2.0  # the sidewalk's outer edge, where the wall stands


def _edge(eid, a, b, pts, width=7.0, cls="residential"):
    return RoadEdge(eid, a, b, pts, cls, 1, 1, False, 40, width, 0, False, False, eid, 1, [])


def _graph(side_street: bool = False) -> RoadGraph:
    """A level street along z = 0 from x = 20 to 220 with a sidewalk on its north side, and
    optionally a side street leaving north at x = 120."""
    nodes = {
        "w": RoadNode("w", (20.0, ROAD_Y, 0.0), [1]),
        "e": RoadNode("e", (220.0, ROAD_Y, 0.0), [2]),
    }
    edges = {"street": _edge("street", "w", "e", [(20.0, ROAD_Y, 0.0), (220.0, ROAD_Y, 0.0)])}
    if side_street:
        nodes["m"] = RoadNode("m", (120.0, ROAD_Y, 0.0), [3])
        nodes["n"] = RoadNode("n", (120.0, ROAD_Y, -60.0), [4])
        edges = {
            "street.0": _edge("street.0", "w", "m", [(20.0, ROAD_Y, 0.0), (120.0, ROAD_Y, 0.0)]),
            "street.1": _edge("street.1", "m", "e", [(120.0, ROAD_Y, 0.0), (220.0, ROAD_Y, 0.0)]),
            "side": _edge("side", "m", "n", [(120.0, ROAD_Y, 0.0), (120.0, ROAD_Y, -60.0)]),
        }
        nodes["m"].junction_type = "junction"
    sidewalk = PedestrianWay(
        "p1",
        [(20.0, ROAD_Y + CURB, SIDEWALK_Z), (220.0, ROAD_Y + CURB, SIDEWALK_Z)],
        "footway",
        1,
        None,
        "sidewalk",
        SIDEWALK_W,
    )
    return RoadGraph(nodes, edges, [sidewalk])


def _terrain(bank_from_z: float = -8.0, bank_y: float = ROAD_Y + 6.0, x_range=(0.0, 256.0)):
    """One flat chunk at road level with a bank north of `bank_from_z` (the finished terrain a
    deck's abutment or an under-deck clamp leaves beside a street)."""
    chunk = sample_chunk(FlatSource(ROAD_Y), 0, -1)  # z from -256 to 0
    zs = chunk.min_z + np.arange(chunk.heights.shape[0]) * TERRAIN_RES_M
    xs = chunk.min_x + np.arange(chunk.heights.shape[1]) * TERRAIN_RES_M
    rows = zs <= bank_from_z
    cols = (xs >= x_range[0]) & (xs <= x_range[1])
    chunk.heights[np.ix_(rows, cols)] = bank_y
    south = sample_chunk(FlatSource(ROAD_Y), 0, 0)
    return [chunk, south]


def _walls(graph, chunks, bridges=None):
    return build_walls(graph, ChunkSampler(chunks).sample, bridges, CFG)


def test_a_steep_bank_behind_a_sidewalk_gets_a_wall_on_that_side_only():
    graph = _graph()
    chunks = _terrain()
    result = _walls(graph, chunks)
    assert len(result.walls) == 1
    w = result.walls[0]
    assert w.id == "w:street:l0" and w.edge_id == "street"
    # At the sidewalk's outer edge, at the sidewalk's level, the length of the street.
    assert all(z == pytest.approx(OUTER_Z, abs=0.01) for _x, _y, z in w.points)
    assert all(y == pytest.approx(ROAD_Y + CURB, abs=0.01) for _x, y, _z in w.points)
    assert w.length_m() == pytest.approx(200.0, abs=2.0)
    # The top is the bank's height above the foot; height_m the tallest.
    assert all(t == pytest.approx(6.0 - CURB, abs=0.05) for t in w.tops_m)
    assert w.height_m == pytest.approx(max(w.tops_m))
    assert result.counts()["walls"] == 1 and result.counts()["metres"] > 190


def test_a_gentle_bank_and_a_low_bank_get_no_wall():
    graph = _graph()
    assert _walls(graph, _terrain(bank_y=ROAD_Y + 0.8)).walls == []  # under min_rise_m
    # 1.2 m up, but climbing only over the two cells from z = -8 to -16: 0.6 m per cell.
    chunks = _terrain(bank_from_z=-16.0, bank_y=ROAD_Y + 1.2)
    chunks[0].heights[chunks[0].heights.shape[0] - 3, :] = ROAD_Y + 0.6  # z = -8
    assert _walls(graph, chunks).walls == []


def test_a_short_bank_is_dropped_and_a_short_gap_is_joined():
    graph = _graph()
    # One cell of bank, 2.2 m up: the rise reads over 1 m at the stations 2 m either side of it
    # and no further, a 4 m stretch, under min_length_m.
    short = _walls(graph, _terrain(x_range=(100.0, 100.0), bank_y=ROAD_Y + 2.2))
    assert short.walls == []
    chunks = _terrain()
    chunks[0].heights[:, int(120 / TERRAIN_RES_M)] = ROAD_Y  # a one-cell dip in the bank
    joined = _walls(graph, chunks)
    assert len(joined.walls) == 1 and joined.walls[0].length_m() == pytest.approx(200.0, abs=2.0)


def test_a_side_street_breaks_the_wall_and_the_junction_is_left_open():
    graph = _graph(side_street=True)
    chunks = _terrain()
    chunk = chunks[0]
    xs = chunk.min_x + np.arange(chunk.heights.shape[1]) * TERRAIN_RES_M
    # The side street's own cutting through the bank, wider than a wall's reach from its edges.
    chunk.heights[:, np.abs(xs - 120.0) <= 16.0] = ROAD_Y
    result = _walls(graph, chunks)
    ids = sorted(w.id for w in result.walls)
    assert ids == ["w:street.0:l0", "w:street.1:l0"]
    for w in result.walls:
        for x, _y, _z in w.points:
            # Clear of the side street's ribbon (3.5 m) and the junction's outline around it.
            assert abs(x - 120.0) > 3.5


def test_a_path_leaving_through_the_wall_line_breaks_it():
    graph = _graph()
    graph.pedestrian.append(
        PedestrianWay(
            "p2",
            [(150.0, ROAD_Y + CURB, -5.0), (150.0, ROAD_Y + 5.0, -30.0)],
            "steps",
            2,
            None,
            "steps",
            1.5,
        )
    )
    result = _walls(graph, _terrain())
    assert len(result.walls) == 2
    for w in result.walls:
        for x, _y, _z in w.points:
            assert abs(x - 150.0) > 0.75


def test_under_a_deck_the_top_stops_at_the_soffit():
    graph = _graph()
    deck = SimpleNamespace(
        points=[(60.0, 54.0, -40.0), (60.0, 54.0, 40.0)], left_m=[10.0, 10.0], right_m=[10.0, 10.0]
    )
    bridges = SimpleNamespace(bridges=[SimpleNamespace(decks=[deck], depth_m=1.0)])
    result = _walls(graph, _terrain(), bridges)
    assert len(result.walls) == 1
    w = result.walls[0]
    under = [t for (x, _y, _z), t in zip(w.points, w.tops_m) if abs(x - 60.0) < 9.0]
    beside = [t for (x, _y, _z), t in zip(w.points, w.tops_m) if abs(x - 60.0) > 12.0]
    assert under and all(t == pytest.approx(53.0 - (ROAD_Y + CURB), abs=0.05) for t in under)
    assert beside and all(t == pytest.approx(6.0 - CURB, abs=0.05) for t in beside)


def test_the_ground_in_front_of_a_wall_is_held_at_the_sidewalks_level():
    graph = _graph()
    chunks = _terrain()
    chunk = chunks[0]
    row_of = lambda z: int((z - chunk.min_z) / TERRAIN_RES_M)
    col = int(120 / TERRAIN_RES_M)
    chunk.heights[row_of(-4.0), col] = ROAD_Y - 0.6  # a pit between the street and the sidewalk
    result = _walls(graph, chunks)
    changed = hold_in_front_of_walls(chunks, graph, result)
    assert changed > 0
    level = ROAD_Y + CURB - ROAD_SURFACE_DROP_M
    assert chunk.heights[row_of(-4.0), col] == pytest.approx(level, abs=1e-3)  # the pit filled
    assert chunk.heights[row_of(-8.0), col] == pytest.approx(level, abs=1e-3)  # one cell behind
    assert chunk.heights[row_of(-12.0), col] == pytest.approx(ROAD_Y + 6.0)  # the bank stays
    assert chunk.heights[row_of(0.0), col] == pytest.approx(ROAD_Y)  # the road's own cells too


def test_the_hold_keeps_off_another_roads_flat_zone_behind_the_wall():
    graph = _graph()
    graph.nodes["u0"] = RoadNode("u0", (20.0, 56.0, -12.0), [5])
    graph.nodes["u1"] = RoadNode("u1", (220.0, 56.0, -12.0), [6])
    graph.edges["upper"] = _edge("upper", "u0", "u1", [(20.0, 56.0, -12.0), (220.0, 56.0, -12.0)])
    chunks = _terrain()
    chunk = chunks[0]
    row = int((-8.0 - chunk.min_z) / TERRAIN_RES_M)
    result = _walls(graph, chunks)
    hold_in_front_of_walls(chunks, graph, result)
    # z = -8 is 4 m from the upper road's centreline: inside its grading zone, so not lowered.
    assert chunk.heights[row, int(120 / TERRAIN_RES_M)] == pytest.approx(56.0)


def test_the_file_validates_and_carries_a_top_per_point(tmp_path: Path):
    graph = _graph()
    result = _walls(graph, _terrain())
    data = result.to_dict()
    Draft202012Validator(json.loads(SCHEMA.read_text(encoding="utf-8"))).validate(data)
    w = data["walls"][0]
    assert len(w["tops_m"]) == len(w["points"]) >= 2
    assert w["height_m"] == max(w["tops_m"])
    assert "kind" not in w  # not a barrier: an older game never reads it


def test_beside_a_bare_road_the_wall_stands_where_the_bank_starts():
    graph = _graph()
    graph.pedestrian = []  # no sidewalk: the outer edge is the road's edge at z = -3.5
    chunks = _terrain(bank_from_z=-12.0)  # flat to z = -8, the bank from z = -12: 6 m from the edge
    result = _walls(graph, chunks)
    assert len(result.walls) == 1
    w = result.walls[0]
    # The climb starts between the z = -8 and z = -12 cells, over 4 m from the edge: past
    # probe_m, so the wall stands at the last flat metre station, not at the road's edge.
    assert all(-8.0 <= z <= -7.0 for _x, _y, z in w.points)
    assert all(y == pytest.approx(ROAD_Y, abs=0.05) for _x, y, _z in w.points)
    assert all(t == pytest.approx(6.0, abs=0.1) for t in w.tops_m)
    chunk = chunks[0]
    col = int(120 / TERRAIN_RES_M)
    hold_in_front_of_walls(chunks, graph, result)
    # Nothing is held behind such a wall: the bank cell stays, the step is at the wall.
    assert chunk.heights[int((-12.0 - chunk.min_z) / TERRAIN_RES_M), col] == pytest.approx(
        ROAD_Y + 6.0
    )
    assert chunk.heights[int((-8.0 - chunk.min_z) / TERRAIN_RES_M), col] == pytest.approx(ROAD_Y)
