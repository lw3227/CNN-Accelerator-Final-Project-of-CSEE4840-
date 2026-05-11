"""Configuration loading for the web comparison demo.

The demo can run on different networks and boards, so the host-side runtime
does not hard-code SSH addresses, model paths, or the FPGA CSR base address.
This module merges JSON configuration with environment variables and returns a
single `DemoConfig` object used by `web_demo/app.py` when it builds the service
graph.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL = REPO_ROOT / "Golden-Module" / "models" / "v1.int8.tflite"
DEFAULT_CONFIG_PATH = Path(
    os.environ.get("CNN_ACC_DEMO_CONFIG", str(REPO_ROOT / "web_demo" / "demo_config.json"))
)


@dataclass
class DemoConfig:
    """All runtime settings needed to connect the browser flow to the board."""

    cpu_model: Path
    labels: List[str]
    board_host: str
    board_user: str
    board_port: int
    ssh_key: Optional[Path]
    ssh_known_hosts: Optional[Path]
    ssh_bind_address: Optional[str]
    remote_repo: str
    remote_preload_root: str
    remote_reference_case_root: str
    csr_base: str
    fabric_mhz: float
    local_host: str
    local_port: int
    debug: bool

    @property
    def model_lane(self) -> str:
        """Infer which model family the current preload/config appears to use."""
        preload = self.remote_preload_root.lower()
        labels_are_numeric = self.labels and all(label.isdigit() for label in self.labels)
        if "digit_" in preload or labels_are_numeric:
            return "gesture-10class"
        if any(token in preload for token in ("paper", "rock", "scissors", "gesture")):
            return "gesture"
        return "unknown"

    @property
    def model_warning(self) -> Optional[str]:
        """Return a UI warning when the configured model path looks ambiguous."""
        if self.model_lane == "unknown":
            return (
                "Current demo config does not clearly map to a gesture-specific deployed model. "
                "Predictions may not match the intended gesture task."
            )
        return None

    @property
    def dataset_name(self) -> str:
        if self.model_lane == "gesture-10class":
            return "Sign Language Digits Dataset"
        if self.model_lane == "gesture":
            return "Gesture dataset"
        return "Unknown dataset"

    @property
    def dataset_source_hint(self) -> Optional[str]:
        if self.model_lane == "gesture-10class":
            return "Kaggle sign-language digits dataset family; local training root expected as dataset_wlx/"
        return None


def _read_json_config(path: Path) -> dict:
    """Read the optional JSON config file; missing files simply mean defaults."""
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _resolve_repo_path(value: Optional[str]) -> Optional[Path]:
    """Resolve relative paths from the repository root for stable launching."""
    if not value:
        return None
    raw = Path(value)
    if raw.is_absolute():
        return raw
    return (REPO_ROOT / raw).resolve()


def load_demo_config(path: Optional[Path] = None) -> DemoConfig:
    """Load the demo configuration with JSON values overriding defaults."""
    cfg_path = path or DEFAULT_CONFIG_PATH
    raw = _read_json_config(cfg_path)

    # Labels may be supplied either as a JSON list or a comma-separated
    # environment variable. If neither is present, the deployed demo defaults
    # to the ten digit/gesture classes used by the hardware-aligned tests.
    labels = raw.get("labels") or os.environ.get("CNN_ACC_LABELS", "")
    label_list = labels if isinstance(labels, list) else [x.strip() for x in labels.split(",") if x.strip()]
    if not label_list:
        label_list = [str(i) for i in range(10)]

    ssh_key = raw.get("ssh_key") or os.environ.get("CNN_ACC_SSH_KEY")
    ssh_known_hosts = raw.get("ssh_known_hosts") or os.environ.get("CNN_ACC_SSH_KNOWN_HOSTS")
    ssh_bind_address = raw.get("ssh_bind_address") or os.environ.get("CNN_ACC_SSH_BIND_ADDRESS")

    return DemoConfig(
        cpu_model=_resolve_repo_path(
            raw.get("cpu_model") or os.environ.get("CNN_ACC_CPU_MODEL", str(DEFAULT_MODEL))
        )
        or DEFAULT_MODEL,
        labels=label_list,
        board_host=raw.get("board_host") or os.environ.get("CNN_ACC_BOARD_HOST", "192.168.0.2"),
        board_user=raw.get("board_user") or os.environ.get("CNN_ACC_BOARD_USER", "root"),
        board_port=int(raw.get("board_port") or os.environ.get("CNN_ACC_BOARD_PORT", "22")),
        ssh_key=_resolve_repo_path(ssh_key),
        ssh_known_hosts=_resolve_repo_path(ssh_known_hosts),
        ssh_bind_address=ssh_bind_address or None,
        remote_repo=raw.get("remote_repo") or os.environ.get("CNN_ACC_REMOTE_REPO", "/root/cnn_acc_hps"),
        remote_preload_root=raw.get("remote_preload_root")
        or os.environ.get(
            "CNN_ACC_REMOTE_PRELOAD_ROOT",
            "Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test",
        ),
        remote_reference_case_root=raw.get("remote_reference_case_root")
        or os.environ.get(
            "CNN_ACC_REMOTE_REFERENCE_CASE_ROOT",
            "Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test",
        ),
        csr_base=raw.get("csr_base") or os.environ.get("CNN_ACC_CSR_BASE", "0xff200000"),
        fabric_mhz=float(raw.get("fabric_mhz") or os.environ.get("CNN_ACC_FABRIC_MHZ", "50")),
        local_host=raw.get("local_host") or os.environ.get("HOST", "127.0.0.1"),
        local_port=int(raw.get("local_port") or os.environ.get("PORT", "5000")),
        debug=bool(raw.get("debug", os.environ.get("FLASK_DEBUG", "1") not in ("0", "false", "False"))),
    )
