"""Validate pack folders against the manifest schema and the data-only rules.

Approach: for each folder under the given root that has a pack.json, validate the manifest
against the schema for its `schema_version` (v0 frozen, v1 additive), then walk the folder and
reject any file whose extension is not on the allowlist for data-only packs. Every content
file the pack indexes (v1 `content[]`, or the known v0 file names) must exist inside the pack
and validate against its type's schema; items that carry descriptors or variants are checked
against the tone modes. Dependencies are resolved across the packs under the root (a warning
when the dependency is not there, an error when it is there but out of range). Errors are
collected, not raised, so one run reports everything.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parents[2]
FORMAT_DIR = REPO_ROOT / "docs" / "pack-format"
SCHEMA_PATH = FORMAT_DIR / "pack.schema.v0.json"
SCHEMA_V1_PATH = FORMAT_DIR / "pack.schema.v1.json"
MANIFEST_SCHEMAS = {0: SCHEMA_PATH, 1: SCHEMA_V1_PATH}
ADS_SCHEMA_PATH = FORMAT_DIR / "ads.schema.v0.json"
CONTENT_DIR = REPO_ROOT / "game" / "core" / "content"
DESCRIPTORS_PATH = CONTENT_DIR / "content-descriptors.v0.json"
MODES_DIR = CONTENT_DIR / "modes"
ADS_NAME = "ads.v0.json"
VEHICLES_SCHEMA_PATH = FORMAT_DIR / "vehicles.schema.v0.json"
VEHICLES_NAME = "vehicles.v0.json"
PARKING_SCHEMA_PATH = FORMAT_DIR / "parking.schema.v0.json"
PARKING_NAME = "parking.v0.json"
BRIDGES_SCHEMA_PATH = FORMAT_DIR / "bridges.schema.v0.json"
BRIDGES_NAME = "bridges.v0.json"
WALLS_SCHEMA_PATH = FORMAT_DIR / "retaining_walls.schema.v0.json"
WALLS_NAME = "retaining_walls.v0.json"
VEGETATION_SCHEMA_PATH = FORMAT_DIR / "vegetation.schema.v0.json"
VEGETATION_NAME = "vegetation.v0.json"
WEAPONS_SCHEMA_PATH = FORMAT_DIR / "weapons.schema.v0.json"
WEAPONS_NAME = "weapons.v0.json"
SERVICES_SCHEMA_PATH = FORMAT_DIR / "services.schema.v0.json"
SERVICES_NAME = "services.v0.json"
FACTIONS_SCHEMA_PATH = FORMAT_DIR / "factions.schema.v0.json"
FACTIONS_NAME = "factions.v0.json"
TURF_SCHEMA_PATH = FORMAT_DIR / "turf.schema.v0.json"
LAP_SCHEMA_PATH = FORMAT_DIR / "lap.schema.v0.json"
RADIO_SCHEMA_PATH = FORMAT_DIR / "radio.schema.v0.json"
MUSIC_SCHEMA_PATH = FORMAT_DIR / "music.schema.v0.json"
PALETTES_SCHEMA_PATH = FORMAT_DIR / "character-palettes.schema.v1.json"
PRESETS_SCHEMA_PATH = FORMAT_DIR / "character-presets.schema.v1.json"
BASE_WEAPONS_PATH = REPO_ROOT / "game" / "actors" / "combat" / "weapons.v0.json"

# Content types the registry serves: the schema each file validates against and the key of
# the item list inside it (None: the file is one item). `missions` has no schema until
# add-story-pack lands; its files must exist and parse.
CONTENT_SCHEMAS: dict[str, tuple[Path | None, str | None]] = {
    "ads": (ADS_SCHEMA_PATH, "ads"),
    "vehicles": (VEHICLES_SCHEMA_PATH, "vehicles"),
    "weapons": (WEAPONS_SCHEMA_PATH, "weapons"),
    "factions": (FACTIONS_SCHEMA_PATH, "factions"),
    "turf": (TURF_SCHEMA_PATH, "turfs"),
    "lap": (LAP_SCHEMA_PATH, "laps"),
    "radio": (RADIO_SCHEMA_PATH, "stations"),
    "music": (MUSIC_SCHEMA_PATH, "tracks"),
    "palettes": (PALETTES_SCHEMA_PATH, None),
    "presets": (PRESETS_SCHEMA_PATH, "presets"),
    "missions": (None, "missions"),
}
# A v0 manifest has no content index: these file names imply their type.
V0_CONTENT_FILES: dict[str, str] = {
    ADS_NAME: "ads",
    VEHICLES_NAME: "vehicles",
    WEAPONS_NAME: "weapons",
    FACTIONS_NAME: "factions",
    "turf.v0.json": "turf",
    "lap.v0.json": "lap",
    "radio.v0.json": "radio",
    "music.v0.json": "music",
}
# Files the importer generates: (file, schema, where the ids are). An id path is the list key
# then the id field, or list, nested list and field for ids inside items (a bridge's decks).
GENERATED = [
    (
        "road_graph.v0.json",
        FORMAT_DIR / "road_graph.schema.v0.json",
        [
            ("nodes", "id"),
            ("edges", "id"),
            ("gores", "id"),
            ("pedestrian_ways", "id"),
            ("bus_stops", "id"),
        ],
    ),
    ("barriers.v0.json", FORMAT_DIR / "barriers.schema.v0.json", [("barriers", "id")]),
    (WALLS_NAME, WALLS_SCHEMA_PATH, [("walls", "id")]),
    (
        BRIDGES_NAME,
        BRIDGES_SCHEMA_PATH,
        [("bridges", "id"), ("bridges", "decks", "source")],
    ),
    ("buildings.v0.json", FORMAT_DIR / "buildings.schema.v0.json", [("buildings", "id")]),
    ("water.v0.json", FORMAT_DIR / "water.schema.v0.json", [("polygons", "id")]),
    (PARKING_NAME, PARKING_SCHEMA_PATH, [("lots", "id"), ("garages", "id")]),
    (VEGETATION_NAME, VEGETATION_SCHEMA_PATH, [("areas", "id")]),
    (SERVICES_NAME, SERVICES_SCHEMA_PATH, [("places", "id")]),
    ("yards.v0.json", FORMAT_DIR / "yards.schema.v0.json", [("yards", "house"), ("fences", "id")]),
    ("border.v0.json", FORMAT_DIR / "border.schema.v0.json", [("crossings", "node")]),
    # Pack extras a district's author writes by hand or by generator (add-proving-ground).
    ("lap.v0.json", LAP_SCHEMA_PATH, [("laps", "id")]),
    ("turf.v0.json", TURF_SCHEMA_PATH, [("turfs", "id")]),
]
MAX_ERRORS_PER_FILE = 20
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
_SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


# GitHub warns on a pushed file over 50 MB and refuses one over 100 MB; warn early, fail
# before GitHub would, and warn when a whole pack gets big (add-pack-repositories).
MB = 1024 * 1024
FILE_WARN_BYTES = 40 * MB
FILE_FAIL_BYTES = 90 * MB
PACK_WARN_BYTES = 250 * MB


def size_problems(pack_dir: Path) -> tuple[list[str], list[str]]:
    """(errors, warnings) for files near GitHub's limits; `chunks/` (built by the game, never
    committed) is not counted."""
    errors: list[str] = []
    warnings: list[str] = []
    total = 0
    for p in sorted(pack_dir.rglob("*")):
        rel = p.relative_to(pack_dir)
        if not p.is_file() or "chunks" in rel.parts:
            continue
        size = p.stat().st_size
        total += size
        if size > FILE_FAIL_BYTES:
            errors.append(
                f"{rel.as_posix()}: {size / MB:.0f} MB, over the {FILE_FAIL_BYTES // MB} MB limit "
                "(GitHub refuses files over 100 MB); split the district"
            )
        elif size > FILE_WARN_BYTES:
            warnings.append(
                f"{rel.as_posix()}: {size / MB:.0f} MB; plan a split before {FILE_FAIL_BYTES // MB} MB"
            )
    if total > PACK_WARN_BYTES:
        warnings.append(f"the pack is {total / MB:.0f} MB; plan a split before it reaches 1 GB")
    return errors, warnings


@dataclass
class PackReport:
    """Validation outcome for one pack folder."""

    path: Path
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    manifest: dict = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return not self.errors


_schema_cache: dict[Path, Draft202012Validator] = {}


def load_schema(path: Path = SCHEMA_PATH) -> Draft202012Validator:
    """Load and check a schema (cached per path)."""
    if path not in _schema_cache:
        schema = json.loads(path.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        _schema_cache[path] = Draft202012Validator(schema)
    return _schema_cache[path]


def manifest_validator(manifest: dict, v0: Draft202012Validator | None = None) -> tuple:
    """(validator, error) for the manifest's `schema_version`: v0 (the given validator when one
    is passed, for callers that bring their own schema), v1, or an error naming the version."""
    version = manifest.get("schema_version")
    if version == 0:
        return (v0 if v0 is not None else load_schema(SCHEMA_PATH)), ""
    if version == 1:
        return load_schema(SCHEMA_V1_PATH), ""
    known = ", ".join(str(v) for v in MANIFEST_SCHEMAS)
    return None, f"schema_version: unknown version {version!r} (known: {known})"


def validate_manifest(manifest: dict, validator: Draft202012Validator) -> list[str]:
    """Return schema and policy errors for a parsed manifest."""
    errors: list[str] = []
    for err in sorted(validator.iter_errors(manifest), key=lambda e: list(e.path)):
        where = "/".join(str(p) for p in err.path) or "(root)"
        errors.append(f"{where}: {err.message}")
    # OpenStreetMap data is ODbL; a map pack under another licence (a generated test
    # district) has no OpenStreetMap data to credit.
    if manifest.get("type") == "map" and manifest.get("license", "ODbL-1.0") == "ODbL-1.0":
        credits = manifest.get("attribution", [])
        if not any(OSM_CREDIT in line for line in credits if isinstance(line, str)):
            errors.append(f"attribution: ODbL map packs must credit '{OSM_CREDIT}'")
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


def nonlethal_variant_keys(modes_dir: Path = MODES_DIR) -> set[str]:
    """Variant keys of the tone modes whose `lethal_weapons` flag is off (clean)."""
    keys = set()
    for p in sorted(modes_dir.glob("*.json")):
        mode = json.loads(p.read_text(encoding="utf-8"))
        if not mode.get("flags", {}).get("lethal_weapons", False):
            keys.add(str(mode.get("variant_key", mode.get("id", p.stem))))
    return keys


def load_base_weapons(path: Path = BASE_WEAPONS_PATH) -> dict:
    """The first-party weapons a faction's ids resolve against."""
    return json.loads(path.read_text(encoding="utf-8"))


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


