"""Turns a validated report into a GitHub issue: title, labels and a Markdown body.

Everything a player typed and everything the game measured is untrusted here. Text is defused
before it reaches Markdown: HTML is escaped, @mentions are broken with a zero-width space so
nobody is pinged, and links are shown as code so they cannot be dressed up. The body stays
under GitHub's 65,536-character limit by dropping the oldest log lines first.
"""

from __future__ import annotations

import json
import re

BODY_LIMIT = 65_000  # GitHub allows 65,536; leave room for the trailing comment's escaping
ZWSP = "\u200b"
AREAS = {
    "roads": "Roads and junctions",
    "traffic": "Traffic",
    "pedestrians": "Pedestrians",
    "vehicles": "Vehicles and handling",
    "world": "Buildings and world",
    "visuals": "Visuals",
    "performance": "Performance",
    "controls": "Controls and menus",
    "audio": "Audio",
    "crash": "Crash or freeze",
    "other": "Other",
}
SEVERITIES = {
    "cosmetic": "Cosmetic",
    "annoying": "Annoying",
    "blocks_play": "Blocks play",
    "crash": "Crash",
}
_URL = re.compile(r"https?://[^\s<>`]+")
_CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def defuse(text: str) -> str:
    """Untrusted text made safe for Markdown: no HTML, no mentions, links shown as code."""
    text = _CONTROL.sub("", text)
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = text.replace("@", "@" + ZWSP)
    return _URL.sub(lambda m: "`" + m.group(0) + "`", text)


def defuse_title(text: str) -> str:
    """Titles are plain text on GitHub; only control characters and mentions matter."""
    return _CONTROL.sub("", text).replace("@", "@" + ZWSP).strip()


def labels(report: dict) -> list[str]:
    return [
        "in-game-report",
        "needs-triage",
        f"area:{report['area']}",
        f"severity:{report['severity']}",
    ]


def marker(report_id: str) -> str:
    """The line that identifies a report's issue; the relay searches for it before filing."""
    return f"<!-- code430-report-id {report_id} -->"


def _code(value: str) -> str:
    """Inline code for an id from the report; backticks would end the span, so they go."""
    return "`" + _CONTROL.sub("", value).replace("`", "").replace("\n", " ") + "`"


def _cell(value: object) -> str:
    return defuse(str(value)).replace("|", "\\|").replace("\n", " ")


def _os_name(m: dict) -> str:
    """'SteamOS (Linux)', or just 'macOS' when the distribution is the OS's own name."""
    if m["distribution"] in ("", m["os"]):
        return m["os"]
    return f"{m['distribution']} ({m['os']})"


def _table(report: dict) -> list[str]:
    d = report["diagnostics"]
    b, m, s, place, ft = d["build"], d["machine"], d["settings"], d["place"], d["frame_time"]
    build_bits = [b["branch"], b["date"], "dirty" if b["dirty"] else "", b["source"]]
    packs = ", ".join(f"{p['id']} {p['version']}" for p in d["packs"]) or "none"
    session = d["session"]
    rows = [
        ("Build", f"{b['commit']} ({', '.join(x for x in build_bits if x)})"),
        ("Godot", d["engine"]["godot"]),
        (
            "Machine",
            f"{_os_name(m)} {m['os_version']}, {m['cpu']} ×{m['cpu_count']}, "
            f"{m['gpu']} ({m['graphics_api']}), {m['memory_mb']} MB"
            + (", Steam Deck" if m["deck"] else ""),
        ),
        (
            "Settings",
            (
                f"preset {s['preset']}, tone {s['tone_mode']}, "
                f"{m['resolution'][0]}×{m['resolution'][1]}"
            ),
        ),
        ("Packs", packs),
        (
            "Session",
            session["role"]
            if session["role"] == "single"
            else f"{session['role']}, {session['peers']} players",
        ),
        (
            "Place",
            (
                f"x {place['x']}, y {place['y']}, z {place['z']}, "
                f"heading {place['heading_deg']}°, {place['mode']}, {place['time_of_day']}"
            ),
        ),
        ("Frame time", f"avg {ft['avg_ms']} ms, p99 {ft['p99_ms']} ms over {ft['seconds']} s"),
    ]
    return ["| | |", "|---|---|"] + [f"| {k} | {_cell(v)} |" for k, v in rows]


def _comment_json(report: dict) -> str:
    slim = {k: v for k, v in report.items() if k != "log_tail"}
    # "--" may not appear inside an HTML comment; \u002d is the same character to a JSON reader.
    return json.dumps(slim, separators=(",", ":"), sort_keys=True).replace("--", "-\\u002d")


def body(report: dict, screenshot_url: str | None) -> str:
    """The issue body. Drops the oldest log lines until it fits GitHub's limit."""
    place = report["diagnostics"]["place"]
    where = f"x {place['x']}, z {place['z']}"
    ids = ", ".join(
        x
        for x in (
            place["road"] and defuse(place["road"]),
            place["edge_id"] and f"edge {_code(place['edge_id'])}",
            place["node_id"] and f"junction {_code(place['node_id'])}",
        )
        if x
    )
    head = [
        f"**Area:** {AREAS[report['area']]} · **Severity:** {SEVERITIES[report['severity']]} · "
        f"**Place:** {where}" + (f" ({ids})" if ids else ""),
        "",
    ]
    if report["description"].strip():
        head += [defuse(report["description"]), ""]
    if screenshot_url:
        head += [f"![screenshot]({screenshot_url})", ""]
    if report["credit_name"].strip():
        head += [f"Reported by {defuse(report['credit_name'])}.", ""]
    head += ["<details><summary>Diagnostics</summary>", ""] + _table(report) + [""]
    tail = [
        "</details>",
        "",
        marker(report["id"]),
        f"<!-- code430-report {_comment_json(report)} -->",
    ]
    log = [line.replace("~~~", "~ ~ ~") for line in report["log_tail"]]
    while True:
        log_block = ["~~~text", *log, "~~~", ""] if log else []
        text = "\n".join(head + log_block + tail)
        if len(text) <= BODY_LIMIT or not log:
            return text
        log = log[max(1, len(log) // 10) :]


def title(report: dict) -> str:
    return defuse_title(report["title"])[:120] or AREAS[report["area"]]
