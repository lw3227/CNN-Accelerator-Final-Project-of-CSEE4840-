import unittest
from pathlib import Path

from gesture_runtime.mmio_runtime import (
    ScratchpadLayout,
    build_mmio_image,
    build_mmio_register_file,
    load_inference_case,
    load_preload_bundle,
)
from gesture_runtime.quantization import (
    fixed_q7_8_to_float,
    float_to_fixed_q7_8,
    quantize_u8_to_i8,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
PRELOAD_ROOT = REPO_ROOT / "Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test"
CASE_ROOT = REPO_ROOT / "Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test"


class RuntimeTests(unittest.TestCase):
    def test_layout_is_non_overlapping(self) -> None:
        layout = ScratchpadLayout()
        layout.assert_non_overlapping()

    def test_quantization_helpers(self) -> None:
        self.assertEqual(float_to_fixed_q7_8(1.0), 128)
        self.assertAlmostEqual(fixed_q7_8_to_float(64), 0.5)
        self.assertEqual(quantize_u8_to_i8([0, 255]), [-128, 127])

    def test_mmio_image_builder(self) -> None:
        layout = ScratchpadLayout()
        preload = load_preload_bundle(PRELOAD_ROOT)
        case = load_inference_case(CASE_ROOT)
        mem16 = build_mmio_image(layout, preload, case)
        regs = build_mmio_register_file(layout)

        self.assertEqual(len(preload.conv_cfg_words), 45)
        self.assertEqual(len(preload.conv_wt_words), 225)
        self.assertEqual(len(preload.fc_bias_words), 10)
        self.assertEqual(len(preload.fcw_words), 864)
        self.assertEqual(len(case.image_words), 1024)
        self.assertEqual(case.expected_class, 0)

        # first 32-bit config word split into low/high halfwords
        first_cfg_word = preload.conv_cfg_words[0] & 0xFFFFFFFF
        self.assertEqual(mem16[0], first_cfg_word & 0xFFFF)
        self.assertEqual(mem16[1], (first_cfg_word >> 16) & 0xFFFF)
        self.assertEqual(regs[10], layout.image_base_hw)


if __name__ == "__main__":
    unittest.main()