def _schema_errors(name: str, data, validator: Draft202012Validator) -> list[str]:
    errors = []
    for found, err in enumerate(
        sorted(validator.iter_errors(data), key=lambda e: list(e.path)), start=1
    ):
        where = "/".join(str(p) for p in err.path) or "(root)"
        errors.append(f"{name}: {where}: {err.message}")
        if found >= MAX_ERRORS_PER_FILE:
            break
    return errors


def item_content_checks(
    name: str, items: list, desc: dict, modes: dict, supported: list[str]
) -> tuple[list[str], list[str]]:
    """Descriptor, leak and support checks for any list of content items: each item's own
    `descriptors`, each variant's descriptors, no variant keyed to a mode exceeding what that
    mode allows, and a warning when a supported mode would hide an item with variants
    entirely. Returns (errors, warnings)."""
    errors: list[str] = []
    warnings: list[str] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        iid = str(item.get("id", item.get("name", index)))
        errors.extend(_descriptor_errors(f"{name} {iid}", item.get("descriptors", {}), desc))
        variants = item.get("variants")
        if not isinstance(variants, dict):
            continue
        for key, variant in variants.items():
            if not isinstance(variant, dict):
                continue
            declared = variant.get("descriptors", {})
            errors.extend(_descriptor_errors(f"{name} {iid}/{key}", declared, desc))
            if key in modes and not _allowed(declared, modes[key], desc):
                over = [n for n in declared if not _allowed({n: declared[n]}, modes[key], desc)]
                errors.append(
                    f"{name} {iid}/{key}: descriptors {over} exceed what mode '{key}' allows"
                )
        for mode_id in supported:
            mode = modes[mode_id]
            shown = any(
                key in (mode["variant_key"], "fallback")
                and isinstance(variant, dict)
                and _allowed(variant.get("descriptors", {}), mode, desc)
                for key, variant in variants.items()
            )
            if not shown:
                warnings.append(f"{name} {iid}: nothing allowed in supported mode '{mode_id}'")
    return errors, warnings


