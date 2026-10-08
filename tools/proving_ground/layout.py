"""Layout of the Double Cross proving ground in local metres (x east, z south, origin at the
map centre). Everything is parameters and plain geometry; no clock, no random input, so the
same code gives the same district every time.

The shape is the human's figure eight (2026-10-08). Two straights cross near the centre: the
highway runs west to east along the river's north bank at ground level, and a vertical road
crosses the highway and the river on one bridge. The top lobe is street level through the main
city (clockwise: west along the bank road, north past the roundabout, east along the top, south
down the vertical onto the bridge); the bottom lobe is the elevated motorway (anticlockwise:
south over the centre bridge, east along the bottom, north over the river on a second bridge,
west along the bank at grade back to the crossing). Four ways on and off the loop, one per
quarter: the roundabout top left, an exit pair into the city top right, an exit pair on the
far-right ascent into the residential east, an exit pair on the vertical descent into the
residential west. Greenbelt along the top and left, the river across the middle, grids in the
three quarters, edge streets curling back, one deliberate dead end, one of every feature.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from itertools import pairwise

Point = tuple[float, float]

HALF_W = 1200.0
HALF_H = 800.0

TOWN = "Double Cross"
LOOP_ROAD = "Double Cross Loop"
HIGHWAY = "Double Cross Highway"
RIVER = "Cross River"
GANG_TURF = "the Double Cross"

# River: a band across the middle with a little wave; the bank road keeps clear of it.
RIVER_HALF_W = 35.0
# The horizontal straight: loop road west of the crossing, highway east of it. It sits 60 m
# north of the water so the viaduct crossing both has room to change height between them
# at a motorway grade; the strip between is grass and the riverside path.
BANK_Z = -40.0


def river_centre(x: float) -> float:
    return 100.0 + 15.0 * math.sin((x + 200.0) / 300.0)


# Top lobe: a rounded rectangle whose south side is the bank road and whose east side is the
# vertical straight; its south-east corner is the crossing, left open.
A_WEST, A_NORTH = -620.0, -540.0
A_CORNER = 110.0
SPLIT_Z = -300.0  # two-way street becomes the motorway pair on the vertical, heading south
MERGE_X = 120.0  # the pair merges back into the loop road on the bank, heading west
# Bottom lobe: rounded rectangle south-east of the crossing, elevated except along the bank.
B_EAST, B_SOUTH = 900.0, 620.0
B_SWEEP = 180.0  # the two fast corners
B_NE = 90.0  # the tight corner where the far-right ascent turns west onto the bank
PAIR_OFFSET = 6.0
DECK_FROM_Z = -120.0  # the viaduct begins here on the vertical (north of the bank road)
ROUNDABOUT_R = 25.0

# Grids.
MAIN_AVENUES = (-140.0, -270.0, -400.0)  # z; the roundabout sits on the middle one
MAIN_STREETS = (-470.0, -320.0, -170.0)  # x; stop signs where they meet the loop
WEST_STREETS = (-780.0, -900.0)  # x; the one-way pair west of the lobe
CITY_AVENUES = (-100.0, -400.0)  # z; Riverside Avenue and Station Avenue
CITY_STREETS = (200.0, 400.0, 600.0, 800.0, 1000.0)  # x
EAST_STREET = 1100.0  # x; Bridge Street, over the highway and the river
SOUTH_AVENUES = (250.0, 400.0, 550.0, 700.0)  # z; River, Park, Mid, South Road
SOUTH_STREETS = (-850.0, -650.0, -450.0, -250.0, -50.0, 150.0, 350.0, 550.0, 750.0, 1000.0)
GREENBELT_TOP = -640.0
GREENBELT_LEFT = -1050.0

# Minor streets fill the grids to Ottawa-sized blocks (about 70 to 100 m on a side; the human,
# 2026-10-08: "there is a lot of open space in the grid"). Each grid names its own; a segment
# that would run through a service, the park, the turf or a ramp is left out, so those keep
# their larger blocks. Frontage roads run beside the elevated motorway through the south and
# along the bank road's south side.
MAIN_MINOR_AVENUES = (-190.0, -285.0, -470.0)  # z; -285 clears the hospital and the garage
MAIN_MINOR_STREETS = (-700.0, -545.0, -85.0)  # x
CITY_MINOR_AVENUES = (-200.0, -300.0)  # z
CITY_MINOR_STREETS = (300.0, 500.0, 700.0, 900.0)  # x
SOUTH_MINOR_AVENUES = (325.0, 475.0, 625.0)  # z; 625 stops short of the viaduct's sweeps
SOUTH_MINOR_STREETS = (-750.0, -550.0, -350.0, -150.0, 50.0, 250.0, 450.0, 650.0, 875.0)  # x
VIADUCT_FRONTAGE_Z = (590.0, 650.0)  # both sides of the south straight, 6 Lane to 9 Lane
VIADUCT_LANE_X = 50.0  # east of the vertical straight, River Road to Park Road
RIVER_LANE_Z = 10.0  # the bank road's south side, First Street to a turning circle
RIVER_LANE_END_X = 760.0
BULB_R = 14.0
MINOR_MARGIN_M = 8.0  # a minor street keeps this clear of a footprint or a ramp corridor

STEP_M = 12.0  # arc sampling


@dataclass
class Way:
    id: int
    points: list[Point]
    tags: dict[str, str]


@dataclass
class Area:
    """A closed polygon feature for one of the layer files (outer ring, optional inners)."""

    id: int
    ring: list[Point]
    tags: dict[str, str]
    inners: list[list[Point]] = field(default_factory=list)


@dataclass
class Spot:
    """A standalone tagged node for a layer file (a tree, a service, an entrance)."""

    id: int
    at: Point
    tags: dict[str, str]


@dataclass
class District:
    ways: list[Way] = field(default_factory=list)
    node_tags: list[tuple[Point, dict[str, str]]] = field(default_factory=list)
    water: list[Area] = field(default_factory=list)
    buildings: list[Area] = field(default_factory=list)
    parking: list[Area] = field(default_factory=list)
    bridges: list[Area] = field(default_factory=list)
    vegetation_areas: list[Area] = field(default_factory=list)
    trees: list[Spot] = field(default_factory=list)
    tree_rows: list[Way] = field(default_factory=list)
    service_areas: list[Area] = field(default_factory=list)
    spawn: tuple[float, float, float] = (0.0, 0.0, 0.0)  # x, z, heading degrees (0 N, 90 E)
    start_line: tuple[Point, Point] = ((0.0, 0.0), (0.0, 1.0))  # point, direction of travel
    loop_names: tuple[str, ...] = (LOOP_ROAD, HIGHWAY, "Loop Circle")
    turf: list[Point] = field(default_factory=list)
    access: list[tuple[str, Point]] = field(default_factory=list)  # the four ways on and off
    _next: dict[str, int] = field(
        default_factory=lambda: {
            "way": 1000,
            "water": 30000,
            "building": 20000,
            "parking": 40000,
            "bridge": 70000,
            "veg": 60000,
            "tree": 65000,
            "service": 50000,
        }
    )

    def _id(self, kind: str) -> int:
        n = self._next[kind]
        self._next[kind] = n + 1
        return n

    def way(self, points: list[Point], **tags: str) -> Way:
        w = Way(
            self._id("way"), [_r(p) for p in points], {k: v for k, v in tags.items() if v != ""}
        )
        self.ways.append(w)
        return w

    def tag_node(self, at: Point, **tags: str) -> None:
        self.node_tags.append((_r(at), tags))

    def area(self, kind: str, ring: list[Point], **tags: str) -> Area:
        a = Area(self._id(kind), [_r(p) for p in ring], tags)
        {
            "water": self.water,
            "building": self.buildings,
            "parking": self.parking,
            "bridge": self.bridges,
            "veg": self.vegetation_areas,
            "service": self.service_areas,
        }[kind].append(a)
        return a

    def tree(self, at: Point, **tags: str) -> Spot:
        s = Spot(self._id("tree"), _r(at), tags)
        self.trees.append(s)
        return s

    def named(self, name: str) -> list[Way]:
        return [w for w in self.ways if w.tags.get("name") == name]


def _r(p: Point) -> Point:
    return (round(p[0], 3), round(p[1], 3))


# ---------------------------------------------------------------- geometry helpers


def arc(cx: float, cz: float, r: float, a0_deg: float, a1_deg: float) -> list[Point]:
    """Points on a circle from angle a0 to a1 (degrees, 0 = +x east, 90 = +z south), both ends
    included, about STEP_M apart."""
    length = abs(math.radians(a1_deg - a0_deg)) * r
    n = max(2, math.ceil(length / STEP_M))
    out = []
    for i in range(n + 1):
        a = math.radians(a0_deg + (a1_deg - a0_deg) * i / n)
        out.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return out


def line(a: Point, b: Point, step: float = 0.0) -> list[Point]:
    """A straight run, with intermediate points every `step` metres when step > 0."""
    if step <= 0.0:
        return [a, b]
    n = max(1, math.ceil(math.dist(a, b) / step))
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


def chain(*parts: list[Point]) -> list[Point]:
    """Joins runs, dropping a repeated point where one ends where the next begins."""
    out: list[Point] = []
    for part in parts:
        for p in part:
            if out and math.dist(out[-1], p) < 1e-6:
                continue
            out.append(p)
    return out


def offset(points: list[Point], d: float) -> list[Point]:
    """The polyline shifted `d` metres to the right of its direction of travel (x east,
    z south: the right of heading (dx, dz) is (-dz, dx))."""
    out = []
    n = len(points)
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, n - 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dz) or 1.0
        out.append((p[0] - dz / length * d, p[1] + dx / length * d))
    return out


def rect(x0: float, z0: float, x1: float, z1: float) -> list[Point]:
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def _project(p: Point, a: Point, b: Point) -> tuple[float, float]:
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    if l2 == 0.0:
        return 0.0, math.dist(p, a)
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2
    return t, math.dist(p, (a[0] + dx * t, a[1] + dz * t))


def insert_vertex(d: District, name: str, p: Point, tolerance: float = 3.0) -> Point:
    """Adds `p` as a vertex of the way named `name` on its nearest segment, so another way can
    share that node. Returns the rounded point."""
    p = _r(p)
    best = None
    for w in d.named(name):
        for i in range(len(w.points) - 1):
            a, b = w.points[i], w.points[i + 1]
            if p in (a, b):
                return p
            t, dist = _project(p, a, b)
            if 0.0 <= t <= 1.0 and dist <= tolerance and (best is None or dist < best[0]):
                best = (dist, w, i + 1)
    if best is None:
        raise ValueError(f"no way named {name} within {tolerance} m of {p}")
    _, w, at = best
    w.points.insert(at, p)
    return p


def split_stop(d: District, junction: Point, stop_at: Point) -> None:
    """Makes `stop_at` a vertex of the street that ends at `junction` (for a stop sign)."""
    junction, stop_at = _r(junction), _r(stop_at)
    for w in d.ways:
        if w.points[0] == junction:
            w.points.insert(1, stop_at)
            return
        if w.points[-1] == junction:
            w.points.insert(len(w.points) - 1, stop_at)
            return
    raise ValueError(f"no street ends at {junction}")


# ---------------------------------------------------------------- the pieces


def build_river(d: District) -> None:
    xs = [-HALF_W + i * 50.0 for i in range(int(2 * HALF_W / 50.0) + 1)]
    top = [(x, river_centre(x) - RIVER_HALF_W) for x in xs]
    bottom = [(x, river_centre(x) + RIVER_HALF_W) for x in reversed(xs)]
    d.area("water", top + bottom, natural="water", water="river", name=RIVER)


def build_greenbelt(d: District) -> None:
    ring = [
        (-HALF_W, -HALF_H),
        (HALF_W, -HALF_H),
        (HALF_W, GREENBELT_TOP),
        (GREENBELT_LEFT, GREENBELT_TOP),
        (GREENBELT_LEFT, HALF_H),
        (-HALF_W, HALF_H),
    ]
    d.area("veg", ring, natural="wood", name="Northbank Woods")


def top_lobe_path() -> list[Point]:
    """The street-level lobe from the crossing, clockwise: west along the bank road, north,
    east along the top, south down the vertical to the split."""
    r = A_CORNER
    return chain(
        line((MERGE_X, BANK_Z), (A_WEST + r, BANK_Z), 40.0),
        arc(A_WEST + r, BANK_Z - r, r, 90, 180),
        line((A_WEST, BANK_Z - r), (A_WEST, A_NORTH + r), 40.0),
        arc(A_WEST + r, A_NORTH + r, r, 180, 270),
        line((A_WEST + r, A_NORTH), (-r, A_NORTH), 40.0),
        arc(-r, A_NORTH + r, r, 270, 360),
        line((0.0, A_NORTH + r), (0.0, SPLIT_Z), 40.0),
    )


def bottom_lobe_centre() -> list[Point]:
    """The motorway's centre line from the split, anticlockwise: south over the centre bridge,
    east along the bottom, north over the river, west along the bank to the merge."""
    return chain(
        line((0.0, SPLIT_Z), (0.0, B_SOUTH - B_SWEEP), 30.0),
        arc(B_SWEEP, B_SOUTH - B_SWEEP, B_SWEEP, 180, 90),
        line((B_SWEEP, B_SOUTH), (B_EAST - B_SWEEP, B_SOUTH), 30.0),
        arc(B_EAST - B_SWEEP, B_SOUTH - B_SWEEP, B_SWEEP, 90, 0),
        line((B_EAST, B_SOUTH - B_SWEEP), (B_EAST, BANK_Z + B_NE), 30.0),
        arc(B_EAST - B_NE, BANK_Z + B_NE, B_NE, 0, -90),
        line((B_EAST - B_NE, BANK_Z), (MERGE_X, BANK_Z), 30.0),
    )


def build_loop(d: District) -> None:
    # Top lobe: two-way, street level, broken at the roundabout on its west side.
    a = top_lobe_path()
    rz = MAIN_AVENUES[1]
    south_pt, north_pt = (A_WEST, rz + ROUNDABOUT_R), (A_WEST, rz - ROUNDABOUT_R)
    kept = [p for p in a if not (abs(p[0] - A_WEST) < 1e-6 and abs(p[1] - rz) < ROUNDABOUT_R)]
    i_s = next(i for i, p in enumerate(kept) if abs(p[0] - A_WEST) < 1e-6 and p[1] < rz)
    street = {
        "highway": "secondary",
        "lanes": "2",
        "oneway": "no",
        "maxspeed": "50",
        "name": LOOP_ROAD,
    }
    d.way(kept[:i_s] + [south_pt], **street)
    d.way([north_pt] + kept[i_s:], **street)
    # The roundabout: one-way circle. On this map (z south) a clockwise circle in angle order
    # keeps the island on the driver's left for right-hand traffic.
    circle = [
        (
            A_WEST + ROUNDABOUT_R * math.cos(math.radians(90 - 22.5 * k)),
            rz + ROUNDABOUT_R * math.sin(math.radians(90 - 22.5 * k)),
        )
        for k in range(17)
    ]
    d.way(circle, highway="secondary", junction="roundabout", oneway="yes", name="Loop Circle")
    d.access.append(("roundabout", (A_WEST, rz)))
    # Bottom lobe: the motorway as a one-way pair. The lap carriageway heads south from the
    # split; the other runs the opposite way. Each is three ways: a ramp at grade from the
    # split, the viaduct (bridge=yes) from DECK_FROM_Z round the lower right and over the river
    # to the end of the north-east corner, then the bank straight at grade to the merge.
    centre = bottom_lobe_centre()
    i_deck = next(i for i, p in enumerate(centre) if p[1] >= DECK_FROM_Z)
    i_bank = next(
        i for i, p in enumerate(centre) if p[0] < B_EAST - B_NE and abs(p[1] - BANK_Z) < 1e-6
    )
    hw = {
        "highway": "motorway",
        "lanes": "2",
        "oneway": "yes",
        "maxspeed": "100",
        "name": HIGHWAY,
        "ref": "DC-8",
    }
    lap = offset(centre, PAIR_OFFSET)
    other = offset(centre, -PAIR_OFFSET)
    d.way([(0.0, SPLIT_Z)] + lap[: i_deck + 1], **hw)
    d.way(lap[i_deck : i_bank + 1], **hw, bridge="yes", layer="1")
    d.way(lap[i_bank:] + [(MERGE_X, BANK_Z)], **hw)
    back = other[::-1]
    j_bank = len(centre) - 1 - i_bank
    j_deck = len(centre) - 1 - i_deck
    d.way([(MERGE_X, BANK_Z)] + back[: j_bank + 1], **hw)
    d.way(back[j_bank : j_deck + 1], **hw, bridge="yes", layer="1")
    d.way(back[j_deck:] + [(0.0, SPLIT_Z)], **hw)


def _ramp(d: District, name: str, pts: list[Point]) -> None:
    d.way(pts, highway="motorway_link", oneway="yes", lanes="1", maxspeed="60", name=name)


def build_exits(d: District) -> None:
    """Three exit pairs for the lap direction, each an off-ramp and an on-ramp with its gore:
    top right into the city off the bank, bottom right on the far-right ascent into the
    residential east, bottom left on the vertical descent into the residential west."""
    lap_z_bank = BANK_Z - PAIR_OFFSET  # the lap carriageway heads west along the bank (north one)
    # Top right. Off at x = 700 to the city's Riverside Avenue at x = 600; on from x = 330.
    off0 = insert_vertex(d, HIGHWAY, (700.0, lap_z_bank))
    _ramp(
        d,
        "City Exit",
        chain(
            [off0],
            line((650.0, lap_z_bank - 12.0), (600.0, -60.0), 20.0),
            [(600.0, CITY_AVENUES[0])],
        ),
    )
    on1 = insert_vertex(d, HIGHWAY, (250.0, lap_z_bank))
    _ramp(
        d,
        "City Entrance",
        chain(
            [(330.0, CITY_AVENUES[0])],
            line((330.0, -60.0), (290.0, lap_z_bank - 12.0), 20.0),
            [on1],
        ),
    )
    insert_vertex(d, "Riverside Avenue", (600.0, CITY_AVENUES[0]))
    insert_vertex(d, "Riverside Avenue", (330.0, CITY_AVENUES[0]))
    d.access.append(("city exit", (650.0, -20.0)))
    # Bottom right: the lap carriageway heads north at x = B_EAST + PAIR_OFFSET (its right is
    # east). The entrance climbs from 10 Lane; the exit comes down onto River Road, so neither
    # crosses a street on the way.
    xe = B_EAST + PAIR_OFFSET
    lane10 = SOUTH_STREETS[9]
    # The entrance starts where Mid Road meets 10 Lane and climbs north-west; the exit leaves
    # further north and comes down to where River Road meets 10 Lane.
    on2 = insert_vertex(d, HIGHWAY, (xe, 470.0))
    _ramp(
        d,
        "East Entrance",
        chain(
            [(lane10, SOUTH_AVENUES[2])],
            line((lane10 - 30.0, 535.0), (xe + 12.0, 500.0), 20.0),
            [on2],
        ),
    )
    off2 = insert_vertex(d, HIGHWAY, (xe, 330.0))
    _ramp(
        d,
        "East Exit",
        chain(
            [off2],
            line((xe + 14.0, 300.0), (lane10 - 30.0, 258.0), 20.0),
            [(lane10, SOUTH_AVENUES[0])],
        ),
    )
    d.access.append(("east exit", (xe + 30.0, 400.0)))
    # Bottom left: the lap carriageway heads south at x = -PAIR_OFFSET (its right is west). The
    # exit leaves after the deck has cleared River Road and comes down onto 5 Lane; the
    # entrance climbs from South Road onto the south straight, heading east.
    xw = -PAIR_OFFSET
    lane5 = SOUTH_STREETS[4]
    off3 = insert_vertex(d, HIGHWAY, (xw, 280.0))
    _ramp(
        d,
        "West Exit",
        chain([off3], line((xw - 14.0, 320.0), (lane5 + 8.0, 378.0), 20.0), [(lane5, 390.0)]),
    )
    insert_vertex(d, "5 Lane", (lane5, 390.0))
    zs = B_SOUTH + PAIR_OFFSET  # the lap carriageway along the south straight, heading east
    on3 = insert_vertex(d, HIGHWAY, (500.0, zs))
    fz = VIADUCT_FRONTAGE_Z[1]
    _ramp(
        d,
        "West Entrance",
        chain([(360.0, fz)], line((420.0, fz - 10.0), (480.0, zs + 12.0), 20.0), [on3]),
    )
    insert_vertex(d, "Viaduct Road South", (360.0, fz))
    d.access.append(("west exit", (-40.0, 330.0)))


def build_main_city(d: District) -> None:
    """Top left: avenues and streets through and around the top lobe, the roundabout's avenue,
    the one-way pair to the west, signals where avenues cross the loop, stops elsewhere."""
    a1, a2, a3 = MAIN_AVENUES
    s1, s2, s3 = MAIN_STREETS
    w1, w2 = WEST_STREETS
    tert = {"highway": "tertiary", "lanes": "2", "maxspeed": "50"}
    res = {"highway": "residential", "lanes": "2", "maxspeed": "40"}
    bus = {"lanes:bus": "1", "busway:right": "lane"}
    d.way(line((w2, a1), (s3, a1)), **tert, name="Mill Avenue")
    d.way(line((w2, a2), (A_WEST - ROUNDABOUT_R, a2)), **tert, name="Circle Avenue", **bus)
    d.way(line((A_WEST + ROUNDABOUT_R, a2), (s3, a2)), **tert, name="Circle Avenue", **bus)
    # The curl west of the pair: Mill Avenue and Circle Avenue joined by a half circle.
    d.way(arc(w2, (a1 + a2) / 2.0, (a2 - a1) / 2.0, -90, -270), **res, name="West Bend")
    # Station Avenue: across both cities, over the loop's west side and the vertical at signals.
    d.way(line((w2, a3), (CITY_STREETS[4], a3), 100.0), **tert, name="Station Avenue")
    for x in (A_WEST, 0.0):
        insert_vertex(d, LOOP_ROAD, (x, a3))
        d.tag_node((x, a3), highway="traffic_signals")
    # Streets through the lobe from the bank road to the top, stops at both loop crossings.
    kerb = {"parking:right": "lane", "parking:right:orientation": "parallel"}
    for i, sx in enumerate((s1, s2, s3)):
        name = f"{['First', 'Second', 'Third'][i]} Street"
        d.way(line((sx, BANK_Z), (sx, A_NORTH)), **res, name=name, **(kerb if sx == s2 else {}))
        for z, stop in ((BANK_Z, BANK_Z - 8.0), (A_NORTH, A_NORTH + 8.0)):
            insert_vertex(d, LOOP_ROAD, (sx, z))
            split_stop(d, (sx, z), (sx, stop))
            d.tag_node((sx, stop), highway="stop")
    # First and Second continue north of the loop and curl into each other.
    top = GREENBELT_TOP + 40.0
    d.way(
        chain(
            line((s1, A_NORTH), (s1, top)),
            arc((s1 + s2) / 2.0, top, (s2 - s1) / 2.0, 180, 360),
            line((s2, top), (s2, A_NORTH)),
        ),
        **res,
        name="North Bend",
    )
    # The west pair: one-way each, opposite directions.
    d.way(
        line((w1, a1), (w1, a3)),
        highway="residential",
        lanes="1",
        oneway="yes",
        maxspeed="40",
        name="Pair Street South",
    )
    d.way(
        line((w2, a3), (w2, a1)),
        highway="residential",
        lanes="1",
        oneway="yes",
        maxspeed="40",
        name="Pair Street North",
    )
    d.way(line((w1, a1), (w2, a1)), **tert, name="Mill Avenue")
    d.way(line((w1, a2), (w2, a2)), **tert, name="Circle Avenue", **bus)
    d.way(line((w1, a3), (w2, a3)), **tert, name="Station Avenue")
    for sx in (s1, s2, s3):
        for az in (a1, a2):
            insert_vertex(d, name_at(d, az), (sx, az))
    d.tag_node((s2, a2), highway="traffic_signals")
    # Bus: stops on Circle Avenue's reserved lane and a bus-only loop at Third Street.
    for bx in (-560.0, -420.0, -250.0):
        insert_vertex(d, "Circle Avenue", (bx, a2))
        d.tag_node((bx, a2), highway="bus_stop", public_transport="stop_position", bus="yes")
    busonly = {
        "highway": "service",
        "access": "no",
        "bus": "yes",
        "oneway": "yes",
        "name": "Bus Loop",
    }
    d.way(line((s3, a2 + 60.0), (s3 - 40.0, a2 + 60.0)), **busonly)
    d.way(line((s3 - 40.0, a2 + 60.0), (s3 - 40.0, a2)), **busonly)
    d.way(line((s3, a2), (s3, a2 + 60.0)), **busonly)
    insert_vertex(d, "Third Street", (s3, a2 + 60.0))
    insert_vertex(d, "Circle Avenue", (s3 - 40.0, a2))


def name_at(d: District, z: float) -> str:
    return {
        MAIN_AVENUES[0]: "Mill Avenue",
        MAIN_AVENUES[1]: "Circle Avenue",
        MAIN_AVENUES[2]: "Station Avenue",
    }[z]


def build_city(d: District) -> None:
    """Top right between the bank highway and the greenbelt: two avenues, five streets, the
    curls at the top, the one dead end at the east edge, Bridge Street over highway and river,
    and the rail stub with its station."""
    a1, a3 = CITY_AVENUES
    tert = {"highway": "tertiary", "lanes": "2", "maxspeed": "50"}
    res = {"highway": "residential", "lanes": "2", "maxspeed": "40"}
    d.way(line((CITY_STREETS[0], a1), (EAST_STREET, a1), 100.0), **tert, name="Riverside Avenue")
    top = GREENBELT_TOP + 40.0
    names = ["Fourth", "Fifth", "Sixth", "Seventh", "Eighth"]
    for i, sx in enumerate(CITY_STREETS):
        d.way(line((sx, a1), (sx, a3)), **res, name=f"{names[i]} Street")
        insert_vertex(d, "Station Avenue", (sx, a3))
    for left, right in ((CITY_STREETS[0], CITY_STREETS[1]), (CITY_STREETS[2], CITY_STREETS[3])):
        d.way(
            chain(
                line((left, a3), (left, top)),
                arc((left + right) / 2.0, top, (right - left) / 2.0, 180, 360),
                line((right, top), (right, a3)),
            ),
            **res,
            name="Top Bend",
        )
    # Eighth Street's east end: the one deliberate dead end, cut by the map edge.
    d.way(line((CITY_STREETS[4], -270.0), (HALF_W, -270.0)), **res, name="Edge Road")
    insert_vertex(d, "Eighth Street", (CITY_STREETS[4], -270.0))
    # Bridge Street: from Riverside Avenue south over the highway and the river to River Road.
    d.way(line((EAST_STREET, a1), (EAST_STREET, -20.0)), **res, name="Bridge Street")
    d.way(
        line((EAST_STREET, -20.0), (EAST_STREET, 170.0)),
        **res,
        name="Bridge Street",
        bridge="yes",
        layer="1",
    )
    d.way(line((EAST_STREET, 170.0), (EAST_STREET, SOUTH_AVENUES[3])), **res, name="Bridge Street")
    d.area(
        "bridge",
        rect(EAST_STREET - 6.0, -24.0, EAST_STREET + 6.0, 174.0),
        man_made="bridge",
        name="East Bridge",
    )
    # Rail stub along the greenbelt with a station (inert until add-rail).
    rz = GREENBELT_TOP + 12.0
    d.way(
        line((CITY_STREETS[0] - 60.0, rz), (CITY_STREETS[4] + 60.0, rz)),
        railway="rail",
        name="Cross Line",
    )
    d.tag_node(
        (CITY_STREETS[2], rz), railway="station", public_transport="station", name=f"{TOWN} Station"
    )


def build_south(d: District) -> None:
    """The residential grid across the south under the bottom lobe: four roads, ten lanes,
    curls at the bottom, Mill Bridge back to the main city, houses with driveways, the park and
    the gang's turf."""
    res = {"highway": "residential", "lanes": "2", "maxspeed": "40"}
    tert = {"highway": "tertiary", "lanes": "2", "maxspeed": "50"}
    names = ["River Road", "Park Road", "Mid Road", "South Road"]
    for i, az in enumerate(SOUTH_AVENUES):
        d.way(
            line((SOUTH_STREETS[0], az), (EAST_STREET, az), 100.0),
            **(tert if i in (0, 3) else res),
            name=names[i],
        )
    for i, sx in enumerate(SOUTH_STREETS):
        bottom = SOUTH_AVENUES[3] if i % 2 == 0 else SOUTH_AVENUES[3] + 60.0
        d.way(line((sx, SOUTH_AVENUES[0]), (sx, bottom)), **res, name=f"{i + 1} Lane")
    for i in range(1, len(SOUTH_STREETS) - 2, 2):
        left, right = SOUTH_STREETS[i], SOUTH_STREETS[i + 2]
        bottom = SOUTH_AVENUES[3] + 60.0
        d.way(
            arc((left + right) / 2.0, bottom, (right - left) / 2.0, 180, 0),
            **res,
            name="South Bend",
        )
    insert_vertex(d, "Bridge Street", (EAST_STREET, SOUTH_AVENUES[0]))
    insert_vertex(d, "Bridge Street", (EAST_STREET, SOUTH_AVENUES[1]))
    build_frontage(d)
    # Mill Bridge: Second Street continues south over the river to River Road.
    s2 = MAIN_STREETS[1]
    d.way(line((s2, BANK_Z), (s2, 45.0)), **tert, name="Mill Bridge Road")
    d.way(line((s2, 45.0), (s2, 160.0)), **tert, name="Mill Bridge", bridge="yes", layer="1")
    d.way(line((s2, 160.0), (s2, SOUTH_AVENUES[0])), **tert, name="Mill Bridge Road")
    d.area("bridge", rect(s2 - 7.0, 41.0, s2 + 7.0, 164.0), man_made="bridge", name="Mill Bridge")
    # Houses with driveways along Park Road and Mid Road, 2 Lane to 5 Lane.
    hid = 100
    for az, side, street in (
        (SOUTH_AVENUES[1], 1.0, "Park Road"),
        (SOUTH_AVENUES[2], -1.0, "Mid Road"),
    ):
        for sx in range(int(SOUTH_STREETS[1]) + 30, int(SOUTH_STREETS[4]) - 30, 40):
            if any(abs(sx - mx) < 22.0 for mx in SOUTH_MINOR_STREETS):
                continue  # a minor lane runs here
            z0, z1 = az + side * 14.0, az + side * 26.0
            d.area(
                "building",
                rect(sx - 8.0, min(z0, z1), sx + 8.0, max(z0, z1)),
                building="house",
                **{"building:levels": "2", "addr:housenumber": str(hid), "addr:street": street},
            )
            hid += 1
            if sx % 80 == 10:
                insert_vertex(d, street, (sx + 10.0, az))
                d.way(
                    line((sx + 10.0, az), (sx + 10.0, az + side * 14.0)),
                    highway="service",
                    service="driveway",
                )
    # The park between 1 Lane and 2 Lane, Park Road to Mid Road: trees, a tree row, paths, grass.
    px0, px1 = SOUTH_STREETS[0] + 10.0, SOUTH_STREETS[1] - 10.0
    pz0, pz1 = SOUTH_AVENUES[1] + 10.0, SOUTH_AVENUES[2] - 10.0
    d.area("veg", rect(px0, pz0, px1, pz1), leisure="park", name="Cross Park")
    for k, x in enumerate(range(int(px0) + 30, int(px1) - 20, 45)):
        d.tree((x, pz0 + 30.0 + (k % 2) * 25.0), natural="tree", species="Acer saccharum")
    d.tree_rows.append(
        Way(
            d._id("veg"),
            [(px0 + 10.0, pz1 - 12.0), (px1 - 10.0, pz1 - 12.0)],
            {"natural": "tree_row"},
        )
    )
    d.tree_rows.append(
        Way(
            d._id("veg"),
            [
                (MAIN_STREETS[0] + 10.0, MAIN_AVENUES[1] - 9.0),
                (MAIN_STREETS[2] - 10.0, MAIN_AVENUES[1] - 9.0),
            ],
            {"natural": "tree_row"},
        )
    )
    d.tree_rows.append(
        Way(
            d._id("veg"),
            [
                (CITY_STREETS[0] + 10.0, CITY_AVENUES[0] + 9.0),
                (CITY_STREETS[4] - 10.0, CITY_AVENUES[0] + 9.0),
            ],
            {"natural": "tree_row"},
        )
    )
    for k in range(6):
        d.tree(
            (MAIN_STREETS[0] + 30.0 + 40.0 * k, MAIN_AVENUES[2] + 9.0),
            natural="tree",
            species="Tilia americana",
        )
    d.way(
        line((px0, (pz0 + pz1) / 2.0), (px1, (pz0 + pz1) / 2.0)), highway="path", name="Park Path"
    )
    d.way(
        line(((px0 + px1) / 2.0, pz0), ((px0 + px1) / 2.0, pz1)),
        highway="footway",
        name="Park Walk",
    )
    d.area(
        "veg",
        [
            (-1000.0, river_centre(-1000.0) + RIVER_HALF_W + 5.0),
            (EAST_STREET + 100.0, river_centre(EAST_STREET + 100.0) + RIVER_HALF_W + 5.0),
            (EAST_STREET + 100.0, SOUTH_AVENUES[0] - 8.0),
            (-1000.0, SOUTH_AVENUES[0] - 8.0),
        ],
        landuse="grass",
        name="South Bank",
    )
    d.area(
        "veg",
        [
            (A_WEST, BANK_Z + 10.0),
            (B_EAST - B_NE - 40.0, BANK_Z + 10.0),
            (B_EAST - B_NE - 40.0, river_centre(B_EAST - B_NE - 40.0) - RIVER_HALF_W - 4.0),
            (A_WEST, river_centre(A_WEST) - RIVER_HALF_W - 4.0),
        ],
        landuse="grass",
        name="North Bank",
    )
    # The gang's turf: the block 8 Lane to 9 Lane, Park Road to Mid Road, under the viaduct's
    # south straight; apartments and a corner store on it.
    t0, t1 = SOUTH_STREETS[7], SOUTH_STREETS[8]
    d.turf = rect(t0, SOUTH_AVENUES[1], t1, SOUTH_AVENUES[2])
    d.area(
        "building",
        rect(t0 + 20.0, SOUTH_AVENUES[1] + 20.0, t0 + 90.0, SOUTH_AVENUES[1] + 60.0),
        building="apartments",
        **{"building:levels": "5", "addr:housenumber": "7", "addr:street": "Park Road"},
    )
    d.area(
        "building",
        rect(t1 - 40.0, SOUTH_AVENUES[2] - 40.0, t1 - 12.0, SOUTH_AVENUES[2] - 12.0),
        building="retail",
        shop="convenience",
        name="Corner Store",
        **{"addr:housenumber": "8", "addr:street": "Mid Road"},
    )


