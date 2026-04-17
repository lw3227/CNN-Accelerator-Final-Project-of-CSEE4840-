"""Driver-like MMIO helpers for cnn_mmio_interface.

This is the host-side counterpart to the RTL wrapper. It mirrors the roles of
Gesture's old memory_ioctl/main split without requiring a Linux kernel driver.
"""

import os
import struct
import time

from .mmio_runtime import (
    ScratchpadLayout,
    build_mmio_image,
    build_mmio_register_file,
    load_inference_case,
    load_preload_bundle,
)


class MMIOBackend(object):
    def write16(self, address, value):
        raise NotImplementedError

    def read16(self, address):
        raise NotImplementedError


class MockMMIOBackend(MMIOBackend):
    """Simple software model for transaction verification.

    It records memory/register writes and can be seeded with status/predict
    values. This keeps host-side logic testable even when no real SoC fabric is
    available.
    """

    def __init__(self):
        self.space = {}
        self.control_writes = []
        self.next_status = 0x000C  # model_loaded=1, predict_done=1, class=0
        self.next_error = 0x0000

    def write16(self, address, value):
        self.space[address] = value & 0xFFFF
        if (address >> 19) & 0x1 and (address & 0x1F) == 0:
            self.control_writes.append(value & 0xFFFF)
            if value & 0x0001:
                self.next_status = 0x0004
            if value & 0x0002:
                self.next_status = 0x000C

    def read16(self, address):
        if (address >> 19) & 0x1:
            reg_idx = address & 0x1F
            if reg_idx == 1:
                return self.next_status
            if reg_idx == 12:
                return (self.next_status >> 4) & 0xF
            if reg_idx == 13:
                return self.next_error
        return self.space.get(address, 0)


class DevMemBackend(MMIOBackend):
    """Very small /dev/mem-style backend.

    This is intentionally thin and only meant for future HPS bring-up. It is
    not exercised in the current environment.
    """

    def __init__(self, mem_file, base_addr):
        self._fd = os.open(mem_file, os.O_RDWR | os.O_SYNC)
        self._base_addr = int(base_addr)

    def close(self):
        if self._fd is not None:
            os.close(self._fd)
            self._fd = None

    def write16(self, address, value):
        os.lseek(self._fd, self._base_addr + address * 2, os.SEEK_SET)
        os.write(self._fd, struct.pack("<H", value & 0xFFFF))

    def read16(self, address):
        os.lseek(self._fd, self._base_addr + address * 2, os.SEEK_SET)
        raw = os.read(self._fd, 2)
        return struct.unpack("<H", raw)[0]


class CNNAcceleratorDriver(object):
    def __init__(self, backend, layout=None):
        self.backend = backend
        self.layout = layout or ScratchpadLayout()

    @staticmethod
    def _cfg_addr(reg_idx):
        return (1 << 19) | (reg_idx & 0x1F)

    @staticmethod
    def _mem_addr(halfword_addr):
        return halfword_addr & ((1 << 19) - 1)

    def write_registers(self, reg_file):
        for reg_idx, value in sorted(reg_file.items()):
            self.backend.write16(self._cfg_addr(reg_idx), value)

    def write_memory_image(self, mem_image):
        for halfword_addr, value in sorted(mem_image.items()):
            self.backend.write16(self._mem_addr(halfword_addr), value)

    def trigger_model_load(self):
        self.backend.write16(self._cfg_addr(0), 0x0001)

    def trigger_inference(self):
        self.backend.write16(self._cfg_addr(0), 0x0002)

    def read_status(self):
        return self.backend.read16(self._cfg_addr(1))

    def read_predict_class(self):
        return self.backend.read16(self._cfg_addr(12)) & 0xF

    def read_error(self):
        return self.backend.read16(self._cfg_addr(13))

    def wait_for_status_bit(self, bit_idx, expected_value, timeout_s=1.0, poll_s=0.001):
        deadline = time.time() + timeout_s
        while time.time() < deadline:
          status = self.read_status()
          if ((status >> bit_idx) & 0x1) == expected_value:
              return status
          time.sleep(poll_s)
        raise RuntimeError(
            "Timeout waiting for status bit {} == {} (last status=0x{:04x})".format(
                bit_idx, expected_value, self.read_status()
            )
        )

    def run_case(self, preload_root, case_root):
        preload = load_preload_bundle(preload_root)
        case = load_inference_case(case_root)
        reg_file = build_mmio_register_file(self.layout)
        mem_image = build_mmio_image(self.layout, preload, case)

        self.write_registers(reg_file)
        self.write_memory_image(mem_image)

        self.trigger_model_load()
        self.wait_for_status_bit(2, 1)

        self.trigger_inference()
        self.wait_for_status_bit(3, 1)

        return {
            "expected_class": case.expected_class,
            "predict_class": self.read_predict_class(),
            "status": self.read_status(),
            "error": self.read_error(),
        }
