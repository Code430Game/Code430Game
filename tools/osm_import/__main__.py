"""CLI: python -m osm_import --bbox S,W,N,E --out DIR [--osm-json FILE] [--config FILE]

Subcommand `crop` cuts a fixture out of a cached extract:
python -m osm_import crop --osm-json FILE --bbox S,W,N,E --out FILE
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from osm_import.elevation import FlatSource, SyntheticSource, hrdem_source
from osm_import.fetch import DEFAULT_CACHE_DIR, fetch_bbox
from osm_import.osm_data import BBox, OsmData
from osm_import.pipeline import load_cfg, run_pipeline, write_outputs
from osm_import.projection import Projector


def _import(args: argparse.Namespace) -> int:
    bbox = BBox.parse(args.bbox)
    cfg, cfg_name = load_cfg(args.config)
    if args.osm_json:
        data = OsmData.load(args.osm_json)
    else:
        data = fetch_bbox(bbox, cache_dir=args.cache_dir)
    if args.dem == "hrdem":
        elevation = hrdem_source(bbox, Projector.for_bbox(bbox), args.cache_dir)
    elif args.dem == "synthetic":
        elevation = SyntheticSource()
    elif args.dem == "flat":
        elevation = FlatSource()
    else:
        elevation = None
    result = run_pipeline(data, bbox, cfg, cfg_name, elevation)
    paths = write_outputs(result, args.out, args.title or bbox.overpass())
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
    imp.add_argument("--bbox", required=True, help="S,W,N,E in WGS84")
    imp.add_argument("--out", required=True, type=Path, help="Output directory")
    imp.add_argument(
        "--osm-json", type=Path, help="Read this Overpass JSON file instead of fetching"
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
