"""The Double Cross proving ground generator: deterministic, one of every feature in the
emitted data, the four ways on and off the loop, and ways that cross at grade share a node."""

from __future__ import annotations

import json
from pathlib import Path

from proving_ground import emit
from proving_ground.layout import build

REPO = Path(__file__).resolve().parents[2]
REGION = REPO / "regions" / "proving-ground.json"
INPUTS = REPO / "regions" / "proving-ground"

# Every feature the district must contain, by the generator's own count.
EMITTED_FEATURES = (
    "signals",
    "stops",
    "bus_stops",
    "bus_lanes",
    "bus_only",
    "oneway_streets",
    "motorway_links",
    "motorway",
    "bridges",
    "footbridges",
    "tunnels",
    "sidewalks",
    "crossings",
    "cycleways",
    "steps",
    "roundabouts",
    "driveways",
    "parking_aisles",
    "kerb_parking",
    "rail",
    "stations",
    "parking_entrances",
    "houses",
    "apartments",
    "shops",
    "offices",
    "surface_lots",
    "garages",
    "police",
    "hospital",
    "fire_station",
    "helipad",
    "ambulance",
    "water",
    "parks",
    "woods",
    "grass",
    "trees",
    "tree_rows",
)


def test_generator_is_deterministic():
    a = emit.osm_payload(build())
    b = emit.osm_payload(build())
    assert json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)
    assert json.dumps(emit.vegetation_payload(build())) == json.dumps(
        emit.vegetation_payload(build())
    )


def test_emitted_data_has_one_of_everything():
    counts = emit.feature_counts(build())
    missing = [f for f in EMITTED_FEATURES if counts.get(f, 0) < 1]
    assert missing == [], f"features absent from the generated district: {missing}"
    assert counts["access_points"] == 4, "four ways on and off the loop, one per quarter"
    assert counts["turf_corners"] == 4


def test_motorway_links_come_in_pairs_per_quarter():
    d = build()
    names = sorted(w.tags["name"] for w in d.ways if w.tags.get("highway") == "motorway_link")
    assert names == sorted(
        ["City Entrance", "City Exit", "East Entrance", "East Exit", "West Entrance", "West Exit"]
    )


def test_ways_that_cross_at_grade_share_a_node():
    """The stitch pass: any two same-level ways whose segments cross have the crossing as a
    vertex of both, and nothing meets the motorway at grade except its own links."""
    d = build()
    points = {w.id: set(w.points) for w in d.ways}
    motorway = {w.id for w in d.ways if w.tags.get("highway") in ("motorway", "motorway_link")}
    for w1 in d.ways:
        for w2 in d.ways:
            if w2.id <= w1.id:
                continue
            same_level = w1.tags.get("layer", "0") == w2.tags.get("layer", "0") and (
                (w1.tags.get("bridge") == "yes") == (w2.tags.get("bridge") == "yes")
            )
            if not same_level or ((w1.id in motorway) != (w2.id in motorway)):
                continue
            for a, b in zip(w1.points, w1.points[1:], strict=False):
                for c, e in zip(w2.points, w2.points[1:], strict=False):
                    hit = _proper_crossing(a, b, c, e)
                    if hit is not None:
                        assert hit in points[w1.id] and hit in points[w2.id], (
                            w1.tags.get("name"),
                            w2.tags.get("name"),
                            hit,
                        )


def _proper_crossing(a, b, c, e):
    r = (b[0] - a[0], b[1] - a[1])
    q = (e[0] - c[0], e[1] - c[1])
    denom = r[0] * q[1] - r[1] * q[0]
    if abs(denom) < 1e-9:
        return None
    w = (c[0] - a[0], c[1] - a[1])
    t = (w[0] * q[1] - w[1] * q[0]) / denom
    u = (w[0] * r[1] - w[1] * r[0]) / denom
    if 1e-3 < t < 1 - 1e-3 and 1e-3 < u < 1 - 1e-3:
        return (round(a[0] + r[0] * t, 3), round(a[1] + r[1] * t, 3))
    return None


def test_committed_inputs_match_the_generator(tmp_path: Path):
    """What is committed under regions/ is exactly what the generator writes today."""
    out = tmp_path / "proving-ground"
    emit.write_all(build(), out, tmp_path / "proving-ground.json")
    for path in sorted(INPUTS.glob("*.json")):
        fresh = (out / path.name).read_text(encoding="utf-8")
        assert fresh == path.read_text(encoding="utf-8"), (
            f"{path.name} is stale; run scripts/regen-proving-ground.sh"
        )
    assert (tmp_path / "proving-ground.json").read_text(encoding="utf-8") == REGION.read_text(
        encoding="utf-8"
    )
