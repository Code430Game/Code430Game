"""The report relay: validation, form parsing, images, keys, rendering and the endpoint itself.

GitHub is a fake in memory; nothing here touches the network.
"""

from __future__ import annotations

import asyncio
import base64
import copy
import json
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from jsonschema import Draft202012Validator
from report_relay.github import GitHub
from report_relay.handler import Config, Request, handle
from report_relay.ratelimit import Limits, MemoryStore, sender_key

from report_relay import jpeg, keys, multipart, render, validate

HERE = Path(__file__).parent
REPO_ROOT = HERE.parents[1]
EXAMPLE = json.loads((HERE / "fixtures" / "report_example.v1.json").read_text(encoding="utf-8"))
T0 = 1_791_023_700.0


def run(coro):
    return asyncio.run(coro)


def tiny_jpeg(width: int, height: int, progressive: bool = False) -> bytes:
    """SOI, an APP0 segment, a frame header with the size, EOI: enough for jpeg.size."""
    app0 = b"\xff\xe0" + (16).to_bytes(2, "big") + b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    sof = (
        (b"\xff\xc2" if progressive else b"\xff\xc0")
        + (11).to_bytes(2, "big")
        + b"\x08"
        + height.to_bytes(2, "big")
        + width.to_bytes(2, "big")
        + b"\x01\x01\x11\x00"
    )
    return b"\xff\xd8" + app0 + sof + b"\xff\xd9"


def form(
    report: dict | None, shot: bytes | None = None, boundary: str = "code430-abc"
) -> tuple[bytes, str]:
    """A multipart body shaped exactly like RelayClient.multipart_body in the game."""
    body = b""
    if report is not None:
        body += (
            (
                f'--{boundary}\r\nContent-Disposition: form-data; name="report"\r\n'
                "Content-Type: application/json\r\n\r\n"
            ).encode()
            + json.dumps(report).encode()
            + b"\r\n"
        )
    if shot is not None:
        body += (
            (
                f'--{boundary}\r\nContent-Disposition: form-data; name="screenshot"; '
                'filename="screenshot.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'
            ).encode()
            + shot
            + b"\r\n"
        )
    body += f"--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


# --- schema and validation -------------------------------------------------------------------


def test_packaged_schema_is_the_documented_one():
    docs = (REPO_ROOT / "docs" / "report-format" / "report.schema.v1.json").read_text(
        encoding="utf-8"
    )
    assert json.loads(docs) == validate.load_schema(), (
        "report_relay/schema_v1.py is out of date: paste docs/report-format/report.schema.v1.json into it"
    )


MUTATIONS = [
    (("area",), "bugs"),
    (("severity",), "urgent"),
    (("title",), ""),
    (("title",), "x" * 121),
    (("id",), "not-an-id"),
    (("version",), 2),
    (("has_screenshot",), "yes"),
    (("log_tail",), ["x"] * 201),
    (("diagnostics", "session", "role"), "spectator"),
    (("diagnostics", "machine", "cpu_count"), 2.5),
    (("diagnostics", "machine", "resolution"), [1280]),
    (("diagnostics", "place", "x"), "237"),
    (("diagnostics", "frame_time", "avg_ms"), -1),
    (("reporter_id",), "Ryan"),
]


def mutated(path, value):
    report = copy.deepcopy(EXAMPLE)
    target = report
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value
    return report


def test_example_report_is_valid():
    assert validate.errors(EXAMPLE) == []


@pytest.mark.parametrize(("path", "value"), MUTATIONS)
def test_validator_agrees_with_jsonschema(path, value):
    report = mutated(path, value)
    expected = list(Draft202012Validator(validate.load_schema()).iter_errors(report))
    assert expected, "the mutation should break the schema"
    assert validate.errors(report), f"relay accepted {path}={value!r}"


def test_unknown_and_missing_keys_are_errors():
    report = copy.deepcopy(EXAMPLE)
    report["extra"] = 1
    del report["diagnostics"]["build"]["commit"]
    errs = validate.errors(report)
    assert any("unknown key extra" in e for e in errs)
    assert any("missing commit" in e for e in errs)


# --- multipart and images --------------------------------------------------------------------


