#!/usr/bin/env python3
"""Probe a small set of local candidate IPs for SSH reachability."""

from __future__ import annotations

import argparse
import ipaddress
import socket
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Iterable, List, Set


def parse_arp_candidates() -> Set[str]:
    proc = subprocess.run(["arp", "-a"], capture_output=True, text=True, encoding="utf-8", errors="ignore")
    hosts: Set[str] = set()
    for line in proc.stdout.splitlines():
        parts = line.split()
        if parts and parts[0].count(".") == 3:
            hosts.add(parts[0])
    return hosts


def add_subnet_candidates(hosts: Set[str], cidr: str, limit: int = 64) -> None:
    network = ipaddress.ip_network(cidr, strict=False)
    for idx, host in enumerate(network.hosts()):
        if idx >= limit:
            break
        hosts.add(str(host))


def probe_host(host: str, port: int, timeout_s: float) -> str | None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout_s)
    try:
        sock.connect((host, port))
        return host
    except OSError:
        return None
    finally:
        sock.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe local candidate IPs for SSH reachability")
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--timeout", type=float, default=0.35)
    parser.add_argument(
        "--subnet",
        action="append",
        default=[],
        help="optional extra CIDR to probe, e.g. 192.168.1.0/24",
    )
    args = parser.parse_args()

    candidates = parse_arp_candidates()
    for subnet in args.subnet:
        add_subnet_candidates(candidates, subnet)

    candidates = {host for host in candidates if not host.startswith(("224.", "239.", "255."))}
    found: List[str] = []

    with ThreadPoolExecutor(max_workers=32) as pool:
        futures = {pool.submit(probe_host, host, args.port, args.timeout): host for host in sorted(candidates)}
        for future in as_completed(futures):
            hit = future.result()
            if hit:
                found.append(hit)

    for host in sorted(found):
        print(host)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
