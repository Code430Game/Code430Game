from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.filter import filter_ways
from osm_import.graph import build_graph
from osm_import.projection import Projector
from osm_import.validation import render_markdown, validate
from tests.osm_helpers import BBOX, make_data

CFG = load_config()


def run(ways, node_tags=None):
    data = make_data(ways, node_tags)
    fr = filter_ways(data, CFG)
    proj = Projector.for_bbox(BBOX)
    g = build_graph(data, fr.drivable, fr.pedestrian, proj, CFG)
    cluster_junctions(g, CFG)
    return validate(g, CFG, proj.bbox_local(BBOX), fr.dropped_by_node())


GRID = [
    (1, [(-300, 0), (0, 0), (300, 0)], {"highway": "secondary", "name": "Main"}),
    (2, [(0, -300), (0, 0), (0, 300)], {"highway": "secondary", "name": "Cross"}),
]


def test_clean_grid_has_no_findings():
    r = run(GRID)
    assert r.summary["components"] == 1
    assert r.ramps == [] and r.traps == []
    assert r.summary["dead_ends"] == {
        "bbox_edge": 0,
        "declared_noexit": 0,
        "likely_real": 0,
        "suspicious": 4,
        "parking": 0,
    }


def test_dead_end_categories():
    ways = GRID + [
        (3, [(0, 0), (50, 50)], {"highway": "residential", "name": "Cul de sac"}),
        (4, [(0, 0), (-50, 50), (-440, 50)], {"highway": "tertiary", "name": "To the edge"}),
        (5, [(0, 0), (60, -60)], {"highway": "tertiary", "name": "Declared"}),
    ]
    r = run(ways, node_tags={1008: {"noexit": "yes"}})  # node at (60,-60)
    cats = {cat: [d.name for d in entries] for cat, entries in r.dead_ends.items()}
    assert cats["likely_real"] == ["Cul de sac"]
    assert cats["bbox_edge"] == ["To the edge"]
    assert cats["declared_noexit"] == ["Declared"]
    assert sorted(cats["suspicious"]) == ["Cross", "Cross", "Main", "Main"]


def test_one_way_trap_detected():
    ways = GRID + [
        (3, [(0, 0), (100, 100)], {"highway": "residential", "oneway": "yes", "name": "In"}),
        (
            4,
            [(100, 100), (150, 100), (150, 150), (100, 150), (100, 100)],
            {"highway": "residential", "oneway": "yes", "name": "Loop"},
        ),
    ]
    r = run(ways)
    assert len(r.traps) == 1
    assert r.traps[0].kind == "trap_can_enter_not_leave"
    assert "Loop" in r.traps[0].sample_names


def test_one_way_stub_is_not_a_trap():
    ways = GRID + [(3, [(0, 0), (100, 100)], {"highway": "service", "oneway": "yes"})]
    r = run(ways)
    assert r.traps == []
    assert r.summary["oneway_dead_ends"] == 1


def test_ramp_leading_nowhere_reported():
    ways = [
        (1, [(-300, 0), (0, 0), (300, 0)], {"highway": "motorway", "name": "417"}),
        (2, [(0, 0), (100, 50), (200, 60)], {"highway": "motorway_link", "oneway": "yes"}),
    ]
    r = run(ways)
    assert len(r.ramps) == 1
    assert r.ramps[0].osm_way_ids == [2]
    assert "fewer than two points" in r.ramps[0].problem


def test_ramp_connecting_motorway_to_street_is_fine():
    ways = [
        (1, [(-300, 0), (0, 0), (300, 0)], {"highway": "motorway", "name": "417"}),
        (2, [(0, 0), (100, 50), (200, 100)], {"highway": "motorway_link", "oneway": "yes"}),
        (3, [(-300, 100), (200, 100), (300, 100)], {"highway": "secondary", "name": "Street"}),
    ]
    r = run(ways)
    assert r.ramps == []


def test_island_explained_by_filtered_connector():
    ways = GRID + [
        (3, [(0, 0), (80, 80)], {"highway": "service", "service": "emergency_access"}),
        (4, [(80, 80), (120, 80), (120, 120)], {"highway": "service", "name": "Lot road"}),
    ]
    r = run(ways)
    assert r.summary["components"] == 2
    assert r.components[1].likely_cause == "connector filtered out (service=emergency_access)"
    md = render_markdown(r, "test")
    assert "connector filtered out (service=emergency_access)" in md


def test_a_driveway_now_joins_its_lot_road_to_the_streets():
    ways = GRID + [
        (3, [(0, 0), (80, 80)], {"highway": "service", "service": "driveway"}),
        (4, [(80, 80), (120, 80), (120, 120)], {"highway": "service", "name": "Lot road"}),
    ]
    assert run(ways).summary["components"] == 1


def test_region_file_supplies_bbox_and_pack_id(tmp_path, monkeypatch):
    import json

    from osm_import.__main__ import main

    region = tmp_path / "r.json"
    region.write_text(
        json.dumps(
            {
                "name": "demo",
                "bbox": [45.405, -75.715, 45.435, -75.675],
                "pack_id": "code430.demo",
                "dem": "flat",
            }
        )
    )
    captured = {}

    def fake_import(args):
        captured.update(vars(args))
        return 0

    monkeypatch.setattr("osm_import.__main__._import", fake_import)
    assert main(["--region", str(region), "--out", str(tmp_path / "out")]) == 0
    # The region is resolved inside _import; here we check the parser accepted it without --bbox.
    assert captured["region"] == region and captured["bbox"] is None


def test_parking_dead_ends_are_counted_apart_from_streets():
    ways = GRID + [
        (6, [(0, 0), (40, -40)], {"highway": "service", "service": "parking_aisle"}),
        (7, [(0, 0), (-30, -30)], {"highway": "service", "service": "driveway"}),
    ]
    r = run(ways)
    assert len(r.dead_ends["parking"]) == 2
    assert len(r.dead_ends["suspicious"]) == 4  # the four real street ends, unchanged