def test_multipart_round_trip():
    shot = tiny_jpeg(1280, 800)
    body, ctype = form(EXAMPLE, shot)
    fields = multipart.parse(body, ctype)
    assert json.loads(fields["report"]) == EXAMPLE
    assert fields["screenshot"] == shot


@pytest.mark.parametrize(
    ("body", "ctype"),
    [
        (b"--x\r\nno headers\r\n--x--\r\n", "multipart/form-data; boundary=x"),
        (
            b'--x\r\nContent-Disposition: form-data; name="a"\r\n\r\nv\r\n',
            "multipart/form-data; boundary=x",
        ),
        (b"", "application/json"),
        (b"--x--\r\n", "multipart/form-data"),
    ],
)
def test_malformed_multipart_is_refused(body, ctype):
    with pytest.raises(multipart.MultipartError):
        multipart.parse(body, ctype)


def test_jpeg_size():
    assert jpeg.size(tiny_jpeg(1280, 800)) == (1280, 800)
    assert jpeg.size(tiny_jpeg(640, 400, progressive=True)) == (640, 400)
    assert jpeg.size(b"\x89PNG\r\n\x1a\n") is None
    assert jpeg.size(b"\xff\xd8\xff\xda\x00\x02") is None


# --- keys and the App token ------------------------------------------------------------------


@pytest.fixture(scope="module")
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def test_pkcs1_key_is_wrapped_as_pkcs8(rsa_key):
    pkcs1 = rsa_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption(),
    ).decode()
    assert pkcs1.startswith("-----BEGIN RSA PRIVATE KEY-----")
    loaded = serialization.load_der_private_key(keys.pkcs8_der(pkcs1), password=None)
    assert loaded.private_numbers() == rsa_key.private_numbers()
    pkcs8 = rsa_key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    assert keys.pkcs8_der(pkcs8) == rsa_key.private_bytes(
        serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    )


def test_app_jwt_is_signed_rs256_with_github_claims(rsa_key):
    async def signer(data: bytes) -> bytes:
        return rsa_key.sign(data, padding.PKCS1v15(), hashes.SHA256())

    token = run(keys.app_jwt("12345", int(T0), signer))
    header_b64, payload_b64, sig_b64 = token.split(".")
    pad = lambda s: s + "=" * (-len(s) % 4)
    assert json.loads(base64.urlsafe_b64decode(pad(header_b64))) == {"alg": "RS256", "typ": "JWT"}
    claims = json.loads(base64.urlsafe_b64decode(pad(payload_b64)))
    assert claims == {"iat": int(T0) - 60, "exp": int(T0) + 540, "iss": "12345"}
    rsa_key.public_key().verify(
        base64.urlsafe_b64decode(pad(sig_b64)),
        f"{header_b64}.{payload_b64}".encode(),
        padding.PKCS1v15(),
        hashes.SHA256(),
    )


# --- rendering -------------------------------------------------------------------------------


def test_defuse_breaks_mentions_html_and_links():
    out = render.defuse("@rjksn look <script>x</script> at https://evil.example/a?b=1")
    assert "@\u200brjksn" in out
    assert "<script>" not in out and "&lt;script&gt;" in out
    assert "`https://evil.example/a?b=1`" in out


def test_body_has_screenshot_ids_diagnostics_and_marker():
    report = copy.deepcopy(EXAMPLE)
    report["reporter_id"] = "3fa9c2d1"
    text = render.body(
        report, "https://github.com/rjksn/Code430/blob/issue-attachments/reports/x.jpg?raw=true"
    )
    assert (
        "![screenshot](https://github.com/rjksn/Code430/blob/issue-attachments/reports/x.jpg?raw=true)"
        in text
    )
    assert "junction `c901050337`" in text and "edge `w435115744.0`" in text
    assert "Reporter id `3fa9c2d1`" in text
    assert "<details><summary>Diagnostics</summary>" in text
    assert render.marker(report["id"]) in text
    comment = text.split("<!-- code430-report ", 1)[1].rsplit(" -->", 1)[0]
    assert "--" not in comment
    assert json.loads(comment)["id"] == report["id"]


def test_untrusted_ids_cannot_escape_inline_code():
    report = copy.deepcopy(EXAMPLE)
    report["diagnostics"]["place"]["edge_id"] = "w1` <img src=x>"
    text = render.body(report, None)
    assert "edge `w1 <img src=x>`" in text