def validate_ads(
    ads: dict, manifest: dict, desc: dict, modes: dict, ads_validator: Draft202012Validator
) -> tuple[list[str], list[str]]:
    """Descriptor, leak and support checks for an ads file. Returns (errors, warnings)."""
    errors = _schema_errors(ADS_NAME, ads, ads_validator)
    if errors:
        return errors, []
    supported = [m for m in manifest.get("supported_modes", []) if m in modes]
    return item_content_checks(ADS_NAME, ads.get("ads", []), desc, modes, supported)


def validate_vehicles(
    vehicles: dict, desc: dict, vehicles_validator: Draft202012Validator
) -> list[str]:
    """Schema (body class, dims, tunables) and descriptor checks for a vehicles file."""
    errors = _schema_errors(VEHICLES_NAME, vehicles, vehicles_validator)
    if errors:
        return errors
    seen = set()
    for v in vehicles.get("vehicles", []):
        vid = v["id"]
        if vid in seen:
            errors.append(f"{VEHICLES_NAME}: duplicate id '{vid}'")
        seen.add(vid)
        errors.extend(_descriptor_errors(f"{VEHICLES_NAME}: {vid}", v.get("descriptors", {}), desc))
        for key, variant in v.get("liveries", {}).get("variants", {}).items():
            errors.extend(
                _descriptor_errors(
                    f"{VEHICLES_NAME}: {vid} livery {key}", variant.get("descriptors", {}), desc
                )
            )
    return errors


