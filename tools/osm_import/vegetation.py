"""Trees, bushes and green areas (add-vegetation 1.1).

Sources, from their own Overpass query:
- `natural=tree` nodes: one tree each, at its mapped spot (source `tagged`).
- `natural=tree_row` ways: a tree every `row_spacing_m` (source `row`).
- `natural=wood`, `landuse=forest`, `leisure=park|garden`, `landuse=grass` polygons: a seeded
  Poisson-disc scatter at the land use's spacing (source `scatter`); parks and gardens also
  get bushes along their edge, `natural=scrub` is all bushes.
- Residential frontages: a bush every `frontage_spacing_m` just outside house and apartment
  walls where there is room.

Everything keeps clear of road ribbons, sidewalks, buildings and water by a margin. Heights
come from the built terrain. Each tree carries an archetype (broadleaf, columnar, conifer;
bushes: bush_round, bush_low), a height, a crown radius and a seed. Within each 256 m chunk
trees are written tagged first, then rows, then scatter by seed, so a per-preset cap in the
game drops scatter before any mapped street tree. Same input, same output.
"""

from __future__ import annotations

import logging
import math
import random
from dataclasses import dataclass, field

from shapely import STRtree, make_valid
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.prepared import prep

from osm_import.buildings import BuildingsResult
from osm_import.graph import RoadGraph
from osm_import.osm_data import BBox
from osm_import.projection import Projector
from osm_import.water import (
    WaterResult,
    _polygons_from_rings,
    _to_local,
    _triangulate,
    assemble_rings,
)

log = logging.getLogger(__name__)

CHUNK_SIZE_M = 256.0
DEFAULTS = {
    "row_spacing_m": 8.0,
    "spacing_m": {"wood": 6.0, "park": 14.0, "garden": 10.0, "grass": 25.0, "scrub": 4.0},
    "park_edge_bush_m": 8.0,
    "park_edge_inset_m": 2.0,
    "frontage_spacing_m": 6.0,
    "frontage_offset_m": 1.6,
    "road_margin_m": 2.0,
    "walk_margin_m": 1.0,
    "building_margin_m": 1.0,
    "conifer_share_wood": 0.3,
    "frontage_kinds": [
        "house",
        "residential",
        "apartments",
        "detached",
        "semidetached_house",
        "terrace",
    ],
}
GENUS = {
    "acer": "broadleaf",
    "quercus": "broadleaf",
    "tilia": "broadleaf",
    "ulmus": "broadleaf",
    "gleditsia": "broadleaf",
    "celtis": "broadleaf",
    "populus": "columnar",
    "fraxinus": "columnar",
    "carpinus": "columnar",
    "picea": "conifer",
    "pinus": "conifer",
    "thuja": "conifer",
    "abies": "conifer",
    "larix": "conifer",
}
HEIGHTS = {
    "broadleaf": (7.0, 14.0),
    "columnar": (10.0, 18.0),
    "conifer": (8.0, 16.0),
    "bush_round": (0.8, 1.6),
    "bush_low": (0.5, 0.9),
}
CROWN = {"broadleaf": 0.35, "columnar": 0.2, "conifer": 0.22, "bush_round": 0.6, "bush_low": 0.9}
SOURCE_ORDER = {"tagged": 0, "row": 1, "frontage": 2, "edge": 2, "scatter": 3}


def vegetation_query(bbox: BBox) -> str:
    b = bbox.overpass()
    return (
        "[out:json][timeout:180];("
        f'node["natural"="tree"]({b});'
        f'way["natural"="tree_row"]({b});'
        f'way["natural"~"^(wood|scrub)$"]({b});relation["natural"~"^(wood|scrub)$"]({b});'
        f'way["landuse"~"^(forest|grass)$"]({b});relation["landuse"~"^(forest|grass)$"]({b});'
        f'way["leisure"~"^(park|garden)$"]({b});relation["leisure"~"^(park|garden)$"]({b});'
        ");out body geom;"
    )


@dataclass
class Plant:
    x: float
    y: float
    z: float
    archetype: str
    height: float
    crown: float
    seed: int
    source: str

    def to_list(self) -> list:
        # Compact rows: [x, y, z, archetype, height, crown, seed, source]
        return [
            round(self.x, 2),
            round(self.y, 2),
            round(self.z, 2),
            self.archetype,
            round(self.height, 2),
            round(self.crown, 2),
            self.seed,
            self.source,
        ]


