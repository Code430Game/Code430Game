"""Pack versions mean something: compare a pack with its last release and say which bump the
change needs (add-pack-repositories, "Pack versions").

- major: an id a pack built on this one could reference is gone (buildings, turf, ads, ...),
  the map origin moved, or `engine_api` changed;
- minor: new ids, nothing removed;
- patch: files changed, no ids added or removed.

While a pack is `0.x` the minor number counts as the major one (as semver's `^0.2` does), so a
breaking change needs 0.2 -> 0.3 and anything else 0.2.0 -> 0.2.1. A release tag must read
`<pack folder>-v<version>`.

Usage: python -m pack_tools version check PACK_DIR (--old OLD_PACK_DIR | --ref GIT_REF) [--tag TAG]
"""

from __future__ import annotations

import argparse
import io
import json
import subprocess
import tarfile
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from pack_tools.validate import GENERATED, MANIFEST_NAME, V0_CONTENT_FILES, parse_semver

# Files whose ids other packs may reference, and where the ids sit: every importer file the
# validator knows plus the hand-made content files. Ads are keyed `ads/id`.
IGNORED_PARTS = {"chunks"}
IGNORED_NAMES = {"build.json"}
MANIFEST_FREE_KEYS = {"version", "build"}  # changes to these alone are not a content change
LEVELS = ("none", "patch", "minor", "major")


@dataclass
class Change:
    """What moved between two copies of a pack, and the bump it needs."""

    changed_files: list[str] = field(default_factory=list)
    removed_ids: list[str] = field(default_factory=list)
    added_ids: list[str] = field(default_factory=list)
    breaking: list[str] = field(default_factory=list)  # origin moved, engine_api changed

    @property
    def level(self) -> str:
        if self.removed_ids or self.breaking:
            return "major"
        if self.added_ids:
            return "minor"
        if self.changed_files:
            return "patch"
        return "none"


def id_paths() -> dict[str, list[tuple[str, ...]]]:
    """File name -> id paths, from the validator's tables (generated files and ads)."""
    out: dict[str, list[tuple[str, ...]]] = {name: paths for name, _s, paths in GENERATED}
    for name, ctype in V0_CONTENT_FILES.items():
        if ctype == "ads":
            out.setdefault(name, [("ads", "id")])
    return out


def _ids(data: dict, path: tuple[str, ...]) -> set[str]:
    if len(path) == 2:
        return {str(i[path[1]]) for i in data.get(path[0], []) if path[1] in i}
    return {
        str(inner[path[2]])
        for item in data.get(path[0], [])
        for inner in item.get(path[1], [])
        if path[2] in inner
    }


def _files(pack_dir: Path) -> dict[str, Path]:
    out = {}
    for p in sorted(pack_dir.rglob("*")):
        rel = p.relative_to(pack_dir)
        if p.is_file() and not (IGNORED_PARTS & set(rel.parts)) and rel.name not in IGNORED_NAMES:
            out[rel.as_posix()] = p
    return out


def _json(path: Path | None) -> dict:
    if path is None or not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def compare(old_dir: Path, new_dir: Path) -> Change:
    """The change from `old_dir` to `new_dir`, both pack folders."""
    change = Change()
    old_files, new_files = _files(old_dir), _files(new_dir)
    for rel in sorted(set(old_files) | set(new_files)):
        a, b = old_files.get(rel), new_files.get(rel)
        if rel == MANIFEST_NAME and a and b:
            strip = lambda m: {k: v for k, v in m.items() if k not in MANIFEST_FREE_KEYS}
            if strip(_json(a)) != strip(_json(b)):
                change.changed_files.append(rel)
        elif a is None or b is None or a.read_bytes() != b.read_bytes():
            change.changed_files.append(rel)
    for name, paths in id_paths().items():
        old, new = _json(old_files.get(name)), _json(new_files.get(name))
        for path in paths:
            before, after = _ids(old, path), _ids(new, path)
            where = f"{name}:{'/'.join(path)}"
            change.removed_ids += [f"{where} {i}" for i in sorted(before - after)]
            change.added_ids += [f"{where} {i}" for i in sorted(after - before)]
    old_m, new_m = _json(old_files.get(MANIFEST_NAME)), _json(new_files.get(MANIFEST_NAME))
    if (old_m.get("map") or {}).get("origin") != (new_m.get("map") or {}).get("origin"):
        change.breaking.append("map.origin moved")
    if old_m.get("engine_api") != new_m.get("engine_api"):
        change.breaking.append(f"engine_api {old_m.get('engine_api')} -> {new_m.get('engine_api')}")
    return change


