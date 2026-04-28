#!/usr/bin/env python3
"""One-command host+board prep for the DE1-SoC web demo path."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Optional

import serial

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from gesture_runtime.ssh_transport import SshBoardTransport, TransportError
from hps_serial_exec import login, run_command
from web_demo.config import load_demo_config


def _run_subprocess(cmd: List[str], timeout_s: float = 30.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout_s,
    )


def _registry_quartus_install_dirs() -> List[Path]:
    try:
        import winreg  # type: ignore
    except ImportError:
        return []

    dirs: List[Path] = []
    keys = [
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Altera Corporation\Quartus"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Altera Corporation\Quartus"),
    ]
    for hive, subkey in keys:
        try:
            key = winreg.OpenKey(hive, subkey)
        except OSError:
            continue
        try:
            value, _ = winreg.QueryValueEx(key, "Quartus Install Directory")
        except OSError:
            continue
        dirs.append(Path(value))
    return dirs


def find_quartus_pgm(explicit_path: Optional[Path]) -> Path:
    candidates: List[Path] = []
    if explicit_path:
        candidates.append(explicit_path)

    env_value = os.environ.get("QUARTUS_PGM")
    if env_value:
        candidates.append(Path(env_value))

    which_path = shutil.which("quartus_pgm")
    if which_path:
        candidates.append(Path(which_path))

    for install_dir in _registry_quartus_install_dirs():
        candidates.append(install_dir / "bin64" / "quartus_pgm.exe")
        candidates.append(install_dir / "bin" / "quartus_pgm.exe")

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    raise FileNotFoundError(
        "quartus_pgm not found. Install Quartus Programmer, or pass --quartus-pgm."
    )


def list_programmer_cables(quartus_pgm: Path) -> List[str]:
    proc = _run_subprocess([str(quartus_pgm), "-l"], timeout_s=20.0)
    if proc.returncode != 0:
        raise RuntimeError(f"quartus_pgm -l failed\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")
    cables = []
    for line in proc.stdout.splitlines():
        match = re.match(r"^\s*\d+\)\s+(.+?)\s*$", line)
        if match:
            cables.append(match.group(1))
    return cables


def program_sof(quartus_pgm: Path, cable: Optional[str], sof_path: Path, device_index: int) -> None:
    if not sof_path.is_file():
        raise FileNotFoundError(f"missing SOF file: {sof_path}")

    chosen_cable = cable
    if not chosen_cable:
        cables = list_programmer_cables(quartus_pgm)
        if not cables:
            raise RuntimeError("no JTAG programming cable found")
        chosen_cable = cables[0]

    operation = f"p;{sof_path}@{device_index}"
    cmd = [str(quartus_pgm), "-c", chosen_cable, "-m", "jtag", "-o", operation]
    print(f"[INFO] programming SOF via cable: {chosen_cable}")
    proc = _run_subprocess(cmd, timeout_s=60.0)
    print(proc.stdout.strip())
    if proc.returncode != 0:
        raise RuntimeError(f"SOF programming failed\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")


def run_serial_checked(ser: serial.Serial, command: str, timeout_s: float) -> str:
    output, status = run_command(ser, command, timeout_s)
    if status != 0:
        raise RuntimeError(
            "serial remote command failed\n"
            f"command: {command}\n"
            f"status: {status}\n"
            f"output:\n{output}"
        )
    return output.strip()


def configure_board_network_and_ssh(
    port: str,
    baud: int,
    user: str,
    password: str,
    board_ip: str,
    timeout_s: float,
) -> None:
    network_cmd = f"""
if command -v ip >/dev/null 2>&1; then
  ip link set eth0 up
  ip addr flush dev eth0 >/dev/null 2>&1 || true
  ip addr add {board_ip}/16 dev eth0
  ip addr show dev eth0
else
  ifconfig eth0 up
  ifconfig eth0 {board_ip} netmask 255.255.0.0
  ifconfig eth0
fi
""".strip()

    ssh_cmd = """
started=0
if command -v systemctl >/dev/null 2>&1; then
  systemctl start ssh >/dev/null 2>&1 && started=1 || true
  systemctl start sshd >/dev/null 2>&1 && started=1 || true
fi
if command -v service >/dev/null 2>&1; then
  service ssh start >/dev/null 2>&1 && started=1 || true
  service sshd start >/dev/null 2>&1 && started=1 || true
  service dropbear start >/dev/null 2>&1 && started=1 || true
