"""Bridge structures: group bridge edges into bridges, put walkways on their decks, place
piers and abutments.

OSM splits one deck into several ways wherever a tag changes, and a divided highway is two
one-way ways side by side. A bridge here is:
- the `bridge=*` road edges that share a node on the same layer, joined with
- parallel carriageways whose ribbons run within `merge_gap_m` for most of their length,
- and anything inside the same `man_made=bridge` outline (the footprint mappers draw; it also
  names the bridge).
Footbridges are bridge walkways (layer above 0) that join no road bridge.

Walkways that belong to a road bridge (the same outline, or `bridge=*` running beside the
deck within `walkway_range_m`) are given the deck's height and widen the deck on their side;
the rest stay where they are, so the ground sidewalks of the road below never join a deck.

Piers stand every `pier_spacing_m` (`pier_spacing_water_m` over water), moved along the span
until they are `pier_clearance_m` clear of every road ribbon and walkway on a lower level;
where no clear spot is within a third of the spacing, that pier is left out (a longer span is
fine, a pier in a lane is not). Their feet are on the built terrain (or the water floor).
Each end where the deck meets the ground gets an abutment for the game to build.
"""

from __future__ import annotations

import itertools
import logging
import math
from dataclasses import dataclass, field

from osm_import.elevation import _seg_dist, _SegmentIndex
from osm_import.graph import PedestrianWay, RoadEdge, RoadGraph
from osm_import.osm_data import BBox
from osm_import.projection import Projector
from osm_import.water import WaterResult

log = logging.getLogger(__name__)

DEFAULTS = {
    "merge_gap_m": 3.0,
    "walkway_range_m": 4.0,
    "pier_spacing_m": 25.0,
    "pier_spacing_water_m": 40.0,
    "pier_clearance_m": 1.5,
    "pier_thickness_m": 0.9,
    "column_radius_m": 0.7,
    "depth_per_span": 0.06,
    "depth_min_m": 0.8,
    "depth_max_m": 1.8,
    "end_clear_m": 4.0,
    "sidewalk_tag_width_m": 1.8,
}


def bridges_query(bbox: BBox) -> str:
    """`man_made=bridge` outlines in the bbox, with geometry."""
    b = bbox.overpass()
    return (
        "[out:json][timeout:180];("
        f'way["man_made"="bridge"]({b});relation["man_made"="bridge"]({b});'
        ");out body geom;"
    )


@dataclass
class DeckStrip:
    """One piece of deck along a road edge or walkway: points with the half-width each side.
    Left is left of travel along `points` (north when heading east; x east, z south)."""

    source: str  # edge or pedestrian way id
    points: list[tuple[float, float, float]]
    left_m: list[float]
    right_m: list[float]

    def to_dict(self) -> dict:
        return {
            "source": self.source,
            "points": [[round(v, 3) for v in p] for p in self.points],
            "left_m": [round(v, 3) for v in self.left_m],
            "right_m": [round(v, 3) for v in self.right_m],
        }


@dataclass
class Pier:
    x: float
    z: float
    top_y: float
    bottom_y: float
    dir: tuple[float, float]  # along the deck
    width_m: float  # across the deck
    kind: str  # "wall" | "column"

    def to_dict(self) -> dict:
        return {
            "x": round(self.x, 3),
            "z": round(self.z, 3),
            "top_y": round(self.top_y, 3),
            "bottom_y": round(self.bottom_y, 3),
            "dir": [round(self.dir[0], 4), round(self.dir[1], 4)],
            "width_m": round(self.width_m, 3),
            "kind": self.kind,
        }


@dataclass
class BridgeEnd:
    x: float
    y: float
    z: float
    dir: tuple[float, float]  # pointing off the deck, onto the approach
    width_m: float

    def to_dict(self) -> dict:
        return {
            "x": round(self.x, 3),
            "y": round(self.y, 3),
            "z": round(self.z, 3),
            "dir": [round(self.dir[0], 4), round(self.dir[1], 4)],
            "width_m": round(self.width_m, 3),
        }


