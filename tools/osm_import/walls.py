"""Retaining walls where the ground rises beside a road (add-retaining-walls).

Approach: walk the outer edge of what every ground-level road carries beside it, every
`step_m`: the sidewalk's outer edge where a sidewalk runs along that side, else the road's
edge (its width already holds its shoulders). At each station the finished terrain is read
outward from that edge, perpendicular to the road, for the first 1 m window that climbs more
than 1 m for every `slope` m out. Where the climb starts within `probe_m` of the edge, the wall
stands at the edge; where it starts further out, up to `reach_m` (a bare road's own flat
margin and shoulder put every bank at least that far from its edge), the wall stands where
the climb starts (the running median of that over `smooth_stations`, so the line is
straight). Where the ground `probe_m` past the wall's foot then stands more than 1 m per
`slope` m above the foot (and over `min_rise_m`), and is not another carriageway running
alongside, that station is wall. Stations where a way leaves the road
through the foot (a junction's outline, another road's ribbon, a path crossing the edge
line, all at about the road's level) are hard breaks; short gaps of no-wall stations between
two wall stretches are joined; stretches shorter than `min_length_m` are dropped. A wall's top
is the ground `probe_m` behind it (at a sidewalk's edge, the highest ground within two cells),
or the soffit of a deck over it, whichever is lower, and at most `max_top_m`; its foot is the
edge's level.

Then the terrain in front of each wall (from the road's edge out to the wall) is held at the
edge's level, and where the wall stands at a sidewalk's edge the first cell behind it too, so
the step up to the bank happens behind the wall's face and never pokes through the sidewalk.
Cells a junction or another road owns are left alone, and the ground is never raised above
another road's bed.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field

import numpy as np

from osm_import.barriers import _samples
from osm_import.bridges import BridgesResult
from osm_import.config import ImportConfig
from osm_import.elevation import _seg_dist, _SegmentIndex
from osm_import.graph import RoadGraph
from osm_import.junctions import JunctionSurface
from osm_import.pack import (
    CHUNK_SIZE_M,
    COVER_MARGIN_M,
    FLAT_MARGIN_M,
    ROAD_SURFACE_DROP_M,
    SAMPLES_PER_CHUNK,
    SHOULDER_M,
    TERRAIN_RES_M,
    ChunkTerrain,
    _in_triangle,
    _junction_field,
    _lowest_bed,
    _road_footprints,
    ground_junctions,
)

log = logging.getLogger(__name__)

DEFAULTS = {
    "min_rise_m": 1.0,  # the ground probe_m past the foot stands at least this far above it
    "slope": 1.5,  # the climb that is a bank: more than 1 m per this many metres out
    "probe_m": 4.0,  # the wall stands at the edge when the climb starts within this of it
    "reach_m": 8.0,  # else where the climb starts, up to this far out
    "step_m": 2.0,
    "min_length_m": 6.0,
    "join_gap_m": 4.0,  # no-wall gaps up to this long between two stretches are filled
    "sidewalk_range_m": 3.5,  # a sidewalk this close to the ribbon edge is the road's
    "sidewalk_along_deg": 40.0,  # and runs within this angle of the road
    "top_reach_cells": 2,  # at a sidewalk's edge the top is the highest ground this many cells behind
    "min_top_m": 0.3,  # a wall never stands shorter than this (joined gaps, deck soffits)
    "max_top_m": 8.0,  # and never taller: above that the bank goes on as a slope
    "smooth_stations": 9,  # a bare road's wall line: the running median over this many stations, then the mean over a quarter
}
COORD_DECIMALS = 2
SLOPE_SAMPLE_M = 1.0  # the climb is read over windows this long between the edge and the probe
WAY_MARGIN_M = 0.3  # a way's ribbon this much wider still breaks the wall
BED_SLACK_M = 0.2  # the hold never raises a cell more than this above another road's bed
LEVEL_M = 2.5  # a way further than this above or below the edge passes over or under it
SIDEWALK_LEVEL_M = 0.75  # a sidewalk further than this from the road's level is not its own
# In front of a wall another road's ribbon plus this stays: EdgeDropReport reads the ground up
# to 1 m outside a ribbon, and a cell lowered there is a wheel trap on that road. Behind the
# wall another road's whole grading (its flat margin and shoulder) stays: a cell lowered just
# past the flat margin still pulls the interpolated ground at that road's edge down.
FRONT_KEEP_M = 1.5
BEHIND_KEEP_M = FLAT_MARGIN_M + SHOULDER_M


@dataclass
class Wall:
    id: str
    edge_id: str
    points: list[tuple[float, float, float]]  # the foot, on the ground in front
    tops_m: list[float]  # height above each point
    # Importer-only: how far the held ground reaches in from each point toward the road
    # (the wall's offset from the centreline less the road's half width), and the road's own
    # level at each point (the ground between the road and a lower sidewalk follows the road).
    depth_m: list[float] = field(default_factory=list)
    road_y: list[float] = field(default_factory=list)
    # Importer-only: how far behind each point the ground is held too (one cell where the wall
    # stands at a sidewalk's edge, so the bank never pokes through the sidewalk; 0 elsewhere).
    behind_m: list[float] = field(default_factory=list)
    side: float = 0.0  # -1 left of travel, +1 right (the outward normal's sign)

    @property
    def height_m(self) -> float:
        return max(self.tops_m) if self.tops_m else 0.0

    def length_m(self) -> float:
        return sum(
            math.dist((a[0], a[2]), (b[0], b[2])) for a, b in zip(self.points, self.points[1:])
        )


@dataclass
class WallsResult:
    walls: list[Wall] = field(default_factory=list)
    stations: int = 0  # edge stations scanned
    wall_stations: int = 0  # of those, wall before joining and filtering

    def counts(self) -> dict:
        return {
            "walls": len(self.walls),
            "metres": round(sum(w.length_m() for w in self.walls), 1),
            "tallest_m": round(max((w.height_m for w in self.walls), default=0.0), 2),
            "stations": self.stations,
            "wall_stations": self.wall_stations,
        }

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, x east, y up, z south; points are the wall's foot, tops_m its height above each",
            "walls": [
                {
                    "id": w.id,
                    "edge_id": w.edge_id,
                    "height_m": round(w.height_m, 2),
                    "points": [
                        [
                            round(x, COORD_DECIMALS),
                            round(y, COORD_DECIMALS),
                            round(z, COORD_DECIMALS),
                        ]
                        for x, y, z in w.points
                    ],
                    "tops_m": [round(t, 2) for t in w.tops_m],
                }
                for w in sorted(self.walls, key=lambda w: w.id)
            ],
        }


def _in_polygon(x: float, z: float, poly: list) -> bool:
    inside = False
    n = len(poly)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        if (az > z) != (bz > z) and x < ax + (z - az) * (bx - ax) / (bz - az):
            inside = not inside
    return inside


class _Junctions:
    """Junction outlines on a coarse grid, for asking whether a point is in or beside one."""

    def __init__(self, junctions: list[JunctionSurface], cell: float = 32.0) -> None:
        self.cell = cell
        self.grid: dict[tuple[int, int], list[JunctionSurface]] = {}
        for j in junctions:
            if len(j.polygon) < 3:
                continue
            x0, z0, x1, z1 = j.bounds()
            for cx in range(math.floor((x0 - 1) / cell), math.floor((x1 + 1) / cell) + 1):
                for cz in range(math.floor((z0 - 1) / cell), math.floor((z1 + 1) / cell) + 1):
                    self.grid.setdefault((cx, cz), []).append(j)

    def near(self, x: float, z: float, y: float, margin: float) -> bool:
        """Inside a junction's outline, or within `margin` of it, at about height `y`."""
        for j in self.grid.get((math.floor(x / self.cell), math.floor(z / self.cell)), []):
            if abs(j.centre[1] - y) > LEVEL_M:
                continue  # a junction on a deck over the road, or in a cutting under it
            if _in_polygon(x, z, j.polygon):
                return True
            poly = j.polygon
            for i in range(len(poly)):
                a, b = poly[i], poly[(i + 1) % len(poly)]
                if _seg_dist(x, z, a[0], a[1], b[0], b[1]) <= margin:
                    return True
        return False


