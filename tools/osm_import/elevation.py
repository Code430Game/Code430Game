"""Elevation: sample a DEM for ground height, lift bridges, sink tunnels, limit grades.

Approach:
1. An ElevationSource gives ground height at local (x, z). HrdemSource reads a
   window of NRCan's HRDEM cloud-optimized GeoTIFF, reprojects it onto a local
   UTM grid, and caches that grid on disk (gitignored). SyntheticSource is an
   analytic surface for tests. FlatSource is y = 0.
2. The DTM keeps bridge decks as terrain, so vertices of lower roads inside a
   bridge footprint are refilled from their neighbours instead of sampled.
3. Bridge and tunnel edges form chains anchored at the nodes where they meet
   ground-level roads. A chain's deck runs between its anchors' heights and the
   whole chain rises (bridge) or sinks (tunnel) by the largest clearance
   violation against roads crossing it, clearance being
   max(1, |layer|) x bridge_clearance_m. Those vertices are "fixed"; all others
   are "free".
4. Grade limits: a vertex pair along an edge may differ by at most
   max_grade x distance. Fixed vertices propagate lower and upper bounds to free
   vertices (a Dijkstra-like relaxation), free vertices are clamped, and a few
   smoothing passes handle steep natural terrain between free vertices.
Shared nodes are one vertex, so profiles stay continuous across junctions.
"""

from __future__ import annotations

import hashlib
import heapq
import json
import logging
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

import numpy as np

from osm_import.config import ImportConfig
from osm_import.graph import RoadGraph
from osm_import.osm_data import BBox
from osm_import.projection import Projector

log = logging.getLogger(__name__)

HRDEM_DTM_2M_URL = (
    "https://canelevation-dem.s3.ca-central-1.amazonaws.com/hrdem-mosaic-2m/9_2-mosaic-2m-dtm.tif"
)
HRDEM_LICENSE = "Open Government Licence - Canada"
HRDEM_ATTRIBUTION = "Elevation: High Resolution Digital Elevation Model (HRDEM), Natural Resources Canada, Open Government Licence - Canada"
DEFAULT_GRID_RES_M = 2.0
DEFAULT_MARGIN_M = 300.0
SMOOTHING_PASSES = 50
SMOOTHING_EPSILON = 0.001


class ElevationSource(Protocol):
    """Ground height at local coordinates."""

    def sample(self, x: float, z: float) -> float: ...

    def describe(self) -> dict: ...


@dataclass
class FlatSource:
    height: float = 0.0

    def sample(self, x: float, z: float) -> float:
        return self.height

    def describe(self) -> dict:
        return {"kind": "flat", "height": self.height}


@dataclass
class SyntheticSource:
    """Gentle slope plus a hill, in metres. Deterministic, for tests and demos."""

    base: float = 60.0
    slope_x: float = 0.01
    hill_height: float = 12.0
    hill_radius: float = 250.0

    def sample(self, x: float, z: float) -> float:
        r2 = (x * x + z * z) / (self.hill_radius * self.hill_radius)
        return self.base + self.slope_x * x + self.hill_height * math.exp(-r2)

    def describe(self) -> dict:
        return {
            "kind": "synthetic",
            "base": self.base,
            "slope_x": self.slope_x,
            "hill_height": self.hill_height,
        }


@dataclass
class GridSource:
    """Bilinear sampling of a regular local grid. Row 0 is the northern edge (smallest z)."""

    heights: np.ndarray
    min_x: float
    min_z: float
    res: float
    meta: dict = field(default_factory=dict)

    def sample(self, x: float, z: float) -> float:
        rows, cols = self.heights.shape
        fx = (x - self.min_x) / self.res
        fz = (z - self.min_z) / self.res
        fx = min(max(fx, 0.0), cols - 1.001)
        fz = min(max(fz, 0.0), rows - 1.001)
        c0, r0 = int(fx), int(fz)
        tx, tz = fx - c0, fz - r0
        h = self.heights
        top = h[r0, c0] * (1 - tx) + h[r0, c0 + 1] * tx
        bottom = h[r0 + 1, c0] * (1 - tx) + h[r0 + 1, c0 + 1] * tx
        return float(top * (1 - tz) + bottom * tz)

    def describe(self) -> dict:
        d = dict(self.meta)
        d.update(
            {
                "kind": d.get("kind", "grid"),
                "grid_res_m": self.res,
                "grid_shape": list(self.heights.shape),
            }
        )
        return d


