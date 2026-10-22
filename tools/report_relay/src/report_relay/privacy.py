"""What the relay does to a report before it is posted publicly.

- The reporter id (a random id the player chose to include) is published only as a keyed
  one-way hash: the same install always shows the same hash, so its reports can be grouped, but
  without the relay's secret nobody can get back to the id saved on the player's machine.
- IP addresses and email addresses are scrubbed from the description and the log lines, also
  from older game builds that didn't scrub them.
"""

from __future__ import annotations

import copy
import hashlib
import hmac
import re

REPORTER_HASH_LEN = 12
_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
_IPV4 = re.compile(
    r"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])"
)
# Written out in full (eight groups) or shortened with ::, so clock times (12:34:56) are left alone.
_IPV6 = re.compile(
    r"(?<![\w:])(?=[0-9A-Fa-f:]*::|(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4})(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![\w:])"
)


def reporter_hash(reporter_id: str, secret: str) -> str:
    """The public form of a reporter id: an HMAC-SHA256 of it under the relay's secret, cut short."""
    mac = hmac.new(secret.encode(), f"reporter:{reporter_id}".encode(), hashlib.sha256)
    return mac.hexdigest()[:REPORTER_HASH_LEN]


def scrub(text: str) -> str:
    """`text` with email addresses as <email> and IP addresses as <ip>."""
    text = _EMAIL.sub("<email>", text)
    text = _IPV4.sub("<ip>", text)
    return _IPV6.sub("<ip>", text)


def public(report: dict, secret: str) -> dict:
    """A copy of `report` fit to post: the reporter id hashed, contacts scrubbed."""
    out = copy.deepcopy(report)
    if out.get("reporter_id"):
        # Without a secret the short random id could be found by trying them all: leave it out.
        out["reporter_id"] = reporter_hash(out["reporter_id"], secret) if secret else ""
    out["description"] = scrub(out.get("description", ""))
    out["log_tail"] = [scrub(line) for line in out.get("log_tail", [])]
    return out
