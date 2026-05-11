"""Helpers for exporting one uploaded image into a board-consumable case folder.

The HPS C tools reuse the same file names as the hardware-aligned testbench
cases. This exporter turns an in-memory INT8 image into that directory layout
so uploaded browser images and saved test cases follow the same board path.
"""

from pathlib import Path
from typing import Iterable

from .preprocess import write_txt_int8_image


def write_inference_case(
    case_root: Path,
    image_values: Iterable[int],
    case_name: str = "gesture_upload",
    expected_class: int = -1,
) -> Path:
    """Write image data and metadata files expected by the board loaders."""
    case_root.mkdir(parents=True, exist_ok=True)

    image_path = case_root / "tb_conv1_in_i8_64x64x1.txt"
    manifest_path = case_root / "manifest.txt"

    # The FPGA-side loader packs four signed INT8 samples into each 32-bit
    # scratchpad word, so this text file remains one scalar per line and the C
    # runtime performs the final packing step.
    write_txt_int8_image(image_path, image_values)

    manifest_lines = [
        f"case={case_name}",
        "image_file=uploaded_image",
        f"conv1_input={image_path.name}",
        f"predict_class={expected_class}",
    ]
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    return case_root
