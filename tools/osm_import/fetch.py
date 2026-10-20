"""Fetch an OSM extract for a bbox from the Overpass API, with an on-disk cache.

Cache key is a hash of the query text. A sidecar .meta.json records the endpoint,
the query, and the fetch time so the output can cite its source.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

from osm_import.osm_data import BBox, OsmData

log = logging.getLogger(__name__)

USER_AGENT = "code430-osm-import/0.1 (+https://github.com/Code430Game/Code430Game)"
DEFAULT_ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
)
# Download cache: CODE430_OSM_CACHE points it at a shared or external volume so several
# machines reuse the same extracts and DEM tiles; otherwise it sits beside the package.
DEFAULT_CACHE_DIR = Path(os.environ.get("CODE430_OSM_CACHE") or Path(__file__).with_name(".cache"))
RETRY_DELAY_S = 5.0
TIMEOUT_S = 240


def overpass_query(bbox: BBox) -> str:
    """All highway ways in the bbox with their nodes."""
    # Node tags are needed too: traffic_signals, stop and crossing live on nodes.
    return f'[out:json][timeout:180];(way["highway"]({bbox.overpass()}););out body;>;out body qt;'


def _cache_paths(cache_dir: Path, query: str) -> tuple[Path, Path]:
    digest = hashlib.sha1(query.encode("utf-8")).hexdigest()[:16]
    return cache_dir / f"overpass_{digest}.json", cache_dir / f"overpass_{digest}.meta.json"


def fetch_bbox(
    bbox: BBox,
    cache_dir: Path = DEFAULT_CACHE_DIR,
    endpoints: tuple[str, ...] = DEFAULT_ENDPOINTS,
    attempts_per_endpoint: int = 2,
) -> OsmData:
    """Return the highway OSM data for bbox, from cache if present, else from Overpass."""
    payload, meta = fetch_query(
        overpass_query(bbox), bbox, cache_dir, endpoints, attempts_per_endpoint
    )
    return OsmData.from_overpass_json(payload, meta)


def fetch_query(
    query: str,
    bbox: BBox,
    cache_dir: Path = DEFAULT_CACHE_DIR,
    endpoints: tuple[str, ...] = DEFAULT_ENDPOINTS,
    attempts_per_endpoint: int = 2,
) -> tuple[dict, dict]:
    """Return (payload, source meta) for any Overpass query, cached by query text."""
    data_path, meta_path = _cache_paths(cache_dir, query)
    if data_path.is_file() and meta_path.is_file():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        log.info("using cached extract %s (fetched %s)", data_path.name, meta.get("fetched_at"))
        payload = json.loads(data_path.read_text(encoding="utf-8"))
        return payload, meta

    cache_dir.mkdir(parents=True, exist_ok=True)
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    last_error: Exception | None = None
    for endpoint in endpoints:
        for attempt in range(attempts_per_endpoint):
            req = urllib.request.Request(endpoint, data=body, headers={"User-Agent": USER_AGENT})
            try:
                log.info("fetching %s from %s (attempt %d)", bbox.overpass(), endpoint, attempt + 1)
                with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
                    raw = resp.read()
                payload = json.loads(raw)
                if "elements" not in payload:
                    raise ValueError("Overpass response has no 'elements'")
                fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
                meta = {
                    "kind": "overpass",
                    "url": endpoint,
                    "query": query,
                    "bbox": bbox.as_list(),
                    "fetched_at": fetched_at,
                    "osm_base_timestamp": payload.get("osm3s", {}).get("timestamp_osm_base"),
                    "license": "ODbL-1.0",
                    "attribution": "© OpenStreetMap contributors",
                }
                data_path.write_bytes(raw)
                meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
                log.info("cached %d bytes to %s", len(raw), data_path)
                return payload, meta
            except (urllib.error.URLError, urllib.error.HTTPError, ValueError, TimeoutError) as exc:
                last_error = exc
                log.warning("fetch failed: %s", exc)
                time.sleep(RETRY_DELAY_S)
    raise RuntimeError(f"Overpass fetch failed for {bbox.overpass()}: {last_error}")