def hrdem_source(
    bbox: BBox,
    proj: Projector,
    cache_dir: Path,
    url: str = HRDEM_DTM_2M_URL,
    res: float = DEFAULT_GRID_RES_M,
    margin: float = DEFAULT_MARGIN_M,
) -> GridSource:
    """Load (or fetch and cache) the HRDEM grid for bbox in the local frame."""
    import rasterio
    from rasterio.transform import from_origin
    from rasterio.warp import Resampling, reproject

    min_x, min_z, max_x, max_z = proj.bbox_local(bbox)
    min_x, min_z = (
        math.floor((min_x - margin) / res) * res,
        math.floor((min_z - margin) / res) * res,
    )
    max_x, max_z = math.ceil((max_x + margin) / res) * res, math.ceil((max_z + margin) / res) * res
    cols, rows = int((max_x - min_x) / res), int((max_z - min_z) / res)
    key = hashlib.sha1(
        f"{url}|{proj.frame.to_dict()}|{min_x},{min_z},{max_x},{max_z},{res}".encode()
    ).hexdigest()[:16]
    cache_dir.mkdir(parents=True, exist_ok=True)
    npy_path, meta_path = cache_dir / f"dem_{key}.npy", cache_dir / f"dem_{key}.meta.json"
    if npy_path.is_file() and meta_path.is_file():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        log.info("using cached DEM grid %s", npy_path.name)
        return GridSource(np.load(npy_path), min_x, min_z, res, meta)

    # Destination grid in UTM: x east = easting - origin_e; z south = origin_n - northing.
    frame = proj.frame
    dst_transform = from_origin(
        frame.origin_easting + min_x, frame.origin_northing - min_z, res, res
    )
    dst = np.full((rows, cols), np.nan, dtype=np.float32)
    log.info("fetching HRDEM window from %s", url)
    with rasterio.open(url) as src:
        from rasterio.warp import transform_bounds
        from rasterio.windows import from_bounds

        b = transform_bounds(
            "EPSG:32618",
            src.crs,
            frame.origin_easting + min_x,
            frame.origin_northing - max_z,
            frame.origin_easting + max_x,
            frame.origin_northing - min_z,
        )
        pad = 4 * res
        win = from_bounds(b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad, transform=src.transform)
        data = src.read(1, window=win)
        src_transform = src.window_transform(win)
        reproject(
            source=data,
            destination=dst,
            src_transform=src_transform,
            src_crs=src.crs,
            src_nodata=src.nodata,
            dst_transform=dst_transform,
            dst_crs="EPSG:32618",
            dst_nodata=np.nan,
            resampling=Resampling.bilinear,
        )
        source_desc = {
            "url": url,
            "crs": str(src.crs),
            "native_res_m": src.res[0],
            "nodata": src.nodata,
        }
    nan_count = int(np.isnan(dst).sum())
    if nan_count:
        log.warning("DEM grid has %d nodata cells; filling with nearest valid value", nan_count)
        dst = _fill_nan(dst)
    from datetime import UTC, datetime

    meta = {
        "kind": "hrdem",
        "source": source_desc,
        "license": HRDEM_LICENSE,
        "attribution": HRDEM_ATTRIBUTION,
        "fetched_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "nodata_filled": nan_count,
        "grid_origin_local": [min_x, min_z],
    }
    np.save(npy_path, dst)
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return GridSource(dst, min_x, min_z, res, meta)


def _fill_nan(arr: np.ndarray) -> np.ndarray:
    """Replace NaNs by the nearest valid value (simple iterative dilation)."""
    out = arr.copy()
    for _ in range(64):
        mask = np.isnan(out)
        if not mask.any():
            break
        shifted = [np.roll(out, s, axis=a) for a in (0, 1) for s in (1, -1)]
        stack = np.stack(shifted)
        with np.errstate(all="ignore"):
            fill = np.nanmean(stack, axis=0)
        out[mask] = fill[mask]
    return np.nan_to_num(out, nan=float(np.nanmean(out)))


