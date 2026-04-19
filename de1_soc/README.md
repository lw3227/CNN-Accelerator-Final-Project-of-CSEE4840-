# DE1-SoC Integration

This folder is the current landing area for the board-facing DE1-SoC work.

## Read First

- [DEVELOPMENT_MAINLINE.md](DEVELOPMENT_MAINLINE.md)
- [BOARD_TEST_PLAN.md](BOARD_TEST_PLAN.md)
- [device_tree/README.md](device_tree/README.md)
- [FILE_INDEX.md](FILE_INDEX.md)

If you only read one file before changing board code, read
`DEVELOPMENT_MAINLINE.md`.

## What This Folder Owns

- Platform Designer / SoC assembly for the DE1-SoC board
- board top-level integration
- boot-artifact notes and DTB patch helpers
- bring-up documentation and board test flow

The board-facing accelerator contract is still:

- RTL compute core: [`../input/RTL/system_top.v`](../input/RTL/system_top.v)
- MMIO wrapper: [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v)
- shared register map: [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h)

## Current Recommended Mainline

Stay on the staged `HPS + MMIO` mainline.

- `system_top` remains the compute core
- `cnn_mmio_interface` remains the host-facing contract
- `de1_soc/` remains the board integration layer
- HPS userspace tools remain the execution path

The FPGA-only LED demo is still useful, but only as a fallback debug shell.

## Key Working Files

- [`soc_system.qsys`](soc_system.qsys)
- [`soc_system_top.sv`](soc_system_top.sv)
- [`BOARD_TEST_PLAN.md`](BOARD_TEST_PLAN.md)
- [`DEVELOPMENT_MAINLINE.md`](DEVELOPMENT_MAINLINE.md)
- [`device_tree/README.md`](device_tree/README.md)

## Note On Historical Materials

This repository still contains older documents and older model lanes. Use the
files linked above as the current source of truth for the DE1-SoC path.
