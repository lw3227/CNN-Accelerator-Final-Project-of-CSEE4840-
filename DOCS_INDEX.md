# Documentation Index

This file is the top-level documentation guide for the current repository.

## Read First

- [README.md](README.md)
  Short repository overview and current active lane
- [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
  Cross-platform teammate setup, support matrix, and first commands to try
- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
  Detailed teammate runbook for rebuild, programming, board validation, web demo, and recovery after unplugging
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
  End-to-end browser -> host -> board -> FPGA -> browser flow
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
  Shared HPS-to-FPGA MMIO contract, register map, scratchpad layout, and host helper API
- [DATASET_GUIDE.md](DATASET_GUIDE.md)
  Current dataset/task semantics and how to interpret the 10 classes
- [PROJECT_STATUS_AND_PLAN.md](PROJECT_STATUS_AND_PLAN.md)
  Current snapshot summary and near-term plan
- [de1_soc/DEVELOPMENT_MAINLINE.md](de1_soc/DEVELOPMENT_MAINLINE.md)
  Best starting point for current board work

## Board Bring-Up

- [de1_soc/README.md](de1_soc/README.md)
  Landing page for DE1-SoC integration docs
- [de1_soc/BOARD_TEST_PLAN.md](de1_soc/BOARD_TEST_PLAN.md)
  Board validation notes and staged bring-up checkpoints
- [de1_soc/device_tree/README.md](de1_soc/device_tree/README.md)
  DTB patching and boot-partition handling notes
- [de1_soc/FILE_INDEX.md](de1_soc/FILE_INDEX.md)
  Current board-lane file map

## Runtime, Interfaces, And Data

- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
  Detailed runtime flow and code entry points
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
  MMIO register and scratchpad explanation
- [web_demo/README.md](web_demo/README.md)
  Host-side upload-first comparison demo
- [test_data/README.md](test_data/README.md)
  Lightweight entry point for existing hardware-aligned test cases
- [Golden-Module/README.md](Golden-Module/README.md)
  Model-side and MATLAB-side reference materials

## Environment Notes

- [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
  Cross-platform teammate setup and host-role guidance

## Historical / Legacy Areas

These are still part of the repo, but they are not the best place to start if
you are trying to continue the current DE1-SoC board path:

- older paper/rock/scissors materials under `Golden-Module/matlab/lab/`
- older simulation and archive materials under `matlab_old/`
- lab reference collateral under `lab3-hw/`

Use them as reference material, not as the primary development guide.
