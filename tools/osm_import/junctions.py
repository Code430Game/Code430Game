"""Junction outlines and per-vertex heights, as the game draws them (update-junction-ground).

A port of the game's JunctionBuilder (game/world/roads/junction_builder.gd): at a node with
three or more roads the arms are sorted by bearing, each pair of neighbours gets a corner
where one's side line meets the next's, each arm is trimmed back to its farthest corner plus
a margin and capped there, and the outline walks cap, cap, corner around the node with
rounded corners. A walk that crosses itself falls back to the convex hull. The importer
flattens the terrain under each outline to the surface (pack.flatten_roads), so the arithmetic
here must match the game's: tools/tests/test_osm_junctions.py checks it against a dump of
the game's outlines on the proving ground (game/world/build/junction_outline_dump.gd).
The Godot geometry it leans on (line and segment intersection, ear-clip triangulation, the
convex hull) is ported too, so the same polygon falls back or triangulates on both sides.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from osm_import.graph import Point, RoadEdge, RoadGraph

TRIM_MARGIN_M = 3.0
MAX_TRIM_M = 60.0
FILLET_STEPS = 4
STRAIGHT_GAP_DEG = 150.0
ALONG_MERGE_M = 0.25
MAX_CORNER_HALF_WIDTHS = 3.0
PARALLEL_ARMS_DEG = 12.0
SPLIT_ARMS_DEG = 30.0
SORT_PROBE_M = 20.0
CMP_EPSILON = 0.00001  # Godot's
TAU = 2.0 * math.pi

FILLET, STRAIGHT, ALONG, SHARP, PAIR = range(5)  # JunctionBuilder.Corner

Vec = tuple[float, float]


@dataclass
class JunctionSurface:
    """One junction's outline (x, z per vertex, as the game's polygon_xz) and heights."""

    node_id: str
    centre: Point
    polygon: list[Vec]
    heights: list[float]
    trims: dict[str, float] = field(default_factory=dict)
    fallback_hull: bool = False
    has_bridge_arm: bool = False
    has_tunnel_arm: bool = False
    # Each arm's ribbon as (ax, az, bx, bz, ay, by, half width) segments: under an arm the
    # terrain follows the arm (pack._junction_field).
    arm_segments: list[tuple] = field(default_factory=list)

    def triangles(self) -> list[tuple[int, int, int]]:
        """The game's triangulation of the outline (Geometry2D.triangulate_polygon)."""
        tri = triangulate(self.polygon)
        return tri if tri is not None else []

    def bounds(self) -> tuple[float, float, float, float]:
        xs = [p[0] for p in self.polygon]
        zs = [p[1] for p in self.polygon]
        return min(xs), min(zs), max(xs), max(zs)


# -- vectors -----------------------------------------------------------------------------------


def _sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1])


def _add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1])


def _mul(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s)


def _dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1]


def _length(a: Vec) -> float:
    return math.hypot(a[0], a[1])


def _dist(a: Vec, b: Vec) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _normalized(a: Vec) -> Vec:
    l2 = a[0] * a[0] + a[1] * a[1]
    if l2 == 0.0:
        return (0.0, 0.0)
    length = math.sqrt(l2)
    return (a[0] / length, a[1] / length)


def _rotated(a: Vec, by: float) -> Vec:
    s, c = math.sin(by), math.cos(by)
    return (a[0] * c - a[1] * s, a[0] * s + a[1] * c)


