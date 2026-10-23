"""Write a data-only map pack: manifest, road graph, per-chunk terrain heightmaps.

Terrain approach: sample the elevation source on a regular grid per 256 m chunk
(65 x 65 samples at 4 m, edges shared with neighbours), carve the DTM's bridge
decks out by refilling cells inside bridge footprints from their surroundings,
then flatten cells under ground-level roads to the road surface with a blended
shoulder, and cells under each junction's outline to the junction surface the game draws
(osm_import.junctions). Each chunk is an RGB PNG (16-bit height in R and G) plus min/max in
terrain.json, because Godot reads only 8-bit PNG channels.
"""

from __future__ import annotations

import json
import math
import warnings
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from osm_import.barriers import BarriersResult
from osm_import.border import BorderResult
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
from osm_import.junctions import JunctionSurface
from osm_import.junctions import build_all as build_junctions
from osm_import.osm_data import BBox
from osm_import.parking import ParkingResult
from osm_import.png import encode_heights, write_rgb8
from osm_import.projection import LocalFrame
from osm_import.services import ServicesResult
from osm_import.underpasses import dig_underpasses
from osm_import.vegetation import VegetationResult
from osm_import.water import WaterResult
from osm_import.yards import YardsResult

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


PEDESTRIAN = "ped"  # marks a pedestrian way's ground segment (its 10th field)
COVER_MARGIN_M = 0.5  # a surface covers the cells this close to its ribbon


def _road_footprints(
    graph: RoadGraph, include_pedestrian: bool = True
) -> tuple[list[tuple], list[tuple]]:
    """(ground segments, bridge segments): (ax, az, bx, bz, ay, by, half_width[, margin
    [, shoulder[, PEDESTRIAN]]]). Pedestrian ways count as ground segments so the terrain
    meets their surface, but a road owns the ground beside it (see _distance_field). The
    ground under junctions is the junctions' own (ground_junctions, _junction_field)."""
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
            ground.append((a[0], a[2], b[0], b[2], a[1], b[1], hw, margin, shoulder, PEDESTRIAN))
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
    return ground, bridges


def ground_junctions(graph: RoadGraph) -> list[JunctionSurface]:
    """The junction surfaces the terrain follows (update-junction-ground): every junction the
    game draws (osm_import.junctions, the port of JunctionBuilder) whose arms are all on the
    ground. One with a bridge arm stands at the deck's height, and one with a tunnel arm at
    the portal: the ground there is the abutment's or the hillside's, and the ribbons cover
    the node as before."""
    return [
        j
        for j in build_junctions(graph).values()
        if len(j.polygon) >= 3 and not j.has_bridge_arm and not j.has_tunnel_arm
    ]


JUNCTION_FINE_RES_M = 1.0  # the junction surface is read this finely to find its low points
# Under an arm's ribbon the pooled height may go this far below the arm: enough to take most of
# the surface's dips between cells, less than a wheel trap (EdgeDropReport.DROP_M). Centretown
# 2026-10-23: 0 gave 615 wheel traps and 42 junctions with grass through the surface (1.9%),
# 0.15 gave 672 and 16 (0.7%), 0.2 gave 699 and 14.
JUNCTION_FLOOR_SLACK_M = 0.15