@dataclass
class Bridge:
    id: str
    kind: str  # over_road | over_water | over_ground | footbridge
    name: str | None
    edges: list[str]
    walkways: list[str]
    span_m: float
    depth_m: float
    decks: list[DeckStrip] = field(default_factory=list)
    piers: list[Pier] = field(default_factory=list)
    ends: list[BridgeEnd] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "name": self.name,
            "edges": self.edges,
            "walkways": self.walkways,
            "span_m": round(self.span_m, 2),
            "depth_m": round(self.depth_m, 2),
            "decks": [d.to_dict() for d in self.decks],
            "piers": [p.to_dict() for p in self.piers],
            "ends": [e.to_dict() for e in self.ends],
        }


@dataclass
class BridgesResult:
    bridges: list[Bridge] = field(default_factory=list)
    walkways_lifted: int = 0
    piers_skipped: int = 0

    def counts(self) -> dict:
        kinds: dict[str, int] = {}
        for b in self.bridges:
            kinds[b.kind] = kinds.get(b.kind, 0) + 1
        return {
            "bridges": len(self.bridges),
            "kinds": dict(sorted(kinds.items())),
            "walkways_on_decks": sum(len(b.walkways) for b in self.bridges),
            "walkways_lifted": self.walkways_lifted,
            "piers": sum(len(b.piers) for b in self.bridges),
            "piers_skipped": self.piers_skipped,
            "abutments": sum(len(b.ends) for b in self.bridges),
        }

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, x east, z south; y up",
            "bridges": [b.to_dict() for b in self.bridges],
        }


# --- geometry helpers ---


def _length(pl) -> float:
    return sum(math.dist((a[0], a[2]), (b[0], b[2])) for a, b in itertools.pairwise(pl))


def _samples(pl, step: float):
    """(x, y, z, dx, dz, s) every `step` metres along a polyline, ends included."""
    total = _length(pl)
    if total <= 0:
        return
    n = max(1, int(total // step))
    for k in range(n + 1):
        yield (*_point_at(pl, total * k / n), total * k / n)


def _point_at(pl, s: float):
    run = 0.0
    for a, b in itertools.pairwise(pl):
        seg = math.dist((a[0], a[2]), (b[0], b[2]))
        if seg > 0 and run + seg >= s:
            t = (s - run) / seg
            dx, dz = (b[0] - a[0]) / seg, (b[2] - a[2]) / seg
            return (
                a[0] + (b[0] - a[0]) * t,
                a[1] + (b[1] - a[1]) * t,
                a[2] + (b[2] - a[2]) * t,
                dx,
                dz,
            )
        run += seg
    a, b = pl[-2], pl[-1]
    seg = max(math.dist((a[0], a[2]), (b[0], b[2])), 1e-6)
    return (b[0], b[1], b[2], (b[0] - a[0]) / seg, (b[2] - a[2]) / seg)


def _nearest_on(pl, x: float, z: float) -> tuple[float, float, int, float]:
    """(distance, height, segment index, signed side: + left) of the closest point on `pl`."""
    best = (math.inf, 0.0, 0, 0.0)
    for i, (a, b) in enumerate(itertools.pairwise(pl)):
        dx, dz = b[0] - a[0], b[2] - a[2]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[2]) * dz) / l2))
        px, pz = a[0] + dx * t, a[2] + dz * t
        d = math.hypot(x - px, z - pz)
        if d < best[0]:
            # Left of travel, as everywhere in this file: cross(dir, p - a) < 0 (north when heading east).
            side = 1.0 if (dx * (z - a[2]) - dz * (x - a[0])) < 0 else -1.0
            best = (d, a[1] + (b[1] - a[1]) * t, i, side)
    return best


