"""House hints: a type, a front wall facing the street, a door and party walls per house.

Approach: every house footprint (`house`, `detached`, `semidetached_house`, `terrace`,
`bungalow`) gets a hint the game builds from. Party walls are outer-ring edges that lie along
a neighbouring footprint (closer than PARTY_GAP_M over most of their length): terrace rows and
semi-detached pairs in OSM are drawn as one way per unit sharing those edges. The type comes
from the kind, the party walls, the tagged levels, the footprint size and a seed from the id.
The front wall is the edge facing the nearest street (drivable, not a service lane), so the
door and porch face it; the setback is the distance from that wall to the street's edge.
Houses whose height came from the per-kind default get the type's own height instead.
"""

from __future__ import annotations

import logging
import zlib
from dataclasses import dataclass, field

from shapely import STRtree
from shapely.geometry import LineString, Point, Polygon

from osm_import.buildings import Building, BuildingsResult
from osm_import.graph import RoadGraph

log = logging.getLogger(__name__)

HOUSE_KINDS = {"house", "detached", "semidetached_house", "terrace", "bungalow"}
TYPES = ("detached", "cottage", "bungalow", "semi", "terrace")
STREET_EXCLUDED = {"service", "motorway", "motorway_link", "trunk_link", "parking"}
PARTY_GAP_M = 0.6  # a neighbour this close along an edge shares the wall
PARTY_MIN_SHARED = 0.6  # of the edge's length
MIN_FRONT_EDGE_M = 2.5
STREET_REACH_M = 60.0
FACING_MIN_COS = 0.3  # the wall's outward normal must point this much toward the street
MAX_HOUSE_AREA_M2 = 400.0  # bigger "house" footprints are blocks: no hint
# Height to the eaves per type (the roof rises above it), used when the height was defaulted.
EAVE_M = {"detached": 5.8, "cottage": 4.2, "bungalow": 3.0, "semi": 5.8, "terrace": 6.0}
STOREYS = {"detached": 2.0, "cottage": 1.5, "bungalow": 1.0, "semi": 2.0, "terrace": 2.0}


@dataclass
class HouseHint:
    building_id: str
    type: str
    storeys: float
    front_edge: int  # index i of the outer-ring edge rings[0][i] -> rings[0][i+1]
    door: tuple[float, float]
    setback_m: float | None  # None when no street is within reach
    street: str | None  # road edge id
    party_walls: list[int] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "type": self.type,
            "storeys": self.storeys,
            "front_edge": self.front_edge,
            "door": [round(self.door[0], 2), round(self.door[1], 2)],
            "setback_m": None if self.setback_m is None else round(self.setback_m, 2),
            "street": self.street,
            "party_walls": self.party_walls,
        }


def seed01(building_id: str, salt: str = "") -> float:
    """A stable 0..1 seed from the id (crc32, so it is the same on every run and machine)."""
    return (zlib.crc32((salt + building_id).encode()) % 10007) / 10007.0


def _edges(
    ring: list[tuple[float, float]],
) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    return [(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))]


def party_walls(b: Building, neighbours: list[tuple[int, Polygon]]) -> tuple[list[int], set[int]]:
    """(indices of the outer-ring edges that lie along a neighbouring footprint, those neighbours)."""
    out: list[int] = []
    sharing: set[int] = set()
    zones = [(j, n.buffer(PARTY_GAP_M)) for j, n in neighbours]
    for i, (a, c) in enumerate(_edges(b.rings[0])):
        seg = LineString([a, c])
        if seg.length < 0.5:
            continue
        shared, j = max(((seg.intersection(z).length, j) for j, z in zones), default=(0.0, -1))
        if shared >= PARTY_MIN_SHARED * seg.length:
            out.append(i)
            sharing.add(j)
    return out, sharing


def house_type(b: Building, n_party: int, area: float, in_row: bool = False) -> str:
    """The house type from the kind, the party walls, the levels, the size and the seed.
    `in_row`: a neighbour sharing a wall has two or more party walls (this is a row's end)."""
    if b.kind == "terrace" or n_party >= 2 or (n_party == 1 and in_row):
        return "terrace"
    if b.kind == "semidetached_house" or n_party == 1:
        return "semi"
    if b.kind == "bungalow" or b.levels == 1:
        return "bungalow"
    if b.levels >= 2:
        return "detached"
    s = seed01(b.id, "type")
    if area < 70.0:
        return "cottage" if s < 0.5 else "detached"
    if area > 160.0:
        return "bungalow" if s < 0.3 else "detached"
    if s < 0.2:
        return "cottage"
    if s < 0.35:
        return "bungalow"
    return "detached"