def _junction_field(
    chunk: ChunkTerrain, junctions: list[JunctionSurface], reach: float
) -> tuple[np.ndarray, np.ndarray]:
    """Per cell: distance to the nearest junction outline (0 inside it) and the height the
    terrain takes under the junction there. Outside an outline that is the lower of the
    outline's height at its nearest point and at the point the ray from the node through the
    cell leaves the outline (the surface's own edge there), which the flat margin and shoulder
    blend out from. Inside the outline, it is the lowest the surface gets within a cell of
    the point: the terrain interpolates between cells 4 m apart, and the surface (the
    triangulated outline the game draws, which JunctionReport samples) is not flat across a
    cell where two arms meet at different heights, so a cell set to the surface right at it
    would carry the terrain through the surface between cells. Under an arm's ribbon the
    pooled height stops JUNCTION_FLOOR_SLACK_M below the arm, and the margin is not pooled at
    all: cells beside an arm's edge pooled down toward a lower arm's cap left a drop at that
    edge."""
    s = SAMPLES_PER_CHUNK
    dist, y_at, floor = _junction_surface(chunk, junctions, reach, TERRAIN_RES_M, s)
    inside = dist <= 0.0
    if not inside.any():
        return dist, y_at
    step = int(TERRAIN_RES_M / JUNCTION_FINE_RES_M)
    fine_s = (s - 1) * step + 1
    f_dist, f_y, _f = _junction_surface(chunk, junctions, reach, JUNCTION_FINE_RES_M, fine_s)
    f_y = np.where(f_dist <= reach, f_y, np.inf)
    padded = np.pad(f_y, step, mode="constant", constant_values=np.inf)
    low = np.full((s, s), np.inf)
    for dr in range(2 * step + 1):
        for dc in range(2 * step + 1):
            low = np.minimum(low, padded[dr : dr + fine_s : step, dc : dc + fine_s : step])
    y = np.where(inside & np.isfinite(low), np.minimum(y_at, low), y_at)
    return dist, np.maximum(y, floor)


