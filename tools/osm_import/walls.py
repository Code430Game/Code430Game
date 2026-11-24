"""Retaining walls where the ground rises beside a road (add-retaining-walls).

Approach: walk the outer edge of what every ground-level road carries beside it, every
`step_m`: the sidewalk's outer edge where a sidewalk runs along that side, else the road's
edge (its width already holds its shoulders). At each station the finished terrain is read
outward from that edge, perpendicular to the road, for the first 1 m window that climbs more
than 1 m for every `slope` m out, up to `reach_m`. Where the ground `probe_m` past the start
of that climb stands more than 1 m per `slope` m above the edge (and over `min_rise_m`), and
is not another carriageway running alongside, that station is wall.

The wall's line runs parallel to the road, never where the climb happens to start: at the
sidewalk's outer edge, or `bare_setback_m` out from a bare road's edge (the end of the road's
own level margin). Where the two meet, the line moves out no faster than `line_slew`. So a
wall is as smooth as its road.

The wall holds the ground back, so the ground is made to fit the wall, not the wall to the
ground (shape_ground_at_walls):
  - in front of the wall, and for one terrain cell's diagonal behind it, the ground is held
    at the foot's level, so no slope reaches the sidewalk or the road and none pokes through
    the wall's face (a 4 m grid cannot step: every cell that touches the face must be low);
  - behind that, out to FILL_M, the ground is raised to the wall's top where it stood lower,
    so the bank carries on from the top of the wall;
  - the strip between, where the grid climbs from the foot to the top, lies under the wall's
    cap: the game builds each wall as a solid block with a level top `cap_m` deep, so there
    is no slot behind a wall to drop into.
A top is the ground `probe_m` into the climb, or a deck's soffit where the bank behind climbs
to the deck, at most `max_top_m`; tops are smoothed along the wall, taper to the ground at
both ends, and are lowered wherever the shaped ground at the back of the cap stands lower
(another road's grading or a building kept it), so a wall never stands above what it holds.

Stations where a way leaves the road through the foot (a junction's outline, another road's
ribbon, a path crossing the line, all at about the road's level) are hard breaks, and a
station whose cap would cover a lower road, junction or path is no wall; short gaps of no-wall
stations between two wall stretches are joined; stretches shorter than `min_length_m` or
lower than `min_height_m` are dropped.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from itertools import pairwise

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
    ChunkSampler,
    ChunkTerrain,
    _in_triangle,
    _junction_field,
    _lowest_bed,
    _road_footprints,
    ground_junctions,
)

log = logging.getLogger(__name__)

DEFAULTS = {
    "min_rise_m": 1.0,  # the ground probe_m into the climb stands at least this far above the edge
    "slope": 1.5,  # the climb that is a bank: more than 1 m per this many metres out
    "probe_m": 4.0,  # how far into the climb the bank's height is read
    "reach_m": 8.0,  # the climb starts within this of the outer edge
    "step_m": 2.0,
    "min_length_m": 6.0,
    "min_height_m": 1.5,  # a wall whose tallest point is lower than this is dropped
    "join_gap_m": 4.0,  # no-wall gaps up to this long between two stretches are filled
    "sidewalk_range_m": 8.0,  # a sidewalk this close to the ribbon edge is the road's
    "sidewalk_along_deg": 40.0,  # and runs within this angle of the road
    "bare_setback_m": 4.0,  # a bare road's wall stands this far from its edge (its level margin)
    "line_slew": 0.25,  # the line moves out from the road at most this many metres per metre along
    "taper": 1.0,  # a wall's ends come down to min_top_m this many metres per metre along
    "crest_gap_m": 2.0,  # the wall goes to the bank's crest when that is within this of the probed height
    "deck_gap_m": 1.0,  # under a deck the wall meets the soffit when the bank climbs to within this of it
    "max_turn_deg": 30.0,  # a wall whose line turns more than this at one point is dropped
    "min_top_m": 0.3,  # a wall never stands shorter than this (its tapered ends)
    "max_top_m": 8.0,  # and never taller: above that the bank goes on as a slope
}
COORD_DECIMALS = 2
SLOPE_SAMPLE_M = 1.0  # the climb is read over windows this long between the edge and the reach
WAY_MARGIN_M = 0.3  # a way's ribbon this much wider still breaks the wall
BED_SLACK_M = 0.2  # the ground is never raised more than this above another way's bed
LEVEL_M = 2.5  # a way further than this above or below the edge passes over or under it
SIDEWALK_LEVEL_M = 0.75  # a sidewalk further than this from the road's level is not its own
# In front of a wall another road's ribbon plus this stays: EdgeDropReport reads the ground up
# to 1 m outside a ribbon, and a cell lowered there is a wheel trap on that road. Behind the
# wall another road's whole grading (its flat margin and shoulder) stays: a cell lowered just
# past the flat margin still pulls the interpolated ground at that road's edge down.
FRONT_KEEP_M = 1.5
BEHIND_KEEP_M = FLAT_MARGIN_M + SHOULDER_M
# The terrain is a 4 m grid, so the step at a wall takes a cell. Every cell with a corner in
# front of the face must be low or the ground pokes through the face: the corners of such a
# cell lie within one cell's diagonal behind the line. The climb to the top then happens in
# the cells behind those, within two diagonals: the cap covers that, and the fill behind it
# reaches a cell further so the cap's back edge always meets raised ground.
LOW_BEHIND_M = TERRAIN_RES_M * math.sqrt(2.0)
CAP_M = round(2.0 * LOW_BEHIND_M + 0.2, 1)
FILL_M = CAP_M + TERRAIN_RES_M
CAP_SINK_M = 0.5  # the cap's back edge sits this far below the top (BarrierBuilder.CAP_SINK_M)


@dataclass
class Wall:
    id: str
    edge_id: str
    points: list[tuple[float, float, float]]  # the foot, on the ground in front
    tops_m: list[float]  # height above each point
    # Importer-only: how far the held ground reaches in from each point toward the road
    # (the wall's offset from the centreline less the road's half width), the road's own
    # level at each point (the ground between the road and a lower sidewalk follows the road),
    # and the unit normal at each point, pointing behind the wall.
    depth_m: list[float] = field(default_factory=list)
    road_y: list[float] = field(default_factory=list)
    normals: list[tuple[float, float]] = field(default_factory=list)
    side: float = 0.0  # -1 left of travel, +1 right (the outward normal's sign)
    cap_m: float = CAP_M  # how far behind its face the wall's level top reaches

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
    min_top_m: float = DEFAULTS["min_top_m"]
    tops_lowered: int = 0  # tops brought down to the shaped ground behind them
    # For looking into one place: when a list, every station that found a climb is appended
    # as (x, z, side, what it came to: "wall" or why not).
    trace: list | None = None

    def counts(self) -> dict:
        return {
            "walls": len(self.walls),
            "metres": round(sum(w.length_m() for w in self.walls), 1),
            "tallest_m": round(max((w.height_m for w in self.walls), default=0.0), 2),
            "stations": self.stations,
            "wall_stations": self.wall_stations,
            "tops_lowered": self.tops_lowered,
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
                    "side": "left" if w.side < 0 else "right",
                    "cap_m": round(w.cap_m, 2),
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

    def below(self, x: float, z: float, level: float) -> bool:
        """Inside the outline of a junction that lies below `level`."""
        for j in self.grid.get((math.floor(x / self.cell), math.floor(z / self.cell)), []):
            if j.centre[1] < level and _in_polygon(x, z, j.polygon):
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
    result = WallsResult(min_top_m=float(rules["min_top_m"]))
    step = float(rules["step_m"])
    probe = float(rules["probe_m"])
    reach = float(rules["reach_m"])
    min_rise = float(rules["min_rise_m"])
    slope_rise = SLOPE_SAMPLE_M / float(rules["slope"])  # the climb over one window that is a wall
    sw_range = float(rules["sidewalk_range_m"])
    along_cos = math.cos(math.radians(float(rules["sidewalk_along_deg"])))
    min_top = float(rules["min_top_m"])
    max_top = float(rules["max_top_m"])
    min_probe_rise = max(min_rise, probe / float(rules["slope"]))  # the spec's 1 m per 1.5 m out
    join_gap = float(rules["join_gap_m"])
    min_length = float(rules["min_length_m"])
    min_height = float(rules["min_height_m"])
    setback = float(rules["bare_setback_m"])
    slew = float(rules["line_slew"])
    taper = float(rules["taper"])
    deck_gap = float(rules["deck_gap_m"])
    crest_gap = float(rules["crest_gap_m"])
    max_turn = float(rules["max_turn_deg"])

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

    def road_between(x, y, z, nx, nz, hw, out, own) -> bool:
        """True when another way's ribbon, at about this road's level, lies between this
        road's edge and `out` from its centreline: a sidewalk past it is that road's."""
        way = own.split(".")[0]
        d = hw + 1.0
        while d < out:
            px, pz = x + nx * d, z + nz * d
            for a, b, (oid, ohw, ya, yb) in road_index.near(px, pz, widest / 2.0):
                if (
                    oid.split(".")[0] != way
                    and _seg_dist(px, pz, a[0], a[1], b[0], b[1]) <= ohw
                    and abs(height_at(a, b, ya, yb, px, pz) - y) <= LEVEL_M
                ):
                    return True
            d += 1.5
        return False

    def sidewalk_beside(x, y, z, nx, nz, dx, dz, hw, own):
        """(outer edge distance from the centreline, height) of the nearest sidewalk running
        along this side of the road within range of its ribbon edge, at about its level, with
        no other road between, or None."""
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
        if best is None or road_between(x, y, z, nx, nz, hw, best[1], own):
            return None
        return best[1], best[2]

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

    def height_at(a, b, ya, yb, x, z) -> float:
        """Segment a-b's height at its point nearest (x, z)."""
        dx, dz = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
        return ya + (yb - ya) * t

    def level_with(a, b, ya, yb, x, z, y) -> bool:
        """True when segment a-b's height at its point nearest (x, z) is within LEVEL_M of y."""
        return abs(height_at(a, b, ya, yb, x, z) - y) <= LEVEL_M

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

    def under_the_cap(x, z, nx, nz, foot, level, own) -> bool:
        """True when another road, a junction or a path lies behind the foot within the cap's
        reach and below `level` (the cap's underside): the wall's solid top would cover it. A
        way at the top of the bank, or a deck over it, is above the cap and does not count."""
        way = own.split(".")[0]
        d = 1.5
        while d <= CAP_M + 1e-6:
            px, pz = x + nx * (foot + d), z + nz * (foot + d)
            if outlines.below(px, pz, level):
                return True
            for a, b, (oid, ohw, ya, yb) in road_index.near(px, pz, widest / 2.0 + WAY_MARGIN_M):
                if oid.split(".")[0] == way:
                    continue
                if (
                    _seg_dist(px, pz, a[0], a[1], b[0], b[1]) <= ohw + WAY_MARGIN_M
                    and height_at(a, b, ya, yb, px, pz) < level
                ):
                    return True
            for a, b, (_wid, whw, ya, yb) in ped_index.near(px, pz, 6.0):
                if (
                    _seg_dist(px, pz, a[0], a[1], b[0], b[1]) <= whw + WAY_MARGIN_M
                    and height_at(a, b, ya, yb, px, pz) < level
                ):
                    return True
            d += 1.5
        return False

    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.bridge or e.tunnel or e.road_class == "parking" or len(e.polyline) < 2:
            continue
        hw = e.width_m / 2.0
        for side in (-1.0, 1.0):
            stations = list(_samples(e.polyline, step))
            if len(stations) < 2:
                continue
            along = [0.0]  # metres along the road at each station
            for p, q in pairwise(stations):
                along.append(along[-1] + math.hypot(q[0] - p[0], q[2] - p[2]))
            feet: list = []  # per station: (outer, edge_y, start, has a sidewalk)
            for x, y, z, dx, dz in stations:
                nx, nz = -dz * side, dx * side
                beside = sidewalk_beside(x, y, z, nx, nz, dx, dz, hw, eid)
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
                feet.append([outer, edge_y, start, beside is not None])
            # A station that read some other sidewalk's level (two run side by side) would
            # put a step in the foot: each level is the median of three.
            levels = [f[1] for f in feet]
            for i in range(1, len(feet) - 1):
                feet[i][1] = sorted(levels[i - 1 : i + 2])[1]
            # The wall's line: the sidewalk's outer edge, or the end of a bare road's level
            # margin, wherever the bank behind it starts. Parallel to the road, so as smooth
            # as the road; where a sidewalk starts or ends it moves over gently, and never
            # inside any station's own line.
            line = _envelope(
                [outer + (0.0 if has_sw else setback) for outer, _ey, _s, has_sw in feet],
                along,
                slew,
            )
            pts: list = []  # (x, y, z) the foot
            normals: list = []
            tops: list = []
            ceilings: list = []  # the most each top may be: the soffit over it, or max_top
            decked: list = []  # the top is the soffit: the wall meets the deck
            depths: list = []
            road_ys: list = []
            keep: list = []  # wall here
            hard: list = []  # a way leaves here: never joined across
            for (x, y, z, dx, dz), (outer, edge_y, start, _sw), foot in zip(stations, feet, line):
                nx, nz = -dz * side, dx * side
                fx, fz = x + nx * foot, z + nz * foot
                foot_y = edge_y
                leaves = way_leaves(fx, fz, foot_y, eid, dx, dz)
                top = min_top
                ceiling = None
                is_wall = to_deck = False
                if start is not None and not leaves:
                    # The bank's height: the ground `probe` into the climb.
                    back = outer + start + probe
                    px, pz = x + nx * back, z + nz * back
                    ground = sample(px, pz)
                    soffit = soffit_over(fx, fz)
                    ceiling = min(soffit - foot_y, max_top)
                    # Where the bank tops out within the cap's reach and not much higher, the
                    # wall goes to the crest, so its top is level with the ground up there.
                    # Under a deck the wall is the abutment: it meets the soffit where the
                    # bank behind climbs to the deck.
                    crest = max(
                        sample(x + nx * (foot + d), z + nz * (foot + d))
                        for d in (2.0, 4.0, 6.0, 8.0, 10.0, CAP_M)
                    )
                    if ground < crest <= ground + crest_gap:
                        ground = crest
                    if soffit < math.inf and max(ground, crest) >= soffit - deck_gap:
                        ground, to_deck = max(ground, soffit), True
                    rise = ground - foot_y  # what the wall would hold back
                    top = min(ground - foot_y, ceiling)
                    why = "wall"
                    if rise <= min_probe_rise:
                        why = "low bank"
                    elif top <= min_top:
                        why = "low deck"
                    elif on_parallel_road(px, pz, dx, dz, eid):
                        why = "a road alongside"
                    elif under_the_cap(x, z, nx, nz, foot, foot_y + top - CAP_SINK_M, eid):
                        why = "a way under the cap"
                    is_wall = why == "wall"
                    if result.trace is not None:
                        result.trace.append((fx, fz, side, why))
                elif start is not None and result.trace is not None:
                    result.trace.append((fx, fz, side, "a way leaves"))
                if is_wall:
                    result.wall_stations += 1
                pts.append((fx, foot_y, fz))
                normals.append((nx, nz))
                tops.append(max(top, min_top))
                ceilings.append(ceiling)
                decked.append(is_wall and to_deck)
                depths.append(foot - hw)
                road_ys.append(y)
                keep.append(is_wall)
                hard.append(leaves)
            measured = list(keep)
            _join_gaps(pts, keep, hard, join_gap)
            n = 0
            for lo, hi in _stretches(keep):
                for i in range(lo, hi):
                    if ceilings[i] is None:  # a joined station: its soffit was never read
                        ceilings[i] = min(soffit_over(pts[i][0], pts[i][2]) - pts[i][1], max_top)
                wall_tops = _wall_tops(
                    tops[lo:hi],
                    measured[lo:hi],
                    decked[lo:hi],
                    ceilings[lo:hi],
                    [a - along[lo] for a in along[lo:hi]],
                    min_top,
                    # A wall that reaches its edge's end carries on along the next edge of
                    # the road (a way leaving would have stopped it short): no taper there.
                    taper if lo > 0 else 0.0,
                    taper if hi < len(stations) else 0.0,
                )
                # On the inside of a bend tighter than the line's offset the stations' feet
                # bunch up or run backwards: only those that move on along the road stay.
                kept = _moving_on(pts[lo:hi], [(s[3], s[4]) for s in stations[lo:hi]])
                wall = Wall(
                    f"w:{eid}:{'l' if side < 0 else 'r'}{n}",
                    eid,
                    [pts[lo + i] for i in kept],
                    [wall_tops[i] for i in kept],
                    [depths[lo + i] for i in kept],
                    [road_ys[lo + i] for i in kept],
                    [normals[lo + i] for i in kept],
                    side,
                )
                if wall.length_m() < min_length or wall.height_m < min_height:
                    continue
                if _sharpest_turn(wall.points) > max_turn:
                    continue  # the inside of a loop tighter than the line's offset: no line
                result.walls.append(wall)
                n += 1
    result.walls = _without_doubles(result.walls)
    log.info("retaining walls: %s", result.counts())
    return result


