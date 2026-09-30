"""Parsers for the OSM tag values the pipeline uses. Lenient, never raise."""

from __future__ import annotations

import re

_NUMBER = re.compile(r"[-+]?\d+(?:\.\d+)?")
MPH_TO_KPH = 1.609344


def parse_int(value: str | None) -> int | None:
    """First integer in the value, e.g. '2' or '2;3' -> 2."""
    if value is None:
        return None
    m = _NUMBER.search(value)
    if not m:
        return None
    try:
        return int(float(m.group(0)))
    except ValueError:
        return None


def parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    m = _NUMBER.search(value)
    if not m:
        return None
    try:
        return float(m.group(0))
    except ValueError:
        return None


def parse_width_m(value: str | None) -> float | None:
    """'12', '12 m', '12.5m', '40 ft' -> metres."""
    w = parse_float(value)
    if w is None or w <= 0:
        return None
    if value and ("ft" in value or "'" in value):
        return w * 0.3048
    return w


def parse_maxspeed_kph(value: str | None) -> int | None:
    """'50', '50 mph', 'walk' -> km/h or None when not numeric."""
    if value is None:
        return None
    v = parse_float(value)
    if v is None or v <= 0:
        return None
    if "mph" in value:
        v *= MPH_TO_KPH
    return round(v)


def parse_layer(value: str | None) -> int:
    """'1', '-1', '-1;0' -> int, default 0."""
    v = parse_int(value)
    return v if v is not None else 0


def is_truthy(value: str | None) -> bool:
    """Tag present and not 'no'/'false'/'0'. Used for bridge=* and tunnel=*."""
    return value is not None and value.lower() not in ("no", "false", "0")


def parse_oneway(value: str | None) -> str:
    """Return 'forward', 'reverse', 'no', or 'unset'."""
    if value is None:
        return "unset"
    v = value.lower()
    if v in ("yes", "true", "1"):
        return "forward"
    if v in ("-1", "reverse"):
        return "reverse"
    if v in ("no", "false", "0"):
        return "no"
    return "unset"
