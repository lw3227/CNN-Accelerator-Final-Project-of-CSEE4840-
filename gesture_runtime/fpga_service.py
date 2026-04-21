"""Board-side FPGA inference service wrappers."""

from __future__ import annotations

import shlex
import tempfile
from dataclasses import dataclass
from pathlib import Path
from time import perf_counter
from typing import Dict

from .board_transport import BoardTransport


def parse_key_value_output(text: str) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip()
    return result


@dataclass
class FPGAServiceConfig:
    remote_repo: str = "/root/cnn_acc_hps"
    csr_base: str = "0xff200000"
    remote_preload_root: str = "Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test"
    remote_reference_case_root: str = "Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test"
    remote_case_parent: str = "/tmp"


class FPGABoardService:
    def __init__(self, transport: BoardTransport, config: FPGAServiceConfig):
        self.transport = transport
        self.config = config
        self._model_loaded = False

    def _read_status(self) -> Dict[str, str]:
        cmd = (
            f"cd {shlex.quote(self.config.remote_repo)} && "
            f"./tools/hps_mmio_status {shlex.quote(self.config.csr_base)}"
        )
        output = self.transport.run(cmd, timeout_s=20.0)
        return parse_key_value_output(output)

    def ensure_model_loaded(self, force: bool = False) -> None:
        if not force and self._model_loaded:
            try:
                status = self._read_status()
                if status.get("model_loaded") == "1":
                    return
            except Exception:
                # Fall back to reloading the model if a status probe fails.
                pass
        cmd = (
            f"cd {shlex.quote(self.config.remote_repo)} && "
            f"./tools/hps_mmio_load_model {shlex.quote(self.config.csr_base)} "
            f"{shlex.quote(self.config.remote_preload_root)}"
        )
        self.transport.run(cmd, timeout_s=60.0)
        self._model_loaded = True

    def predict_case_dir(self, local_case_dir: Path) -> Dict[str, object]:
        self.ensure_model_loaded()
        self.transport.put_dir(local_case_dir, self.config.remote_case_parent, timeout_s=60.0)

        remote_case_dir = f"{self.config.remote_case_parent}/{local_case_dir.name}"
        cmd = (
            f"cd {shlex.quote(self.config.remote_repo)} && "
            f"./tools/hps_mmio_predict {shlex.quote(self.config.csr_base)} "
            f"{shlex.quote(remote_case_dir)}"
        )

        started = perf_counter()
        try:
            output = self.transport.run(cmd, timeout_s=60.0)
        except Exception as exc:
            message = str(exc)
            if "timeout waiting for predict_done" not in message:
                raise
            self.ensure_model_loaded(force=True)
            output = self.transport.run(cmd, timeout_s=60.0)
        elapsed_ms = (perf_counter() - started) * 1000.0
        parsed = parse_key_value_output(output)
        profile = {
            "l1_cycles": int(parsed.get("l1_cycles", "0") or 0),
            "l2_p0_cycles": int(parsed.get("l2_p0_cycles", "0") or 0),
            "l2_p1_cycles": int(parsed.get("l2_p1_cycles", "0") or 0),
            "l3_p0_cycles": int(parsed.get("l3_p0_cycles", "0") or 0),
            "l3_p1_cycles": int(parsed.get("l3_p1_cycles", "0") or 0),
            "fc_cycles": int(parsed.get("fc_cycles", "0") or 0),
            "argmax_cycles": int(parsed.get("argmax_cycles", "0") or 0),
            "total_cycles": int(parsed.get("total_cycles", "0") or 0),
        }
        return {
            "predict_class": int(parsed.get("predict_class", "0")),
            "status": parsed.get("status", ""),
            "error": parsed.get("error", ""),
            "request_elapsed_ms": elapsed_ms,
            "board_case_load_ms": float(parsed.get("board_case_load_ms", "0") or 0),
            "board_program_ms": float(parsed.get("board_program_ms", "0") or 0),
            "board_infer_wait_ms": float(parsed.get("board_infer_wait_ms", "0") or 0),
            "board_total_ms": float(parsed.get("board_total_ms", "0") or 0),
            "profile": profile,
            "raw_output": output,
        }


class BoardCPUReferenceService:
    def __init__(self, transport: BoardTransport, config: FPGAServiceConfig):
        self.transport = transport
        self.config = config

    def predict_case_dir(self, local_case_dir: Path) -> Dict[str, object]:
        self.transport.put_dir(local_case_dir, self.config.remote_case_parent, timeout_s=60.0)

        remote_case_dir = f"{self.config.remote_case_parent}/{local_case_dir.name}"
        cmd = (
            f"cd {shlex.quote(self.config.remote_repo)} && "
            f"./tools/hps_cpu_reference {shlex.quote(remote_case_dir)} "
            f"{shlex.quote(self.config.remote_reference_case_root)}"
        )
        output = self.transport.run(cmd, timeout_s=60.0)
        parsed = parse_key_value_output(output)
        return {
            "predict_class": int(parsed.get("predict_class", "0")),
            "board_cpu_infer_ms": float(parsed.get("board_cpu_infer_ms", "0") or 0),
            "raw_output": output,
        }
