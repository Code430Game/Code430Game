"""Per-sender and global report limits, counted in a key-value store with expiring keys.

On Workers the store is a KV namespace (eventually consistent, so a burst can slip a report or
two past a limit; fine for abuse control). Senders are keyed by a salted hash of their IP, so
no address is ever stored.
"""

from __future__ import annotations

import hashlib
from collections.abc import Awaitable
from dataclasses import dataclass
from typing import Protocol

HOUR = 3600
DAY = 86400


class Store(Protocol):
    def get(self, key: str) -> Awaitable[str | None]: ...
    def put(self, key: str, value: str, ttl_s: int) -> Awaitable[None]: ...


@dataclass(frozen=True)
class Limits:
    per_hour: int = 5
    per_day: int = 20
    global_per_day: int = 200


DEFAULT_LIMITS = Limits()


def sender_key(ip: str, salt: str) -> str:
    """A short salted hash of the sender's IP; the IP itself is never stored."""
    return hashlib.sha256(f"{salt}:{ip}".encode()).hexdigest()[:24]


def _windows(sender: str, now: float, limits: Limits) -> list[tuple[str, int, int]]:
    return [
        (f"h:{sender}:{int(now // HOUR)}", limits.per_hour, HOUR),
        (f"d:{sender}:{int(now // DAY)}", limits.per_day, DAY),
        (f"g:{int(now // DAY)}", limits.global_per_day, DAY),
    ]


async def check(
    store: Store, sender: str, now: float, limits: Limits = DEFAULT_LIMITS
) -> float | None:
    """Seconds to wait when a limit is reached, else None. Reads only; nothing is counted."""
    for key, limit, span in _windows(sender, now, limits):
        if int(await store.get(key) or 0) >= limit:
            return float(span - (now % span))
    return None


async def count(store: Store, sender: str, now: float, limits: Limits = DEFAULT_LIMITS) -> None:
    """Counts one report in every window."""
    for key, _, span in _windows(sender, now, limits):
        current = int(await store.get(key) or 0)
        await store.put(key, str(current + 1), int(span - (now % span)) + 60)


async def check_and_count(
    store: Store, sender: str, now: float, limits: Limits = DEFAULT_LIMITS
) -> float | None:
    """Counts one report and returns None, or returns seconds to wait when a limit is reached."""
    wait = await check(store, sender, now, limits)
    if wait is None:
        await count(store, sender, now, limits)
    return wait


class MemoryStore:
    """An in-memory Store with expiry, for tests and local runs."""

    def __init__(self, clock) -> None:
        self._data: dict[str, tuple[str, float]] = {}
        self._clock = clock

    async def get(self, key: str) -> str | None:
        value = self._data.get(key)
        if value is None or value[1] <= self._clock():
            return None
        return value[0]

    async def put(self, key: str, value: str, ttl_s: int) -> None:
        self._data[key] = (value, self._clock() + ttl_s)