fi
[ -x /etc/init.d/ssh ] && /etc/init.d/ssh start >/dev/null 2>&1 && started=1 || true
[ -x /etc/init.d/sshd ] && /etc/init.d/sshd start >/dev/null 2>&1 && started=1 || true
[ -x /etc/init.d/dropbear ] && /etc/init.d/dropbear start >/dev/null 2>&1 && started=1 || true
echo ssh_service_started=$started
(ps | grep -E '[s]shd|[d]ropbear') || true
""".strip()

    ser = serial.Serial(port, baud, timeout=0.2)
    try:
        login(ser, user, password)
        print("[INFO] board repo check:")
        print(run_serial_checked(ser, "cd /root/cnn_acc_hps && pwd", timeout_s))
        print("[INFO] configuring board Ethernet:")
        print(run_serial_checked(ser, network_cmd, timeout_s))
        print("[INFO] starting board SSH service:")
        print(run_serial_checked(ser, ssh_cmd, timeout_s))
    finally:
        ser.close()


def ping_host(target: str) -> None:
    if os.name == "nt":
        cmd = ["ping", target, "-n", "2"]
    else:
        cmd = ["ping", target, "-c", "2"]
    proc = _run_subprocess(cmd, timeout_s=15.0)
    print("[INFO] host ping:")
    print(proc.stdout.strip())
    if proc.returncode != 0:
        raise RuntimeError(f"ping to {target} failed")


def verify_ssh(build_tools: bool) -> None:
    cfg = load_demo_config()
    transport = SshBoardTransport(
        host=cfg.board_host,
        user=cfg.board_user,
        port=cfg.board_port,
        identity_file=cfg.ssh_key,
        known_hosts_file=cfg.ssh_known_hosts,
        bind_address=cfg.ssh_bind_address,
    )
    print("[INFO] SSH uname:")
    print(transport.run("uname -a", timeout_s=15.0).strip())
    print("[INFO] SSH repo check:")
    print(transport.run(f"cd '{cfg.remote_repo}' && pwd", timeout_s=15.0).strip())
    if build_tools:
        print("[INFO] SSH build remote tools:")
        print(transport.run(f"cd '{cfg.remote_repo}/tools' && make", timeout_s=180.0).strip())
    print("[INFO] SSH board demo tools:")
    print(
        transport.run(
            f"cd '{cfg.remote_repo}/tools' && ls -l hps_mmio_predict* hps_cpu_reference*",
            timeout_s=15.0,
        ).strip()
    )


def main() -> int:
    cfg = load_demo_config()
    parser = argparse.ArgumentParser(
        description="One-command SOF programming + board network/SSH bring-up for the web demo"
    )
    parser.add_argument("--program-sof", action="store_true", help="program the current SOF before board checks")
    parser.add_argument("--quartus-pgm", type=Path, help="explicit path to quartus_pgm")
    parser.add_argument("--cable", help="Quartus programmer cable name")
    parser.add_argument(
        "--sof",
        type=Path,
        default=REPO_ROOT / "de1_soc" / "output_files" / "soc_system.sof",
        help="SOF file to program",
    )
    parser.add_argument(
        "--jtag-device-index",
        type=int,
        default=2,
        help="JTAG chain device index for the FPGA. DE1-SoC uses 2 by default.",
    )
    parser.add_argument("--port", default="COM3", help="serial COM port for the board UART")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--user", default="root")
    parser.add_argument("--password", default="CSee4840!")
    parser.add_argument("--serial-timeout", type=float, default=15.0)
    parser.add_argument("--skip-serial-network", action="store_true", help="skip serial eth0/SSH bring-up")
    parser.add_argument("--skip-ssh-check", action="store_true", help="skip host-side ping and SSH verification")
    parser.add_argument("--build-tools", action="store_true", help="build remote tools after SSH comes up")
    parser.add_argument("--board-ip", default=cfg.board_host)
    args = parser.parse_args()

    if args.program_sof:
        quartus_pgm = find_quartus_pgm(args.quartus_pgm)
        print(f"[INFO] quartus_pgm: {quartus_pgm}")
        program_sof(quartus_pgm, args.cable, args.sof.resolve(), args.jtag_device_index)

    if not args.skip_serial_network:
        configure_board_network_and_ssh(
            port=args.port,
            baud=args.baud,
            user=args.user,
            password=args.password,
            board_ip=args.board_ip,
            timeout_s=args.serial_timeout,
        )

    if not args.skip_ssh_check:
        ping_host(args.board_ip)
        try:
            verify_ssh(build_tools=args.build_tools)
        except (TransportError, subprocess.TimeoutExpired) as exc:
            raise RuntimeError(f"SSH verification failed: {exc}") from exc

    print("[INFO] board web-demo preparation complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
