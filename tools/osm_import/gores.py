"""Paved gores (add-road-shoulders 1.4).

Where a ramp leaves a motorway (or joins it), the two ribbons run side by side the same way
with a wedge of ground between them that widens from nothing at the fork. Real motorways pave
that wedge up to where it opens out. A gore here is a strip down the middle of the gap between
two ground carriageways of `gore_classes` running the same way, from just past the fork until
the gap passes `infill_max_m` (the same tunables as the deck infill in `bridges.py`), at the
mean of their heights. The terrain is flattened under gores like under roads, and the game
draws them as asphalt with the road surface. Opposing carriageways across a median are never
paired. Runs after `trim_shoulders`, on the final ribbons.
"""

from __future__ import annotations

import itertools
import logging

from osm_import.bridges import DEFAULTS as BRIDGE_DEFAULTS
from osm_import.bridges import DeckStrip, _infill, _samples
from osm_import.config import ImportConfig
from osm_import.elevation import _SegmentIndex
from osm_import.graph import RoadGraph

log = logging.getLogger(__name__)

DEFAULT_CLASSES = ("motorway", "trunk", "motorway_link", "trunk_link")


def build_gores(graph: RoadGraph, cfg: ImportConfig) -> list[DeckStrip]:
    """Gore strips between same-way ground carriageways of `gore_classes`; sets graph.gores."""
    rules = dict(BRIDGE_DEFAULTS)
    rules.update(cfg.bridges)
    classes = set(cfg.shoulders.get("gore_classes", DEFAULT_CLASSES))
    ribbons: dict[str, DeckStrip] = {}
    for eid in sorted(graph.edges):
        e = graph.edges[eid]
        if e.bridge or e.tunnel or e.road_class not in classes or len(e.polyline) < 2:
            continue
        hw = e.width_m / 2.0
        ribbons[eid] = DeckStrip(
            eid, list(e.polyline), [hw] * len(e.polyline), [hw] * len(e.polyline)
        )
    index = _SegmentIndex()
    for eid, r in ribbons.items():
        for a, b in itertools.pairwise(r.points):
            index.add((a[0], a[2]), (b[0], b[2]), eid)
    widest = max((r.left_m[0] for r in ribbons.values()), default=0.0)
    pairs: set[tuple[str, str]] = set()
    for eid, r in ribbons.items():
        for x, _y, z, _dx, _dz, _s in _samples(r.points, 8.0):
            for _a, _b, oid in index.near(x, z, rules["infill_max_m"] + 2.0 * widest):
                if oid != eid:
                    pairs.add((min(eid, oid), max(eid, oid)))
    out: list[DeckStrip] = []
    for a_id, b_id in sorted(pairs):
        a, b = ribbons[a_id], ribbons[b_id]
        if graph.edges[a_id].length_m < graph.edges[b_id].length_m:
            a, b = b, a
        out.extend(_infill(a, b, rules, same_direction=True, prefix="gore:"))
    graph.gores = out
    log.info("gores: %d paved between ramps and their roads", len(out))
    return out
