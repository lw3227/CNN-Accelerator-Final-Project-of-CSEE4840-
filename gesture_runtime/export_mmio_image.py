#!/usr/bin/env python3
"""Emit a human-readable MMIO image plan for cnn_mmio_interface."""

import argparse
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from gesture_runtime.mmio_runtime import (
        ScratchpadLayout,
        build_mmio_image,
        build_mmio_register_file,
        load_inference_case,
        load_preload_bundle,
    )
else:
    from .mmio_runtime import (
        ScratchpadLayout,
        build_mmio_image,
        build_mmio_register_file,
        load_inference_case,
        load_preload_bundle,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preload-root", type=Path, required=True)
    parser.add_argument("--case-root", type=Path, required=True)
    args = parser.parse_args()

    layout = ScratchpadLayout()
    preload = load_preload_bundle(args.preload_root)
    case = load_inference_case(args.case_root)
    mem16 = build_mmio_image(layout, preload, case)
    regs = build_mmio_register_file(layout)

    print("# config registers")
    for reg_idx, value in sorted(regs.items()):
        print(f"cfg[{reg_idx}] = {value}")
    print("# first 16 memory halfwords")
    for addr in range(16):
        print(f"mem[{addr}] = {mem16.get(addr, 0)}")


if __name__ == "__main__":
    main()
