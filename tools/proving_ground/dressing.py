"""Dresses the Double Cross district: buildings on every block and trees along the streets.

Approach: walk every straight run of every street on both sides and drop lots along it at a
setback from the kerb, so buildings face their street and leave the sidewalk. A lot is kept
only when none of its corners (or its centre) lies within a per-class clearance of any other
road, inside the river, the banks, the greenbelt, the park, a bridge, the turf block or the
roundabout, or on top of an existing footprint. Zones come from position: south of the river
is residential, north of it and west of the vertical is the main city, north and east is the
city. One seeded generator per zone gives the variety, in a fixed order, so the pack
regenerates byte for byte. Tree rows run 9 m off every avenue and the bank road; a yard tree
stands behind each detached house.
"""

from __future__ import annotations

import math
import random
from collections import defaultdict
from dataclasses import dataclass

from proving_ground import layout as L
from proving_ground.layout import District, Point, Way, insert_vertex, line, rect

# Metres from a road's centreline that a lot must keep clear of, by highway class.
CLEARANCE = {
    "motorway": 16.0,
    "motorway_link": 10.0,
    "secondary": 11.0,
    "tertiary": 10.0,
    "residential": 9.0,
    "service": 5.0,
    "footway": 4.0,
    "cycleway": 4.0,
    "path": 4.0,
    "steps": 3.0,
}
RAIL_CLEARANCE = 8.0
# Where a lot's front edge sits, measured from its own street's centreline.
FRONT_M = {"secondary": 12.0, "tertiary": 11.0, "residential": 10.0}
RUN_END_MARGIN_M = 18.0  # frontage left clear at each end of a straight run (the corners)
ROW_OFFSET_M = 9.0  # tree rows this far off an avenue's centreline
ROW_END_MARGIN_M = 15.0  # rows stop this far short of a run's end (signal heads, stop lines)
CELL_M = 50.0
MAX_CLEARANCE = max(CLEARANCE.values())
TOWER_RADIUS_M = 220.0  # towers stand within this of the roundabout
TOWER_COUNT = 4
SHOPS = ("convenience", "clothes", "bakery", "hairdresser", "books", "electronics", "florist")
YARD_SPECIES = ("Acer saccharum", "Tilia americana", "Quercus rubra", "Betula papyrifera")
SEEDS = {"south": 7, "main": 11, "city": 13}


@dataclass
class Lot:
    x0: float
    z0: float
    x1: float
    z1: float

    def corners(self) -> list[Point]:
        return [(self.x0, self.z0), (self.x1, self.z0), (self.x1, self.z1), (self.x0, self.z1)]

    def centre(self) -> Point:
        return ((self.x0 + self.x1) / 2.0, (self.z0 + self.z1) / 2.0)

    def ring(self) -> list[Point]:
        return rect(self.x0, self.z0, self.x1, self.z1)