def build_frontage(d: District) -> None:
    """Roads beside the elevated motorway: one each side of the south straight from 6 Lane to
    9 Lane, a lane east of the vertical straight from River Road to Park Road, and River Lane
    along the bank road's south side from First Street to a turning circle short of the
    highway's north-east corner (the human: "roads beside the highway in the residential
    section too, to densen it all up a bit")."""
    res = {"highway": "residential", "lanes": "2", "maxspeed": "40"}
    x0, x1 = SOUTH_STREETS[5], SOUTH_STREETS[8]  # 6 Lane to 9 Lane
    zn, zs = VIADUCT_FRONTAGE_Z
    d.way(line((x0, zn), (x1, zn), 100.0), **res, name="Viaduct Road North")
    d.way(line((x0, zs), (x1, zs), 100.0), **res, name="Viaduct Road South")
    vx = VIADUCT_LANE_X
    d.way(line((vx, SOUTH_AVENUES[0]), (vx, SOUTH_AVENUES[1])), **res, name="Viaduct Lane")
    # River Lane and the two streets that reach it across the bank road.
    s1, _s2, s3 = MAIN_STREETS
    d.way(line((s1, BANK_Z), (s1, RIVER_LANE_Z)), **res, name="First Street")
    d.way(line((s3, BANK_Z), (s3, RIVER_LANE_Z)), **res, name="Third Street")
    d.way(
        line((s1, RIVER_LANE_Z), (RIVER_LANE_END_X, RIVER_LANE_Z), 100.0), **res, name="River Lane"
    )
    cx, cz = RIVER_LANE_END_X + BULB_R, RIVER_LANE_Z
    circle = [
        (
            cx + BULB_R * math.cos(math.radians(180 - 22.5 * k)),
            cz + BULB_R * math.sin(math.radians(180 - 22.5 * k)),
        )
        for k in range(17)
    ]
    d.way(
        circle,
        highway="residential",
        junction="roundabout",
        oneway="yes",
        maxspeed="20",
        name="River Lane Circle",
    )


