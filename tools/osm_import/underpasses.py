"""Dig underpasses: a covered pedestrian way that joins open ways gets a floor below whatever
covers it (the carved terrain, any ground road over it), the joined ways ramp down to that
floor, and the way is exported with a `tunnel` profile the game builds a passage from.
A covered way with nothing modelled above it is uncovered and drawn like any path.
Runs after pedestrian heights and before the terrain is flattened to the ways."""

from __future__ import annotations

import logging
import math
from collections.abc import Callable

from osm_import.graph import PedestrianWay, RoadGraph

log = logging.getLogger("osm_import")

CLEARANCE_M = 3.4  # floor to the highest cover point
CEILING_SLAB_M = 0.3  # the ceiling sits this far below the cover
MIN_COVER_M = 1.5  # less than this above the joined ends: nothing to dig under
RAMP_GRADE = 0.15  # approaches on paths
STEPS_GRADE = 0.6  # approaches on stairs
MAX_LENGTH_M = 80.0
JOIN_TOL_M = 1.0
ROAD_REACH_M = 1.0  # a road covers the way within half its width plus this
TERRAIN_MARGIN_M = 1.0  # terrain follows ramps within half width + this, blending beyond
TUNNEL_MARGIN_M = 4.0  # under a tunnel the terrain is at the floor within half width + this
# with no blend: the game cuts that strip out of the terrain mesh and hides the edge in the walls
KINDS = ("footway", "path", "cycleway", "pedestrian")

Sampler = Callable[[float, float], float]


def dig_underpasses(graph: RoadGraph, sample: Sampler) -> dict:
    """Shapes every qualifying covered way and its approaches in place.
    Returns {"tunnels": n, "uncovered": n}."""
    roads = _ground_road_segments(graph)
    open_ends: list[tuple[PedestrianWay, int]] = []
    for w in graph.pedestrian:
        if not w.covered and len(w.polyline) >= 2:
            open_ends.append((w, 0))
            open_ends.append((w, -1))
    stats = {"tunnels": 0, "uncovered": 0}
    for w in graph.pedestrian:
        if not w.covered or w.kind not in KINDS or len(w.polyline) < 2:
            continue
        if _length(w.polyline) > MAX_LENGTH_M:
            continue
        joins = [
            (
                idx,
                [j for j in open_ends if _dist(j[0].polyline[j[1]], w.polyline[idx]) <= JOIN_TOL_M],
            )
            for idx in (0, -1)
        ]
        if not any(js for _idx, js in joins):
            continue
        end_y = min(j[0].polyline[j[1]][1] for _idx, js in joins for j in js)
        samples = _samples(w.polyline)
        road_cover = [_road_cover(p, roads) for p in samples]
        terrain_cover = [sample(p[0], p[2]) for p in samples]
        cover = max(max(r, t) for r, t in zip(road_cover, terrain_cover, strict=True))
        under_road = any(r > -math.inf for r in road_cover)
        if not under_road and max(terrain_cover) - end_y < MIN_COVER_M:
            w.covered = False
            w.profile = ""
            w.margin_m = TERRAIN_MARGIN_M
            for idx, js in joins:
                for jw, jidx in js:
                    _ramp(jw, jidx, w.polyline[idx][1])
            stats["uncovered"] += 1
            continue
        floor = min(end_y, cover - CLEARANCE_M)
        w.polyline = [(p[0], floor, p[2]) for p in w.polyline]
        w.profile = "tunnel"
        w.top = [floor + CLEARANCE_M - CEILING_SLAB_M] * len(
            w.polyline
        )  # flat, under the highest cover
        w.margin_m = TUNNEL_MARGIN_M
        w.shoulder_m = 0.0
        for _idx, js in joins:
            for jw, jidx in js:
                _ramp(jw, jidx, floor)
        stats["tunnels"] += 1
    log.info(
        "underpasses: %d tunnels, %d covered ways opened", stats["tunnels"], stats["uncovered"]
    )
    return stats


def _ramp(way: PedestrianWay, end_idx: int, floor: float) -> None:
    """Re-profiles `way` from the end at `end_idx` so it meets `floor` there and climbs back
    to its own heights at the ramp grade, inserting a vertex where the ramp tops out when the
    first segment is longer than the ramp."""
    pts = list(way.polyline)
    if end_idx == -1:
        pts.reverse()
    grade = STEPS_GRADE if way.kind == "steps" else RAMP_GRADE
    rise = pts[0][1] - floor
    if rise > 0.0:
        ramp_len = rise / grade
        first = _dist(pts[0], pts[1])
        if first > ramp_len + 1.0:
            t = ramp_len / first
            a, b = pts[0], pts[1]
            pts.insert(
                1, (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
            )
    s = 0.0
    out = []
    for i, p in enumerate(pts):
        if i > 0:
            s += _dist(pts[i - 1], p)
        out.append((p[0], min(p[1], floor + grade * s), p[2]))
    if end_idx == -1:
        out.reverse()
    way.polyline = out
    way.profile = way.profile or "trench"
    way.margin_m = TERRAIN_MARGIN_M


def _ground_road_segments(graph: RoadGraph) -> list[tuple]:
    out = []
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.tunnel or e.bridge:
            continue
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            out.append((a[0], a[2], b[0], b[2], a[1], b[1], e.width_m / 2.0 + ROAD_REACH_M))
    return out


def _road_cover(p: tuple, roads: list[tuple]) -> float:
    best = -math.inf
    for ax, az, bx, bz, ay, by, reach in roads:
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        if l2 < 1e-9:
            continue
        t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[2] - az) * dz) / l2))
        if math.hypot(p[0] - (ax + t * dx), p[2] - (az + t * dz)) <= reach:
            best = max(best, ay + (by - ay) * t)
    return best


def _samples(pl: list, step: float = 2.0) -> list:
    """The polyline's vertices plus points every `step` metres along it, so a road crossing
    between two vertices is still seen."""
    out = [pl[0]]
    for i in range(len(pl) - 1):
        a, b = pl[i], pl[i + 1]
        n = max(1, int(_dist(a, b) / step))
        for k in range(1, n + 1):
            t = k / n
            out.append(
                (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
            )
    return out


def _dist(a: tuple, b: tuple) -> float:
    return math.hypot(a[0] - b[0], a[2] - b[2])


def _length(pl: list) -> float:
    return sum(_dist(pl[i], pl[i + 1]) for i in range(len(pl) - 1))
