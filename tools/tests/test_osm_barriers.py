import json
from pathlib import Path

from jsonschema import Draft202012Validator

from osm_import.barriers import build_barriers
from osm_import.buildings import Building, BuildingsResult
from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, apply_elevation
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()
SCHEMA = Path(__file__).parents[2] / "docs" / "pack-format" / "barriers.schema.v0.json"


def graph_for(ways, source):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    apply_elevation(g, source, CFG)
    return g


def kinds(result):
    return sorted(b.kind for b in result.barriers)


def test_bridge_gets_two_parapets():
    g = graph_for(
        [
            (
                1,
                [(-200, 0), (200, 0)],
                {"highway": "primary", "bridge": "yes", "layer": "1", "width": "12"},
            )
        ],
        FlatSource(10.0),
    )
    r = build_barriers(g, FlatSource(10.0), None, CFG)
    assert kinds(r) == ["parapet", "parapet"]
    road_z = g.edges["w1.0"].polyline[0][2]
    offsets = sorted(b.points[0][2] - road_z for b in r.barriers)
    assert abs(offsets[0] + 5.75) < 0.3 and abs(offsets[1] - 5.75) < 0.3


def test_close_opposing_carriageways_get_one_median():
    ways = [
        (1, [(-300, 0), (300, 0)], {"highway": "motorway", "oneway": "yes", "width": "10"}),
        (
            2,
            [(300, 13), (-300, 13)],
            {"highway": "motorway", "oneway": "yes", "width": "10"},
        ),  # gap 3 m
    ]
    g = graph_for(ways, FlatSource(10.0))
    r = build_barriers(g, FlatSource(10.0), None, CFG)
    medians = [b for b in r.barriers if b.kind == "median"]
    assert len(medians) == 1

    def z_on(edge_id, x):
        pl = g.edges[edge_id].polyline
        a, b = (pl[0], pl[-1]) if pl[0][0] < pl[-1][0] else (pl[-1], pl[0])
        t = (x - a[0]) / (b[0] - a[0])
        return a[2] + (b[2] - a[2]) * t

    for x, _y, z in medians[0].points:
        lo = min(z_on("w1.0", x), z_on("w2.0", x)) + 5.0
        hi = max(z_on("w1.0", x), z_on("w2.0", x)) - 5.0
        assert lo - 0.6 <= z <= hi + 0.6  # inside the 3 m gap between the 10 m ribbons


def test_far_apart_carriageways_get_no_median():
    ways = [
        (1, [(-300, 0), (300, 0)], {"highway": "motorway", "oneway": "yes", "width": "10"}),
        (2, [(300, 40), (-300, 40)], {"highway": "motorway", "oneway": "yes", "width": "10"}),
    ]
    g = graph_for(ways, FlatSource(10.0))
    r = build_barriers(g, FlatSource(10.0), None, CFG)
    assert "median" not in kinds(r)


def test_embankment_gets_guardrails():
    class Embankment:
        def sample(self, x, z):
            return 20.0 if abs(z) < 7 else 15.0  # road on a 5 m ridge

        def describe(self):
            return {"kind": "emb"}

    g = graph_for(
        [(1, [(-300, 0), (300, 0)], {"highway": "motorway", "oneway": "yes", "width": "10"})],
        Embankment(),
    )
    r = build_barriers(g, Embankment(), None, CFG)
    assert kinds(r) == ["guardrail", "guardrail"]


def test_houses_beside_highway_get_a_sound_wall_on_that_side():
    houses = BuildingsResult(
        [
            Building(
                f"w{i}.0",
                "house",
                None,
                6.0,
                10.0,
                [[(x, 25.0), (x + 8, 25.0), (x + 8, 33.0), (x, 33.0)]],
                [(x, 25.0), (x + 8, 25.0), (x + 8, 33.0), (x, 33.0)],
                [0, 1, 2, 0, 2, 3],
                i,
                "default",
            )
            for i, x in enumerate(range(-200, 200, 20))
        ]
    )
    g = graph_for(
        [(1, [(-300, 0), (300, 0)], {"highway": "motorway", "oneway": "yes", "width": "10"})],
        FlatSource(10.0),
    )
    r = build_barriers(g, FlatSource(10.0), houses, CFG)
    walls = [b for b in r.barriers if b.kind == "soundwall"]
    assert len(walls) == 1
    assert all(p[2] > 0 for p in walls[0].points)  # on the housing (+z) side only
    assert walls[0].height_m == 4.0


def test_output_validates_and_is_deterministic():
    g = graph_for(
        [
            (
                1,
                [(-200, 0), (200, 0)],
                {"highway": "motorway", "oneway": "yes", "bridge": "yes", "layer": "1"},
            )
        ],
        FlatSource(5.0),
    )
    a = build_barriers(g, FlatSource(5.0), None, CFG).to_dict()
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    assert list(Draft202012Validator(schema).iter_errors(a)) == []
    assert build_barriers(g, FlatSource(5.0), None, CFG).to_dict() == a