def build_services(d: District) -> None:
    """Police with helipad, hospital with ambulance bay (main city), fire station (city),
    shopfronts, offices, apartments, the garage with an underground entrance, the surface lot."""
    _a1, a2, a3 = MAIN_AVENUES
    s1, s2, s3 = MAIN_STREETS
    police = rect(s1 + 20.0, a2 + 20.0, s1 + 90.0, a2 + 60.0)
    addr_p = {"addr:housenumber": "1", "addr:street": "Circle Avenue"}
    d.area(
        "building",
        police,
        building="yes",
        amenity="police",
        name=f"{TOWN} Police",
        **addr_p,
        **{"building:levels": "3"},
    )
    d.area("service", police, amenity="police", name=f"{TOWN} Police", **addr_p)
    d.area(
        "service",
        rect(s1 + 100.0, a2 + 25.0, s1 + 130.0, a2 + 55.0),
        aeroway="helipad",
        name="Police Pad",
    )
    insert_vertex(d, "Circle Avenue", (s1 + 95.0, a2))
    d.way(
        line((s1 + 95.0, a2), (s1 + 95.0, a2 + 20.0)),
        highway="service",
        service="driveway",
        name="Police Drive",
    )
    hospital = rect(s2 + 20.0, a3 + 30.0, s2 + 110.0, a3 + 100.0)
    addr_h = {"addr:housenumber": "2", "addr:street": "Station Avenue"}
    d.area(
        "building",
        hospital,
        building="hospital",
        amenity="hospital",
        name=f"{TOWN} General",
        **addr_h,
        **{"building:levels": "4"},
    )
    d.area("service", hospital, amenity="hospital", name=f"{TOWN} General", **addr_h)
    d.area(
        "service",
        rect(s2 + 115.0, a3 + 40.0, s2 + 135.0, a3 + 70.0),
        emergency="ambulance_station",
        name="Ambulance Bay",
    )
    insert_vertex(d, "Station Avenue", (s2 + 125.0, a3))
    d.way(
        line((s2 + 125.0, a3), (s2 + 125.0, a3 + 40.0)),
        highway="service",
        service="driveway",
        name="Hospital Drive",
    )
    f0 = CITY_STREETS[0]
    fire = rect(f0 + 20.0, CITY_AVENUES[1] + 30.0, f0 + 80.0, CITY_AVENUES[1] + 70.0)
    addr_f = {"addr:housenumber": "3", "addr:street": "Station Avenue"}
    d.area(
        "building",
        fire,
        building="fire_station",
        amenity="fire_station",
        name=f"{TOWN} Fire Hall",
        **addr_f,
    )
    d.area("service", fire, amenity="fire_station", name=f"{TOWN} Fire Hall", **addr_f)
    insert_vertex(d, "Station Avenue", (f0 + 50.0, CITY_AVENUES[1]))
    d.way(
        line((f0 + 50.0, CITY_AVENUES[1]), (f0 + 50.0, CITY_AVENUES[1] + 30.0)),
        highway="service",
        service="driveway",
        name="Fire Hall Drive",
    )
    for k, x in enumerate(range(int(s2) + 20, int(s3) - 30, 30)):
        d.area(
            "building",
            rect(x, a2 + 12.0, x + 24.0, a2 + 40.0),
            building="retail",
            shop=["bakery", "clothes", "books", "hardware"][k % 4],
            name=["Loaf", "Thread", "Pages", "Bolt"][k % 4] + " Shop",
            **{"addr:housenumber": str(10 + k), "addr:street": "Circle Avenue"},
        )
    for k, x in enumerate((410, 530, 610, 730)):  # between the city's streets and minor streets
        d.area(
            "building",
            rect(x, CITY_AVENUES[0] - 60.0, x + 50.0, CITY_AVENUES[0] - 14.0),
            building="office",
            **{
                "building:levels": str(6 + k),
                "addr:housenumber": str(20 + k),
                "addr:street": "Riverside Avenue",
            },
        )
    for k, x in enumerate(range(int(s1) + 20, int(s2) - 40, 60)):
        d.area(
            "building",
            rect(x, a3 - 50.0, x + 44.0, a3 - 14.0),
            building="apartments",
            **{
                "building:levels": "8",
                "addr:housenumber": str(30 + k),
                "addr:street": "Station Avenue",
            },
        )
    # Surface lot between Third Street and the vertical, with an aisle and a driveway.
    d.area(
        "parking",
        rect(s3 + 15.0, a3 + 20.0, -30.0, a3 + 90.0),
        amenity="parking",
        parking="surface",
        capacity="40",
        name="Loop Lot",
    )
    aisle_z = a3 + 55.0
    insert_vertex(d, "Third Street", (s3, aisle_z))
    d.way(line((s3, aisle_z), (s3 + 20.0, aisle_z)), highway="service", service="driveway")
    d.way(line((s3 + 20.0, aisle_z), (-35.0, aisle_z)), highway="service", service="parking_aisle")
    # Multi-storey garage with an underground entrance at the end of a ramp off Second Street.
    garage = rect(s1 + 20.0, a3 + 20.0, s1 + 80.0, a3 + 80.0)
    d.area(
        "building",
        garage,
        building="parking",
        parking="multi-storey",
        name="Cross Garage",
        **{"building:levels": "4"},
    )
    d.area(
        "parking",
        garage,
        amenity="parking",
        parking="multi-storey",
        capacity="200",
        name="Cross Garage",
    )
    entrance = (s1 + 100.0, a3 + 50.0)
    insert_vertex(d, "Second Street", (s2, a3 + 50.0))
    d.way(
        line((s2, a3 + 50.0), entrance), highway="service", service="driveway", name="Garage Ramp"
    )
    d.tag_node(entrance, amenity="parking_entrance", parking="underground", name="Cross Garage")


