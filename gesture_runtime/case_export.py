"""把上传图片导出成板端可读取 case 文件夹的工具。

HPS C 工具复用了 hardware-aligned testbench 的文件命名方式。本模块把内存里的
INT8 图片写成同样的目录结构，所以浏览器上传图片和保存好的测试样例可以走同一条
board-side loader 路径。
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
    """写出 HPS C loader 需要的图片文本文件和 manifest。"""
    case_root.mkdir(parents=True, exist_ok=True)

    image_path = case_root / "tb_conv1_in_i8_64x64x1.txt"
    manifest_path = case_root / "manifest.txt"

    # FPGA loader 会把每 4 个 signed INT8 样本打包成一个 32-bit scratchpad
    # word，所以这里仍然保持“一行一个像素值”的文本格式。
    write_txt_int8_image(image_path, image_values)

    manifest_lines = [
        f"case={case_name}",
        "image_file=uploaded_image",
        f"conv1_input={image_path.name}",
        f"predict_class={expected_class}",
    ]
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    return case_root
