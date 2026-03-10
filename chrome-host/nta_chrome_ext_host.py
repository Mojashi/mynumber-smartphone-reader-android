#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlencode


LOG_PATH = Path.home() / "Library/Logs/mynumber-bridge/nta.chrome.ext.log"
APP_GROUP_ROOT = Path.home() / "Library/Group Containers/jp.go.nta.eTaxWebGroup"
HOST_TIMEOUT_SECONDS = float(os.environ.get("NTA_HOST_TIMEOUT_SECONDS", "30"))
CHUNK_SIZE = int(os.environ.get("NTA_HOST_CHUNK_SIZE", "3500"))

# Direct message names exposed by the macOS e-Tax container app.
DIRECT_MESSAGE_FIELDS: dict[str, tuple[str, ...]] = {
    "StartProcess": tuple(),
    "PollingProcess": tuple(),
    "EndProcess": tuple(),
    "SignRelease": tuple(),
    "SignLoadInfomation": ("password",),
    "SignSetCertificateICCard": ("cspName", "password"),
    "SignSetCertificateP12": ("filePath", "password"),
    "SignToReport": ("reportData", "userID"),
    "SignToReportEltax": ("reportData",),
    "SignToCertificateRegistration": ("certRegData", "userID"),
}

# Heuristics for Chrome-side message names when args1/args2 are used.
ARG_MAPPED_MESSAGES: dict[str, tuple[str, tuple[str, ...]]] = {
    "StartProcess": ("StartProcess", tuple()),
    "PollingProcess": ("PollingProcess", tuple()),
    "EndProcess": ("EndProcess", tuple()),
    "SignRelease": ("SignRelease", tuple()),
    "SignLoadInfomation": ("SignLoadInfomation", ("password",)),
    "SignSetCertificateICCard": ("SignSetCertificateICCard", ("cspName", "password")),
    "SignSetCertificateP12": ("SignSetCertificateP12", ("filePath", "password")),
    "SignToReport": ("SignToReport", ("reportData", "userID")),
    "SignToReportEltax": ("SignToReportEltax", ("reportData",)),
    "SignToCertificateRegistration": (
        "SignToCertificateRegistration",
        ("certRegData", "userID"),
    ),
}


def log_line(message: str) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    with LOG_PATH.open("a", encoding="utf-8") as fh:
        fh.write(f"[{timestamp}] {message}\n")


def read_native_message() -> dict | None:
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        return None
    if len(raw_length) != 4:
        log_line(f"short length prefix: {raw_length!r}")
        return None
    message_length = struct.unpack("<I", raw_length)[0]
    payload = sys.stdin.buffer.read(message_length)
    if len(payload) != message_length:
        log_line(f"short payload: expected={message_length} got={len(payload)}")
        return None
    decoded = payload.decode("utf-8")
    log_line(f"recv {decoded}")
    return json.loads(decoded)


def write_native_message(message: str) -> None:
    payload = message.encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(payload)))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()
    log_line(f"send {message}")


def write_chunked_response(payload: dict[str, Any]) -> None:
    encoded = quote(json.dumps(payload, ensure_ascii=False), safe="")
    if not encoded:
        write_native_message(json.dumps({"JSONDATA": ""}, ensure_ascii=False))
        return
    for offset in range(0, len(encoded), CHUNK_SIZE):
        chunk = encoded[offset : offset + CHUNK_SIZE]
        write_native_message(json.dumps({"JSONDATA": chunk}, ensure_ascii=False))
    write_native_message(json.dumps({"JSONDATA": ""}, ensure_ascii=False))


def make_error_payload(
    message_type: str,
    detail: str,
    *,
    detail_code: str = "CHMAC001E",
) -> dict[str, str]:
    return {
        "NtaCh_CallResult": "E_FAIL",
        "DetailErrorInfo": detail_code,
        "DetailErrorMessage": f"{message_type}: {detail}",
    }


def ensure_request_dir(uid: str) -> Path:
    request_dir = APP_GROUP_ROOT / uid
    request_dir.mkdir(parents=True, exist_ok=True)
    data_path = request_dir / "data.plist"
    if not data_path.exists():
        data_path.write_bytes(plistlib.dumps({}))
    return request_dir


