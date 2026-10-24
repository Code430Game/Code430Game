"""Replay the importer's road passes on a captured district in seconds, and measure the result.

A district export takes about four minutes, almost all of it fetching, carving and building
everything but the terrain's road passes. Tuning those passes (update-junction-ground,
add-retaining-walls) needs many runs, so:

    uv run python terrain_replay.py capture <region.json> <out dir>
        Exports the district once with the road passes stubbed out and pickles what they need
        (the carved chunks, the graph after pedestrian heights, the bridges) next to the pack.
    uv run python terrain_replay.py replay <out dir>/<district>.pkl [label]
        Runs flatten, the sidewalk lift and cut, the under-deck lowering, the bed restore and
        the retaining walls (the scan and the hold in front of them, add-retaining-walls) with
        the importer as it stands now, then measures wheel traps (a port of the game's
        EdgeDropReport) and junctions with terrain through their drawn surface (a port of
        JunctionReport.terrain_above), says which pass last moved each trap's lowest cell, and
        counts the walls' metres.

On Centretown (2026-10-23) a replay took 25 s and its two counts were within three of the
game's own reports on the same terrain. The capture builds the bridges from the carved, not
the flattened, terrain, so walkway lifts and pier feet can differ a little from a real export:
confirm a kept variant with scripts/terrain-trial.sh before releasing it.
"""

from __future__ import annotations

import collections
import copy
import math
import pickle
import sys
import time
from itertools import pairwise
from pathlib import Path

from osm_import import junctions as J
from osm_import import pack
from osm_import import walls as W
from osm_import.config import load_config
from osm_import.pack import CHUNK_SIZE_M, SAMPLES_PER_CHUNK, TERRAIN_RES_M, ChunkSampler

# EdgeDropReport's constants (game/world/roads/edge_drop_report.gd)
DROP_M = 0.25
STEP_M = 2.0
OUT_M = (0.4, 1.0)
MERGE_M = 12.0
CELL_M = 16.0
COVER_DY_M = 1.0
# JunctionReport's (game/world/roads/junction_report.gd)
POKE_M = 0.05
SAMPLE_FRACTIONS = (0.6, 0.85)


def capture(region: Path, out: Path) -> Path:
    """Export `region` to `out` with the road passes stubbed, pickling their inputs beside it."""
    import osm_import.__main__ as main_mod

    state: dict = {"chunks": [], "bridges": None, "graph": None, "buildings": None}

    def flatten_stub(chunk, ground, junctions=None):
        state["chunks"].append(chunk)
        return 0

    def clamp_stub(chunks, bridges):
        state["bridges"] = bridges
        return 0

    real_bridges = main_mod.build_bridges
    real_buildings = main_mod.build_buildings

    def bridges_wrap(graph, sample, *args, **kwargs):
        state["graph"] = graph
        return real_bridges(graph, sample, *args, **kwargs)

    def buildings_wrap(*args, **kwargs):
        state["buildings"] = real_buildings(*args, **kwargs)
        return state["buildings"]

    pack_names = (
        "flatten_roads",
        "lift_buried_paths",
        "cut_under_deep_paths",
        "clamp_under_decks",
        "restore_road_beds",
    )
    main_names = (
        *pack_names[1:],
        "build_terrain",
        "build_bridges",
        "build_buildings",
        "build_walls",
        "hold_in_front_of_walls",
    )
    original_pack = {name: getattr(pack, name) for name in pack_names}
    original_main = {name: getattr(main_mod, name) for name in main_names}
    try:
        pack.flatten_roads = flatten_stub
        pack.lift_buried_paths = lambda graph, sample: 0
        pack.cut_under_deep_paths = lambda chunks, graph, sample: 0
        pack.clamp_under_decks = clamp_stub
        pack.restore_road_beds = lambda chunks, graph: 0
        for name in pack_names[1:]:
            setattr(main_mod, name, getattr(pack, name))
        main_mod.build_terrain = pack.build_terrain
        main_mod.build_bridges = bridges_wrap
        main_mod.build_buildings = buildings_wrap
        main_mod.build_walls = lambda graph, sample, bridges, cfg: W.WallsResult()
        main_mod.hold_in_front_of_walls = lambda chunks, graph, walls, buildings=None: 0
        main_mod.main(
            [
                "--region",
                str(region),
                "--pack-out",
                str(out),
                "--pack-version",
                "0.0.0",
                "--build-stamp",
            ]
        )
    finally:
        # Put the real passes back, so a replay in the same process runs them.
        for name, function in original_pack.items():
            setattr(pack, name, function)
        for name, function in original_main.items():
            setattr(main_mod, name, function)
    pkl = out.with_suffix(".pkl")
    with pkl.open("wb") as f:
        pickle.dump(state, f)
    print(f"captured {len(state['chunks'])} chunks to {pkl}")
    return pkl