def test_long_log_is_trimmed_to_fit_but_the_marker_stays():
    report = copy.deepcopy(EXAMPLE)
    report["log_tail"] = ["x" * 499] * 200
    report["description"] = "d" * 4000
    text = render.body(report, None)
    assert len(text) <= render.BODY_LIMIT
    assert render.marker(report["id"]) in text
    assert text.count("x" * 499) < 200


def test_labels_and_title():
    assert render.labels(EXAMPLE) == [
        "in-game-report",
        "needs-triage",
        "area:roads",
        "severity:annoying",
    ]
    report = copy.deepcopy(EXAMPLE)
    report["title"] = "  @team broken  "
    assert render.title(report) == "@\u200bteam broken"


def test_tags_are_optional_and_become_labels_and_a_body_line():
    # The example has no tags: labels and body are as before (an untagged report is unchanged).
    assert "tags" not in EXAMPLE
    assert "**Tags:**" not in render.body(EXAMPLE, None)
    report = copy.deepcopy(EXAMPLE)
    report["tags"] = ["stuck", "fell_through"]
    report["description"] = ""
    assert validate.errors(report) == []
    assert render.labels(report)[-2:] == ["tag:stuck", "tag:fell_through"]
    text = render.body(report, None)
    assert "**Tags:** Stuck, Fell through" in text
    # The tags line is its own paragraph, not run into the area line.
    assert "\n\n**Tags:**" in text


@pytest.mark.parametrize("tags", [["Stuck"], ["has space"], ["x" * 25], ["a"] * 9, "stuck"])
def test_bad_tags_are_refused(tags):
    report = copy.deepcopy(EXAMPLE)
    report["tags"] = tags
    assert list(Draft202012Validator(validate.load_schema()).iter_errors(report))
    assert validate.errors(report)


def test_game_tag_labels_follow_the_relay_rule():
    table = json.loads(
        (REPO_ROOT / "game" / "ui" / "report" / "report_tags.json").read_text(encoding="utf-8")
    )
    for tag in table["tags"]:
        assert render.tag_name(tag["id"]) == tag["label"]


# --- the endpoint, against a fake GitHub -----------------------------------------------------


class FakeGitHub:
    """Just enough of api.github.com: installation, tokens, issues, git refs and contents."""

    def __init__(self) -> None:
        self.issues: list[dict] = []
        self.files: dict[str, bytes] = {}
        self.branch_exists = False
        self.tokens_minted = 0
        self.fail_create = False
        self.conflicts = 0  # how many screenshot commits answer 409 before one lands
        self.lookups = 0  # issue listings, the call a replayed report must not reach

    async def __call__(self, method, url, headers, body):
        path = url.removeprefix("https://api.github.com")
        payload = json.loads(body) if body else {}
        ok = lambda status, data: (status, json.dumps(data).encode())
        if path == "/repos/rjksn/Code430/installation":
            assert (
                headers["Authorization"].startswith("Bearer ")
                and headers["Authorization"].count(".") == 2
            )
            return ok(200, {"id": 77})
        if path == "/app/installations/77/access_tokens":
            self.tokens_minted += 1
            return ok(201, {"token": f"ghs_{self.tokens_minted}"})
        assert headers["Authorization"].startswith("Bearer ghs_"), path
        if path.startswith("/repos/rjksn/Code430/issues?"):
            assert "labels=in-game-report" in path
            self.lookups += 1
            return ok(200, list(reversed(self.issues)))
        if path == "/repos/rjksn/Code430/issues" and method == "POST":
            if self.fail_create:
                return ok(500, {})
            issue = {
                "html_url": f"https://github.com/rjksn/Code430/issues/{len(self.issues) + 1}",
                **payload,
            }
            self.issues.append(issue)
            return ok(201, issue)
        if path == "/repos/rjksn/Code430/git/ref/heads/issue-attachments":
            return ok(200 if self.branch_exists else 404, {})
        if path == "/repos/rjksn/Code430/git/trees":
            return ok(201, {"sha": "tree1"})
        if path == "/repos/rjksn/Code430/git/commits":
            assert payload["parents"] == []
            return ok(201, {"sha": "commit1"})
        if path == "/repos/rjksn/Code430/git/refs":
            self.branch_exists = True
            return ok(201, {})
        if path.startswith("/repos/rjksn/Code430/contents/reports/") and method == "PUT":
            assert self.branch_exists and payload["branch"] == "issue-attachments"
            if self.conflicts:
                self.conflicts -= 1
                return ok(409, {"message": "is at abc but expected def"})
            name = path.rsplit("/", 1)[1]
            if name in self.files:
                return ok(422, {})
            self.files[name] = base64.b64decode(payload["content"])
            return ok(201, {})
        raise AssertionError(f"unexpected {method} {path}")


