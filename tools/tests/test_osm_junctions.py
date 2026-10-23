"""Junction surfaces in the importer (update-junction-ground): the outline port matches the
game's, and the terrain under a junction follows the surface instead of one arm."""

import hashlib
import json
import math
from pathlib import Path

import numpy as np
import pytest

from osm_import import junctions as J
from osm_import.elevation import FlatSource
from osm_import.graph import RoadEdge, RoadGraph, RoadNode
from osm_import.pack import (
    FLAT_MARGIN_M,
    ROAD_SURFACE_DROP_M,
    TERRAIN_RES_M,
    ChunkSampler,
    _road_footprints,
    flatten_roads,
    ground_junctions,
    sample_chunk,
)

ROOT = Path(__file__).resolve().parents[2]
PROVING_GROUND = ROOT / "packs" / "proving-ground" / "road_graph.v0.json"
FIXTURE = Path(__file__).with_name("fixtures") / "proving_ground_junctions.json"


def graph_from_pack(path: Path) -> RoadGraph:
    """The road graph as the game reads it (rounded, sorted ids), from a pack's JSON."""
    d = json.loads(path.read_text(encoding="utf-8"))
    nodes = {
        n["id"]: RoadNode(
            n["id"],
            tuple(n["position"]),
            n.get("osm_node_ids", []),
            junction_type=n.get("junction_type", "junction"),
            ground_y=n.get("ground_y", 0.0),
        )
        for n in d["nodes"]
    }
    edges = {
        e["id"]: RoadEdge(
            e["id"],
            e["from"],
            e["to"],
            [tuple(p) for p in e["polyline"]],
            e["class"],
            e["lanes_forward"],
            e["lanes_backward"],
            e["oneway"],
            e["speed_kph"],
            e["width_m"],
            e["layer"],
            e["bridge"],
            e["tunnel"],
            e.get("name"),
            e["osm_way_id"],
            [],
            length_m=e.get("length_m", 0.0),
        )
        for e in d["edges"]
    }
    return RoadGraph(nodes, edges, [])


def _hausdorff(a: list, b: list) -> float:
    """How far any vertex of one outline is from the other outline's boundary, both ways."""

    def to_boundary(p, poly):
        best = math.inf
        for i in range(len(poly)):
            q = J.closest_point_to_segment(
                tuple(p), tuple(poly[i]), tuple(poly[(i + 1) % len(poly)])
            )
            best = min(best, math.dist(p, q))
        return best

    return max(max(to_boundary(p, b) for p in a), max(to_boundary(p, a) for p in b))


def test_the_outline_port_matches_the_games_on_the_proving_ground():
    """tools/tests/fixtures/proving_ground_junctions.json is the game's JunctionBuilder output
    (game/world/build/junction_outline_dump.gd); regenerate it when the proving ground's road
    graph changes. Godot computes in single precision, so a corner that sits on a knife edge
    (two side lines meeting within a millimetre of the node) may be drawn differently: those
    few must still outline the same shape within 5 cm."""
    game = json.loads(FIXTURE.read_text(encoding="utf-8"))
    game.pop("_road_graph_sha256", None)
    ours = J.build_all(graph_from_pack(PROVING_GROUND))
    assert set(game) == set(ours)
    assert len(ours) > 300
    exact = 0
    for nid, g in game.items():
        o = ours[nid]
        assert g["hull"] == o.fallback_hull, nid
        if len(g["polygon"]) == len(o.polygon):
            plan = max(math.dist(a, b) for a, b in zip(g["polygon"], o.polygon))
            height = max(abs(a - b) for a, b in zip(g["heights"], o.heights))
            if plan < 0.01 and height < 0.01:
                exact += 1
                continue
        assert _hausdorff(g["polygon"], o.polygon) < 0.05, nid
        assert abs(max(g["heights"]) - max(o.heights)) < 0.05, nid
        assert abs(min(g["heights"]) - min(o.heights)) < 0.05, nid
    assert exact >= 0.95 * len(game), f"{exact} of {len(game)} outlines match exactly"


def test_the_fixture_is_for_the_committed_proving_ground():
    """The dump records the road graph it was made from; a stale fixture would pass for the
    wrong reasons."""
    game = json.loads(FIXTURE.read_text(encoding="utf-8"))
    digest = hashlib.sha256(PROVING_GROUND.read_bytes()).hexdigest()
    assert game.get("_road_graph_sha256", digest) == digest, (
        "regenerate tests/fixtures/proving_ground_junctions.json with junction_outline_dump.gd"
    )


