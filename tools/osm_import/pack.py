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
from itertools import pairwise
from pathlib import Path

import numpy as np

from osm_import.barriers import BarriersResult
from osm_import.bridges import BridgesResult
from osm_import.buildings import BuildingsResult
from osm_import.config import ImportConfig
from osm_import.elevation import (
    HRDEM_ATTRIBUTION,
    ElevationSource,
    apply_pedestrian_elevation,
    split_pedestrian_under_bridges,
)
from osm_import.export import OSM_ATTRIBUTION, dump_json
from osm_import.graph import RoadGraph
from osm_import.osm_data import BBox
from osm_import.parking import ParkingResult
from osm_import.png import encode_heights, write_rgb8
from osm_import.projection import LocalFrame
from osm_import.services import ServicesResult
from osm_import.underpasses import dig_underpasses
from osm_import.vegetation import VegetationResult
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
BRIDGE_UNDER_DECK_M = 0.7  # ground under a deck stays at least this far below it
BRIDGE_UNDER_DECK_REACH_M = 2.0  # and that rule reaches this far outside the deck edge
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


class ChunkSampler:
    """Bilinear sampling over built chunks, used for pedestrian heights after carving."""

    def __init__(self, chunks: list[ChunkTerrain]) -> None:
        self._by_coord = {(c.cx, c.cz): c for c in chunks}

    def sample(self, x: float, z: float) -> float:
        cx, cz = math.floor(x / CHUNK_SIZE_M), math.floor(z / CHUNK_SIZE_M)
        chunk = self._by_coord.get((cx, cz))
        if chunk is None:
            return 0.0
        fx = min(max((x - chunk.min_x) / TERRAIN_RES_M, 0.0), SAMPLES_PER_CHUNK - 1.001)
        fz = min(max((z - chunk.min_z) / TERRAIN_RES_M, 0.0), SAMPLES_PER_CHUNK - 1.001)
        c0, r0 = int(fx), int(fz)
        tx, tz = fx - c0, fz - r0
        h = chunk.heights
        top = h[r0, c0] * (1 - tx) + h[r0, c0 + 1] * tx
        bottom = h[r0 + 1, c0] * (1 - tx) + h[r0 + 1, c0 + 1] * tx
        return float(top * (1 - tz) + bottom * tz)

    def describe(self) -> dict:
        return {"kind": "chunks"}


def _road_footprints(
    graph: RoadGraph, include_pedestrian: bool = True
) -> tuple[list[tuple], list[tuple]]:
    """(ground segments, bridge segments): (ax, az, bx, bz, ay, by, half_width).
    Pedestrian ways count as ground segments so the terrain meets their surface."""
    ground: list[tuple] = []
    bridges: list[tuple] = []
    for w in graph.pedestrian if include_pedestrian else []:
        if w.kind == "steps" and w.profile != "trench":
            continue
        hw = w.width_m / 2.0
        margin = FLAT_MARGIN_M if w.margin_m is None else w.margin_m
        shoulder = SHOULDER_M if w.shoulder_m is None else w.shoulder_m
        for i in range(len(w.polyline) - 1):
            a, b = w.polyline[i], w.polyline[i + 1]
            ground.append((a[0], a[2], b[0], b[2], a[1], b[1], hw, margin, shoulder))
    for g in graph.gores:  # paved gores (add-road-shoulders 1.4): flat like the roads beside them
        for i in range(len(g.points) - 1):
            a, b = g.points[i], g.points[i + 1]
            hw = max(g.left_m[i], g.left_m[i + 1])
            ground.append((a[0], a[2], b[0], b[2], a[1], b[1], hw, FLAT_MARGIN_M))
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        hw = e.width_m / 2.0
        target = bridges if e.bridge else ground
        if e.tunnel:
            continue
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            target.append((a[0], a[2], b[0], b[2], a[1], b[1], hw, FLAT_MARGIN_M))
    ground.extend(_junction_corners(graph))
    return ground, bridges


JUNCTION_CORNER_HW_M = 0.5  # half width of a corner's flattening line; FLAT_MARGIN_M is added
JUNCTION_CORNER_MAX_HW = 3.0  # a corner reaches at most this many of its widest arm's half widths


