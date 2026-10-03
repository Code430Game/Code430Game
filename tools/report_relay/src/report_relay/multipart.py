"""Parses multipart/form-data request bodies (just enough for the report form)."""

from __future__ import annotations

import re


class MultipartError(ValueError):
    pass


def boundary_of(content_type: str) -> str:
    """The boundary from a multipart/form-data Content-Type header."""
    if not content_type.lower().startswith("multipart/form-data"):
        raise MultipartError("expected multipart/form-data")
    m = re.search(r'boundary="?([^";]+)"?', content_type)
    if not m:
        raise MultipartError("no boundary")
    return m.group(1)


def parse(body: bytes, content_type: str) -> dict[str, bytes]:
    """Field name to raw bytes. Raises MultipartError on anything malformed."""
    delimiter = b"--" + boundary_of(content_type).encode("latin-1")
    parts = body.split(delimiter)
    if len(parts) < 3 or not parts[-1].startswith(b"--"):
        raise MultipartError("unterminated multipart body")
    fields: dict[str, bytes] = {}
    for part in parts[1:-1]:
        if not part.startswith(b"\r\n") or b"\r\n\r\n" not in part:
            raise MultipartError("malformed part")
        head, _, data = part[2:].partition(b"\r\n\r\n")
        if not data.endswith(b"\r\n"):
            raise MultipartError("part without CRLF before the next boundary")
        m = re.search(rb'Content-Disposition:\s*form-data;\s*name="([^"]+)"', head, re.IGNORECASE)
        if not m:
            raise MultipartError("part without a name")
        name = m.group(1).decode("latin-1")
        if name in fields:
            raise MultipartError(f"duplicate field {name}")
        fields[name] = data[:-2]
    return fields
