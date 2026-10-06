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


@dataclass
class SplitStats:
    splits: int = 0
    skipped_sides: int = 0  # carriageway pairs drawn on the wrong sides for right-hand traffic


def shape_splits(graph: RoadGraph, cfg: ImportConfig) -> SplitStats:
    """Lines up a two-way road's end with the one-way carriageways it splits into.

    A node with three roads, one two-way and two one-way carriageways leaving the same way
    within `max_split_angle_deg` of each other, one carrying traffic away from the node and one
    toward it, and the pair roughly opposite the two-way road (`min_through_angle_deg`), is
    where a road divides (#78, Colonel By Drive). OSM draws both carriageways from the two-way
    road's centreline, so their ribbons start on top of each other and the road pinches to one
    carriageway's width at the split. Each carriageway's end moves sideways onto its own side
    of the two-way road, the one carrying traffic away on the right, so their outer edges
    continue the two-way road's edges; the move fades out over `blend_m`. Returns counts.
    """
    rules = cfg.forks
    stats = SplitStats()
    if not rules:
        return stats
    cos_split = math.cos(math.radians(float(rules.get("max_split_angle_deg", 35.0))))
    cos_through = math.cos(math.radians(float(rules.get("min_through_angle_deg", 140.0))))
    blend = float(rules.get("blend_m", 40.0))
    inc = graph.incident()
    for nid in sorted(graph.nodes):
        eids = inc[nid]
        if len(eids) != 3:
            continue
        two_way = [eid for eid in eids if not graph.edges[eid].oneway]
        one_way = sorted(eid for eid in eids if graph.edges[eid].oneway)
        if len(two_way) != 1 or len(one_way) != 2:
            continue
        trunk = graph.edges[two_way[0]]
        a, b = (graph.edges[eid] for eid in one_way)
        if (a.from_node == nid) == (b.from_node == nid):
            continue  # both leave or both arrive: not the two halves of one road
        da = _unit_from_node(a.polyline, a.from_node == nid)
        db = _unit_from_node(b.polyline, b.from_node == nid)
        if da[0] * db[0] + da[1] * db[1] < cos_split:
            continue  # too far apart to be one road dividing
        mx, mz = da[0] + db[0], da[1] + db[1]
        m = math.hypot(mx, mz)
        if m < 1e-9:
            continue
        ux, uz = mx / m, mz / m  # the way the divided road leaves the node
        dt = _unit_from_node(trunk.polyline, trunk.from_node == nid)
        if dt[0] * ux + dt[1] * uz > cos_through:
            continue  # the two-way road does not continue straight into the pair
        rx, rz = -uz, ux  # right of travel along u (x east, z south)
        leaving, arriving = (a, b) if a.from_node == nid else (b, a)
        d_leave = da if leaving is a else db
        d_arrive = db if leaving is a else da
        # Right-hand traffic: the carriageway carrying traffic away from the node is the one on
        # the right of u. A pair drawn the other way round is left alone.
        side_leave = d_leave[0] * rx + d_leave[1] * rz
        side_arrive = d_arrive[0] * rx + d_arrive[1] * rz
        if side_leave < side_arrive:
            stats.skipped_sides += 1
            continue
        hw_t = trunk.width_m / 2.0
        for edge, sign in ((leaving, 1.0), (arriving, -1.0)):
            shift = max(hw_t - edge.width_m / 2.0, 0.0)
            _shift_end(edge, edge.from_node == nid, rx * sign * shift, rz * sign * shift, blend)
        stats.splits += 1
    log.info(
        "splits: %d roads dividing shaped (%d drawn on the wrong sides, left)",
        stats.splits,
        stats.skipped_sides,
    )
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
