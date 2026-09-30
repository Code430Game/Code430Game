"""Helpers to build tiny synthetic OSM extracts in metres around a base point."""

from __future__ import annotations

import math

from osm_import.osm_data import BBox, OsmData, OsmNode, OsmWay

BASE_LAT = 45.41
BASE_LON = -75.69
BBOX = BBox(
    BASE_LAT - 0.004, BASE_LON - 0.006, BASE_LAT + 0.004, BASE_LON + 0.006
)  # roughly 900 m x 900 m
M_PER_DEG_LAT = 111320.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(BASE_LAT))


def ll(x_m: float, z_m: float) -> tuple[float, float]:
    """Local metres (x east, z south) -> (lat, lon)."""
    return BASE_LAT - z_m / M_PER_DEG_LAT, BASE_LON + x_m / M_PER_DEG_LON


def make_data(
    ways: list[tuple[int, list[tuple[float, float]], dict[str, str]]],
    node_tags: dict[int, dict[str, str]] | None = None,
) -> OsmData:
    """Build OsmData from (way_id, [(x_m, z_m), ...], tags). Equal points share a node."""
    node_ids: dict[tuple[float, float], int] = {}
    nodes: dict[int, OsmNode] = {}
    osm_ways: dict[int, OsmWay] = {}
    for wid, points, tags in ways:
        ids: list[int] = []
        for p in points:
            key = (round(p[0], 3), round(p[1], 3))
            if key not in node_ids:
                nid = 1000 + len(node_ids)
                node_ids[key] = nid
                lat, lon = ll(*key)
                nodes[nid] = OsmNode(nid, lat, lon, {})
            ids.append(node_ids[key])
        osm_ways[wid] = OsmWay(wid, ids, dict(tags))
    for nid, tags in (node_tags or {}).items():
        nodes[nid].tags.update(tags)
    return OsmData(nodes, osm_ways, {"kind": "synthetic"})
