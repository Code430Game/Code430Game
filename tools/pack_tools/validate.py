"""Validate pack folders against the manifest schema and the data-only rules.

Approach: for each folder under the given root that has a pack.json, validate the
manifest against docs/pack-format/pack.schema.v0.json, then walk the folder and
reject any file whose extension is not on the allowlist for data-only packs.
Errors are collected, not raised, so one run reports everything.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "docs" / "pack-format" / "pack.schema.v0.json"
ADS_SCHEMA_PATH = REPO_ROOT / "docs" / "pack-format" / "ads.schema.v0.json"
CONTENT_DIR = REPO_ROOT / "game" / "core" / "content"
DESCRIPTORS_PATH = CONTENT_DIR / "content-descriptors.v0.json"
MODES_DIR = CONTENT_DIR / "modes"
ADS_NAME = "ads.v0.json"
LEVELS = ["none", "mild", "strong"]
MANIFEST_NAME = "pack.json"

DATA_ONLY_TYPES = {"map", "character", "story"}
DATA_ONLY_EXTENSIONS = {
    ".json",
    ".yaml",
    ".yml",
    ".txt",
    ".md",
    ".csv",
    ".gltf",
    ".glb",
    ".bin",
    ".png",
    ".jpg",
    ".jpeg",
    ".ktx2",
    ".webp",
    ".ogg",
    ".wav",
}
OSM_CREDIT = "© OpenStreetMap contributors"
IGNORED_NAMES = {".DS_Store", ".gitkeep"}


@dataclass
class PackReport:
    """Validation outcome for one pack folder."""

    path: Path
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def load_schema(path: Path = SCHEMA_PATH) -> Draft202012Validator:
    """Load and check the manifest schema itself."""
    schema = json.loads(path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def validate_manifest(manifest: dict, validator: Draft202012Validator) -> list[str]:
    """Return schema and policy errors for a parsed manifest."""
    errors: list[str] = []
    for err in sorted(validator.iter_errors(manifest), key=lambda e: list(e.path)):
        where = "/".join(str(p) for p in err.path) or "(root)"
        if err.validator == "required":
            errors.append(f"{where}: {err.message}")
        else:
            errors.append(f"{where}: {err.message}")
    if manifest.get("type") == "map":
        credits = manifest.get("attribution", [])
        if not any(OSM_CREDIT in line for line in credits if isinstance(line, str)):
            errors.append(f"attribution: map packs must credit '{OSM_CREDIT}'")
    return errors


def validate_files(pack_dir: Path, pack_type: str) -> list[str]:
    """Return errors for files that a data-only pack is not allowed to contain."""
    if pack_type not in DATA_ONLY_TYPES:
        return []
    errors: list[str] = []
    for file in sorted(p for p in pack_dir.rglob("*") if p.is_file()):
        if file.name in IGNORED_NAMES:
            continue
        if file.suffix.lower() not in DATA_ONLY_EXTENSIONS:
            rel = file.relative_to(pack_dir)
            errors.append(
                f"file {rel}: extension '{file.suffix}' is not allowed in a {pack_type} pack"
            )
    return errors


def load_content_rules(
    descriptors_path: Path = DESCRIPTORS_PATH, modes_dir: Path = MODES_DIR
) -> tuple[dict, dict]:
    """(descriptors, modes by id) from the game's content data."""
    desc = json.loads(descriptors_path.read_text(encoding="utf-8"))
    modes = {}
    for f in sorted(modes_dir.glob("*.json")):
        mode = json.loads(f.read_text(encoding="utf-8"))
        modes[mode["id"]] = mode
    return desc, modes


def _level(value: str, descriptor: str, desc: dict) -> int | None:
    aliases = desc["descriptors"].get(descriptor, {}).get("aliases", {})
    value = aliases.get(value, value)
    return LEVELS.index(value) if value in LEVELS else None


def _descriptor_errors(where: str, declared: dict, desc: dict) -> list[str]:
    errors = []
    for name, level in declared.items():
        if name not in desc["descriptors"]:
            errors.append(f"{where}: unknown descriptor '{name}'")
        elif _level(level, name, desc) is None:
            errors.append(f"{where}: descriptor '{name}' has unknown level '{level}'")
    return errors


def _allowed(declared: dict, mode: dict, desc: dict) -> bool:
    for name, level in declared.items():
        lv = _level(level, name, desc)
        mx = _level(mode["max"].get(name, "none"), name, desc)
        if lv is None or mx is None or lv > mx:
            return False
    return True


