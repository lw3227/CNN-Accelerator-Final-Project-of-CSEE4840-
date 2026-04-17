"""Input preprocessing helpers.

The current RTL expects a quantized 64x64x1 INT8 tensor. For hardware-aligned
tests we support direct TXT loading; for image files we expose a thin optional
Pillow-based path that applies grayscale conversion and the project's default
zero-point convention (uint8 + (-128) -> int8).
"""

from pathlib import Path
from typing import List

from .quantization import quantize_u8_to_i8


def load_txt_int8_image(path: Path) -> List[int]:
    with path.open("r", encoding="utf-8") as fp:
        return [int(line.strip()) for line in fp if line.strip()]


def load_image_to_int8(path: Path, width: int = 64, height: int = 64) -> List[int]:
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover - optional dependency
        raise RuntimeError("Pillow is required for image preprocessing") from exc

    img = Image.open(path).convert("L").resize((width, height))
    return quantize_u8_to_i8(list(img.getdata()), zero_point=-128)
