"""Write road_graph.v0.json deterministically: sorted ids, fixed rounding, no clocks."""

from __future__ import annotations

import json
from pathlib import Path

from osm_import.graph import Point, RoadGraph
from osm_import.osm_data import BBox
from osm_import.projection import LocalFrame

SCHEMA_VERSION = 0
COORD_DECIMALS = 3
OSM_ATTRIBUTION = "© OpenStreetMap contributors"


def _pt(p: Point) -> list[float]:
    return [round(p[0], COORD_DECIMALS), round(p[1], COORD_DECIMALS), round(p[2], COORD_DECIMALS)]


def graph_to_dict(
    graph: RoadGraph,
    bbox: BBox,
    frame: LocalFrame,
    sources: list[dict],
    config_name: str,
    elevation: dict | None,
) -> dict:
    """Serializable representation of the graph."""
    nodes = []
    for nid in sorted(graph.nodes):
        n = graph.nodes[nid]
        nodes.append(
            {
                "id": n.id,
                "position": _pt(n.position),
                "ground_y": round(n.ground_y, COORD_DECIMALS),
                "osm_node_ids": n.osm_node_ids,
                "junction_type": n.junction_type,
                "control": n.control,
            }
        )
    edges = []
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        edges.append(
            {
                "id": e.id,
                "from": e.from_node,
                "to": e.to_node,
                "polyline": [_pt(p) for p in e.polyline],
                "class": e.road_class,
                "lanes_forward": e.lanes_forward,
                "lanes_backward": e.lanes_backward,
                "oneway": e.oneway,
                "speed_kph": e.speed_kph,
                "width_m": round(e.width_m, 2),
                "layer": e.layer,
                "bridge": e.bridge,
                "tunnel": e.tunnel,
                "name": e.name,
                "osm_way_id": e.osm_way_id,
                "defaulted_fields": sorted(e.defaulted_fields),
                "access": e.access,
                "length_m": round(e.length_m, COORD_DECIMALS),
                "control_to": e.control_to,
                "control_from": e.control_from,
                "bus": e.bus,
                "bus_lane": e.bus_lane,
                "shoulder_left_m": round(e.shoulder_left_m, 2),
                "shoulder_right_m": round(e.shoulder_right_m, 2),
            }
        )
    pedestrian = pedestrian_to_list(graph)
    return {
        "meta": {
            "schema_version": SCHEMA_VERSION,
            "generator": "code430 osm_import",
            "config": config_name,
            "units": "metres, x east, y up, z south",
            "origin": frame.to_dict(),
            "bbox": bbox.as_list(),
            "elevation": elevation,
            "sources": sources,
            "attribution": [OSM_ATTRIBUTION],
            "license": "ODbL-1.0",
            "notes": graph.notes,
        },
        "nodes": nodes,
        "edges": edges,
        "pedestrian_ways": pedestrian,
        "bus_stops": [
            {"id": s["id"], "position": _pt(s["position"]), "edge": s["edge"]}
            for s in graph.bus_stops
        ],
        "gores": [
            {
                "id": g.source,
                "points": [_pt(p) for p in g.points],
                "half_m": [round(h, 3) for h in g.left_m],
            }
            for g in graph.gores
        ],
    }


def pedestrian_to_list(graph: RoadGraph) -> list[dict]:
    """Serializable pedestrian ways; called again after the terrain stage adjusts them."""
    return [
        {
            "id": p.id,
            "polyline": [_pt(q) for q in p.polyline],
            "class": p.road_class,
            "kind": p.kind,
            "width_m": round(p.width_m, 2),
            "covered": p.covered,
            "osm_way_id": p.osm_way_id,
            "name": p.name,
            **({"profile": p.profile} if p.profile else {}),
            **({"top": [round(t, 2) for t in p.top]} if p.top else {}),
        }
        for p in sorted(graph.pedestrian, key=lambda p: (p.osm_way_id, p.id))
    ]


def dump_json(data: dict, path: Path) -> None:
    """Write JSON with stable formatting and a trailing newline."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, indent=1, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8"
    )
