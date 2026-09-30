"""Write a data-only map pack: manifest, road graph, per-chunk terrain heightmaps.

Terrain approach: sample the elevation source on a regular grid per 256 m chunk
(65 x 65 samples at 4 m, edges shared with neighbours), carve the DTM's bridge
decks out by refilling cells inside bridge footprints from their surroundings,
then flatten cells under ground-level roads to the road surface with a blended
shoulder. Each chunk is an RGB PNG (16-bit height in R and G) plus min/max in
terrain.json, because Godot reads only 8-bit PNG channels.
"""

from __future__ import annotations

import math
import warnings
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from osm_import.buildings import BuildingsResult
from osm_import.elevation import HRDEM_ATTRIBUTION, ElevationSource
from osm_import.export import OSM_ATTRIBUTION, dump_json
from osm_import.graph import RoadGraph
from osm_import.osm_data import BBox
from osm_import.png import encode_heights, write_rgb8
from osm_import.projection import LocalFrame
from osm_import.water import WaterResult

CHUNK_SIZE_M = 256.0
TERRAIN_RES_M = 4.0
SAMPLES_PER_CHUNK = int(CHUNK_SIZE_M / TERRAIN_RES_M) + 1  # shared edges
SHOULDER_M = 3.0
# Cells within this extra distance of the road edge are flattened fully, so the
# linear interpolation between 4 m cells never rises above the road surface.
FLAT_MARGIN_M = TERRAIN_RES_M
ROAD_SURFACE_DROP_M = 0.03
BRIDGE_CARVE_MARGIN_M = 10.0
FILL_ITERATIONS = 60


@dataclass
class ChunkTerrain:
    cx: int
    cz: int
    heights: np.ndarray  # (S, S) float32, row 0 = north edge (min z)

    @property
    def min_x(self) -> float:
        return self.cx * CHUNK_SIZE_M

    @property
    def min_z(self) -> float:
        return self.cz * CHUNK_SIZE_M


def chunk_range(bounds: tuple[float, float, float, float]) -> tuple[range, range]:
    min_x, min_z, max_x, max_z = bounds
    return (
        range(math.floor(min_x / CHUNK_SIZE_M), math.ceil(max_x / CHUNK_SIZE_M)),
        range(math.floor(min_z / CHUNK_SIZE_M), math.ceil(max_z / CHUNK_SIZE_M)),
    )


def sample_chunk(source: ElevationSource, cx: int, cz: int) -> ChunkTerrain:
    s = SAMPLES_PER_CHUNK
    heights = np.empty((s, s), dtype=np.float32)
    x0, z0 = cx * CHUNK_SIZE_M, cz * CHUNK_SIZE_M
    for r in range(s):
        z = z0 + r * TERRAIN_RES_M
        for c in range(s):
            heights[r, c] = source.sample(x0 + c * TERRAIN_RES_M, z)
    return ChunkTerrain(cx, cz, heights)


def _road_footprints(graph: RoadGraph) -> tuple[list[tuple], list[tuple]]:
    """(ground segments, bridge segments): (ax, az, bx, bz, ay, by, half_width)."""
    ground: list[tuple] = []
    bridges: list[tuple] = []
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        hw = e.width_m / 2.0
        target = bridges if e.bridge else ground
        if e.tunnel:
            continue
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            target.append((a[0], a[2], b[0], b[2], a[1], b[1], hw))
    return ground, bridges


def _segments_near(
    segments: list[tuple], min_x: float, min_z: float, size: float, reach: float
) -> list[tuple]:
    out = []
    for seg in segments:
        ax, az, bx, bz, _, _, hw = seg
        r = hw + reach
        if max(ax, bx) + r < min_x or min(ax, bx) - r > min_x + size:
            continue
        if max(az, bz) + r < min_z or min(az, bz) - r > min_z + size:
            continue
        out.append(seg)
    return out


