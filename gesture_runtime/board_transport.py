"""Transport abstraction for host-to-board execution.

The comparison service only depends on this abstract interface. Today the
implementation is SSH/SCP, but the same interface could wrap a serial link,
local mock, or a different board-control backend without changing the web
routes or result formatting code.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional


class BoardTransport(ABC):
    @abstractmethod
    def run(self, command: str, timeout_s: float = 30.0) -> str:
        """Run a remote command and return its standard output."""
        raise NotImplementedError

    @abstractmethod
    def put_dir(self, local_dir: Path, remote_parent: str, timeout_s: float = 30.0) -> None:
        """Copy a local directory into a remote parent directory."""
        raise NotImplementedError


class TransportError(RuntimeError):
    """Raised when command execution or file transfer fails."""

    pass
