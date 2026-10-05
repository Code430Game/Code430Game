"""Parking lots and street-side bays from OpenStreetMap.

Approach: `amenity=parking` ways are rings on their own; multipolygon relations reuse the
water ring assembly. Rings are projected, clipped to the bbox and kept above a minimum area.
Each lot gets its kind from `parking=*`, its tagged capacity, access, fee, operator and stall
orientation, the parking aisles (class `parking` edges) whose middles lie inside it, a stall
direction along the longest of those aisles (else along the ring's longest side), entrances
where an aisle or driveway meets a street near the lot, and a ground height from the built
terrain. The game drapes the lot over its own terrain grid, so rings stay 2D.

Street-side bays come from the tags on the street ways: the older `parking:lane:<side>`
scheme and the newer `parking:<side>` with `parking:<side>:orientation`. Sides are given
relative to each exported edge's direction (left of travel from `from` to `to`).
"""

from __future__ import annotations

import logging
import math
import statistics
from dataclasses import dataclass, field

from shapely import make_valid
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.geometry.polygon import orient

from osm_import import tags as T
from osm_import.graph import RoadGraph
from osm_import.osm_data import BBox, OsmData
from osm_import.projection import Projector
from osm_import.water import assemble_rings

log = logging.getLogger(__name__)

COORD_DECIMALS = 2
MIN_AREA_M2 = 30.0
ENTRANCE_REACH_M = 12.0  # an aisle/street junction this close to the lot is one of its entrances
AISLE_INSIDE_BUFFER_M = 2.0
KINDS = {
    "surface": "surface",
    "multi-storey": "multi-storey",
    "underground": "underground",
    "rooftop": "rooftop",
    "street_side": "street_side",
    "lane": "street_side",
    "layby": "street_side",
}
ORIENTATIONS = {"perpendicular", "diagonal", "parallel"}
OLD_LANE_VALUES = {
    "parallel": "parallel",
    "diagonal": "diagonal",
    "perpendicular": "perpendicular",
    "marked": "parallel",
}
NEW_PLACES = {"lane", "street_side", "on_kerb", "half_on_kerb", "shoulder"}


def parking_query(bbox: BBox) -> str:
    """Parking areas (ways and relations) in the bbox, with full geometry."""
    b = bbox.overpass()
    return (
        "[out:json][timeout:180];("
        f'way["amenity"="parking"]({b});relation["amenity"="parking"]({b});'
        ");out body geom;"
    )


@dataclass
class ParkingLot:
    id: str
    kind: str
    name: str | None
    operator: str | None
    capacity: int | None
    access: str | None
    fee: str | None
    orientation: str | None
    stall_dir: tuple[float, float]
    ground_y: float
    rings: list[list[tuple[float, float]]]  # outer first, then holes; not closed
    aisles: list[str]
    entrances: list[tuple[float, float, float]]
    osm_id: int


@dataclass
class ParkingBay:
    edge: str
    side: str  # left | right of the edge's direction
    orientation: str
    osm_way_id: int


@dataclass
class ParkingResult:
    lots: list[ParkingLot] = field(default_factory=list)
    bays: list[ParkingBay] = field(default_factory=list)
    skipped: list[dict] = field(default_factory=list)
    garages: list = field(default_factory=list)  # garages.Garage

    def counts(self) -> dict:
        kinds: dict[str, int] = {}
        for lot in self.lots:
            kinds[lot.kind] = kinds.get(lot.kind, 0) + 1
        return {
            "lots": len(self.lots),
            "kinds": dict(sorted(kinds.items())),
            "with_aisles": sum(1 for lot in self.lots if lot.aisles),
            "with_capacity": sum(1 for lot in self.lots if lot.capacity is not None),
            "bays": len(self.bays),
            "skipped": len(self.skipped),
            "garages": len(self.garages),
            "garage_tier": sum(1 for g in self.garages if g.tier == "garage"),
            "door_tier": sum(1 for g in self.garages if g.tier == "door"),
        }

    def to_dict(self) -> dict:
        def r2(v: float) -> float:
            return round(v, COORD_DECIMALS)

        return {
            "schema_version": 0,
            "units": "metres, x east, z south; ground_y vertical",
            "lots": [
                {
                    "id": lot.id,
                    "kind": lot.kind,
                    "name": lot.name,
                    "operator": lot.operator,
                    "capacity": lot.capacity,
                    "access": lot.access,
                    "fee": lot.fee,
                    "orientation": lot.orientation,
                    "stall_dir": [round(lot.stall_dir[0], 4), round(lot.stall_dir[1], 4)],
                    "ground_y": r2(lot.ground_y),
                    "rings": [[[r2(x), r2(z)] for x, z in ring] for ring in lot.rings],
                    "aisles": lot.aisles,
                    "entrances": [[r2(x), r2(y), r2(z)] for x, y, z in lot.entrances],
                    "osm_id": lot.osm_id,
                }
                for lot in sorted(self.lots, key=lambda lot: lot.id)
            ],
            "bays": [
                {
                    "edge": b.edge,
                    "side": b.side,
                    "orientation": b.orientation,
                    "osm_way_id": b.osm_way_id,
                }
                for b in sorted(self.bays, key=lambda b: (b.edge, b.side))
            ],
            "garages": [g.to_dict() for g in self.garages],
        }


