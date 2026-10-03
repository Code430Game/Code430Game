"""Cloudflare Python Worker entry point for the report relay.

Only glue lives here: JavaScript fetch for HTTP, Web Crypto for signing with the App key, and a
KV namespace for rate limits. The behaviour is in `report_relay.handler`, which the tools tests
cover; this file is exercised by the deploy check (`GET /health`) and the first real report.

Configuration (see README.md): vars APP_ID, REPO, RELAY_ENABLED; secrets PRIVATE_KEY (the App's
PEM key) and RATE_SALT; KV binding REPORT_LIMITS.
"""

import time
from urllib.parse import urlparse

from js import Object, Uint8Array, crypto
from js import fetch as js_fetch
from pyodide.ffi import to_js
from report_relay.github import GitHub
from report_relay.handler import Config, Request, handle
from report_relay.keys import pkcs8_der
from workers import Response, WorkerEntrypoint

_github: GitHub | None = None  # reused while the isolate lives, so the token cache helps


def _js(value):
    return to_js(value, dict_converter=Object.fromEntries)


async def _http(method: str, url: str, headers: dict, body: bytes | None) -> tuple[int, bytes]:
    init = {"method": method, "headers": headers}
    if body is not None:
        init["body"] = Uint8Array.new(to_js(body))
    resp = await js_fetch(url, _js(init))
    raw = await resp.arrayBuffer()
    return int(resp.status), bytes(Uint8Array.new(raw).to_py())


def _setting(env, name: str) -> str:
    """A var or secret as a string; empty when it is not set."""
    value = getattr(env, name, None)
    return "" if value is None else str(value)


def _signer(pem_of):
    key_holder = {}

    async def sign(data: bytes) -> bytes:
        if "key" not in key_holder:
            der = Uint8Array.new(to_js(pkcs8_der(pem_of())))
            key_holder["key"] = await crypto.subtle.importKey(
                "pkcs8",
                der.buffer,
                _js({"name": "RSASSA-PKCS1-v1_5", "hash": "SHA-256"}),
                False,
                _js(["sign"]),
            )
        sig = await crypto.subtle.sign(
            "RSASSA-PKCS1-v1_5", key_holder["key"], Uint8Array.new(to_js(data))
        )
        return bytes(Uint8Array.new(sig).to_py())

    return sign


class _KV:
    def __init__(self, ns) -> None:
        self._ns = ns

    async def get(self, key: str):
        value = await self._ns.get(key)
        return None if value is None else str(value)

    async def put(self, key: str, value: str, ttl_s: int) -> None:
        await self._ns.put(key, value, _js({"expirationTtl": max(60, int(ttl_s))}))


class Default(WorkerEntrypoint):
    async def fetch(self, request):
        global _github
        env = self.env
        if _github is None:
            # Settings are read lazily: /health answers even before the secrets are set.
            _github = GitHub(
                http=_http,
                app_id=_setting(env, "APP_ID"),
                signer=_signer(lambda: _setting(env, "PRIVATE_KEY")),
                repo=_setting(env, "REPO"),
            )
        # The SDK wraps the request; the JavaScript object underneath has the raw body.
        js_req = getattr(request, "js_object", request)
        body = bytes(Uint8Array.new(await js_req.arrayBuffer()).to_py())
        headers = {"content-type": str(js_req.headers.get("content-type") or "")}
        req = Request(
            method=str(js_req.method),
            path=urlparse(str(js_req.url)).path,
            headers=headers,
            body=body,
            client_ip=str(js_req.headers.get("cf-connecting-ip") or ""),
        )
        cfg = Config(
            enabled=_setting(env, "RELAY_ENABLED").lower() == "true",
            salt=_setting(env, "RATE_SALT"),
        )
        resp = await handle(
            req, cfg, _github, _KV(getattr(env, "REPORT_LIMITS", None)), time.time()
        )
        return Response(
            resp.json(),
            status=resp.status,
            headers={"Content-Type": "application/json", **resp.headers},
        )
