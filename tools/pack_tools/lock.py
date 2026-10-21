"""The packs the game builds and tests with, pinned in packs.lock.json (add-pack-repositories 2.1).

Each entry names a pack release in its own repository: the tag, the release asset, its sha256,
the commit the tag points at, and the folder under packs/ it unpacks into. `fetch` downloads
each release zip, checks its sha256, and replaces the folder (keeping chunks/, the game's
local mesh cache); a pack already at its locked hash is skipped. `check` makes sure every
locked pack is present at its hash and validates.

Usage:
  python -m pack_tools lock fetch [--lock FILE] [--packs DIR]
  python -m pack_tools lock check [--lock FILE] [--packs DIR]
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from jsonschema import Draft202012Validator

from pack_tools.validate import FORMAT_DIR, REPO_ROOT, validate_pack

LOCK_PATH = REPO_ROOT / "packs.lock.json"
LOCK_SCHEMA_PATH = FORMAT_DIR / "packs-lock.schema.v0.json"
PACKS_DIR = REPO_ROOT / "packs"
STAMP_DIR = ".fetched"  # packs/.fetched/<folder>.sha256: the hash each folder was fetched at
KEEP = {"chunks"}  # local caches a fetch leaves in place
# Release downloads; CODE430_PACK_BASE_URL points them elsewhere (a mirror, or a test folder).
BASE_URL = "https://github.com/{repo}/releases/download/{tag}/{asset}"


class LockError(Exception):
    """A lock file, download or pack that doesn't match."""


def load_lock(path: Path = LOCK_PATH) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    schema = json.loads(LOCK_SCHEMA_PATH.read_text(encoding="utf-8"))
    errors = sorted(Draft202012Validator(schema).iter_errors(data), key=lambda e: e.path)
    if errors:
        raise LockError(f"{path.name}: {errors[0].message}")
    return data["packs"]


def asset_url(entry: dict) -> str:
    base = os.environ.get("CODE430_PACK_BASE_URL")
    if base:
        return f"{base.rstrip('/')}/{entry['asset']}"
    return BASE_URL.format(repo=entry["repo"], tag=entry["tag"], asset=entry["asset"])


def _stamp(packs_dir: Path, entry: dict) -> Path:
    return packs_dir / STAMP_DIR / f"{entry['folder']}.sha256"


def is_current(packs_dir: Path, entry: dict) -> bool:
    stamp = _stamp(packs_dir, entry)
    return (
        (packs_dir / entry["folder"] / "pack.json").is_file()
        and stamp.is_file()
        and stamp.read_text(encoding="utf-8").strip() == entry["sha256"]
    )


def _unpack(data: bytes, target: Path) -> None:
    """Unzip a release (one top folder, the pack) into `target`, keeping its local caches."""
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
        tops = {n.split("/", 1)[0] for n in names}
        if len(tops) != 1 or any("/" not in n for n in names):
            raise LockError("a release zip must hold one folder, the pack")
        with tempfile.TemporaryDirectory(dir=target.parent) as tmp:
            zf.extractall(tmp)
            fresh = Path(tmp) / tops.pop()
            if target.is_dir():
                for child in target.iterdir():
                    if child.name in KEEP:
                        child.rename(fresh / child.name)
                shutil.rmtree(target)
            fresh.rename(target)


def fetch(entries: list[dict], packs_dir: Path = PACKS_DIR, log=print) -> int:
    """Fetch every locked pack that isn't current. Returns how many were fetched."""
    fetched = 0
    for entry in entries:
        if is_current(packs_dir, entry):
            log(f"ok    {entry['folder']} ({entry['tag']})")
            continue
        url = asset_url(entry)
        log(f"fetch {entry['folder']} <- {url}")
        with urllib.request.urlopen(url, timeout=120) as resp:
            data = resp.read()
        digest = hashlib.sha256(data).hexdigest()
        if digest != entry["sha256"]:
            raise LockError(
                f"{entry['asset']}: sha256 {digest} does not match the lock's {entry['sha256']}"
            )
        packs_dir.mkdir(parents=True, exist_ok=True)
        _unpack(data, packs_dir / entry["folder"])
        stamp = _stamp(packs_dir, entry)
        stamp.parent.mkdir(exist_ok=True)
        stamp.write_text(entry["sha256"] + "\n", encoding="utf-8")
        fetched += 1
    return fetched


def check(entries: list[dict], packs_dir: Path = PACKS_DIR) -> list[str]:
    """Errors: a locked pack missing, not at its hash, of another id or version, or invalid."""
    errors = []
    for entry in entries:
        folder = packs_dir / entry["folder"]
        if not is_current(packs_dir, entry):
            errors.append(
                f"{entry['folder']}: not fetched at {entry['tag']}; run scripts/fetch-packs.sh"
            )
            continue
        report = validate_pack(folder)
        manifest = report.manifest
        if manifest.get("id") != entry["id"]:
            errors.append(
                f"{entry['folder']}: pack id is {manifest.get('id')}, lock says {entry['id']}"
            )
        if not entry["tag"].endswith(f"-v{manifest.get('version')}"):
            errors.append(
                f"{entry['folder']}: pack version {manifest.get('version')} doesn't match tag {entry['tag']}"
            )
        errors += [f"{entry['folder']}: {e}" for e in report.errors]
    return errors


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="python -m pack_tools lock")
    parser.add_argument("action", choices=["fetch", "check"])
    parser.add_argument("--lock", type=Path, default=LOCK_PATH)
    parser.add_argument("--packs", type=Path, default=PACKS_DIR)
    args = parser.parse_args(argv)
    try:
        entries = load_lock(args.lock)
        if args.action == "fetch":
            fetch(entries, args.packs)
            return 0
        errors = check(entries, args.packs)
    except (LockError, OSError) as exc:
        print(f"FAIL  {exc}")
        return 1
    for e in errors:
        print(f"FAIL  {e}")
    if not errors:
        print(f"OK    {len(entries)} locked pack(s) present and valid")
    return 1 if errors else 0
