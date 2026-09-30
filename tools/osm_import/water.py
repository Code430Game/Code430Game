"""Water areas from OpenStreetMap: rings, clipping, triangulation, surface height.

Approach: closed `natural=water` ways are rings on their own. Multipolygon
relations are assembled by joining member ways end to end (roles outer/inner,
with containment deciding which outer a hole belongs to). Rings are projected
to the local frame, turned into shapely polygons, clipped to the bbox, and
triangulated with earcut so Godot gets ready-made triangles. The surface height
is the median terrain height at the polygon's vertices and centroid, because the
DTM records the water surface.
"""

from __future__ import annotations

import logging
import statistics
from dataclasses import dataclass, field

import mapbox_earcut as earcut
import numpy as np
from shapely import make_valid
from shapely.geometry import MultiPolygon, Polygon, box
from shapely.geometry.polygon import orient

from osm_import.elevation import ElevationSource
from osm_import.osm_data import BBox
from osm_import.projection import Projector

log = logging.getLogger(__name__)

WATER_KINDS = {"river", "canal", "lake", "pond", "basin", "reservoir", "stream", "lock"}
COORD_DECIMALS = 3
MIN_AREA_M2 = 25.0


def water_query(bbox: BBox) -> str:
    """Water ways and relations in the bbox, with full member geometry."""
    b = bbox.overpass()
    return (
        "[out:json][timeout:180];("
        f'way["natural"="water"]({b});relation["natural"="water"]({b});'
        f'way["waterway"="riverbank"]({b});relation["waterway"="riverbank"]({b});'
        ");out body geom;"
    )


@dataclass
class WaterPolygon:
    id: str
    name: str | None
    kind: str
    surface_y: float
    vertices: list[tuple[float, float]]  # local (x, z)
    triangles: list[int]
    source_osm_id: int


@dataclass
class WaterResult:
    polygons: list[WaterPolygon] = field(default_factory=list)
    skipped: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, x east, z south; y is the water surface height",
            "polygons": [
                {
                    "id": p.id,
                    "name": p.name,
                    "kind": p.kind,
                    "surface_y": round(p.surface_y, COORD_DECIMALS),
                    "vertices": [
                        [round(x, COORD_DECIMALS), round(z, COORD_DECIMALS)] for x, z in p.vertices
                    ],
                    "triangles": p.triangles,
                    "osm_id": p.source_osm_id,
                }
                for p in sorted(self.polygons, key=lambda p: p.id)
            ],
        }


def _kind(tags: dict) -> str:
    k = tags.get("water") or ("river" if tags.get("waterway") == "riverbank" else "water")
    return k if k in WATER_KINDS else "water"


def assemble_rings(
    members: list[dict],
) -> tuple[list[list[tuple[float, float]]], list[list[tuple[float, float]]], int]:
    """Join member ways into closed rings. Returns (outers, inners, unclosed count) in (lat, lon)."""
    pieces: dict[str, list[list[tuple[float, float]]]] = {"outer": [], "inner": []}
    for m in members:
        if m.get("type") != "way" or "geometry" not in m:
            continue
        role = "inner" if m.get("role") == "inner" else "outer"
        pieces[role].append([(g["lat"], g["lon"]) for g in m["geometry"]])
    result: dict[str, list[list[tuple[float, float]]]] = {"outer": [], "inner": []}
    unclosed = 0
    for role, ways in pieces.items():
        remaining = [w for w in ways if len(w) >= 2]
        while remaining:
            ring = list(remaining.pop(0))
            progressed = True
            while ring[0] != ring[-1] and progressed:
                progressed = False
                for i, w in enumerate(remaining):
                    if w[0] == ring[-1]:
                        ring.extend(w[1:])
                    elif w[-1] == ring[-1]:
                        ring.extend(reversed(w[:-1]))
                    elif w[-1] == ring[0]:
                        ring = w[:-1] + ring
                    elif w[0] == ring[0]:
                        ring = list(reversed(w[1:])) + ring
                    else:
                        continue
                    remaining.pop(i)
                    progressed = True
                    break
            if ring[0] == ring[-1] and len(ring) >= 4:
                result[role].append(ring)
            else:
                unclosed += 1
    return result["outer"], result["inner"], unclosed