def validate_weapons(weapons: dict, validator: Draft202012Validator) -> list[str]:
    """Schema errors, plus any lethal variant keyed to a mode that bans lethal weapons."""
    errors = _schema_errors(WEAPONS_NAME, weapons, validator)
    banned = nonlethal_variant_keys()
    for w in weapons.get("weapons", []):
        for key, v in w.get("variants", {}).items():
            if key in banned and v.get("lethal"):
                errors.append(
                    f"{WEAPONS_NAME}: {w.get('id')}: variant '{key}' is lethal in a mode without lethal weapons"
                )
    return errors


def validate_factions(
    factions: dict,
    weapons: dict,
    desc: dict,
    validator: Draft202012Validator,
) -> list[str]:
    """Schema errors, unknown descriptors, weapon ids that are not in `weapons`, and any variant
    keyed to a mode without lethal weapons that names a weapon lethal in that mode
    (add-hostile-gang 1.1)."""
    errors = _schema_errors(FACTIONS_NAME, factions, validator)
    if errors:
        return errors
    banned = nonlethal_variant_keys()
    by_id = {w.get("id"): w for w in weapons.get("weapons", [])}
    for f in factions.get("factions", []):
        fid = f.get("id")
        errors.extend(_descriptor_errors(f"{FACTIONS_NAME}: {fid}", f.get("descriptors", {}), desc))
        for key, v in f.get("variants", {}).items():
            errors.extend(
                _descriptor_errors(
                    f"{FACTIONS_NAME}: {fid}: variant '{key}'", v.get("descriptors", {}), desc
                )
            )
            for role in ("melee", "ranged"):
                wid = v.get(role, "")
                if wid == "":
                    continue
                w = by_id.get(wid)
                if w is None:
                    errors.append(
                        f"{FACTIONS_NAME}: {fid}: variant '{key}' names unknown weapon '{wid}'"
                    )
                    continue
                if key in banned:
                    wv = w.get("variants", {}).get(key, w.get("variants", {}).get("fallback", {}))
                    if wv.get("lethal"):
                        errors.append(
                            f"{FACTIONS_NAME}: {fid}: variant '{key}' arms the crew with '{wid}', lethal in a mode without lethal weapons"
                        )
    return errors


