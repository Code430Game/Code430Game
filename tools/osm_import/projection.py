"""WGS84 -> UTM 18N (EPSG:32618) -> local metres, Y up.

Local frame: x = east, y = up, z = south (so -z is north, matching Godot's
forward). Origin is the projected bbox centre rounded to whole metres.
"""

from __future__ import annotations

from dataclasses import dataclass

from pyproj import Transformer

from osm_import.osm_data import BBox

TARGET_CRS = "EPSG:32618"
SOURCE_CRS = "EPSG:4326"


@dataclass(frozen=True)
class LocalFrame:
    crs: str
    origin_easting: float
    origin_northing: float
    origin_lat: float
    origin_lon: float

    def to_dict(self) -> dict:
        return {
            "crs": self.crs,
            "easting": self.origin_easting,
            "northing": self.origin_northing,
            "lat": self.origin_lat,
            "lon": self.origin_lon,
        }


class Projector:
    """Projects lat/lon to the local frame."""

    def __init__(self, frame: LocalFrame) -> None:
        self.frame = frame
        self._fwd = Transformer.from_crs(SOURCE_CRS, TARGET_CRS, always_xy=True)
        self._inv = Transformer.from_crs(TARGET_CRS, SOURCE_CRS, always_xy=True)

    @classmethod
    def for_bbox(cls, bbox: BBox) -> Projector:
        """Frame whose origin is the projected bbox centre, rounded to metres."""
        fwd = Transformer.from_crs(SOURCE_CRS, TARGET_CRS, always_xy=True)
        inv = Transformer.from_crs(TARGET_CRS, SOURCE_CRS, always_xy=True)
        lat, lon = bbox.center
        e, n = fwd.transform(lon, lat)
        e, n = float(round(e)), float(round(n))
        olon, olat = inv.transform(e, n)
        return cls(LocalFrame(TARGET_CRS, e, n, round(olat, 7), round(olon, 7)))

    def to_local(self, lat: float, lon: float) -> tuple[float, float]:
        """Returns (x, z) in local metres; y (elevation) is added later."""
        e, n = self._fwd.transform(lon, lat)
        return e - self.frame.origin_easting, self.frame.origin_northing - n

    def bbox_local(self, bbox: BBox) -> tuple[float, float, float, float]:
        """Axis-aligned local bounds (min_x, min_z, max_x, max_z) of the bbox corners."""
        corners = [
            self.to_local(bbox.south, bbox.west),
            self.to_local(bbox.south, bbox.east),
            self.to_local(bbox.north, bbox.west),
            self.to_local(bbox.north, bbox.east),
        ]
        xs = [c[0] for c in corners]
        zs = [c[1] for c in corners]
        return min(xs), min(zs), max(xs), max(zs)
