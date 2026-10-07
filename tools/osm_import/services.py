"""Emergency service places (add-emergency-services 1.1): police stations, hospitals, fire
stations, ambulance posts and helipads, each with a kind, a name, a position (node, or the
centre of a way or relation) and the nearest road node (where a car leaves from or arrives).
Private and campus security desks are kept as `security`, apart from police. Clinics come
back from the query but are left out.

Each place also gets a street address for the map's places list (add-map-legend): its own
OSM `addr:*` tags, else those of the building it stands in (or the nearest one within
`building_near_m`), else "on <street>" for the nearest named road within `street_near_m`.
Addresses are OSM data (ODbL), credited with the rest of the map."""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field

from osm_import.graph import RoadGraph
from osm_import.osm_data import BBox
from osm_import.projection import Projector

log = logging.getLogger(__name__)

KINDS = ("police", "security", "hospital", "fire_station", "ambulance", "helipad")
DEFAULTS = {"building_near_m": 15.0, "street_near_m": 120.0}


def services_query(bbox: BBox) -> str:
    b = bbox.overpass()
    return (
        f"[out:json][timeout:120];("
        f'nwr["amenity"~"^(police|hospital|fire_station|clinic)$"]({b});'
        f'nwr["aeroway"~"^(helipad|heliport)$"]({b});'
        f'nwr["emergency"="ambulance_station"]({b});'
        ");out center tags;"
    )


@dataclass
class Place:
    id: str
    kind: str
    name: str | None
    x: float
    y: float
    z: float
    road_node: str | None
    address: str | None = None
    address_source: str = "none"  # tags | building | street | none (reported, not exported)

    def to_dict(self) -> dict:
        out = {
            "id": self.id,
            "kind": self.kind,
            "name": self.name,
            "at": [round(self.x, 2), round(self.y, 2), round(self.z, 2)],
            "road_node": self.road_node,
        }
        if self.address:
            out["address"] = self.address
        return out


@dataclass
class ServicesResult:
    places: list[Place] = field(default_factory=list)

    def counts(self) -> dict:
        out: dict[str, int] = {}
        for p in self.places:
            out[p.kind] = out.get(p.kind, 0) + 1
        return dict(sorted(out.items()))

    def address_sources(self) -> dict:
        """How many places took their address from their own tags, a building, a street, or none."""
        out = {"tags": 0, "building": 0, "street": 0, "none": 0}
        for p in self.places:
            out[p.address_source] += 1
        return out

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, x east, z south; y the ground",
            "places": [p.to_dict() for p in self.places],
        }


def kind_of(tags: dict) -> str | None:
    amenity = tags.get("amenity")
    name = (tags.get("name") or "").lower()
    if amenity == "police":
        private = (
            tags.get("police") in ("campus", "private", "security")
            or "security" in name
            or "protection" in name
        )
        return "security" if private else "police"
    if amenity == "hospital":
        return "hospital"
    if amenity == "fire_station":
        return "fire_station"
    if tags.get("emergency") == "ambulance_station":
        return "ambulance"
    if tags.get("aeroway") in ("helipad", "heliport"):
        return "helipad"
    return None


def format_address(tags: dict) -> str | None:
    """The street address from OSM addr:* tags, such as "474 Elgin Street" ("…, Suite 100"
    with a unit); None without a house number and a street."""
    number = (tags.get("addr:housenumber") or "").strip()
    street = (tags.get("addr:street") or "").strip()
    if not number or not street:
        return None
    unit = (tags.get("addr:unit") or "").strip()
    if unit and not unit.lower().startswith(("suite", "unit", "room", "floor")):
        unit = f"Unit {unit}"
    return f"{number} {street}" + (f", {unit}" if unit else "")


def _point_in_ring(x: float, z: float, ring: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, zi = ring[i]
        xj, zj = ring[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
            inside = not inside
        j = i
    return inside


def _segment_distance(x: float, z: float, a: tuple[float, float], b: tuple[float, float]) -> float:
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0.0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
    return math.hypot(x - a[0] - dx * t, z - a[1] - dz * t)


def _ring_distance(x: float, z: float, ring: list[tuple[float, float]]) -> float:
    if _point_in_ring(x, z, ring):
        return 0.0
    return min(
        _segment_distance(x, z, ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))
    )


def addressed_buildings(payload: dict | None, proj: Projector) -> list[tuple[str, list]]:
    """(address, outline in local x, z) for every building way in an Overpass `out geom`
    payload that has a house number and a street, in id order."""
    out: list[tuple[str, list]] = []
    if not payload:
        return out
    for el in sorted(payload.get("elements", []), key=lambda e: (e["type"], e["id"])):
        if el.get("type") != "way" or len(el.get("geometry") or []) < 3:
            continue
        address = format_address(el.get("tags", {}))
        if address is None:
            continue
        ring = [proj.to_local(p["lat"], p["lon"]) for p in el["geometry"]]
        out.append((address, ring))
    return out


def nearest_street(graph: RoadGraph, x: float, z: float, within_m: float) -> str | None:
    """Name of the nearest named road edge within `within_m` of (x, z), or None."""
    best, best_d = None, within_m
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if not e.name:
            continue
        pts = [(p[0], p[2]) for p in e.polyline]
        for i in range(len(pts) - 1):
            d = _segment_distance(x, z, pts[i], pts[i + 1])
            if d < best_d:
                best, best_d = e.name, d
    return best


def address_for(
    tags: dict,
    x: float,
    z: float,
    buildings: list[tuple[str, list]],
    graph: RoadGraph,
    rules: dict,
) -> tuple[str | None, str]:
    """The place's address and where it came from: "tags", "building", "street" or "none"."""
    own = format_address(tags)
    if own:
        return own, "tags"
    best, best_d = None, float(rules["building_near_m"])
    for address, ring in buildings:
        d = _ring_distance(x, z, ring)
        if d == 0.0:
            return address, "building"
        if d < best_d:
            best, best_d = address, d
    if best:
        return best, "building"
    street = nearest_street(graph, x, z, float(rules["street_near_m"]))
    if street:
        return f"on {street}", "street"
    return None, "none"


def build_services(
    payload: dict,
    bbox: BBox,
    proj: Projector,
    graph: RoadGraph,
    ground,
    buildings_payload: dict | None = None,
    rules: dict | None = None,
) -> ServicesResult:
    res = ServicesResult()
    min_x, min_z, max_x, max_z = proj.bbox_local(bbox)
    settings = dict(DEFAULTS)
    settings.update({k: v for k, v in (rules or {}).items() if not k.startswith("_")})
    buildings = addressed_buildings(buildings_payload, proj)
    for el in sorted(payload.get("elements", []), key=lambda e: (e["type"], e["id"])):
        tags = el.get("tags", {})
        kind = kind_of(tags)
        if kind is None:
            continue
        c = el.get("center") or {"lat": el.get("lat"), "lon": el.get("lon")}
        if c.get("lat") is None:
            continue
        x, z = proj.to_local(c["lat"], c["lon"])
        if not (min_x <= x <= max_x and min_z <= z <= max_z):
            continue
        best, best_d = None, math.inf
        for nid, n in graph.nodes.items():
            d = math.hypot(n.position[0] - x, n.position[2] - z)
            if d < best_d:
                best, best_d = nid, d
        address, source = address_for(tags, x, z, buildings, graph, settings)
        place = Place(
            f"{el['type'][0]}{el['id']}",
            kind,
            tags.get("name"),
            x,
            ground.sample(x, z),
            z,
            best,
            address,
            source,
        )
        res.places.append(place)
    log.info("services: %s, addresses %s", res.counts(), res.address_sources())
    return res
