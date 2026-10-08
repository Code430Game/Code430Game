"""In-memory model of an OSM extract (Overpass JSON format) and bbox cropping."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class BBox:
    """WGS84 bounding box: south, west, north, east."""

    south: float
    west: float
    north: float
    east: float

    @classmethod
    def parse(cls, text: str) -> BBox:
        """Parse 'S,W,N,E'."""
        parts = [float(p) for p in text.split(",")]
        if len(parts) != 4:
            raise ValueError(f"bbox must be S,W,N,E, got {text!r}")
        s, w, n, e = parts
        if not (s < n and w < e):
            raise ValueError(f"bbox must have south<north and west<east, got {text!r}")
        return cls(s, w, n, e)

    def contains(self, lat: float, lon: float) -> bool:
        return self.south <= lat <= self.north and self.west <= lon <= self.east

    def as_list(self) -> list[float]:
        return [self.south, self.west, self.north, self.east]

    def overpass(self) -> str:
        return f"{self.south},{self.west},{self.north},{self.east}"

    @property
    def center(self) -> tuple[float, float]:
        return ((self.south + self.north) / 2.0, (self.west + self.east) / 2.0)


@dataclass
class OsmNode:
    id: int
    lat: float
    lon: float
    tags: dict[str, str] = field(default_factory=dict)


@dataclass
class OsmWay:
    id: int
    nodes: list[int]
    tags: dict[str, str] = field(default_factory=dict)


@dataclass
class OsmData:
    nodes: dict[int, OsmNode]
    ways: dict[int, OsmWay]
    source: dict = field(default_factory=dict)

    @classmethod
    def from_overpass_json(cls, payload: dict, source: dict | None = None) -> OsmData:
        nodes: dict[int, OsmNode] = {}
        ways: dict[int, OsmWay] = {}
        for el in payload.get("elements", []):
            if el["type"] == "node":
                nodes[el["id"]] = OsmNode(el["id"], el["lat"], el["lon"], el.get("tags", {}))
            elif el["type"] == "way":
                ways[el["id"]] = OsmWay(el["id"], list(el["nodes"]), el.get("tags", {}))
        src = dict(source or {})
        osm3s = payload.get("osm3s", {})
        if "timestamp_osm_base" in osm3s:
            src.setdefault("osm_base_timestamp", osm3s["timestamp_osm_base"])
        if "generator" in payload:
            src.setdefault("generator", payload["generator"])
        return cls(nodes, ways, src)

    @classmethod
    def load(cls, path: Path, source: dict | None = None) -> OsmData:
        payload = json.loads(path.read_text(encoding="utf-8"))
        # The file's name, not its absolute path: a committed pack must regenerate byte for
        # byte on any machine (the proving ground's check compares the files).
        src = {"kind": "file", "path": path.name}
        src.update(source or {})
        return cls.from_overpass_json(payload, src)

    def crop(self, bbox: BBox) -> OsmData:
        """Keep ways with at least one node inside bbox, plus all their nodes."""
        ways = {
            wid: w
            for wid, w in self.ways.items()
            if any(
                n in self.nodes and bbox.contains(self.nodes[n].lat, self.nodes[n].lon)
                for n in w.nodes
            )
        }
        needed = {n for w in ways.values() for n in w.nodes}
        nodes = {nid: self.nodes[nid] for nid in needed if nid in self.nodes}
        src = dict(self.source)
        src["cropped_to_bbox"] = bbox.as_list()
        return OsmData(nodes, ways, src)

    def to_overpass_json(self) -> dict:
        """Serialize back to Overpass JSON (sorted, for committed fixtures)."""
        elements: list[dict] = []
        for nid in sorted(self.nodes):
            n = self.nodes[nid]
            el: dict = {"type": "node", "id": n.id, "lat": n.lat, "lon": n.lon}
            if n.tags:
                el["tags"] = dict(sorted(n.tags.items()))
            elements.append(el)
        for wid in sorted(self.ways):
            w = self.ways[wid]
            el = {"type": "way", "id": w.id, "nodes": list(w.nodes)}
            if w.tags:
                el["tags"] = dict(sorted(w.tags.items()))
            elements.append(el)
        out: dict = {"version": 0.6, "generator": "code430 osm_import crop", "elements": elements}
        if "osm_base_timestamp" in self.source:
            out["osm3s"] = {"timestamp_osm_base": self.source["osm_base_timestamp"]}
        out["code430_source"] = dict(sorted(self.source.items()))
        return out