class Replay:
    """One run of the road passes on a capture, with the terrain after each pass kept."""

    def __init__(self, cap: dict) -> None:
        self.chunks = copy.deepcopy(cap["chunks"])
        self.graph = copy.deepcopy(cap["graph"])
        self.bridges = cap["bridges"]
        self.buildings = cap.get("buildings")
        self.walls = W.WallsResult()
        self.snaps: list[tuple[str, dict]] = []
        self.by_key = {(c.cx, c.cz): c for c in self.chunks}

    def run(self) -> float:
        t0 = time.time()
        ground, _bridges = pack._road_footprints(self.graph)
        junctions = pack.ground_junctions(self.graph)
        self._snap("carved")
        for ch in self.chunks:
            pack.flatten_roads(ch, ground, junctions)
        self._snap("flatten")
        pack.lift_buried_paths(self.graph, ChunkSampler(self.chunks).sample)
        pack.cut_under_deep_paths(self.chunks, self.graph, ChunkSampler(self.chunks).sample)
        self._snap("cut")
        pack.clamp_under_decks(self.chunks, self.bridges)
        self._snap("clamp")
        pack.restore_road_beds(self.chunks, self.graph)
        self._snap("restore")
        pack.lift_buried_paths(self.graph, ChunkSampler(self.chunks).sample)
        pack.cut_under_deep_paths(self.chunks, self.graph, ChunkSampler(self.chunks).sample)
        self._snap("cut again")
        self.walls = W.build_walls(
            self.graph, ChunkSampler(self.chunks).sample, self.bridges, load_config()
        )
        W.hold_in_front_of_walls(self.chunks, self.graph, self.walls, self.buildings)
        self._snap("walls")
        return time.time() - t0

    def _snap(self, name: str) -> None:
        self.snaps.append((name, {k: c.heights.copy() for k, c in self.by_key.items()}))

    def sample(self, x: float, z: float) -> float:
        ch = self.by_key.get((math.floor(x / CHUNK_SIZE_M), math.floor(z / CHUNK_SIZE_M)))
        if ch is None:
            return math.nan
        fx = min(max((x - ch.min_x) / TERRAIN_RES_M, 0.0), SAMPLES_PER_CHUNK - 1.001)
        fz = min(max((z - ch.min_z) / TERRAIN_RES_M, 0.0), SAMPLES_PER_CHUNK - 1.001)
        c0, r0 = int(fx), int(fz)
        tx, tz = fx - c0, fz - r0
        h = ch.heights
        top = h[r0, c0] * (1 - tx) + h[r0, c0 + 1] * tx
        bottom = h[r0 + 1, c0] * (1 - tx) + h[r0 + 1, c0 + 1] * tx
        return float(top * (1 - tz) + bottom * tz)

    def blame(self, x: float, z: float) -> str:
        """The pass that last moved the lowest of the four cells around (x, z)."""
        key = (math.floor(x / CHUNK_SIZE_M), math.floor(z / CHUNK_SIZE_M))
        ch = self.by_key[key]
        c0, r0 = int((x - ch.min_x) / TERRAIN_RES_M), int((z - ch.min_z) / TERRAIN_RES_M)
        cells = [(r0, c0), (r0, c0 + 1), (r0 + 1, c0), (r0 + 1, c0 + 1)]
        r, c = min(cells, key=lambda rc: ch.heights[rc])
        history = [(name, float(hs[key][r, c])) for name, hs in self.snaps]
        last = history[0][0]
        for i in range(1, len(history)):
            if abs(history[i][1] - history[i - 1][1]) > 1e-3:
                last = history[i][0]
        return last


