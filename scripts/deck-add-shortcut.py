# /// script
# requires-python = ">=3.11"
# dependencies = ["vdf>=3.4"]
# ///
"""Add (or update) the Code 430 non-Steam shortcut on a Steam Deck over SSH.

Usage: uv run scripts/deck-add-shortcut.py [host]
Downloads <userdata>/config/shortcuts.vdf (or starts a new one), upserts an entry
pointing at ~/Games/code430/code430.x86_64, and uploads it. Backs up the existing
file first. Steam reads the file only at startup, so restart the Deck (Power >
Restart) afterwards; the entry then appears under the Non-Steam tab in Game Mode.
"""

from __future__ import annotations

import subprocess
import sys
import time
import zlib
from pathlib import Path

HOST = sys.argv[1] if len(sys.argv) > 1 else "steamdeck.local"
APP_NAME = "Code 430"
EXE = "/home/deck/Games/code430/code430.x86_64"
START_DIR = "/home/deck/Games/code430/"
LOCAL = Path("/tmp/code430_shortcuts.vdf")


def ssh(cmd: str) -> str:
    return subprocess.run(["ssh", f"deck@{HOST}", cmd], check=True, capture_output=True, text=True).stdout.strip()


def steam_app_id(exe: str, name: str) -> int:
    """Steam's non-Steam app id: crc32 of exe+name with the high bit set, stored as a signed int32."""
    unsigned = (zlib.crc32((exe + name).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF
    return unsigned - 0x100000000 if unsigned >= 0x80000000 else unsigned


def main() -> int:
    import vdf

    users = ssh("ls -d ~/.steam/steam/userdata/*/ | grep -v '/0/'").splitlines()
    if len(users) != 1:
        print(f"expected one Steam user on the Deck, found {users}")
        return 1
    remote = users[0].rstrip("/") + "/config/shortcuts.vdf"
    exists = ssh(f"test -f {remote} && echo yes || echo no") == "yes"
    data: dict = {"shortcuts": {}}
    if exists:
        subprocess.run(["scp", "-q", f"deck@{HOST}:{remote}", str(LOCAL)], check=True)
        ssh(f"cp {remote} {remote}.bak-{int(time.time())}")
        data = vdf.binary_loads(LOCAL.read_bytes())
    shortcuts = data.setdefault("shortcuts", {})
    entry = {
        "appid": steam_app_id(f'"{EXE}"', APP_NAME),
        "AppName": APP_NAME,
        "Exe": f'"{EXE}"',
        "StartDir": f'"{START_DIR}"',
        "icon": "",
        "ShortcutPath": "",
        "LaunchOptions": "",
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime": 0,
        "FlatpakAppID": "",
        "tags": {},
    }
    for key, existing in shortcuts.items():
        if existing.get("AppName") == APP_NAME:
            shortcuts[key] = entry
            break
    else:
        shortcuts[str(len(shortcuts))] = entry
    LOCAL.write_bytes(vdf.binary_dumps(data))
    subprocess.run(["scp", "-q", str(LOCAL), f"deck@{HOST}:{remote}"], check=True)
    print(f"wrote {remote} with {len(shortcuts)} shortcut(s); app id {entry['appid']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
