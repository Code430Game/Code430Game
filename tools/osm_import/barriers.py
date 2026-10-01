"""Highway barriers: bridge parapets, median barriers, guardrails, sound walls.

Approach: sample each highway edge every few metres and look sideways.
- Parapet: every bridge edge, both deck edges, full length. Where a sidewalk or
  cycleway runs beside the deck (within `parapet_walkway_range_m`) the parapet
  moves to that walkway's outer edge and a curb marks the road edge instead.
- Median: an opposing highway edge runs alongside within `median_max_gap_m`
  (gap between the two ribbon edges): a barrier on the mid-line of the gap.
- Guardrail: the terrain `guardrail_probe_m` outside the ribbon edge drops more
  than `guardrail_drop_m` below the road: a rail on that edge.
- Sound wall: at grade or above it, housing within range on that side, no
  median on that side: a wall on that edge, in runs of at least the minimum.
- Curb: a sidewalk runs within `curb_sidewalk_range_m` of a street's ribbon
  edge: a low step along that edge (kind "curb").
- Median curb: a one-way street in `median_curb_classes` with the opposing
  carriageway running alongside across a gap of up to `median_curb_max_gap_m`
  (a boulevard with a grass median): a curb along the inner ribbon edge.
- Roadblock: a road that dead-ends within `bbox_edge_margin_m` of the import
  bounds was cut by the bbox, not by the city: a block across its full width at
  the end (kind "roadblock"), so the district has a visible edge instead of a
  road that stops in mid-air.
No wall stands inside another road's ribbon: samples more than
`overlap_margin_m` inside a different way's carriageway at the same level
(ramps peeling off a highway, decks meeting at a fork) are dropped, so runs
break around the overlap. The margin exceeds the parapet inset so a deck
continuing as another OSM way keeps its wall.
Runs are strung from consecutive samples; each becomes a polyline with a kind
and height for the game to extrude.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field

from osm_import.buildings import BuildingsResult
from osm_import.config import ImportConfig
from osm_import.elevation import ElevationSource, _seg_dist, _SegmentIndex
from osm_import.graph import RoadGraph
from osm_import.validation import _touches_edge

log = logging.getLogger(__name__)

COORD_DECIMALS = 2


@dataclass
class Barrier:
    id: str
    kind: str  # parapet | median | guardrail | soundwall
    height_m: float
    edge_id: str
    points: list[tuple[float, float, float]]


@dataclass
class BarriersResult:
    barriers: list[Barrier] = field(default_factory=list)
    counts: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, x east, y up, z south; points are the wall base line",
            "barriers": [
                {
                    "id": b.id,
                    "kind": b.kind,
                    "height_m": round(b.height_m, 2),
                    "edge_id": b.edge_id,
                    "points": [
                        [
                            round(x, COORD_DECIMALS),
                            round(y, COORD_DECIMALS),
                            round(z, COORD_DECIMALS),
                        ]
                        for x, y, z in b.points
                    ],
                }
                for b in sorted(self.barriers, key=lambda b: b.id)
            ],
        }


def _samples(pl: list, step: float):
    """Yields (x, y, z, dir_x, dir_z) every `step` metres along a polyline, always ending on
    the last vertex. The direction is the smoothed tangent (blended between the vertices'
    averaged directions), so an offset wall bends at the corners instead of jumping."""
    n = len(pl)
    if n < 2:
        return
    seg_dirs = []
    seg_lens = []
    for i in range(n - 1):
        a, b = pl[i], pl[i + 1]
        length = math.hypot(b[0] - a[0], b[2] - a[2])
        seg_lens.append(length)
        seg_dirs.append(
            ((b[0] - a[0]) / length, (b[2] - a[2]) / length) if length > 0 else (1.0, 0.0)
        )
    total = sum(seg_lens)
    if total <= 0:
        return
    # Vertex tangents: the normalised sum of the neighbouring segment directions.
    vdirs = []
    for i in range(n):
        parts = [seg_dirs[j] for j in (i - 1, i) if 0 <= j < n - 1]
        sx, sz = sum(d[0] for d in parts), sum(d[1] for d in parts)
        norm = math.hypot(sx, sz)
        vdirs.append((sx / norm, sz / norm) if norm > 1e-9 else parts[0])
    stations = []
    s = 0.0
    while s < total - 1e-6:
        stations.append(s)
        s += step
    stations.append(total)
    walked = 0.0
    seg = 0
    for s in stations:
        while seg < n - 2 and s > walked + seg_lens[seg] + 1e-9:
            walked += seg_lens[seg]
            seg += 1
        a, b, length = pl[seg], pl[seg + 1], seg_lens[seg]
        t = max(0.0, min(1.0, (s - walked) / length)) if length > 0 else 0.0
        da, db = vdirs[seg], vdirs[seg + 1]
        dx, dz = da[0] + (db[0] - da[0]) * t, da[1] + (db[1] - da[1]) * t
        norm = math.hypot(dx, dz)
        if norm < 1e-9:
            dx, dz = seg_dirs[seg]
        else:
            dx, dz = dx / norm, dz / norm
        yield (
            a[0] + (b[0] - a[0]) * t,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t,
            dx,
            dz,
        )


def _runs(points: list, keep: list, min_run: float = 0.0) -> list[list]:
    """Splits points into runs where keep[i] is true; drops runs shorter than min_run."""
    out: list[list] = []
    current: list = []
    for p, k in zip(points, keep, strict=True):
        if k:
            current.append(p)
        else:
            if len(current) >= 2:
                out.append(current)
            current = []
    if len(current) >= 2:
        out.append(current)
    if min_run > 0:
        out = [
            r
            for r in out
            if sum(
                math.hypot(r[i + 1][0] - r[i][0], r[i + 1][2] - r[i][2]) for i in range(len(r) - 1)
            )
            >= min_run
        ]
    return out


def build_barriers(
    graph: RoadGraph,
    source: ElevationSource,
    buildings: BuildingsResult | None,
    cfg: ImportConfig,
    bounds: tuple[float, float, float, float] | None = None,
) -> BarriersResult:
    rules = cfg.barriers
    result = BarriersResult()
    if not rules:
        return result
    highway = set(rules.get("highway_classes", []))
    step = float(rules.get("sample_step_m", 8.0))
    seq = 0

    def add(kind: str, height: float, edge_id: str, pts: list) -> None:
        nonlocal seq
        result.barriers.append(Barrier(f"b{seq}", kind, height, edge_id, pts))
        result.counts[kind] = result.counts.get(kind, 0) + 1
        seq += 1

    # Index highway segments for the median search and building centroids for sound walls.
    hw_index = _SegmentIndex()
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.road_class in highway:
            for i in range(len(e.polyline) - 1):
                a, b = e.polyline[i], e.polyline[i + 1]
                hw_index.add((a[0], a[2]), (b[0], b[2]), (eid, i))
    house_cells: dict[tuple[int, int], list[tuple[float, float]]] = {}
    if buildings is not None:
        kinds = set(rules.get("soundwall_kinds", []))
        for b in buildings.buildings:
            if b.kind not in kinds:
                continue
            ring = b.rings[0]
            cx, cz = sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring)
            house_cells.setdefault((int(cx // 50), int(cz // 50)), []).append((cx, cz))

    def houses_near(x: float, z: float, r: float) -> bool:
        cells = int(r // 50) + 1
        for dx in range(-cells, cells + 1):
            for dz in range(-cells, cells + 1):
                for hx, hz in house_cells.get((int(x // 50) + dx, int(z // 50) + dz), []):
                    if math.hypot(hx - x, hz - z) <= r:
                        return True
        return False

    # Sidewalk segments for curb detection; walkways (sidewalks and cycleways) for bridge parapets.
    sw_index = _SegmentIndex()
    walk_index = _SegmentIndex()
    walkway_kinds = set(rules.get("parapet_walkway_kinds", ["sidewalk", "cycleway"]))
    for w in graph.pedestrian:
        if w.covered:
            continue
        for i in range(len(w.polyline) - 1):
            a, b = w.polyline[i], w.polyline[i + 1]
            if w.kind == "sidewalk":
                sw_index.add((a[0], a[2]), (b[0], b[2]), (w.id, i))
            if w.kind in walkway_kinds:
                walk_index.add((a[0], a[2]), (b[0], b[2]), (w.id, i, w.width_m))
    walk_range = float(rules.get("parapet_walkway_range_m", 8.0))
    # Every carriageway, for keeping walls out of other roads (ramps at forks, decks at splits).
    road_index = _SegmentIndex()
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            road_index.add((a[0], a[2]), (b[0], b[2]), (eid, e.width_m / 2.0, a[1], b[1]))
    overlap_margin = float(rules.get("overlap_margin_m", 0.2))
    overlap_height = float(rules.get("overlap_height_m", 2.5))

    def clear_of_roads(x: float, y: float, z: float, own: str) -> bool:
        """False when (x, z) lies inside the ribbon of an edge from a different OSM way at
        about the same level; a deck crossing well above or below another road is clear."""
        way = own.split(".")[0]
        for a, b, (oid, ohw, ya, yb) in road_index.near(x, z, 12.0):
            if oid.split(".")[0] == way:
                continue
            if _seg_dist(x, z, a[0], a[1], b[0], b[1]) >= ohw - overlap_margin:
                continue
            dx, dz = b[0] - a[0], b[1] - a[1]
            l2 = dx * dx + dz * dz
            t = max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2)) if l2 else 0.0
            if abs(y - (ya + (yb - ya) * t)) < overlap_height:
                return False
        return True

    curb_classes = set(rules.get("curb_classes", []))
    curb_range = float(rules.get("curb_sidewalk_range_m", 3.5))
    # One-way carriageways of boulevard classes, for median curbs.
    median_curb_classes = set(rules.get("median_curb_classes", []))
    median_curb_gap = float(rules.get("median_curb_max_gap_m", 30.0))
    dual_index = _SegmentIndex()
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.road_class in median_curb_classes and e.oneway:
            for i in range(len(e.polyline) - 1):
                a, b = e.polyline[i], e.polyline[i + 1]
                dual_index.add((a[0], a[2]), (b[0], b[2]), (eid, i))

    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        hw = e.width_m / 2.0
        # Curbs along streets where a sidewalk runs beside the ribbon edge.
        if e.road_class in curb_classes and not e.bridge and not e.tunnel:
            for side in (-1.0, 1.0):
                pts, keep = [], []
                for x, y, z, dx, dz in _samples(e.polyline, step):
                    nx, nz = -dz * side, dx * side
                    ex, ez = x + nx * hw, z + nz * hw
                    near = False
                    for a, b, _payload in sw_index.near(ex, ez, curb_range + 2.0):
                        if _seg_dist(ex, ez, a[0], a[1], b[0], b[1]) <= curb_range:
                            near = True
                            break
                    pts.append((ex, y, ez))
                    keep.append(near and clear_of_roads(ex, y, ez, eid))
                for run in _runs(pts, keep):
                    add("curb", float(rules.get("curb_height_m", 0.12)), eid, run)
        # Median curbs: the opposing carriageway runs alongside across a grass gap.
        if e.road_class in median_curb_classes and e.oneway and not e.bridge and not e.tunnel:
            for side in (-1.0, 1.0):
                pts, keep = [], []
                for x, y, z, dx, dz in _samples(e.polyline, step):
                    nx, nz = -dz * side, dx * side
                    ex, ez = x + nx * hw, z + nz * hw
                    facing = False
                    for a, b, (oid, _i) in dual_index.near(x, z, median_curb_gap + 30.0):
                        if oid.split(".")[0] == eid.split(".")[0]:
                            continue
                        o = graph.edges[oid]
                        odx, odz = b[0] - a[0], b[1] - a[1]
                        ol = math.hypot(odx, odz)
                        if ol < 1e-6 or (odx * dx + odz * dz) / ol > -0.7:
                            continue  # not opposing traffic
                        d = _seg_dist(x, z, a[0], a[1], b[0], b[1])
                        t = max(0.0, min(1.0, ((x - a[0]) * odx + (z - a[1]) * odz) / (ol * ol)))
                        px, pz = a[0] + odx * t, a[1] + odz * t
                        if (px - x) * nx + (pz - z) * nz <= 0:
                            continue  # on the other side
                        gap = d - hw - o.width_m / 2.0
                        if 0.3 <= gap <= median_curb_gap:
                            facing = True
                            break
                    pts.append((ex, y, ez))
                    keep.append(facing and clear_of_roads(ex, y, ez, eid))
                for run in _runs(pts, keep, 10.0):
                    add("curb", float(rules.get("curb_height_m", 0.12)), eid, run)
        # Bridge parapets on every bridge edge, outside any walkway that rides along the deck.
        if e.bridge:
            inset = float(rules.get("parapet_inset_m", 0.25))
            for side in (-1.0, 1.0):
                pts, keep, curb_pts, curb_keep = [], [], [], []
                for x, y, z, dx, dz in _samples(e.polyline, step):
                    nx, nz = -dz * side, dx * side
                    ex, ez = x + nx * hw, z + nz * hw
                    outer = hw  # deck edge measured from the centreline
                    for a, b, (_wid, _i, ww) in walk_index.near(ex, ez, walk_range + 4.0):
                        d = _seg_dist(x, z, a[0], a[1], b[0], b[1])
                        mx, mz = (a[0] + b[0]) / 2.0 - x, (a[1] + b[1]) / 2.0 - z
                        if (mx * nx + mz * nz) <= 0 or d - hw > walk_range:
                            continue  # other side, or too far out to be part of this deck
                        outer = max(outer, d + ww / 2.0)
                    px, pz = x + nx * (outer - inset), z + nz * (outer - inset)
                    pts.append((px, y, pz))
                    keep.append(clear_of_roads(px, y, pz, eid))
                    curb_pts.append((ex, y, ez))
                    curb_keep.append(outer > hw + 0.5 and clear_of_roads(ex, y, ez, eid))
                for run in _runs(pts, keep):
                    add("parapet", float(rules.get("parapet_height_m", 1.0)), eid, run)
                for run in _runs(curb_pts, curb_keep):
                    add("curb", float(rules.get("curb_height_m", 0.12)), eid, run)
        if e.road_class not in highway or e.bridge or e.tunnel:
            continue
        samples = list(_samples(e.polyline, step))
        if len(samples) < 2:
            continue
        median_side = {-1.0: [False] * len(samples), 1.0: [False] * len(samples)}
        median_pts = {-1.0: [], 1.0: []}
        max_gap = float(rules["median_max_gap_m"])
        for si, (x, y, z, dx, dz) in enumerate(samples):
            for side in (-1.0, 1.0):
                nx, nz = -dz * side, dx * side
                best = None  # (distance, gap, other edge id)
                for a, b, (oid, _i) in hw_index.near(x, z, max_gap + 30.0):
                    if oid == eid:
                        continue
                    o = graph.edges[oid]
                    if o.bridge != e.bridge:
                        continue
                    odx, odz = b[0] - a[0], b[1] - a[1]
                    ol = math.hypot(odx, odz)
                    if ol < 1e-6 or (odx * dx + odz * dz) / ol > -0.7:
                        continue  # not opposing traffic
                    d = _seg_dist(x, z, a[0], a[1], b[0], b[1])
                    t = max(0.0, min(1.0, ((x - a[0]) * odx + (z - a[1]) * odz) / (ol * ol)))
                    px, pz = a[0] + odx * t, a[1] + odz * t
                    if (px - x) * nx + (pz - z) * nz <= 0:
                        continue  # the other carriageway is on the other side
                    gap = d - hw - o.width_m / 2.0
                    if 0.0 <= gap <= max_gap and (best is None or d < best[0]):
                        best = (d, gap, oid)
                if best is not None:
                    median_side[side][si] = True
                    d, gap, oid = best
                    # One barrier per pair: only the edge with the smaller id emits it.
                    median_pts[side].append(
                        (x + nx * (hw + gap / 2.0), y, z + nz * (hw + gap / 2.0))
                        if eid < oid
                        else None
                    )
                else:
                    median_pts[side].append(None)
        for side in (-1.0, 1.0):
            pts = median_pts[side]
            keep = [p is not None for p in pts]
            for run in _runs([p if p is not None else (0.0, 0.0, 0.0) for p in pts], keep):
                add("median", float(rules.get("median_height_m", 0.9)), eid, run)
        # Guardrails and sound walls on sides without a median.
        for side in (-1.0, 1.0):
            rail_pts, rail_keep = [], []
            wall_pts, wall_keep = [], []
            for si, (x, y, z, dx, dz) in enumerate(samples):
                nx, nz = -dz * side, dx * side
                edge_x, edge_z = x + nx * hw, z + nz * hw
                probe = float(rules.get("guardrail_probe_m", 3.0))
                ground = source.sample(edge_x + nx * probe, edge_z + nz * probe)
                drop = y - ground
                has_median = median_side[side][si]
                rail_pts.append((edge_x + nx * 0.3, y, edge_z + nz * 0.3))
                rail_keep.append(
                    (not has_median)
                    and drop > float(rules.get("guardrail_drop_m", 1.2))
                    and clear_of_roads(edge_x + nx * 0.3, y, edge_z + nz * 0.3, eid)
                )
                at_grade = drop > -float(rules.get("soundwall_trench_depth_m", 2.0))
                wall_pts.append((edge_x + nx * 2.0, y, edge_z + nz * 2.0))
                wall_keep.append(
                    (not has_median)
                    and at_grade
                    and clear_of_roads(edge_x + nx * 2.0, y, edge_z + nz * 2.0, eid)
                    and houses_near(
                        edge_x + nx * 20.0,
                        edge_z + nz * 20.0,
                        float(rules.get("soundwall_building_range_m", 45.0)),
                    )
                )
            for run in _runs(wall_pts, wall_keep, float(rules.get("soundwall_min_run_m", 60.0))):
                add("soundwall", float(rules.get("soundwall_height_m", 4.0)), eid, run)
            # No guardrail where a sound wall already stands.
            for run in _runs(
                rail_pts, [rk and not wk for rk, wk in zip(rail_keep, wall_keep, strict=True)]
            ):
                add("guardrail", float(rules.get("guardrail_height_m", 0.8)), eid, run)
    # Roadblocks where the bbox cut a road: a dead end within the edge margin of the bounds.
    if bounds is not None:
        at_edge = _touches_edge(graph, bounds, cfg.bbox_edge_margin_m)
        inc = graph.incident()
        for nid in sorted(at_edge):
            if len(inc[nid]) != 1 or graph.nodes[nid].junction_type != "dead_end":
                continue
            e = graph.edges[inc[nid][0]]
            pl = e.polyline
            end, prev = (pl[0], pl[1]) if e.from_node == nid else (pl[-1], pl[-2])
            dx, dz = end[0] - prev[0], end[2] - prev[2]
            length = math.hypot(dx, dz)
            if length < 1e-6:
                continue
            dx, dz = dx / length, dz / length
            nx, nz = -dz, dx
            hw = e.width_m / 2.0 + 0.5
            # Set back from the very end so the block sits on the ribbon, not past it.
            bx, by, bz = end[0] - dx * 1.5, end[1], end[2] - dz * 1.5
            add(
                "roadblock",
                float(rules.get("roadblock_height_m", 1.1)),
                e.id,
                [(bx - nx * hw, by, bz - nz * hw), (bx + nx * hw, by, bz + nz * hw)],
            )
    log.info("barriers: %s", result.counts)
    return result