def _lerp(a: Vec, b: Vec, t: float) -> Vec:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def _lerpf(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _fposmod(x: float, y: float) -> float:
    value = math.fmod(x, y)
    if (value < 0 and y > 0) or (value > 0 and y < 0):
        value += y
    return value + 0.0


def _normal(d: Vec) -> Vec:
    return (-d[1], d[0])


# -- Godot geometry ----------------------------------------------------------------------------


def line_intersects_line(from_a: Vec, dir_a: Vec, from_b: Vec, dir_b: Vec) -> Vec | None:
    """Geometry2D.line_intersects_line: where two infinite lines meet, None when parallel."""
    denom = dir_b[1] * dir_a[0] - dir_b[0] * dir_a[1]
    if abs(denom) < CMP_EPSILON:
        return None
    v = _sub(from_a, from_b)
    t = (dir_b[0] * v[1] - dir_b[1] * v[0]) / denom
    return _add(from_a, _mul(dir_a, t))


def segment_intersects_segment(from_a: Vec, to_a: Vec, from_b: Vec, to_b: Vec) -> bool:
    """Geometry2D.segment_intersects_segment, as a yes or no."""
    b = _sub(to_a, from_a)
    c = _sub(from_b, from_a)
    d = _sub(to_b, from_a)
    ab_len = _dot(b, b)
    if ab_len <= 0:
        return False
    bn = _mul(b, 1.0 / ab_len)
    c = (c[0] * bn[0] + c[1] * bn[1], c[1] * bn[0] - c[0] * bn[1])
    d = (d[0] * bn[0] + d[1] * bn[1], d[1] * bn[0] - d[0] * bn[1])
    if (c[1] < -CMP_EPSILON and d[1] < -CMP_EPSILON) or (c[1] > CMP_EPSILON and d[1] > CMP_EPSILON):
        return False
    if _is_equal_approx(c[1], d[1]):
        return False
    abba = c[0] + (d[0] - c[0]) * c[1] / (c[1] - d[1])
    return -CMP_EPSILON <= abba <= 1 + CMP_EPSILON


def _is_equal_approx(a: float, b: float) -> bool:
    if a == b:
        return True
    tolerance = max(CMP_EPSILON * abs(a), CMP_EPSILON)
    return abs(a - b) < tolerance


def closest_point_to_segment(p: Vec, a: Vec, b: Vec) -> Vec:
    """Geometry2D.get_closest_point_to_segment."""
    n = _sub(b, a)
    l2 = _dot(n, n)
    if l2 < 1e-20:
        return a
    t = _dot(_sub(p, a), n) / l2
    if t < 0.0:
        return a
    if t > 1.0:
        return b
    return _add(a, _mul(n, t))


def convex_hull(points: list[Vec]) -> list[Vec]:
    """Geometry2D.convex_hull (monotone chain), without the repeated closing point."""
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o: Vec, a: Vec, b: Vec) -> float:
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[Vec] = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: list[Vec] = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _area(contour: list[Vec]) -> float:
    n = len(contour)
    a = 0.0
    p = n - 1
    for q in range(n):
        a += contour[p][0] * contour[q][1] - contour[q][0] * contour[p][1]
        p = q
    return a * 0.5


def _inside_triangle(ax, ay, bx, by, cx, cy, px, py, include_edges: bool) -> bool:
    a = (cx - bx, cy - by)
    b = (ax - cx, ay - cy)
    c = (bx - ax, by - ay)
    ap = (px - ax, py - ay)
    bp = (px - bx, py - by)
    cp = (px - cx, py - cy)
    a_bp = a[0] * bp[1] - a[1] * bp[0]
    c_ap = c[0] * ap[1] - c[1] * ap[0]
    b_cp = b[0] * cp[1] - b[1] * cp[0]
    if include_edges:
        return a_bp > 0.0 and b_cp > 0.0 and c_ap > 0.0
    return a_bp >= 0.0 and b_cp >= 0.0 and c_ap >= 0.0


def _snip(contour: list[Vec], u: int, v: int, w: int, n: int, idx: list[int], relative: bool):
    ax, ay = contour[idx[u]]
    bx, by = contour[idx[v]]
    cx, cy = contour[idx[w]]
    threshold = -CMP_EPSILON if relative else 0.0
    if threshold > ((bx - ax) * (cy - ay)) - ((by - ay) * (cx - ax)):
        return False
    for p in range(n):
        if p in (u, v, w):
            continue
        px, py = contour[idx[p]]
        if _inside_triangle(ax, ay, bx, by, cx, cy, px, py, relative):
            return False
    return True


