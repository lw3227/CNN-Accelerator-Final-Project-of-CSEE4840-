#!/usr/bin/env python3

import argparse
import base64
import sys
import time
from pathlib import Path

import serial


def read_until(ser, marker, timeout_s):
    deadline = time.time() + timeout_s
    buf = ""
    while time.time() < deadline:
        data = ser.read(4096)
        if data:
            buf += data.decode("utf-8", errors="replace")
            if marker in buf:
                return buf
    return buf


def login(ser, username, password):
    ser.write(b"\r\n")
    time.sleep(0.3)
    out = read_until(ser, "login:", 2.0)
    if "login:" in out:
        ser.write((username + "\n").encode("utf-8"))
        out += read_until(ser, "Password:", 2.0)
    if "Password:" in out:
        ser.write((password + "\n").encode("utf-8"))
        read_until(ser, "# ", 3.0)


def fetch_file(ser, remote_path: str) -> bytes:
    start_marker = "__CODEX_B64_START__"
    end_marker = "__CODEX_B64_END__"
    status_marker = "__CODEX_B64_STATUS__"
    ser.reset_input_buffer()
    cmd = "\n".join(
        [
            f"echo {start_marker}",
            f"base64 '{remote_path}'",
            "status=$?",
            f"echo {end_marker}",
            f"echo {status_marker}$status",
        ]
    )
    ser.write((cmd + "\n").encode("utf-8"))
    ser.flush()

    out = read_until(ser, status_marker, 30.0)
    start = out.find(start_marker)
    end = out.find(end_marker)
    if start == -1 or end == -1:
        raise RuntimeError("timed out waiting for base64 transfer markers")

    payload = out[start + len(start_marker) : end]
    status_idx = out.find(status_marker, end)
    if status_idx == -1:
        raise RuntimeError("did not find remote status marker")
    status_line = out[status_idx:].splitlines()[0]
    status_text = status_line[len(status_marker) :].strip()
    if status_text and status_text not in {"0", "$status"}:
        raise RuntimeError(f"remote base64 command failed with status {status_text}")

    allowed = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
    raw_text = "".join(line.strip() for line in payload.splitlines() if line.strip())
    b64_text = "".join(ch for ch in raw_text if ch in allowed)
    if len(b64_text) % 4:
        b64_text += "=" * (4 - (len(b64_text) % 4))
    return base64.b64decode(b64_text)


def main():
    parser = argparse.ArgumentParser(description="Copy one file from DE1-SoC HPS over serial")
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--user", default="root")
    parser.add_argument("--password", default="CSee4840!")
    parser.add_argument("remote_path")
    parser.add_argument("local_path")
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.2)
    try:
        login(ser, args.user, args.password)
        data = fetch_file(ser, args.remote_path)
    finally:
        ser.close()

    out_path = Path(args.local_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(data)
    sys.stdout.write(f"copied {args.remote_path} -> {args.local_path}\n")


if __name__ == "__main__":
    main()
