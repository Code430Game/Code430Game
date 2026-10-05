"""Underground garages from parking entrances (add-underground-parking 1.1, 1.2).

Mappers seldom draw garage outlines but do map their entrances: `amenity=parking_entrance`
nodes (and `amenity=parking` + `parking=underground` points) at the end of a driveway. Each
entrance on the road graph becomes a ramp down from the street; entrances that share a name,
or serve the same building close together, are one garage.

Two tiers:
- `door`: private or anonymous garages. A short ramp down to a closed roll-up door in a
  concrete portal; nothing behind it. Fixes every driveway that used to end in a terrain wall.
- `garage`: public garages (a name, a capacity, a fee, public access) and any named in
  `garage_overrides` (matched against entrance names and served building names). A ramp down
  to one level below the street, under a footprint taken from an underground lot outline,
  else the building the entrance serves (shrunk), else a rectangle sized from the capacity.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

from osm_import import tags as T
from osm_import.buildings import BuildingsResult
from osm_import.graph import RoadGraph
from osm_import.osm_data import OsmData
from osm_import.projection import Projector

log = logging.getLogger(__name__)

DEFAULTS = {
    "garage_depth_m": 3.2,  # garage floor below the lowest entrance
    "ceiling_m": 2.9,  # floor to ceiling
    "ramp_grade": 0.15,
    "ramp_min_m": 12.0,
    "ramp_width_m": 6.5,
    "door_ramp_m": 8.0,
    "door_drop_m": 1.2,
    "merge_m": 40.0,
    "building_reach_m": 30.0,  # the Museum of Nature entrance is 25.3 m from its footprint
    "building_inset_m": 2.0,
    "stall_area_m2": 28.0,  # stall plus its share of aisle
    "default_capacity": 60,
    "public_access": ["yes", "public", "customers", "permissive", "destination"],
    "garage_overrides": [],
}
SKIP_PARKING = {"surface", "multi-storey", "rooftop", "street_side", "lane"}


@dataclass
class Entrance:
    osm_id: int
    x: float
    y: float
    z: float
    dir: tuple[float, float]  # from the street into the garage
    tags: dict
    building: str | None = None  # served building id
    ramp: list[tuple[float, float, float]] = field(default_factory=list)  # start, end

    def name(self) -> str:
        return self.tags.get("name", "")


@dataclass
class Garage:
    id: str
    tier: str  # door | garage
    name: str | None
    capacity: int | None
    access: str | None
    fee: str | None
    floor_y: float
    ceiling_y: float
    rings: list[list[tuple[float, float]]]
    entrances: list[Entrance]
    building: str | None
    footprint_source: str  # lot | building | capacity | none

    def to_dict(self) -> dict:
        def r(v: float) -> float:
            return round(v, 2)

        return {
            "id": self.id,
            "tier": self.tier,
            "name": self.name,
            "capacity": self.capacity,
            "access": self.access,
            "fee": self.fee,
            "floor_y": r(self.floor_y),
            "ceiling_y": r(self.ceiling_y),
            "footprint": self.footprint_source,
            "building": self.building,
            "rings": [[[r(x), r(z)] for x, z in ring] for ring in self.rings],
            "entrances": [
                {
                    "osm_id": e.osm_id,
                    "at": [r(e.x), r(e.y), r(e.z)],
                    "dir": [round(e.dir[0], 4), round(e.dir[1], 4)],
                    "ramp": [[r(v) for v in p] for p in e.ramp],
                }
                for e in self.entrances
            ],
        }


def _is_entrance(tags: dict) -> bool:
    if tags.get("amenity") == "parking_entrance":
        return tags.get("parking", "underground") not in SKIP_PARKING
    return tags.get("amenity") == "parking" and tags.get("parking") == "underground"


def _node_index(graph: RoadGraph) -> dict[int, str]:
    out = {}
    for nid, n in graph.nodes.items():
        for o in n.osm_node_ids:
            out[o] = nid
    return out


def _direction_in(graph: RoadGraph, nid: str) -> tuple[float, float] | None:
    """The street's heading as it arrives at a dead-end node; None at a through node."""
    arrivals = []
    for e in graph.edges.values():
        if e.to_node == nid:
            a, b = e.polyline[-2], e.polyline[-1]
        elif e.from_node == nid:
            a, b = e.polyline[1], e.polyline[0]
        else:
            continue
        d = math.hypot(b[0] - a[0], b[2] - a[2])
        if d > 0:
            arrivals.append(((b[0] - a[0]) / d, (b[2] - a[2]) / d))
    return arrivals[0] if len(arrivals) == 1 else None