def triangulate(contour: list[Vec]) -> list[tuple[int, int, int]] | None:
    """Godot's ear clipping (Triangulate::triangulate): index triples, or None when it fails."""
    n = len(contour)
    if n < 3:
        return None
    idx = list(range(n)) if _area(contour) > 0.0 else [(n - 1) - v for v in range(n)]
    relative = False
    nv = n
    count = 2 * nv
    out: list[tuple[int, int, int]] = []
    v = nv - 1
    while nv > 2:
        if count <= 0:
            if relative:
                return None
            relative = True
            count = 2 * nv
        count -= 1
        u = v if v < nv else 0
        v = u + 1 if u + 1 < nv else 0
        w = v + 1 if v + 1 < nv else 0
        if _snip(contour, u, v, w, nv, idx, relative):
            out.append((idx[u], idx[v], idx[w]))
            del idx[v]
            nv -= 1
            count = 2 * nv
    return out


# -- the port ----------------------------------------------------------------------------------


def _direction_from(edge: RoadEdge, node_id: str) -> Vec:
    pl = edge.polyline
    if edge.from_node == node_id:
        a, b = pl[0], pl[1]
    else:
        a, b = pl[-1], pl[-2]
    d = (b[0] - a[0], b[2] - a[2])
    return _normalized(d) if _dot(d, d) > 0.0 else (1.0, 0.0)


def _end_point(edge: RoadEdge, node_id: str) -> Point:
    return edge.polyline[0] if edge.from_node == node_id else edge.polyline[-1]


def _point_at(pl: list[Point], distance: float) -> Point:
    """RoadGeometry.point_at."""
    remaining = distance
    for i in range(len(pl) - 1):
        seg = math.hypot(pl[i + 1][0] - pl[i][0], pl[i + 1][2] - pl[i][2])
        if remaining <= seg or i == len(pl) - 2:
            t = min(max(remaining / seg, 0.0), 1.0) if seg > 0.0 else 0.0
            a, b = pl[i], pl[i + 1]
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
        remaining -= seg
    return pl[-1]


def _height_along(edge: RoadEdge, node_id: str, distance: float) -> float:
    pl = edge.polyline if edge.from_node == node_id else list(reversed(edge.polyline))
    return _point_at(pl, distance)[1]


def build_all(graph: RoadGraph) -> dict[str, JunctionSurface]:
    """Every node with three or more roads, except forks and merges: node id -> surface."""
    out: dict[str, JunctionSurface] = {}
    inc = graph.incident()
    for nid in sorted(graph.nodes):
        eids = inc.get(nid, [])
        if len(eids) >= 3 and graph.nodes[nid].junction_type not in ("fork", "merge"):
            out[nid] = build_one(graph, nid, sorted(eids))
    return out


def _overlap(a: dict, b: dict) -> bool:
    wide = a if a["hw"] >= b["hw"] else b
    other = b if wide is a else a
    d = wide["dir"]
    lateral = abs(_dot(_sub(other["origin"], wide["origin"]), _normal(d)))
    return lateral < a["hw"] + b["hw"]


def _overlap_out(a: dict, b: dict) -> bool:
    wide = a if a["hw"] >= b["hw"] else b
    other = b if wide is a else a
    d = wide["dir"]
    out = 2.0 * wide["hw"] + TRIM_MARGIN_M
    p_wide = _add(wide["origin"], _mul(d, out))
    p_other = _add(other["origin"], _mul(other["dir"], out))
    lateral = abs(_dot(_sub(p_other, p_wide), _normal(d)))
    return lateral < a["hw"] + b["hw"]


def _widen_to_cover(keep: dict, other: dict) -> None:
    d = keep["dir"]
    n = _normal(d)
    o = keep["origin"]
    c = _dot(_sub(other["origin"], o), n)
    lo = min(-keep["hw"], c - other["hw"])
    hi = max(keep["hw"], c + other["hw"])
    keep["origin"] = _add(o, _mul(n, (lo + hi) * 0.5))
    keep["hw"] = (hi - lo) * 0.5