def _mesh_height(j: J.JunctionSurface, tris: list, px: float, pz: float) -> float | None:
    for ia, ib, ic in tris:
        (ax, az), (bx, bz), (qx, qz) = j.polygon[ia], j.polygon[ib], j.polygon[ic]
        det = (bx - ax) * (qz - az) - (qx - ax) * (bz - az)
        if abs(det) < 1e-9:
            continue
        wb = ((px - ax) * (qz - az) - (qx - ax) * (pz - az)) / det
        wc = ((bx - ax) * (pz - az) - (px - ax) * (bz - az)) / det
        wa = 1 - wb - wc
        if wa >= -1e-6 and wb >= -1e-6 and wc >= -1e-6:
            return wa * j.heights[ia] + wb * j.heights[ib] + wc * j.heights[ic]
    return None


def junction_pokes(rep: Replay) -> tuple[list, int]:
    """(worst, node id, centre) per junction with terrain over POKE_M above its drawn surface
    at JunctionReport's sample points, worst first, and how many junctions were checked."""
    out = []
    checked = 0
    for nid, j in J.build_all(rep.graph).items():
        if j.has_tunnel_arm or len(j.polygon) < 3:
            continue
        checked += 1
        tris = j.triangles()
        worst = -math.inf
        for i, (vx, vz) in enumerate(j.polygon):
            for f in SAMPLE_FRACTIONS:
                px = j.centre[0] + (vx - j.centre[0]) * f
                pz = j.centre[2] + (vz - j.centre[2]) * f
                fallback = j.centre[1] + (j.heights[i] - j.centre[1]) * f
                surface = _mesh_height(j, tris, px, pz)
                g = rep.sample(px, pz)
                if math.isnan(g):
                    continue
                worst = max(worst, g - (fallback if surface is None else surface))
        if worst > POKE_M:
            out.append((worst, nid, j.centre))
    out.sort(reverse=True)
    return out, checked


class _Cover:
    """EdgeDropReport._cover_grid: every surface that can cover the ground beside a road."""

    def __init__(self, graph, junctions: dict) -> None:
        self.grid: dict = {}
        for e in graph.edges.values():
            if not e.tunnel:
                self._ribbon(e.polyline, e.width_m * 0.5)
        for w in graph.pedestrian:
            if not w.covered and w.profile != "tunnel":
                self._ribbon(w.polyline, max(w.width_m, 1.0) * 0.5)
        for j in junctions.values():
            if len(j.polygon) < 3:
                continue
            xs = [p[0] for p in j.polygon]
            zs = [p[1] for p in j.polygon]
            self._box(min(xs), min(zs), max(xs), max(zs), ("poly", j, j.triangles()))

    def _box(self, x0, z0, x1, z1, item) -> None:
        for cx in range(math.floor(x0 / CELL_M), math.floor(x1 / CELL_M) + 1):
            for cz in range(math.floor(z0 / CELL_M), math.floor(z1 / CELL_M) + 1):
                self.grid.setdefault((cx, cz), []).append(item)

    def _ribbon(self, pl, half: float) -> None:
        for a, b in pairwise(pl):
            item = ("seg", a[0], a[2], b[0], b[2], a[1], b[1], half + 0.05)
            r = half + 0.05
            self._box(
                min(a[0], b[0]) - r,
                min(a[2], b[2]) - r,
                max(a[0], b[0]) + r,
                max(a[2], b[2]) + r,
                item,
            )

    def covered(self, x: float, z: float, y: float) -> bool:
        for item in self.grid.get((math.floor(x / CELL_M), math.floor(z / CELL_M)), []):
            if item[0] == "poly":
                j, tris = item[1], item[2]
                if _in_polygon(x, z, j.polygon):
                    sy = _mesh_height(j, tris, x, z)
                    if abs((j.centre[1] if sy is None else sy) - y) <= COVER_DY_M:
                        return True
                continue
            _, ax, az, bx, bz, ya, yb, half = item
            dx, dz = bx - ax, bz - az
            l2 = max(dx * dx + dz * dz, 1e-6)
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / l2))
            near = math.hypot(x - (ax + t * dx), z - (az + t * dz)) <= half
            if near and abs(ya + (yb - ya) * t - y) <= COVER_DY_M:
                return True
        return False