def build_garages(
    data: OsmData,
    graph: RoadGraph,
    proj: Projector,
    buildings: BuildingsResult | None,
    underground_lots: list,  # parking.ParkingLot with kind "underground"
    ground,  # sample(x, z)
    rules: dict | None = None,
) -> list[Garage]:
    cfg = dict(DEFAULTS)
    cfg.update(rules or {})
    on_graph = _node_index(graph)
    polys = []
    if buildings is not None:
        for b in buildings.buildings:
            if b.rings and len(b.rings[0]) >= 3:
                p = Polygon(b.rings[0], b.rings[1:])
                polys.append((b.id, b.name or "", p if p.is_valid else p.buffer(0)))
    entrances: list[Entrance] = []
    loose_points: list[tuple[float, float, dict]] = []
    for node in data.nodes.values():
        if not _is_entrance(node.tags):
            continue
        nid = on_graph.get(node.id)
        if nid is None:
            x, z = proj.to_local(node.lat, node.lon)
            loose_points.append((x, z, node.tags))
            continue
        x, y, z = graph.nodes[nid].position
        d = _direction_in(graph, nid)
        entrances.append(Entrance(node.id, x, y, z, d or (0.0, 0.0), dict(node.tags)))
    # Points that are not on a road (garage markers inside blocks) lend their tags to the
    # nearest entrance.
    for x, z, tags in loose_points:
        near = min(entrances, key=lambda e: math.hypot(e.x - x, e.z - z), default=None)
        if near is not None and math.hypot(near.x - x, near.z - z) <= 80.0:
            for k in ("name", "capacity", "fee", "access", "operator"):
                if k in tags and k not in near.tags:
                    near.tags[k] = tags[k]
    # Served building and missing directions.
    for e in entrances:
        probe = Point(e.x + e.dir[0] * 6.0, e.z + e.dir[1] * 6.0)
        best = None
        for bid, _name, p in polys:
            d = p.distance(probe)
            if d <= cfg["building_reach_m"] and (best is None or d < best[0]):
                best = (d, bid, p)
        if best is not None:
            e.building = best[1]
            if e.dir == (0.0, 0.0):
                c = best[2].representative_point()
                dx, dz = c.x - e.x, c.y - e.z
                n = math.hypot(dx, dz) or 1.0
                e.dir = (dx / n, dz / n)
        if e.dir == (0.0, 0.0):
            e.dir = (1.0, 0.0)
    clusters = _cluster(entrances, cfg["merge_m"])
    building_by_id = {bid: (name, p) for bid, name, p in polys}
    lot_polys = [Polygon(lot.rings[0], lot.rings[1:]) for lot in underground_lots if lot.rings]
    garages: list[Garage] = []
    overrides = [s.lower() for s in cfg["garage_overrides"]]
    for n, group in enumerate(clusters):
        tags = {}
        for e in group:
            for k, v in e.tags.items():
                tags.setdefault(k, v)
        bids = [e.building for e in group if e.building]
        building = max(set(bids), key=bids.count) if bids else None
        bname = building_by_id[building][0] if building else ""
        names = [e.name() for e in group if e.name()] + ([bname] if bname else [])
        overridden = any(o in nm.lower() for nm in names for o in overrides)
        public = (
            bool(tags.get("name"))
            or tags.get("capacity") is not None
            or tags.get("fee") == "yes"
            or tags.get("access") in cfg["public_access"]
        )
        private = tags.get("access") in ("private", "no")
        tier = "garage" if overridden or (public and not private) else "door"
        top = min(e.y for e in group)
        floor_y = top - cfg["garage_depth_m"]
        rings: list[list[tuple[float, float]]] = []
        source = "none"
        if tier == "garage":
            for e in group:
                drop = e.y - floor_y
                length = max(cfg["ramp_min_m"], drop / cfg["ramp_grade"])
                e.ramp = [
                    (e.x, e.y, e.z),
                    (e.x + e.dir[0] * length, floor_y, e.z + e.dir[1] * length),
                ]
            poly, source = _footprint(group, lot_polys, building_by_id.get(building), tags, cfg)
            ends = [Point(e.ramp[1][0], e.ramp[1][2]) for e in group]
            joins = [poly]
            for end in ends:
                if not poly.buffer(0.5).contains(end):
                    nearest = poly.exterior.interpolate(poly.exterior.project(end))
                    joins.append(LineString([end, nearest]).buffer(cfg["ramp_width_m"] / 2.0 + 1.0))
                joins.append(end.buffer(cfg["ramp_width_m"] / 2.0 + 1.0))
            merged = unary_union(joins)
            if merged.geom_type == "MultiPolygon":
                merged = max(merged.geoms, key=lambda g: g.area)
            merged = merged.simplify(0.5)
            rings = [list(merged.exterior.coords)[:-1]]
        else:
            for e in group:
                end_y = e.y - cfg["door_drop_m"]
                e.ramp = [
                    (e.x, e.y, e.z),
                    (
                        e.x + e.dir[0] * cfg["door_ramp_m"],
                        end_y,
                        e.z + e.dir[1] * cfg["door_ramp_m"],
                    ),
                ]
        garages.append(
            Garage(
                id=f"g{n}",
                tier=tier,
                name=tags.get("name") or (bname if tier == "garage" and bname else None),
                capacity=T.parse_int(tags.get("capacity")),
                access=tags.get("access"),
                fee=tags.get("fee"),
                floor_y=floor_y,
                ceiling_y=floor_y + cfg["ceiling_m"],
                rings=[[(float(x), float(z)) for x, z in ring] for ring in rings],
                entrances=group,
                building=building,
                footprint_source=source,
            )
        )
    log.info(
        "garages: %d (%d garage tier, %d door tier) from %d entrances",
        len(garages),
        sum(1 for g in garages if g.tier == "garage"),
        sum(1 for g in garages if g.tier == "door"),
        len(entrances),
    )
    return garages


