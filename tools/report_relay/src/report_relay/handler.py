"""The relay's one endpoint: `POST /v1/report`, plus `GET /health` for deploy checks.

Order matters: cheap refusals first (switch, method, size, parsing, schema, image), then the
rate limit is read (a sender over it never reaches GitHub, so replaying one valid body cannot
spend the App's API quota), then the idempotency check, so a game resending a report that was
already filed gets its issue back without being counted, then the count, then GitHub. Nothing
from the report is logged or stored here.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from report_relay import jpeg, multipart, render, validate
from report_relay.github import GitHub, GitHubError
from report_relay.ratelimit import Limits, Store, check, count, sender_key

MAX_BODY_BYTES = 2 * 1024 * 1024
MAX_SHOT = (1920, 1200)
SWITCHED_OFF_RETRY_S = 600


@dataclass
class Request:
    method: str
    path: str
    headers: dict[str, str]  # lower-case names
    body: bytes
    client_ip: str


@dataclass
class Response:
    status: int
    payload: dict
    headers: dict[str, str] = field(default_factory=dict)

    def json(self) -> str:
        return json.dumps(self.payload)


@dataclass
class Config:
    enabled: bool
    salt: str
    limits: Limits = field(default_factory=Limits)
    max_body_bytes: int = MAX_BODY_BYTES


def _refuse(status: int, error: str, **extra) -> Response:
    return Response(status, {"error": error, **extra})


async def handle(req: Request, cfg: Config, github: GitHub, store: Store, now: float) -> Response:
    """Answers one request."""
    if req.path == "/health" and req.method == "GET":
        return Response(200, {"ok": True, "enabled": cfg.enabled})
    if req.path != "/v1/report":
        return _refuse(404, "not found")
    if req.method != "POST":
        return Response(405, {"error": "use POST"}, {"Allow": "POST"})
    if not cfg.enabled:
        return Response(
            503, {"error": "reporting is switched off"}, {"Retry-After": str(SWITCHED_OFF_RETRY_S)}
        )
    if len(req.body) > cfg.max_body_bytes:
        return _refuse(413, "report too large")
    try:
        fields = multipart.parse(req.body, req.headers.get("content-type", ""))
    except multipart.MultipartError as e:
        return _refuse(400, f"bad form data: {e}")
    if "report" not in fields or set(fields) - {"report", "screenshot"}:
        return _refuse(400, "expected the fields report and, optionally, screenshot")
    try:
        report = json.loads(fields["report"].decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return _refuse(400, "report is not JSON")
    problems = validate.errors(report)
    if problems:
        return _refuse(400, "report does not match the schema", details=problems[:5])
    shot = fields.get("screenshot")
    if shot is not None:
        dims = jpeg.size(shot)
        if dims is None:
            return _refuse(400, "screenshot is not a JPEG")
        if dims[0] > MAX_SHOT[0] or dims[1] > MAX_SHOT[1]:
            return _refuse(400, f"screenshot larger than {MAX_SHOT[0]}x{MAX_SHOT[1]}")
    sender = sender_key(req.client_ip, cfg.salt)
    wait = await check(store, sender, now, cfg.limits)
    if wait is not None:
        return Response(
            429, {"error": "too many reports; try later"}, {"Retry-After": str(int(wait) + 1)}
        )
    try:
        existing = await github.find_issue(report["id"], now)
        if existing:
            return Response(200, {"issue_url": existing, "report_id": report["id"]})
        await count(store, sender, now, cfg.limits)
        shot_url = await github.put_screenshot(report["id"], shot, now) if shot else None
        url = await github.create_issue(
            render.title(report), render.body(report, shot_url), render.labels(report), now
        )
    except GitHubError as e:
        # The step and GitHub's status only; never the report's content.
        print(f"relay: {e} ({e.body[:200]!r})")
        return _refuse(502, "GitHub refused the report", step=str(e))
    return Response(201, {"issue_url": url, "report_id": report["id"]})