def _in_polygon(x: float, z: float, poly: list) -> bool:
    inside = False
    n = len(poly)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        if (az > z) != (bz > z) and x < ax + (z - az) * (bx - ax) / (bz - az):
            inside = not inside
    return inside


def wheel_traps(rep: Replay) -> list[dict]:
    """EdgeDropReport.analyse: spots where the ground past a ground road's edge drops more than
    DROP_M with nothing covering it, deepest first."""
    cover = _Cover(rep.graph, J.build_all(rep.graph))
    rows: list[dict] = []
    for e in rep.graph.edges.values():
        if e.bridge or e.tunnel or len(e.polyline) < 2:
            continue
        half = e.width_m * 0.5
        last: dict = {}
        walked = 0.0
        for a, b in pairwise(e.polyline):
            sx, sz = b[0] - a[0], b[2] - a[2]
            length = math.hypot(sx, sz)
            if length < 0.01:
                continue
            nx, nz = -sz / length, sx / length
            steps = max(1, int(length / STEP_M))
            for s in range(steps):
                t = (s + 0.5) / steps
                cx, cy, cz = a[0] + sx * t, a[1] + (b[1] - a[1]) * t, a[2] + sz * t
                for side in (-1, 1):
                    deepest, at = 0.0, None
                    for out in OUT_M:
                        qx, qz = cx + nx * side * (half + out), cz + nz * side * (half + out)
                        g = rep.sample(qx, qz)
                        if math.isnan(g) or cover.covered(qx, qz, cy):
                            continue
                        if cy - g > deepest:
                            deepest, at = cy - g, (qx, qz)
                    if deepest <= DROP_M:
                        continue
                    along = walked + length * t
                    row = last.get(side)
                    if row and along - row["along"] <= MERGE_M:
                        row["along"] = along
                        if deepest > row["drop"]:
                            row["drop"], row["at"] = deepest, at
                        continue
                    row = {
                        "drop": deepest,
                        "at": at,
                        "road": e.name or e.road_class,
                        "cls": e.road_class,
                        "along": along,
                    }
                    rows.append(row)
                    last[side] = row
            walked += length
    rows.sort(key=lambda r: -r["drop"])
    return rows


def replay(pkl: Path, label: str = "") -> None:
    with pkl.open("rb") as f:
        cap = pickle.load(f)
    rep = Replay(cap)
    seconds = rep.run()
    t1 = time.time()
    pokes, checked = junction_pokes(rep)
    rows = wheel_traps(rep)
    worst = pokes[0][0] if pokes else 0.0
    share = 100 * len(pokes) / checked if checked else 0.0
    print(
        f"== {label}: {len(rows)} wheel traps; {len(pokes)} of {checked} junctions "
        f"({share:.1f}%) with terrain through the surface, worst "
        f"{worst:.2f} m; passes {seconds:.0f} s, measure {time.time() - t1:.0f} s"
    )
    by_class = collections.Counter(r["cls"] for r in rows).most_common(8)
    print("   retaining walls:", rep.walls.counts())
    print("   traps by class:", by_class)
    blames = collections.Counter(rep.blame(*r["at"]) for r in rows).most_common()
    print("   traps by the pass that last moved the low cell:", blames)
    for r in rows[:8]:
        print(
            f"   {r['drop']:.2f} m at ({r['at'][0]:.0f},{r['at'][1]:.0f}) {r['road']} ({r['cls']})"
        )
    for p in pokes[:8]:
        print(f"   poke +{p[0]:.2f} {p[1]} at ({p[2][0]:.0f},{p[2][2]:.0f})")


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) >= 3 and argv[0] == "capture":
        capture(Path(argv[1]), Path(argv[2]))
        return 0
    if len(argv) >= 2 and argv[0] == "replay":
        replay(Path(argv[1]), argv[2] if len(argv) > 2 else "")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