class _Surfaces:
    """Every road ribbon and walkway as indexed segments, for "what is under this point"."""

    def __init__(self, graph: RoadGraph) -> None:
        self.index = _SegmentIndex()
        for eid, e in graph.edges.items():
            if not e.tunnel:
                self._add(eid, e.polyline, e.width_m / 2.0)
        for w in graph.pedestrian:
            if not w.covered:
                self._add(w.id, w.polyline, w.width_m / 2.0)

    def _add(self, sid: str, pl, hw: float) -> None:
        for a, b in itertools.pairwise(pl):
            self.index.add((a[0], a[2]), (b[0], b[2]), (sid, hw, a[1], b[1]))

    def near(self, x: float, z: float, radius: float):
        """(id, centreline distance, height there, half width) of each segment within reach."""
        for a, b, (sid, hw, ya, yb) in self.index.near(x, z, radius):
            dx, dz = b[0] - a[0], b[1] - a[1]
            l2 = dx * dx + dz * dz
            t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
            d = math.hypot(x - (a[0] + dx * t), z - (a[1] + dz * t))
            if d <= radius:
                yield sid, d, ya + (yb - ya) * t, hw


def _depth(span: float, rules: dict) -> float:
    return max(rules["depth_min_m"], min(rules["depth_max_m"], rules["depth_per_span"] * span))


# --- grouping ---


class _Union:
    def __init__(self, keys) -> None:
        self.parent = {k: k for k in keys}

    def find(self, k):
        while self.parent[k] != k:
            self.parent[k] = self.parent[self.parent[k]]
            k = self.parent[k]
        return k

    def join(self, a, b) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[max(ra, rb)] = min(ra, rb)


def _outline_polygons(payload: dict | None, proj: Projector):
    """[(shapely Polygon, name)] from a `man_made=bridge` payload."""
    if not payload:
        return []
    from shapely.geometry import Polygon

    out = []
    for el in payload.get("elements", []):
        geoms = []
        if el.get("type") == "way" and "geometry" in el:
            geoms.append(el["geometry"])
        elif el.get("type") == "relation":
            geoms += [
                m["geometry"]
                for m in el.get("members", [])
                if m.get("role") == "outer" and "geometry" in m
            ]
        for g in geoms:
            ring = [proj.to_local(p["lat"], p["lon"]) for p in g]
            if len(ring) >= 4:
                poly = Polygon(ring)
                if not poly.is_valid:
                    poly = poly.buffer(0)
                if not poly.is_empty:
                    out.append((poly, el.get("tags", {}).get("name")))
    return out


def _water_polygons(water: WaterResult | None):
    if water is None:
        return []
    from shapely.geometry import Polygon

    polys = []
    for w in water.polygons:
        if len(w.vertices) >= 3:
            p = Polygon(w.vertices)
            polys.append(p if p.is_valid else p.buffer(0))
    return polys


def _parallel(a: RoadEdge, b: RoadEdge, gap: float) -> bool:
    """True when b runs beside a, ribbon gap at most `gap`, for at least half of a's length."""
    near = total = 0
    for x, _y, z, _dx, _dz, _s in _samples(a.polyline, 4.0):
        total += 1
        d, _h, _i, _side = _nearest_on(b.polyline, x, z)
        if d - a.width_m / 2.0 - b.width_m / 2.0 <= gap:
            near += 1
    return total > 0 and near * 2 >= total