def lot_kind(tags: dict) -> str:
    return KINDS.get(tags.get("parking", "surface"), "surface")


def _direction(a: tuple[float, float], b: tuple[float, float]) -> tuple[float, float]:
    dx, dz = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dz)
    if n < 1e-6:
        return (1.0, 0.0)
    # One canonical sign (the larger component positive), so a stall direction doesn't flip
    # with the aisle's drawing order or a fraction of a degree of projection tilt.
    if (abs(dx) >= abs(dz) and dx < 0.0) or (abs(dz) > abs(dx) and dz < 0.0):
        dx, dz = -dx, -dz
    return (dx / n, dz / n)


def _longest_side(poly: Polygon) -> tuple[float, float]:
    pts = list(poly.exterior.coords)
    best = max(range(len(pts) - 1), key=lambda i: math.dist(pts[i], pts[i + 1]))
    return _direction(pts[best], pts[best + 1])


def _aisles_inside(poly: Polygon, graph: RoadGraph) -> list[tuple[str, float, tuple[float, float]]]:
    """(edge id, length, direction) of parking edges whose middles lie inside the lot."""
    area = poly.buffer(AISLE_INSIDE_BUFFER_M)
    out = []
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.road_class != "parking":
            continue
        line = LineString([(p[0], p[2]) for p in e.polyline])
        if line.length < 1.0 or not area.contains(line.interpolate(0.5, normalized=True)):
            continue
        a, b = line.coords[0], line.coords[-1]
        out.append((eid, line.length, _direction(a, b)))
    return out


def _entrances(poly: Polygon, graph: RoadGraph) -> list[tuple[float, float, float]]:
    """Nodes where a parking edge meets a street edge, near the lot."""
    inc = graph.incident()
    reach = poly.buffer(ENTRANCE_REACH_M)
    out = []
    for nid in sorted(inc):
        classes = {graph.edges[eid].road_class for eid in inc[nid]}
        if "parking" not in classes or classes == {"parking"}:
            continue
        p = graph.nodes[nid].position
        if reach.contains(Point(p[0], p[2])):
            out.append((float(p[0]), float(p[1]), float(p[2])))
    return out


def _bay_orientation(tags: dict, side: str) -> str | None:
    """Orientation of street parking on `side` (left/right) of the OSM way, or None."""
    for key in (f"parking:lane:{side}", "parking:lane:both"):
        v = tags.get(key)
        if v is not None:
            return OLD_LANE_VALUES.get(v)
    for prefix in (f"parking:{side}", "parking:both"):
        place = tags.get(prefix)
        if place is not None:
            if place not in NEW_PLACES:
                return None
            o = tags.get(f"{prefix}:orientation", "parallel")
            return o if o in ORIENTATIONS else "parallel"
    return None