def build_walls(
    graph: RoadGraph,
    sample,
    bridges: BridgesResult | None,
    cfg: ImportConfig,
    junctions: list[JunctionSurface] | None = None,
) -> WallsResult:
    """Wall lines along the graph's ground roads, read off the finished terrain (`sample(x, z)`,
    the built chunks). Bridges give the deck soffits a wall under a deck stops at."""
    rules = dict(DEFAULTS)
    rules.update(cfg.walls)
    result = WallsResult()
    step = float(rules["step_m"])
    probe = float(rules["probe_m"])
    reach = float(rules["reach_m"])
    min_rise = float(rules["min_rise_m"])
    slope_rise = SLOPE_SAMPLE_M / float(rules["slope"])  # the climb over one window that is a wall
    sw_range = float(rules["sidewalk_range_m"])
    along_cos = math.cos(math.radians(float(rules["sidewalk_along_deg"])))
    reach_cells = int(rules["top_reach_cells"])
    min_top = float(rules["min_top_m"])
    max_top = float(rules["max_top_m"])
    smooth_n = max(1, int(rules["smooth_stations"]))
    min_probe_rise = max(min_rise, probe / float(rules["slope"]))  # the spec's 1 m per 1.5 m out
    join_gap = float(rules["join_gap_m"])
    min_length = float(rules["min_length_m"])

    road_index = _SegmentIndex()
    widest = 0.0
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.tunnel:
            continue
        widest = max(widest, e.width_m)
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            road_index.add((a[0], a[2]), (b[0], b[2]), (eid, e.width_m / 2.0, a[1], b[1]))
    sw_index = _SegmentIndex()  # sidewalks, with their heights
    ped_index = _SegmentIndex()  # every drawn pedestrian way, for paths leaving the road
    for w in graph.pedestrian:
        if w.covered:
            continue
        for i in range(len(w.polyline) - 1):
            a, b = w.polyline[i], w.polyline[i + 1]
            if w.kind == "sidewalk":
                sw_index.add((a[0], a[2]), (b[0], b[2]), (w.id, w.width_m / 2.0, a[1], b[1]))
            ped_index.add((a[0], a[2]), (b[0], b[2]), (w.id, w.width_m / 2.0, a[1], b[1]))
    deck_index = _SegmentIndex()  # deck strips with the soffit height at each end
    if bridges is not None:
        for b in bridges.bridges:
            for d in b.decks:
                for i in range(len(d.points) - 1):
                    a, c = d.points[i], d.points[i + 1]
                    half = max(d.left_m[i], d.left_m[i + 1], d.right_m[i], d.right_m[i + 1])
                    deck_index.add(
                        (a[0], a[2]), (c[0], c[2]), (half, a[1] - b.depth_m, c[1] - b.depth_m)
                    )
    outlines = _Junctions(junctions if junctions is not None else ground_junctions(graph))

    def sidewalk_beside(x, y, z, nx, nz, dx, dz, hw):
        """(outer edge distance from the centreline, height) of the nearest sidewalk running
        along this side of the road within range of its ribbon edge, at about its level, or
        None."""
        ex, ez = x + nx * hw, z + nz * hw
        best = None
        for a, b, (_wid, whw, ya, yb) in sw_index.near(ex, ez, sw_range + 4.0):
            wdx, wdz = b[0] - a[0], b[1] - a[1]
            wl = math.hypot(wdx, wdz)
            if wl < 1e-6 or abs(wdx * dx + wdz * dz) / wl < along_cos:
                continue  # crossing the road's line, not running along it
            l2 = wl * wl
            t = max(0.0, min(1.0, ((ex - a[0]) * wdx + (ez - a[1]) * wdz) / l2))
            px, pz = a[0] + wdx * t, a[1] + wdz * t
            out = (px - x) * nx + (pz - z) * nz  # the sidewalk's centreline, from the road's
            if out <= hw - whw:
                continue  # on the other side, or under the road
            d = math.hypot(ex - px, ez - pz)
            if d - whw > sw_range:
                continue
            ys = ya + (yb - ya) * t
            if abs(ys - y) > SIDEWALK_LEVEL_M:
                continue  # a sidewalk of a lower or higher street, not this road's
            if best is None or d < best[0]:
                best = (d, out + whw, ys)
        return None if best is None else (best[1], best[2])

    def soffit_over(x, z):
        """The lowest deck soffit over (x, z), or inf."""
        low = math.inf
        for a, b, (half, sa, sb) in deck_index.near(x, z, widest + 10.0):
            dx, dz = b[0] - a[0], b[1] - a[1]
            l2 = dx * dx + dz * dz
            t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
            if math.hypot(x - a[0] - dx * t, z - a[1] - dz * t) <= half:
                low = min(low, sa + (sb - sa) * t)
        return low

    def on_parallel_road(x, z, dx, dz, own) -> bool:
        """True when (x, z) lies in the grading zone (ribbon, flat margin and shoulder) of
        another way running along this road: the other carriageway of a split, a ramp beside
        the mainline, a motorway above its frontage road. That ground is the other road's
        surface or its embankment, not a bank to wall (gores, medians and embankments are
        theirs); a road crossing over, like the 417 over Metcalfe Street, still is."""
        way = own.split(".")[0]
        zone = FLAT_MARGIN_M + SHOULDER_M
        for a, b, (oid, ohw, _ya, _yb) in road_index.near(x, z, widest / 2.0 + zone):
            if oid.split(".")[0] == way:
                continue
            odx, odz = b[0] - a[0], b[1] - a[1]
            ol = math.hypot(odx, odz)
            if ol < 1e-6 or abs(odx * dx + odz * dz) / ol < along_cos:
                continue
            if _seg_dist(x, z, a[0], a[1], b[0], b[1]) <= ohw + zone:
                return True
        return False

    def level_with(a, b, ya, yb, x, z, y) -> bool:
        """True when segment a-b's height at its point nearest (x, z) is within LEVEL_M of y."""
        dx, dz = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
        return abs(ya + (yb - ya) * t - y) <= LEVEL_M

    def way_leaves(x, z, y, own, dx, dz):
        """True when a way other than this road passes through (x, z) at about its level: a
        road's ribbon, a junction's outline, or a path crossing the edge line. A road or path
        well above or below (the 417's approach beside Metcalfe Street) passes over or under."""
        if outlines.near(x, z, y, COVER_MARGIN_M):
            return True
        way = own.split(".")[0]
        for a, b, (oid, ohw, ya, yb) in road_index.near(x, z, widest / 2.0 + WAY_MARGIN_M):
            if oid.split(".")[0] == way:
                continue
            if _seg_dist(x, z, a[0], a[1], b[0], b[1]) <= ohw + WAY_MARGIN_M and level_with(
                a, b, ya, yb, x, z, y
            ):
                return True
        for a, b, (_wid, whw, ya, yb) in ped_index.near(x, z, 6.0):
            wdx, wdz = b[0] - a[0], b[1] - a[1]
            wl = math.hypot(wdx, wdz)
            if wl < 1e-6 or abs(wdx * dx + wdz * dz) / wl >= along_cos:
                continue  # running along the road: the sidewalk the wall stands behind
            if _seg_dist(x, z, a[0], a[1], b[0], b[1]) <= whw + WAY_MARGIN_M and level_with(
                a, b, ya, yb, x, z, y
            ):
                return True
        return False

    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.bridge or e.tunnel or e.road_class == "parking" or len(e.polyline) < 2:
            continue
        hw = e.width_m / 2.0
        for side in (-1.0, 1.0):
            stations = list(_samples(e.polyline, step))
            feet: list = []  # per station: (outer, edge_y, start, at_edge, beside)
            for x, y, z, dx, dz in stations:
                nx, nz = -dz * side, dx * side
                beside = sidewalk_beside(x, y, z, nx, nz, dx, dz, hw)
                outer, edge_y = beside if beside is not None else (hw, y)
                result.stations += 1
                # Where the ground starts climbing: the last 1 m station before the first
                # window steeper than the slope, out to `reach` from the outer edge.
                start = None
                last = sample(x + nx * outer, z + nz * outer)
                k = SLOPE_SAMPLE_M
                while k <= reach + 1e-6:
                    g = sample(x + nx * (outer + k), z + nz * (outer + k))
                    if g - last > slope_rise:
                        start = k - SLOPE_SAMPLE_M
                        break
                    last = g
                    k += SLOPE_SAMPLE_M
                # At a sidewalk's edge when the climb starts within the probe of it; a bare
                # road's wall always stands where the climb starts (its own margin is level).
                at_edge = beside is not None and start is not None and start < probe
                feet.append((outer, edge_y, start, at_edge, beside))
            # A bare road's wall stands where the climb starts, which jumps from station to
            # station on the 4 m grid: the running median of the offsets straightens it.
            offsets = [
                outer if (at_edge or start is None) else outer + start
                for outer, _ey, start, at_edge, _b in feet
            ]
            walked = [not at_edge and start is not None for _o, _ey, start, at_edge, _b in feet]
            smoothed = _smooth(offsets, walked, smooth_n)
            pts: list = []  # (x, y, z) the foot
            tops: list = []
            depths: list = []
            road_ys: list = []
            behinds: list = []
            keep: list = []  # wall here
            hard: list = []  # a way leaves here: never joined across
            for (x, y, z, dx, dz), (outer, edge_y, start, at_edge, beside), foot in zip(
                stations, feet, smoothed
            ):
                nx, nz = -dz * side, dx * side
                fx, fz = x + nx * foot, z + nz * foot
                foot_y = edge_y if at_edge else max(edge_y, sample(fx, fz) + ROAD_SURFACE_DROP_M)
                leaves = way_leaves(fx, fz, foot_y, eid, dx, dz)
                px, pz = fx + nx * probe, fz + nz * probe
                bank = not on_parallel_road(px, pz, dx, dz, eid)
                if at_edge:
                    # The bank is right behind the sidewalk, and the cell behind the wall is
                    # held down to the foot: the top is the highest ground within reach.
                    ground = max(
                        sample(fx + nx * TERRAIN_RES_M * c, fz + nz * TERRAIN_RES_M * c)
                        for c in range(1, reach_cells + 1)
                    )
                else:
                    # Beside a bare road the wall holds the first cell of the bank only; a
                    # taller wall would leave a slot between its back and the slope.
                    ground = sample(px, pz)
                rise = ground - foot_y  # what the wall would hold back
                top = min(min(ground, soffit_over(fx, fz)) - foot_y, max_top)
                is_wall = (
                    start is not None
                    and bank
                    and rise > min_probe_rise
                    and not leaves
                    and top > min_top
                )
                if is_wall:
                    result.wall_stations += 1
                pts.append((fx, foot_y, fz))
                tops.append(max(top, min_top))
                depths.append(foot - hw)
                road_ys.append(y)
                behinds.append(TERRAIN_RES_M if at_edge and beside is not None else 0.0)
                keep.append(is_wall)
                hard.append(leaves)
            _join_gaps(pts, keep, hard, join_gap)
            n = 0
            for lo, hi in _stretches(keep):
                wall = Wall(
                    f"w:{eid}:{'l' if side < 0 else 'r'}{n}",
                    eid,
                    pts[lo:hi],
                    tops[lo:hi],
                    depths[lo:hi],
                    road_ys[lo:hi],
                    behinds[lo:hi],
                    side,
                )
                if wall.length_m() < min_length:
                    continue
                result.walls.append(wall)
                n += 1
    log.info("retaining walls: %s", result.counts())
    return result


