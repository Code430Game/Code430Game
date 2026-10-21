"""Writes a District as the files the importer reads: `osm.json` in Overpass JSON (nodes and
ways, equal points sharing a node, node tags on the way vertices they sit on) and one Overpass
`out body geom` payload per layer (water, buildings, parking, bridges, vegetation, services),
plus the pack extras the importer does not know about (`lap.v0.json`, `turf.v0.json`) and
the region file that ties them together. Local metres become WGS84 around a base point far
from any real place; the importer projects them back with the real UTM projection.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from proving_ground.layout import HALF_H, HALF_W, Area, District, Spot, Way

# On UTM zone 18N's central meridian, so the projection's grid convergence is zero and the
# generator's metres are the pack's metres (a fixed spawn or start line lands where it was
# drawn); far enough south of Ottawa Centretown that the two never overlap.
BASE_LAT = 45.0
BASE_LON = -75.0
M_PER_DEG_LAT = 111320.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(BASE_LAT))
GENERATOR = "code430 proving_ground"
PACK_ID = "code430.proving-ground"
PACK_NAME = "Double Cross"


def ll(x: float, z: float) -> tuple[float, float]:
    """Local metres (x east, z south) -> (lat, lon)."""
    return round(BASE_LAT - z / M_PER_DEG_LAT, 7), round(BASE_LON + x / M_PER_DEG_LON, 7)


def bbox() -> list[float]:
    s, w = ll(-HALF_W, HALF_H)
    n, e = ll(HALF_W, -HALF_H)
    return [s, w, n, e]


class _Nodes:
    """Node ids by rounded local point, so ways that meet share a node."""

    def __init__(self) -> None:
        self.ids: dict[tuple[float, float], int] = {}
        self.tags: dict[int, dict[str, str]] = {}

    def id_for(self, p: tuple[float, float]) -> int:
        key = (round(p[0], 3), round(p[1], 3))
        if key not in self.ids:
            self.ids[key] = 100000 + len(self.ids)
        return self.ids[key]

    def elements(self) -> list[dict]:
        out = []
        for key, nid in sorted(self.ids.items(), key=lambda kv: kv[1]):
            lat, lon = ll(*key)
            el: dict = {"type": "node", "id": nid, "lat": lat, "lon": lon}
            if nid in self.tags:
                el["tags"] = dict(sorted(self.tags[nid].items()))
            out.append(el)
        return out


def osm_payload(d: District) -> dict:
    nodes = _Nodes()
    ways = []
    for w in sorted(d.ways, key=lambda w: w.id):
        ids = [nodes.id_for(p) for p in w.points]
        ways.append({"type": "way", "id": w.id, "nodes": ids, "tags": dict(sorted(w.tags.items()))})
    for at, tags in d.node_tags:
        nid = nodes.id_for(at)
        nodes.tags.setdefault(nid, {}).update(tags)
    return {
        "version": 0.6,
        "generator": GENERATOR,
        "elements": nodes.elements() + ways,
        "code430_source": {"kind": "generated", "generator": GENERATOR},
    }


def _geom(ring: list[tuple[float, float]], closed: bool) -> list[dict]:
    pts = list(ring) + ([ring[0]] if closed and ring[0] != ring[-1] else [])
    return [{"lat": lat, "lon": lon} for lat, lon in (ll(*p) for p in pts)]


def _way_element(a: Area | Way, closed: bool, base: int) -> dict:
    ring = a.ring if isinstance(a, Area) else a.points
    geom = _geom(ring, closed)
    nids = [base + i for i in range(len(geom))]
    return {
        "type": "way",
        "id": a.id,
        "nodes": nids,
        "tags": dict(sorted(a.tags.items())),
        "geometry": geom,
    }


def area_payload(areas: list[Area]) -> dict:
    elements = []
    for a in sorted(areas, key=lambda a: a.id):
        if a.inners:
            members = [
                {"type": "way", "ref": a.id * 10, "role": "outer", "geometry": _geom(a.ring, True)}
            ]
            for k, inner in enumerate(a.inners):
                members.append(
                    {
                        "type": "way",
                        "ref": a.id * 10 + 1 + k,
                        "role": "inner",
                        "geometry": _geom(inner, True),
                    }
                )
            elements.append(
                {
                    "type": "relation",
                    "id": a.id,
                    "members": members,
                    "tags": dict(sorted({**a.tags, "type": "multipolygon"}.items())),
                }
            )
        else:
            elements.append(_way_element(a, True, a.id * 1000))
    return {"version": 0.6, "generator": GENERATOR, "elements": elements}


def vegetation_payload(d: District) -> dict:
    elements: list[dict] = []
    for t in sorted(d.trees, key=lambda s: s.id):
        lat, lon = ll(*t.at)
        elements.append(
            {
                "type": "node",
                "id": t.id,
                "lat": lat,
                "lon": lon,
                "tags": dict(sorted(t.tags.items())),
            }
        )
    for row in sorted(d.tree_rows, key=lambda w: w.id):
        elements.append(_way_element(row, False, row.id * 1000))
    elements.extend(area_payload(d.vegetation_areas)["elements"])
    return {"version": 0.6, "generator": GENERATOR, "elements": elements}


def services_payload(d: District) -> dict:
    """`out center tags` shape: each place is a way with its centre and tags."""
    elements = []
    for a in sorted(d.service_areas, key=lambda a: a.id):
        cx = sum(p[0] for p in a.ring) / len(a.ring)
        cz = sum(p[1] for p in a.ring) / len(a.ring)
        lat, lon = ll(cx, cz)
        elements.append(
            {
                "type": "way",
                "id": a.id,
                "center": {"lat": lat, "lon": lon},
                "tags": dict(sorted(a.tags.items())),
            }
        )
    return {"version": 0.6, "generator": GENERATOR, "elements": elements}


def lap_payload(d: District) -> dict:
    (sx, sz), (dx, dz) = d.start_line
    return {
        "schema_version": 0,
        "laps": [
            {
                "id": "double-cross",
                "name": "Double Cross",
                "start": {"x": sx, "z": sz},
                "direction": {"x": dx, "z": dz},
                "half_width_m": 16.0,
                "rearm_s": 10.0,
                "loop_names": list(d.loop_names),
            }
        ],
    }


def turf_payload(d: District) -> dict:
    """The gang's turf with the faction that holds it and where the crew regroups (the ring's
    centroid), for add-hostile-gang."""
    cx = sum(x for x, _ in d.turf) / len(d.turf)
    cz = sum(z for _, z in d.turf) / len(d.turf)
    return {
        "schema_version": 0,
        "turfs": [
            {
                "id": "double-cross",
                "name": "the Double Cross",
                "faction": "double-cross",
                "ring": [[x, z] for x, z in d.turf],
                "centre": [round(cx, 2), round(cz, 2)],
            }
        ],
    }


def region_payload(inputs_dir: str) -> dict:
    return {
        "name": "proving-ground",
        "bbox": bbox(),
        "pack_id": PACK_ID,
        "pack_name": PACK_NAME,
        "dem": "synthetic",
        "synthetic": {
            "base": 60.0,
            "slope_x": 0.004,
            "hill_height": 9.0,
            "hill_radius": 320.0,
            "hill_x": -380.0,
            "hill_z": -330.0,
        },
        "inputs": {
            "osm": f"{inputs_dir}/osm.json",
            "water": f"{inputs_dir}/water.json",
            "buildings": f"{inputs_dir}/buildings.json",
            "parking": f"{inputs_dir}/parking.json",
            "bridges": f"{inputs_dir}/bridges.json",
            "services": f"{inputs_dir}/services.json",
            "vegetation": f"{inputs_dir}/vegetation.json",
        },
        "extras": [f"{inputs_dir}/lap.v0.json", f"{inputs_dir}/turf.v0.json"],
        "description": "The Double Cross proving ground: a generated test district with one of everything (tools/proving_ground).",
        # Generated by our own code, not OpenStreetMap data: the game's asset licence.
        "license": "CC-BY-SA-4.0",
        "attribution": ["Double Cross by Code 430 contributors"],
    }


def write_all(d: District, out_dir: Path, region_path: Path | None = None) -> dict[str, Path]:
    """Writes every file under `out_dir`; the region file beside it when `region_path` is given."""
    out_dir.mkdir(parents=True, exist_ok=True)
    files = {
        "osm": (out_dir / "osm.json", osm_payload(d)),
        "water": (out_dir / "water.json", area_payload(d.water)),
        "buildings": (out_dir / "buildings.json", area_payload(d.buildings)),
        "parking": (out_dir / "parking.json", area_payload(d.parking)),
        "bridges": (out_dir / "bridges.json", area_payload(d.bridges)),
        "services": (out_dir / "services.json", services_payload(d)),
        "vegetation": (out_dir / "vegetation.json", vegetation_payload(d)),
        "lap": (out_dir / "lap.v0.json", lap_payload(d)),
        "turf": (out_dir / "turf.v0.json", turf_payload(d)),
    }
    paths: dict[str, Path] = {}
    for key, (path, payload) in files.items():
        path.write_text(json.dumps(payload, indent=1, sort_keys=False) + "\n", encoding="utf-8")
        paths[key] = path
    if region_path is not None:
        rel = out_dir.name if out_dir.parent == region_path.parent else str(out_dir)
        region = region_payload(rel)
        region["spawn"] = {"x": d.spawn[0], "z": d.spawn[1], "heading_deg": d.spawn[2]}
        region_path.write_text(json.dumps(region, indent=2) + "\n", encoding="utf-8")
        paths["region"] = region_path
    return paths


def feature_counts(d: District) -> dict[str, int]:
    """What the district contains, by feature, for the checklist test and the report."""
    tags = [w.tags for w in d.ways]
    node_tags = [t for _, t in d.node_tags]
    return {
        "ways": len(d.ways),
        "signals": sum(1 for t in node_tags if t.get("highway") == "traffic_signals"),
        "stops": sum(1 for t in node_tags if t.get("highway") == "stop"),
        "bus_stops": sum(1 for t in node_tags if t.get("highway") == "bus_stop"),
        "bus_lanes": sum(1 for t in tags if t.get("lanes:bus")),
        "bus_only": sum(1 for t in tags if t.get("bus") == "yes" and t.get("access") == "no"),
        "oneway_streets": sum(
            1 for t in tags if t.get("oneway") == "yes" and t.get("highway") == "residential"
        ),
        "motorway_links": sum(1 for t in tags if t.get("highway") == "motorway_link"),
        "motorway": sum(1 for t in tags if t.get("highway") == "motorway"),
        "bridges": sum(
            1 for t in tags if t.get("bridge") == "yes" and t.get("highway") not in ("footway",)
        ),
        "footbridges": sum(
            1 for t in tags if t.get("bridge") == "yes" and t.get("highway") == "footway"
        ),
        "tunnels": sum(1 for t in tags if t.get("tunnel") == "yes"),
        "sidewalks": sum(1 for t in tags if t.get("footway") == "sidewalk"),
        "crossings": sum(1 for t in tags if t.get("footway") == "crossing"),
        "cycleways": sum(1 for t in tags if t.get("highway") == "cycleway"),
        "steps": sum(1 for t in tags if t.get("highway") == "steps"),
        "roundabouts": sum(1 for t in tags if t.get("junction") == "roundabout"),
        "driveways": sum(1 for t in tags if t.get("service") == "driveway"),
        "parking_aisles": sum(1 for t in tags if t.get("service") == "parking_aisle"),
        "kerb_parking": sum(1 for t in tags if t.get("parking:right")),
        "rail": sum(1 for t in tags if t.get("railway") == "rail"),
        "stations": sum(1 for t in node_tags if t.get("railway") == "station"),
        "parking_entrances": sum(1 for t in node_tags if t.get("amenity") == "parking_entrance"),
        "houses": sum(1 for a in d.buildings if a.tags.get("building") == "house"),
        "apartments": sum(1 for a in d.buildings if a.tags.get("building") == "apartments"),
        "shops": sum(1 for a in d.buildings if a.tags.get("shop")),
        "offices": sum(1 for a in d.buildings if a.tags.get("building") == "office"),
        "surface_lots": sum(1 for a in d.parking if a.tags.get("parking") == "surface"),
        "garages": sum(1 for a in d.parking if a.tags.get("parking") == "multi-storey"),
        "police": sum(1 for a in d.service_areas if a.tags.get("amenity") == "police"),
        "hospital": sum(1 for a in d.service_areas if a.tags.get("amenity") == "hospital"),
        "fire_station": sum(1 for a in d.service_areas if a.tags.get("amenity") == "fire_station"),
        "helipad": sum(1 for a in d.service_areas if a.tags.get("aeroway") == "helipad"),
        "ambulance": sum(
            1 for a in d.service_areas if a.tags.get("emergency") == "ambulance_station"
        ),
        "water": len(d.water),
        "parks": sum(1 for a in d.vegetation_areas if a.tags.get("leisure") == "park"),
        "woods": sum(1 for a in d.vegetation_areas if a.tags.get("natural") == "wood"),
        "grass": sum(1 for a in d.vegetation_areas if a.tags.get("landuse") == "grass"),
        "trees": len(d.trees),
        "tree_rows": len(d.tree_rows),
        "access_points": len(d.access),
        "turf_corners": len(d.turf),
    }


__all__ = ["Spot", "area_payload", "bbox", "feature_counts", "ll", "osm_payload", "write_all"]
