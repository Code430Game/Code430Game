"""Yards around houses: front lawns, backyards, side yards, paths to the door, fence lines.

Approach: OSM has almost no parcels, so each house's lot is the land closer to it than to any
other house (a Voronoi diagram of points sampled along every house outline), within
LOT_REACH_M of the house, minus everything that is not yard: roads with their sidewalks,
footpaths, driveways, other buildings, parking lots and water. The lot is split by the house's
front wall (from houses.py): the front lawn lies on the street side of that wall's line, the
backyard behind the house's rearmost point, and what is left beside the house is side yard
(wide on a corner lot). The path runs from the door straight out across the front lawn.
Fences follow the lines where two backyards meet, so they never cross a road, a driveway or a
path (those were cut out of every yard first) and never run between front lawns. The
frontage is the part of the front lawn's edge along the street, where a hedge can grow.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

import shapely
from shapely import STRtree, make_valid
from shapely.geometry import (
    GeometryCollection,
    LineString,
    MultiLineString,
    MultiPoint,
    MultiPolygon,
    Point,
    Polygon,
)
from shapely.ops import linemerge, unary_union

from osm_import.buildings import BuildingsResult
from osm_import.graph import RoadGraph
from osm_import.parking import ParkingResult
from osm_import.water import WaterResult

log = logging.getLogger(__name__)

COORD_DECIMALS = 1  # 10 cm is plenty for lawns and fences, and keeps the file small
LOT_REACH_M = 30.0  # a lot reaches at most this far from its house
SAMPLE_M = 2.0  # spacing of the outline points the Voronoi diagram is built from
SIDEWALK_M = 2.0  # what a street takes beyond its carriageway (the generated sidewalk)
SERVICE_CLASSES = {"service", "parking"}  # driveways, lanes and aisles: no sidewalk
MIN_YARD_M2 = 4.0
MIN_FENCE_M = 1.0
SIMPLIFY_M = 0.1
GRID_M = 0.01  # overlays snap to this grid, so near-coincident Voronoi edges stay robust
FENCE_SIMPLIFY_M = 1.0  # fences run straight between their bends, not along every Voronoi kink
FRONTAGE_REACH_M = 0.5  # front-lawn edge this close to a street or sidewalk is frontage


@dataclass
class Yard:
    house: str  # building id
    front: list[Polygon] = field(default_factory=list)
    back: list[Polygon] = field(default_factory=list)
    side: list[Polygon] = field(default_factory=list)
    path: list[tuple[float, float]] = field(default_factory=list)  # door -> lawn edge, or []
    frontage: list[list[tuple[float, float]]] = field(default_factory=list)


@dataclass
class Fence:
    id: str
    houses: tuple[str, str]
    points: list[tuple[float, float]]


@dataclass
class YardsResult:
    yards: list[Yard] = field(default_factory=list)
    fences: list[Fence] = field(default_factory=list)

    def counts(self) -> dict:
        return {
            "yards": len(self.yards),
            "with_front": sum(1 for y in self.yards if y.front),
            "with_back": sum(1 for y in self.yards if y.back),
            "with_path": sum(1 for y in self.yards if y.path),
            "fences": len(self.fences),
            "fence_km": round(sum(LineString(f.points).length for f in self.fences) / 1000.0, 2),
        }

    def to_dict(self) -> dict:
        def pt(p) -> list[float]:
            return [round(float(p[0]), COORD_DECIMALS), round(float(p[1]), COORD_DECIMALS)]

        def poly(p: Polygon) -> list[list[list[float]]]:
            p = shapely.geometry.polygon.orient(p, sign=1.0)
            return [[pt(c) for c in list(p.exterior.coords)[:-1]]] + [
                [pt(c) for c in list(r.coords)[:-1]] for r in p.interiors
            ]

        return {
            "schema_version": 0,
            "units": "metres, x east, z south; polygons are rings (outer first, then holes), not closed",
            "yards": [
                {
                    "house": y.house,
                    "front": [poly(p) for p in y.front],
                    "back": [poly(p) for p in y.back],
                    "side": [poly(p) for p in y.side],
                    "path": [pt(p) for p in y.path],
                    "frontage": [[pt(p) for p in line] for line in y.frontage],
                }
                for y in sorted(self.yards, key=lambda y: y.house)
            ],
            "fences": [
                {"id": f.id, "houses": list(f.houses), "points": [pt(p) for p in f.points]}
                for f in sorted(self.fences, key=lambda f: f.id)
            ],
        }


def _polygons(geom) -> list[Polygon]:
    if geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, (MultiPolygon, GeometryCollection)):
        return [g for part in geom.geoms for g in _polygons(part)]
    return []


def _polygonal(geom):
    """The polygon parts of `geom` as one geometry. `make_valid` turns a degenerate outline (a
    sliver, a repeated point) into lines or a collection, and GEOS refuses an overlay that mixes
    those with polygons ("Overlay input is mixed-dimension"; Ottawa had them)."""
    return unary_union(_polygons(geom))


def _lines(geom) -> list[LineString]:
    if geom.is_empty:
        return []
    if isinstance(geom, LineString):
        return [geom]
    if isinstance(geom, (MultiLineString, GeometryCollection)):
        return [g for part in geom.geoms for g in _lines(part)]
    return []


def _samples(poly: Polygon) -> list[tuple[float, float]]:
    ring = poly.exterior
    n = max(int(ring.length / SAMPLE_M), 4)
    return [tuple(ring.interpolate(ring.length * k / n).coords[0]) for k in range(n)]


def _frame(ring, hint: dict) -> tuple[tuple[float, float], tuple[float, float]]:
    """(a point on the front wall, the outward unit normal of the front wall)."""
    a = ring[hint["front_edge"]]
    c = ring[(hint["front_edge"] + 1) % len(ring)]
    dx, dz = c[0] - a[0], c[1] - a[1]
    length = max((dx * dx + dz * dz) ** 0.5, 1e-6)
    return a, (dz / length, -dx / length)  # outward: rings are counter-clockwise in (x, z)


def _cells_union(cells: list[Polygon]):
    """Union of a house's Voronoi cells. A very regular grid of houses (the proving ground)
    gives near-degenerate cells that GEOS can't overlay; then each cell is grown by a hair."""
    try:
        return shapely.union_all([make_valid(c) for c in cells], grid_size=GRID_M)
    except shapely.errors.GEOSException:
        return shapely.union_all([c.buffer(GRID_M) for c in cells])