Box = tuple[float, float, float, float]


def _hits_box(a: Point, b: Point, box: Box) -> bool:
    """Whether the axis-aligned segment ab, widened by the minor margin, overlaps the box."""
    m = MINOR_MARGIN_M
    sx0, sx1 = min(a[0], b[0]) - m, max(a[0], b[0]) + m
    sz0, sz1 = min(a[1], b[1]) - m, max(a[1], b[1]) + m
    return not (sx1 <= box[0] or box[2] <= sx0 or sz1 <= box[1] or box[3] <= sz0)


def _box(ring: list[Point]) -> Box:
    xs = [p[0] for p in ring]
    zs = [p[1] for p in ring]
    return (min(xs), min(zs), max(xs), max(zs))


def _reserved(d: District) -> list[Box]:
    """What a minor street never runs through: footprints, lots, services, bridges, the park,
    the turf, the roundabout and the ramp corridors."""
    boxes: list[Box] = []
    for group in (d.buildings, d.parking, d.service_areas, d.bridges):
        boxes.extend(_box(a.ring) for a in group)
    boxes.extend(_box(a.ring) for a in d.vegetation_areas if a.tags.get("leisure") == "park")
    if d.turf:
        boxes.append(_box(d.turf))
    rz = MAIN_AVENUES[1]
    r = ROUNDABOUT_R + 10.0
    boxes.append((A_WEST - r, rz - r, A_WEST + r, rz + r))
    xe = B_EAST + PAIR_OFFSET
    lane10 = SOUTH_STREETS[9]
    boxes.append((-60.0, 270.0, 0.0, 395.0))  # West Exit, down to 5 Lane
    boxes.append((350.0, 620.0, 505.0, 660.0))  # West Entrance, up from Viaduct Road South
    boxes.append((xe - 6.0, 245.0, lane10 + 5.0, 335.0))  # East Exit, down to River Road
    boxes.append((xe - 6.0, 465.0, lane10 + 5.0, 555.0))  # East Entrance, up from Mid Road
    boxes.append((240.0, BANK_Z - 70.0, 710.0, BANK_Z))  # City Exit and Entrance off the bank
    return boxes