def build_one(graph: RoadGraph, node_id: str, eids: list[str]) -> JunctionSurface:
    """The junction at one node (JunctionBuilder.build_one); `eids` in the game's order."""
    node = graph.nodes[node_id]
    centre = (node.position[0], node.position[2])
    arms: list[dict] = []
    has_bridge = False
    has_tunnel = False
    for eid in eids:
        edge = graph.edges[eid]
        has_bridge = has_bridge or edge.bridge
        has_tunnel = has_tunnel or edge.tunnel
        d = _direction_from(edge, node_id)
        end = _end_point(edge, node_id)
        origin = (end[0], end[2])
        probe = _sub(_add(origin, _mul(d, SORT_PROBE_M)), centre)
        arms.append(
            {
                "edge": eid,
                "dir": d,
                "origin": origin,
                "angle": math.atan2(d[1], d[0]),
                "bearing": math.atan2(probe[1], probe[0]),
                "hw": edge.width_m * 0.5,
            }
        )
    arms.sort(key=lambda arm: arm["bearing"])
    merged_into: dict[str, str] = {}
    slot = 0
    while len(arms) > 1 and slot < len(arms):
        a = arms[slot]
        b = arms[(slot + 1) % len(arms)]
        gap = _fposmod(b["angle"] - a["angle"], TAU)
        if gap < math.radians(PARALLEL_ARMS_DEG) and len(arms) > 2 and _overlap(a, b):
            keep = a if a["hw"] >= b["hw"] else b
            drop = b if keep is a else a
            _widen_to_cover(keep, drop)
            merged_into[drop["edge"]] = keep["edge"]
            arms = [arm for arm in arms if arm is not drop]
            continue
        slot += 1
    count = len(arms)
    corners: list[Vec] = []
    corner_t: list[Vec] = []
    kinds: list[int] = []
    behind: list[tuple[int, int]] = []
    for i in range(count):
        a = arms[i]
        b = arms[(i + 1) % count]
        da, db = a["dir"], b["dir"]
        na, nb = _normal(da), _normal(db)
        pa = _add(a["origin"], _mul(na, a["hw"]))
        pb = _sub(b["origin"], _mul(nb, b["hw"]))
        hit = line_intersects_line(pa, da, pb, db)
        corner: Vec = (0.0, 0.0)
        ta = 0.0
        tb = 0.0
        widest = max(a["hw"], b["hw"])
        cap = min(MAX_CORNER_HALF_WIDTHS * widest, MAX_TRIM_M)
        if hit is not None:
            corner = hit
            ta = _dot(_sub(corner, pa), da)
            tb = _dot(_sub(corner, pb), db)
        gap = _fposmod(b["angle"] - a["angle"], TAU)
        kind = FILLET
        behind_a = 0
        behind_b = 0
        if gap < math.radians(SPLIT_ARMS_DEG) and count > 2 and _overlap_out(a, b):
            kind = PAIR
            corner = _mul(_add(pa, pb), 0.5)
            ta = 0.0
            tb = 0.0
        elif gap < math.radians(PARALLEL_ARMS_DEG) or gap > TAU - math.radians(PARALLEL_ARMS_DEG):
            kind = STRAIGHT
            corner = _mul(_add(pa, pb), 0.5)
            ta = 0.0
            tb = 0.0
        elif gap >= math.radians(STRAIGHT_GAP_DEG) and (
            hit is None or ta < 0.0 or tb < 0.0 or ta > cap or tb > cap
        ):
            kind = ALONG
            corner = _mul(_add(pa, pb), 0.5)
            if hit is not None and ta <= 0.0 and tb <= 0.0 and -ta < cap and -tb < cap:
                kind = SHARP
                corner = hit
            ta = 0.0
            tb = 0.0
        elif hit is not None and ta >= -cap and tb >= -cap and ta <= cap and tb <= cap:
            behind_a = 1 if ta < 0.0 else 0
            behind_b = 1 if tb < 0.0 else 0
            ta = max(ta, 0.0)
            tb = max(tb, 0.0)
        else:
            bisector = _rotated(da, gap * 0.5)
            corner = _add(_mul(_add(pa, pb), 0.5), _mul(bisector, min(cap, widest * 1.5)))
            ta = max(_dot(_sub(corner, pa), da), 0.0)
            tb = max(_dot(_sub(corner, pb), db), 0.0)
        corners.append(corner)
        corner_t.append((ta, tb))
        kinds.append(kind)
        behind.append((behind_a, behind_b))
    trims: dict[str, float] = {}
    for k in range(count):
        prev = (k - 1 + count) % count
        t = max(corner_t[k][0], corner_t[prev][1]) + TRIM_MARGIN_M
        trims[arms[k]["edge"]] = min(t, MAX_TRIM_M)
    for k in range(count):
        if kinds[k] == PAIR:
            e1 = arms[k]["edge"]
            e2 = arms[(k + 1) % count]["edge"]
            level = max(trims[e1], trims[e2])
            trims[e1] = level
            trims[e2] = level
    for dropped, kept in merged_into.items():
        while kept in merged_into:
            kept = merged_into[kept]
        trims[dropped] = trims[kept]
    polygon, heights = _walk(graph, node_id, arms, trims, corners, kinds, behind)
    if not _usable(polygon) and ALONG in kinds:
        plain = [STRAIGHT if k == ALONG else k for k in kinds]
        polygon, heights = _walk(graph, node_id, arms, trims, corners, plain, behind)
    arm_segments: list[tuple] = []
    for eid in eids:
        edge = graph.edges[eid]
        hw = edge.width_m * 0.5
        for a, b in zip(edge.polyline, edge.polyline[1:]):
            arm_segments.append((a[0], a[2], b[0], b[2], a[1], b[1], hw))
    j = JunctionSurface(
        node_id=node_id,
        centre=node.position,
        polygon=polygon,
        heights=heights,
        trims=trims,
        has_bridge_arm=has_bridge,
        has_tunnel_arm=has_tunnel,
        arm_segments=arm_segments,
    )
    if not _usable(polygon):
        hull = convex_hull(polygon)
        j.polygon = hull
        j.heights = [_hull_height(graph, node_id, arms, p) for p in hull]
        j.fallback_hull = True
    return j


