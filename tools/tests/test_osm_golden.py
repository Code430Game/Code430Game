"""Golden-file, determinism, and schema tests on the committed Metcalfe / 417 fixture."""

import json
from pathlib import Path

from jsonschema import Draft202012Validator

from osm_import.config import load_config
from osm_import.osm_data import BBox, OsmData
from osm_import.pipeline import run_pipeline, write_outputs

HERE = Path(__file__).parent
REPO = HERE.parents[1]
FIXTURE = HERE / "fixtures" / "metcalfe_417.osm.json"
FIXTURE_BBOX = BBox(45.4095, -75.6900, 45.4145, -75.6830)
GOLDEN_GRAPH = HERE / "golden" / "metcalfe_417.road_graph.v0.json"
GOLDEN_REPORT = HERE / "golden" / "metcalfe_417.validation_report.json"
SCHEMA = REPO / "docs" / "pack-format" / "road_graph.schema.v0.json"


def run():
    data = OsmData.load(FIXTURE)
    data.source["path"] = "tests/fixtures/metcalfe_417.osm.json"  # stable regardless of cwd
    return run_pipeline(data, FIXTURE_BBOX, load_config())


def test_fixture_credits_osm():
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert payload["code430_source"]["attribution"] == "© OpenStreetMap contributors"
    assert payload["code430_source"]["license"] == "ODbL-1.0"


def test_graph_matches_golden():
    result = run()
    assert result.graph_dict == json.loads(GOLDEN_GRAPH.read_text(encoding="utf-8"))


def test_report_matches_golden():
    result = run()
    assert result.report.to_dict() == json.loads(GOLDEN_REPORT.read_text(encoding="utf-8"))


def test_two_runs_are_byte_identical(tmp_path: Path):
    a = write_outputs(run(), tmp_path / "a", "t")
    b = write_outputs(run(), tmp_path / "b", "t")
    for key in a:
        assert a[key].read_bytes() == b[key].read_bytes(), key


def test_output_validates_against_schema():
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    errors = list(Draft202012Validator(schema).iter_errors(run().graph_dict))
    assert errors == []


def test_oneway_preserved_from_osm():
    result = run()
    data = OsmData.load(FIXTURE)
    checked = 0
    for e in result.graph.edges.values():
        tag = data.ways[e.osm_way_id].tags.get("oneway")
        if tag == "yes":
            assert e.oneway is True
            checked += 1
        elif tag == "no":
            assert e.oneway is False
    assert checked > 10


def test_every_edge_references_its_osm_way():
    result = run()
    data = OsmData.load(FIXTURE)
    for e in result.graph.edges.values():
        assert e.osm_way_id in data.ways
        assert e.id.startswith(f"w{e.osm_way_id}.")


def test_motorway_never_meets_local_streets_directly():
    """Highway 417 only connects to motorway and link edges; it passes over streets."""
    result = run()
    inc = result.graph.incident()
    for e in result.graph.edges.values():
        if e.road_class != "motorway":
            continue
        for nid in (e.from_node, e.to_node):
            classes = {result.graph.edges[x].road_class for x in inc[nid]}
            assert classes <= {"motorway", "motorway_link"}, (e.id, classes)


def test_fixture_covers_the_interesting_cases():
    s = run().report.summary
    assert s["classes"]["motorway"] > 0 and s["classes"]["motorway_link"] > 0
    assert s["components"] == 1 and s["ramp_problems"] == 0 and s["one_way_traps"] == 0
    assert result_has_bridge(run())


def result_has_bridge(result) -> bool:
    return any(e.bridge and e.layer == 1 for e in result.graph.edges.values())