def _pieces(
    fixed: float, breaks: list[float], lo: float, hi: float, vertical: bool
) -> list[tuple[Point, Point]]:
    """A straight street at `fixed` from lo to hi, cut at every cross road it meets."""
    cuts = sorted({c for c in breaks if lo <= c <= hi} | {lo, hi})
    out = []
    for c0, c1 in pairwise(cuts):
        if vertical:
            out.append(((fixed, c0), (fixed, c1)))
        else:
            out.append(((c0, fixed), (c1, fixed)))
    return out


def _minor_way(
    d: District,
    pieces: list[tuple[Point, Point]],
    name: str,
    boxes: list[Box],
    big: list[tuple[Point, Point]],
) -> None:
    """Joins consecutive kept pieces of one minor street into ways; a piece that meets a
    reserved box is left out, so the street breaks there. An end on a through road gets a
    stop sign 8 m back."""
    res = {"highway": "residential", "lanes": "2", "maxspeed": "40"}
    run: list[Point] = []

    def flush() -> None:
        if len(run) >= 2:
            w = d.way(list(run), **res, name=name)
            for end, back in ((w.points[0], w.points[1]), (w.points[-1], w.points[-2])):
                if _on_segments(end, big):
                    dx, dz = back[0] - end[0], back[1] - end[1]
                    length = math.hypot(dx, dz) or 1.0
                    stop_at = (end[0] + dx / length * 8.0, end[1] + dz / length * 8.0)
                    split_stop(d, end, stop_at)
                    d.tag_node(stop_at, highway="stop")
        run.clear()

    for a, b in pieces:
        if any(_hits_box(a, b, box) for box in boxes):
            flush()
            continue
        if not run:
            run.extend([a, b])
        else:
            run.append(b)
    flush()