class Relay:
    def __init__(self, enabled: bool = True, limits: Limits | None = None) -> None:
        self.now = T0
        self.gh_fake = FakeGitHub()

        async def signer(data: bytes) -> bytes:
            return b"sig"

        self.github = GitHub(
            http=self.gh_fake, app_id="1", signer=signer, repo="rjksn/Code430", retry_delay_s=0.0
        )
        self.store = MemoryStore(lambda: self.now)
        self.cfg = Config(enabled=enabled, salt="pepper", limits=limits or Limits())

    def post(self, report, shot=None, ip="203.0.113.7", path="/v1/report", method="POST", raw=None):
        body, ctype = (
            (raw, "multipart/form-data; boundary=x") if raw is not None else form(report, shot)
        )
        req = Request(
            method=method, path=path, headers={"content-type": ctype}, body=body, client_ip=ip
        )
        return run(handle(req, self.cfg, self.github, self.store, self.now))


def report_with_id(n: int) -> dict:
    report = copy.deepcopy(EXAMPLE)
    report["id"] = f"20261003T101500Z-{n:08x}"
    return report


def test_health_and_routing():
    relay = Relay()
    assert relay.post(None, path="/health", method="GET").payload == {"ok": True, "enabled": True}
    assert relay.post(EXAMPLE, path="/v1/other").status == 404
    resp = relay.post(EXAMPLE, method="GET")
    assert resp.status == 405 and resp.headers["Allow"] == "POST"


def test_switched_off_relay_says_when_to_retry():
    resp = Relay(enabled=False).post(EXAMPLE)
    assert resp.status == 503 and int(resp.headers["Retry-After"]) > 0


def test_report_is_filed_with_screenshot_labels_and_marker():
    relay = Relay()
    resp = relay.post(EXAMPLE, tiny_jpeg(1280, 800))
    assert resp.status == 201
    assert resp.payload == {
        "issue_url": "https://github.com/rjksn/Code430/issues/1",
        "report_id": EXAMPLE["id"],
    }
    issue = relay.gh_fake.issues[0]
    assert issue["title"] == EXAMPLE["title"]
    assert issue["labels"] == ["in-game-report", "needs-triage", "area:roads", "severity:annoying"]
    assert f"reports/{EXAMPLE['id']}.jpg?raw=true" in issue["body"]
    assert render.marker(EXAMPLE["id"]) in issue["body"]
    assert relay.gh_fake.files[f"{EXAMPLE['id']}.jpg"] == tiny_jpeg(1280, 800)


def test_branch_and_token_are_set_up_once():
    relay = Relay()
    relay.post(report_with_id(1), tiny_jpeg(64, 40))
    relay.post(report_with_id(2), tiny_jpeg(64, 40))
    assert relay.github.calls.count("POST /repos/rjksn/Code430/git/refs") == 1
    assert relay.gh_fake.tokens_minted == 1
    relay.now += 3600  # the token has expired
    relay.post(report_with_id(3))
    assert relay.gh_fake.tokens_minted == 2


def test_resent_report_returns_the_same_issue_and_does_not_count():
    relay = Relay(limits=Limits(per_hour=2))
    first = relay.post(EXAMPLE, tiny_jpeg(64, 40))
    again = relay.post(EXAMPLE, tiny_jpeg(64, 40))
    assert first.status == 201 and again.status == 200
    assert again.payload["issue_url"] == first.payload["issue_url"]
    assert len(relay.gh_fake.issues) == 1
    # The resend was not counted: a second distinct report still fits under the limit of two.
    assert relay.post(report_with_id(1)).status == 201


