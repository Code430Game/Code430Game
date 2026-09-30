"""Minimal, deterministic PNG writer and reader (8-bit RGB), no external deps."""

from __future__ import annotations

import struct
import zlib

import numpy as np


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_rgb8(rgb: np.ndarray) -> bytes:
    """Encode an (H, W, 3) uint8 array as PNG bytes. Filter type 0 on every row."""
    if rgb.ndim != 3 or rgb.shape[2] != 3 or rgb.dtype != np.uint8:
        raise ValueError("expected (H, W, 3) uint8")
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[r].tobytes() for r in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(raw, 9))
        + _chunk(b"IEND", b"")
    )


def read_rgb8(data: bytes) -> np.ndarray:
    """Decode a PNG written by write_rgb8 (filter 0 rows only). For tests."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    w = h = 0
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        tag = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype == 2
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    rows = []
    stride = w * 3 + 1
    for r in range(h):
        row = raw[r * stride : (r + 1) * stride]
        assert row[0] == 0
        rows.append(np.frombuffer(row[1:], dtype=np.uint8).reshape(w, 3))
    return np.stack(rows)


def encode_heights(heights: np.ndarray, min_y: float, max_y: float) -> np.ndarray:
    """Heights -> RGB where R is the high byte and G the low byte of a 16-bit value."""
    span = max(max_y - min_y, 1e-6)
    q = np.clip(np.round((heights - min_y) / span * 65535.0), 0, 65535).astype(np.uint32)
    rgb = np.zeros((*heights.shape, 3), dtype=np.uint8)
    rgb[..., 0] = (q >> 8) & 0xFF
    rgb[..., 1] = q & 0xFF
    return rgb


def decode_heights(rgb: np.ndarray, min_y: float, max_y: float) -> np.ndarray:
    q = rgb[..., 0].astype(np.float64) * 256.0 + rgb[..., 1].astype(np.float64)
    return q / 65535.0 * (max_y - min_y) + min_y