def build_bays(data: OsmData, graph: RoadGraph, proj: Projector) -> list[ParkingBay]:
    """Street-side bays along the edges of every street way tagged with parking."""
    bays: list[ParkingBay] = []
    by_way: dict[int, list[str]] = {}
    for eid, e in graph.edges.items():
        by_way.setdefault(e.osm_way_id, []).append(eid)
    for wid in sorted(by_way):
        way = data.ways.get(wid)
        if way is None:
            continue
        sides = {s: _bay_orientation(way.tags, s) for s in ("left", "right")}
        if not any(sides.values()):
            continue
        known = [n for n in way.nodes if n in data.nodes]
        if len(known) < 2:
            continue
        a = proj.to_local(data.nodes[known[0]].lat, data.nodes[known[0]].lon)
        b = proj.to_local(data.nodes[known[-1]].lat, data.nodes[known[-1]].lon)
        way_dir = (b[0] - a[0], b[1] - a[1])
        for eid in sorted(by_way[wid]):
            e = graph.edges[eid]
            ed = (e.polyline[-1][0] - e.polyline[0][0], e.polyline[-1][2] - e.polyline[0][2])
            same = way_dir[0] * ed[0] + way_dir[1] * ed[1] >= 0.0
            for side, orientation in sides.items():
                if orientation is None:
                    continue
                edge_side = side if same else ("right" if side == "left" else "left")
                bays.append(ParkingBay(eid, edge_side, orientation, wid))
    return bays


def build_parking(
    payload: dict,
    bbox: BBox,
    proj: Projector,
    graph: RoadGraph,
    ground,  # anything with sample(x, z): the built terrain (pack.ChunkSampler)
    data: OsmData | None = None,
) -> ParkingResult:
    result = ParkingResult()
    min_x, min_z, max_x, max_z = proj.bbox_local(bbox)
    clip = box(min_x, min_z, max_x, max_z)
    items: list[tuple[str, int, dict, list, list]] = []
    for el in payload.get("elements", []):
        tags = el.get("tags", {})
        if el["type"] == "way":
            geom = [(g["lat"], g["lon"]) for g in el.get("geometry", [])]
            if len(geom) < 4 or geom[0] != geom[-1]:
                result.skipped.append({"id": f"w{el['id']}", "reason": "not a closed ring"})
                continue
            items.append((f"w{el['id']}", el["id"], tags, [geom], []))
        elif el["type"] == "relation":
            outers, inners, unclosed = assemble_rings(el.get("members", []))
            if not outers:
                result.skipped.append(
                    {"id": f"r{el['id']}", "reason": f"{unclosed} unclosed ring(s), no outer"}
                )
                continue
            items.append((f"r{el['id']}", el["id"], tags, outers, inners))
    for lid, osm_id, tags, outers, inners in sorted(items, key=lambda t: t[0]):
        local_outers = [[proj.to_local(lat, lon) for lat, lon in r] for r in outers]
        local_inners = [[proj.to_local(lat, lon) for lat, lon in r] for r in inners]
        parts: list[Polygon] = []
        for outer in local_outers:
            op = Polygon(outer)
            holes = [h for h in local_inners if op.contains(Polygon(h).representative_point())]
            geom = make_valid(Polygon(outer, holes)).intersection(clip)
            if isinstance(geom, Polygon):
                parts.append(geom)
            elif isinstance(geom, MultiPolygon):
                parts.extend(list(geom.geoms))
            else:
                parts.extend(g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon))
        parts = [p for p in parts if not p.is_empty and p.area >= MIN_AREA_M2]
        orientation = tags.get("orientation") or tags.get("parking:orientation")
        for n, part in enumerate(sorted(parts, key=lambda p: (-p.area, p.bounds))):
            part = orient(part, sign=1.0)
            rings = [list(part.exterior.coords)[:-1]] + [
                list(r.coords)[:-1] for r in part.interiors
            ]
            aisles = _aisles_inside(part, graph)
            stall_dir = max(aisles, key=lambda a: a[1])[2] if aisles else _longest_side(part)
            samples = [ground.sample(x, z) for x, z in rings[0]]
            result.lots.append(
                ParkingLot(
                    id=f"{lid}.{n}",
                    kind=lot_kind(tags),
                    name=tags.get("name"),
                    operator=tags.get("operator"),
                    capacity=T.parse_int(tags.get("capacity")),
                    access=tags.get("access"),
                    fee=tags.get("fee"),
                    orientation=orientation if orientation in ORIENTATIONS else None,
                    stall_dir=stall_dir,
                    ground_y=float(statistics.median(samples)),
                    rings=[[(float(x), float(z)) for x, z in r] for r in rings],
                    aisles=[a[0] for a in aisles],
                    entrances=_entrances(part, graph),
                    osm_id=osm_id,
                )
            )
    if data is not None:
        result.bays = build_bays(data, graph, proj)
    log.info("parking: %s", result.counts())
    return result