def test_a_sender_over_the_limit_never_reaches_github():
    # Replaying one valid body used to cost an authenticated issue listing per request before
    # the limit was looked at, enough to burn the App's API quota from one address.
    relay = Relay(limits=Limits(per_hour=1))
    assert relay.post(EXAMPLE).status == 201
    lookups = relay.gh_fake.lookups
    for _ in range(5):
        resp = relay.post(EXAMPLE)
        assert resp.status == 429 and "Retry-After" in resp.headers
    assert relay.gh_fake.lookups == lookups


def test_sixth_report_in_an_hour_is_refused_with_retry_after():
    relay = Relay()
    for n in range(5):
        assert relay.post(report_with_id(n)).status == 201
    resp = relay.post(report_with_id(5))
    assert resp.status == 429
    assert 0 < int(resp.headers["Retry-After"]) <= 3601
    assert relay.post(report_with_id(6), ip="198.51.100.1").status == 201  # another sender
    relay.now += 3600
    assert relay.post(report_with_id(7)).status == 201


def test_global_daily_ceiling():
    relay = Relay(limits=Limits(per_hour=100, per_day=100, global_per_day=3))
    for n in range(3):
        assert relay.post(report_with_id(n), ip=f"198.51.100.{n}").status == 201
    assert relay.post(report_with_id(3), ip="198.51.100.9").status == 429


def test_rate_limit_keys_never_contain_the_ip():
    relay = Relay()
    relay.post(EXAMPLE, ip="203.0.113.7")
    keys_seen = list(relay.store._data)
    assert keys_seen and all("203.0.113.7" not in k for k in keys_seen)
    assert sender_key("203.0.113.7", "pepper") != sender_key("203.0.113.7", "salt")


@pytest.mark.parametrize(
    ("kwargs", "status"),
    [
        ({"raw": b"not multipart"}, 400),
        ({"report": None, "shot": tiny_jpeg(64, 40)}, 400),
        ({"report": mutated(("area",), "bugs")}, 400),
        ({"report": EXAMPLE, "shot": b"\x89PNG\r\n\x1a\n"}, 400),
        ({"report": EXAMPLE, "shot": tiny_jpeg(4000, 3000)}, 400),
    ],
)
def test_bad_requests_are_refused_before_github(kwargs, status):
    relay = Relay()
    report = kwargs.pop("report", EXAMPLE)
    resp = relay.post(report, **kwargs)
    assert resp.status == status
    assert relay.github.calls == []


def test_schema_errors_are_listed():
    resp = Relay().post(mutated(("severity",), "urgent"))
    assert resp.status == 400 and any("severity" in d for d in resp.payload["details"])


def test_oversized_request_is_413():
    relay = Relay()
    relay.cfg.max_body_bytes = 100
    assert relay.post(EXAMPLE).status == 413


def test_github_failure_is_502_so_the_game_backs_off():
    relay = Relay()
    relay.gh_fake.fail_create = True
    resp = relay.post(EXAMPLE)
    assert resp.status == 502 and "create issue" in resp.payload["step"]


def test_screenshot_commit_retries_when_reports_race_on_the_branch():
    relay = Relay()
    relay.gh_fake.conflicts = 2
    assert relay.post(EXAMPLE, tiny_jpeg(64, 40)).status == 201
    assert (
        relay.github.calls.count(f"PUT /repos/rjksn/Code430/contents/reports/{EXAMPLE['id']}.jpg")
        == 3
    )


def test_persistent_conflict_is_a_502():
    relay = Relay()
    relay.gh_fake.conflicts = 10
    resp = relay.post(EXAMPLE, tiny_jpeg(64, 40))
    assert resp.status == 502 and "upload screenshot" in resp.payload["step"]


def test_machine_row_names_the_os_once():
    text = render.body(EXAMPLE, None)
    assert "SteamOS (Linux) 3.7" in text
    mac = copy.deepcopy(EXAMPLE)
    mac["diagnostics"]["machine"].update(os="macOS", distribution="macOS", os_version="14.5.0")
    assert "| Machine | macOS 14.5.0," in render.body(mac, None)


def test_whole_numbers_read_back_as_floats_print_as_integers():
    report = copy.deepcopy(EXAMPLE)
    m = report["diagnostics"]["machine"]
    m.update(cpu_count=8.0, memory_mb=14809.0, resolution=[1280.0, 800.0])
    text = render.body(report, None)
    assert "×8," in text and "14809 MB" in text and "1280×800" in text
    assert validate.errors(report) == []
