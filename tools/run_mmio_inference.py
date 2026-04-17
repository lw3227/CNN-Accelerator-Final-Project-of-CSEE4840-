#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from gesture_runtime.mmio_driver import CNNAcceleratorDriver, DevMemBackend, MockMMIOBackend


def build_backend(args):
    if args.backend == "mock":
        return MockMMIOBackend()
    return DevMemBackend(args.mem_file, args.base_addr)


def main():
    parser = argparse.ArgumentParser(description="Run one inference through cnn_mmio_interface")
    parser.add_argument("--preload-root", type=Path, required=True)
    parser.add_argument("--case-root", type=Path, required=True)
    parser.add_argument("--backend", choices=["mock", "devmem"], default="mock")
    parser.add_argument("--mem-file", default="/dev/mem")
    parser.add_argument("--base-addr", type=lambda x: int(x, 0), default=0)
    args = parser.parse_args()

    backend = build_backend(args)
    try:
        driver = CNNAcceleratorDriver(backend)
        result = driver.run_case(args.preload_root, args.case_root)
    finally:
        if hasattr(backend, "close"):
            backend.close()

    print("expected_class={}".format(result["expected_class"]))
    print("predict_class={}".format(result["predict_class"]))
    print("status=0x{:04x}".format(result["status"]))
    print("error=0x{:04x}".format(result["error"]))

    if result["predict_class"] != result["expected_class"] or result["error"] != 0:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
