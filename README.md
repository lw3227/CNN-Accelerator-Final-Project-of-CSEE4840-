# CNN_ACC

This repository contains a CNN accelerator project that now has two important
working lanes:

- the original RTL / simulation lane centered on `input/RTL/system_top.v`
- the current DE1-SoC board lane centered on `HPS + MMIO + FPGA`

The current active development baseline is the DE1-SoC integration lane on the
branch snapshot `snapshot/de1-soc-mmio-baseline-20260419`.

## Current Status

- Accelerator core: present in `input/RTL/`
- Board-facing MMIO wrapper: `input/RTL/interface/cnn_mmio_interface.v`
- Shared register contract: `include/cnn_mmio_regs.h`
- HPS userspace tools: `tools/`
- DE1-SoC integration project: `de1_soc/`
- Python-side runtime helpers: `gesture_runtime/`

The validated board path is:

`HPS Linux userspace -> lightweight HPS-FPGA bridge -> cnn_mmio_interface -> system_top`

For teammates, the most useful doc split is:

- [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
  Cross-platform host-role guidance and first commands to try
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
  Detailed browser -> host -> board -> FPGA runtime flow
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
  Shared register map, scratchpad layout, and host helper contract at
  `0xff200000`

## Start Here

Read these first:

- [DOCS_INDEX.md](DOCS_INDEX.md)
- [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- [DATASET_GUIDE.md](DATASET_GUIDE.md)
- [PROJECT_STATUS_AND_PLAN.md](PROJECT_STATUS_AND_PLAN.md)
- [de1_soc/DEVELOPMENT_MAINLINE.md](de1_soc/DEVELOPMENT_MAINLINE.md)

If you are working on board bring-up specifically, then read:

- [de1_soc/README.md](de1_soc/README.md)
- [de1_soc/BOARD_TEST_PLAN.md](de1_soc/BOARD_TEST_PLAN.md)

## Repository Map

- `input/RTL/`
  Main accelerator RTL
- `include/`
  Shared MMIO register and host definitions
- `tools/`
  HPS-side C tools and host-side helper scripts
- `gesture_runtime/`
  Python preprocessing and MMIO runtime helpers
- `de1_soc/`
  Board integration, Platform Designer outputs, bring-up notes
- `Golden-Module/`
  Model, MATLAB, and notebook-side reference assets
- `test_data/`
  Lightweight entry points for existing hardware-aligned test cases

## Current Mainline

Stay on the staged `HPS + MMIO` mainline.

- `system_top` remains the compute core
- `cnn_mmio_interface` remains the host-facing contract
- `de1_soc/` remains the board integration layer
- HPS userspace tools remain the board execution path

Do not treat older paper/rock/scissors materials as the current board mainline.
They are still useful as historical references, but they are not the primary
development path now.

For the current model/data interpretation, treat the active task as a
**10-class sign-language gesture** problem. Existing `digit_*` case-folder names
are legacy artifact names for gesture class IDs, not a statement that the
project has reverted to handwritten-digit semantics.

## Quick Commands

Build HPS-side tools:

```bash
make -C tools
```

Run one local mock MMIO case:

```bash
python test_data/run_case.py digit_0_test
```

Typical board-side staged flow:

```bash
./tools/hps_mmio_status 0xff200000
./tools/hps_mmio_load_model 0xff200000 <preload_root>
./tools/hps_mmio_run_case 0xff200000 <case_root>
```

Rebuild the DE1-SoC Quartus project from the repository root:

```bash
python de1_soc/build_soc_system.py
```

Quick team environment check:

```bash
python de1_soc/build_soc_system.py --check
```

or on Windows:

```cmd
de1_soc\build_soc_system.cmd
```

## Documentation Policy

This repository has accumulated both active docs and historical docs.

- Active entry-point docs are linked from [DOCS_INDEX.md](DOCS_INDEX.md)
- DE1-SoC working docs live under `de1_soc/`
- Older model-lab and historical reference docs are kept in place, but should
  not be used as the first place to orient on the current board path