def test_street_with_sidewalk_gets_a_curb_on_that_side():
    from osm_import.graph import PedestrianWay

    g = graph_for(
        [(1, [(-200, 0), (200, 0)], {"highway": "residential", "width": "8"})], FlatSource(10.0)
    )
    sw = PedestrianWay(
        "p1", [(-200.0, 10.12, 6.0), (200.0, 10.12, 6.0)], "footway", 1, None, "sidewalk", 2.0
    )
    g.pedestrian.append(sw)
    r = build_barriers(g, FlatSource(10.0), None, CFG)
    curbs = [b for b in r.barriers if b.kind == "curb"]
    assert len(curbs) == 1
    assert all(p[2] > 0 for p in curbs[0].points)  # only on the sidewalk side
    assert curbs[0].height_m == 0.12


def test_bridge_parapet_moves_outside_a_walkway_and_leaves_a_curb():
    from osm_import.graph import PedestrianWay

    g = graph_for(
        [
            (
                1,
                [(-200, 0), (200, 0)],
                {"highway": "primary", "bridge": "yes", "layer": "1", "width": "12"},
            )
        ],
        FlatSource(10.0),
    )
    road = g.edges["w1.0"].polyline
    # A 3 m sidewalk whose centre runs 8 m off the deck centreline on the +z side.
    sw = PedestrianWay(
        "p1", [(p[0], p[1] + 0.12, p[2] + 8.0) for p in road], "footway", 1, None, "sidewalk", 3.0
    )
    g.pedestrian.append(sw)
    r = build_barriers(g, FlatSource(10.0), None, CFG)
    assert kinds(r) == ["curb", "parapet", "parapet"]
    road_z = road[0][2]
    parapets = sorted(b.points[0][2] - road_z for b in r.barriers if b.kind == "parapet")
    assert abs(parapets[0] + 5.75) < 0.3  # plain deck edge on the -z side
    assert abs(parapets[1] - 9.25) < 0.3  # sidewalk outer edge (8 + 1.5) minus the inset
    curb = next(b for b in r.barriers if b.kind == "curb")
    assert abs(curb.points[0][2] - road_z - 6.0) < 0.3  # road edge on the walkway side


def test_ramp_walls_stay_out_of_the_highway_ribbon():
    # A bridge ramp peels off a bridge highway at a mid node: its parapet must not start
    # inside the highway's 14 m carriageway.
    g = graph_for(
        [
            (
                1,
                [(-300, 0), (0, 0), (300, 0)],
                {
                    "highway": "motorway",
                    "oneway": "yes",
                    "bridge": "yes",
                    "layer": "1",
                    "width": "14",
                },
            ),
            (
                2,
                [(0, 0), (120, 25), (240, 60)],
                {
                    "highway": "motorway_link",
                    "oneway": "yes",
                    "bridge": "yes",
                    "layer": "1",
                    "width": "5",
                },
            ),
        ],
        FlatSource(10.0),
    )
    r = build_barriers(g, FlatSource(10.0), None, CFG)
    hw_segments = [
        (e.polyline[i], e.polyline[i + 1])
        for e in g.edges.values()
        if e.osm_way_id == 1
        for i in range(len(e.polyline) - 1)
    ]
    from osm_import.elevation import _seg_dist

    ramp_walls = [b for b in r.barriers if b.edge_id.startswith("w2.")]
    assert ramp_walls, "the ramp still gets walls where it is clear"
    for b in ramp_walls:
        for x, _y, z in b.points:
            d = min(_seg_dist(x, z, a[0], a[2], c[0], c[2]) for a, c in hw_segments)
            assert d >= 7.0 - 0.2 - 0.01, (
                f"wall point {x:.1f},{z:.1f} is {d:.1f} m from the highway centreline"
            )


def test_deck_over_a_road_keeps_its_parapet_and_walls_meet_at_edge_splits():
    # Two bridge ways meeting at (0, 0) cross 6 m above a street that shares no node with them:
    # the street is "inside" in 2D but not at the same level, so the parapets stay, and the
    # runs of the two deck edges meet exactly at the split.
    bridge = {"highway": "primary", "bridge": "yes", "layer": "1", "width": "12"}
    g = graph_for(
        [
            (1, [(-200, 0), (0, 0)], bridge),
            (3, [(0, 0), (200, 0)], bridge),
            (2, [(0, -200), (0, 200)], {"highway": "residential", "width": "8"}),
        ],
        FlatSource(10.0),
    )
    r = build_barriers(g, FlatSource(10.0), None, CFG)
    parapets = [b for b in r.barriers if b.kind == "parapet"]
    assert sorted(b.edge_id for b in parapets) == ["w1.0", "w1.0", "w3.0", "w3.0"]
    for b in parapets:
        assert abs(b.points[0][1] - b.points[-1][1]) < 0.5  # a flat deck: same height along the run
    node = g.nodes[g.edges["w1.0"].to_node].position
    for side in (-1.0, 1.0):
        runs = [b for b in parapets if (b.points[0][2] - node[2]) * side > 0]
        assert len(runs) == 2, side
        end_of_first = next(b for b in runs if b.edge_id == "w1.0").points[-1]
        start_of_second = next(b for b in runs if b.edge_id == "w3.0").points[0]
        assert abs(end_of_first[0] - start_of_second[0]) < 0.05
        assert abs(end_of_first[2] - start_of_second[2]) < 0.05