def _distance_field(
    chunk: ChunkTerrain, segments: list[tuple], reach: float
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Per cell: distance to the nearest segment centreline, the road height there, and that segment's half width."""
    s = SAMPLES_PER_CHUNK
    dist = np.full((s, s), np.inf, dtype=np.float64)
    road_y = np.zeros((s, s), dtype=np.float64)
    half_w = np.zeros((s, s), dtype=np.float64)
    xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
    zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
    gx, gz = np.meshgrid(xs, zs)
    for ax, az, bx, bz, ay, by, hw in _segments_near(
        segments, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, reach
    ):
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        if l2 < 1e-9:
            continue
        t = np.clip(((gx - ax) * dx + (gz - az) * dz) / l2, 0.0, 1.0)
        d = np.hypot(gx - (ax + t * dx), gz - (az + t * dz))
        closer = d < dist
        dist = np.where(closer, d, dist)
        road_y = np.where(closer, ay + (by - ay) * t, road_y)
        half_w = np.where(closer, hw, half_w)
    return dist, road_y, half_w


def carve_bridges(chunk: ChunkTerrain, bridge_segments: list[tuple]) -> int:
    """Refill cells under bridge decks from their surroundings. Returns cells changed."""
    dist, _, half_w = _distance_field(chunk, bridge_segments, BRIDGE_CARVE_MARGIN_M)
    mask = dist <= half_w + BRIDGE_CARVE_MARGIN_M
    if not mask.any():
        return 0
    h = chunk.heights.astype(np.float64)
    known = ~mask
    if not known.any():
        return 0
    # Iterative neighbour averaging, seeded by the nearest known cells via dilation.
    filled = h.copy()
    filled[mask] = np.nan
    for _ in range(FILL_ITERATIONS):
        nan = np.isnan(filled)
        if not nan.any():
            break
        padded = np.pad(filled, 1, mode="edge")
        neigh = np.stack([padded[:-2, 1:-1], padded[2:, 1:-1], padded[1:-1, :-2], padded[1:-1, 2:]])
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            mean = np.nanmean(neigh, axis=0)
        filled = np.where(nan & ~np.isnan(mean), mean, filled)
    filled = np.where(np.isnan(filled), np.nanmean(h[known]), filled)
    for _ in range(FILL_ITERATIONS):
        padded = np.pad(filled, 1, mode="edge")
        mean = (padded[:-2, 1:-1] + padded[2:, 1:-1] + padded[1:-1, :-2] + padded[1:-1, 2:]) / 4.0
        filled = np.where(mask, mean, filled)
    chunk.heights = filled.astype(np.float32)
    return int(mask.sum())


def flatten_roads(chunk: ChunkTerrain, ground_segments: list[tuple]) -> int:
    """Set terrain under roads to the road surface, blending over the shoulder. Returns cells changed."""
    dist, road_y, half_w = _distance_field(chunk, ground_segments, FLAT_MARGIN_M + SHOULDER_M)
    flat_edge = half_w + FLAT_MARGIN_M
    under = dist <= flat_edge
    shoulder = (dist > flat_edge) & (dist <= flat_edge + SHOULDER_M)
    h = chunk.heights.astype(np.float64)
    target = road_y - ROAD_SURFACE_DROP_M
    h = np.where(under, target, h)
    with np.errstate(invalid="ignore", divide="ignore"):
        t = np.clip((dist - flat_edge) / SHOULDER_M, 0.0, 1.0)
    h = np.where(shoulder, target * (1.0 - t) + h * t, h)
    changed = int((under | shoulder).sum())
    chunk.heights = h.astype(np.float32)
    return changed


def lower_water(chunk: ChunkTerrain, water: WaterResult | None, depth: float) -> int:
    """Lower terrain cells inside water polygons to surface minus depth. Returns cells changed."""
    if water is None or not water.polygons or depth <= 0.0:
        return 0
    import shapely
    from shapely.geometry import Polygon

    s = SAMPLES_PER_CHUNK
    xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
    zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
    gx, gz = np.meshgrid(xs, zs)
    h = chunk.heights.astype(np.float64)
    changed = np.zeros((s, s), dtype=bool)
    chunk_box = shapely.box(
        chunk.min_x, chunk.min_z, chunk.min_x + CHUNK_SIZE_M, chunk.min_z + CHUNK_SIZE_M
    )
    for poly in water.polygons:
        ring = Polygon(poly.vertices) if len(poly.vertices) >= 3 else None
        if ring is None or not ring.intersects(chunk_box):
            continue
        # Triangles are the truth (holes are baked in); test membership per triangle.
        tri = np.array(poly.triangles, dtype=np.int64).reshape(-1, 3)
        v = np.array(poly.vertices, dtype=np.float64)
        inside = np.zeros((s, s), dtype=bool)
        for a, b, c in tri:
            inside |= _in_triangle(gx, gz, v[a], v[b], v[c])
        target = poly.surface_y - depth
        lowered = inside & (h > target)
        h = np.where(lowered, target, h)
        changed |= lowered
    chunk.heights = h.astype(np.float32)
    return int(changed.sum())


def _in_triangle(px: np.ndarray, pz: np.ndarray, a, b, c) -> np.ndarray:
    def sign(p1x, p1z, p2, p3):
        return (p1x - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1z - p3[1])

    d1 = sign(px, pz, a, b)
    d2 = sign(px, pz, b, c)
    d3 = sign(px, pz, c, a)
    has_neg = (d1 < 0) | (d2 < 0) | (d3 < 0)
    has_pos = (d1 > 0) | (d2 > 0) | (d3 > 0)
    return ~(has_neg & has_pos)


def flatten_buildings(chunk: ChunkTerrain, buildings: BuildingsResult | None) -> int:
    """Set terrain cells inside a footprint to the building's ground height. Returns cells changed."""
    if buildings is None or not buildings.buildings:
        return 0
    s = SAMPLES_PER_CHUNK
    xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
    zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
    gx, gz = np.meshgrid(xs, zs)
    h = chunk.heights.astype(np.float64)
    changed = np.zeros((s, s), dtype=bool)
    x0, z0, x1, z1 = (
        chunk.min_x,
        chunk.min_z,
        chunk.min_x + CHUNK_SIZE_M,
        chunk.min_z + CHUNK_SIZE_M,
    )
    for b in buildings.buildings:
        v = np.array(b.roof_vertices, dtype=np.float64)
        if v[:, 0].max() < x0 or v[:, 0].min() > x1 or v[:, 1].max() < z0 or v[:, 1].min() > z1:
            continue
        tri = np.array(b.roof_triangles, dtype=np.int64).reshape(-1, 3)
        inside = np.zeros((s, s), dtype=bool)
        for a, bb, c in tri:
            inside |= _in_triangle(gx, gz, v[a], v[bb], v[c])
        h = np.where(inside, b.ground_y, h)
        changed |= inside
    chunk.heights = h.astype(np.float32)
    return int(changed.sum())


def build_terrain(
    graph: RoadGraph,
    source: ElevationSource,
    bounds: tuple[float, float, float, float],
    water: WaterResult | None = None,
    water_depth_m: float = 0.0,
    buildings: BuildingsResult | None = None,
) -> tuple[list[ChunkTerrain], dict]:
    ground, bridges = _road_footprints(graph)
    xr, zr = chunk_range(bounds)
    chunks: list[ChunkTerrain] = []
    stats = {
        "chunks": 0,
        "cells_carved": 0,
        "cells_flattened": 0,
        "cells_lowered_for_water": 0,
        "cells_under_buildings": 0,
    }
    for cz in zr:
        for cx in xr:
            chunk = sample_chunk(source, cx, cz)
            stats["cells_carved"] += carve_bridges(chunk, bridges)
            stats["cells_lowered_for_water"] += lower_water(chunk, water, water_depth_m)
            stats["cells_under_buildings"] += flatten_buildings(chunk, buildings)
            stats["cells_flattened"] += flatten_roads(chunk, ground)
            chunks.append(chunk)
            stats["chunks"] += 1
    return chunks, stats


def write_pack(
    out_dir: Path,
    pack_id: str,
    pack_name: str,
    version: str,
    graph_dict: dict,
    report_dict: dict,
    report_md: str,
    chunks: list[ChunkTerrain],
    frame: LocalFrame,
    bbox: BBox,
    elevation_attribution: str | None,
    water: WaterResult | None = None,
    buildings: BuildingsResult | None = None,
) -> dict[str, Path]:
    """Write the pack folder. Returns the paths written."""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "terrain").mkdir(exist_ok=True)
    attribution = [OSM_ATTRIBUTION]
    if elevation_attribution:
        attribution.append(elevation_attribution)
    manifest = {
        "schema_version": 0,
        "id": pack_id,
        "name": pack_name,
        "version": version,
        "type": "map",
        "engine_api": 0,
        "description": "Generated from OpenStreetMap by tools/osm_import. Roads, junctions, and terrain for one district.",
        "authors": ["Code 430 contributors"],
        "dependencies": [],
        "license": "ODbL-1.0",
        "attribution": attribution,
        "map": {
            "crs": frame.crs,
            "origin": {
                "easting": frame.origin_easting,
                "northing": frame.origin_northing,
                "lat": frame.origin_lat,
                "lon": frame.origin_lon,
            },
            "bbox": bbox.as_list(),
        },
    }
    terrain_index = {
        "schema_version": 0,
        "chunk_size_m": CHUNK_SIZE_M,
        "resolution_m": TERRAIN_RES_M,
        "samples_per_chunk": SAMPLES_PER_CHUNK,
        "encoding": "rgb8: height = (R*256 + G) / 65535 * (max_y - min_y) + min_y; row 0 is the north edge (min z)",
        "chunks": [],
    }
    for chunk in chunks:
        min_y, max_y = float(chunk.heights.min()), float(chunk.heights.max())
        name = f"terrain/chunk_{chunk.cx}_{chunk.cz}.png"
        (out_dir / name).write_bytes(write_rgb8(encode_heights(chunk.heights, min_y, max_y)))
        terrain_index["chunks"].append(
            {
                "cx": chunk.cx,
                "cz": chunk.cz,
                "file": name,
                "min_y": round(min_y, 3),
                "max_y": round(max_y, 3),
            }
        )
    paths = {
        "manifest": out_dir / "pack.json",
        "graph": out_dir / "road_graph.v0.json",
        "terrain": out_dir / "terrain.json",
        "overrides": out_dir / "overrides.json",
        "report_json": out_dir / "validation_report.json",
        "report_md": out_dir / "validation_report.md",
    }
    dump_json(manifest, paths["manifest"])
    dump_json(graph_dict, paths["graph"])
    dump_json(terrain_index, paths["terrain"])
    if not paths["overrides"].exists():
        dump_json({"schema_version": 0, "edges": {}, "nodes": {}}, paths["overrides"])
    dump_json(report_dict, paths["report_json"])
    paths["report_md"].write_text(report_md, encoding="utf-8")
    if water is not None:
        paths["water"] = out_dir / "water.v0.json"
        dump_json(water.to_dict(), paths["water"])
    if buildings is not None:
        paths["buildings"] = out_dir / "buildings.v0.json"
        dump_json(buildings.to_dict(), paths["buildings"])
    return paths


def elevation_attribution_for(source: ElevationSource) -> str | None:
    kind = source.describe().get("kind")
    if kind == "hrdem":
        return HRDEM_ATTRIBUTION
    return None
