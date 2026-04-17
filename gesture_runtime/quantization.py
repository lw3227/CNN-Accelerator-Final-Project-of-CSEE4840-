"""Shared quantization helpers for host/runtime code.

The current RTL datapath is INT8 activation/weight with INT32 accumulation.
The reference Gesture design used a simple Q7.8-style short transport for some
paths; we keep those helpers here for interoperability, but the project-wide
default remains the RTL-native INT8/INT32 format.
"""

from typing import Iterable, List


Q7_8_SCALE = 128.0


def saturate_int8(value: int) -> int:
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
    return [saturate_int8(int(v) + zero_point) for v in samples]


def dequantize_q7_8_buffer(samples: Iterable[int]) -> List[float]:
    return [fixed_q7_8_to_float(v) for v in samples]