def _junction_surface(
    chunk: ChunkTerrain, junctions: list[JunctionSurface], reach: float, res: float, s: int
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The junction surfaces on an s x s grid of `res` metres from the chunk's corner: per
    point, the distance to the nearest outline (0 inside), the surface height there (inside:
    the game's triangulation of the outline; outside: the lower of the outline's nearest point
    and where the ray from the node through the point crosses the outline, so the margin never
    stands above the surface's edge beside it), and a floor the pooled height may not go under
    (the arm's ribbon where the point is under one, -inf elsewhere)."""
    dist = np.full((s, s), np.inf, dtype=np.float64)
    y_out = np.zeros((s, s), dtype=np.float64)
    floor = np.full((s, s), -np.inf, dtype=np.float64)
    x0, z0 = chunk.min_x, chunk.min_z
    for j in junctions:
        bx0, bz0, bx1, bz1 = j.bounds()
        c0 = max(0, math.floor((bx0 - reach - x0) / res))
        c1 = min(s - 1, math.ceil((bx1 + reach - x0) / res))
        r0 = max(0, math.floor((bz0 - reach - z0) / res))
        r1 = min(s - 1, math.ceil((bz1 + reach - z0) / res))
        if c0 > c1 or r0 > r1:
            continue
        gx, gz = np.meshgrid(x0 + np.arange(c0, c1 + 1) * res, z0 + np.arange(r0, r1 + 1) * res)
        poly = np.asarray(j.polygon, dtype=np.float64)
        hs = np.asarray(j.heights, dtype=np.float64)
        n = len(poly)
        d_edge = np.full(gx.shape, np.inf)
        y_edge = np.zeros(gx.shape)
        inside = np.zeros(gx.shape, dtype=bool)
        cx, cy, cz = j.centre
        rx, rz = gx - cx, gz - cz
        t_hit = np.full(gx.shape, np.inf)
        y_hit = np.zeros(gx.shape)
        for i in range(n):
            ax, az = poly[i]
            bx, bz = poly[(i + 1) % n]
            ex, ez = bx - ax, bz - az
            l2 = ex * ex + ez * ez
            if l2 < 1e-12:
                continue
            # Nearest point on the edge, and the outline's height there.
            t = np.clip(((gx - ax) * ex + (gz - az) * ez) / l2, 0.0, 1.0)
            d = np.hypot(gx - (ax + t * ex), gz - (az + t * ez))
            closer = d < d_edge
            d_edge = np.where(closer, d, d_edge)
            y_edge = np.where(closer, hs[i] + (hs[(i + 1) % n] - hs[i]) * t, y_edge)
            # Crossing number for the inside test.
            if az != bz:
                crosses = (az > gz) != (bz > gz)
                x_at = ax + (gz - az) * ex / ez
                inside ^= crosses & (gx < x_at)
            # The ray from the node through the cell meets this edge at t_ray (1 at the cell).
            denom = rx * ez - rz * ex
            with np.errstate(divide="ignore", invalid="ignore"):
                s_edge = ((ax - cx) * rz - (az - cz) * rx) / denom
                t_ray = ((ax - cx) * ez - (az - cz) * ex) / denom
                hit = (np.abs(denom) > 1e-9) & (s_edge >= 0.0) & (s_edge <= 1.0)
                hit &= (t_ray > 0.0) & (t_ray < t_hit)
                t_hit = np.where(hit, t_ray, t_hit)
                y_hit = np.where(hit, hs[i] + (hs[(i + 1) % n] - hs[i]) * s_edge, y_hit)
        with np.errstate(divide="ignore", invalid="ignore"):
            fan = np.where(np.isfinite(t_hit), cy + (y_hit - cy) / t_hit, cy)
        # The surface the game draws: its triangulation of the outline, with the fan from the
        # node (what JunctionReport falls back to) where a point falls in no triangle.
        tri_y = np.full(gx.shape, np.inf)
        for ia, ib, ic in j.triangles():
            (ax, az), (bx, bz), (qx, qz) = poly[ia], poly[ib], poly[ic]
            det = (bx - ax) * (qz - az) - (qx - ax) * (bz - az)
            if abs(det) < 1e-9:
                continue
            wb = ((gx - ax) * (qz - az) - (qx - ax) * (gz - az)) / det
            wc = ((bx - ax) * (gz - az) - (gx - ax) * (bz - az)) / det
            wa = 1.0 - wb - wc
            in_tri = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6)
            tri_y = np.where(
                in_tri, np.minimum(tri_y, wa * hs[ia] + wb * hs[ib] + wc * hs[ic]), tri_y
            )
        y_in = np.where(np.isfinite(tri_y), tri_y, fan)
        j_dist = np.where(inside, 0.0, d_edge)
        y_edge = np.where(np.isfinite(t_hit), np.minimum(y_edge, y_hit), y_edge)
        j_y = np.where(inside, y_in, y_edge)
        # Under an arm's ribbon the terrain is never pooled below the arm (or below the
        # surface itself, where the arm's ribbon rises above it at a crest): the ground beside
        # the arm's edge must meet the arm, or a wheel leaving it drops in.
        arm_y = np.full(gx.shape, -np.inf)
        for ax, az, bx, bz, ay, by, hw in j.arm_segments:
            ex, ez = bx - ax, bz - az
            l2 = ex * ex + ez * ez
            if l2 < 1e-9:
                continue
            t = np.clip(((gx - ax) * ex + (gz - az) * ez) / l2, 0.0, 1.0)
            d = np.hypot(gx - (ax + t * ex), gz - (az + t * ez))
            arm_y = np.where(d <= hw, np.maximum(arm_y, ay + (by - ay) * t), arm_y)
        arm_y = np.minimum(arm_y, j_y) - JUNCTION_FLOOR_SLACK_M
        win_d = dist[r0 : r1 + 1, c0 : c1 + 1]
        win_y = y_out[r0 : r1 + 1, c0 : c1 + 1]
        win_f = floor[r0 : r1 + 1, c0 : c1 + 1]
        closer = j_dist < win_d
        dist[r0 : r1 + 1, c0 : c1 + 1] = np.where(closer, j_dist, win_d)
        y_out[r0 : r1 + 1, c0 : c1 + 1] = np.where(closer, j_y, win_y)
        floor[r0 : r1 + 1, c0 : c1 + 1] = np.where(closer, arm_y, win_f)
    return dist, y_out, floor


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
    chunk: ChunkTerrain,
    segments: list[tuple],
    reach: float,
    junctions: list[JunctionSurface] | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Per cell: distance to the nearest surface (a segment centreline, or a junction outline:
    0 inside it), the surface height there, the flat edge (a segment's half width plus its
    flat margin; a junction's margin) and the shoulder width beyond it.

    A junction owns the ground inside its outline and FLAT_MARGIN_M around it, ahead of its
    arms and of any path (update-junction-ground): where two arms meet at different heights
    the corner between them can only follow one of them, which left a wheel trap at one arm's
    edge or grass through the surface at the other's. Beyond its margin the junction is just
    the nearest surface, blending like a road's shoulder, and a road's own zone comes first.

    A road owns the ground within its own half width plus margin and shoulder, ahead of any
    nearer sidewalk or path: a sidewalk lower than the road beside it (a corner where a street
    climbs away from the junction) must not pull the ground down at the road's edge, where a
    wheel would drop in. Only a surface the cell is actually under (its ribbon plus COVER_MARGIN_M)
    can lower it below the nearest one."""
    s = SAMPLES_PER_CHUNK
    dist = np.full((s, s), np.inf, dtype=np.float64)
    road_y = np.zeros((s, s), dtype=np.float64)
    half_w = np.zeros((s, s), dtype=np.float64)
    shoulder = np.full((s, s), SHOULDER_M, dtype=np.float64)
    xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
    zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
    gx, gz = np.meshgrid(xs, zs)
    covered_y = np.full((s, s), np.inf, dtype=np.float64)  # lowest surface over the cell
    under_path = np.zeros((s, s), dtype=bool)  # under a pedestrian way's ribbon
    # The nearest road (not a pedestrian way), kept apart so it can own the ground beside it.
    r_dist = np.full((s, s), np.inf, dtype=np.float64)
    r_y = np.zeros((s, s), dtype=np.float64)
    r_half = np.zeros((s, s), dtype=np.float64)
    r_sh = np.full((s, s), SHOULDER_M, dtype=np.float64)
    for seg in _segments_near(segments, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, reach):
        ax, az, bx, bz, ay, by, hw = seg[:7]
        margin = seg[7] if len(seg) > 7 else FLAT_MARGIN_M
        sh = seg[8] if len(seg) > 8 else SHOULDER_M
        is_road = not (len(seg) > 9 and seg[9] == PEDESTRIAN)
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
        if is_road:
            rc = d < r_dist
            r_dist = np.where(rc, d, r_dist)
            r_y = np.where(rc, y_here, r_y)
            r_half = np.where(rc, hw + margin, r_half)
            r_sh = np.where(rc, sh, r_sh)
        # Only a surface the cell is under can lower it below the nearest one: where two roads
        # cross without sharing a node (an untagged embankment over an underpass), the lower
        # road owns the ground under it; a lower road or sidewalk merely nearby does not pull
        # the ground down at another road's edge, where a wheel would drop in.
        under = d <= hw + COVER_MARGIN_M
        covered_y = np.where(under, np.minimum(covered_y, y_here), covered_y)
        if not is_road:
            under_path |= under
    # Within a road's own flat zone, and its shoulder where no path's ribbon covers the cell:
    # that road, not a nearer path or junction.
    owned = (r_dist <= r_half) | ((r_dist <= r_half + SHOULDER_M) & ~under_path)
    dist = np.where(owned, r_dist, dist)
    road_y = np.where(owned, r_y, road_y)
    half_w = np.where(owned, r_half, half_w)
    shoulder = np.where(owned, r_sh, shoulder)
    if junctions:
        j_dist, j_y = _junction_field(chunk, junctions, reach)
        take = (j_dist <= FLAT_MARGIN_M) | ((j_dist < dist) & ~owned)
        dist = np.where(take, j_dist, dist)
        road_y = np.where(take, j_y, road_y)
        half_w = np.where(take, FLAT_MARGIN_M, half_w)
        shoulder = np.where(take, SHOULDER_M, shoulder)
    # A lower surface the cell is under wins, including a road under a curb-height sidewalk.
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
            fences = _deck_end_fences(pts, ends)
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
                    changed += _lower_disc(by_key, x, z, reach, target, fences)
    return changed


DECK_END_MATCH_M = 3.0  # a deck strip's end this close to one of its bridge's ends meets the ground


def _deck_end_fences(pts: list, ends: list) -> list[tuple[float, float, float, float]]:
    """(x, z, ux, uz) per end of a deck strip that meets the ground (one of its bridge's
    `ends`): the end, and the direction into the deck from it. The lowering under the deck
    stops short of these, or it digs a pit beside the approach road (Mill Bridge Road and
    Bridge Street on the proving ground). A strip ending in mid-air (an infill strip, a split
    carriageway) has no fence there."""
    fences: list = []
    for end, nxt in ((pts[0], pts[1]), (pts[-1], pts[-2])) if len(pts) >= 2 else ():
        if not any(math.dist((e[0], e[2]), (end[0], end[2])) <= DECK_END_MATCH_M for e in ends):
            continue
        dx, dz = nxt[0] - end[0], nxt[2] - end[2]
        length = math.hypot(dx, dz)
        if length > 0:
            fences.append((end[0], end[2], dx / length, dz / length))
    return fences


def _near_an_end(px: float, pz: float, fences: list) -> bool:
    """Behind a deck end, or within one terrain cell in front of it: the grid interpolates
    between cells 4 m apart, so a cell lowered just inside the end would drag the approach
    road's edge down with it. The first cell under the deck is the abutment's."""
    return any((px - ex) * ux + (pz - ez) * uz < TERRAIN_RES_M for ex, ez, ux, uz in fences)


def _lower_disc(
    by_key: dict, x: float, z: float, radius: float, target: float, fences: list | None = None
) -> int:
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
                    if math.hypot(px - x, pz - z) > radius or ch.heights[r, c] <= target:
                        continue
                    if fences and _near_an_end(px, pz, fences):
                        continue
                    ch.heights[r, c] = target
                    n += 1
    return n


def flatten_roads(
    chunk: ChunkTerrain,
    ground_segments: list[tuple],
    junctions: list[JunctionSurface] | None = None,
) -> int:
    """Set terrain under roads and junctions to their surfaces, blending over the shoulder.
    Returns cells changed."""
    dist, road_y, half_w, shoulder_w = _distance_field(
        chunk, ground_segments, FLAT_MARGIN_M + SHOULDER_M, junctions
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
    junctions = ground_junctions(graph)
    stats["junctions_flattened"] = len(junctions)
    for chunk in chunks:
        stats["cells_flattened"] += flatten_roads(chunk, ground, junctions)
    stats["path_points_lifted"] = lift_buried_paths(graph, ChunkSampler(chunks).sample)
    stats["cells_cut_under_paths"] = cut_under_deep_paths(
        chunks, graph, ChunkSampler(chunks).sample
    )
    return chunks, stats


def restore_road_beds(chunks: list[ChunkTerrain], graph: RoadGraph) -> int:
    """Puts the ground within every ground-level road's and junction's flat zone back to its
    bed (the surface less ROAD_SURFACE_DROP_M) wherever a later step moved it, except under
    a deck at the deck's own height (the abutment's ground). Returns cells changed."""
    ground, bridges = _road_footprints(graph, include_pedestrian=False)
    junctions = ground_junctions(graph)
    changed = 0
    for chunk in chunks:
        dist, road_y, half_w, _sh = _distance_field(chunk, ground, FLAT_MARGIN_M, junctions)
        target = road_y - ROAD_SURFACE_DROP_M
        # Under a deck only a road passing beneath it gets its bed back: the ground under a
        # bridge end is the abutment's, not the approach road's (the 417's approach would
        # otherwise raise the ground under the deck onto Metcalfe Street beside it). "Under"
        # means alongside the deck, not past its ends, where the approach road's own bed holds.
        under_deck, deck_y = _under_decks(chunk, bridges)
        too_high = under_deck & (target > deck_y - BRIDGE_UNDER_DECK_M)
        # Set, not just raise: refill left standing near a deck end (the deck-end fence keeps
        # it so the approach road's edge isn't dragged down) must not stay over a lower road.
        low = (dist <= half_w) & (np.abs(chunk.heights - target) > 0.005) & ~too_high
        if low.any():
            chunk.heights = np.where(low, target, chunk.heights).astype(np.float32)
            changed += int(low.sum())
        # Under a deck, a road passing beneath it owns its flat zone even where a road at the
        # deck's height is nearer (Metcalfe beside the 417's abutment): the ground goes down
        # to the lowest such bed.
        bed = _lowest_bed(chunk, ground, SHOULDER_M) - ROAD_SURFACE_DROP_M
        sink = under_deck & (bed < deck_y - BRIDGE_UNDER_DECK_M) & (chunk.heights > bed + 0.005)
        if sink.any():
            chunk.heights = np.where(sink, bed, chunk.heights).astype(np.float32)
            changed += int(sink.sum())
    return changed


def _lowest_bed(chunk: ChunkTerrain, segments: list[tuple], beyond: float = 0.0) -> np.ndarray:
    """Per cell: the lowest road surface whose flat zone (half width plus margin, plus
    `beyond`) reaches it, inf where none does. Under a deck a road passing beneath owns its
    shoulder too: the 417's abutment lands beside Metcalfe just past its flat zone, and the
    refill the deck-end fence keeps there stood as a step beside the street."""
    s = SAMPLES_PER_CHUNK
    xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
    zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
    gx, gz = np.meshgrid(xs, zs)
    low = np.full((s, s), np.inf, dtype=np.float64)
    reach = FLAT_MARGIN_M + beyond
    for seg in _segments_near(segments, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, reach):
        ax, az, bx, bz, ay, by, hw = seg[:7]
        margin = seg[7] if len(seg) > 7 else FLAT_MARGIN_M
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        if l2 < 1e-9:
            continue
        t = np.clip(((gx - ax) * dx + (gz - az) * dz) / l2, 0.0, 1.0)
        d = np.hypot(gx - (ax + t * dx), gz - (az + t * dz))
        low = np.where(d <= hw + margin + beyond, np.minimum(low, ay + (by - ay) * t), low)
    return low


def _under_decks(chunk: ChunkTerrain, bridges: list[tuple]) -> tuple[np.ndarray, np.ndarray]:
    """Per cell: whether it is beside a deck (within its half width plus
    BRIDGE_UNDER_DECK_REACH_M, alongside the deck, not past its ends), and the lowest such
    deck's height there."""
    s = SAMPLES_PER_CHUNK
    xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
    zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
    gx, gz = np.meshgrid(xs, zs)
    under = np.zeros((s, s), dtype=bool)
    deck_y = np.full((s, s), np.inf, dtype=np.float64)
    for seg in _segments_near(
        bridges, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, BRIDGE_UNDER_DECK_REACH_M
    ):
        ax, az, bx, bz, ay, by, hw = seg[:7]
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        if l2 < 1e-9:
            continue
        t = ((gx - ax) * dx + (gz - az) * dz) / l2
        inside = (t >= 0.0) & (t <= 1.0)
        tc = np.clip(t, 0.0, 1.0)
        d = np.hypot(gx - (ax + tc * dx), gz - (az + tc * dz))
        here = inside & (d <= hw + BRIDGE_UNDER_DECK_REACH_M)
        under |= here
        deck_y = np.where(here, np.minimum(deck_y, ay + (by - ay) * tc), deck_y)
    return under, deck_y


BURIED_M = 0.05  # a path point this far under the finished terrain is lifted onto it
LIFT_ABOVE_M = 0.02


LIFT_MAX_M = 0.5  # buried deeper than this, the ground is someone else's: cut it, don't climb it


def _liftable(w) -> bool:
    return not (w.covered or w.profile in ("tunnel", "trench") or w.kind == "steps")


def lift_buried_paths(graph: RoadGraph, sample) -> int:
    """Lifts path points the finished terrain buries by a little (up to LIFT_MAX_M) back onto
    it. A road owns the ground beside it (_distance_field), so a sidewalk a little lower than
    that road, at a corner where the street climbs away from the junction, would otherwise run
    under the grass. A point buried deeper is under an embankment or a higher road's ground
    (a street's sidewalk beside the 417's abutment at Metcalfe): it keeps its height, and
    cut_under_deep_paths lowers the ground along it instead. Covered ways, dug passages,
    trenches and steps keep their heights. Returns the points lifted."""
    lifted = 0
    for w in graph.pedestrian:
        if not _liftable(w):
            continue
        pts = []
        for x, y, z in w.polyline:
            g = sample(x, z)
            if not math.isnan(g) and BURIED_M < g - y <= LIFT_MAX_M:
                y = g + LIFT_ABOVE_M
                lifted += 1
            pts.append((x, y, z))
        w.polyline = pts
    return lifted


def cut_under_deep_paths(chunks: list[ChunkTerrain], graph: RoadGraph, sample) -> int:
    """Lowers the ground along path segments buried more than LIFT_MAX_M to the path, within
    its ribbon plus COVER_MARGIN_M, never under a road's ribbon or a junction. Only lowers.
    Returns cells changed."""
    segs = []
    for w in graph.pedestrian:
        if not _liftable(w):
            continue
        hw = w.width_m / 2.0
        for a, b in zip(w.polyline, w.polyline[1:]):
            if any(sample(p[0], p[2]) - p[1] > LIFT_MAX_M for p in (a, b)):
                segs.append((a[0], a[2], b[0], b[2], a[1], b[1], hw, COVER_MARGIN_M))
    if not segs:
        return 0
    roads, _bridges = _road_footprints(graph, include_pedestrian=False)
    junctions = ground_junctions(graph)
    changed = 0
    for chunk in chunks:
        if not _segments_near(segs, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, COVER_MARGIN_M):
            continue
        d_p, y_p, half_p, _s = _distance_field(chunk, segs, COVER_MARGIN_M)
        d_r, _yr, half_r, _sr = _distance_field(chunk, roads, COVER_MARGIN_M)
        road_ribbon = d_r <= half_r - FLAT_MARGIN_M + COVER_MARGIN_M
        d_j, _yj = _junction_field(chunk, junctions, COVER_MARGIN_M)
        road_ribbon |= d_j <= COVER_MARGIN_M
        target = y_p - ROAD_SURFACE_DROP_M
        cut = (d_p <= half_p) & ~road_ribbon & (chunk.heights > target)
        if cut.any():
            chunk.heights = np.where(cut, target, chunk.heights).astype(np.float32)
            changed += int(cut.sum())
    return changed


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
    spawn: dict | None = None,
    yards: YardsResult | None = None,
    build: dict | None = None,
    border: tuple[int, int, int, int] | None = None,
    license: dict | None = None,
    border_result: BorderResult | None = None,
) -> dict[str, Path]:
    """Write the pack folder. Returns the paths written. `spawn` ({x, z, heading_deg}) puts a
    fixed start on the manifest for packs whose author chose one. `build` ({importer, inputs})
    records which importer commit and which input snapshots made the pack. `license`
    ({license, attribution, description}) is for a pack that isn't OpenStreetMap data, such as
    a generated test district: it replaces the ODbL licence and the OpenStreetMap credit."""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "terrain").mkdir(exist_ok=True)
    license = license or {}
    attribution = list(license.get("attribution") or [OSM_ATTRIBUTION])
    if elevation_attribution:
        attribution.append(elevation_attribution)
    manifest = {
        "schema_version": 0,
        "id": pack_id,
        "name": pack_name,
        "version": version,
        "type": "map",
        "engine_api": 0,
        "description": license.get(
            "description",
            "Generated from OpenStreetMap by tools/osm_import. Roads, junctions, and terrain for one district.",
        ),
        "authors": ["Code 430 contributors"],
        "dependencies": [],
        "license": license.get("license", "ODbL-1.0"),
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
    if border is not None:
        manifest["map"]["border"] = {"chunks": list(border)}
    if build:
        manifest["build"] = build
    if spawn:
        manifest["map"]["spawn"] = {
            "x": float(spawn["x"]),
            "z": float(spawn["z"]),
            "heading_deg": float(spawn.get("heading_deg", 0.0)),
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
    # A hand-placed turf in the overrides (add-hostile-gang 1.2) becomes the pack's turf file,
    # so a city pack can give a faction its ground without a generator; a turf extra copied
    # after this call replaces it.
    overrides = json.loads(paths["overrides"].read_text(encoding="utf-8"))
    if (
        isinstance(overrides, dict)
        and isinstance(overrides.get("turf"), list)
        and overrides["turf"]
    ):
        paths["turf"] = out_dir / "turf.v0.json"
        dump_json({"schema_version": 0, "turfs": overrides["turf"]}, paths["turf"])
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
    if yards is not None:
        paths["yards"] = out_dir / "yards.v0.json"
        dump_json(yards.to_dict(), paths["yards"])
    if border_result is not None:
        paths["border"] = out_dir / "border.v0.json"
        dump_json(border_result.to_dict(), paths["border"])
    return paths


def elevation_attribution_for(source: ElevationSource) -> str | None:
    kind = source.describe().get("kind")
    if kind == "hrdem":
        return HRDEM_ATTRIBUTION
    return None