def build_bridges(
    graph: RoadGraph,
    sample_ground,
    cfg_rules: dict | None = None,
    outlines_payload: dict | None = None,
    proj: Projector | None = None,
    water: WaterResult | None = None,
) -> BridgesResult:
    """Groups bridges, lifts their walkways onto the decks (mutating the graph's pedestrian
    ways), and places piers and abutments. `sample_ground(x, z)` is the built terrain."""
    rules = dict(DEFAULTS)
    rules.update(cfg_rules or {})
    outlines = _outline_polygons(outlines_payload, proj) if proj is not None else []
    water_polys = _water_polygons(water)
    from shapely.geometry import Point

    def outline_of(x: float, z: float) -> int:
        p = Point(x, z)
        for i, (poly, _name) in enumerate(outlines):
            if poly.contains(p):
                return i
        return -1

    bridge_edges = {eid: e for eid, e in graph.edges.items() if e.bridge and not e.tunnel}
    keys = list(bridge_edges)
    u = _Union(keys)
    by_node: dict[tuple[str, int], list[str]] = {}
    for eid, e in bridge_edges.items():
        for n in (e.from_node, e.to_node):
            by_node.setdefault((n, e.layer), []).append(eid)
    for ids in by_node.values():
        for other in ids[1:]:
            u.join(ids[0], other)
    edge_outline = {}
    for eid, e in bridge_edges.items():
        mid = _point_at(e.polyline, _length(e.polyline) / 2.0)
        edge_outline[eid] = outline_of(mid[0], mid[2])
    by_outline: dict[int, list[str]] = {}
    for eid, oi in edge_outline.items():
        if oi >= 0:
            by_outline.setdefault(oi, []).append(eid)
    for ids in by_outline.values():
        for other in ids[1:]:
            u.join(ids[0], other)
    index = _SegmentIndex()
    for eid, e in bridge_edges.items():
        for a, b in zip(e.polyline, e.polyline[1:], strict=False):
            index.add((a[0], a[2]), (b[0], b[2]), eid)
    for eid, e in bridge_edges.items():
        mid = _point_at(e.polyline, _length(e.polyline) / 2.0)
        for _a, _b, oid in index.near(mid[0], mid[2], e.width_m + rules["merge_gap_m"] + 20.0):
            if oid == eid or u.find(oid) == u.find(eid):
                continue
            o = bridge_edges[oid]
            if o.layer == e.layer and _parallel(e, o, rules["merge_gap_m"]):
                u.join(eid, oid)
    groups: dict[str, list[str]] = {}
    for eid in sorted(keys):
        groups.setdefault(u.find(eid), []).append(eid)

    surfaces = _Surfaces(graph)
    result = BridgesResult()
    walk_by_group: dict[str, list[PedestrianWay]] = {g: [] for g in groups}
    lone_walks: list[PedestrianWay] = []
    for w in graph.pedestrian:
        if w.layer <= 0 or w.covered or len(w.polyline) < 2:
            continue
        mid = _point_at(w.polyline, _length(w.polyline) / 2.0)
        oi = outline_of(mid[0], mid[2])
        best_group, best_share = None, 0.0
        if oi >= 0:
            for g, ids in groups.items():
                if any(edge_outline.get(i) == oi for i in ids):
                    best_group, best_share = g, 1.0
        if best_group is None:
            # Beside a deck for most of its length?
            share_by_group: dict[str, int] = {}
            pts = list(_samples(w.polyline, 3.0))
            for x, _y, z, _dx, _dz, _s in pts:
                hit = set()
                for _a, _b, eid in index.near(x, z, rules["walkway_range_m"] + 20.0):
                    e = bridge_edges[eid]
                    d, _h, _i, _side = _nearest_on(e.polyline, x, z)
                    if d - e.width_m / 2.0 <= rules["walkway_range_m"]:
                        hit.add(u.find(eid))
                for g in hit:
                    share_by_group[g] = share_by_group.get(g, 0) + 1
            for g, n in share_by_group.items():
                share = n / max(len(pts), 1)
                if share > best_share:
                    best_group, best_share = g, share
        if best_group is not None and best_share >= 0.5:
            walk_by_group[best_group].append(w)
        elif w.kind not in ("sidewalk", "crossing"):
            lone_walks.append(w)

    for n, (g, ids) in enumerate(sorted(groups.items())):
        edges = [bridge_edges[i] for i in ids]
        walks = walk_by_group[g]
        lifted = _lift_walkways(walks, edges)
        result.walkways_lifted += lifted
        span = max(_length(e.polyline) for e in edges)
        names = [
            nm for oi in {edge_outline[i] for i in ids} if oi >= 0 for nm in [outlines[oi][1]] if nm
        ]
        name = names[0] if names else next((e.name for e in edges if e.name), None)
        kind = _kind(edges, surfaces, set(ids), water_polys)
        b = Bridge(
            f"bridge{n}", kind, name, ids, sorted(w.id for w in walks), span, _depth(span, rules)
        )
        b.decks = [_road_deck(e, walks, rules) for e in edges] + [_walk_deck(w) for w in walks]
        _place_piers(
            b,
            edges + walks,
            surfaces,
            set(ids) | {w.id for w in walks},
            sample_ground,
            water_polys,
            rules,
            result,
        )
        b.ends = _ends(edges, graph, set(ids))
        result.bridges.append(b)
    for w in lone_walks:
        span = _length(w.polyline)
        mid = _point_at(w.polyline, span / 2.0)
        if mid[1] - sample_ground(mid[0], mid[2]) < 2.0:
            continue  # a bridge path at grade (a boardwalk, a culvert crossing): nothing to build
        b = Bridge(
            f"bridge{len(result.bridges)}",
            "footbridge",
            w.name,
            [],
            [w.id],
            span,
            _depth(span, rules) * 0.6,
        )
        b.decks = [_walk_deck(w)]
        _place_piers(b, [w], surfaces, {w.id}, sample_ground, water_polys, rules, result)
        b.ends = _walk_ends(w)
        result.bridges.append(b)
    log.info("bridges: %s", result.counts())
    return result