def _cap(arm: dict, trims: dict, side: float) -> Vec:
    d = arm["dir"]
    return _add(
        _add(arm["origin"], _mul(d, trims[arm["edge"]])), _mul(_normal(d), arm["hw"] * side)
    )


def _walk(
    graph: RoadGraph,
    node_id: str,
    arms: list[dict],
    trims: dict,
    corners: list[Vec],
    kinds: list[int],
    behind: list[tuple[int, int]],
) -> tuple[list[Vec], list[float]]:
    count = len(arms)
    polygon: list[Vec] = []
    heights: list[float] = []
    for i in range(count):
        a = arms[i]
        d = a["dir"]
        n = _normal(d)
        t = trims[a["edge"]]
        edge = graph.edges[a["edge"]]
        h = _height_along(edge, node_id, t)
        o = a["origin"]
        cap_minus = _sub(_add(o, _mul(d, t)), _mul(n, a["hw"]))
        cap_plus = _add(_add(o, _mul(d, t)), _mul(n, a["hw"]))
        prev_arm = arms[(i - 1 + count) % count]
        next_arm = arms[(i + 1) % count]
        if kinds[(i - 1 + count) % count] == PAIR:
            other_plus = _cap(prev_arm, trims, 1.0)
            mean_prev = _normalized(_add(prev_arm["dir"], d))
            across = _normal(mean_prev)
            if _dot(other_plus, across) > _dot(cap_plus, across):
                cap_plus = other_plus
        else:
            if kinds[i] == PAIR:
                other_minus = _cap(next_arm, trims, -1.0)
                mean_next = _normalized(_add(d, next_arm["dir"]))
                across = _normal(mean_next)
                if _dot(other_minus, across) < _dot(cap_minus, across):
                    cap_minus = other_minus
            polygon.append(cap_minus)
            heights.append(h)
        if kinds[i] != PAIR:
            polygon.append(cap_plus)
            heights.append(h)
        b = arms[(i + 1) % count]
        next_edge = graph.edges[b["edge"]]
        t_next = trims[next_edge.id]
        h_next = _height_along(next_edge, node_id, t_next)
        db = b["dir"]
        nb = _normal(db)
        next_cap_minus = _sub(_add(b["origin"], _mul(db, t_next)), _mul(nb, b["hw"]))
        if kinds[i] in (STRAIGHT, PAIR):
            continue
        if kinds[i] == ALONG:
            end_a = _add(o, _mul(n, a["hw"]))
            end_b = _sub(b["origin"], _mul(nb, b["hw"]))
            h_end_a = _height_along(edge, node_id, 0.0)
            h_end_b = _height_along(next_edge, node_id, 0.0)
            if _dist(end_a, end_b) < ALONG_MERGE_M:
                polygon.append(_mul(_add(end_a, end_b), 0.5))
                heights.append((h_end_a + h_end_b) * 0.5)
            else:
                polygon.append(end_a)
                heights.append(h_end_a)
                polygon.append(end_b)
                heights.append(h_end_b)
            continue
        if kinds[i] == SHARP:
            polygon.append(corners[i])
            heights.append(_lerpf(h, h_next, 0.5))
            continue
        frm = cap_plus
        to = next_cap_minus
        h_from = h
        h_to = h_next
        if behind[i][0] == 1:
            frm = _add(o, _mul(n, a["hw"]))
            h_from = _height_along(edge, node_id, 0.0)
            polygon.append(frm)
            heights.append(h_from)
        if behind[i][1] == 1:
            to = _sub(b["origin"], _mul(nb, b["hw"]))
            h_to = _height_along(next_edge, node_id, 0.0)
        for k in range(1, FILLET_STEPS + 1):
            u = k / (FILLET_STEPS + 1)
            q = _lerp(_lerp(frm, corners[i], u), _lerp(corners[i], to, u), u)
            polygon.append(q)
            heights.append(_lerpf(h_from, h_to, u))
        if behind[i][1] == 1:
            polygon.append(to)
            heights.append(h_to)
    _dedupe(polygon, heights)
    return polygon, heights


