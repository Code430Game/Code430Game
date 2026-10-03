"""Validates a report against report.schema.v1.json.

A small JSON Schema subset (the keywords the report schema uses) instead of the jsonschema
package, whose dependencies are compiled and not available on Workers. The tools tests check it
agrees with jsonschema on the example report and on broken variants.
"""

from __future__ import annotations

import json
import re
from typing import Any

from report_relay.schema_v1 import SCHEMA_JSON

_TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
}


def load_schema() -> dict:
    return json.loads(SCHEMA_JSON)


SCHEMA = load_schema()


def errors(value: Any, node: dict = SCHEMA, at: str = "$") -> list[str]:
    """Every way `value` breaks `node`; empty when it is valid."""
    out: list[str] = []
    if "const" in node and value != node["const"]:
        out.append(f"{at}: must be {node['const']!r}")
    if "enum" in node and value not in node["enum"]:
        out.append(f"{at}: must be one of {node['enum']}")
    kind = node.get("type")
    if kind is None:
        return out
    if kind == "integer":
        if isinstance(value, bool) or not (
            isinstance(value, int) or (isinstance(value, float) and value.is_integer())
        ):
            return out + [f"{at}: must be an integer"]
    elif kind == "number":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return out + [f"{at}: must be a number"]
    elif not isinstance(value, _TYPES[kind]) or (kind != "boolean" and isinstance(value, bool)):
        return out + [f"{at}: must be {kind}"]
    if kind in ("integer", "number"):
        if "minimum" in node and value < node["minimum"]:
            out.append(f"{at}: below {node['minimum']}")
        if "maximum" in node and value > node["maximum"]:
            out.append(f"{at}: above {node['maximum']}")
    elif kind == "string":
        if len(value) < node.get("minLength", 0) or len(value) > node.get("maxLength", 1 << 30):
            out.append(f"{at}: length {len(value)} out of range")
        if "pattern" in node and not re.search(node["pattern"], value):
            out.append(f"{at}: does not match {node['pattern']}")
    elif kind == "array":
        if len(value) < node.get("minItems", 0) or len(value) > node.get("maxItems", 1 << 30):
            out.append(f"{at}: {len(value)} items out of range")
        for i, item in enumerate(value):
            out += errors(item, node.get("items", {}), f"{at}[{i}]")
    elif kind == "object":
        props = node.get("properties", {})
        for key in node.get("required", []):
            if key not in value:
                out.append(f"{at}: missing {key}")
        for key, item in value.items():
            if key in props:
                out += errors(item, props[key], f"{at}.{key}")
            elif node.get("additionalProperties", True) is False:
                out.append(f"{at}: unknown key {key}")
    return out
