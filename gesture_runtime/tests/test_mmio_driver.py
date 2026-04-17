import unittest
from pathlib import Path

from gesture_runtime.mmio_driver import CNNAcceleratorDriver, MockMMIOBackend


REPO_ROOT = Path(__file__).resolve().parents[2]
PRELOAD_ROOT = REPO_ROOT / "Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test"
CASE_ROOT = REPO_ROOT / "Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test"


class MMIODriverTests(unittest.TestCase):
    def test_mock_driver_flow(self):
        backend = MockMMIOBackend()
        driver = CNNAcceleratorDriver(backend)
        result = driver.run_case(PRELOAD_ROOT, CASE_ROOT)

        self.assertEqual(result["predict_class"], 0)
        self.assertEqual(result["expected_class"], 0)
        self.assertEqual(result["error"], 0)
        self.assertEqual(backend.control_writes, [0x0001, 0x0002])


if __name__ == "__main__":
    unittest.main()