def _junction_corners(graph: RoadGraph) -> list[tuple]:
    """Ground segments into each corner of every junction on the ground (update-junction-surfaces).

    A junction's surface fills its corners out to where its roads' edges meet (the game's
    JunctionBuilder), past the ribbons the edge segments flatten under. In a cutting the terrain
    stood above those corners. Each corner between neighbouring arms less than a half turn apart
    gets a segment from the node toward that meeting point, at most JUNCTION_CORNER_MAX_HW of
    its widest arm's half widths out, its far end at the two arms' mean height that far out.
    Forks and merges (no surface), and junctions with a bridge or tunnel arm, are left out.
    """
    out: list[tuple] = []
    inc = graph.incident()
    for nid in sorted(graph.nodes):
        node = graph.nodes[nid]
        eids = inc.get(nid, [])
        if len(eids) < 3 or node.junction_type in ("fork", "merge"):
            continue
        arms = []
        for eid in sorted(eids):
            e = graph.edges[eid]
            if e.bridge or e.tunnel:
                arms = []
                break
            pl = e.polyline if e.from_node == nid else list(reversed(e.polyline))
            dx, dz = pl[1][0] - pl[0][0], pl[1][2] - pl[0][2]
            length = math.hypot(dx, dz)
            if length < 1e-6:
                continue
            arms.append((math.atan2(dz, dx), (dx / length, dz / length), e.width_m / 2.0, pl))
        if len(arms) < 3:
            continue
        arms.sort(key=lambda arm: arm[0])
        nx_, ny_, nz_ = node.position
        for i, a in enumerate(arms):
            b = arms[(i + 1) % len(arms)]
            gap = (b[0] - a[0]) % (2.0 * math.pi)
            if gap <= 0.0 or gap >= math.pi * 0.95:
                continue  # a road running straight on: its own ribbons cover that side
            reach = _corner_reach(a[1], a[2], b[1], b[2], JUNCTION_CORNER_MAX_HW * max(a[2], b[2]))
            half = gap / 2.0
            bx = a[1][0] * math.cos(half) - a[1][1] * math.sin(half)
            bz = a[1][0] * math.sin(half) + a[1][1] * math.cos(half)
            y_far = (_height_at(a[3], reach) + _height_at(b[3], reach)) / 2.0
            out.append(
                (
                    nx_,
                    nz_,
                    nx_ + bx * reach,
                    nz_ + bz * reach,
                    ny_,
                    y_far,
                    JUNCTION_CORNER_HW_M,
                    FLAT_MARGIN_M,
                )
            )
    return out


def _corner_reach(da: tuple, ha: float, db: tuple, hb: float, cap: float) -> float:
    """Distance from the node to where arm a's left edge meets arm b's right edge, capped."""
    # a's counter-clockwise edge: ha * na + s * da; b's clockwise edge: -hb * nb + t * db.
    na = (-da[1], da[0])
    nb = (-db[1], db[0])
    px, pz = ha * na[0], ha * na[1]
    qx, qz = -hb * nb[0], -hb * nb[1]
    det = da[0] * (-db[1]) - da[1] * (-db[0])
    if abs(det) < 1e-9:
        return cap
    s = ((qx - px) * (-db[1]) - (qz - pz) * (-db[0])) / det
    x, z = px + s * da[0], pz + s * da[1]
    return min(math.hypot(x, z), cap)


def _height_at(polyline: list, distance: float) -> float:
    """Road height `distance` metres along `polyline` from its start (its end height past it)."""
    walked = 0.0
    for a, b in pairwise(polyline):
        seg = math.hypot(b[0] - a[0], b[2] - a[2])
        if walked + seg >= distance and seg > 0.0:
            t = (distance - walked) / seg
            return a[1] + (b[1] - a[1]) * t
        walked += seg
    return polyline[-1][1]