@dataclass
class GreenArea:
    id: str
    kind: str  # park | garden | grass | wood | scrub
    name: str | None
    vertices: list[tuple[float, float]]
    triangles: list[int]


@dataclass
class VegetationResult:
    trees: list[Plant] = field(default_factory=list)
    bushes: list[Plant] = field(default_factory=list)
    areas: list[GreenArea] = field(default_factory=list)
    skipped: dict = field(default_factory=dict)

    def counts(self) -> dict:
        by_source: dict[str, int] = {}
        for t in self.trees:
            by_source[t.source] = by_source.get(t.source, 0) + 1
        per_chunk: dict[tuple[int, int], int] = {}
        for t in self.trees:
            k = (math.floor(t.x / CHUNK_SIZE_M), math.floor(t.z / CHUNK_SIZE_M))
            per_chunk[k] = per_chunk.get(k, 0) + 1
        return {
            "trees": len(self.trees),
            "bushes": len(self.bushes),
            "areas": len(self.areas),
            "trees_by_source": dict(sorted(by_source.items())),
            "max_trees_in_a_chunk": max(per_chunk.values(), default=0),
            "chunks_over_400_trees": sum(1 for v in per_chunk.values() if v > 400),
            "skipped": dict(sorted(self.skipped.items())),
        }

    def to_dict(self) -> dict:
        return {
            "schema_version": 0,
            "units": "metres, x east, z south; y is the ground under the plant",
            "columns": ["x", "y", "z", "archetype", "height", "crown", "seed", "source"],
            "trees": [t.to_list() for t in self.trees],
            "bushes": [b.to_list() for b in self.bushes],
            "areas": [
                {
                    "id": a.id,
                    "kind": a.kind,
                    "name": a.name,
                    "vertices": [[round(x, 2), round(z, 2)] for x, z in a.vertices],
                    "triangles": a.triangles,
                }
                for a in self.areas
            ],
        }


def _area_kind(tags: dict) -> str | None:
    if tags.get("natural") == "wood" or tags.get("landuse") == "forest":
        return "wood"
    if tags.get("natural") == "scrub":
        return "scrub"
    if tags.get("leisure") == "park":
        return "park"
    if tags.get("leisure") == "garden":
        return "garden"
    if tags.get("landuse") == "grass":
        return "grass"
    return None


def _archetype(tags: dict, rng: random.Random) -> str:
    if tags.get("leaf_type") == "needleleaved":
        return "conifer"
    for key in ("genus", "species", "taxon"):
        v = tags.get(key, "").strip().lower()
        if v:
            g = GENUS.get(v.split()[0])
            if g:
                return g
    return "broadleaf"


def _size(archetype: str, tags: dict, rng: random.Random) -> tuple[float, float]:
    lo, hi = HEIGHTS[archetype]
    h = rng.uniform(lo, hi)
    try:
        if tags.get("height"):
            h = float(str(tags["height"]).split()[0])
    except ValueError:
        pass
    crown = h * CROWN[archetype]
    try:
        if tags.get("diameter_crown"):
            crown = float(str(tags["diameter_crown"]).split()[0]) * 0.5
    except ValueError:
        pass
    return h, crown


class _Exclusion:
    """Where nothing may grow. `hard`: the road surface itself, buildings and water (a mapped
    street tree stands in the sidewalk strip, so mapped trees are only kept off these).
    `soft`: those grown by their margins, plus the sidewalks, for scattered planting."""

    def __init__(
        self,
        graph: RoadGraph,
        buildings: BuildingsResult | None,
        water: WaterResult | None,
        rules: dict,
    ) -> None:
        hard, soft = [], []
        for e in graph.edges.values():
            if e.tunnel or len(e.polyline) < 2:
                continue
            line = LineString([(p[0], p[2]) for p in e.polyline])
            hard.append(line.buffer(e.width_m / 2.0, 4))
            soft.append(line.buffer(e.width_m / 2.0 + rules["road_margin_m"], 4))
        for w in graph.pedestrian:
            if len(w.polyline) < 2 or w.covered:
                continue
            soft.append(
                LineString([(p[0], p[2]) for p in w.polyline]).buffer(
                    w.width_m / 2.0 + rules["walk_margin_m"], 4
                )
            )
        self.buildings = []
        if buildings is not None:
            for b in buildings.buildings:
                if b.rings and len(b.rings[0]) >= 3:
                    p = Polygon(b.rings[0])
                    p = p if p.is_valid else p.buffer(0)
                    self.buildings.append((b, p))
                    hard.append(p)
                    soft.append(p.buffer(rules["building_margin_m"], 2))
        if water is not None:
            for wp in water.polygons:
                if len(wp.vertices) >= 3:
                    p = Polygon(wp.vertices)
                    p = p if p.is_valid else p.buffer(0)
                    hard.append(p)
                    soft.append(p)
        self.hard, self.soft = hard, soft
        self.hard_tree, self.soft_tree = STRtree(hard), STRtree(soft)

    def blocked(self, x: float, z: float, strict: bool = True) -> bool:
        pt = Point(x, z)
        geoms, tree = (self.soft, self.soft_tree) if strict else (self.hard, self.hard_tree)
        return any(geoms[i].contains(pt) for i in tree.query(pt))


