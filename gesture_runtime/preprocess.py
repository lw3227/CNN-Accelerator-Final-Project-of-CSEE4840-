"""输入图片预处理工具。

当前 RTL 期望输入为量化后的 64x64x1 INT8 tensor。对于硬件对齐测试，我们支持
直接读取 TXT；对于浏览器上传的图片，则使用 Pillow 完成灰度化、裁剪、缩放和
量化，并且同时支持磁盘文件和内存 bytes。

Web demo 会生成两个预处理分支：
  * `plain`：保留整张图，只做归一化/resize。
  * `crop`：估计手势/数字前景，裁成正方形后再 resize 到硬件输入尺寸。

CPU-side 模型会给两个分支打分，然后 demo 选择更安全的分支导出给板子。
"""

import base64
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Iterable, List

from .quantization import quantize_u8_to_i8


@dataclass
class PreprocessedImage:
    """一个候选输入 tensor，加上浏览器预览图。"""

    mode: str
    values: List[int]
    preview_b64: str


def load_txt_int8_image(path: Path) -> List[int]:
    """读取已经量化好的 testbench 图片文本文件。"""
    with path.open("r", encoding="utf-8") as fp:
        return [int(line.strip()) for line in fp if line.strip()]


def _encode_image_b64(image) -> str:
    buf = BytesIO()
    image.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def _otsu_threshold(arr) -> int:
    """计算自动灰度阈值，用于前景/背景分离。"""
    import numpy as np

    hist = np.bincount(arr.reshape(-1), minlength=256).astype(np.float64)
    total = arr.size
    cumulative = np.cumsum(hist)
    cumulative_mean = np.cumsum(hist * np.arange(256))
    global_mean = cumulative_mean[-1] / max(total, 1)

    numerator = (global_mean * cumulative - cumulative_mean) ** 2
    denominator = cumulative * (total - cumulative)
    with np.errstate(divide="ignore", invalid="ignore"):
        score = numerator / denominator
    score[~np.isfinite(score)] = 0.0
    return int(score.argmax())


def _select_foreground_mask(arr):
    """判断暗色像素还是亮色像素更像前景。"""
    import numpy as np

    threshold = _otsu_threshold(arr)
    dark_mask = arr <= threshold
    light_mask = arr >= threshold
    border = np.concatenate([arr[0, :], arr[-1, :], arr[:, 0], arr[:, -1]])
    bg_hint = int(np.median(border))

    def score(mask):
        area = float(mask.mean())
        border_frac = float(
            np.concatenate([mask[0, :], mask[-1, :], mask[:, 0], mask[:, -1]]).mean()
        )
        area_penalty = 0.0
        if area < 0.01:
            area_penalty += 1.0
        if area > 0.85:
            area_penalty += 1.0
        return border_frac + area_penalty

    if bg_hint >= threshold:
        preferred = dark_mask
        alternate = light_mask
    else:
        preferred = light_mask
        alternate = dark_mask

    return preferred if score(preferred) <= score(alternate) else alternate


def _estimate_background_level(arr) -> int:
    import numpy as np

    border = np.concatenate([arr[0, :], arr[-1, :], arr[:, 0], arr[:, -1]])
    return int(np.median(border))


def _canonical_background_level(bg_level: int) -> int:
    # Snap the background to a clean binary pole so upload previews and model
    # input do not retain curtain / wall gradients after foreground extraction.
    return 255 if bg_level >= 128 else 0


def _largest_connected_component(mask):
    """只保留最大的连通前景区域，去掉小噪点。"""
    import numpy as np

    height, width = mask.shape
    visited = np.zeros((height, width), dtype=bool)
    best_component = []

    for y in range(height):
        for x in range(width):
            if not mask[y, x] or visited[y, x]:
                continue

            stack = [(y, x)]
            visited[y, x] = True
            component = []

            while stack:
                cy, cx = stack.pop()
                component.append((cy, cx))
                for ny in range(max(0, cy - 1), min(height, cy + 2)):
                    for nx in range(max(0, cx - 1), min(width, cx + 2)):
                        if visited[ny, nx] or not mask[ny, nx]:
                            continue
                        visited[ny, nx] = True
                        stack.append((ny, nx))

            if len(component) > len(best_component):
                best_component = component

    if not best_component:
        return mask

    refined = np.zeros_like(mask, dtype=bool)
    for y, x in best_component:
        refined[y, x] = True
    return refined