def validate_ads(
    ads: dict, manifest: dict, desc: dict, modes: dict, ads_validator: Draft202012Validator
) -> tuple[list[str], list[str]]:
    """Descriptor, leak and support checks for an ads file. Returns (errors, warnings)."""
    errors: list[str] = []
    warnings: list[str] = []
    for err in sorted(ads_validator.iter_errors(ads), key=lambda e: list(e.path)):
        where = "/".join(str(p) for p in err.path) or "(root)"
        errors.append(f"{ADS_NAME}/{where}: {err.message}")
    if errors:
        return errors, warnings
    supported = [m for m in manifest.get("supported_modes", []) if m in modes]
    for item in ads.get("ads", []):
        iid = item["id"]
        errors.extend(_descriptor_errors(f"{ADS_NAME} {iid}", item.get("descriptors", {}), desc))
        for key, variant in item["variants"].items():
            declared = variant.get("descriptors", {})
            errors.extend(_descriptor_errors(f"{ADS_NAME} {iid}/{key}", declared, desc))
            if key in modes and not _allowed(declared, modes[key], desc):
                over = [n for n in declared if not _allowed({n: declared[n]}, modes[key], desc)]
                errors.append(
                    f"{ADS_NAME} {iid}/{key}: descriptors {over} exceed what mode '{key}' allows"
                )
        for mode_id in supported:
            mode = modes[mode_id]
            shown = any(
                key in (mode["variant_key"], "fallback")
                and _allowed(variant.get("descriptors", {}), mode, desc)
                for key, variant in item["variants"].items()
            )
            if not shown:
                warnings.append(f"{ADS_NAME} {iid}: nothing allowed in supported mode '{mode_id}'")
    return errors, warnings


def validate_pack(pack_dir: Path, validator: Draft202012Validator) -> PackReport:
    """Validate one pack folder."""
    report = PackReport(path=pack_dir)
    manifest_path = pack_dir / MANIFEST_NAME
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        report.errors.append(f"{MANIFEST_NAME}: invalid JSON: {exc}")
        return report
    if not isinstance(manifest, dict):
        report.errors.append(f"{MANIFEST_NAME}: must be a JSON object")
        return report
    report.errors.extend(validate_manifest(manifest, validator))
    pack_type = manifest.get("type")
    if isinstance(pack_type, str):
        report.errors.extend(validate_files(pack_dir, pack_type))
    desc, modes = load_content_rules()
    for mode_id in manifest.get("supported_modes", []):
        if mode_id not in modes:
            report.errors.append(f"supported_modes: unknown mode '{mode_id}'")
    ads_path = pack_dir / ADS_NAME
    if ads_path.is_file():
        try:
            ads = json.loads(ads_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            report.errors.append(f"{ADS_NAME}: invalid JSON: {exc}")
            return report
        errors, warnings = validate_ads(ads, manifest, desc, modes, load_schema(ADS_SCHEMA_PATH))
        report.errors.extend(errors)
        report.warnings.extend(warnings)
    return report


def find_packs(root: Path) -> list[Path]:
    """Return every folder under root (or root itself) that holds a pack.json."""
    if (root / MANIFEST_NAME).is_file():
        return [root]
    return sorted(p.parent for p in root.rglob(MANIFEST_NAME))


def validate_root(root: Path, schema_path: Path = SCHEMA_PATH) -> list[PackReport]:
    """Validate every pack under root."""
    validator = load_schema(schema_path)
    return [validate_pack(pack_dir, validator) for pack_dir in find_packs(root)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate Code 430 pack manifests and contents.")
    parser.add_argument("root", type=Path, help="Folder containing packs, or a single pack folder.")
    parser.add_argument("--schema", type=Path, default=SCHEMA_PATH, help="Manifest schema to use.")
    args = parser.parse_args(argv)

    reports = validate_root(args.root, args.schema)
    if not reports:
        print(f"No packs found under {args.root}")
        return 1
    failed = 0
    for report in reports:
        if report.ok:
            print(f"OK    {report.path}")
            for warn in report.warnings:
                print(f"      - warning: {warn}")
        else:
            failed += 1
            print(f"FAIL  {report.path}")
            for err in report.errors:
                print(f"      - {err}")
            for warn in report.warnings:
                print(f"      - warning: {warn}")
    print(f"{len(reports) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
