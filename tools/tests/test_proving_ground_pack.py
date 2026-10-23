"""The committed proving ground pack: built offline from the committed inputs, byte for byte,
and holding one of every feature the game needs within a short drive of the spawn."""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest

from osm_import import __main__ as importer
from osm_import.png import read_rgb8

REPO = Path(__file__).resolve().parents[2]
PACK = REPO / "packs" / "proving-ground"
REGION = REPO / "regions" / "proving-ground.json"
HEIGHT_STEPS = 2  # terrain heights may differ by this many 16-bit steps across platforms


def _load(name: str) -> dict:
    return json.loads((PACK / name).read_text(encoding="utf-8"))


def test_the_generated_district_is_not_labelled_as_openstreetmap_data():
    manifest = _load("pack.json")
    assert manifest["license"] == "CC-BY-SA-4.0"
    assert not any("OpenStreetMap" in line for line in manifest["attribution"])


def test_committed_pack_matches_a_fresh_import(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """The whole pipeline from the committed inputs, offline, gives the committed pack."""

    def no_network(*_args, **_kwargs):
        raise AssertionError("the proving ground import must not touch the network")

    monkeypatch.setattr(importer, "fetch_query", no_network)
    monkeypatch.setattr(importer, "fetch_bbox", no_network)
    out = tmp_path / "pack"
    argv = ["--region", str(REGION), "--pack-out", str(out), "--pack-version", "0.1.0"]
    assert importer.main(argv) == 0
    fresh = sorted(p.relative_to(out) for p in out.rglob("*") if p.is_file())
    committed = sorted(
        p.relative_to(PACK)
        for p in PACK.rglob("*")
        if p.is_file() and "chunks" not in p.parts and p.name != "build.json"
    )
    assert fresh == committed
    differs = []
    for rel in committed:
        a, b = (out / rel).read_bytes(), (PACK / rel).read_bytes()
        if a == b:
            continue
        if rel.suffix == ".png" and rel.parts[0] == "terrain":
            # Heights come out of float maths that rounds a little differently on x86 Linux
            # (CI) than on arm64 macOS: a step of the 16-bit height (well under a millimetre)
            # is the same terrain. Anything more is a real change.
            ha = read_rgb8(a).astype(np.int32)
            hb = read_rgb8(b).astype(np.int32)
            qa = ha[..., 0] * 256 + ha[..., 1]
            qb = hb[..., 0] * 256 + hb[..., 1]
            if qa.shape == qb.shape and int(np.abs(qa - qb).max()) <= HEIGHT_STEPS:
                continue
        differs.append(str(rel))
    assert not differs, f"{', '.join(differs)} differ; run scripts/regen-proving-ground.sh"


def test_pack_has_one_of_everything():
    graph = _load("road_graph.v0.json")
    edges = graph["edges"]
    classes = {e["class"] for e in edges}
    assert {
        "motorway",
        "motorway_link",
        "secondary",
        "tertiary",
        "residential",
        "parking",
        "service",
    } <= classes
    assert any(e["bus"] == "only" for e in edges), "a bus-only street"
    assert any(e["bus"] == "lane" for e in edges), "a reserved bus lane"
    assert len(graph["bus_stops"]) >= 3
    assert any(e["oneway"] and e["class"] == "residential" for e in edges), "the one-way pair"
    assert any("Circle" in (e["name"] or "") for e in edges), "the roundabout"
    assert any(e["bridge"] and e["class"] == "motorway" for e in edges), "the viaduct"
    assert any(e["bridge"] and e["class"] in ("residential", "tertiary") for e in edges), (
        "a street bridge"
    )
    assert any(e["shoulder_right_m"] > 0 for e in edges if e["class"] == "motorway"), "shoulders"
    controls = {n["control"] for n in graph["nodes"]}
    assert "signals" in controls
    assert any(e["control_from"] == "stop" or e["control_to"] == "stop" for e in edges), (
        "stop signs"
    )
    kinds = {w["kind"] for w in graph["pedestrian_ways"]}
    assert {"sidewalk", "crossing", "cycleway", "steps", "footway"} <= kinds
    assert any(w.get("profile") == "tunnel" for w in graph["pedestrian_ways"]), "the underpass"
    report = _load("validation_report.json")
    assert report["summary"]["components"] == 1
    assert report["summary"]["one_way_traps"] == 0
    assert report["summary"]["ramp_problems"] == 0
    assert report["elevation"]["inferred_bridges"] == []
    assert report["elevation"]["clearance_shortfalls"] == []
    assert report["elevation"]["edges_over_grade"] == []
    dead = report["dead_ends"]
    assert len(dead["bbox_edge"]) == 1 and dead["likely_real"] == [] and dead["suspicious"] == []
    bridges = _load("bridges.v0.json")["bridges"]
    assert {b["kind"] for b in bridges} >= {"over_water"}
    assert max(b["span_m"] for b in bridges) > 1500.0, "the viaduct round the bottom lobe"
    parking = _load("parking.v0.json")
    assert {lot["kind"] for lot in parking["lots"]} >= {"surface", "multi-storey"}
    assert parking["bays"], "kerb parking bays"
    assert parking["garages"], "an underground garage"
    assert any(lot["aisles"] for lot in parking["lots"])
    services = _load("services.v0.json")["places"]
    assert {p["kind"] for p in services} == {
        "police",
        "hospital",
        "fire_station",
        "helipad",
        "ambulance",
    }
    veg = _load("vegetation.v0.json")
    source = veg["columns"].index("source")
    assert {t[source] for t in veg["trees"]} >= {"tagged", "row", "scatter"}
    assert veg["bushes"]
    assert _load("water.v0.json")["polygons"]
    buildings = _load("buildings.v0.json")["buildings"]
    assert {b["kind"] for b in buildings} >= {"house", "apartments", "retail", "office", "hospital"}
    assert any(b["shopfront"] for b in buildings)
    barriers = _load("barriers.v0.json")["barriers"]
    assert any(b["kind"] == "roadblock" for b in barriers), "the edge closure"
    assert any(b["kind"] == "parapet" for b in barriers)
    assert (PACK / "lap.v0.json").exists() and (PACK / "turf.v0.json").exists()


def test_services_are_a_short_drive_from_the_spawn():
    spawn = _load("pack.json")["map"]["spawn"]
    places = _load("services.v0.json")["places"]
    for kind in ("police", "hospital", "fire_station", "helipad", "ambulance"):
        place = next(p for p in places if p["kind"] == kind)
        x, _y, z = place["at"]
        assert math.dist((x, z), (spawn["x"], spawn["z"])) < 600.0, kind


def test_spawn_and_start_line_are_on_the_loop():
    graph = _load("road_graph.v0.json")
    lap = _load("lap.v0.json")["laps"][0]
    spawn = _load("pack.json")["map"]["spawn"]
    loop = [e for e in graph["edges"] if e["name"] in lap["loop_names"]]
    assert loop

    def near_loop(x: float, z: float, within: float) -> bool:
        for e in loop:
            for p in e["polyline"]:
                if math.dist((p[0], p[2]), (x, z)) <= within:
                    return True
        return False

    assert near_loop(spawn["x"], spawn["z"], 25.0)
    assert near_loop(lap["start"]["x"], lap["start"]["z"], 25.0)
    assert spawn["heading_deg"] == 180.0, "the car starts heading south down the vertical"


def test_pack_is_dressed_as_a_town():
    """update-proving-ground-dressing: buildings on every grid and tree rows on the avenues,
    counted on the committed pack."""
    buildings = _load("buildings.v0.json")["buildings"]
    kinds: dict[str, int] = {}
    for b in buildings:
        kinds[b["kind"]] = kinds.get(b["kind"], 0) + 1
    assert len(buildings) >= 2300, len(buildings)
    for kind, need in (
        ("house", 550),
        ("semidetached_house", 350),
        ("terrace", 550),
        ("retail", 150),
        ("apartments", 80),
        ("office", 200),
        ("warehouse", 8),
    ):
        assert kinds.get(kind, 0) >= need, (kind, kinds.get(kind, 0))
    assert sum(1 for b in buildings if b["height_m"] >= 30.0) >= 3, "towers"
    veg = _load("vegetation.v0.json")
    source = veg["columns"].index("source")
    rows = sum(1 for t in veg["trees"] if t[source] == "row")
    tagged = sum(1 for t in veg["trees"] if t[source] == "tagged")
    assert rows >= 600, rows
    assert tagged >= 500, tagged
    graph = _load("road_graph.v0.json")
    driveways = sum(
        1 for e in graph["edges"] if e["class"] == "parking" or e.get("service") == "driveway"
    )
    assert driveways >= 100 or sum(1 for e in graph["edges"] if e["class"] == "service") >= 100


def test_pack_has_the_minor_streets_and_frontage_roads():
    """fix/proving-ground-density: town-sized blocks and roads beside the motorway, counted
    on the committed pack."""
    graph = _load("road_graph.v0.json")
    edges = graph["edges"]
    residential = [e for e in edges if e["class"] == "residential"]
    assert len(residential) >= 400, len(residential)
    names = {e["name"] for e in edges if e["name"]}
    for name in (
        "Viaduct Road North",
        "Viaduct Road South",
        "Viaduct Lane",
        "River Lane",
        "Elm Road",
        "Quay Avenue",
        "Hollow Avenue",
    ):
        assert name in names, name
    report = _load("validation_report.json")
    assert report["dead_ends"]["likely_real"] == []