def _envelope(offsets: list[float], along: list[float], slew: float) -> list[float]:
    """The smallest line that is nowhere inside `offsets` and moves in or out at most `slew`
    metres per metre along: each station's offset, or a neighbour's less the slew to it."""
    out = list(offsets)
    for i in range(1, len(out)):
        out[i] = max(out[i], out[i - 1] - slew * (along[i] - along[i - 1]))
    for i in range(len(out) - 2, -1, -1):
        out[i] = max(out[i], out[i + 1] - slew * (along[i + 1] - along[i]))
    return out


def _without_doubles(walls: list[Wall], near: float = 2.5) -> list[Wall]:
    """Two roads side by side (a slip lane and its street, two ways drawn over each other)
    each find the same bank: of walls that run along each other, the longer stays. A wall is
    a double when over half its points lie within `near` of a longer wall's."""
    cell = near
    taken: dict[tuple[int, int], list[tuple[float, float]]] = {}
    kept = []
    for w in sorted(walls, key=lambda w: (-w.length_m(), w.id)):
        close = 0
        for x, _y, z in w.points:
            cx, cz = math.floor(x / cell), math.floor(z / cell)
            if any(
                math.hypot(x - px, z - pz) <= near
                for i in (cx - 1, cx, cx + 1)
                for j in (cz - 1, cz, cz + 1)
                for px, pz in taken.get((i, j), ())
            ):
                close += 1
        if close * 2 > len(w.points):
            continue
        kept.append(w)
        for x, _y, z in w.points:
            taken.setdefault((math.floor(x / cell), math.floor(z / cell)), []).append((x, z))
    return sorted(kept, key=lambda w: w.id)