def _halfplane(origin: tuple[float, float], normal: tuple[float, float], offset: float) -> Polygon:
    """The side of the line {p: (p - origin) . normal = offset} that `normal` points to."""
    big = 10.0 * LOT_REACH_M
    nx, nz = normal
    tx, tz = -nz, nx
    ox, oz = origin[0] + nx * offset, origin[1] + nz * offset
    return Polygon(
        [
            (ox - tx * big, oz - tz * big),
            (ox + tx * big, oz + tz * big),
            (ox + tx * big + nx * big, oz + tz * big + nz * big),
            (ox - tx * big + nx * big, oz - tz * big + nz * big),
        ]
    )


def _obstacles(
    buildings: BuildingsResult,
    houses: set[str],
    graph: RoadGraph,
    parking: ParkingResult | None,
    water: WaterResult | None,
) -> tuple[list, list]:
    """(not-yard geometries, street-side geometries for frontage)."""
    out: list = []
    streets: list = []
    for e in graph.edges.values():
        if e.tunnel or e.bridge or len(e.polyline) < 2:
            continue
        line = LineString([(p[0], p[2]) for p in e.polyline])
        margin = 0.0 if e.road_class in SERVICE_CLASSES else SIDEWALK_M
        g = line.buffer(e.width_m / 2.0 + margin, cap_style="flat")
        out.append(g)
        if e.road_class not in SERVICE_CLASSES:
            streets.append(g)
    for w in graph.pedestrian:
        if w.covered or len(w.polyline) < 2:
            continue
        g = LineString([(p[0], p[2]) for p in w.polyline]).buffer(w.width_m / 2.0, cap_style="flat")
        out.append(g)
        if w.kind == "sidewalk":
            streets.append(g)
    for b in buildings.buildings:
        if b.id not in houses:
            out.append(_polygonal(make_valid(Polygon(b.rings[0], b.rings[1:]))))
    if parking is not None:
        out.extend(
            _polygonal(make_valid(Polygon(lot.rings[0], lot.rings[1:]))) for lot in parking.lots
        )
    if water is not None:
        for wp in water.polygons:
            v, t = wp.vertices, wp.triangles
            tris = [Polygon([v[t[k]], v[t[k + 1]], v[t[k + 2]]]) for k in range(0, len(t) - 2, 3)]
            out.append(unary_union([g.buffer(0.01) for g in tris if g.area > 0]))
    return [g for g in out if not g.is_empty], streets


