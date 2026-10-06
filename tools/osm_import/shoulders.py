"""Shoulder trimming (add-road-shoulders).

Motorway, trunk and link edges are given paved shoulders when the graph is built (see
`graph._shoulders`). Where a shoulder would spread over another road at a different height,
it would stand up as a step in that road; this happens through interchanges, where a ramp
runs alongside on the shoulder side. There the shoulder is dropped for the whole edge
(edges are short through interchanges), keeping the open stretches' shoulders. Runs after
elevation, since it compares heights, and before anything that reads the final widths.
"""

from __future__ import annotations

import logging
import math

from osm_import.graph import RoadGraph

log = logging.getLogger(__name__)

STEP_M = 4.0  # sample spacing along an edge
LEVEL_M = 0.15  # surfaces closer than this in height can share pavement


def _seg(x: float, z: float, a, b) -> tuple[float, float]:
    """Distance from (x, z) to segment a-b in the xz plane, and the height there."""
    dx, dz = b[0] - a[0], b[2] - a[2]
    l2 = dx * dx + dz * dz
    t = max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[2]) * dz) / l2)) if l2 > 0 else 0.0
    return math.hypot(x - a[0] - dx * t, z - a[2] - dz * t), a[1] + (b[1] - a[1]) * t


def trim_shoulders(graph: RoadGraph) -> int:
    """Drops each shoulder that overlaps another road at a different level. Returns how many."""
    cell = 32.0
    index: dict[tuple[int, int], list[tuple[str, int]]] = {}
    for eid, e in graph.edges.items():
        if e.tunnel:
            continue
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            for cx in range(int(min(a[0], b[0]) // cell) - 1, int(max(a[0], b[0]) // cell) + 2):
                for cz in range(int(min(a[2], b[2]) // cell) - 1, int(max(a[2], b[2]) // cell) + 2):
                    index.setdefault((cx, cz), []).append((eid, i))
    dropped = 0
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.shoulder_left_m <= 0.0 and e.shoulder_right_m <= 0.0:
            continue
        hw = e.width_m / 2.0
        clash = {-1.0: False, 1.0: False}
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            dx, dz = b[0] - a[0], b[2] - a[2]
            length = math.hypot(dx, dz)
            if length <= 0.0:
                continue
            ux, uz = dx / length, dz / length
            for k in range(int(length // STEP_M) + 1):
                t = min(k * STEP_M, length)
                x, y, z = a[0] + ux * t, a[1] + (b[1] - a[1]) * t / length, a[2] + uz * t
                for side in (-1.0, 1.0):
                    s = e.shoulder_right_m if side > 0 else e.shoulder_left_m
                    if s <= 0.0 or clash[side]:
                        continue
                    nx, nz = -uz * side, ux * side  # side > 0: right of travel
                    # The middle of the shoulder: is it on another road at another height?
                    px, pz = x + nx * (hw - s * 0.5), z + nz * (hw - s * 0.5)
                    for oid, oi in index.get((int(px // cell), int(pz // cell)), []):
                        if oid == eid:
                            continue
                        o = graph.edges[oid]
                        d, oy = _seg(px, pz, o.polyline[oi], o.polyline[oi + 1])
                        if d < o.width_m / 2.0 and abs(oy - y) > LEVEL_M and abs(oy - y) < 4.0:
                            clash[side] = True  # a road alongside, not one far over or under
                            break
        for side, hit in clash.items():
            if not hit:
                continue
            if side > 0:
                e.width_m -= e.shoulder_right_m
                e.shoulder_right_m = 0.0
            else:
                e.width_m -= e.shoulder_left_m
                e.shoulder_left_m = 0.0
            dropped += 1
    log.info("shoulders: %d dropped where they would overlap another road", dropped)
    return dropped