def validate_presets(presets: dict, palettes: dict | None) -> list[str]:
    """Every preset's colour indices must fit the pack's palettes (schema errors come first)."""
    errors: list[str] = []
    if palettes is None:
        return errors
    lists = palettes.get("palettes", {})
    fields = {
        "skin": "skin",
        "hair_colour": "hair_colour",
        "top": "cloth",
        "bottom": "cloth",
        "jacket_colour": "cloth",
        "shoes": "shoes",
    }
    for preset in presets.get("presets", []):
        profile = preset.get("profile", {})
        for key, palette in fields.items():
            n = len(lists.get(palette, []))
            if int(profile.get(key, 0)) >= n:
                errors.append(
                    f"presets: {preset.get('name')}: {key} index {profile.get(key)} is outside the {palette} palette ({n} entries)"
                )
    return errors


def parse_semver(version: str) -> tuple[int, int, int] | None:
    """(major, minor, patch) or None when `version` is not a semantic version."""
    m = _SEMVER.match(version or "")
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def semver_satisfies(version: str, spec: str) -> bool:
    """Whether `version` satisfies `spec`: exact, `^1.2`, `~1.2.3`, `>=1.0 <2.0` (space
    separated comparators) or `*`. Unparseable input never satisfies."""
    v = parse_semver(version)
    if v is None:
        return False
    spec = (spec or "").strip()
    if spec in ("", "*"):
        return True
    for part in spec.split():
        if not _satisfies_one(v, part):
            return False
    return True


def _pad(text: str) -> tuple[tuple[int, int, int], int]:
    """A partial version like `1.2` padded to a triple, plus how many parts were given."""
    parts = text.split(".")
    nums = [int(p) if p.isdigit() else 0 for p in parts[:3]]
    while len(nums) < 3:
        nums.append(0)
    return (nums[0], nums[1], nums[2]), len(parts)


def _satisfies_one(v: tuple[int, int, int], part: str) -> bool:
    if part.startswith("^"):
        low, _ = _pad(part[1:])
        if low[0] > 0:
            high = (low[0] + 1, 0, 0)
        elif low[1] > 0:
            high = (0, low[1] + 1, 0)
        else:
            high = (0, 0, low[2] + 1)
        return low <= v < high
    if part.startswith("~"):
        low, given = _pad(part[1:])
        high = (low[0] + 1, 0, 0) if given == 1 else (low[0], low[1] + 1, 0)
        return low <= v < high
    for op in (">=", "<=", ">", "<", "="):
        if part.startswith(op):
            bound, _ = _pad(part[len(op) :])
            return {
                ">=": v >= bound,
                "<=": v <= bound,
                ">": v > bound,
                "<": v < bound,
                "=": v == bound,
            }[op]
    exact, given = _pad(part)
    return v == exact if given == 3 else v[:given] == exact[:given]


def content_index(manifest: dict, pack_dir: Path) -> list[dict]:
    """The pack's content entries: `content[]` for v1, or the known v0 file names that exist."""
    if manifest.get("schema_version") == 1:
        entries = manifest.get("content", [])
        return [e for e in entries if isinstance(e, dict)]
    return [
        {"type": ctype, "path": name}
        for name, ctype in V0_CONTENT_FILES.items()
        if (pack_dir / name).is_file()
    ]


def _inside(pack_dir: Path, rel: str) -> Path | None:
    """The absolute path of `rel` when it stays inside `pack_dir`, else None."""
    if not rel or rel.startswith(("/", "\\")) or ".." in Path(rel).parts:
        return None
    target = (pack_dir / rel).resolve()
    try:
        target.relative_to(pack_dir.resolve())
    except ValueError:
        return None
    return target


