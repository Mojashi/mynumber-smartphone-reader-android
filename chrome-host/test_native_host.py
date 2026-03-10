#!/usr/bin/env python3

from __future__ import annotations

import json
import struct
import subprocess
import sys
from pathlib import Path


HOST = Path(__file__).with_name("nta_chrome_ext_host.py")


def encode_message(message: dict) -> bytes:
    payload = json.dumps(message, ensure_ascii=False).encode("utf-8")
    return struct.pack("<I", len(payload)) + payload


def read_messages(data: bytes) -> list[dict]:
    messages: list[dict] = []
    cursor = 0
    while cursor + 4 <= len(data):
        length = struct.unpack("<I", data[cursor : cursor + 4])[0]
        cursor += 4
        payload = data[cursor : cursor + length]
        cursor += length
        messages.append(json.loads(payload.decode("utf-8")))
    return messages


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: test_native_host.py '{\"MessageType\":\"StartProcess\",\"uid\":\"probe-cli\"}'",
            file=sys.stderr,
        )
        return 2

    request = json.loads(sys.argv[1])
    proc = subprocess.run(
        [sys.executable, str(HOST)],
        input=encode_message(request),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    print(json.dumps(read_messages(proc.stdout), ensure_ascii=False, indent=2))
    if proc.stderr:
        print(proc.stderr.decode("utf-8"), file=sys.stderr, end="")
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
