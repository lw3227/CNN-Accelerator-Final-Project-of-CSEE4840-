"""Host 到 board 执行流程的传输抽象层。

对比服务只依赖这个抽象接口。当前实现是 SSH/SCP，但同一个接口也可以换成
串口、本地 mock，或者其他 board-control backend，而不需要改 Flask route 或
结果格式化代码。
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional


class BoardTransport(ABC):
    @abstractmethod
    def run(self, command: str, timeout_s: float = 30.0) -> str:
        """执行一条远端命令并返回标准输出。"""
        raise NotImplementedError

    @abstractmethod
    def put_dir(self, local_dir: Path, remote_parent: str, timeout_s: float = 30.0) -> None:
        """把本地目录复制到远端父目录下。"""
        raise NotImplementedError


class TransportError(RuntimeError):
    """命令执行或文件传输失败时抛出的异常。"""

    pass
