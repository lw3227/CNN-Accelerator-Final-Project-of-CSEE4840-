"""Transport abstraction for host-to-board execution."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional


class BoardTransport(ABC):
    @abstractmethod
    def run(self, command: str, timeout_s: float = 30.0) -> str:
        raise NotImplementedError

    @abstractmethod
    def put_dir(self, local_dir: Path, remote_parent: str, timeout_s: float = 30.0) -> None:
        raise NotImplementedError


class TransportError(RuntimeError):
    pass