def _front(b: Building, party: list[int], streets: list[tuple[str, LineString, float]], tree):
    """(edge index, street id, setback) of the wall facing the nearest street."""
    ring = b.rings[0]
    centre = Polygon(ring).centroid
    best = None
    near = [streets[i] for i in tree.query(centre.buffer(STREET_REACH_M))] if streets else []
    for i, (a, c) in enumerate(_edges(ring)):
        dx, dz = c[0] - a[0], c[1] - a[1]
        length = (dx * dx + dz * dz) ** 0.5
        if i in party or length < MIN_FRONT_EDGE_M:
            continue
        # Rings are counter-clockwise in (x, z): the outward normal of a->c is (dz, -dx).
        nx, nz = dz / length, -dx / length
        mid = Point((a[0] + c[0]) / 2.0, (a[1] + c[1]) / 2.0)
        for sid, line, half_w in near:
            p = line.interpolate(line.project(mid))
            vx, vz = p.x - mid.x, p.y - mid.y
            d = (vx * vx + vz * vz) ** 0.5
            if d > STREET_REACH_M or d < 1e-6 or (vx * nx + vz * nz) / d < FACING_MIN_COS:
                continue
            score = d - min(length, 12.0) * 0.25  # a longer wall wins a near tie
            if best is None or score < best[0]:
                best = (score, i, sid, max(d - half_w, 0.0))
    if best is None:
        return None
    return best[1], best[2], best[3]


def _longest_free(ring, party: list[int]) -> int:
    edges = _edges(ring)
    order = sorted(
        range(len(edges)),
        key=lambda i: (
            -((edges[i][1][0] - edges[i][0][0]) ** 2 + (edges[i][1][1] - edges[i][0][1]) ** 2)
        ),
    )
    free = [i for i in order if i not in party]
    return (free or order)[0]


def build_house_hints(buildings: BuildingsResult, graph: RoadGraph) -> dict[str, HouseHint]:
    """A hint per house footprint, keyed by building id. Defaulted heights take the type's."""
    houses = [b for b in buildings.buildings if b.kind in HOUSE_KINDS and len(b.rings[0]) >= 3]
    polys = [Polygon(b.rings[0]) for b in houses]
    house_tree = STRtree(polys)
    streets: list[tuple[str, LineString, float]] = []
    for e in graph.edges.values():
        if e.road_class in STREET_EXCLUDED or e.tunnel or e.bridge or len(e.polyline) < 2:
            continue
        streets.append((e.id, LineString([(p[0], p[2]) for p in e.polyline]), e.width_m / 2.0))
    street_tree = STRtree([s[1] for s in streets])
    hints: dict[str, HouseHint] = {}
    counts: dict[str, int] = {}
    party: dict[int, tuple[list[int], set[int]]] = {}
    for idx, b in enumerate(houses):
        if polys[idx].area > MAX_HOUSE_AREA_M2:
            continue
        near = [(j, polys[j]) for j in house_tree.query(polys[idx].buffer(PARTY_GAP_M)) if j != idx]
        party[idx] = party_walls(b, near)
    for idx, (walls, sharing) in party.items():
        b = houses[idx]
        in_row = any(len(party.get(j, ([], set()))[0]) >= 2 for j in sharing)
        kind = house_type(b, len(walls), polys[idx].area, in_row)
        front = _front(b, walls, streets, street_tree)
        if front is None:
            edge, sid, setback = _longest_free(b.rings[0], walls), None, None
        else:
            edge, sid, setback = front
        a, c = _edges(b.rings[0])[edge]
        # Terrace and semi doors sit to one side of the unit (seeded); others in the middle.
        t = 0.5 if kind not in ("terrace", "semi") else (0.3 if seed01(b.id, "door") < 0.5 else 0.7)
        door = (a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t)
        hints[b.id] = HouseHint(b.id, kind, STOREYS[kind], edge, door, setback, sid, walls)
        b.house = hints[b.id].to_dict()
        counts[kind] = counts.get(kind, 0) + 1
        if b.height_source == "default":
            b.height_m = EAVE_M[kind]
    log.info("houses: %d hints %s", len(hints), counts)
    return hints
