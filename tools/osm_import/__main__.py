"""CLI: python -m osm_import --bbox S,W,N,E --out DIR [--osm-json FILE] [--config FILE]

Subcommand `crop` cuts a fixture out of a cached extract:
python -m osm_import crop --osm-json FILE --bbox S,W,N,E --out FILE
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from collections import Counter
from pathlib import Path

from osm_import.barriers import build_barriers
from osm_import.bridges import bridges_query, build_bridges
from osm_import.buildings import build_buildings, buildings_query
from osm_import.elevation import FlatSource, SyntheticSource, hrdem_source
from osm_import.export import pedestrian_to_list
from osm_import.fetch import DEFAULT_CACHE_DIR, fetch_bbox, fetch_query
from osm_import.garages import build_garages
from osm_import.houses import build_house_hints
from osm_import.osm_data import BBox, OsmData
from osm_import.pack import (
    ChunkSampler,
    build_terrain,
    clamp_under_decks,
    elevation_attribution_for,
    write_pack,
)
from osm_import.parking import build_parking, parking_query
from osm_import.pipeline import load_cfg, run_pipeline, write_outputs
from osm_import.projection import Projector
from osm_import.services import build_services, services_query
from osm_import.validation import render_markdown
from osm_import.vegetation import build_vegetation, vegetation_query
from osm_import.water import build_water, water_query
from osm_import.yards import build_yards


def _source(layer: str, meta: dict | None, path: Path | None = None) -> dict:
    """Where one layer's data came from, for the road graph's meta (AGENTS.md: record the
    source URL and timestamp in the generated output). Every query is its own snapshot."""
    if path is not None:
        return {"kind": "file", "layer": layer, "path": path.name}
    return dict(sorted({**(meta or {}), "layer": layer}.items()))


def _import(args: argparse.Namespace) -> int:
    if args.region is not None:
        region = json.loads(args.region.read_text(encoding="utf-8"))
        s, w, n, e = region["bbox"]
        args.bbox = f"{s},{w},{n},{e}"
        args.pack_id = region.get("pack_id", args.pack_id)
        args.pack_name = args.pack_name or region.get("pack_name") or region.get("name")
        args.title = args.title or region.get("pack_name") or region.get("name")
        if args.dem == "hrdem" and region.get("dem"):
            args.dem = region["dem"]
        # A region may name every layer's input file (a generated district, or a cached
        # extract), so the import runs with no network at all. Paths are relative to the file.
        base = args.region.parent
        for layer, attr in (
            ("osm", "osm_json"),
            ("water", "water_json"),
            ("buildings", "buildings_json"),
            ("parking", "parking_json"),
            ("bridges", "bridges_json"),
            ("services", "services_json"),
            ("vegetation", "vegetation_json"),
        ):
            rel = region.get("inputs", {}).get(layer)
            if rel and getattr(args, attr) is None:
                setattr(args, attr, base / rel)
        args.extras = [base / rel for rel in region.get("extras", [])]
        args.spawn = region.get("spawn")
        args.synthetic = region.get("synthetic")
    bbox = BBox.parse(args.bbox)
    cfg, cfg_name = load_cfg(args.config)
    if args.osm_json:
        data = OsmData.load(args.osm_json)
    else:
        data = fetch_bbox(bbox, cache_dir=args.cache_dir)
    if args.dem == "hrdem":
        elevation = hrdem_source(bbox, Projector.for_bbox(bbox), args.cache_dir)
    elif args.dem == "synthetic":
        elevation = SyntheticSource(**(getattr(args, "synthetic", None) or {}))
    elif args.dem == "flat":
        elevation = FlatSource()
    else:
        elevation = None
    result = run_pipeline(data, bbox, cfg, cfg_name, elevation)
    title = args.title or bbox.overpass()
    if args.pack_out:
        if elevation is None:
            parser_error("--pack-out needs an elevation source (use --dem flat for a test pack)")
        proj = Projector.for_bbox(bbox)
        sources = result.graph_dict["meta"]["sources"]
        sources[:] = [_source("roads", src) for src in sources]
        water = None
        if args.water:
            if args.water_json:
                water_payload = json.loads(args.water_json.read_text(encoding="utf-8"))
                sources.append(_source("water", None, args.water_json))
            else:
                water_payload, meta = fetch_query(water_query(bbox), bbox, args.cache_dir)
                sources.append(_source("water", meta))
            water = build_water(water_payload, bbox, proj, elevation)
            result.report.summary["water"] = {
                "polygons": len(water.polygons),
                "skipped": water.skipped,
            }
        buildings = None
        if args.buildings:
            if args.buildings_json:
                b_payload = json.loads(args.buildings_json.read_text(encoding="utf-8"))
                sources.append(_source("buildings", None, args.buildings_json))
            else:
                b_payload, meta = fetch_query(buildings_query(bbox), bbox, args.cache_dir)
                sources.append(_source("buildings", meta))
            buildings = build_buildings(b_payload, bbox, proj, elevation, cfg.buildings)
            houses = build_house_hints(buildings, result.graph)
            result.report.summary["buildings"] = {
                "footprints": len(buildings.buildings),
                "skipped": buildings.skipped[:20],
                "height_sources": buildings.height_sources,
                "house_types": dict(sorted(Counter(h.type for h in houses.values()).items())),
            }
        chunks, tstats = build_terrain(
            result.graph, elevation, proj.bbox_local(bbox), water, cfg.water_depth_m, buildings, cfg
        )
        # Bridges after the terrain (pier feet stand on it); they lift deck walkways, so the
        # pedestrian ways are re-exported after them.
        if args.bridges_json:
            outlines = json.loads(args.bridges_json.read_text(encoding="utf-8"))
            sources.append(_source("bridges", None, args.bridges_json))
        else:
            outlines, meta = fetch_query(bridges_query(bbox), bbox, args.cache_dir)
            sources.append(_source("bridges", meta))
        bridges = build_bridges(
            result.graph, ChunkSampler(chunks).sample, cfg.bridges, outlines, proj, water
        )
        tstats["cells_lowered_under_decks"] = clamp_under_decks(chunks, bridges)
        bridges.reset_pier_feet(ChunkSampler(chunks).sample)
        result.report.summary["bridges"] = bridges.counts()
        # The terrain stage sets pedestrian heights and cuts paths under bridges: re-export them.
        result.graph_dict["pedestrian_ways"] = pedestrian_to_list(result.graph)
        # Barriers use final pedestrian heights (curbs), so they come after the terrain.
        barriers = build_barriers(
            result.graph, elevation, buildings, cfg, proj.bbox_local(bbox), bridges.infill()
        )
        result.report.summary["barriers"] = barriers.counts
        parking = None
        if args.parking:
            if args.parking_json:
                p_payload = json.loads(args.parking_json.read_text(encoding="utf-8"))
                sources.append(_source("parking", None, args.parking_json))
            else:
                p_payload, meta = fetch_query(parking_query(bbox), bbox, args.cache_dir)
                sources.append(_source("parking", meta))
            # After the terrain: lots take their ground height from the built (graded) terrain.
            parking = build_parking(p_payload, bbox, proj, result.graph, ChunkSampler(chunks), data)
            parking.garages = build_garages(
                data,
                result.graph,
                proj,
                buildings,
                [lot for lot in parking.lots if lot.kind == "underground"],
                ChunkSampler(chunks),
                cfg.parking.get("garages"),
            )
            result.report.summary["parking"] = parking.counts()
        # Yards after parking: lots, like roads and other buildings, are not yard.
        yards = None
        if buildings is not None:
            yards = build_yards(buildings, result.graph, parking, water)
            result.report.summary["yards"] = yards.counts()
        # Vegetation last: it keeps off the final roads, sidewalks, buildings and water, and
        # stands on the finished terrain.
        if args.vegetation_json:
            v_payload = json.loads(args.vegetation_json.read_text(encoding="utf-8"))
            sources.append(_source("vegetation", None, args.vegetation_json))
        else:
            v_payload, meta = fetch_query(vegetation_query(bbox), bbox, args.cache_dir)
            sources.append(_source("vegetation", meta))
        vegetation = build_vegetation(
            v_payload, bbox, proj, result.graph, buildings, water, ChunkSampler(chunks)
        )
        result.report.summary["vegetation"] = vegetation.counts()
        if args.services_json:
            s_payload = json.loads(args.services_json.read_text(encoding="utf-8"))
            sources.append(_source("services", None, args.services_json))
        else:
            s_payload, meta = fetch_query(services_query(bbox), bbox, args.cache_dir)
            sources.append(_source("services", meta))
        services = build_services(
            s_payload,
            bbox,
            proj,
            result.graph,
            ChunkSampler(chunks),
            b_payload if args.buildings else None,
            cfg.services,
        )
        result.report.summary["services"] = services.counts()
        result.report.summary["service_addresses"] = services.address_sources()
        result.report.summary["terrain"] = tstats
        paths = write_pack(
            args.pack_out,
            args.pack_id,
            args.pack_name or title,
            args.pack_version,
            result.graph_dict,
            result.report.to_dict(),
            render_markdown(result.report, title),
            chunks,
            proj.frame,
            bbox,
            elevation_attribution_for(elevation),
            water,
            buildings,
            barriers,
            parking,
            bridges,
            vegetation,
            services,
            spawn=getattr(args, "spawn", None),
            yards=yards,
        )
        # Pack extras the importer does not produce (a lap timer, a gang's turf) ride along.
        for extra in getattr(args, "extras", None) or []:
            target = args.pack_out / extra.name
            target.write_bytes(extra.read_bytes())
            paths[extra.stem] = target
        print(f"terrain: {tstats}")
        print(f"barriers: {barriers.counts}")
        print(f"bridges: {bridges.counts()}")
        print(f"vegetation: {vegetation.counts()}")
        print(f"services: {services.counts()}, addresses {services.address_sources()}")
        if buildings is not None:
            print(
                f"buildings: {len(buildings.buildings)} footprints, heights {buildings.height_sources}"
            )
        if water is not None:
            print(f"water: {len(water.polygons)} polygons, {len(water.skipped)} skipped")
        if parking is not None:
            print(f"parking: {parking.counts()}")
    else:
        paths = write_outputs(result, args.out, title)
    s = result.report.summary
    print(
        f"nodes {s['nodes']}  edges {s['edges']}  length {s['total_length_km']} km  components {s['components']}"
    )
    print(
        f"dead ends {s['dead_ends']}  ramp problems {s['ramp_problems']}  traps {s['one_way_traps']}"
    )
    for k, p in paths.items():
        print(f"{k}: {p}")
    return 0


def parser_error(message: str) -> None:
    raise SystemExit(f"error: {message}")


def _crop(args: argparse.Namespace) -> int:
    bbox = BBox.parse(args.bbox)
    data = OsmData.load(args.osm_json).crop(bbox)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(data.to_overpass_json(), indent=0, sort_keys=False) + "\n", encoding="utf-8"
    )
    print(f"wrote {len(data.ways)} ways, {len(data.nodes)} nodes to {args.out}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="osm_import", description="OSM to Code 430 road graph.")
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command")

    imp = sub.add_parser("import", help="Import a bbox (default command).")
    imp.add_argument("--bbox", help="S,W,N,E in WGS84 (or use --region)")
    imp.add_argument(
        "--region", type=Path, help="regions/<name>.json from the region picker: bbox, pack id, dem"
    )
    imp.add_argument("--out", type=Path, help="Output directory for graph and report")
    imp.add_argument(
        "--pack-out", type=Path, help="Write a complete map pack folder here instead of --out"
    )
    imp.add_argument("--pack-id", default="code430.map", help="Pack id for pack.json")
    imp.add_argument("--pack-name", help="Pack display name (defaults to --title)")
    imp.add_argument("--pack-version", default="0.1.0")
    imp.add_argument(
        "--water",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Fetch and write water polygons with --pack-out",
    )
    imp.add_argument(
        "--water-json", type=Path, help="Read this Overpass water JSON instead of fetching"
    )
    imp.add_argument(
        "--buildings",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Fetch and write building footprints with --pack-out",
    )
    imp.add_argument(
        "--buildings-json", type=Path, help="Read this Overpass buildings JSON instead of fetching"
    )
    imp.add_argument(
        "--parking",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Fetch and write parking lots and street bays with --pack-out",
    )
    imp.add_argument(
        "--parking-json", type=Path, help="Read this Overpass parking JSON instead of fetching"
    )
    imp.add_argument(
        "--osm-json", type=Path, help="Read this Overpass JSON file instead of fetching"
    )
    imp.add_argument(
        "--bridges-json",
        type=Path,
        help="Read this Overpass bridge-outline JSON instead of fetching",
    )
    imp.add_argument(
        "--services-json", type=Path, help="Read this Overpass services JSON instead of fetching"
    )
    imp.add_argument(
        "--vegetation-json",
        type=Path,
        help="Read this Overpass vegetation JSON instead of fetching",
    )
    imp.add_argument("--config", type=Path, help="Road class defaults JSON")
    imp.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    imp.add_argument("--title", help="Title for the Markdown report")
    imp.add_argument(
        "--dem",
        choices=["hrdem", "synthetic", "flat", "none"],
        default="hrdem",
        help="Elevation source (default hrdem)",
    )
    imp.set_defaults(func=_import)

    crop = sub.add_parser("crop", help="Cut a fixture out of an Overpass JSON file.")
    crop.add_argument("--osm-json", required=True, type=Path)
    crop.add_argument("--bbox", required=True)
    crop.add_argument("--out", required=True, type=Path)
    crop.set_defaults(func=_crop)

    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] not in ("import", "crop", "-h", "--help", "-v", "--verbose"):
        argv.insert(0, "import")
    elif (
        argv
        and argv[0] in ("-v", "--verbose")
        and len(argv) > 1
        and argv[1] not in ("import", "crop")
    ):
        argv.insert(1, "import")
    args = parser.parse_args(argv)
    if getattr(args, "command", None) == "import" and not (args.out or args.pack_out):
        parser.error("one of --out or --pack-out is required")
    if getattr(args, "command", None) == "import" and not (args.bbox or args.region):
        parser.error("one of --bbox or --region is required")
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    if not getattr(args, "func", None):
        parser.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