def reset_request_dir(uid: str) -> Path:
    request_dir = APP_GROUP_ROOT / uid
    if request_dir.exists():
        shutil.rmtree(request_dir)
    return request_dir


def decode_value(value: Any) -> Any:
    if isinstance(value, str):
        try:
            return value.encode("utf-8").decode("utf-8")
        except UnicodeError:
            return value
    return value


def extract_direct_request(request: dict[str, Any]) -> tuple[str, dict[str, str], str]:
    message_type = str(request.get("MessageType", "UNKNOWN"))
    uid = str(request.get("uid") or f"chrome-{uuid.uuid4().hex}")

    if message_type in DIRECT_MESSAGE_FIELDS:
        params: dict[str, str] = {"uid": uid}
        for field in DIRECT_MESSAGE_FIELDS[message_type]:
            if field in request and request[field] is not None:
                params[field] = str(decode_value(request[field]))
        return message_type, params, uid

    if message_type in ARG_MAPPED_MESSAGES:
        target_message, fields = ARG_MAPPED_MESSAGES[message_type]
        args = list(request.get("args1") or [])
        params = {"uid": uid}
        for field, value in zip(fields, args):
            params[field] = str(decode_value(value))
        return target_message, params, uid

    raise KeyError(message_type)


def open_etax_url(message_name: str, params: dict[str, str]) -> None:
    query = urlencode(params, doseq=False, safe="")
    url = f"CLeTaxWEB://{message_name}?{query}"
    log_line(f"launch {url}")
    subprocess.run(["open", url], check=True)


def read_plist(path: Path) -> dict[str, Any]:
    with path.open("rb") as fh:
        data = plistlib.load(fh)
    if not isinstance(data, dict):
        raise ValueError(f"unexpected plist root type: {type(data)!r}")
    return data


def wait_for_result(uid: str, *, baseline_mtime: float) -> dict[str, Any]:
    request_plist = APP_GROUP_ROOT / uid / "data.plist"
    shared_plist = APP_GROUP_ROOT / "data.plist"
    deadline = time.monotonic() + HOST_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if request_plist.exists():
            stat = request_plist.stat()
            if stat.st_mtime > baseline_mtime:
                result = read_plist(request_plist)
                if result:
                    return result
        if shared_plist.exists():
            stat = shared_plist.stat()
            if stat.st_mtime > baseline_mtime:
                result = read_plist(shared_plist)
                if result:
                    log_line(f"result uid={uid} fell back to shared data.plist")
                    return result
        time.sleep(0.2)
    raise TimeoutError(f"timed out waiting for {request_plist}")


def bridge_request(request: dict[str, Any]) -> dict[str, Any]:
    message_name, params, uid = extract_direct_request(request)
    APP_GROUP_ROOT.mkdir(parents=True, exist_ok=True)
    reset_request_dir(uid)
    baseline_mtime = time.time()
    open_etax_url(message_name, params)
    result = wait_for_result(uid, baseline_mtime=baseline_mtime)
    log_line(f"result uid={uid} payload={json.dumps(result, ensure_ascii=False)}")
    return result


def main() -> int:
    log_line(f"host start pid={os.getpid()}")
    try:
        while True:
            request = read_native_message()
            if request is None:
                break
            message_type = str(request.get("MessageType", "UNKNOWN"))
            try:
                payload = bridge_request(request)
            except KeyError:
                payload = make_error_payload(message_type, "unsupported MessageType")
            except subprocess.CalledProcessError as exc:
                payload = make_error_payload(message_type, f"failed to launch app: {exc}")
            except TimeoutError as exc:
                payload = make_error_payload(message_type, str(exc), detail_code="CHMAC002E")
            except Exception as exc:  # pragma: no cover
                payload = make_error_payload(message_type, repr(exc), detail_code="CHMAC999E")
            write_chunked_response(payload)
    except Exception as exc:  # pragma: no cover
        log_line(f"fatal {exc!r}")
        return 1
    finally:
        log_line("host stop")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
