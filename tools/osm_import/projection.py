"""WGS84 -> UTM 18N (EPSG:32618) -> local metres, Y up.

Local frame: x = east, y = up, z = south (so -z is north, matching Godot's
forward). The origin is a point rounded to whole metres in its UTM zone: the region's pinned
`origin` when it has one (add-pack-repositories: a map keeps its centre across re-exports),
otherwise the bbox centre.
"""

from __future__ import annotations

from dataclasses import dataclass

from pyproj import Transformer

from osm_import.osm_data import BBox

TARGET_CRS = "EPSG:32618"  # Ottawa's zone; for_bbox picks the zone of any other region
SOURCE_CRS = "EPSG:4326"


def utm_crs_for(lat: float, lon: float) -> str:
    """EPSG code of the UTM zone containing a point."""
    zone = int((lon + 180.0) // 6.0) + 1
    zone = max(1, min(60, zone))
    return f"EPSG:{326 if lat >= 0 else 327}{zone:02d}"


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
        self._fwd = Transformer.from_crs(SOURCE_CRS, frame.crs, always_xy=True)
        self._inv = Transformer.from_crs(frame.crs, SOURCE_CRS, always_xy=True)

    @classmethod
    def for_bbox(cls, bbox: BBox) -> Projector:
        """Frame whose origin is the projected bbox centre, rounded to metres, in the UTM
        zone of that centre (EPSG:326xx north, 327xx south)."""
        return cls.for_origin(*bbox.center)

    @classmethod
    def for_origin(cls, lat: float, lon: float) -> Projector:
        """Frame whose origin is this point, projected and rounded to metres, in its UTM
        zone. A pack's own `origin` lat/lon gives back the same frame."""
        crs = utm_crs_for(lat, lon)
        fwd = Transformer.from_crs(SOURCE_CRS, crs, always_xy=True)
        inv = Transformer.from_crs(crs, SOURCE_CRS, always_xy=True)
        e, n = fwd.transform(lon, lat)
        e, n = float(round(e)), float(round(n))
        olon, olat = inv.transform(e, n)
        return cls(LocalFrame(crs, e, n, round(olat, 7), round(olon, 7)))

    def to_local(self, lat: float, lon: float) -> tuple[float, float]:
        """Returns (x, z) in local metres; y (elevation) is added later."""
        e, n = self._fwd.transform(lon, lat)
        return e - self.frame.origin_easting, self.frame.origin_northing - n

    def to_latlon(self, x: float, z: float) -> tuple[float, float]:
        """The inverse of to_local: (lat, lon) of a local point."""
        lon, lat = self._inv.transform(
            x + self.frame.origin_easting, self.frame.origin_northing - z
        )
        return lat, lon

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