def bump_of(old: str, new: str) -> str | None:
    """The bump from `old` to `new` in this project's terms ("none", "patch", "minor",
    "major"), or None when `new` is not above `old` or either isn't a version. In `0.x`, a
    minor step counts as major and a patch step as minor or patch."""
    a, b = parse_semver(old), parse_semver(new)
    if a is None or b is None:
        return None
    if b == a:
        return "none"
    if b < a:
        return None
    if b[0] > a[0]:
        return "major"
    if a[0] == 0:
        return "major" if b[1] > a[1] else "minor"  # a 0.x patch step covers minor and patch
    return "minor" if b[1] > a[1] else "patch"


def next_version(old: str, level: str) -> str:
    """The smallest version after `old` that satisfies `level`."""
    v = parse_semver(old) or (0, 0, 0)
    if level == "none":
        return old
    if v[0] == 0:
        return f"0.{v[1] + 1}.0" if level == "major" else f"0.{v[1]}.{v[2] + 1}"
    if level == "major":
        return f"{v[0] + 1}.0.0"
    if level == "minor":
        return f"{v[0]}.{v[1] + 1}.0"
    return f"{v[0]}.{v[1]}.{v[2] + 1}"


def check(old_dir: Path | None, new_dir: Path, tag: str | None = None) -> list[str]:
    """Errors for a pack against its last release (None: the first release)."""
    errors = []
    new_version = str(_json(new_dir / MANIFEST_NAME).get("version", ""))
    if tag is not None and tag != f"{new_dir.name}-v{new_version}":
        errors.append(f"tag '{tag}' should be '{new_dir.name}-v{new_version}'")
    if old_dir is None:
        return errors
    old_version = str(_json(old_dir / MANIFEST_NAME).get("version", ""))
    change = compare(old_dir, new_dir)
    need = change.level
    got = bump_of(old_version, new_version)
    if got is None:
        errors.append(f"version {new_version} is not above the last release {old_version}")
    elif LEVELS.index(got) < LEVELS.index(need):
        why = (
            (change.breaking + change.removed_ids[:5])
            or change.added_ids[:5]
            or change.changed_files[:5]
        )
        errors.append(
            f"the pack changed since {old_version} and needs a {need} bump "
            f"(at least {next_version(old_version, need)}), but pack.json says {new_version}: "
            + "; ".join(why)
            + (" …" if len(change.removed_ids) + len(change.added_ids) > 5 else "")
        )
    return errors


def _from_ref(pack_dir: Path, ref: str, into: Path) -> Path | None:
    """The pack folder as it was at `ref` in its git repository, unpacked under `into`."""
    pack_dir = pack_dir.resolve()
    top = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=pack_dir,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    )
    rel = pack_dir.relative_to(top).as_posix()
    out = subprocess.run(
        ["git", "archive", "--format=tar", ref, "--", rel],
        cwd=top,
        capture_output=True,
        check=False,
    )
    if out.returncode != 0:
        return None
    with tarfile.open(fileobj=io.BytesIO(out.stdout)) as tar:
        tar.extractall(into, filter="data")
    old = into / rel
    return old if (old / MANIFEST_NAME).is_file() else None


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="python -m pack_tools version check")
    parser.add_argument("pack", type=Path, help="The pack folder")
    src = parser.add_mutually_exclusive_group()
    src.add_argument("--old", type=Path, help="The pack folder of the last release")
    src.add_argument("--ref", help="Git ref of the last release (a tag); none: first release")
    parser.add_argument("--tag", help="The release tag being made, checked against the version")
    args = parser.parse_args(argv)
    with tempfile.TemporaryDirectory() as tmp:
        old = args.old
        if args.ref:
            old = _from_ref(args.pack, args.ref, Path(tmp))
            if old is None:
                print(f"FAIL  {args.pack}: no pack at {args.ref}")
                return 1
        errors = check(old, args.pack, args.tag)
    for e in errors:
        print(f"FAIL  {args.pack}: {e}")
    if not errors:
        print(f"OK    {args.pack}: version {_json(args.pack / MANIFEST_NAME).get('version')}")
    return 1 if errors else 0
