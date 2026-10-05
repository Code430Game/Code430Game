"""Emergency service places (add-emergency-services 1.1): police stations, hospitals, fire
stations, ambulance posts and helipads, each with a kind, a name, a position (node, or the
centre of a way or relation) and the nearest road node (where a car leaves from or arrives).
Private and campus security desks are kept as `security`, apart from police. Clinics come
back from the query but are left out."""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field

from osm_import.graph import RoadGraph
from osm_import.osm_data import BBox
from osm_import.projection import Projector

log = logging.getLogger(__name__)

KINDS = ("police", "security", "hospital", "fire_station", "ambulance", "helipad")


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

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "name": self.name,
            "at": [round(self.x, 2), round(self.y, 2), round(self.z, 2)],
            "road_node": self.road_node,
        }


@dataclass
class ServicesResult:
    places: list[Place] = field(default_factory=list)

    def counts(self) -> dict:
        out: dict[str, int] = {}
        for p in self.places:
            out[p.kind] = out.get(p.kind, 0) + 1
        return dict(sorted(out.items()))

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


def build_services(
    payload: dict, bbox: BBox, proj: Projector, graph: RoadGraph, ground
) -> ServicesResult:
    res = ServicesResult()
    min_x, min_z, max_x, max_z = proj.bbox_local(bbox)
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
        res.places.append(
            Place(
                f"{el['type'][0]}{el['id']}",
                kind,
                tags.get("name"),
                x,
                ground.sample(x, z),
                z,
                best,
            )
        )
    log.info("services: %s", res.counts())
    return res