def _segments_near(
    segments: list[tuple], min_x: float, min_z: float, size: float, reach: float
) -> list[tuple]:
    out = []
    for seg in segments:
        ax, az, bx, bz, _, _, hw = seg[:7]
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
    """Per cell: distance to the nearest segment centreline, the road height there, and that
    segment's half width plus its flat margin."""
    s = SAMPLES_PER_CHUNK
    dist = np.full((s, s), np.inf, dtype=np.float64)
    road_y = np.zeros((s, s), dtype=np.float64)
    half_w = np.zeros((s, s), dtype=np.float64)
    shoulder = np.full((s, s), SHOULDER_M, dtype=np.float64)
    xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
    zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
    gx, gz = np.meshgrid(xs, zs)
    covered_y = np.full((s, s), np.inf, dtype=np.float64)  # lowest road surface covering the cell
    for seg in _segments_near(segments, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, reach):
        ax, az, bx, bz, ay, by, hw = seg[:7]
        margin = seg[7] if len(seg) > 7 else FLAT_MARGIN_M
        sh = seg[8] if len(seg) > 8 else SHOULDER_M
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        if l2 < 1e-9:
            continue
        t = np.clip(((gx - ax) * dx + (gz - az) * dz) / l2, 0.0, 1.0)
        d = np.hypot(gx - (ax + t * dx), gz - (az + t * dz))
        y_here = ay + (by - ay) * t
        closer = d < dist
        dist = np.where(closer, d, dist)
        road_y = np.where(closer, y_here, road_y)
        half_w = np.where(closer, hw + margin, half_w)
        shoulder = np.where(closer, sh, shoulder)
        # Where two roads cross without sharing a node (an untagged embankment over an
        # underpass), the lower road must own the ground or a wall cuts across it.
        under = d <= hw + margin
        covered_y = np.where(under, np.minimum(covered_y, y_here), covered_y)
    # Any lower covering surface wins, including a road under a curb-height sidewalk.
    lower = covered_y < road_y - 0.02
    road_y = np.where(lower, covered_y, road_y)
    return dist, road_y, half_w, shoulder


def carve_bridges(chunk: ChunkTerrain, bridge_segments: list[tuple]) -> int:
    """Refill cells under bridge decks from their surroundings, then keep the ground under
    the deck itself below it wherever the refill came out above the deck: a deck is a
    bridge because the ground is lower, and a refill seeded from a hillside must not bury
    it. Returns cells changed."""
    dist, road_y, half_w, _sh = _distance_field(chunk, bridge_segments, BRIDGE_CARVE_MARGIN_M)
    half_w = half_w - FLAT_MARGIN_M  # bridge tuples carry the road margin; carving has its own
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
    buried = (dist <= half_w + BRIDGE_UNDER_DECK_REACH_M) & (filled > road_y + 0.05)
    filled = np.where(buried, road_y - BRIDGE_UNDER_DECK_M, filled)
    chunk.heights = filled.astype(np.float32)
    return int(mask.sum())


UNDER_DECK_SLOPE = 1.5  # embankments fall 1 m per 1.5 m from a bridge end
UNDER_DECK_SIDE_M = 8.0  # natural ground is read this far outside the deck edges
UNDER_DECK_GAP_M = 0.3  # ground stays at least this far below the soffit
UNDER_DECK_REACH_M = 5.0  # and that holds this far past the deck edges (closes gaps between decks)


