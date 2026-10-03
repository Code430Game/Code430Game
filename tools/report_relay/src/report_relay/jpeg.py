"""Reads a JPEG's dimensions from its frame header without decoding it."""

from __future__ import annotations

# Start-of-frame markers: baseline, extended, progressive and lossless variants (not DHT, JPG, DAC).
_SOF = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}


def size(data: bytes) -> tuple[int, int] | None:
    """(width, height), or None when `data` is not a JPEG with a frame header."""
    if len(data) < 4 or data[0:2] != b"\xff\xd8":
        return None
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            return None
        marker = data[i + 1]
        if marker == 0xFF:
            i += 1
            continue
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        length = int.from_bytes(data[i + 2 : i + 4], "big")
        if length < 2:
            return None
        if marker in _SOF:
            if i + 9 > len(data):
                return None
            height = int.from_bytes(data[i + 5 : i + 7], "big")
            width = int.from_bytes(data[i + 7 : i + 9], "big")
            return width, height
        if marker == 0xDA:  # start of scan before any frame header
            return None
        i += 2 + length
    return None
