#!/usr/bin/env python3

import argparse
import sys
import time
import uuid

import serial


def write_text(ser, text, delay_s=0.08):
    for line in text.splitlines(True):
        data = line.encode("utf-8")
        ser.write(data)
        ser.flush()
        time.sleep(delay_s)


def read_until(ser, patterns, timeout_s):
    deadline = time.time() + timeout_s
    buf = ""
    while time.time() < deadline:
        data = ser.read(4096)
        if data:
            chunk = data.decode("utf-8", errors="replace")
            buf += chunk
            if any(pattern in buf for pattern in patterns):
                return buf
    return buf


def login(ser, username, password):
    ser.write(b"\x03\r\n")
    ser.flush()
    time.sleep(0.3)
    buf = read_until(ser, ["login:", "Password:", "# ", "$ "], 2.0)

    if "login:" in buf:
        ser.write((username + "\n").encode("utf-8"))
        buf += read_until(ser, ["Password:", "# ", "$ "], 2.0)

    if "Password:" in buf:
        ser.write((password + "\n").encode("utf-8"))
        buf += read_until(ser, ["# ", "$ "], 3.0)

    return buf


def run_command(ser, command, settle_s):
    nonce = uuid.uuid4().hex[:8].upper()
    start_marker = f"CNNACCSTART{nonce}"
    end_marker = f"CNNACCEND{nonce}"
    ser.reset_input_buffer()
    wrapped = "\n".join(
        [
            f"echo {start_marker}",
            command.rstrip("\n"),
            "status=$?",
            f"echo {end_marker}",
            "echo $status",
        ]
    )
    write_text(ser, wrapped.replace("\n", "\r\n") + "\r\n")
    out = read_until(ser, [end_marker], settle_s)

    start = out.find(start_marker)
    end = out.find(end_marker)
    status = None
    if end != -1:
        tail = out[end + len(end_marker) :]
        for line in tail.splitlines():
            field = line.strip()
            if not field:
                continue
            try:
                status = int(field)
                break
            except ValueError:
                continue
    if start != -1 and end != -1:
        out = out[start + len(start_marker) : end]
    return out.strip(), status


def main():
    parser = argparse.ArgumentParser(description="Run shell commands on DE1-SoC HPS over serial")
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--user", default="root")
    parser.add_argument("--password", default="CSee4840!")
    parser.add_argument("--timeout", type=float, default=8.0, help="seconds to wait for command completion")
    parser.add_argument("command", nargs="+", help="shell command to execute")
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.2)
    try:
        login(ser, args.user, args.password)
        output, status = run_command(ser, " ".join(args.command), args.timeout)
    finally:
        ser.close()

    sys.stdout.reconfigure(encoding="utf-8", errors="ignore")
    print(output)
    if status is not None:
        raise SystemExit(status)


if __name__ == "__main__":
    main()
