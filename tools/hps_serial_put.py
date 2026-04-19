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


def run_remote(ser, command, timeout_s=20.0):
    marker = "__DONE__"
    ser.reset_input_buffer()
    wrapped = "\n".join(
        [
            command.rstrip("\n"),
            "status=$?",
            f"echo {marker}$status",
        ]
    )
    ser.write((wrapped + "\n").encode("utf-8"))
    ser.flush()
    out = read_until(ser, marker, timeout_s)
    line_start = out.rfind(marker)
    if line_start == -1:
        raise RuntimeError("timed out waiting for remote completion marker")
    line_end = out.find("\n", line_start)
    if line_end == -1:
        line_end = len(out)
    status_text = out[line_start + len(marker) : line_end].strip()
    status_text = "".join(ch for ch in status_text if ch.isdigit() or ch == "-")
    status = int(status_text or "0")
    if status != 0:
        raise RuntimeError(f"remote command failed with status {status}\n{out}")


def push_file(ser, local_path: Path, remote_path: str, decode_timeout_s: float):
    content = local_path.read_bytes()
    encoded = base64.b64encode(content).decode("ascii")
    remote_b64 = remote_path + ".b64"
    run_remote(ser, f"mkdir -p $(dirname '{remote_path}')")
    ser.write((f"cat > '{remote_b64}' <<'__EOF__'\n").encode("utf-8"))
    chunk_size = 512
    for idx in range(0, len(encoded), chunk_size):
        ser.write((encoded[idx : idx + chunk_size] + "\n").encode("utf-8"))
    ser.write(b"__EOF__\n")
    ser.flush()
    run_remote(
        ser,
        f"base64 -d '{remote_b64}' > '{remote_path}' && rm -f '{remote_b64}'",
        decode_timeout_s,
    )


def main():
    parser = argparse.ArgumentParser(description="Copy one local file to DE1-SoC HPS over serial")
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--user", default="root")
    parser.add_argument("--password", default="CSee4840!")
    parser.add_argument(
        "--decode-timeout",
        type=float,
        default=60.0,
        help="seconds to wait for remote base64 decode/write completion",
    )
    parser.add_argument("local_path")
    parser.add_argument("remote_path")
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.2)
    try:
        login(ser, args.user, args.password)
        push_file(ser, Path(args.local_path), args.remote_path, args.decode_timeout)
    finally:
        ser.close()

    sys.stdout.write(f"copied {args.local_path} -> {args.remote_path}\n")


if __name__ == "__main__":
    main()
