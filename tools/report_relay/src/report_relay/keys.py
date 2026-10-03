"""The GitHub App's private key and the JWT that proves the relay is that App.

GitHub hands out keys as PKCS#1 PEM ("BEGIN RSA PRIVATE KEY"); Web Crypto, which signs on
Workers, imports only PKCS#8. `pkcs8_der` accepts either and returns PKCS#8 DER by wrapping the
PKCS#1 key in the fixed rsaEncryption header. Signing itself is passed in (`signer`).
"""

from __future__ import annotations

import base64
import json
from collections.abc import Awaitable, Callable

Signer = Callable[[bytes], Awaitable[bytes]]

# AlgorithmIdentifier { rsaEncryption, NULL }
_RSA_ALGORITHM = bytes.fromhex("300d06092a864886f70d0101010500")


def _der_length(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def _pem_body(pem: str) -> tuple[str, bytes]:
    lines = [line.strip() for line in pem.strip().splitlines()]
    if (
        len(lines) < 3
        or not lines[0].startswith("-----BEGIN ")
        or not lines[-1].startswith("-----END ")
    ):
        raise ValueError("not a PEM block")
    kind = lines[0][len("-----BEGIN ") :].rstrip("-")
    return kind, base64.b64decode("".join(lines[1:-1]))


def pkcs8_der(pem: str) -> bytes:
    """PKCS#8 DER for a PKCS#1 or PKCS#8 PEM private key."""
    kind, der = _pem_body(pem)
    if kind == "PRIVATE KEY":
        return der
    if kind != "RSA PRIVATE KEY":
        raise ValueError(f"unsupported key type {kind}")
    octets = b"\x04" + _der_length(len(der)) + der
    inner = b"\x02\x01\x00" + _RSA_ALGORITHM + octets
    return b"\x30" + _der_length(len(inner)) + inner


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


async def app_jwt(app_id: str, now: int, signer: Signer) -> str:
    """An RS256 JWT for the App, valid for nine minutes (GitHub allows ten), backdated a minute."""
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64url(
        json.dumps(
            {"iat": now - 60, "exp": now + 540, "iss": str(app_id)}, separators=(",", ":")
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode("ascii")
    return f"{header}.{payload}.{_b64url(await signer(signing_input))}"