def build_yards(
    buildings: BuildingsResult,
    graph: RoadGraph,
    parking: ParkingResult | None = None,
    water: WaterResult | None = None,
) -> YardsResult:
    """Yards and fences for every building carrying a house hint (houses.build_house_hints)."""
    result = YardsResult()
    houses = [b for b in buildings.buildings if b.house is not None]
    if not houses:
        return result
    polys = [_polygonal(make_valid(Polygon(b.rings[0]))) for b in houses]
    house_ids = {b.id for b in houses}
    obstacles, streets = _obstacles(buildings, house_ids, graph, parking, water)
    obstacle_tree = STRtree(obstacles)
    street_tree = STRtree(streets) if streets else None
    # Voronoi cells of outline samples, unioned per house: the land nearer it than any other.
    # A point on a party wall is sampled from both houses; the first keeps it.
    seen: dict[tuple[float, float], int] = {}
    for i, p in enumerate(polys):
        for x, z in _samples(p):
            seen.setdefault((round(x, 2), round(z, 2)), i)
    points = list(seen)
    owner = list(seen.values())
    cells = shapely.voronoi_polygons(MultiPoint(points), ordered=True)
    by_house: list[list[Polygon]] = [[] for _ in houses]
    for k, cell in enumerate(cells.geoms):
        by_house[owner[k]].append(cell)
    backs: list[Polygon | None] = [None] * len(houses)
    for i, b in enumerate(houses):
        h = b.house
        house = polys[i]
        lot = _polygonal(
            shapely.intersection(
                _cells_union(by_house[i]),
                house.buffer(LOT_REACH_M),
                grid_size=GRID_M,
            )
        )
        if lot.is_empty or house.is_empty:
            continue
        cut = [obstacles[j] for j in obstacle_tree.query(lot) if not obstacles[j].is_empty]
        if cut:
            lot = shapely.difference(
                lot, shapely.union_all(cut, grid_size=GRID_M), grid_size=GRID_M
            )
        lot = shapely.difference(lot, house, grid_size=GRID_M)
        # Keep only the pieces touching the house (not land across a lane or behind a shed).
        reach = house.buffer(0.3)
        lot = unary_union([p for p in _polygons(lot) if p.intersects(reach)])
        ring = b.rings[0]
        a, n = _frame(ring, h)
        rear = min((v[0] - a[0]) * n[0] + (v[1] - a[1]) * n[1] for v in ring)
        front = lot.intersection(_halfplane(a, n, 0.0))
        back = lot.intersection(_halfplane(a, (-n[0], -n[1]), -rear))
        side = lot.difference(front).difference(back)
        yard = Yard(house=b.id)
        for name, geom in (("front", front), ("back", back), ("side", side)):
            parts = [
                p.simplify(SIMPLIFY_M) for p in _polygons(make_valid(geom)) if p.area >= MIN_YARD_M2
            ]
            getattr(yard, name).extend(p for p in parts if not p.is_empty and p.is_valid)
        if yard.back:
            backs[i] = unary_union(yard.back)
        if yard.front:
            front_u = unary_union(yard.front)
            door = Point(h["door"])
            ray = LineString(
                [
                    (door.x - n[0] * 0.01, door.y - n[1] * 0.01),
                    (door.x + n[0] * LOT_REACH_M, door.y + n[1] * LOT_REACH_M),
                ]
            )
            pieces = [g for g in _lines(ray.intersection(front_u)) if g.distance(door) < 0.1]
            if pieces:
                end = max(pieces[0].coords, key=lambda q: Point(q).distance(door))
                if Point(end).distance(door) >= 1.0:
                    yard.path = [tuple(h["door"]), (float(end[0]), float(end[1]))]
            if street_tree is not None:
                near = [streets[j] for j in street_tree.query(front_u.buffer(FRONTAGE_REACH_M))]
                if near:
                    edge = front_u.boundary.intersection(unary_union(near).buffer(FRONTAGE_REACH_M))
                    merged = linemerge(_lines(edge)) if _lines(edge) else edge
                    yard.frontage = [
                        [tuple(q) for q in g.coords] for g in _lines(merged) if g.length >= 1.0
                    ]
        if yard.front or yard.back or yard.side:
            result.yards.append(yard)
    # Fences where two backyards meet.
    back_idx = [i for i, g in enumerate(backs) if g is not None]
    if back_idx:
        tree = STRtree([backs[i] for i in back_idx])
        for k, i in enumerate(back_idx):
            for m in tree.query(backs[i].buffer(0.2)):
                j = back_idx[m]
                if j <= i:
                    continue
                shared = backs[i].boundary.intersection(backs[j].buffer(0.2))
                lines = _lines(shared)
                if not lines:
                    continue
                merged = linemerge(lines) if len(lines) > 1 else lines[0]
                for n_line, line in enumerate(sorted(_lines(merged), key=lambda g: g.coords[0])):
                    line = line.simplify(FENCE_SIMPLIFY_M)
                    if line.length < MIN_FENCE_M:
                        continue
                    result.fences.append(
                        Fence(
                            id=f"{houses[i].id}|{houses[j].id}|{n_line}",
                            houses=(houses[i].id, houses[j].id),
                            points=[(float(x), float(z)) for x, z in line.coords],
                        )
                    )
    log.info("yards: %s", result.counts())
    return result