def _kind(edges, surfaces: _Surfaces, own: set[str], water_polys) -> str:
    from shapely.geometry import Point

    over_road = over_water = 0
    for e in edges:
        for x, y, z, _dx, _dz, _s in _samples(e.polyline, 5.0):
            if any(p.contains(Point(x, z)) for p in water_polys):
                over_water += 1
                continue
            for sid, d, h, hw in surfaces.near(x, z, 20.0):
                if sid not in own and d <= hw and h < y - 2.0:
                    over_road += 1
                    break
    if over_water >= over_road and over_water > 0:
        return "over_water"
    return "over_road" if over_road > 0 else "over_ground"


def _lift_walkways(walks: list[PedestrianWay], edges: list[RoadEdge]) -> int:
    """Gives each walkway the height of the nearest deck point. Returns how many moved > 0.5 m."""
    moved = 0
    for w in walks:
        worst = 0.0
        pts = []
        for x, y, z in w.polyline:
            best = (math.inf, y)
            for e in edges:
                d, h, _i, _side = _nearest_on(e.polyline, x, z)
                if d < best[0]:
                    best = (d, h)
            worst = max(worst, abs(best[1] - y))
            pts.append((x, best[1], z))
        w.polyline = pts
        w.layer = max(w.layer, max(e.layer for e in edges))
        if worst > 0.5:
            moved += 1
    return moved


def _road_deck(e: RoadEdge, walks: list[PedestrianWay], rules: dict) -> DeckStrip:
    """The edge's ribbon, widened on each side to cover the walkways that run beside it."""
    hw = e.width_m / 2.0
    left, right = [], []
    for i, (x, _y, z) in enumerate(e.polyline):
        lw = rw = hw
        for w in walks:
            d, _h, _j, _side = _nearest_on(w.polyline, x, z)
            reach = d + w.width_m / 2.0
            if d - hw <= rules["walkway_range_m"] and reach > hw:
                # Which side of the edge is the walkway on?
                a = e.polyline[max(i - 1, 0)]
                b = e.polyline[min(i + 1, len(e.polyline) - 1)]
                dx, dz = b[0] - a[0], b[2] - a[2]
                wx, wz = _nearest_xz(w.polyline, x, z)
                left_side = (dx * (wz - z) - dz * (wx - x)) < 0
                if left_side:
                    lw = max(lw, reach)
                else:
                    rw = max(rw, reach)
        left.append(lw)
        right.append(rw)
    return DeckStrip(e.id, list(e.polyline), left, right)


def _nearest_xz(pl, x: float, z: float) -> tuple[float, float]:
    best = (math.inf, x, z)
    for a, b in itertools.pairwise(pl):
        dx, dz = b[0] - a[0], b[2] - a[2]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[2]) * dz) / l2))
        px, pz = a[0] + dx * t, a[2] + dz * t
        d = math.hypot(x - px, z - pz)
        if d < best[0]:
            best = (d, px, pz)
    return best[1], best[2]