def _sharpest_turn(pts: list) -> float:
    """The largest change of direction, in degrees, between two successive segments."""
    worst = 0.0
    for a, b, c in zip(pts, pts[1:], pts[2:]):
        h1 = math.atan2(b[2] - a[2], b[0] - a[0])
        h2 = math.atan2(c[2] - b[2], c[0] - b[0])
        worst = max(worst, abs((h2 - h1 + math.pi) % (2.0 * math.pi) - math.pi))
    return math.degrees(worst)


def _moving_on(pts: list, dirs: list, min_step: float = 1.0) -> list[int]:
    """Indices of the points that each lie at least `min_step` further along their road's
    direction than the last one kept; the first and the last always stay."""
    kept = [0]
    for i in range(1, len(pts)):
        a = pts[kept[-1]]
        if (pts[i][0] - a[0]) * dirs[i][0] + (pts[i][2] - a[2]) * dirs[i][1] >= min_step:
            kept.append(i)
    last = len(pts) - 1
    if kept[-1] != last:
        if len(kept) > 1:
            kept[-1] = last
        else:
            kept.append(last)
    return kept


def _wall_tops(
    tops: list[float],
    measured: list[bool],
    decked: list[bool],
    ceilings: list[float],
    along: list[float],
    min_top: float,
    taper_start: float,
    taper_end: float,
) -> list[float]:
    """One wall's tops from its stations': joined stations (not `measured`) take the line
    between their neighbours, the tops are smoothed (the median of five, then the mean of
    three) so the top is not a saw of terrain cells, a `decked` station keeps the soffit, no
    top passes its ceiling, and each end comes down to `min_top` at its taper, metres per
    metre (0: that end stands at full height)."""
    n = len(tops)
    raw = list(tops)
    known = [i for i in range(n) if measured[i]]
    for i in range(n):
        if measured[i] or not known:
            continue
        before = max((k for k in known if k < i), default=None)
        after = min((k for k in known if k > i), default=None)
        if before is None or after is None:
            raw[i] = tops[after if before is None else before]
            continue
        f = (along[i] - along[before]) / max(along[after] - along[before], 1e-9)
        raw[i] = tops[before] + (tops[after] - tops[before]) * f
    medians = [
        sorted(raw[max(0, i - 2) : i + 3])[len(raw[max(0, i - 2) : i + 3]) // 2] for i in range(n)
    ]
    out = []
    for i in range(n):
        window = medians[max(0, i - 1) : i + 2]
        t = raw[i] if decked[i] else sum(window) / len(window)
        t = min(t, ceilings[i])
        if taper_start > 0.0:
            t = min(t, min_top + taper_start * along[i])
        if taper_end > 0.0:
            t = min(t, min_top + taper_end * (along[-1] - along[i]))
        out.append(max(t, min_top))
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


def shape_ground_at_walls(
    chunks: list[ChunkTerrain], graph: RoadGraph, walls: WallsResult, buildings=None
) -> tuple[int, int]:
    """Makes the ground fit the walls, then the walls fit the ground. Returns (cells held at a
    wall's foot, cells raised to a wall's top).

    Held: the terrain between each wall and its road, and LOW_BEHIND_M behind the wall (every
    cell that touches its face), is set to the wall's foot level (less ROAD_SURFACE_DROP_M),
    so no slope reaches the road or sidewalk or pokes through the face. Between the road and
    a sidewalk lower than it the ground follows the road, as the road's own flat zone does (a
    wheel must not drop off the road's edge). In front of the wall only another road's ribbon
    (plus FRONT_KEEP_M) is left alone; behind it another road's whole grading zone
    (BEHIND_KEEP_M) is, so the hold never opens a drop at that road's edge.

    Raised: behind that, out to FILL_M, ground lower than the wall's top is raised to it, so
    the bank carries on from the top of the wall and the cap's back edge meets ground. Never
    in any road's grading zone, and never above a road's or path's bed.

    Cells a junction owns or a building stands on keep their height throughout. Last, each
    top is lowered to the shaped ground at the back of its cap where that stands lower (the
    fill was kept off it), so no wall stands above what it holds (`walls.tops_lowered`)."""
    if not walls.walls:
        return 0, 0
    roads, _bridges = _road_footprints(graph, include_pedestrian=False)
    ways, _bridges = _road_footprints(graph)  # with the paths: the fill never buries one
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
    held = raised = 0
    s = SAMPLES_PER_CHUNK
    for chunk in chunks:
        near = [
            w
            for w in walls.walls
            if _touches(w, chunk.min_x, chunk.min_z, CHUNK_SIZE_M, FILL_M + TERRAIN_RES_M)
        ]
        if not near:
            continue
        xs = chunk.min_x + np.arange(s) * TERRAIN_RES_M
        zs = chunk.min_z + np.arange(s) * TERRAIN_RES_M
        gx, gz = np.meshgrid(xs, zs)
        d_j, _yj = _junction_field(chunk, junctions, FLAT_MARGIN_M)
        bed = _lowest_bed(chunk, roads)
        bed_any = _lowest_bed(chunk, ways)
        free = (d_j > FLAT_MARGIN_M) & ~_footprints(chunk, gx, gz, buildings)
        low = np.full((s, s), np.inf)  # the foot level a cell is held at
        high = np.full((s, s), np.inf)  # the top a cell is raised to
        for w in near:
            front, behind, fill, y_low, y_high = _band(w, gx, gz)
            band = front | behind | fill
            if not band.any():
                continue
            rows, cols = np.nonzero(band)
            r0, r1, c0, c1 = rows.min(), rows.max() + 1, cols.min(), cols.max() + 1
            wx, wz = gx[r0:r1, c0:c1], gz[r0:r1, c0:c1]
            ribbon = np.zeros(wx.shape, dtype=bool)  # another road's ribbon, and a little more
            zone = np.zeros(wx.shape, dtype=bool)  # another road's grading zone
            own = np.zeros(wx.shape, dtype=bool)  # the wall's own road (another leg of it)
            way = w.edge_id.split(".")[0]
            for rway, ax, az, bx, bz, hw in ribbons:
                half = hw + BEHIND_KEEP_M
                if (
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
                if rway == way:
                    own |= d <= half
                else:
                    ribbon |= d <= hw + FRONT_KEEP_M
                    zone |= d <= half
            window = (slice(r0, r1), slice(c0, c1))
            keep_low = (front[window] & ~ribbon) | (behind[window] & ~zone)
            low[window] = np.where(keep_low, np.minimum(low[window], y_low[window]), low[window])
            keep_high = fill[window] & ~zone & ~own
            high[window] = np.where(
                keep_high, np.minimum(high[window], y_high[window]), high[window]
            )
        hold = np.isfinite(low) & free
        hold &= (low <= bed + BED_SLACK_M) & (np.abs(chunk.heights - low) > 0.005)
        heights = np.where(hold, low, chunk.heights)
        lift = np.minimum(high, bed_any + BED_SLACK_M)
        fill = np.isfinite(high) & ~np.isfinite(low) & free & (lift > heights + 0.005)
        heights = np.where(fill, lift, heights)
        if hold.any() or fill.any():
            chunk.heights = heights.astype(np.float32)
            held += int(hold.sum())
            raised += int(fill.sum())
    sample = ChunkSampler(chunks).sample
    walls.tops_lowered = 0
    for w in walls.walls:
        for i, ((x, y, z), (nx, nz)) in enumerate(zip(w.points, w.normals)):
            limit = sample(x + nx * w.cap_m, z + nz * w.cap_m) - y + CAP_SINK_M
            limit = max(limit, walls.min_top_m)
            if w.tops_m[i] > limit + 0.01:
                w.tops_m[i] = limit
                walls.tops_lowered += 1
    return held, raised


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


def _band(w: Wall, gx: np.ndarray, gz: np.ndarray) -> tuple:
    """Per cell, for wall `w`: whether it lies in front (between its road's edge and the wall),
    just behind (within LOW_BEHIND_M: held low too), or in the fill behind that (out to
    FILL_M); the level it is held at (the wall's foot, or in front the road's level where that
    is higher); and the level the fill is raised to (the wall's top)."""
    front = np.zeros(gx.shape, dtype=bool)
    behind = np.zeros(gx.shape, dtype=bool)
    fill = np.zeros(gx.shape, dtype=bool)
    y_low = np.full(gx.shape, np.inf)
    y_high = np.full(gx.shape, np.inf)
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
        here = past <= 1.0
        foot = a[1] + (b[1] - a[1]) * t
        road = w.road_y[i] + (w.road_y[i + 1] - w.road_y[i]) * t
        in_front = here & (out <= 0.0) & (out >= -depth)
        just_behind = here & (out > 0.0) & (out <= LOW_BEHIND_M)
        further = here & (out > LOW_BEHIND_M) & (out <= FILL_M)
        y_low = np.where(
            in_front, np.minimum(y_low, np.maximum(foot, road) - ROAD_SURFACE_DROP_M), y_low
        )
        y_low = np.where(just_behind, np.minimum(y_low, foot - ROAD_SURFACE_DROP_M), y_low)
        top = foot + w.tops_m[i] + (w.tops_m[i + 1] - w.tops_m[i]) * t
        y_high = np.where(further, np.minimum(y_high, top), y_high)
        front |= in_front
        behind |= just_behind
        fill |= further
    behind &= ~front
    fill &= ~(front | behind)
    return front, behind, fill, y_low, y_high


def _touches(w: Wall, min_x: float, min_z: float, size: float, reach: float) -> bool:
    xs = [p[0] for p in w.points]
    zs = [p[2] for p in w.points]
    return not (
        max(xs) + reach < min_x
        or min(xs) - reach > min_x + size
        or max(zs) + reach < min_z
        or min(zs) - reach > min_z + size
    )