@dataclass
class ElevationStats:
    min_y: float = 0.0
    max_y: float = 0.0
    fixed_vertices: int = 0
    free_vertices: int = 0
    bound_conflicts: int = 0
    anchorless_spans: int = 0
    contaminated_vertices: int = 0
    vertices_clamped: int = 0
    max_residual_grade: float = 0.0
    edges_over_grade: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "min_y": round(self.min_y, 3),
            "max_y": round(self.max_y, 3),
            "fixed_vertices": self.fixed_vertices,
            "free_vertices": self.free_vertices,
            "bound_conflicts": self.bound_conflicts,
            "anchorless_spans": self.anchorless_spans,
            "contaminated_vertices": self.contaminated_vertices,
            "vertices_clamped": self.vertices_clamped,
            "max_residual_grade": round(self.max_residual_grade, 4),
            "edges_over_grade": self.edges_over_grade[:50],
        }


def _span_sign(edge) -> int:
    """+1 for bridge edges, -1 for tunnel edges, 0 otherwise."""
    if edge.bridge:
        return 1
    if edge.tunnel:
        return -1
    return 0


# Wide enough to cover the gap between the two carriageway decks of a divided highway,
# where the DTM still reads deck height a few metres outside either footprint.
FOOTPRINT_MARGIN_M = 10.0
FILL_ITERATIONS = 40
CELL_M = 50.0


