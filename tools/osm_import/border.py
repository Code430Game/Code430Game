"""District borders for stitching (add-district-stitching 1.1).

A district with a border on the city's chunk grid (region.py) is imported from the lat/lon box
around that border, so its data runs a little past it. After the heights are final, the road
graph and the pedestrian ways are cut at the border's rectangle: everything outside goes, and
each road that leaves becomes a dead end exactly on the border line. Two neighbouring
districts cut the same OSM road at the same line in the same frame, so their cut ends meet;
each one is written down as a crossing (`border.v0.json`) for the game to join, and the
roadblock at that end is tagged with the border side it stands on.

Each border line has one owner: a district owns its west and north lines, so a road lying
along its east or south line is its neighbour's. A junction exactly on a line isn't split (OSM
coordinates almost never land on a chunk line; move the border if one does).

Pieces keep the edge's id when there is one; a road that leaves and comes back makes several,
`<id>b<k>`. A new end node is `b<n>`, numbered in edge order so a re-export gives the same ids.
"""

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass

from osm_import.graph import PedestrianWay, Point, RoadEdge, RoadGraph, RoadNode, polyline_length

SIDES = ("west", "east", "north", "south")  # x0, x1, z0 (north: z grows south), z1
ON_LINE_M = 0.01


@dataclass
class Crossing:
    """A road leaving the district: where, which way out, and its lanes going out and in."""

    edge: str
    node: str
    osm_way_id: int
    side: str
    position: Point
    heading: tuple[float, float]  # unit (x, z), pointing out of the district
    lanes_out: int
    lanes_in: int
    road_class: str
    width_m: float
    layer: int
    bridge: bool
    tunnel: bool

    def to_dict(self) -> dict:
        return {
            "edge": self.edge,
            "node": self.node,
            "osm_way_id": self.osm_way_id,
            "side": self.side,
            "position": [round(v, 3) for v in self.position],
            "heading": [round(v, 4) for v in self.heading],
            "lanes_out": self.lanes_out,
            "lanes_in": self.lanes_in,
            "class": self.road_class,
            "width_m": round(self.width_m, 2),
            "layer": self.layer,
            "bridge": self.bridge,
            "tunnel": self.tunnel,
        }


@dataclass
class BorderResult:
    rect: tuple[float, float, float, float]  # x0, z0, x1, z1 in metres
    chunks: tuple[int, int, int, int]
    crossings: list[Crossing]
    edges_removed: int = 0
    edges_cut: int = 0
    pedestrian_removed: int = 0

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, local x east and z south",
            "chunks": list(self.chunks),
            "rect": [round(v, 3) for v in self.rect],
            "crossings": [c.to_dict() for c in self.crossings],
        }

    def counts(self) -> dict:
        sides: dict[str, int] = {}
        for c in self.crossings:
            sides[c.side] = sides.get(c.side, 0) + 1
        return {
            "crossings": len(self.crossings),
            "by_side": dict(sorted(sides.items())),
            "edges_removed": self.edges_removed,
            "edges_cut": self.edges_cut,
            "pedestrian_removed": self.pedestrian_removed,
        }


def border_rect(
    chunks: tuple[int, int, int, int], chunk_m: float
) -> tuple[float, float, float, float]:
    x0, z0, x1, z1 = chunks
    return (x0 * chunk_m, z0 * chunk_m, x1 * chunk_m, z1 * chunk_m)


def side_of(p: tuple[float, float], rect: tuple[float, float, float, float]) -> str:
    """The border side `p` stands on (the nearest of the four lines)."""
    x0, z0, x1, z1 = rect
    d = {
        "west": abs(p[0] - x0),
        "east": abs(p[0] - x1),
        "north": abs(p[1] - z0),
        "south": abs(p[1] - z1),
    }
    return min(SIDES, key=lambda s: d[s])


def _inside(p: Point, rect) -> bool:
    x0, z0, x1, z1 = rect
    return x0 <= p[0] <= x1 and z0 <= p[2] <= z1


def _clip_segment(a: Point, b: Point, rect) -> tuple[float, float] | None:
    """Liang-Barsky: the part of a->b inside the rectangle as (t0, t1), or None. A segment
    lying along the east or south line belongs to the neighbour there (each line has one
    owner: a district owns its west and north lines), so it is outside."""
    x0, z0, x1, z1 = rect
    dx, dz = b[0] - a[0], b[2] - a[2]
    t0, t1 = 0.0, 1.0
    for k, (p, q) in enumerate(
        ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dz, a[2] - z0), (dz, z1 - a[2]))
    ):
        if p == 0.0:
            if q < 0.0 or (q == 0.0 and k in (1, 3)):
                return None
            continue
        r = q / p
        if p < 0.0:
            t0 = max(t0, r)
        else:
            t1 = min(t1, r)
        if t0 > t1:
            return None
    return t0, t1


