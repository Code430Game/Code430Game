"""The GitHub REST calls the relay makes, as the App's installation.

HTTP goes through an injected `Http` callable so the same code runs on Workers (JavaScript
fetch) and in tests (a fake GitHub). The installation token is cached until a minute before it
expires.
"""

from __future__ import annotations

import base64
import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field

from report_relay.keys import Signer, app_jwt
from report_relay.render import marker

# (method, url, headers, body) -> (status, body)
Http = Callable[[str, str, dict[str, str], bytes | None], Awaitable[tuple[int, bytes]]]
API = "https://api.github.com"
RECENT_ISSUES_CHECKED = 50


class GitHubError(RuntimeError):
    def __init__(self, what: str, status: int, body: bytes = b"") -> None:
        super().__init__(f"{what}: GitHub answered {status}")
        self.status = status
        self.body = body[:500]


@dataclass
class GitHub:
    http: Http
    app_id: str
    signer: Signer
    repo: str  # owner/name
    attachments_branch: str = "issue-attachments"
    _token: str = ""
    _token_expires: float = 0.0
    _branch_ready: bool = False
    _installation_id: int = 0
    calls: list[str] = field(
        default_factory=list
    )  # method and path of each call, for logs and tests

    async def _request(
        self, method: str, path: str, token: str, payload: dict | None = None
    ) -> tuple[int, dict | list]:
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "code430-report-relay",
        }
        body = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode("utf-8")
        self.calls.append(f"{method} {path}")
        status, raw = await self.http(method, API + path, headers, body)
        try:
            parsed = json.loads(raw.decode("utf-8")) if raw else {}
        except ValueError:
            parsed = {}
        return status, parsed

    async def token(self, now: float) -> str:
        """An installation token, minted with the App's JWT when the cached one is near expiry."""
        if self._token and now < self._token_expires - 60:
            return self._token
        jwt = await app_jwt(self.app_id, int(now), self.signer)
        if not self._installation_id:
            status, data = await self._request("GET", f"/repos/{self.repo}/installation", jwt)
            if status != 200:
                raise GitHubError("find installation", status)
            self._installation_id = int(data["id"])
        status, data = await self._request(
            "POST", f"/app/installations/{self._installation_id}/access_tokens", jwt, {}
        )
        if status != 201:
            raise GitHubError("mint installation token", status)
        self._token = data["token"]
        self._token_expires = now + 3600  # GitHub's tokens last an hour
        return self._token

    async def find_issue(self, report_id: str, now: float) -> str | None:
        """The URL of an issue already filed for this report id, among the newest reports."""
        status, data = await self._request(
            "GET",
            f"/repos/{self.repo}/issues?labels=in-game-report&state=all&sort=created"
            f"&direction=desc&per_page={RECENT_ISSUES_CHECKED}",
            await self.token(now),
        )
        if status != 200:
            raise GitHubError("list reports", status)
        needle = marker(report_id)
        for issue in data:
            if needle in (issue.get("body") or ""):
                return issue["html_url"]
        return None

    async def _ensure_branch(self, now: float) -> None:
        if self._branch_ready:
            return
        token = await self.token(now)
        status, _ = await self._request(
            "GET", f"/repos/{self.repo}/git/ref/heads/{self.attachments_branch}", token
        )
        if status == 404:
            # An orphan branch: screenshots never share history with the game's code.
            status, tree = await self._request(
                "POST",
                f"/repos/{self.repo}/git/trees",
                token,
                {
                    "tree": [
                        {
                            "path": "README.md",
                            "mode": "100644",
                            "type": "blob",
                            "content": "Screenshots attached to in-game issue reports. Never merged.\n",
                        }
                    ]
                },
            )
            if status != 201:
                raise GitHubError("create attachments tree", status)
            status, commit = await self._request(
                "POST",
                f"/repos/{self.repo}/git/commits",
                token,
                {
                    "message": "Start the issue attachments branch",
                    "tree": tree["sha"],
                    "parents": [],
                },
            )
            if status != 201:
                raise GitHubError("create attachments commit", status)
            status, _ = await self._request(
                "POST",
                f"/repos/{self.repo}/git/refs",
                token,
                {"ref": f"refs/heads/{self.attachments_branch}", "sha": commit["sha"]},
            )
            if status not in (201, 422):  # 422: another request created it first
                raise GitHubError("create attachments branch", status)
        elif status != 200:
            raise GitHubError("find attachments branch", status)
        self._branch_ready = True

    async def put_screenshot(self, report_id: str, jpeg: bytes, now: float) -> str:
        """Commits the screenshot to the attachments branch; returns a URL that renders it."""
        await self._ensure_branch(now)
        path = f"reports/{report_id}.jpg"
        status, _ = await self._request(
            "PUT",
            f"/repos/{self.repo}/contents/{path}",
            await self.token(now),
            {
                "message": f"Screenshot for report {report_id}",
                "content": base64.b64encode(jpeg).decode("ascii"),
                "branch": self.attachments_branch,
            },
        )
        if status not in (200, 201, 422):  # 422: already there from an earlier try
            raise GitHubError("upload screenshot", status)
        return f"https://github.com/{self.repo}/blob/{self.attachments_branch}/{path}?raw=true"

    async def create_issue(self, title: str, body: str, labels: list[str], now: float) -> str:
        status, data = await self._request(
            "POST",
            f"/repos/{self.repo}/issues",
            await self.token(now),
            {"title": title, "body": body, "labels": labels},
        )
        if status != 201:
            raise GitHubError("create issue", status)
        return data["html_url"]
