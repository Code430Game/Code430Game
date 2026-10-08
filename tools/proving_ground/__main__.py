"""CLI: python -m proving_ground --out DIR [--region FILE]

Writes the Double Cross district's OSM-shaped inputs under DIR and, with --region, the region
file the importer reads them from (`python -m osm_import --region FILE --pack-out ...`).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from proving_ground.emit import feature_counts, write_all
from proving_ground.layout import build


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="proving_ground", description="Generate the Double Cross test district."
    )
    parser.add_argument(
        "--out", type=Path, required=True, help="Directory for the generated input files"
    )
    parser.add_argument(
        "--region",
        type=Path,
        help="Write the region file here (inputs are referenced relative to it)",
    )
    parser.add_argument("--town", default="Double Cross", help="The town's name")
    args = parser.parse_args(argv)
    district = build(args.town)
    paths = write_all(district, args.out, args.region)
    counts = feature_counts(district)
    print(" ".join(f"{k}={v}" for k, v in counts.items()))
    for key, path in paths.items():
        print(f"{key}: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
