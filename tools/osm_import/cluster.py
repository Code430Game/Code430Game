"""Merge junction clusters so dual-carriageway crossings become one junction.

Approach: contract edges that connect two junction nodes (degree >= 3) and are
shorter than the largest cluster radius of the roads meeting at either end,
never across layers and never a bridge or tunnel edge. Union-find over those edges gives the clusters; the new
node sits at the centroid and internal edges are dropped.

A touching edge keeps its own straight line into the cluster: its end point moves
along its last segment to the point on that line nearest the centroid, so the two
carriageways of a divided road stay parallel and pass beside the centroid at their
real offset instead of bending to meet in an X. An end within the snap tolerance of
the centroid, or one whose projection would fold back past its previous vertex,
goes to the centroid as before. The node keeps the centroid as its position.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from osm_import.config import ImportConfig
from osm_import.graph import Point, RoadEdge, RoadGraph, RoadNode, polyline_length


@dataclass
class ClusterStats:
    clusters: int = 0
    nodes_merged: int = 0
    edges_removed: int = 0
    removed_edge_ids: list[str] = field(default_factory=list)
    # Largest distance from the centroid to a touching edge's end, per cluster node id.
    max_arm_offset_m: dict[str, float] = field(default_factory=dict)
    osm_node_ids: dict[str, list[int]] = field(default_factory=dict)

    def to_list(self) -> list[dict]:
        """Per-cluster entries for the validation report, largest arm offset first."""
        rows = [
            {
                "node_id": nid,
                "osm_node_ids": self.osm_node_ids[nid],
                "max_arm_offset_m": round(off, 3),
            }
            for nid, off in self.max_arm_offset_m.items()
        ]
        return sorted(rows, key=lambda r: (-r["max_arm_offset_m"], r["node_id"]))


class _UnionFind:
    def __init__(self) -> None:
        self.parent: dict[str, str] = {}

    def find(self, a: str) -> str:
        self.parent.setdefault(a, a)
        while self.parent[a] != a:
            self.parent[a] = self.parent[self.parent[a]]
            a = self.parent[a]
        return a

    def union(self, a: str, b: str) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            if ra < rb:
                self.parent[rb] = ra
            else:
                self.parent[ra] = rb


def _junction_radius(
    graph: RoadGraph, inc: dict[str, list[str]], e: RoadEdge, cfg: ImportConfig
) -> float:
    """Largest cluster radius among the roads meeting at either end of the edge.

    A residential street crossing a divided secondary road must contract at the
    secondary road's radius, not its own.
    """
    classes = {e.road_class}
    for nid in (e.from_node, e.to_node):
        classes.update(graph.edges[x].road_class for x in inc[nid])
    return max(cfg.for_class(c).cluster_radius_m for c in classes)


def _arm_end(end: Point, prev: Point, centroid: Point, snap_m: float) -> Point:
    """Where an edge ending at `end` (coming from `prev`) meets a cluster at `centroid`.

    The end slides along the line prev -> end to the point nearest the centroid. Ends
    already within snap_m of the centroid, degenerate last segments, and projections
    that would land on or behind prev all fall back to the centroid.
    """
    if math.hypot(end[0] - centroid[0], end[2] - centroid[2]) <= snap_m:
        return centroid
    dx, dz = end[0] - prev[0], end[2] - prev[2]
    seg = math.hypot(dx, dz)
    if seg < 1e-6:
        return centroid
    ux, uz = dx / seg, dz / seg
    t = (centroid[0] - prev[0]) * ux + (centroid[2] - prev[2]) * uz
    if t <= snap_m:
        return centroid
    return (prev[0] + ux * t, centroid[1], prev[2] + uz * t)


def _node_layers(graph: RoadGraph) -> dict[str, set[int]]:
    layers: dict[str, set[int]] = {nid: set() for nid in graph.nodes}
    for e in graph.edges.values():
        layers[e.from_node].add(e.layer)
        layers[e.to_node].add(e.layer)
    return layers


def cluster_junctions(graph: RoadGraph, cfg: ImportConfig) -> ClusterStats:
    """Contract short junction-to-junction edges in place."""
    stats = ClusterStats()
    inc = graph.incident()
    layers = _node_layers(graph)
    uf = _UnionFind()
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.from_node == e.to_node or e.bridge or e.tunnel:
            continue
        if len(inc[e.from_node]) < 3 or len(inc[e.to_node]) < 3:
            continue
        radius = _junction_radius(graph, inc, e, cfg)
        if e.length_m > radius:
            continue
        if not (layers[e.from_node] & layers[e.to_node]):
            continue
        uf.union(e.from_node, e.to_node)

    groups: dict[str, list[str]] = {}
    for nid in graph.nodes:
        if nid in uf.parent:
            groups.setdefault(uf.find(nid), []).append(nid)
    groups = {root: sorted(members) for root, members in groups.items() if len(members) > 1}
    if not groups:
        return stats

    remap: dict[str, str] = {}
    for members in groups.values():
        xs = [graph.nodes[m].position[0] for m in members]
        zs = [graph.nodes[m].position[2] for m in members]
        centroid: Point = (sum(xs) / len(xs), 0.0, sum(zs) / len(zs))
        new_id = "c" + min(members)[1:]
        osm_ids = sorted(i for m in members for i in graph.nodes[m].osm_node_ids)
        merged_tags: dict[str, str] = {}
        for m in members:
            merged_tags.update(graph.nodes[m].tags)
        for m in members:
            remap[m] = new_id
            del graph.nodes[m]
        graph.nodes[new_id] = RoadNode(new_id, centroid, osm_ids, merged_tags, "junction")
        stats.max_arm_offset_m[new_id] = 0.0
        stats.osm_node_ids[new_id] = osm_ids
        stats.clusters += 1
        stats.nodes_merged += len(members)

    snap_m = float(cfg.clusters["arm_snap_m"])

    def place_end(nid: str, end: Point, prev: Point) -> Point:
        centroid = graph.nodes[nid].position
        p = _arm_end(end, prev, centroid, snap_m)
        off = math.hypot(p[0] - centroid[0], p[2] - centroid[2])
        stats.max_arm_offset_m[nid] = max(stats.max_arm_offset_m[nid], off)
        return p

    for eid in sorted(graph.edges):
        e: RoadEdge = graph.edges[eid]
        a = remap.get(e.from_node, e.from_node)
        b = remap.get(e.to_node, e.to_node)
        if a == b and a in remap.values():
            radius = cfg.for_class(e.road_class).cluster_radius_m
            if e.length_m <= 2.0 * radius:
                # A stop or signal on the removed stub belongs to the cluster now.
                node = graph.nodes[a]
                for ctrl in (e.control_to, e.control_from):
                    if ctrl == "signals":
                        node.tags["highway"] = "traffic_signals"
                    elif ctrl == "stop" and node.tags.get("highway") != "traffic_signals":
                        node.tags["highway"] = "stop"
                del graph.edges[eid]
                stats.edges_removed += 1
                stats.removed_edge_ids.append(eid)
                continue
        # Both ends read the original polyline, so a short edge touching clusters at both
        # ends is projected from its real vertices, not from a moved end.
        orig = list(e.polyline)
        if a != e.from_node:
            e.from_node = a
            e.polyline[0] = place_end(a, orig[0], orig[1])
        if b != e.to_node:
            e.to_node = b
            e.polyline[-1] = place_end(b, orig[-1], orig[-2])
        e.length_m = polyline_length(e.polyline)

    from osm_import.graph import _classify_nodes

    _classify_nodes(graph)
    return stats