def _poisson(
    poly: Polygon, spacing: float, seed: int, limit: int = 20000
) -> list[tuple[float, float]]:
    """Bridson's Poisson-disc sampling inside `poly`, seeded."""
    rng = random.Random(seed)
    minx, minz, maxx, maxz = poly.bounds
    cell = spacing / math.sqrt(2.0)
    grid: dict[tuple[int, int], tuple[float, float]] = {}
    inside = prep(poly)
    pts: list[tuple[float, float]] = []
    active: list[tuple[float, float]] = []

    def key(p):
        return (int((p[0] - minx) // cell), int((p[1] - minz) // cell))

    def fits(p):
        kx, kz = key(p)
        for dx in range(-2, 3):
            for dz in range(-2, 3):
                q = grid.get((kx + dx, kz + dz))
                if q is not None and math.dist(p, q) < spacing:
                    return False
        return True

    for _ in range(30):  # a start point inside
        p = (rng.uniform(minx, maxx), rng.uniform(minz, maxz))
        if inside.contains(Point(p)):
            pts.append(p)
            active.append(p)
            grid[key(p)] = p
            break
    while active and len(pts) < limit:
        i = rng.randrange(len(active))
        base = active[i]
        placed = False
        for _ in range(20):
            a = rng.uniform(0.0, math.tau)
            r = rng.uniform(spacing, 2.0 * spacing)
            p = (base[0] + math.cos(a) * r, base[1] + math.sin(a) * r)
            if (
                minx <= p[0] <= maxx
                and minz <= p[1] <= maxz
                and fits(p)
                and inside.contains(Point(p))
            ):
                pts.append(p)
                active.append(p)
                grid[key(p)] = p
                placed = True
                break
        if not placed:
            active.pop(i)
    return pts


def _along(line_coords, spacing: float) -> list[tuple[float, float]]:
    line = LineString(line_coords)
    if line.length <= 0:
        return []
    n = max(1, int(line.length // spacing))
    return [
        (
            line.interpolate(line.length * (k + 0.5) / n).x,
            line.interpolate(line.length * (k + 0.5) / n).y,
        )
        for k in range(n)
    ]


def build_vegetation(
    payload: dict,
    bbox: BBox,
    proj: Projector,
    graph: RoadGraph,
    buildings: BuildingsResult | None,
    water: WaterResult | None,
    ground,  # sample(x, z)
    rules: dict | None = None,
) -> VegetationResult:
    cfg = dict(DEFAULTS)
    cfg.update(rules or {})
    res = VegetationResult()
    clip = box(*proj.bbox_local(bbox))
    excl = _Exclusion(graph, buildings, water, cfg)

    def skip(reason: str) -> None:
        res.skipped[reason] = res.skipped.get(reason, 0) + 1

    def add(into: list, x: float, z: float, arche: str, tags: dict, seed: int, source: str) -> None:
        if not clip.contains(Point(x, z)):
            skip("outside the district")
            return
        if excl.blocked(x, z, strict=source not in ("tagged", "row")):
            skip(f"{source} on a road, sidewalk, building or water")
            return
        rng = random.Random(seed)
        h, crown = _size(arche, tags, rng)
        into.append(Plant(x, ground.sample(x, z), z, arche, h, crown, seed, source))

    for el in payload.get("elements", []):
        tags = el.get("tags", {})
        if el["type"] == "node" and tags.get("natural") == "tree":
            x, z = proj.to_local(el["lat"], el["lon"])
            rng = random.Random(el["id"])
            add(res.trees, x, z, _archetype(tags, rng), tags, el["id"], "tagged")
        elif el["type"] == "way" and tags.get("natural") == "tree_row":
            coords = _to_local([(g["lat"], g["lon"]) for g in el.get("geometry", [])], proj)
            arche = _archetype(tags, random.Random(el["id"]))
            for k, (x, z) in enumerate(_along(coords, cfg["row_spacing_m"])):
                add(res.trees, x, z, arche, tags, el["id"] * 1000 + k, "row")
    # Areas.
    for el in sorted(payload.get("elements", []), key=lambda e: (e["type"], e["id"])):
        tags = el.get("tags", {})
        kind = _area_kind(tags)
        if kind is None or el["type"] == "node" or tags.get("natural") == "tree_row":
            continue
        if el["type"] == "way":
            geom = [(g["lat"], g["lon"]) for g in el.get("geometry", [])]
            if len(geom) < 4 or geom[0] != geom[-1]:
                skip("area not a closed ring")
                continue
            outers, inners = [geom], []
        else:
            outers, inners, _unclosed = assemble_rings(el.get("members", []))
            if not outers:
                skip("area relation without an outer ring")
                continue
        polys = _polygons_from_rings(
            [_to_local(r, proj) for r in outers], [_to_local(r, proj) for r in inners]
        )
        for n, poly in enumerate(polys):
            g = make_valid(poly).intersection(clip)
            parts = (
                [g]
                if isinstance(g, Polygon)
                else [p for p in getattr(g, "geoms", []) if isinstance(p, Polygon)]
            )
            for m, part in enumerate(parts):
                if part.area < 30.0:
                    continue
                aid = f"{el['type'][0]}{el['id']}.{n}.{m}"
                verts, tris = _triangulate(part)
                res.areas.append(GreenArea(aid, kind, tags.get("name"), verts, tris))
                seed = el["id"] * 31 + n * 7 + m
                spacing = cfg["spacing_m"][kind]
                for k, (x, z) in enumerate(_poisson(part, spacing, seed)):
                    s = seed * 100003 + k
                    if kind == "scrub":
                        add(
                            res.bushes,
                            x,
                            z,
                            "bush_round" if s % 3 else "bush_low",
                            {},
                            s,
                            "scatter",
                        )
                    else:
                        conifer = (
                            kind == "wood" and random.Random(s).random() < cfg["conifer_share_wood"]
                        )
                        add(
                            res.trees, x, z, "conifer" if conifer else "broadleaf", {}, s, "scatter"
                        )
                if kind in ("park", "garden"):
                    inset = part.buffer(-cfg["park_edge_inset_m"])
                    rings = (
                        [inset] if isinstance(inset, Polygon) else list(getattr(inset, "geoms", []))
                    )
                    for ring_poly in rings:
                        if ring_poly.is_empty:
                            continue
                        for k, (x, z) in enumerate(
                            _along(list(ring_poly.exterior.coords), cfg["park_edge_bush_m"])
                        ):
                            s = seed * 7919 + k
                            add(res.bushes, x, z, "bush_round", {}, s, "edge")
    # Frontage bushes outside house and apartment walls.
    for b, poly in excl.buildings:
        if b.kind not in cfg["frontage_kinds"]:
            continue
        ring = poly.buffer(cfg["frontage_offset_m"] + cfg["building_margin_m"], 2)
        if isinstance(ring, MultiPolygon) or ring.is_empty:
            continue
        for k, (x, z) in enumerate(_along(list(ring.exterior.coords), cfg["frontage_spacing_m"])):
            add(
                res.bushes,
                x,
                z,
                "bush_low" if k % 2 else "bush_round",
                {},
                (b.osm_id * 131 + k) & 0x7FFFFFFF,
                "frontage",
            )

    def order(p: Plant):
        return (
            math.floor(p.x / CHUNK_SIZE_M),
            math.floor(p.z / CHUNK_SIZE_M),
            SOURCE_ORDER[p.source],
            p.seed,
        )

    res.trees.sort(key=order)
    res.bushes.sort(key=order)
    res.areas.sort(key=lambda a: a.id)
    log.info("vegetation: %s", res.counts())
    return res