def _cluster(entrances: list[Entrance], merge_m: float) -> list[list[Entrance]]:
    parent = list(range(len(entrances)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i, a in enumerate(entrances):
        for j in range(i + 1, len(entrances)):
            b = entrances[j]
            same_name = a.name() and a.name() == b.name()
            same_building = a.building and a.building == b.building
            close = math.hypot(a.x - b.x, a.z - b.z) <= merge_m
            if same_name or (same_building and close):
                parent[find(i)] = find(j)
    groups: dict[int, list[Entrance]] = {}
    for i, e in enumerate(entrances):
        groups.setdefault(find(i), []).append(e)
    return sorted(groups.values(), key=lambda g: min(e.osm_id for e in g))


def _footprint(group, lot_polys, building, tags, cfg) -> tuple[Polygon, str]:
    for p in lot_polys:
        if any(p.distance(Point(e.x, e.z)) <= 30.0 for e in group):
            return p, "lot"
    if building is not None:
        _name, p = building
        inset = p.buffer(-cfg["building_inset_m"])
        if inset.geom_type == "MultiPolygon":
            inset = max(inset.geoms, key=lambda g: g.area)
        if not inset.is_empty and inset.area > 200.0:
            return inset, "building"
        return p, "building"
    cap = T.parse_int(tags.get("capacity")) or cfg["default_capacity"]
    area = max(20, min(cap, 400)) * cfg["stall_area_m2"]
    e = group[0]
    along = min(math.sqrt(area), 60.0)
    across = area / along
    sx, sz = e.ramp[1][0], e.ramp[1][2]
    ux, uz = e.dir
    vx, vz = -uz, ux
    corners = [
        (sx + vx * across / 2, sz + vz * across / 2),
        (sx + ux * along + vx * across / 2, sz + uz * along + vz * across / 2),
        (sx + ux * along - vx * across / 2, sz + uz * along - vz * across / 2),
        (sx - vx * across / 2, sz - vz * across / 2),
    ]
    return Polygon(corners), "capacity"