def _on_segments(p: Point, segments: list[tuple[Point, Point]]) -> bool:
    for a, b in segments:
        t, dist = _project(p, a, b)
        if -1e-6 <= t <= 1.0 + 1e-6 and dist < 0.01:
            return True
    return False


def build_minor_grids(d: District) -> None:
    """The minor streets of all three grids. Runs after the services so a street never cuts a
    footprint; the stitch pass gives every end and crossing its junction."""
    boxes = _reserved(d)
    big: list[tuple[Point, Point]] = []  # ends on a through road get a stop sign
    for w in d.ways:
        if w.tags.get("highway") in ("tertiary", "secondary") and "junction" not in w.tags:
            big.extend(pairwise(w.points))
    # Main city: streets between the bank road and the loop's top, avenues from the west pair.
    a1, _a2, a3 = MAIN_AVENUES
    s1 = MAIN_STREETS[0]
    m1, m2, m3 = MAIN_MINOR_AVENUES
    x_alder, x_birch, x_cedar = MAIN_MINOR_STREETS
    cross_z = sorted([BANK_Z, *MAIN_AVENUES, *MAIN_MINOR_AVENUES, A_NORTH])
    cross_x = sorted([*WEST_STREETS, A_WEST, *MAIN_STREETS, *MAIN_MINOR_STREETS, 0.0])
    _minor_way(d, _pieces(x_alder, cross_z, a1, a3, True), "Alder Street", boxes, big)
    _minor_way(d, _pieces(x_birch, cross_z, a1, a3, True), "Birch Street", boxes, big)
    _minor_way(d, _pieces(x_cedar, cross_z, BANK_Z, m2, True), "Cedar Street", boxes, big)
    _minor_way(d, _pieces(x_cedar, cross_z, a3, m3, True), "Cedar Street", boxes, big)
    _minor_way(
        d, _pieces(m1, cross_x, WEST_STREETS[1], x_cedar, False), "Hollow Avenue", boxes, big
    )
    _minor_way(d, _pieces(m2, cross_x, s1, x_cedar, False), "Kiln Avenue", boxes, big)
    _minor_way(d, _pieces(m3, cross_x, s1, x_cedar, False), "Foundry Avenue", boxes, big)
    # City: two avenues and four streets between Riverside and Station Avenue.
    c1, c3 = CITY_AVENUES
    cross_z = sorted([c1, *CITY_MINOR_AVENUES, c3])
    cross_x = sorted([*CITY_STREETS, *CITY_MINOR_STREETS])
    names = ("Ninth Street", "Tenth Street", "Eleventh Street", "Twelfth Street")
    for x, name in zip(CITY_MINOR_STREETS, names):
        _minor_way(d, _pieces(x, cross_z, c1, c3, True), name, boxes, big)
    for z, name in zip(CITY_MINOR_AVENUES, ("Quay Avenue", "Depot Avenue")):
        _minor_way(
            d, _pieces(z, cross_x, CITY_STREETS[0], CITY_STREETS[4], False), name, boxes, big
        )
    # South: three roads and nine lanes; Ash Road stops short of the viaduct's sweeps.
    r0, r3 = SOUTH_AVENUES[0], SOUTH_AVENUES[3]
    cross_z = sorted([*SOUTH_AVENUES, *SOUTH_MINOR_AVENUES, *VIADUCT_FRONTAGE_Z])
    cross_x = sorted([*SOUTH_STREETS, *SOUTH_MINOR_STREETS, VIADUCT_LANE_X])
    for i, x in enumerate(SOUTH_MINOR_STREETS):
        hi = SOUTH_AVENUES[1] if x == VIADUCT_LANE_X else r3
        _minor_way(d, _pieces(x, cross_z, r0, hi, True), f"{11 + i} Lane", boxes, big)
    elm, oak, ash = SOUTH_MINOR_AVENUES
    west, east = SOUTH_STREETS[0], SOUTH_STREETS[9]
    _minor_way(d, _pieces(elm, cross_x, west, east, False), "Elm Road", boxes, big)
    _minor_way(d, _pieces(oak, cross_x, west, east, False), "Oak Road", boxes, big)
    _minor_way(d, _pieces(ash, cross_x, west, SOUTH_STREETS[5], False), "Ash Road", boxes, big)