def _refine_foreground_mask(mask):
    import numpy as np
    from PIL import Image, ImageFilter

    mask_img = Image.fromarray((mask.astype(np.uint8) * 255), mode="L")
    # Close small gaps first, then trim isolated speckles.
    mask_img = mask_img.filter(ImageFilter.MaxFilter(5))
    mask_img = mask_img.filter(ImageFilter.MinFilter(5))
    mask_img = mask_img.filter(ImageFilter.MaxFilter(3))
    refined = np.array(mask_img, dtype=np.uint8) >= 128
    return _largest_connected_component(refined)


def _crop_and_square_image(image, width: int, height: int):
    """提取前景目标，并 resize 到 RTL 需要的输入尺寸。"""
    import numpy as np
    from PIL import Image, ImageOps

    gray = ImageOps.autocontrast(image.convert("L"))
    arr = np.array(gray, dtype=np.uint8)
    bg_level = _canonical_background_level(_estimate_background_level(arr))
    mask = _refine_foreground_mask(_select_foreground_mask(arr))

    ys, xs = np.nonzero(mask)
    if len(xs) == 0 or len(ys) == 0:
        cropped = gray
    else:
        x0, x1 = xs.min(), xs.max()
        y0, y1 = ys.min(), ys.max()
        box_w = x1 - x0 + 1
        box_h = y1 - y0 + 1
        pad_x = max(2, int(box_w * 0.12))
        pad_y = max(2, int(box_h * 0.12))
        x0 = max(0, x0 - pad_x)
        y0 = max(0, y0 - pad_y)
        x1 = min(arr.shape[1] - 1, x1 + pad_x)
        y1 = min(arr.shape[0] - 1, y1 + pad_y)

        masked_arr = np.full_like(arr, bg_level)
        masked_arr[mask] = arr[mask]
        masked = Image.fromarray(masked_arr, mode="L")
        cropped = masked.crop((int(x0), int(y0), int(x1 + 1), int(y1 + 1)))

    side = max(cropped.size)
    square = Image.new("L", (side, side), color=bg_level)
    offset = ((side - cropped.size[0]) // 2, (side - cropped.size[1]) // 2)
    square.paste(cropped, offset)
    return square.resize((width, height))


def _plain_resize_image(image, width: int, height: int):
    """生成直接 resize 的保守分支。"""
    from PIL import ImageOps

    return ImageOps.autocontrast(image.convert("L")).resize((width, height))


def _image_to_int8(image) -> List[int]:
    """把 unsigned 灰度像素量化成 signed INT8 activation。"""
    return quantize_u8_to_i8(list(image.getdata()), zero_point=-128)


def _preprocess_image(image, width: int, height: int, mode: str) -> PreprocessedImage:
    """执行一个预处理分支，并打包 tensor 与预览图。"""
    if mode == "plain":
        processed = _plain_resize_image(image, width, height)
    elif mode == "crop":
        processed = _crop_and_square_image(image, width, height)
    else:
        raise ValueError(f"unknown preprocess mode: {mode}")
    return PreprocessedImage(mode=mode, values=_image_to_int8(processed), preview_b64=_encode_image_b64(processed))


def preprocess_image_bytes_variants(image_bytes: bytes, width: int = 64, height: int = 64) -> List[PreprocessedImage]:
    """解码上传图片 bytes，并返回所有候选预处理分支。"""
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover - optional dependency
        raise RuntimeError("Pillow is required for image preprocessing") from exc

    with Image.open(BytesIO(image_bytes)) as img:
        return [
            _preprocess_image(img, width, height, "plain"),
            _preprocess_image(img, width, height, "crop"),
        ]


def render_preprocessed_preview_b64(image_bytes: bytes, width: int = 64, height: int = 64) -> str:
    return preprocess_image_bytes_variants(image_bytes, width, height)[1].preview_b64


def load_image_bytes_to_int8(image_bytes: bytes, width: int = 64, height: int = 64) -> List[int]:
    return preprocess_image_bytes_variants(image_bytes, width, height)[1].values


def load_image_to_int8(path: Path, width: int = 64, height: int = 64) -> List[int]:
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover - optional dependency
        raise RuntimeError("Pillow is required for image preprocessing") from exc

    with Image.open(path) as img:
        return _preprocess_image(img, width, height, "crop").values


def write_txt_int8_image(path: Path, values: Iterable[int]) -> None:
    """写出“一行一个 signed INT8 值”的文本文件，供 HPS C loader 读取。"""
    with path.open("w", encoding="utf-8") as fp:
        for value in values:
            fp.write(f"{int(value)}\n")
