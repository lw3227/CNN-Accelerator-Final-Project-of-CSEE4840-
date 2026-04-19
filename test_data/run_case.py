#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PRELOAD_ROOT = REPO_ROOT / "Golden-Module" / "matlab" / "hardware_aligned" / "debug" / "sram_preload"
CASE_ROOT = REPO_ROOT / "Golden-Module" / "matlab" / "hardware_aligned" / "debug" / "txt_cases"
RUNNER = REPO_ROOT / "tools" / "run_mmio_inference.py"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one mock MMIO test case by short name")
    parser.add_argument("case_name", help="e.g. digit_0_test")
    args = parser.parse_args()

    preload_dir = PRELOAD_ROOT / args.case_name
    case_dir = CASE_ROOT / args.case_name

    if not preload_dir.is_dir():
        print(f"missing preload dir: {preload_dir}", file=sys.stderr)
        return 1
    if not case_dir.is_dir():
        print(f"missing case dir: {case_dir}", file=sys.stderr)
        return 1

    cmd = [
        sys.executable,
        str(RUNNER),
        "--preload-root",
        str(preload_dir),
        "--case-root",
        str(case_dir),
        "--backend",
        "mock",
    ]
    return subprocess.call(cmd, cwd=str(REPO_ROOT))


if __name__ == "__main__":
    raise SystemExit(main())
