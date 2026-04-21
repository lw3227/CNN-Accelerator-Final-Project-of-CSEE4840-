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
- [`build_soc_system.py`](build_soc_system.py)
- [`build_soc_system.cmd`](build_soc_system.cmd)
- [`build_soc_system.ps1`](build_soc_system.ps1)
- [`build_soc_system.sh`](build_soc_system.sh)
- [`BOARD_TEST_PLAN.md`](BOARD_TEST_PLAN.md)
- [`DEVELOPMENT_MAINLINE.md`](DEVELOPMENT_MAINLINE.md)
- [`device_tree/README.md`](device_tree/README.md)

## Fast Build

If Quartus is installed on the machine, the most portable rebuild entry point is:

```bash
python de1_soc/build_soc_system.py
```

Team setup check:

```bash
python de1_soc/build_soc_system.py --check
```

Verbose tool discovery:

```bash
python de1_soc/build_soc_system.py --check --verbose
```

On Windows, `--check` also validates the extra Quartus HPS/Qsys prerequisites:

- `nios2eds/Nios II Command Shell.bat`
- `WSL`
- `dos2unix` inside WSL

If a machine already trusts the committed `soc_system/synthesis/` outputs and
only needs a rebuild from the current checked-in generated HDL, use:

```bash
python de1_soc/build_soc_system.py --skip-qsys
```

There is also a tiny shell wrapper:

```bash
./de1_soc/build_soc_system.sh
```

On Windows, you can still use:

```cmd
de1_soc\build_soc_system.cmd
```

These wrappers try `PATH`, `QUARTUS_ROOTDIR`, and common Quartus install
folders automatically. You can also override each tool explicitly:

```bash
export QSYS_GENERATE=/path/to/qsys-generate
export QUARTUS_SH=/path/to/quartus_sh
export QUARTUS_CPF=/path/to/quartus_cpf
```

Then they run:

1. `qsys-generate soc_system.qsys --synthesis=VERILOG`
2. `quartus_sh --flow compile soc_system`
3. `quartus_cpf -c output_files\soc_system.sof output_files\soc_system.rbf`

There is also a PowerShell version:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc\build_soc_system.ps1
```

## Note On Historical Materials

This repository still contains older documents and older model lanes. Use the
files linked above as the current source of truth for the DE1-SoC path.