class _Index:
    """Road segments in 50 m cells, so a clearance test touches a handful of segments."""

    def __init__(self) -> None:
        self.cells: dict[tuple[int, int], list[tuple[Point, Point, float]]] = defaultdict(list)

    def add(self, a: Point, b: Point, clearance: float) -> None:
        for cx in range(int(min(a[0], b[0]) // CELL_M) - 1, int(max(a[0], b[0]) // CELL_M) + 2):
            for cz in range(int(min(a[1], b[1]) // CELL_M) - 1, int(max(a[1], b[1]) // CELL_M) + 2):
                self.cells[(cx, cz)].append((a, b, clearance))

    def too_close(self, p: Point, skip: tuple[Point, Point] | None) -> bool:
        key = (int(p[0] // CELL_M), int(p[1] // CELL_M))
        for a, b, clearance in self.cells.get(key, ()):
            if skip is not None and a == skip[0] and b == skip[1]:
                continue
            if _seg_dist(p, a, b) < clearance:
                return True
        return False


def _seg_dist(p: Point, a: Point, b: Point) -> float:
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    if l2 < 1e-9:
        return math.dist(p, a)
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2))
    return math.dist(p, (a[0] + dx * t, a[1] + dz * t))


def _bbox(ring: list[Point]) -> tuple[float, float, float, float]:
    xs = [p[0] for p in ring]
    zs = [p[1] for p in ring]
    return min(xs), min(zs), max(xs), max(zs)


def _overlaps(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1])


def _inside(p: Point, ring: list[Point]) -> bool:
    x, z = p
    inside = False
    n = len(ring)
    for i in range(n):
        x1, z1 = ring[i]
        x2, z2 = ring[(i + 1) % n]
        if (z1 > z) != (z2 > z):
            xi = x1 + (z - z1) * (x2 - x1) / (z2 - z1)
            if xi > x:
                inside = not inside
    return inside


class _Exclusions:
    def __init__(self, d: District) -> None:
        self.index = _Index()
        for w in d.ways:
            cls = w.tags.get("highway")
            clearance = CLEARANCE.get(cls or "", 0.0)
            if w.tags.get("railway"):
                clearance = RAIL_CLEARANCE
            if clearance <= 0.0:
                continue
            for a, b in zip(w.points, w.points[1:]):
                self.index.add(a, b, clearance)
        self.boxes: list[tuple[float, float, float, float]] = []
        for group in (d.buildings, d.parking, d.service_areas, d.bridges):
            for area in group:
                self.boxes.append(_bbox(area.ring))
        self.polys: list[list[Point]] = [
            a.ring
            for a in d.vegetation_areas
            if a.tags.get("natural") == "wood"
            or a.tags.get("landuse") == "grass"
            or a.tags.get("leisure") == "park"
        ]
        self.turf = _bbox(d.turf) if d.turf else None
        self.roundabout = (L.A_WEST, L.MAIN_AVENUES[1])

    def rejects(self, lot: Lot, own: tuple[Point, Point]) -> bool:
        box = (lot.x0, lot.z0, lot.x1, lot.z1)
        if abs(lot.x0) > L.HALF_W - 10.0 or abs(lot.x1) > L.HALF_W - 10.0:
            return True
        if abs(lot.z0) > L.HALF_H - 10.0 or abs(lot.z1) > L.HALF_H - 10.0:
            return True
        if self.turf is not None and _overlaps(box, self.turf):
            return True
        for other in self.boxes:
            if _overlaps(box, other):
                return True
        for p in [*lot.corners(), lot.centre()]:
            if abs(p[1] - L.river_centre(p[0])) < L.RIVER_HALF_W + 12.0:
                return True
            if math.dist(p, self.roundabout) < L.ROUNDABOUT_R + 12.0:
                return True
            if self.index.too_close(p, own):
                return True
            for ring in self.polys:
                if _inside(p, ring):
                    return True
        return False

    def claim(self, lot: Lot) -> None:
        self.boxes.append((lot.x0, lot.z0, lot.x1, lot.z1))


def zone_of(p: Point) -> str:
    """south of the river is residential; north of it, west of the vertical is the main city."""
    if p[1] > L.river_centre(p[0]) + L.RIVER_HALF_W:
        return "south"
    return "main" if p[0] < 60.0 else "city"


def _runs(w: Way) -> list[tuple[Point, Point]]:
    """Straight axis-aligned runs of a way, merging collinear segments (inserted vertices)."""
    runs: list[tuple[Point, Point]] = []
    start = w.points[0]
    axis = None
    for a, b in zip(w.points, w.points[1:]):
        if abs(b[0] - a[0]) < 0.01:
            seg_axis = "z"
        elif abs(b[1] - a[1]) < 0.01:
            seg_axis = "x"
        else:
            if axis is not None:
                runs.append((start, a))
            axis = None
            start = b
            continue
        if axis is None:
            axis = seg_axis
            start = a
        elif seg_axis != axis:
            runs.append((start, a))
            axis = seg_axis
            start = a
    if axis is not None and start != w.points[-1]:
        runs.append((start, w.points[-1]))
    return runs


ZONE_SPLIT_X = 60.0  # the main city ends and the city begins here, north of the river


def _split_at_zones(runs: list[tuple[Point, Point]]) -> list[tuple[Point, Point]]:
    """A horizontal run north of the river that spans the main-city/city boundary is dressed
    as two runs, one per zone."""
    out: list[tuple[Point, Point]] = []
    for a, b in runs:
        horizontal = abs(b[1] - a[1]) < 0.01
        north = a[1] < L.river_centre(a[0]) - L.RIVER_HALF_W
        lo, hi = min(a[0], b[0]), max(a[0], b[0])
        if horizontal and north and lo < ZONE_SPLIT_X < hi:
            mid = (ZONE_SPLIT_X, a[1])
            out.append((a, mid))
            out.append((mid, b))
        else:
            out.append((a, b))
    return out


def _frontage_lots(
    run: tuple[Point, Point], front: float, width: float, depth: float, pitch: float
) -> list[tuple[Lot, Point, float]]:
    """Lots along both sides of a run: (lot, kerb point in front of it, side sign)."""
    a, b = run
    horizontal = abs(b[1] - a[1]) < 0.01
    length = math.dist(a, b)
    usable = length - 2.0 * RUN_END_MARGIN_M
    if usable < width:
        return []
    count = int((usable + (pitch - width)) // pitch)
    span = count * pitch - (pitch - width)
    start = RUN_END_MARGIN_M + (usable - span) / 2.0
    out: list[tuple[Lot, Point, float]] = []
    direction = 1.0 if (b[0] > a[0] if horizontal else b[1] > a[1]) else -1.0
    for side in (1.0, -1.0):
        for k in range(count):
            along0 = start + k * pitch
            along1 = along0 + width
            if horizontal:
                x0 = a[0] + direction * along0
                x1 = a[0] + direction * along1
                z_kerb = a[1]
                z0 = z_kerb + side * front
                z1 = z_kerb + side * (front + depth)
                lot = Lot(min(x0, x1), min(z0, z1), max(x0, x1), max(z0, z1))
                kerb = ((x0 + x1) / 2.0, z_kerb)
            else:
                z0 = a[1] + direction * along0
                z1 = a[1] + direction * along1
                x_kerb = a[0]
                x0 = x_kerb + side * front
                x1 = x_kerb + side * (front + depth)
                lot = Lot(min(x0, x1), min(z0, z1), max(x0, x1), max(z0, z1))
                kerb = (x_kerb, (z0 + z1) / 2.0)
            out.append((lot, kerb, side))
    return out


def _house_number(d: District, street: str) -> str:
    n = sum(1 for a in d.buildings if a.tags.get("addr:street") == street) + 1
    return str(200 + n)


def build_dressing(d: District) -> None:
    """Buildings along every street, then trees; call after the streets and services."""
    ex = _Exclusions(d)
    rngs = {zone: random.Random(seed) for zone, seed in SEEDS.items()}
    towers = 0
    for w in sorted(d.ways, key=lambda w: w.id):
        cls = w.tags.get("highway")
        if cls not in FRONT_M or w.tags.get("bridge") or w.tags.get("tunnel"):
            continue
        if (
            w.tags.get("junction") == "roundabout"
            or w.tags.get("oneway") == "yes"
            and cls != "residential"
        ):
            continue
        street = w.tags.get("name", "")
        front = FRONT_M[cls]
        for run in _split_at_zones(_runs(w)):
            zone = zone_of(((run[0][0] + run[1][0]) / 2.0, (run[0][1] + run[1][1]) / 2.0))
            rng = rngs[zone]
            if zone == "south":
                towers = _dress_south(d, ex, rng, run, front, street, cls)
            elif zone == "main":
                towers = _dress_main(d, ex, rng, run, front, street, cls, towers)
            else:
                _dress_city(d, ex, rng, run, front, street, cls)
    _tree_rows(d)


def _place(d: District, ex: _Exclusions, lot: Lot, own: tuple[Point, Point], **tags: str) -> bool:
    if ex.rejects(lot, own):
        return False
    d.area("building", lot.ring(), **{k: v for k, v in tags.items() if v})
    ex.claim(lot)
    return True


def _dress_south(d, ex, rng, run, front, street, cls) -> int:
    """Detached houses, semis and terraces; driveways on every other detached house; a yard
    tree behind each detached house."""
    detached = 0
    for lot, kerb, side in _frontage_lots(run, front, 12.0, 11.0, 18.0):
        roll = rng.random()
        width_jitter = rng.uniform(-2.0, 2.0)
        depth_jitter = rng.uniform(-1.5, 2.5)
        if roll < 0.15:
            # A terrace: four narrow units filling the pitch and the next.
            units = 4
            unit_w = 6.0
            horizontal = abs(run[1][1] - run[0][1]) < 0.01
            for u in range(units):
                if horizontal:
                    x0 = lot.x0 + u * unit_w
                    sub = Lot(x0, lot.z0, x0 + unit_w, lot.z1)
                else:
                    z0 = lot.z0 + u * unit_w
                    sub = Lot(lot.x0, z0, lot.x1, z0 + unit_w)
                _place(
                    d,
                    ex,
                    sub,
                    run,
                    building="terrace",
                    **{
                        "building:levels": "2",
                        "addr:street": street,
                        "addr:housenumber": _house_number(d, street),
                    },
                )
            continue
        if roll < 0.35:
            # A semi: two halves sharing a wall.
            horizontal = abs(run[1][1] - run[0][1]) < 0.01
            for u in range(2):
                # The shared depth jitter moves the far edge only; the front stays at the kerb setback.
                if horizontal:
                    x0 = lot.x0 + u * 7.0
                    far0 = lot.z0 - (depth_jitter if side < 0 else 0.0)
                    far1 = lot.z1 + (depth_jitter if side > 0 else 0.0)
                    sub = Lot(x0, far0, x0 + 7.0, far1)
                else:
                    z0 = lot.z0 + u * 7.0
                    far0 = lot.x0 - (depth_jitter if side < 0 else 0.0)
                    far1 = lot.x1 + (depth_jitter if side > 0 else 0.0)
                    sub = Lot(far0, z0, far1, z0 + 7.0)
                _place(
                    d,
                    ex,
                    sub,
                    run,
                    building="semidetached_house",
                    **{
                        "building:levels": "2",
                        "addr:street": street,
                        "addr:housenumber": _house_number(d, street),
                    },
                )
            continue
        horizontal = abs(run[1][1] - run[0][1]) < 0.01
        # Width varies along the street; depth varies on the far edge only, so the front stays
        # at its setback from the kerb.
        x0, z0, x1, z1 = lot.x0, lot.z0, lot.x1, lot.z1
        if horizontal:
            x0, x1 = x0 + 1.0, x1 - 1.0 + width_jitter
            if side > 0:
                z1 += depth_jitter
            else:
                z0 -= depth_jitter
        else:
            z0, z1 = z0 + 1.0, z1 - 1.0 + width_jitter
            if side > 0:
                x1 += depth_jitter
            else:
                x0 -= depth_jitter
        house = Lot(x0, z0, x1, z1)
        if not _place(
            d,
            ex,
            house,
            run,
            building="house",
            **{
                "building:levels": "2",
                "addr:street": street,
                "addr:housenumber": _house_number(d, street),
            },
        ):
            continue
        detached += 1
        # Yard tree behind the house.
        cx, cz = house.centre()
        if horizontal:
            back = (cx + rng.uniform(-3.0, 3.0), (house.z1 if side > 0 else house.z0) + side * 6.0)
        else:
            back = ((house.x1 if side > 0 else house.x0) + side * 6.0, cz + rng.uniform(-3.0, 3.0))
        d.tree(back, natural="tree", denotation="garden", species=rng.choice(YARD_SPECIES))
        # Driveway from the kerb to the house front, every second detached house, streets only.
        if cls == "residential" and detached % 2 == 0 and street:
            if horizontal:
                drive_x = house.x1 - 3.0
                front_pt = (drive_x, house.z0 if side > 0 else house.z1)
                kerb_pt = (drive_x, kerb[1])
            else:
                drive_z = house.z1 - 3.0
                front_pt = (house.x0 if side > 0 else house.x1, drive_z)
                kerb_pt = (kerb[0], drive_z)
            insert_vertex(d, street, kerb_pt)
            d.way(line(kerb_pt, front_pt), highway="service", service="driveway")
    return 0


def _dress_main(d, ex, rng, run, front, street, cls, towers: int) -> int:
    """Shopfront terraces on the avenues, apartment and commercial blocks on the streets, a few
    towers near the roundabout, a surface lot behind every seventh street lot."""
    roundabout = (L.A_WEST, L.MAIN_AVENUES[1])
    if cls == "tertiary":
        for lot, _kerb, _side in _frontage_lots(run, front, 12.0, 16.0, 12.0):
            if (
                towers < TOWER_COUNT
                and math.dist(lot.centre(), roundabout) < TOWER_RADIUS_M
                and rng.random() < 0.5
            ):
                tower = Lot(lot.x0, lot.z0, lot.x0 + 20.0, lot.z0 + 20.0)
                if _place(
                    d,
                    ex,
                    tower,
                    run,
                    building=rng.choice(("office", "apartments")),
                    **{
                        "building:levels": str(rng.randint(10, 16)),
                        "addr:street": street,
                        "addr:housenumber": _house_number(d, street),
                    },
                ):
                    towers += 1
                    continue
            _place(
                d,
                ex,
                lot,
                run,
                building="retail",
                shop=rng.choice(SHOPS),
                **{
                    "building:levels": str(rng.randint(2, 3)),
                    "addr:street": street,
                    "addr:housenumber": _house_number(d, street),
                },
            )
        return towers
    k = 0
    for lot, _kerb, _side in _frontage_lots(run, front, 18.0, 16.0, 24.0):
        k += 1
        if k % 7 == 0:
            yard = Lot(lot.x0 - 3.0, lot.z0, lot.x1 + 9.0, lot.z1 + 6.0)
            if not ex.rejects(yard, run):
                d.area("parking", yard.ring(), amenity="parking", parking="surface")
                ex.claim(yard)
                continue
        kind = "commercial" if rng.random() < 0.3 else "apartments"
        _place(
            d,
            ex,
            lot,
            run,
            building=kind,
            **{
                "building:levels": str(rng.randint(3, 6)),
                "addr:street": street,
                "addr:housenumber": _house_number(d, street),
            },
        )
    return towers


def _dress_city(d, ex, rng, run, front, street, cls) -> None:
    """Offices along Riverside Avenue and the streets; the warehouse row on the north side of
    Station Avenue along the rail."""
    station_north = street == "Station Avenue"
    for lot, _kerb, side in _frontage_lots(run, front, 20.0, 18.0, 26.0):
        if station_north and side < 0:
            shed = Lot(lot.x0 - 2.0, lot.z0 - 10.0, lot.x1 + 18.0, lot.z1)
            _place(
                d,
                ex,
                shed,
                run,
                building="warehouse",
                **{
                    "building:levels": str(rng.randint(1, 2)),
                    "height": str(rng.choice((9, 11, 12))),
                    "addr:street": street,
                    "addr:housenumber": _house_number(d, street),
                },
            )
            continue
        _place(
            d,
            ex,
            lot,
            run,
            building="office",
            **{
                "building:levels": str(rng.randint(4, 8)),
                "addr:street": street,
                "addr:housenumber": _house_number(d, street),
            },
        )


def _row_exists(d: District, a: Point, b: Point) -> bool:
    for row in d.tree_rows:
        if all(_seg_dist(p, a, b) < 3.0 for p in row.points) and all(
            _seg_dist(q, row.points[0], row.points[-1]) < 3.0 for q in (a, b)
        ):
            return True
    return False


def _tree_rows(d: District) -> None:
    """Rows 9 m off both sides of every avenue's straight runs, and the north side of the bank
    road; clipped short of the run ends."""
    for w in sorted(d.ways, key=lambda w: w.id):
        cls = w.tags.get("highway")
        name = w.tags.get("name", "")
        bank = name == L.LOOP_ROAD and all(abs(p[1] - L.BANK_Z) < 0.01 for p in w.points)
        if cls != "tertiary" and not bank:
            continue
        if w.tags.get("bridge"):
            continue
        for a, b in _runs(w):
            length = math.dist(a, b)
            if length < 2.0 * ROW_END_MARGIN_M + 16.0:
                continue
            ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
            nx, nz = -uz, ux
            a2 = (a[0] + ux * ROW_END_MARGIN_M, a[1] + uz * ROW_END_MARGIN_M)
            b2 = (b[0] - ux * ROW_END_MARGIN_M, b[1] - uz * ROW_END_MARGIN_M)
            sides = (1.0, -1.0)
            if bank:
                sides = tuple(s for s in sides if (a2[1] + s * nz * ROW_OFFSET_M) < L.BANK_Z)
            for s in sides:
                p = (a2[0] + s * nx * ROW_OFFSET_M, a2[1] + s * nz * ROW_OFFSET_M)
                q = (b2[0] + s * nx * ROW_OFFSET_M, b2[1] + s * nz * ROW_OFFSET_M)
                if abs(p[1] - L.river_centre(p[0])) < L.RIVER_HALF_W + 10.0:
                    continue
                if _row_exists(d, p, q):
                    continue
                d.tree_rows.append(Way(d._id("veg"), [L._r(p), L._r(q)], {"natural": "tree_row"}))