def clamp_under_decks(chunks: list[ChunkTerrain], bridges) -> int:
    """Lowers the ground under every deck (add-bridge-structures 2.2) so no refill ridge rises
    into or close under it: at each station the ground goes down to the lower of an
    embankment slope falling away from the nearest bridge end and the natural ground beside
    the deck there, and never above the soffit. Ground only ever goes down. Returns cells
    changed."""
    by_key = {(c.cx, c.cz): c for c in chunks}
    sampler = ChunkSampler(chunks)
    changed = 0
    for b in bridges.bridges:
        ends = [(e.x, e.y, e.z) for e in b.ends]
        for deck in b.decks:
            pts = deck.points
            for i in range(len(pts) - 1):
                a, c = pts[i], pts[i + 1]
                seg = math.dist((a[0], a[2]), (c[0], c[2]))
                if seg <= 0:
                    continue
                dx, dz = (c[0] - a[0]) / seg, (c[2] - a[2]) / seg
                nx, nz = -dz, dx
                n = max(1, int(seg // 2.0))
                for k in range(n + 1):
                    t = k / n
                    x, y, z = (
                        a[0] + (c[0] - a[0]) * t,
                        a[1] + (c[1] - a[1]) * t,
                        a[2] + (c[2] - a[2]) * t,
                    )
                    lw = deck.left_m[i] + (deck.left_m[i + 1] - deck.left_m[i]) * t
                    rw = deck.right_m[i] + (deck.right_m[i + 1] - deck.right_m[i]) * t
                    reach = max(lw, rw) + UNDER_DECK_REACH_M
                    soffit = y - b.depth_m - UNDER_DECK_GAP_M
                    beside = min(
                        sampler.sample(
                            x + nx * (reach + UNDER_DECK_SIDE_M),
                            z + nz * (reach + UNDER_DECK_SIDE_M),
                        ),
                        sampler.sample(
                            x - nx * (reach + UNDER_DECK_SIDE_M),
                            z - nz * (reach + UNDER_DECK_SIDE_M),
                        ),
                    )
                    if ends:
                        ex, ey, ez = min(ends, key=lambda e: math.dist((e[0], e[2]), (x, z)))
                        slope = ey - b.depth_m - math.dist((ex, ez), (x, z)) / UNDER_DECK_SLOPE
                    else:
                        slope = -math.inf
                    target = min(soffit, max(slope, beside))
                    changed += _lower_disc(by_key, x, z, reach, target)
    return changed


def _lower_disc(by_key: dict, x: float, z: float, radius: float, target: float) -> int:
    n = 0
    for cx in range(
        math.floor((x - radius) / CHUNK_SIZE_M),
        math.floor((x + radius) / CHUNK_SIZE_M) + 1,
    ):
        for cz in range(
            math.floor((z - radius) / CHUNK_SIZE_M),
            math.floor((z + radius) / CHUNK_SIZE_M) + 1,
        ):
            ch = by_key.get((cx, cz))
            if ch is None:
                continue
            c0 = max(0, math.floor((x - radius - ch.min_x) / TERRAIN_RES_M))
            c1 = min(SAMPLES_PER_CHUNK - 1, math.ceil((x + radius - ch.min_x) / TERRAIN_RES_M))
            r0 = max(0, math.floor((z - radius - ch.min_z) / TERRAIN_RES_M))
            r1 = min(SAMPLES_PER_CHUNK - 1, math.ceil((z + radius - ch.min_z) / TERRAIN_RES_M))
            for r in range(r0, r1 + 1):
                for c in range(c0, c1 + 1):
                    px, pz = ch.min_x + c * TERRAIN_RES_M, ch.min_z + r * TERRAIN_RES_M
                    if math.hypot(px - x, pz - z) <= radius and ch.heights[r, c] > target:
                        ch.heights[r, c] = target
                        n += 1
    return n


def flatten_roads(chunk: ChunkTerrain, ground_segments: list[tuple]) -> int:
    """Set terrain under roads to the road surface, blending over the shoulder. Returns cells changed."""
    dist, road_y, half_w, shoulder_w = _distance_field(
        chunk, ground_segments, FLAT_MARGIN_M + SHOULDER_M
    )
    flat_edge = half_w  # half width plus the segment's own margin
    under = dist <= flat_edge
    shoulder = (dist > flat_edge) & (dist <= flat_edge + shoulder_w)
    h = chunk.heights.astype(np.float64)
    target = road_y - ROAD_SURFACE_DROP_M
    h = np.where(under, target, h)
    with np.errstate(invalid="ignore", divide="ignore"):
        t = np.clip((dist - flat_edge) / np.maximum(shoulder_w, 1e-6), 0.0, 1.0)
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
    cfg: ImportConfig | None = None,
) -> tuple[list[ChunkTerrain], dict]:
    _roads_only, bridges = _road_footprints(graph, include_pedestrian=False)
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
            chunks.append(chunk)
            stats["chunks"] += 1
    # Pedestrian heights come from the carved terrain (paths under bridges stay on the ground),
    # then roads and sidewalks flatten the terrain to meet them.
    if cfg is not None:
        sampler = ChunkSampler(chunks)
        apply_pedestrian_elevation(graph, sampler, cfg)
        split_pedestrian_under_bridges(graph)
        stats["underpasses"] = dig_underpasses(graph, sampler.sample)
    ground, _bridges = _road_footprints(graph)
    for chunk in chunks:
        stats["cells_flattened"] += flatten_roads(chunk, ground)
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
    barriers: BarriersResult | None = None,
    parking: ParkingResult | None = None,
    bridges: BridgesResult | None = None,
    vegetation: VegetationResult | None = None,
    services: ServicesResult | None = None,
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
    if barriers is not None:
        paths["barriers"] = out_dir / "barriers.v0.json"
        dump_json(barriers.to_dict(), paths["barriers"])
    if parking is not None:
        paths["parking"] = out_dir / "parking.v0.json"
        dump_json(parking.to_dict(), paths["parking"])
    if bridges is not None:
        paths["bridges"] = out_dir / "bridges.v0.json"
        dump_json(bridges.to_dict(), paths["bridges"])
    if vegetation is not None:
        paths["vegetation"] = out_dir / "vegetation.v0.json"
        dump_json(vegetation.to_dict(), paths["vegetation"])
    if services is not None:
        paths["services"] = out_dir / "services.v0.json"
        dump_json(services.to_dict(), paths["services"])
    return paths


def elevation_attribution_for(source: ElevationSource) -> str | None:
    kind = source.describe().get("kind")
    if kind == "hrdem":
        return HRDEM_ATTRIBUTION
    return None
