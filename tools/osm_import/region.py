"""Region rules for map packs that live together in a city's repository (add-pack-repositories).

- **A pinned origin.** A region's `origin` ({lat, lon}) fixes the local frame, so a re-export
  with a wider box doesn't move everything. Re-exporting into a pack whose `map.origin`
  differs is refused unless asked for (`--new-origin`), since stories place things relative
  to it.
- **Borders on the chunk grid.** A district gives its extent as `border.chunks`
  ([x0, z0, x1, z1], chunk coordinates of the city's origin, x0..x1-1 and z0..z1-1), so every
  chunk belongs to exactly one district. The import box is the lat/lon box around it. A border
  needs an origin, and it must not overlap a sibling region (a region file beside this one
  with the same origin).
"""

from __future__ import annotations

import json
from pathlib import Path

from osm_import.osm_data import BBox
from osm_import.pack import CHUNK_SIZE_M
from osm_import.projection import LocalFrame, Projector


class RegionError(ValueError):
    """A region file that breaks the rules above."""


def origin_of(region: dict) -> tuple[float, float] | None:
    o = region.get("origin")
    if o is None:
        return None
    if not isinstance(o, dict) or "lat" not in o or "lon" not in o:
        raise RegionError('origin must be {"lat": ..., "lon": ...}')
    return float(o["lat"]), float(o["lon"])


def border_of(region: dict) -> tuple[int, int, int, int] | None:
    b = region.get("border")
    if b is None:
        return None
    chunks = b.get("chunks") if isinstance(b, dict) else None
    if (
        not isinstance(chunks, list)
        or len(chunks) != 4
        or not all(isinstance(c, int) and not isinstance(c, bool) for c in chunks)
    ):
        raise RegionError('border must be {"chunks": [x0, z0, x1, z1]} in whole chunks')
    x0, z0, x1, z1 = chunks
    if x1 <= x0 or z1 <= z0:
        raise RegionError(f"border {chunks} is empty: x1 must be above x0 and z1 above z0")
    return x0, z0, x1, z1


def border_bbox(border: tuple[int, int, int, int], proj: Projector) -> BBox:
    """The lat/lon box around a border (UTM's grid isn't lat/lon's, so it is a little bigger;
    chunks outside the border belong to the neighbours)."""
    x0, z0, x1, z1 = border
    corners = [
        proj.to_latlon(x * CHUNK_SIZE_M, z * CHUNK_SIZE_M) for x in (x0, x1) for z in (z0, z1)
    ]
    lats = [c[0] for c in corners]
    lons = [c[1] for c in corners]
    return BBox(round(min(lats), 7), round(min(lons), 7), round(max(lats), 7), round(max(lons), 7))


def _overlaps(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def check_siblings(region_path: Path, region: dict) -> None:
    """Raise when this region's border overlaps a sibling district's (same origin)."""
    border = border_of(region)
    if border is None:
        return
    origin = origin_of(region)
    for other in sorted(region_path.parent.glob("*.json")):
        if other.resolve() == region_path.resolve():
            continue
        try:
            data = json.loads(other.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict) or origin_of(data) != origin:
            continue
        theirs = border_of(data)
        if theirs is not None and _overlaps(border, theirs):
            raise RegionError(
                f"border {list(border)} overlaps {other.name}'s {list(theirs)}; districts of a "
                "city must not share chunks"
            )


def projector_for(region: dict, bbox: BBox | None) -> tuple[Projector, BBox]:
    """The region's frame and import box: the pinned origin and the box around its border
    when given, otherwise the bbox and its centre."""
    origin = origin_of(region)
    border = border_of(region)
    if border is not None:
        if origin is None:
            raise RegionError("a border needs a pinned origin (the city's)")
        if region.get("bbox") is not None:
            raise RegionError("give a border or a bbox, not both")
        proj = Projector.for_origin(*origin)
        return proj, border_bbox(border, proj)
    if bbox is None:
        raise RegionError("a region needs a bbox or a border")
    proj = Projector.for_origin(*origin) if origin is not None else Projector.for_bbox(bbox)
    return proj, bbox


def check_origin(pack_out: Path, frame: LocalFrame, allow_new: bool) -> None:
    """Raise when re-exporting into a pack whose origin differs, unless `allow_new`."""
    manifest_path = pack_out / "pack.json"
    if allow_new or not manifest_path.is_file():
        return
    try:
        old = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return
    o = (old.get("map") or {}).get("origin") or {}
    old_crs = (old.get("map") or {}).get("crs")
    if (o.get("easting"), o.get("northing"), old_crs) != (
        frame.origin_easting,
        frame.origin_northing,
        frame.crs,
    ):
        raise RegionError(
            f"this export would move the pack's origin from {o.get('easting')}, "
            f"{o.get('northing')} ({old_crs}) to {frame.origin_easting}, {frame.origin_northing} "
            f"({frame.crs}), which moves everything placed on the map; pin the old origin in the "
            "region file (`origin`), or pass --new-origin and bump the pack's major version"
        )