def _lerp(a: Point, b: Point, t: float) -> Point:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def clip_polyline(pl: list[Point], rect) -> list[tuple[list[Point], bool, bool]]:
    """The runs of `pl` inside `rect`: (points, starts at pl[0], ends at pl[-1]). A run that
    doesn't start (end) at the polyline's own end starts (ends) on the border."""
    runs: list[tuple[list[Point], bool, bool]] = []
    cur: list[Point] = []
    cur_starts = False
    n = len(pl)
    for i in range(n - 1):
        a, b = pl[i], pl[i + 1]
        t = _clip_segment(a, b, rect)
        if t is None:
            if cur:
                runs.append((cur, cur_starts, False))
                cur = []
            continue
        t0, t1 = t
        pa, pb = _lerp(a, b, t0), _lerp(a, b, t1)
        if not cur:
            cur = [pa]
            cur_starts = i == 0 and t0 == 0.0
        elif t0 > 0.0:  # left and came straight back within one segment: a new run
            runs.append((cur, cur_starts, False))
            cur = [pa]
            cur_starts = False
        if math.dist((pb[0], pb[2]), (cur[-1][0], cur[-1][2])) > 1e-9:
            cur.append(pb)
        if t1 < 1.0:
            runs.append((cur, cur_starts, False))
            cur = []
    if cur:
        runs.append((cur, cur_starts, True))
    return [r for r in runs if len(r[0]) >= 2 and polyline_length(r[0]) > 0.05]


def clip_graph(graph: RoadGraph, chunks: tuple[int, int, int, int], chunk_m: float) -> BorderResult:
    """Cuts the graph and the pedestrian ways at the border, in place, and lists the crossings."""
    rect = border_rect(chunks, chunk_m)
    result = BorderResult(rect, chunks, [])
    new_edges: dict[str, RoadEdge] = {}
    new_nodes: dict[str, RoadNode] = {}
    counter = 0

    def border_node(p: Point) -> str:
        nonlocal counter
        counter += 1
        nid = f"b{counter}"
        new_nodes[nid] = RoadNode(nid, p, [], {}, "dead_end", p[1])
        return nid

    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        inside_all = all(_inside(p, rect) for p in e.polyline)
        if inside_all:
            new_edges[eid] = e
            continue
        runs = clip_polyline(e.polyline, rect)
        if not runs:
            result.edges_removed += 1
            continue
        result.edges_cut += 1
        for k, (pts, starts, ends) in enumerate(runs):
            pid = eid if len(runs) == 1 else f"{eid}b{k + 1}"
            frm = e.from_node if starts else border_node(pts[0])
            to = e.to_node if ends else border_node(pts[-1])
            piece = dataclasses.replace(
                e,
                id=pid,
                from_node=frm,
                to_node=to,
                polyline=pts,
                length_m=polyline_length(pts),
                control_from=e.control_from if starts else "none",
                control_to=e.control_to if ends else "none",
            )
            new_edges[pid] = piece
            if not starts:
                result.crossings.append(
                    _crossing(piece, frm, pts[0], pts[1], rect, outward_is_forward=False)
                )
            if not ends:
                result.crossings.append(
                    _crossing(piece, to, pts[-1], pts[-2], rect, outward_is_forward=True)
                )
    used = {e.from_node for e in new_edges.values()} | {e.to_node for e in new_edges.values()}
    nodes = {nid: n for nid, n in graph.nodes.items() if nid in used}
    nodes.update(new_nodes)
    graph.nodes = nodes
    graph.edges = new_edges
    peds: list[PedestrianWay] = []
    for w in graph.pedestrian:
        if all(_inside(p, rect) for p in w.polyline):
            peds.append(w)
            continue
        runs = clip_polyline(w.polyline, rect)
        if not runs:
            result.pedestrian_removed += 1
            continue
        for k, (pts, _s, _e) in enumerate(runs):
            top = w.top
            if top and len(top) != len(pts):
                top = []  # the ceiling heights were per original point: a cut piece drops them
            peds.append(
                dataclasses.replace(
                    w, id=w.id if len(runs) == 1 else f"{w.id}b{k + 1}", polyline=pts, top=top
                )
            )
    graph.pedestrian = peds
    graph.bus_stops = [
        s
        for s in graph.bus_stops
        if s.get("edge") in new_edges and _inside(tuple(s["position"]), rect)
    ]
    result.crossings.sort(
        key=lambda c: (c.side, round(c.position[0], 1), round(c.position[2], 1), c.edge)
    )
    return result


def _crossing(
    edge: RoadEdge, node: str, at: Point, inner: Point, rect, outward_is_forward: bool
) -> Crossing:
    dx, dz = at[0] - inner[0], at[2] - inner[2]
    length = math.hypot(dx, dz) or 1.0
    out_lanes, in_lanes = (
        (edge.lanes_forward, edge.lanes_backward)
        if outward_is_forward
        else (edge.lanes_backward, edge.lanes_forward)
    )
    return Crossing(
        edge=edge.id,
        node=node,
        osm_way_id=edge.osm_way_id,
        side=side_of((at[0], at[2]), rect),
        position=at,
        heading=(dx / length, dz / length),
        lanes_out=out_lanes,
        lanes_in=in_lanes,
        road_class=edge.road_class,
        width_m=edge.width_m,
        layer=edge.layer,
        bridge=edge.bridge,
        tunnel=edge.tunnel,
    )