def _smooth(offsets: list[float], walked: list[bool], n: int) -> list[float]:
    """The walked stations' offsets, each replaced by the running median over `n` walked
    stations and then the running mean over half as many, so a bare road's wall line runs
    straight instead of stepping with the terrain grid. Other stations keep their offset."""
    half = n // 2
    medians = list(offsets)
    for i, is_walked in enumerate(walked):
        if not is_walked:
            continue
        window = sorted(
            offsets[j]
            for j in range(max(0, i - half), min(len(offsets), i + half + 1))
            if walked[j]
        )
        medians[i] = window[len(window) // 2]
    quarter = max(1, n // 4)
    out = list(medians)
    for i, is_walked in enumerate(walked):
        if not is_walked:
            continue
        window = [
            medians[j]
            for j in range(max(0, i - quarter), min(len(offsets), i + quarter + 1))
            if walked[j]
        ]
        out[i] = sum(window) / len(window)
    return out


def _stretches(keep: list[bool]) -> list[tuple[int, int]]:
    """[lo, hi) index ranges of consecutive true stations, two or more long."""
    out = []
    i = 0
    while i < len(keep):
        if not keep[i]:
            i += 1
            continue
        j = i
        while j < len(keep) and keep[j]:
            j += 1
        if j - i >= 2:
            out.append((i, j))
        i = j
    return out


def _join_gaps(pts: list, keep: list[bool], hard: list[bool], join_gap: float) -> None:
    """Marks no-wall stations between two wall stations as wall when the gap between them is
    at most `join_gap` long and no way leaves the road inside it."""
    n = len(keep)
    i = 0
    while i < n:
        if keep[i]:
            i += 1
            continue
        j = i
        while j < n and not keep[j]:
            j += 1
        if 0 < i and j < n and not any(hard[i:j]):
            gap = math.dist((pts[i - 1][0], pts[i - 1][2]), (pts[j][0], pts[j][2]))
            if gap <= join_gap + 1e-6:
                for k in range(i, j):
                    keep[k] = True
        i = j


def hold_in_front_of_walls(
    chunks: list[ChunkTerrain], graph: RoadGraph, walls: WallsResult, buildings=None
) -> int:
    """Sets the terrain between each wall and its road, and where the wall stands at a
    sidewalk's edge one cell beyond it, to the wall's foot level (less ROAD_SURFACE_DROP_M), so
    the rise to the bank starts behind the wall's face. Between the road and a sidewalk lower than it the ground follows the road, as
    the road's own flat zone does (a wheel must not drop off the road's edge). In front of the
    wall only another road's ribbon (plus FRONT_KEEP_M) is left alone; behind it another road's
    whole grading zone (BEHIND_KEEP_M) is, so the hold never opens a drop at that road's edge. Cells a junction owns or a building stands
    on keep their height, and no cell is raised above another road's bed. Returns cells
    changed."""
    if not walls.walls:
        return 0
    roads, _bridges = _road_footprints(graph, include_pedestrian=False)
    # Every ground road's ribbon with its way: a wall's own road never protects the band in
    # front of its wall (the band lies in that road's flat zone by construction).
    ribbons = []
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.bridge or e.tunnel:
            continue
        way = eid.split(".")[0]
        for a, b in zip(e.polyline, e.polyline[1:]):
            ribbons.append((way, a[0], a[2], b[0], b[2], e.width_m / 2.0))
    junctions = ground_junctions(graph)
    changed = 0
    s = SAMPLES_PER_CHUNK
    for chunk in chunks:
        near = [
            w
            for w in walls.walls
            if _touches(w, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, TERRAIN_RES_M * 2)
        ]
        if not near:
            continue
        xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
        zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
        gx, gz = np.meshgrid(xs, zs)
        d_j, _yj = _junction_field(chunk, junctions, FLAT_MARGIN_M)
        bed = _lowest_bed(chunk, roads)
        footprint = _footprints(chunk, gx, gz, buildings)
        target = np.full((s, s), np.inf)
        for w in near:
            front, behind, y = _band(w, gx, gz)
            band = front | behind
            if not band.any():
                continue
            rows, cols = np.nonzero(band)
            r0, r1, c0, c1 = rows.min(), rows.max() + 1, cols.min(), cols.max() + 1
            wx, wz = gx[r0:r1, c0:c1], gz[r0:r1, c0:c1]
            ribbon = np.zeros(wx.shape, dtype=bool)
            zone = np.zeros(wx.shape, dtype=bool)
            way = w.edge_id.split(".")[0]
            for rway, ax, az, bx, bz, hw in ribbons:
                half = hw + BEHIND_KEEP_M
                if rway == way or (
                    max(ax, bx) + half < wx[0, 0]
                    or min(ax, bx) - half > wx[0, -1]
                    or max(az, bz) + half < wz[0, 0]
                    or min(az, bz) - half > wz[-1, 0]
                ):
                    continue
                dx, dz = bx - ax, bz - az
                l2 = dx * dx + dz * dz
                if l2 < 1e-9:
                    continue
                t = np.clip(((wx - ax) * dx + (wz - az) * dz) / l2, 0.0, 1.0)
                d = np.hypot(wx - (ax + t * dx), wz - (az + t * dz))
                ribbon |= d <= hw + FRONT_KEEP_M
                zone |= d <= half
            keep = (front[r0:r1, c0:c1] & ~ribbon) | (behind[r0:r1, c0:c1] & ~zone)
            window = target[r0:r1, c0:c1]
            target[r0:r1, c0:c1] = np.where(keep, np.minimum(window, y[r0:r1, c0:c1]), window)
        hold = np.isfinite(target) & (d_j > FLAT_MARGIN_M) & ~footprint
        hold &= (target <= bed + BED_SLACK_M) & (np.abs(chunk.heights - target) > 0.005)
        if hold.any():
            chunk.heights = np.where(hold, target, chunk.heights).astype(np.float32)
            changed += int(hold.sum())
    return changed


def _footprints(chunk: ChunkTerrain, gx: np.ndarray, gz: np.ndarray, buildings) -> np.ndarray:
    """Per cell: whether a building's footprint covers it (its floor is at the building's
    ground height; the hold must not open a gap under its walls)."""
    inside = np.zeros(gx.shape, dtype=bool)
    if buildings is None:
        return inside
    x0, z0 = chunk.min_x, chunk.min_z
    x1, z1 = x0 + CHUNK_SIZE_M, z0 + CHUNK_SIZE_M
    for b in buildings.buildings:
        v = np.asarray(b.roof_vertices, dtype=np.float64)
        if v[:, 0].max() < x0 or v[:, 0].min() > x1 or v[:, 1].max() < z0 or v[:, 1].min() > z1:
            continue
        tri = np.asarray(b.roof_triangles, dtype=np.int64).reshape(-1, 3)
        for ia, ib, ic in tri:
            inside |= _in_triangle(gx, gz, v[ia], v[ib], v[ic])
    return inside


def _band(w: Wall, gx: np.ndarray, gz: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Per cell: whether it lies in front of wall `w` (between its road's edge and the wall),
    whether it lies in the cell behind the wall that is held too (`behind_m`), and the level
    the ground is held at: the wall's foot, or in front the road's level where that is
    higher."""
    front = np.zeros(gx.shape, dtype=bool)
    behind = np.zeros(gx.shape, dtype=bool)
    level = np.full(gx.shape, np.inf)
    for i in range(len(w.points) - 1):
        a, b = w.points[i], w.points[i + 1]
        dx, dz = b[0] - a[0], b[2] - a[2]
        l2 = dx * dx + dz * dz
        if l2 < 1e-9:
            continue
        length = math.sqrt(l2)
        nx, nz = -dz / length * w.side, dx / length * w.side  # outward, behind the wall
        t = np.clip(((gx - a[0]) * dx + (gz - a[2]) * dz) / l2, 0.0, 1.0)
        px, pz = a[0] + dx * t, a[2] + dz * t
        out = (gx - px) * nx + (gz - pz) * nz  # signed distance from the wall line, + behind
        past = np.hypot(gx - px - out * nx, gz - pz - out * nz)  # beyond the segment's ends
        depth = w.depth_m[i] + (w.depth_m[i + 1] - w.depth_m[i]) * t
        behind_m = w.behind_m[i] + (w.behind_m[i + 1] - w.behind_m[i]) * t
        here = (past <= 1.0) & (out <= behind_m) & (out >= -depth)
        y = a[1] + (b[1] - a[1]) * t - ROAD_SURFACE_DROP_M
        road = w.road_y[i] + (w.road_y[i + 1] - w.road_y[i]) * t - ROAD_SURFACE_DROP_M
        y = np.where(out <= 0.0, np.maximum(y, road), y)
        level = np.where(here, np.minimum(level, y), level)
        front |= here & (out <= 0.0)
        behind |= here & (out > 0.0)
    return front, behind & ~front, level


def _touches(w: Wall, min_x: float, min_z: float, size: float, reach: float) -> bool:
    xs = [p[0] for p in w.points]
    zs = [p[2] for p in w.points]
    return not (
        max(xs) + reach < min_x
        or min(xs) - reach > min_x + size
        or max(zs) + reach < min_z
        or min(zs) - reach > min_z + size
    )
