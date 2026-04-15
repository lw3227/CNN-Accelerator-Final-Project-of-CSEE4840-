#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable

import cv2


VALID_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".webp"}
DEFAULT_SPLITS = ("train", "test", "validation")


def iter_images(folder: Path) -> Iterable[Path]:
    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() in VALID_EXTS:
            yield p


def preprocess_one(src: Path, dst: Path, size: int) -> bool:
    img = cv2.imread(str(src), cv2.IMREAD_GRAYSCALE)
    if img is None:
        return False
    img = cv2.resize(img, (size, size), interpolation=cv2.INTER_AREA)
    dst.parent.mkdir(parents=True, exist_ok=True)
    return cv2.imwrite(str(dst), img)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Save grayscale + resized copies of dataset images to local disk."
    )
    parser.add_argument(
        "--src",
        type=Path,
        default=Path("../dataset_wlx"),
        help="Source dataset root (default: ../dataset_wlx)",
    )
    parser.add_argument(
        "--dst",
        type=Path,
        default=Path("dataset_wlx_gray64"),
        help="Output dataset root (default: dataset_wlx_gray64)",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=64,
        help="Target width/height in pixels (default: 64)",
    )
    args = parser.parse_args()

    src_root = args.src.resolve()
    dst_root = args.dst.resolve()

    if not src_root.exists():
        raise FileNotFoundError(f"Source folder not found: {src_root}")

    total_ok = 0
    total_fail = 0

    for split in DEFAULT_SPLITS:
        split_src = src_root / split
        if not split_src.exists():
            print(f"[WARN] Skip missing split: {split_src}")
            continue

        split_ok = 0
        split_fail = 0
        for img_path in iter_images(split_src):
            rel = img_path.relative_to(src_root)
            dst_path = dst_root / rel
            dst_path = dst_path.with_suffix(".png")
            if preprocess_one(img_path, dst_path, args.size):
                split_ok += 1
            else:
                split_fail += 1

        total_ok += split_ok
        total_fail += split_fail
        print(f"[{split}] ok={split_ok}, fail={split_fail}")

    print(f"[DONE] output={dst_root}")
    print(f"[TOTAL] ok={total_ok}, fail={total_fail}")


if __name__ == "__main__":
    main()
