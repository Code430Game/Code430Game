"""Building footprints from OpenStreetMap: rings, heights, clipping, roof triangles.

Approach: closed `building=*` ways are footprints; multipolygon relations reuse
the water ring assembly. Height comes from `height`, else `building:levels`
times a storey height, else a per-type default level count. Footprints are
projected, clipped to the bbox, and the roof is triangulated with earcut so
Godot extrudes walls from the rings and fans the roof from the triangles. The
ground height is the median terrain height at the footprint vertices.
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

from osm_import import tags as T
from osm_import.elevation import ElevationSource
from osm_import.osm_data import BBox
from osm_import.projection import Projector
from osm_import.water import assemble_rings

log = logging.getLogger(__name__)

COORD_DECIMALS = 2


def buildings_query(bbox: BBox) -> str:
    b = bbox.overpass()
    return (
        f'[out:json][timeout:240];(way["building"]({b});relation["building"]({b}););out body geom;'
    )


@dataclass
class Building:
    id: str
    kind: str
    name: str | None
    height_m: float
    ground_y: float
    rings: list[list[tuple[float, float]]]  # outer first, then holes; not closed
    roof_vertices: list[tuple[float, float]]
    roof_triangles: list[int]
    osm_id: int
    height_source: str
    material: str = ""  # building:material, lower-cased, or ""
    colour: str = ""  # building:colour as tagged (hex or name), or ""
    roof_shape: str = ""  # roof:shape, or ""
    roof_levels: float = 0.0
    levels: float = 0.0  # building:levels, 0 when untagged
    shopfront: bool = False  # a shop or amenity at street level


SHOPFRONT_AMENITIES = {
    "restaurant",
    "cafe",
    "bar",
    "pub",
    "fast_food",
    "bank",
    "pharmacy",
    "cinema",
    "theatre",
    "marketplace",
    "ice_cream",
    "nightclub",
    "dentist",
    "post_office",
    "library",
}


def _has_shopfront(tags: dict) -> bool:
    """A shop or street-level amenity, or a retail building: a glass ground floor."""
    if tags.get("shop"):
        return True
    if tags.get("amenity") in SHOPFRONT_AMENITIES:
        return True
    return tags.get("building") in ("retail", "commercial")


@dataclass
class BuildingsResult:
    buildings: list[Building] = field(default_factory=list)
    skipped: list[dict] = field(default_factory=list)
    height_sources: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, x east, z south; ground_y and height_m vertical",
            "buildings": [
                {
                    "id": b.id,
                    "kind": b.kind,
                    "name": b.name,
                    "height_m": round(b.height_m, 2),
                    "ground_y": round(b.ground_y, 2),
                    "rings": [
                        [[round(x, COORD_DECIMALS), round(z, COORD_DECIMALS)] for x, z in r]
                        for r in b.rings
                    ],
                    # With a single ring the roof vertices equal that ring; readers use rings[0] then.
                    "roof_vertices": (
                        []
                        if len(b.rings) == 1
                        else [
                            [round(x, COORD_DECIMALS), round(z, COORD_DECIMALS)]
                            for x, z in b.roof_vertices
                        ]
                    ),
                    "roof_triangles": b.roof_triangles,
                    "osm_id": b.osm_id,
                    "material": b.material,
                    "colour": b.colour,
                    "roof_shape": b.roof_shape,
                    "roof_levels": b.roof_levels,
                    "levels": b.levels,
                    "shopfront": b.shopfront,
                }
                for b in sorted(self.buildings, key=lambda b: b.id)
            ],
        }


def building_height(tags: dict, rules: dict) -> tuple[float, str]:
    """(height in metres, source) from tags and the config rules."""
    storey = float(rules.get("storey_height_m", 3.2))
    minimum = float(rules.get("min_height_m", 3.0))
    h = T.parse_width_m(tags.get("height"))  # same parser: metres or feet
    if h is not None:
        return max(h, minimum), "tag"
    levels = T.parse_float(tags.get("building:levels"))
    if levels is not None and levels > 0:
        return max(levels * storey, minimum), "levels"
    defaults = rules.get("default_levels", {})
    kind = tags.get("building", "yes")
    lv = defaults.get(kind, defaults.get("default", 2))
    return max(float(lv) * storey, minimum), "default"


def _triangulate(poly: Polygon) -> tuple[list[tuple[float, float]], list[int]]:
    poly = orient(poly, sign=1.0)
    rings = [list(poly.exterior.coords)[:-1]] + [list(r.coords)[:-1] for r in poly.interiors]
    verts: list[tuple[float, float]] = []
    ends: list[int] = []
    for r in rings:
        verts.extend((float(x), float(z)) for x, z in r)
        ends.append(len(verts))
    tris = earcut.triangulate_float64(
        np.array(verts, dtype=np.float64), np.array(ends, dtype=np.uint32)
    )
    return verts, [int(i) for i in tris]


def build_buildings(
    payload: dict, bbox: BBox, proj: Projector, source: ElevationSource, rules: dict
) -> BuildingsResult:
    result = BuildingsResult()
    min_x, min_z, max_x, max_z = proj.bbox_local(bbox)
    clip = box(min_x, min_z, max_x, max_z)
    min_area = float(rules.get("min_area_m2", 4.0))
    items: list[tuple[str, int, dict, list, list]] = []
    for el in payload.get("elements", []):
        tags = el.get("tags", {})
        if tags.get("building", "yes") == "no":
            continue
        if el["type"] == "way":
            geom = [(g["lat"], g["lon"]) for g in el.get("geometry", [])]
            if len(geom) < 4 or geom[0] != geom[-1]:
                result.skipped.append({"id": f"w{el['id']}", "reason": "not a closed ring"})
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
    for bid, osm_id, tags, outers, inners in sorted(items, key=lambda t: t[0]):
        local_outers = [[proj.to_local(lat, lon) for lat, lon in r] for r in outers]
        local_inners = [[proj.to_local(lat, lon) for lat, lon in r] for r in inners]
        height, source_kind = building_height(tags, rules)
        result.height_sources[source_kind] = result.height_sources.get(source_kind, 0) + 1
        parts: list[Polygon] = []
        for outer in local_outers:
            op = Polygon(outer)
            holes = [h for h in local_inners if op.contains(Polygon(h).representative_point())]
            geom = make_valid(Polygon(outer, holes)).intersection(clip)
            if geom.is_empty:
                continue
            if isinstance(geom, Polygon):
                parts.append(geom)
            elif isinstance(geom, MultiPolygon):
                parts.extend(list(geom.geoms))
            else:
                parts.extend(g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon))
        parts = [p for p in parts if p.area >= min_area]
        for n, part in enumerate(sorted(parts, key=lambda p: (-p.area, p.bounds))):
            part = orient(part, sign=1.0)  # rings and roof vertices share this orientation
            verts, tris = _triangulate(part)
            rings = [list(part.exterior.coords)[:-1]] + [
                list(r.coords)[:-1] for r in part.interiors
            ]
            samples = [source.sample(x, z) for x, z in rings[0]]
            result.buildings.append(
                Building(
                    id=f"{bid}.{n}",
                    kind=tags.get("building", "yes"),
                    name=tags.get("name"),
                    material=tags.get("building:material", "").lower(),
                    colour=tags.get("building:colour", "").strip(),
                    roof_shape=tags.get("roof:shape", "").lower(),
                    roof_levels=T.parse_float(tags.get("roof:levels")) or 0.0,
                    levels=T.parse_float(tags.get("building:levels")) or 0.0,
                    shopfront=_has_shopfront(tags),
                    height_m=height,
                    ground_y=float(statistics.median(samples)),
                    rings=[[(float(x), float(z)) for x, z in r] for r in rings],
                    roof_vertices=verts,
                    roof_triangles=tris,
                    osm_id=osm_id,
                    height_source=source_kind,
                )
            )
    log.info(
        "buildings: %d footprints, %d skipped, heights %s",
        len(result.buildings),
        len(result.skipped),
        result.height_sources,
    )
    return result