def _dedupe(poly: list[Vec], heights: list[float]) -> None:
    i = len(poly) - 1
    while i >= 0 and len(poly) > 3:
        k_prev = (i - 1 + len(poly)) % len(poly)
        k_next = (i + 1) % len(poly)
        prev = poly[k_prev]
        nxt = poly[k_next]
        q = closest_point_to_segment(poly[i], prev, nxt)
        span = _dist(prev, nxt)
        t = _dist(prev, q) / span if span > 1e-6 else 0.0
        level = abs(heights[i] - _lerpf(heights[k_prev], heights[k_next], t)) < 0.01
        on_line = _dist(poly[i], q) < 0.01 and level
        if _dist(poly[i], prev) < 0.01 or on_line:
            del poly[i]
            del heights[i]
        i = min(i - 1, len(poly) - 1)


def _usable(polygon: list[Vec]) -> bool:
    return triangulate(polygon) is not None and _is_simple(polygon)


def _is_simple(poly: list[Vec]) -> bool:
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            c = poly[j]
            d = poly[(j + 1) % n]
            if segment_intersects_segment(a, b, c, d):
                return False
    return True


def _hull_height(graph: RoadGraph, node_id: str, arms: list[dict], p: Vec) -> float:
    node = graph.nodes[node_id]
    offset = (p[0] - node.position[0], p[1] - node.position[2])
    dist = _length(offset)
    if dist < 1e-3 or not arms:
        return node.position[1]
    direction = _mul(offset, 1.0 / dist)
    best = arms[0]
    best_dot = -math.inf
    for arm in arms:
        d = _dot(arm["dir"], direction)
        if d > best_dot:
            best_dot = d
            best = arm
    edge = graph.edges[best["edge"]]
    return _height_along(edge, node_id, dist * max(best_dot, 0.0))
