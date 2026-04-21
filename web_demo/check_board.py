#!/usr/bin/env python3
"""Check SSH connectivity and board-side web-demo prerequisites."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from gesture_runtime.ssh_transport import SshBoardTransport
from web_demo.config import load_demo_config


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check board SSH and prepare the board-side CPU/FPGA demo tools"
    )
    parser.add_argument("--build-tools", action="store_true", help="run make -C tools on the remote repo")
    args = parser.parse_args()

    cfg = load_demo_config()
    transport = SshBoardTransport(
        host=cfg.board_host,
        user=cfg.board_user,
        port=cfg.board_port,
        identity_file=cfg.ssh_key,
        known_hosts_file=cfg.ssh_known_hosts,
        bind_address=cfg.ssh_bind_address,
    )

    print(f"[INFO] connecting to {cfg.board_user}@{cfg.board_host}:{cfg.board_port}")
    if cfg.ssh_bind_address:
        print(f"[INFO] bind address: {cfg.ssh_bind_address}")
    print("[INFO] uname:")
    print(transport.run("uname -a", timeout_s=10.0).strip())

    print("[INFO] repo check:")
    print(transport.run(f"cd '{cfg.remote_repo}' && pwd", timeout_s=10.0).strip())

    if args.build_tools:
        print("[INFO] building remote tools...")
        print(transport.run(f"cd '{cfg.remote_repo}/tools' && make", timeout_s=120.0).strip())

    print("[INFO] checking board-side demo tools:")
    print(
        transport.run(
            f"cd '{cfg.remote_repo}/tools' && ls -l hps_mmio_predict* hps_cpu_reference*",
            timeout_s=10.0,
        ).strip()
    )

    print("[INFO] python3 on board:")
    print(transport.run("python3 --version", timeout_s=10.0).strip())

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