def validate_content(
    pack_dir: Path, manifest: dict, desc: dict, modes: dict
) -> tuple[list[str], list[str]]:
    """Every indexed content file exists inside the pack, parses, validates against its type's
    schema and passes the descriptor checks; v1 packs also get the type-section cross checks."""
    errors: list[str] = []
    warnings: list[str] = []
    supported = [m for m in manifest.get("supported_modes", []) if m in modes]
    loaded: dict[str, dict] = {}
    indexed_paths: set[str] = set()
    for entry in content_index(manifest, pack_dir):
        ctype = str(entry.get("type", ""))
        rel = str(entry.get("path", ""))
        indexed_paths.add(rel)
        if ctype not in CONTENT_SCHEMAS:
            errors.append(f"content: {rel}: unknown content type '{ctype}'")
            continue
        target = _inside(pack_dir, rel)
        if target is None:
            errors.append(f"content: {rel}: path leaves the pack folder")
            continue
        if not target.is_file():
            errors.append(f"content: {rel}: file not found")
            continue
        try:
            data = json.loads(target.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{rel}: invalid JSON: {exc}")
            continue
        schema_path, list_key = CONTENT_SCHEMAS[ctype]
        if schema_path is None:
            warnings.append(f"content: {rel}: no schema for '{ctype}' yet, only parsed")
            continue
        if not isinstance(data, dict):
            errors.append(f"{rel}: must be a JSON object")
            continue
        name = Path(rel).name
        if ctype == "ads":
            e, w = validate_ads(data, manifest, desc, modes, load_schema(schema_path))
            errors.extend(x.replace(ADS_NAME, rel, 1) for x in e)
            warnings.extend(x.replace(ADS_NAME, rel, 1) for x in w)
        elif ctype == "vehicles":
            errors.extend(validate_vehicles(data, desc, load_schema(schema_path)))
        elif ctype == "weapons":
            errors.extend(validate_weapons(data, load_schema(schema_path)))
        elif ctype == "factions":
            errors.extend(
                validate_factions(data, load_base_weapons(), desc, load_schema(schema_path))
            )
        else:
            errors.extend(_schema_errors(name, data, load_schema(schema_path)))
            if list_key is not None and isinstance(data.get(list_key), list):
                e, w = item_content_checks(name, data[list_key], desc, modes, supported)
                errors.extend(e)
                warnings.extend(w)
        loaded[ctype] = data
    if manifest.get("schema_version") == 1:
        for name, ctype in V0_CONTENT_FILES.items():
            if (pack_dir / name).is_file() and name not in indexed_paths:
                warnings.append(f"{name}: not in content[]; the loader will not see it")
        character = manifest.get("character")
        if isinstance(character, dict):
            for key, ctype in (("palettes", "palettes"), ("presets", "presets")):
                path = character.get(key)
                if path is not None and path not in indexed_paths:
                    errors.append(
                        f"character.{key}: '{path}' is not listed in content[] as {ctype}"
                    )
        story = manifest.get("story")
        if isinstance(story, dict):
            deps = {d.get("id") for d in manifest.get("dependencies", []) if isinstance(d, dict)}
            if story.get("map") not in deps:
                errors.append(f"story.map: '{story.get('map')}' must also be a dependency")
        if "presets" in loaded:
            errors.extend(validate_presets(loaded["presets"], loaded.get("palettes")))
    return errors, warnings


def duplicate_ids(name: str, data: dict, paths: list[tuple[str, ...]]) -> list[str]:
    """Errors for ids that appear more than once at any of `paths` in a generated file."""
    errors = []
    for path in paths:
        values: list = []
        if len(path) == 2:
            values = [item.get(path[1]) for item in data.get(path[0], [])]
        else:
            values = [
                inner.get(path[2])
                for item in data.get(path[0], [])
                for inner in item.get(path[1], [])
            ]
        seen: set = set()
        dupes: set = set()
        for v in values:
            if v is None:
                continue
            if v in seen:
                dupes.add(v)
            seen.add(v)
        for v in sorted(dupes, key=str)[:MAX_ERRORS_PER_FILE]:
            errors.append(f"{name}: {'/'.join(path)}: '{v}' is not unique")
    return errors


def validate_generated(pack_dir: Path) -> list[str]:
    """Schema and id-uniqueness errors for the importer's files present in a pack."""
    errors: list[str] = []
    for name, schema_path, id_paths in GENERATED:
        path = pack_dir / name
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{name}: invalid JSON: {exc}")
            continue
        errors.extend(_schema_errors(name, data, load_schema(schema_path)))
        if isinstance(data, dict):
            errors.extend(duplicate_ids(name, data, id_paths))
        if name == WALLS_NAME and isinstance(data, dict):
            errors.extend(wall_top_errors(data))
    return errors


def wall_top_errors(data: dict) -> list[str]:
    """A retaining wall carries one top per point (add-retaining-walls): the schema can require
    `tops_m`, not that it is as long as `points`, so that is checked here."""
    errors: list[str] = []
    for w in data.get("walls", []):
        if not isinstance(w, dict):
            continue
        points, tops = w.get("points"), w.get("tops_m")
        if isinstance(points, list) and isinstance(tops, list) and len(points) != len(tops):
            errors.append(
                f"{WALLS_NAME}: wall '{w.get('id')}' has {len(tops)} tops_m for "
                f"{len(points)} points"
            )
        if len(errors) >= MAX_ERRORS_PER_FILE:
            break
    return errors


def validate_pack(pack_dir: Path, validator: Draft202012Validator | None = None) -> PackReport:
    """Validate one pack folder. `validator` is used for v0 manifests when given."""
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
    report.manifest = manifest
    chosen, version_error = manifest_validator(manifest, validator)
    if chosen is None:
        report.errors.append(version_error)
        return report
    report.errors.extend(validate_manifest(manifest, chosen))
    pack_type = manifest.get("type")
    if isinstance(pack_type, str):
        report.errors.extend(validate_files(pack_dir, pack_type))
    desc, modes = load_content_rules()
    for mode_id in manifest.get("supported_modes", []):
        if mode_id not in modes:
            report.errors.append(f"supported_modes: unknown mode '{mode_id}'")
    errors, warnings = validate_content(pack_dir, manifest, desc, modes)
    report.errors.extend(errors)
    report.warnings.extend(warnings)
    report.errors.extend(validate_generated(pack_dir))
    size_errors, size_warnings = size_problems(pack_dir)
    report.errors.extend(size_errors)
    report.warnings.extend(size_warnings)
    return report


def validate_dependencies(reports: list[PackReport]) -> None:
    """Resolves every pack's dependencies against the packs validated together: a dependency
    missing from the root is a warning (it may be installed elsewhere), one present but out of
    its range is an error. Adds to the reports in place."""
    by_id = {r.manifest.get("id"): r.manifest for r in reports if r.manifest.get("id")}
    for report in reports:
        for dep in report.manifest.get("dependencies", []):
            if not isinstance(dep, dict):
                continue
            dep_id = str(dep.get("id", ""))
            spec = str(dep.get("version", "*"))
            found = by_id.get(dep_id)
            if found is None:
                report.warnings.append(
                    f"dependencies: '{dep_id}' not found beside this pack (needs {spec})"
                )
            elif not semver_satisfies(str(found.get("version", "")), spec):
                report.errors.append(
                    f"dependencies: '{dep_id}' is {found.get('version')}, this pack needs {spec}"
                )


def find_packs(root: Path) -> list[Path]:
    """Return every folder under root (or root itself) that holds a pack.json."""
    if (root / MANIFEST_NAME).is_file():
        return [root]
    return sorted(p.parent for p in root.rglob(MANIFEST_NAME))


def validate_root(root: Path, schema_path: Path = SCHEMA_PATH) -> list[PackReport]:
    """Validate every pack under root, then their dependencies against each other."""
    validator = load_schema(schema_path)
    reports = [validate_pack(pack_dir, validator) for pack_dir in find_packs(root)]
    validate_dependencies(reports)
    return reports


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate Code 430 pack manifests and contents.")
    parser.add_argument("root", type=Path, help="Folder containing packs, or a single pack folder.")
    parser.add_argument(
        "--schema", type=Path, default=SCHEMA_PATH, help="Manifest schema to use for v0 packs."
    )
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
