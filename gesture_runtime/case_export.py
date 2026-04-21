"""Helpers for exporting one uploaded image into a board-consumable case folder."""

from pathlib import Path
from typing import Iterable

from .preprocess import write_txt_int8_image


def write_inference_case(
    case_root: Path,
    image_values: Iterable[int],
    case_name: str = "gesture_upload",
    expected_class: int = -1,
) -> Path:
    case_root.mkdir(parents=True, exist_ok=True)

    image_path = case_root / "tb_conv1_in_i8_64x64x1.txt"
    manifest_path = case_root / "manifest.txt"

    write_txt_int8_image(image_path, image_values)

    manifest_lines = [
        f"case={case_name}",
        "image_file=uploaded_image",
        f"conv1_input={image_path.name}",
        f"predict_class={expected_class}",
    ]
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    return case_root