def _walk_deck(w: PedestrianWay) -> DeckStrip:
    hw = w.width_m / 2.0
    return DeckStrip(w.id, list(w.polyline), [hw] * len(w.polyline), [hw] * len(w.polyline))


def _place_piers(
    b: Bridge,
    carriers,
    surfaces: _Surfaces,
    own: set[str],
    sample_ground,
    water_polys,
    rules,
    result,
) -> None:
    from shapely.geometry import Point

    def clear(x: float, y_deck: float, z: float) -> bool:
        for sid, d, h, hw in surfaces.near(x, z, 30.0):
            if sid not in own and d <= hw + rules["pier_clearance_m"] and h < y_deck - 1.0:
                return False
        return True

    for c in carriers:
        pl = c.polyline
        total = _length(pl)
        width = c.width_m
        mid = _point_at(pl, total / 2.0)
        over_water = any(p.contains(Point(mid[0], mid[2])) for p in water_polys)
        spacing = rules["pier_spacing_water_m"] if over_water else rules["pier_spacing_m"]
        n = int(total // spacing)
        for k in range(1, n + 1):
            s0 = total * k / (n + 1)
            if s0 < rules["end_clear_m"] or total - s0 < rules["end_clear_m"]:
                continue
            for off in _search(spacing / 3.0):
                s = s0 + off
                if s < rules["end_clear_m"] or total - s < rules["end_clear_m"]:
                    continue
                x, y, z, dx, dz = _point_at(pl, s)
                ground = sample_ground(x, z)
                top = y - b.depth_m
                if top - ground < 2.0:
                    break  # the deck is near the ground here: no pier needed
                if not clear(x, y, z):
                    continue
                wet = any(p.contains(Point(x, z)) for p in water_polys)
                b.piers.append(
                    Pier(x, z, top, ground - 1.0, (dx, dz), width, "column" if wet else "wall")
                )
                break
            else:
                result.piers_skipped += 1


def _search(reach: float):
    yield 0.0
    step = 1.0
    k = 1
    while k * step <= reach:
        yield k * step
        yield -k * step
        k += 1


def _ends(edges: list[RoadEdge], graph: RoadGraph, own: set[str]) -> list[BridgeEnd]:
    """Where the deck meets an approach: a node of the group with a non-bridge edge (or none)."""
    degree: dict[str, int] = {}
    for e in edges:
        for nd in (e.from_node, e.to_node):
            degree[nd] = degree.get(nd, 0) + 1
    outer_nodes = set()
    for eid, e in graph.edges.items():
        if eid in own:
            continue
        for nd in (e.from_node, e.to_node):
            if nd in degree:
                outer_nodes.add(nd)
    out = []
    for e in edges:
        for nd, pts in ((e.from_node, e.polyline), (e.to_node, list(reversed(e.polyline)))):
            if nd in outer_nodes or degree[nd] == 1:
                a, b = pts[0], pts[1]
                seg = max(math.dist((a[0], a[2]), (b[0], b[2])), 1e-6)
                out.append(
                    BridgeEnd(
                        a[0], a[1], a[2], ((a[0] - b[0]) / seg, (a[2] - b[2]) / seg), e.width_m
                    )
                )
    return out


def _walk_ends(w: PedestrianWay) -> list[BridgeEnd]:
    out = []
    for pts in (w.polyline, list(reversed(w.polyline))):
        a, b = pts[0], pts[1]
        seg = max(math.dist((a[0], a[2]), (b[0], b[2])), 1e-6)
        out.append(
            BridgeEnd(a[0], a[1], a[2], ((a[0] - b[0]) / seg, (a[2] - b[2]) / seg), w.width_m)
        )
    return out


def edge_distance(e: RoadEdge, x: float, z: float) -> float:
    """Distance from (x, z) to an edge's centreline (tests)."""
    return min(
        _seg_dist(x, z, a[0], a[2], b[0], b[2])
        for a, b in zip(e.polyline, e.polyline[1:], strict=False)
    )