def _to_local(ring: list[tuple[float, float]], proj: Projector) -> list[tuple[float, float]]:
    return [proj.to_local(lat, lon) for lat, lon in ring]


def _polygons_from_rings(outers: list, inners: list) -> list[Polygon]:
    outer_polys = [Polygon(r) for r in outers]
    holes_for: dict[int, list] = {i: [] for i in range(len(outer_polys))}
    for hole in inners:
        hp = Polygon(hole)
        for i, op in enumerate(outer_polys):
            if op.contains(hp.representative_point()):
                holes_for[i].append(hole)
                break
    return [Polygon(outers[i], holes_for[i]) for i in range(len(outer_polys))]


def _triangulate(poly: Polygon) -> tuple[list[tuple[float, float]], list[int]]:
    poly = orient(poly, sign=1.0)
    rings = [list(poly.exterior.coords)[:-1]] + [list(r.coords)[:-1] for r in poly.interiors]
    verts: list[tuple[float, float]] = []
    ends: list[int] = []
    for r in rings:
        verts.extend((float(x), float(z)) for x, z in r)
        ends.append(len(verts))
    arr = np.array(verts, dtype=np.float64)
    tris = earcut.triangulate_float64(arr, np.array(ends, dtype=np.uint32))
    return verts, [int(i) for i in tris]


def _surface_height(poly: Polygon, source: ElevationSource) -> float:
    pts = list(poly.exterior.coords)[:-1]
    c = poly.representative_point()
    samples = [source.sample(x, z) for x, z in pts] + [source.sample(c.x, c.y)]
    return float(statistics.median(samples))


def build_water(payload: dict, bbox: BBox, proj: Projector, source: ElevationSource) -> WaterResult:
    """Turn an Overpass water payload into clipped, triangulated polygons."""
    result = WaterResult()
    min_x, min_z, max_x, max_z = proj.bbox_local(bbox)
    clip = box(min_x, min_z, max_x, max_z)
    items: list[tuple[str, int, dict, list, list]] = []
    for el in payload.get("elements", []):
        tags = el.get("tags", {})
        if el["type"] == "way":
            geom = [(g["lat"], g["lon"]) for g in el.get("geometry", [])]
            if len(geom) < 4 or geom[0] != geom[-1]:
                result.skipped.append({"id": f"w{el['id']}", "reason": "way is not a closed ring"})
                continue
            items.append((f"w{el['id']}", el["id"], tags, [geom], []))
        elif el["type"] == "relation":
            outers, inners, unclosed = assemble_rings(el.get("members", []))
            if unclosed or not outers:
                result.skipped.append(
                    {
                        "id": f"r{el['id']}",
                        "reason": f"{unclosed} unclosed ring(s), {len(outers)} outer(s)",
                    }
                )
                if not outers:
                    continue
            items.append((f"r{el['id']}", el["id"], tags, outers, inners))
    for wid, osm_id, tags, outers, inners in sorted(items, key=lambda t: t[0]):
        local_outers = [_to_local(r, proj) for r in outers]
        local_inners = [_to_local(r, proj) for r in inners]
        parts = []
        for poly in _polygons_from_rings(local_outers, local_inners):
            geom = make_valid(poly).intersection(clip)
            if geom.is_empty:
                continue
            if isinstance(geom, Polygon):
                parts.append(geom)
            elif isinstance(geom, MultiPolygon):
                parts.extend(list(geom.geoms))
            else:
                for g in getattr(geom, "geoms", []):
                    if isinstance(g, Polygon):
                        parts.append(g)
        parts = [p for p in parts if p.area >= MIN_AREA_M2]
        for n, part in enumerate(sorted(parts, key=lambda p: (-p.area, p.bounds))):
            verts, tris = _triangulate(part)
            result.polygons.append(
                WaterPolygon(
                    id=f"{wid}.{n}",
                    name=tags.get("name"),
                    kind=_kind(tags),
                    surface_y=_surface_height(part, source),
                    vertices=verts,
                    triangles=tris,
                    source_osm_id=osm_id,
                )
            )
    log.info("water: %d polygons, %d skipped", len(result.polygons), len(result.skipped))
    return result
