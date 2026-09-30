"""Split OSM ways into drivable roads and pedestrian ways; drop the rest."""

from __future__ import annotations

from dataclasses import dataclass, field

from osm_import.config import ImportConfig
from osm_import.osm_data import OsmData, OsmWay


@dataclass
class FilterResult:
    drivable: list[OsmWay]
    pedestrian: list[OsmWay]
    dropped: dict[str, int] = field(default_factory=dict)
    dropped_ways: list[tuple[OsmWay, str]] = field(default_factory=list)

    def dropped_by_node(self) -> dict[int, list[tuple[int, str]]]:
        """OSM node id -> [(dropped way id, reason)] for explaining islands."""
        out: dict[int, list[tuple[int, str]]] = {}
        for way, reason in self.dropped_ways:
            for nid in way.nodes:
                out.setdefault(nid, []).append((way.id, reason))
        return out


def _drop(result: FilterResult, reason: str, way: OsmWay | None = None) -> None:
    result.dropped[reason] = result.dropped.get(reason, 0) + 1
    if way is not None:
        result.dropped_ways.append((way, reason))


def filter_ways(data: OsmData, cfg: ImportConfig) -> FilterResult:
    """Classify every way. Ways with fewer than two known nodes are dropped."""
    result = FilterResult([], [])
    for wid in sorted(data.ways):
        way = data.ways[wid]
        tags = way.tags
        highway = tags.get("highway")
        known_nodes = [n for n in way.nodes if n in data.nodes]
        if len(known_nodes) < 2:
            _drop(result, "too_few_nodes")
            continue
        if highway is None or highway in cfg.excluded_highway_values:
            _drop(result, f"highway={highway}")
            continue
        if tags.get("area") == "yes":
            _drop(result, "area=yes")
            continue
        if highway in cfg.drivable_classes:
            if highway == "service" and tags.get("service") in cfg.excluded_service_values:
                _drop(result, f"service={tags.get('service')}", way)
                continue
            access = tags.get("motor_vehicle", tags.get("access"))
            if access in cfg.excluded_access_values:
                _drop(result, f"access={access}", way)
                continue
            result.drivable.append(way)
        elif highway in cfg.pedestrian_classes:
            result.pedestrian.append(way)
        else:
            _drop(result, f"highway={highway}")
    return result
