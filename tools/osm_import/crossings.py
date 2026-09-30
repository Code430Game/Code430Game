"""Infer missing bridges: two drivable edges that cross in 2D without sharing a
node cannot both be at grade. OSM sometimes omits bridge/layer tags on ramps.

Approach: find 2D crossings between edges of the same layer that share no node.
The DTM records the top structure, so at the crossing the edge whose end
heights are closer to the DTM height there is the one on top. Ties fall back
to road class priority. The upper edge is marked bridge with layer+1 and the
inference is recorded in defaulted_fields and the report.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from osm_import.elevation import _seg_intersect, _SegmentIndex
from osm_import.graph import RoadGraph

log = logging.getLogger(__name__)

CLASS_PRIORITY = [
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
    "secondary",
    "secondary_link",
    "tertiary",
    "tertiary_link",
    "unclassified",
    "residential",
    "living_street",
    "service",
]
TIE_M = 1.0


@dataclass
class InferredBridge:
    edge_id: str
    over_class: str
    under_edge_id: str
    under_class: str
    reason: str


@dataclass
class CrossingResult:
    inferred: list[InferredBridge] = field(default_factory=list)

    def to_list(self) -> list[dict]:
        return [vars(i) for i in self.inferred]


def infer_bridges(graph: RoadGraph, sample) -> CrossingResult:
    """Mark upper edges of untagged crossings as bridges. `sample(x, z)` gives DTM height."""
    result = CrossingResult()
    idx = _SegmentIndex()
    for eid in (
        graph.sorted_edge_ids() if hasattr(graph, "sorted_edge_ids") else sorted(graph.edges)
    ):
        e = graph.edges[eid]
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            idx.add((a[0], a[2]), (b[0], b[2]), (eid, i))
    seen: set[tuple[str, str]] = set()
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.bridge or e.tunnel:
            continue
        for i in range(len(e.polyline) - 1):
            a, b = e.polyline[i], e.polyline[i + 1]
            pa, pb = (a[0], a[2]), (b[0], b[2])
            mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
            radius = max(abs(pb[0] - pa[0]), abs(pb[1] - pa[1])) / 2 + 1.0
            for c, d, (oid, _j) in idx.near(mid[0], mid[1], radius):
                if oid == eid or (min(eid, oid), max(eid, oid)) in seen:
                    continue
                o = graph.edges[oid]
                if o.bridge or o.tunnel or o.layer != e.layer:
                    continue
                if {e.from_node, e.to_node} & {o.from_node, o.to_node}:
                    continue
                hit = _seg_intersect(pa, pb, c, d)
                if hit is None:
                    continue
                t, u = hit
                if t <= 1e-6 or t >= 1 - 1e-6 or u <= 1e-6 or u >= 1 - 1e-6:
                    continue  # touching at an endpoint is a shared point, not a crossing
                seen.add((min(eid, oid), max(eid, oid)))
                x, z = pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t
                dtm = sample(x, z)
                e_ends = (
                    sample(e.polyline[0][0], e.polyline[0][2])
                    + sample(e.polyline[-1][0], e.polyline[-1][2])
                ) / 2
                o_ends = (
                    sample(o.polyline[0][0], o.polyline[0][2])
                    + sample(o.polyline[-1][0], o.polyline[-1][2])
                ) / 2
                de, do = abs(dtm - e_ends), abs(dtm - o_ends)
                if abs(de - do) >= TIE_M:
                    over, under = (e, o) if de < do else (o, e)
                    reason = "dtm"
                else:
                    pe = (
                        CLASS_PRIORITY.index(e.road_class) if e.road_class in CLASS_PRIORITY else 99
                    )
                    po = (
                        CLASS_PRIORITY.index(o.road_class) if o.road_class in CLASS_PRIORITY else 99
                    )
                    over, under = (e, o) if pe <= po else (o, e)
                    reason = "class"
                over.bridge = True
                over.layer = under.layer + 1
                if "bridge" not in over.defaulted_fields:
                    over.defaulted_fields.append("bridge")
                result.inferred.append(
                    InferredBridge(over.id, over.road_class, under.id, under.road_class, reason)
                )
    log.info("crossings: %d bridges inferred", len(result.inferred))
    return result
