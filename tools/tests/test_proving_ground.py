"""The Double Cross proving ground generator: deterministic, one of every feature in the
emitted data, the four ways on and off the loop, and ways that cross at grade share a node."""

from __future__ import annotations

import json
import math
from itertools import pairwise
from pathlib import Path

from proving_ground import dressing, emit, layout
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


# ------------------------------------------------ dressing (update-proving-ground-dressing)

# Minimum counts the dressed district must reach, by the generator's own tags.
DRESSING_MINIMUMS = {
    "house": 550,
    "semidetached_house": 350,
    "terrace": 550,
    "retail": 150,
    "apartments": 80,
    "office": 200,
    "warehouse": 8,
}


def _building_counts(d: layout.District) -> dict[str, int]:
    counts: dict[str, int] = {}
    for a in d.buildings:
        kind = a.tags.get("building", "yes")
        counts[kind] = counts.get(kind, 0) + 1
    return counts


def test_dressing_puts_buildings_on_every_grid():
    d = build()
    counts = _building_counts(d)
    short = {
        k: counts.get(k, 0) for k, need in DRESSING_MINIMUMS.items() if counts.get(k, 0) < need
    }
    assert short == {}, f"below the dressing minimums: {short}"
    roundabout = (layout.A_WEST, layout.MAIN_AVENUES[1])
    towers = []
    for a in d.buildings:
        if int(a.tags.get("building:levels", "0")) < 10:
            continue
        cx = sum(p[0] for p in a.ring) / len(a.ring)
        cz = sum(p[1] for p in a.ring) / len(a.ring)
        if math.dist((cx, cz), roundabout) < dressing.TOWER_RADIUS_M + 20.0:
            towers.append(a)
    assert 3 <= len(towers) <= dressing.TOWER_COUNT, "a few towers near the roundabout"
    yard = [t for t in d.trees if t.tags.get("denotation") == "garden"]
    assert len(yard) >= 400, "a yard tree behind the detached houses"
    assert len(d.tree_rows) >= 20, "tree rows on the avenues and the bank road"
    assert sum(1 for w in d.ways if w.tags.get("service") == "driveway") >= 200


def test_dressing_keeps_off_roads_banks_greenbelt_park_and_turf():
    """Every dressed footprint clears the roads, the river band, the greenbelt, the park and
    the turf, judged by the same geometry the pass used, rebuilt from the streets alone."""
    d = build()
    streets = layout.District()
    streets.ways = [w for w in d.ways if w.tags.get("service") != "driveway"]
    streets.vegetation_areas = d.vegetation_areas
    streets.turf = d.turf
    ex = dressing._Exclusions(streets)
    placed = [
        a
        for a in d.buildings
        if a.tags.get("addr:housenumber", "0").isdigit()
        and int(a.tags.get("addr:housenumber", "0")) >= 200
    ]
    assert len(placed) > 1500
    for a in placed:
        x0, z0, x1, z1 = dressing._bbox(a.ring)
        assert not ex.rejects(dressing.Lot(x0, z0, x1, z1), None), a.tags


def test_town_name_is_a_parameter():
    d = build("Lintport")
    names = {a.tags.get("name", "") for a in d.service_areas}
    assert "Lintport Police" in names and "Lintport General" in names
    assert any(t.get("name") == "Lintport Station" for _, t in d.node_tags)
    d = build()
    assert any(t.get("name") == "Double Cross Station" for _, t in d.node_tags)


# ------------------------------------------------ density (fix/proving-ground-density)


def _gaps(values) -> list[float]:
    ordered = sorted(values)
    return [b - a for a, b in pairwise(ordered)]


def test_blocks_are_town_sized():
    """Streets and avenues in every grid are at most about 100 m apart, except where a service,
    the park or the turf keeps its larger block (the human: "a lot of open space in the grid")."""
    main_x = [*layout.MAIN_STREETS, *layout.MAIN_MINOR_STREETS, layout.A_WEST, 0.0]
    main_z = [layout.BANK_Z, *layout.MAIN_AVENUES, *layout.MAIN_MINOR_AVENUES, layout.A_NORTH]
    city_x = [*layout.CITY_STREETS, *layout.CITY_MINOR_STREETS]
    city_z = [*layout.CITY_AVENUES, *layout.CITY_MINOR_AVENUES]
    south_x = [*layout.SOUTH_STREETS, *layout.SOUTH_MINOR_STREETS, layout.VIADUCT_LANE_X]
    south_z = [*layout.SOUTH_AVENUES, *layout.SOUTH_MINOR_AVENUES, *layout.VIADUCT_FRONTAGE_Z]
    for name, values, limit in (
        ("main streets", main_x, 160.0),  # the police and garage block stays 150 m wide
        ("main avenues", main_z, 120.0),  # the hospital and garage strip
        ("city streets", city_x, 110.0),
        ("city avenues", city_z, 110.0),
        ("south lanes", south_x, 130.0),  # the turf's east side
        ("south roads", south_z, 110.0),
    ):
        assert max(_gaps(values)) <= limit, (name, _gaps(values))


def test_frontage_roads_run_beside_the_motorway():
    """A road each side of the viaduct's south straight, a lane east of its vertical straight,
    and River Lane along the bank road's south side, all joined to the grid; the West Entrance
    climbs from the south frontage road."""
    d = build()
    names = {w.tags.get("name") for w in d.ways}
    for name in ("Viaduct Road North", "Viaduct Road South", "Viaduct Lane", "River Lane"):
        assert name in names, name
    entrance = next(w for w in d.ways if w.tags.get("name") == "West Entrance")
    south = next(w for w in d.ways if w.tags.get("name") == "Viaduct Road South")
    assert entrance.points[0] in south.points
    viaduct = [w for w in d.ways if w.tags.get("highway") == "motorway" and w.tags.get("bridge")]
    deck_z = [p[1] for w in viaduct for p in w.points if 200.0 < p[0] < 700.0 and p[1] > 600.0]
    for w in d.ways:
        if w.tags.get("name", "").startswith("Viaduct Road"):
            for p in w.points:
                assert min(abs(p[1] - z) for z in deck_z) >= 20.0, "clear of the deck's edge"


def test_minor_streets_keep_out_of_services_park_and_turf():
    d = build()
    minor = [
        w
        for w in d.ways
        if w.tags.get("name", "").split(" ")[0]
        in (
            "Alder",
            "Birch",
            "Cedar",
            "Hollow",
            "Kiln",
            "Foundry",
            "Quay",
            "Depot",
            "Elm",
            "Oak",
            "Ash",
        )
        or (w.tags.get("name", "").endswith(" Lane") and w.tags.get("name", "")[0].isdigit())
    ]
    assert len(minor) >= 20
    turf = dressing._bbox(d.turf)
    park = next(a for a in d.vegetation_areas if a.tags.get("leisure") == "park")
    keep_out = [turf, dressing._bbox(park.ring)] + [
        dressing._bbox(a.ring) for a in d.service_areas + d.parking
    ]
    for w in minor:
        for a, b in zip(w.points, w.points[1:], strict=False):
            mid = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
            for box in keep_out:
                assert not (box[0] < mid[0] < box[2] and box[1] < mid[1] < box[3]), (
                    w.tags.get("name"),
                    mid,
                )
