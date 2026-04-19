#!/usr/bin/env python3

import argparse
import base64
import sys
import time
from pathlib import Path

import serial


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REMOTE_REPO = "/homes/user/stud/fall25/lw3227/CNN_ACC"
DEFAULT_PRELOAD_ROOT = (
    "Golden-Module/matlab/hardware_aligned/debug/sram_preload"
)
DEFAULT_CASE_ROOT = "Golden-Module/matlab/hardware_aligned/debug/txt_cases"


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
    ser.write(b"\r\n")
    time.sleep(0.3)
    buf = read_until(ser, ["login:", "Password:", "# ", "$ "], 2.0)

    if "login:" in buf:
        ser.write((username + "\n").encode("utf-8"))
        buf += read_until(ser, ["Password:", "# ", "$ "], 2.0)

    if "Password:" in buf:
        ser.write((password + "\n").encode("utf-8"))
        buf += read_until(ser, ["# ", "$ "], 3.0)

    return buf


def run_remote(ser, command, timeout_s):
    start_marker = "__CNN_ACC_EXEC_START__"
    end_marker = "__CNN_ACC_EXEC_END__"
    ser.reset_input_buffer()
    wrapped = "\n".join(
        [
            f"echo {start_marker}",
            command.rstrip("\n"),
            "status=$?",
            f"echo {end_marker}$status",
        ]
    )
    ser.write((wrapped + "\n").encode("utf-8"))
    ser.flush()
    out = read_until(ser, [end_marker], timeout_s)

    start = out.find(start_marker)
    end = out.find(end_marker)
    status = None
    if end != -1:
        line_end = out.find("\n", end)
        if line_end == -1:
            line_end = len(out)
        status_field = out[end:line_end]
        if status_field.startswith(end_marker):
            try:
                status = int(status_field[len(end_marker) :].strip())
            except ValueError:
                status = None
    if start != -1 and end != -1:
        out = out[start + len(start_marker) : end]
    return out.strip(), status


def push_file(ser, local_path: Path, remote_path: str):
    content = local_path.read_bytes()
    encoded = base64.b64encode(content).decode("ascii")
    remote_b64 = remote_path + ".b64"
    run_checked(ser, f"mkdir -p $(dirname '{remote_path}')", 10.0)
    ser.write((f"cat > '{remote_b64}' <<'__EOF__'\n").encode("utf-8"))
    chunk_size = 512
    for idx in range(0, len(encoded), chunk_size):
        ser.write((encoded[idx : idx + chunk_size] + "\n").encode("utf-8"))
    ser.write(b"__EOF__\n")
    ser.flush()
    run_checked(
        ser,
        f"base64 -d '{remote_b64}' > '{remote_path}' && rm -f '{remote_b64}'",
        60.0,
    )


def run_checked(ser, command, timeout_s):
    output, status = run_remote(ser, command, timeout_s)
    if status not in (0, None):
        raise RuntimeError(
            "remote command failed\n"
            f"command: {command}\n"
            f"status: {status}\n"
            f"output:\n{output}"
        )
    return output


def remote_case_paths(remote_repo, case_name, preload_root, case_root):
    preload = f"{remote_repo}/{preload_root}/{case_name}"
    case = f"{remote_repo}/{case_root}/{case_name}"
    return preload, case


def build_remote_flow_command(remote_repo, csr_base, preload_dir, case_dir, skip_build):
    commands = [f"cd '{remote_repo}'"]
    if not skip_build:
        commands.append("make -C tools")
    commands.extend(
        [
            "echo '=== DT TREE ==='",
            "find /proc/device-tree/sopc@0 -maxdepth 3 2>/dev/null | sort || true",
            "echo '=== DT KEY NODES ==='",
            "find /proc/device-tree/sopc@0 -maxdepth 5 2>/dev/null | grep -E 'cnn_mmio_interface|vga|bridge|fpga' || true",
            "echo '=== STATUS ==='",
            f"./tools/hps_mmio_status {csr_base}",
            "echo '=== MODEL LOAD ==='",
            f"./tools/hps_mmio_load_model {csr_base} '{preload_dir}'",
            "echo '=== RUN CASE ==='",
            f"./tools/hps_mmio_run_case {csr_base} '{case_dir}'",
        ]
    )
    return "\n".join(commands)


def main():
    parser = argparse.ArgumentParser(
        description="Run the staged HPS-to-board MMIO bring-up flow over serial"
    )
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--user", default="root")
    parser.add_argument("--password", default="CSee4840!")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--remote-repo", default=DEFAULT_REMOTE_REPO)
    parser.add_argument("--csr-base", default="0xff200000")
    parser.add_argument("--case", default="digit_0_test")
    parser.add_argument("--preload-root", default=DEFAULT_PRELOAD_ROOT)
    parser.add_argument("--case-root", default=DEFAULT_CASE_ROOT)
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="skip remote 'make -C tools' before running the flow",
    )
    parser.add_argument(
        "--upload-boot-artifacts",
        action="store_true",
        help="copy local soc_system.rbf and soc_system.dtb to the remote staging dir",
    )
    parser.add_argument(
        "--remote-boot-dir",
        default="/mnt",
        help="remote staging directory for uploaded boot artifacts",
    )
    parser.add_argument(
        "--local-rbf",
        type=Path,
        default=REPO_ROOT / "de1_soc" / "output_files" / "soc_system.rbf",
    )
    parser.add_argument(
        "--local-dtb",
        type=Path,
        default=REPO_ROOT / "de1_soc" / "device_tree" / "build" / "soc_system.dtb",
    )
    args = parser.parse_args()

    preload_dir, case_dir = remote_case_paths(
        args.remote_repo, args.case, args.preload_root, args.case_root
    )

    if args.upload_boot_artifacts:
        if not args.local_rbf.is_file():
            raise SystemExit(f"missing local RBF: {args.local_rbf}")
        if not args.local_dtb.is_file():
            raise SystemExit(f"missing local DTB: {args.local_dtb}")

    ser = serial.Serial(args.port, args.baud, timeout=0.2)
    try:
        login(ser, args.user, args.password)

        if args.upload_boot_artifacts:
            print(f"Uploading {args.local_rbf} -> {args.remote_boot_dir}/soc_system.rbf")
            push_file(ser, args.local_rbf, f"{args.remote_boot_dir}/soc_system.rbf")
            print(f"Uploading {args.local_dtb} -> {args.remote_boot_dir}/soc_system.dtb")
            push_file(ser, args.local_dtb, f"{args.remote_boot_dir}/soc_system.dtb")
            print("Remote boot artifacts staged.")

        flow_cmd = build_remote_flow_command(
            args.remote_repo,
            args.csr_base,
            preload_dir,
            case_dir,
            args.skip_build,
        )
        output = run_checked(ser, flow_cmd, args.timeout)
    finally:
        ser.close()

    sys.stdout.reconfigure(encoding="utf-8", errors="ignore")
    print(output)


if __name__ == "__main__":
    main()