def build_paths(d: District) -> None:
    """Sidewalks on Circle Avenue with a crossing, the riverside cycleway between the bank
    road and the water, steps down to it, the footbridge beside the crossing, and the underpass
    under the bank highway."""
    a2 = MAIN_AVENUES[1]
    s1, s2, s3 = MAIN_STREETS
    for side in (-5.5, 5.5):
        d.way(line((s1, a2 + side), (s3, a2 + side), 60.0), highway="footway", footway="sidewalk")
    d.way(line((s2 + 30.0, a2 - 5.5), (s2 + 30.0, a2 + 5.5)), highway="footway", footway="crossing")
    bank = lambda x: river_centre(x) - RIVER_HALF_W - 8.0
    xs = [-900.0 + i * 50.0 for i in range(40)]
    d.way([(x, bank(x)) for x in xs], highway="cycleway", name="Riverside Path")
    d.way([(s2 + 12.0, BANK_Z + 6.0), (s2 + 12.0, bank(s2 + 12.0))], highway="steps")
    fx = -60.0
    d.way(
        [(fx, bank(fx)), (fx, river_centre(fx) + RIVER_HALF_W + 8.0)],
        highway="footway",
        bridge="yes",
        layer="1",
        name="Cross Footbridge",
    )
    d.way([(fx, river_centre(fx) + RIVER_HALF_W + 8.0), (fx, SOUTH_AVENUES[0])], highway="footway")
    insert_vertex(d, "River Road", (fx, SOUTH_AVENUES[0]))
    ux = 450.0
    insert_vertex(d, "Riverside Avenue", (ux, CITY_AVENUES[0]))
    d.way([(ux, CITY_AVENUES[0]), (ux, BANK_Z - 30.0)], highway="footway", name="Underpass Walk")
    d.way(
        [(ux, BANK_Z - 30.0), (ux, BANK_Z + 30.0)],
        highway="footway",
        tunnel="yes",
        layer="-1",
        name="Bank Underpass",
    )
    d.way([(ux, BANK_Z + 30.0), (ux, bank(ux))], highway="footway", name="Underpass Walk")