def _edge(eid, a, b, pts, width=7.0, bridge=False, tunnel=False):
    return RoadEdge(
        eid, a, b, pts, "residential", 1, 1, False, 40, width, 0, bridge, tunnel, eid, 1, []
    )


def _tee(east_y: float, bridge_arm: bool = False) -> RoadGraph:
    """A T at (100, 100): a level east-west street at 50 m, and a north arm climbing to
    `east_y`... no: the east arm climbs to `east_y` over 100 m while west and north stay level,
    so the corners between east and north, and east and west, sit between two heights."""
    c = (100.0, 50.0, 100.0)
    nodes = {"c": RoadNode("c", c, [1])}
    edges = {}
    for name, (x, y, z) in {
        "e": (200.0, east_y, 100.0),
        "w": (0.0, 50.0, 100.0),
        "n": (100.0, 50.0, 0.0),
    }.items():
        nodes[name] = RoadNode(name, (x, y, z), [2])
        edges[name] = _edge(name, "c", name, [c, (x, y, z)], bridge=bridge_arm and name == "e")
    return RoadGraph(nodes, edges, [])


def test_junctions_on_the_ground_are_flattened_and_those_with_a_bridge_arm_are_not():
    assert [j.node_id for j in ground_junctions(_tee(55.0))] == ["c"]
    assert ground_junctions(_tee(55.0, bridge_arm=True)) == []
    assert ground_junctions(RoadGraph({}, {}, [])) == []


def test_the_ground_under_a_junction_follows_its_surface_not_one_arm():
    """The east arm climbs 5 m per 100 m: at the corner between it and the north arm the
    surface is between the two arms' heights. The terrain there must sit just under the
    surface (no grass through it) and not 25 cm or more below it (no wheel trap at either
    arm's edge)."""
    graph = _tee(55.0)
    ground, _bridges = _road_footprints(graph, include_pedestrian=False)
    junctions = ground_junctions(graph)
    chunk = sample_chunk(FlatSource(40.0), 0, 0)
    flatten_roads(chunk, ground, junctions)
    sample = ChunkSampler([chunk]).sample
    j = junctions[0]
    n = len(j.polygon)
    for i, (vx, vz) in enumerate(j.polygon):
        for f in (0.6, 0.85):  # where JunctionReport.terrain_above samples
            x = j.centre[0] + (vx - j.centre[0]) * f
            z = j.centre[2] + (vz - j.centre[2]) * f
            y = j.centre[1] + (j.heights[i] - j.centre[1]) * f
            assert sample(x, z) <= y + 0.05, (i, f)
        # Just outside each outline vertex the ground is level with the surface there.
        nxt = j.polygon[(i + 1) % n]
        prev = j.polygon[(i - 1) % n]
        out_dir = (vx - j.centre[0], vz - j.centre[2])
        length = math.hypot(*out_dir)
        px = vx + out_dir[0] / length * 0.8
        pz = vz + out_dir[1] / length * 0.8
        assert abs(sample(px, pz) - (j.heights[i] - ROAD_SURFACE_DROP_M)) < 0.25, (i, nxt, prev)


def test_a_junction_owns_its_ground_ahead_of_a_lower_path_beside_it():
    from osm_import.pack import PEDESTRIAN

    graph = _tee(50.0)
    ground, _bridges = _road_footprints(graph, include_pedestrian=False)
    # A sidewalk 1 m lower along the junction's south side, 3 m out from the outline (the
    # outline's south edge is at z = 103.5): the cell at z = 104 is in the junction's margin,
    # not under the sidewalk, so the junction keeps it level; the cell under the sidewalk
    # (z = 108) is the sidewalk's.
    ground.append((60.0, 108.0, 160.0, 108.0, 49.0, 49.0, 1.0, FLAT_MARGIN_M, 3.0, PEDESTRIAN))
    chunk = sample_chunk(FlatSource(40.0), 0, 0)
    flatten_roads(chunk, ground, ground_junctions(graph))
    c = int(104 / TERRAIN_RES_M)
    assert chunk.heights[int(104 / TERRAIN_RES_M), c] == pytest.approx(
        50.0 - ROAD_SURFACE_DROP_M, abs=0.02
    )
    assert chunk.heights[int(108 / TERRAIN_RES_M), c] == pytest.approx(
        49.0 - ROAD_SURFACE_DROP_M, abs=0.02
    )
    assert np.isfinite(chunk.heights).all()
