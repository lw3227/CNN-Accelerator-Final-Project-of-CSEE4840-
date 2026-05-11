"""Host/runtime 共用的量化辅助函数。

当前 RTL datapath 使用 INT8 activation/weight 和 INT32 accumulation。早期
Gesture reference 设计里有一些 Q7.8 short 格式的传输路径，所以这里保留相关
函数以兼容旧流程；但项目主路径仍然是 RTL 原生的 INT8/INT32 格式。

对于上传的灰度图片，最关键的转换是 unsigned pixel `0..255` 到 signed
activation `-128..127`。这个映射保持简单，确保 host 预览、HPS C loader 和
RTL input scratchpad 看到的是同一组 byte 值。
"""

from typing import Iterable, List


Q7_8_SCALE = 128.0


def saturate_int8(value: int) -> int:
    """把 Python 整数钳位到 RTL 使用的 signed INT8 范围。"""
    return max(-128, min(127, int(value)))


def saturate_int16(value: int) -> int:
    return max(-32768, min(32767, int(value)))


def saturate_int32(value: int) -> int:
    return max(-(2**31), min(2**31 - 1, int(value)))


def float_to_fixed_q7_8(value: float) -> int:
    return saturate_int16(round(value * Q7_8_SCALE))


def fixed_q7_8_to_float(value: int) -> float:
    return int(value) / Q7_8_SCALE


def quantize_u8_to_i8(samples: Iterable[int], zero_point: int = -128) -> List[int]:
    """把 unsigned 灰度样本映射成 signed INT8 activation 样本。"""
    return [saturate_int8(int(v) + zero_point) for v in samples]


def dequantize_q7_8_buffer(samples: Iterable[int]) -> List[float]:
    return [fixed_q7_8_to_float(v) for v in samples]
