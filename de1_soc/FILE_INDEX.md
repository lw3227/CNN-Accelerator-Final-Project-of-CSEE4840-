# DE1-SoC File Index

This file is a compact map of the current board-development lane.

## Read In This Order

- [DEVELOPMENT_MAINLINE.md](DEVELOPMENT_MAINLINE.md)
- [BOARD_TEST_PLAN.md](BOARD_TEST_PLAN.md)
- [README.md](README.md)
- [device_tree/README.md](device_tree/README.md)

## Core Integration Files

- [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v)
- [`../input/RTL/system_top.v`](../input/RTL/system_top.v)
- [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h)
- [`soc_system.qsys`](soc_system.qsys)
- [`soc_system_top.sv`](soc_system_top.sv)

## Host / Board Tooling

- [`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c)
- [`../tools/hps_mmio_status.c`](../tools/hps_mmio_status.c)
- [`../tools/hps_mmio_load_model.c`](../tools/hps_mmio_load_model.c)
- [`../tools/hps_mmio_run_case.c`](../tools/hps_mmio_run_case.c)
- [`../tools/hps_mmio_infer.c`](../tools/hps_mmio_infer.c)
- [`../tools/run_hps_board_flow.py`](../tools/run_hps_board_flow.py)
- [`../tools/run_hps_digit_suite.py`](../tools/run_hps_digit_suite.py)

## Python Runtime Helpers

- [`../gesture_runtime/preprocess.py`](../gesture_runtime/preprocess.py)
- [`../gesture_runtime/mmio_runtime.py`](../gesture_runtime/mmio_runtime.py)
- [`../gesture_runtime/mmio_driver.py`](../gesture_runtime/mmio_driver.py)
- [`../tools/run_mmio_inference.py`](../tools/run_mmio_inference.py)

## Boot / Device Tree Helpers

- [`device_tree/README.md`](device_tree/README.md)
- [`device_tree/patch_socfpga_dts.py`](device_tree/patch_socfpga_dts.py)
- [`device_tree/build_soc_system_dtb.ps1`](device_tree/build_soc_system_dtb.ps1)
- [`device_tree/stage_boot_partition.ps1`](device_tree/stage_boot_partition.ps1)
- [`device_tree/restore_boot_partition.ps1`](device_tree/restore_boot_partition.ps1)

## Historical Or Less Important For Daily Work

These still matter, but you usually do not need to start here:

- generated files under `soc_system/`
- handoff contents under `hps_isw_handoff/`
- capture artifacts under `boot_capture/`
