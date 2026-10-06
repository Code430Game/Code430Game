"""Fork and merge geometry: ramps peel off the outer edge of the road they leave.

Approach: a node with exactly three roads where two run nearly straight through
and the third (the link) leaves at a shallow angle is a fork (link departs) or a
merge (link arrives). OSM draws the link from the through road's centreline, so
its ribbon starts inside the through road and pokes out of the far side. The
link's end vertex is moved sideways so the link's inner edge sits on the through
road's outer edge (the ramp lane is the outer lane before the gore), and the
move fades out over `blend_m` along the link. The node is tagged "fork" or
"merge" so the game skips the junction polygon there and tapers the through
road's width across it.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from itertools import pairwise

from osm_import.config import ImportConfig
from osm_import.graph import Point, RoadGraph

log = logging.getLogger(__name__)


@dataclass
class ForkStats:
    forks: int = 0
    merges: int = 0


def _unit_from_node(polyline: list[Point], at_start: bool) -> tuple[float, float]:
    """Unit (x, z) direction pointing from the node into the edge."""
    a, b = (polyline[0], polyline[1]) if at_start else (polyline[-1], polyline[-2])
    dx, dz = b[0] - a[0], b[2] - a[2]
    length = math.hypot(dx, dz)
    return (dx / length, dz / length) if length > 0 else (1.0, 0.0)


def shape_forks(graph: RoadGraph, cfg: ImportConfig) -> ForkStats:
    """Tags fork/merge nodes and shifts link ends to the through road's edge. Returns counts."""
    rules = cfg.forks
    stats = ForkStats()
    if not rules:
        return stats
    cos_link = math.cos(math.radians(float(rules.get("max_link_angle_deg", 40.0))))
    cos_through = math.cos(math.radians(float(rules.get("min_through_angle_deg", 140.0))))
    blend = float(rules.get("blend_m", 40.0))
    inc = graph.incident()
    for nid in sorted(graph.nodes):
        eids = inc[nid]
        if len(eids) != 3:
            continue
        arms = []
        for eid in eids:
            e = graph.edges[eid]
            at_start = e.from_node == nid
            arms.append((eid, _unit_from_node(e.polyline, at_start), at_start))
        # The through pair is the most opposite pair; the remaining arm is the link.
        pairs = [(0, 1, 2), (0, 2, 1), (1, 2, 0)]
        dots = [arms[i][1][0] * arms[j][1][0] + arms[i][1][1] * arms[j][1][1] for i, j, _k in pairs]
        best = min(range(3), key=lambda n: dots[n])
        if dots[best] > cos_through:
            continue  # no straight-through pair
        i, j, k = pairs[best]
        link_eid, link_dir, link_at_start = arms[k]
        # The link runs alongside whichever through arm it points most nearly along.
        along = max(
            (arms[i], arms[j]), key=lambda arm: arm[1][0] * link_dir[0] + arm[1][1] * link_dir[1]
        )
        if along[1][0] * link_dir[0] + along[1][1] * link_dir[1] < cos_link:
            continue  # too sharp to be a ramp
        link = graph.edges[link_eid]
        through = graph.edges[along[0]]
        # Lanes to lanes: the ramp lane continues the outer lane, shoulders aside.
        hw_t = (through.width_m - through.shoulder_left_m - through.shoulder_right_m) / 2.0
        hw_l = (link.width_m - link.shoulder_left_m - link.shoulder_right_m) / 2.0
        if hw_l >= hw_t - 0.05:
            continue  # not narrower than the road it leaves: not a ramp
        tx, tz = along[1]
        nx, nz = -tz, tx
        if nx * link_dir[0] + nz * link_dir[1] < 0.0:
            nx, nz = -nx, -nz  # normal toward the link's side
        shift = hw_t - hw_l
        _shift_end(link, link_at_start, nx * shift, nz * shift, blend)
        graph.nodes[nid].junction_type = "fork" if link_at_start else "merge"
        if link_at_start:
            stats.forks += 1
        else:
            stats.merges += 1
    log.info("forks: %d forks, %d merges shaped", stats.forks, stats.merges)
    return stats


def _shift_end(edge, at_start: bool, sx: float, sz: float, blend: float) -> None:
    """Moves the end vertex by (sx, sz) and fades the move out over `blend` metres."""
    pl = list(edge.polyline)
    if not at_start:
        pl.reverse()
    # A vertex at the end of the blend keeps the peel shape when the first segment is long.
    walked = 0.0
    out = [pl[0]]
    inserted = False
    for a, b in pairwise(pl):
        seg = math.hypot(b[0] - a[0], b[2] - a[2])
        if not inserted and walked < blend < walked + seg:
            t = (blend - walked) / seg
            out.append(
                (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
            )
            inserted = True
        out.append(b)
        walked += seg
    walked = 0.0
    shifted = []
    prev = None
    for p in out:
        if prev is not None:
            walked += math.hypot(p[0] - prev[0], p[2] - prev[2])
        f = max(0.0, 1.0 - walked / blend) if blend > 0 else 0.0
        shifted.append((p[0] + sx * f, p[1], p[2] + sz * f))
        prev = p
    if not at_start:
        shifted.reverse()
    edge.polyline = shifted
