"""SSH transport for host-to-board execution.

This module is deliberately small: the rest of the runtime only needs a way to
run a command and copy a directory. Keeping SSH/SCP behind `BoardTransport`
makes the demo code independent from the specific transport and makes command
failures easier to report with stdout/stderr included.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import List, Optional

from .board_transport import BoardTransport, TransportError


class SshBoardTransport(BoardTransport):
    """Concrete board transport implemented with the system `ssh` and `scp`."""

    def __init__(
        self,
        host: str,
        user: str = "root",
        port: int = 22,
        identity_file: Optional[Path] = None,
        known_hosts_file: Optional[Path] = None,
        bind_address: Optional[str] = None,
    ):
        self.host = host
        self.user = user
        self.port = port
        self.identity_file = Path(identity_file) if identity_file else None
        self.known_hosts_file = Path(known_hosts_file) if known_hosts_file else None
        self.bind_address = bind_address

    @property
    def target(self) -> str:
        return f"{self.user}@{self.host}"

    def _base_args(self) -> List[str]:
        """Build SSH options shared by command execution and file transfer."""
        args = [
            "-p",
            str(self.port),
            "-o",
            "StrictHostKeyChecking=no",
        ]
        if self.identity_file:
            args.extend(["-i", str(self.identity_file)])
        if self.known_hosts_file:
            args.extend(["-o", f"UserKnownHostsFile={self.known_hosts_file}"])
        if self.bind_address:
            args.extend(["-o", f"BindAddress={self.bind_address}"])
        return args

    def run(self, command: str, timeout_s: float = 30.0) -> str:
        """Run one shell command on HPS Linux and return stdout."""
        proc = subprocess.run(
            ["ssh", *self._base_args(), self.target, command],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_s,
        )
        if proc.returncode != 0:
            raise TransportError(
                "ssh command failed\n"
                f"command: {command}\n"
                f"stdout:\n{proc.stdout}\n"
                f"stderr:\n{proc.stderr}"
            )
        return proc.stdout

    def put_dir(self, local_dir: Path, remote_parent: str, timeout_s: float = 30.0) -> None:
        """Recursively copy a generated case directory to the remote board."""
        proc = subprocess.run(
            [
                "scp",
                "-r",
                "-P",
                str(self.port),
                "-o",
                "StrictHostKeyChecking=no",
                *(["-i", str(self.identity_file)] if self.identity_file else []),
                *(["-o", f"UserKnownHostsFile={self.known_hosts_file}"] if self.known_hosts_file else []),
                *(["-o", f"BindAddress={self.bind_address}"] if self.bind_address else []),
                str(local_dir),
                f"{self.target}:{remote_parent}",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_s,
        )
        if proc.returncode != 0:
            raise TransportError(
                "scp failed\n"
                f"local_dir: {local_dir}\n"
                f"remote_parent: {remote_parent}\n"
                f"stdout:\n{proc.stdout}\n"
                f"stderr:\n{proc.stderr}"
            )
