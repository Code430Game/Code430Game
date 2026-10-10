"""Checks third-party art and its receipts, and the art size budget.

    uv run python third_party_check.py <repo>

Rules (adopt-art-kit, design.md "Licensing"):
- every pack folder under art/<author>/<pack>/ has a SOURCE.md that says "License: CC0" and
  either carries the pack's own License.txt or a "## Receipt" section with the links;
- every other file in the folder is listed in SOURCE.md with its sha256, and the hash matches,
  so a file can't be swapped or added without a record;
- every folder in game/assets/ holding models (.glb, .gltf) has a SOURCE.md saying where they
  came from;
- art/ and game/assets/ together stay within BUDGET_BYTES.
Exits 1 with one line per problem.
"""

import hashlib
import re
import sys
from pathlib import Path

BUDGET_BYTES = 120 * 1024 * 1024
RECEIPT_FILES = {"SOURCE.md", "License.txt", "LICENSE.txt", "License.md"}
MODEL_SUFFIXES = {".glb", ".gltf"}
HASH_LINE = re.compile(r"^([0-9a-f]{64})\s+(\S.*)$", re.MULTILINE)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_pack(folder: Path, repo: Path) -> list[str]:
    rel = folder.relative_to(repo)
    source = folder / "SOURCE.md"
    if not source.exists():
        return [f"{rel}: no SOURCE.md"]
    text = source.read_text(encoding="utf-8")
    problems = []
    if not re.search(r"License:\s*CC0", text):
        problems.append(f"{rel}/SOURCE.md: no 'License: CC0' line")
    has_licence = any((folder / n).exists() for n in RECEIPT_FILES - {"SOURCE.md"})
    if not has_licence and "## Receipt" not in text:
        problems.append(f"{rel}: neither the pack's License.txt nor a '## Receipt' section")
    listed = {name.strip(): digest for digest, name in HASH_LINE.findall(text)}
    for f in sorted(p for p in folder.rglob("*") if p.is_file()):
        name = f.relative_to(folder).as_posix()
        if name in RECEIPT_FILES or f.name == ".DS_Store":
            continue
        if name not in listed:
            problems.append(f"{rel}/{name}: not listed with its sha256 in SOURCE.md")
        elif listed[name] != sha256(f):
            problems.append(f"{rel}/{name}: sha256 differs from SOURCE.md")
    return problems


def check(repo: Path) -> list[str]:
    problems = []
    art = repo / "art"
    if art.exists():
        for author in sorted(p for p in art.iterdir() if p.is_dir()):
            for pack in sorted(p for p in author.iterdir() if p.is_dir()):
                problems += check_pack(pack, repo)
    assets = repo / "game" / "assets"
    if assets.exists():
        folders = {p.parent for p in assets.rglob("*") if p.suffix in MODEL_SUFFIXES}
        for folder in sorted(folders):
            if not (folder / "SOURCE.md").exists():
                problems.append(f"{folder.relative_to(repo)}: models without a SOURCE.md")
    total = sum(
        p.stat().st_size
        for root in (art, assets)
        if root.exists()
        for p in root.rglob("*")
        if p.is_file()
    )
    if total > BUDGET_BYTES:
        problems.append(f"art budget: {total / 2**20:.1f} MB > {BUDGET_BYTES / 2**20:.0f} MB")
    return problems


def main(argv: list[str]) -> int:
    repo = Path(argv[1] if len(argv) > 1 else "..").resolve()
    problems = check(repo)
    for p in problems:
        print(p)
    if not problems:
        print("third-party art: receipts and budget ok")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