def build_spawn(d: District) -> None:
    """Start line on the vertical straight just north of the centre bridge, heading south; the
    car spawns on the two-way street before the split."""
    d.start_line = ((0.0, -180.0), (0.0, 1.0))
    # In the right-hand lane of the two-way street (heading south, the right is west).
    d.spawn = (-1.75, -340.0, 180.0)


def build(town: str = TOWN) -> District:
    """The whole district; `town` names the station, police, hospital and fire hall."""
    global TOWN
    TOWN = town
    from proving_ground.dressing import build_dressing

    d = District()
    build_river(d)
    build_greenbelt(d)
    build_loop(d)
    build_main_city(d)
    build_city(d)
    build_south(d)
    build_exits(d)
    build_services(d)
    build_minor_grids(d)
    build_paths(d)
    build_dressing(d)
    build_spawn(d)
    stitch(d)
    return d


# ---------------------------------------------------------------- stitching


def _level(w: Way) -> tuple[int, bool]:
    """(layer, separated): a bridge or tunnel way never meets a way on another level."""
    layer = int(w.tags.get("layer", "0"))
    return layer, w.tags.get("bridge") == "yes" or w.tags.get("tunnel") == "yes"


def _motorway(w: Way) -> bool:
    return w.tags.get("highway") in ("motorway", "motorway_link")


def _seg_hit(a: Point, b: Point, c: Point, e: Point) -> Point | None:
    """Where segments ab and ce cross or touch (an end of one lying on the other), or None."""
    r = (b[0] - a[0], b[1] - a[1])
    q = (e[0] - c[0], e[1] - c[1])
    denom = r[0] * q[1] - r[1] * q[0]
    if abs(denom) < 1e-9:
        return None
    w = (c[0] - a[0], c[1] - a[1])
    t = (w[0] * q[1] - w[1] * q[0]) / denom
    u = (w[0] * r[1] - w[1] * r[0]) / denom
    eps = 1e-6
    if -eps <= t <= 1 + eps and -eps <= u <= 1 + eps:
        return _r((a[0] + r[0] * t, a[1] + r[1] * t))
    return None


def _insert_point(w: Way, p: Point) -> None:
    if p in w.points:
        return
    for i in range(len(w.points) - 1):
        t, dist = _project(p, w.points[i], w.points[i + 1])
        if dist < 0.01 and -1e-6 <= t <= 1.0 + 1e-6:
            w.points.insert(i + 1, p)
            return


def stitch(d: District) -> None:
    """Gives every pair of ways that cross or touch at the same level a shared vertex, so the
    importer sees a junction there. Motorways and their links only meet each other (the ramps
    share their nodes by construction), and a bridge or tunnel only meets ways on its layer."""
    ways = d.ways
    hits: list[tuple[Way, Way, Point]] = []
    for i, w1 in enumerate(ways):
        l1, sep1 = _level(w1)
        for w2 in ways[i + 1 :]:
            l2, sep2 = _level(w2)
            if (l1 != l2 or (sep1 and not sep2) or (sep2 and not sep1)) and not (
                w1.points[0] in w2.points
                or w1.points[-1] in w2.points
                or w2.points[0] in w1.points
                or w2.points[-1] in w1.points
            ):
                continue
            if _motorway(w1) != _motorway(w2):
                continue
            box1 = (
                min(p[0] for p in w1.points),
                max(p[0] for p in w1.points),
                min(p[1] for p in w1.points),
                max(p[1] for p in w1.points),
            )
            box2 = (
                min(p[0] for p in w2.points),
                max(p[0] for p in w2.points),
                min(p[1] for p in w2.points),
                max(p[1] for p in w2.points),
            )
            if (
                box1[1] < box2[0] - 1
                or box2[1] < box1[0] - 1
                or box1[3] < box2[2] - 1
                or box2[3] < box1[2] - 1
            ):
                continue
            for a, b in zip(w1.points, w1.points[1:]):
                for c, e in zip(w2.points, w2.points[1:]):
                    hit = _seg_hit(a, b, c, e)
                    if hit is not None:
                        hits.append((w1, w2, hit))
    for w1, w2, p in hits:
        _insert_point(w1, p)
        _insert_point(w2, p)