def _seg_dist(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
    """Distance from point p to segment ab in 2D."""
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    if l2 == 0.0:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def _seg_intersect(a, b, c, d) -> tuple[float, float] | None:
    """Parameters (t on ab, u on cd) where segments ab and cd cross, or None."""
    r = (b[0] - a[0], b[1] - a[1])
    q = (d[0] - c[0], d[1] - c[1])
    denom = r[0] * q[1] - r[1] * q[0]
    if abs(denom) < 1e-9:
        return None
    w = (c[0] - a[0], c[1] - a[1])
    t = (w[0] * q[1] - w[1] * q[0]) / denom
    u = (w[0] * r[1] - w[1] * r[0]) / denom
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        return t, u
    return None


class _SegmentIndex:
    """Coarse grid over 2D segments for neighbourhood queries."""

    def __init__(self) -> None:
        self.cells: dict[tuple[int, int], list[tuple]] = {}

    def add(self, a: tuple[float, float], b: tuple[float, float], payload) -> None:
        for cx in range(int(min(a[0], b[0]) // CELL_M), int(max(a[0], b[0]) // CELL_M) + 1):
            for cz in range(int(min(a[1], b[1]) // CELL_M), int(max(a[1], b[1]) // CELL_M) + 1):
                self.cells.setdefault((cx, cz), []).append((a, b, payload))

    def near(self, x: float, z: float, radius: float):
        seen = set()
        for cx in range(int((x - radius) // CELL_M), int((x + radius) // CELL_M) + 1):
            for cz in range(int((z - radius) // CELL_M), int((z + radius) // CELL_M) + 1):
                for item in self.cells.get((cx, cz), []):
                    if id(item) not in seen:
                        seen.add(id(item))
                        yield item


def _bridge_index(
    graph: RoadGraph, vertex_keys: dict[str, list[str]], positions: dict[str, tuple[float, float]]
) -> _SegmentIndex:
    idx = _SegmentIndex()
    for eid, e in graph.edges.items():
        if not e.bridge:
            continue
        keys = vertex_keys[eid]
        for i in range(len(keys) - 1):
            idx.add(positions[keys[i]], positions[keys[i + 1]], (eid, keys[i], keys[i + 1]))
    return idx


def _footprint_contamination(
    graph: RoadGraph,
    idx: _SegmentIndex,
    vertex_keys: dict[str, list[str]],
    positions: dict[str, tuple[float, float]],
) -> set[str]:
    """Vertices of lower-layer edges that lie inside a bridge footprint.

    The DTM keeps bridge decks as terrain, so those samples are the deck, not
    the ground. They are refilled from their neighbours.
    """
    bad: set[str] = set()
    for eid, e in graph.edges.items():
        if e.bridge:
            continue
        for key in vertex_keys[eid]:
            x, z = positions[key]
            for a, b, (beid, _, _) in idx.near(x, z, 40.0):
                be = graph.edges[beid]
                if be.layer <= e.layer:
                    continue
                if _seg_dist(x, z, a[0], a[1], b[0], b[1]) <= be.width_m / 2.0 + FOOTPRINT_MARGIN_M:
                    bad.add(key)
                    break
    return bad


def _fill(
    y: dict[str, float], bad: set[str], adj: dict[str, list[tuple[str, float, float]]]
) -> None:
    """Replace contaminated heights by a smooth interpolation of clean neighbours."""
    if not bad:
        return
    order = sorted(bad)
    # Seed from clean neighbours, expanding outward for vertices with none.
    pending = set(order)
    seeded: dict[str, float] = {}
    while pending:
        progress = False
        for key in sorted(pending):
            vals = [
                y[o] if o not in bad else seeded[o]
                for o, _, _ in adj[key]
                if o not in bad or o in seeded
            ]
            if vals:
                seeded[key] = sum(vals) / len(vals)
                pending.discard(key)
                progress = True
        if not progress:
            for key in pending:  # isolated cluster: keep the DTM value
                seeded[key] = y[key]
            break
    for key, val in seeded.items():
        y[key] = val
    for _ in range(FILL_ITERATIONS):
        for key in order:
            neigh = adj[key]
            if neigh:
                y[key] = sum(y[o] for o, _, _ in neigh) / len(neigh)


def _crossing_need(
    graph: RoadGraph,
    eids: list[str],
    vertex_keys: dict[str, list[str]],
    positions: dict[str, tuple[float, float]],
    heights: dict[str, float],
    y: dict[str, float],
    all_idx: _SegmentIndex,
    clearance: float,
    sg: int,
) -> float:
    """Largest clearance violation against roads crossing under (or over) the chain."""
    need = 0.0
    chain_set = set(eids)
    chain_keys = {k for eid in eids for k in vertex_keys[eid]}
    for eid in eids:
        keys = vertex_keys[eid]
        layer = graph.edges[eid].layer
        for i in range(len(keys) - 1):
            a, b = positions[keys[i]], positions[keys[i + 1]]
            mid = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
            radius = math.dist(a, b) / 2.0 + CELL_M
            for c, d, (oeid, ka, kb) in all_idx.near(mid[0], mid[1], radius):
                if oeid in chain_set or ka in chain_keys or kb in chain_keys:
                    continue  # the chain's own edges and its approaches, which share a node
                other = graph.edges[oeid]
                if sg > 0 and other.layer >= layer:
                    continue
                if sg < 0 and other.layer <= layer:
                    continue
                hit = _seg_intersect(a, b, c, d)
                if hit is None:
                    continue
                t, u = hit
                deck = heights[keys[i]] + (heights[keys[i + 1]] - heights[keys[i]]) * t
                under = y[ka] + (y[kb] - y[ka]) * u
                need = max(
                    need, (under + clearance - deck) if sg > 0 else (deck - (under - clearance))
                )
    return need


def _all_index(
    graph: RoadGraph, vertex_keys: dict[str, list[str]], positions: dict[str, tuple[float, float]]
) -> _SegmentIndex:
    idx = _SegmentIndex()
    for eid in graph.edges:
        keys = vertex_keys[eid]
        for i in range(len(keys) - 1):
            idx.add(positions[keys[i]], positions[keys[i + 1]], (eid, keys[i], keys[i + 1]))
    return idx


def _span_heights(
    graph: RoadGraph,
    cfg: ImportConfig,
    ground: dict[str, float],
    y: dict[str, float],
    vertex_keys: dict[str, list[str]],
    lengths: dict[str, list[float]],
    positions: dict[str, tuple[float, float]],
) -> tuple[dict[str, float], int]:
    """Fixed heights for bridge and tunnel vertices.

    Bridges are grouped into chains (connected bridge edges of the same sign,
    continuing through junctions where ramps join the deck). Chain end nodes
    that also touch a ground-level edge are anchors at ground height; ramps
    joining mid-deck are not anchors, they climb to the deck like approaches.
    Every chain vertex is the inverse-distance weighted mix of the anchor heights
    (linear along a two-anchor bridge). If clearance over a crossing road is
    violated, the whole chain rises (or, for tunnels, sinks) by the largest
    violation. Chains with no anchor sit at ground plus clearance.
    Returns the fixed heights and the number of anchorless chains.
    """
    inc = graph.incident()
    sign_of = {eid: _span_sign(e) for eid, e in graph.edges.items()}
    span_edges = sorted(eid for eid, sg in sign_of.items() if sg != 0)
    parent: dict[str, str] = {eid: eid for eid in span_edges}

    def find(a: str) -> str:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for eids in inc.values():
        spans = [x for x in eids if sign_of[x] != 0]
        if len(spans) > 1:  # spans continue through this node, whatever else joins here
            for x in spans[1:]:
                if sign_of[x] == sign_of[spans[0]]:
                    ra, rb = find(spans[0]), find(x)
                    if ra != rb:
                        parent[max(ra, rb)] = min(ra, rb)
    chains: dict[str, list[str]] = {}
    for eid in span_edges:
        chains.setdefault(find(eid), []).append(eid)

    all_idx = _all_index(graph, vertex_keys, positions)
    fixed: dict[str, float] = {}
    anchorless = 0
    for root in sorted(chains):
        eids = sorted(chains[root])
        sg = sign_of[eids[0]]
        clearance = max(max(1, abs(graph.edges[x].layer)) for x in eids) * cfg.bridge_clearance_m
        adj: dict[str, list[tuple[str, float]]] = {}
        chain_keys: set[str] = set()
        for eid in eids:
            keys, segs = vertex_keys[eid], lengths[eid]
            chain_keys.update(keys)
            for i in range(len(keys) - 1):
                adj.setdefault(keys[i], []).append((keys[i + 1], segs[i]))
                adj.setdefault(keys[i + 1], []).append((keys[i], segs[i]))
        chain_set = set(eids)
        anchors = sorted(
            k
            for k in chain_keys
            if k.startswith("n:")
            and sum(1 for x in inc[k[2:]] if x in chain_set) == 1
            and any(sign_of[x] == 0 for x in inc[k[2:]])
        )
        heights: dict[str, float] = {}
        if not anchors:
            anchorless += 1
            for k in chain_keys:
                heights[k] = ground[k] + sg * clearance
        else:
            weights: dict[str, float] = {k: 0.0 for k in chain_keys}
            weighted: dict[str, float] = {k: 0.0 for k in chain_keys}
            for a in anchors:
                dist = {a: 0.0}
                heap = [(0.0, a)]
                while heap:
                    d, k = heapq.heappop(heap)
                    if d > dist[k]:
                        continue
                    for other, seg in adj.get(k, []):
                        nd = d + seg
                        if nd < dist.get(other, math.inf):
                            dist[other] = nd
                            heapq.heappush(heap, (nd, other))
                for k, d in dist.items():
                    w = 1.0 / max(d, 0.01)
                    weights[k] += w
                    weighted[k] += w * y[a]
            for k in chain_keys:
                heights[k] = (
                    weighted[k] / weights[k] if weights[k] > 0 else ground[k] + sg * clearance
                )
            need = _crossing_need(
                graph, eids, vertex_keys, positions, heights, y, all_idx, clearance, sg
            )
            if sg < 0 and need <= 0:
                need = (
                    clearance  # a tunnel with nothing crossing above still runs below the terrain
                )
            if need > 0:
                for k in chain_keys:
                    heights[k] += sg * need
        for k, h in heights.items():
            if k not in fixed or (sg > 0 and h > fixed[k]) or (sg < 0 and h < fixed[k]):
                fixed[k] = h
    return fixed, anchorless


def apply_elevation(graph: RoadGraph, source: ElevationSource, cfg: ImportConfig) -> ElevationStats:
    """Set y on every node and polyline vertex in place. Returns statistics."""
    # Vertex model: node vertices "n:<id>", interior vertices "e:<edge id>:<i>".
    ground: dict[str, float] = {}
    y: dict[str, float] = {}
    adj: dict[str, list[tuple[str, float, float]]] = {}  # v -> [(u, distance, grade)]
    vertex_keys: dict[str, list[str]] = {}
    lengths: dict[str, list[float]] = {}
    positions: dict[str, tuple[float, float]] = {}

    def add_link(a: str, b: str, d: float, g: float) -> None:
        adj.setdefault(a, []).append((b, d, g))
        adj.setdefault(b, []).append((a, d, g))

    for nid, node in graph.nodes.items():
        key = f"n:{nid}"
        ground[key] = source.sample(node.position[0], node.position[2])
        y[key] = ground[key]
        positions[key] = (node.position[0], node.position[2])
        adj.setdefault(key, [])

    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        grade = cfg.for_class(e.road_class).max_grade
        keys = []
        for i, p in enumerate(e.polyline):
            if i == 0:
                key = f"n:{e.from_node}"
            elif i == len(e.polyline) - 1:
                key = f"n:{e.to_node}"
            else:
                key = f"e:{eid}:{i}"
                ground[key] = source.sample(p[0], p[2])
                y[key] = ground[key]
                positions[key] = (p[0], p[2])
            keys.append(key)
        segs = [
            max(math.dist(e.polyline[i][::2], e.polyline[i + 1][::2]), 0.01)
            for i in range(len(keys) - 1)
        ]
        for i in range(len(keys) - 1):
            add_link(keys[i], keys[i + 1], segs[i], grade)
        vertex_keys[eid] = keys
        lengths[eid] = segs

    bridge_idx = _bridge_index(graph, vertex_keys, positions)
    contaminated = _footprint_contamination(graph, bridge_idx, vertex_keys, positions)
    _fill(y, contaminated, adj)
    for key in contaminated:
        ground[key] = y[key]
    fixed, anchorless = _span_heights(graph, cfg, ground, y, vertex_keys, lengths, positions)
    stats = ElevationStats(
        fixed_vertices=len(fixed),
        free_vertices=len(y) - len(fixed),
        anchorless_spans=anchorless,
        contaminated_vertices=len(contaminated),
    )
    for key, val in fixed.items():
        y[key] = val

    lower = _propagate(fixed, adj, sign=-1)
    upper = _propagate(fixed, adj, sign=+1)
    for key in list(y):
        if key in fixed:
            continue
        lo, hi = lower.get(key, -math.inf), upper.get(key, math.inf)
        if lo > hi + SMOOTHING_EPSILON:
            stats.bound_conflicts += 1
            y[key] = (lo + hi) / 2.0
            continue
        clamped = min(max(y[key], lo), hi)
        if clamped != y[key]:
            stats.vertices_clamped += 1
        y[key] = clamped

    _smooth(y, fixed, lower, upper, adj)

    # Write back and measure residual grades.
    for nid, node in graph.nodes.items():
        node.position = (node.position[0], y[f"n:{nid}"], node.position[2])
        node.ground_y = ground[f"n:{nid}"]
    worst = 0.0
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        keys = vertex_keys[eid]
        pts = [(p[0], y[k], p[2]) for p, k in zip(e.polyline, keys, strict=True)]
        e.polyline = pts
        limit = cfg.for_class(e.road_class).max_grade
        edge_worst = 0.0
        for i, seg in enumerate(lengths[eid]):
            edge_worst = max(edge_worst, abs(pts[i + 1][1] - pts[i][1]) / seg)
        if edge_worst > limit + 0.005:
            stats.edges_over_grade.append(eid)
        worst = max(worst, edge_worst)
    stats.max_residual_grade = worst
    ys = list(y.values())
    stats.min_y, stats.max_y = (min(ys), max(ys)) if ys else (0.0, 0.0)
    return stats


def _propagate(
    fixed: dict[str, float], adj: dict[str, list[tuple[str, float, float]]], sign: int
) -> dict[str, float]:
    """Bounds implied by fixed vertices. sign=-1: lower bound (max of y_f - g*d); +1: upper bound (min of y_f + g*d)."""
    best: dict[str, float] = dict(fixed)
    heap = [(sign * v, k) for k, v in fixed.items()]
    heapq.heapify(heap)
    while heap:
        prio, key = heapq.heappop(heap)
        val = sign * prio
        if val != best.get(key):
            continue
        for other, d, g in adj[key]:
            cand = val + sign * g * d
            cur = best.get(other)
            if cur is None or (sign < 0 and cand > cur) or (sign > 0 and cand < cur):
                best[other] = cand
                heapq.heappush(heap, (sign * cand, other))
    return best


def _smooth(
    y: dict[str, float],
    fixed: dict[str, float],
    lower: dict[str, float],
    upper: dict[str, float],
    adj: dict[str, list[tuple[str, float, float]]],
) -> None:
    """Relax grade violations between free vertices by moving both ends toward each other."""
    order = sorted(k for k in y if k not in fixed)
    for _ in range(SMOOTHING_PASSES):
        moved = 0.0
        for key in order:
            for other, d, g in adj[key]:
                if other < key and other not in fixed:
                    continue  # each free pair handled once, from the smaller key
                limit = g * d
                diff = y[other] - y[key]
                if abs(diff) <= limit + SMOOTHING_EPSILON:
                    continue
                excess = abs(diff) - limit
                if other in fixed:
                    step = excess if diff > 0 else -excess
                    new = y[key] + step
                else:
                    step = excess / 2.0
                    new = y[key] + (step if diff > 0 else -step)
                    new_other = y[other] - (step if diff > 0 else -step)
                    y[other] = min(
                        max(new_other, lower.get(other, -math.inf)), upper.get(other, math.inf)
                    )
                new = min(max(new, lower.get(key, -math.inf)), upper.get(key, math.inf))
                moved += abs(new - y[key])
                y[key] = new
        if moved < SMOOTHING_EPSILON:
            break
