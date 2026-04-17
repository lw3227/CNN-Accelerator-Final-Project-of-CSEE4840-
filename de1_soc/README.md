# DE1-SoC Integration Notes

This project now has a board-facing wrapper, [cnn_mmio_interface.v](/homes/user/stud/fall25/lw3227/CNN_ACC/input/RTL/interface/cnn_mmio_interface.v), intended to be exposed to the HPS as a memory-mapped Avalon slave.

## What gets instantiated on FPGA

- `cnn_mmio_interface`
- internally instantiates current `system_top`
- adds:
  - 16-bit scratchpad memory space
  - 16-bit config/status register space
  - replay engine that feeds `system_top`'s existing stream interface

There is also an FPGA-only bring-up shell:

- [cnn_mmio_demo_top.v](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/cnn_mmio_demo_top.v)

This shell is useful before full HPS assembly. It exposes:

- `model_loaded` on `LEDR[1]`
- `predict_done` on `LEDR[2]`
- `predict_class[3:0]` on `LEDR[6:3]`
- low error bits on `LEDR[9:7]`

## Recommended Platform Designer hookup

1. Create a new component from [platform_designer/cnn_mmio_interface_hw.tcl](/homes/user/stud/fall25/lw3227/CNN_ACC/platform_designer/cnn_mmio_interface_hw.tcl).
2. Connect its `clock` and `reset` to the same FPGA clock/reset domain as the lightweight HPS-FPGA bridge.
3. Export the Avalon slave on the lightweight bridge so HPS userspace can reach it through `/dev/mem`.
4. Assign a CSR base address. Example:
   - `0xff200000` for the slave window base in HPS address space
5. A starter `qsys-script` template is provided in [soc_system_template.tcl](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/soc_system_template.tcl). Update the clock/reset/HPS instance names to match your Platform Designer system before running it.
6. If you want a standalone Quartus compile for the wrapper before doing full SoC assembly, start from [CNN_ACC_mmio.qsf.template](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/CNN_ACC_mmio.qsf.template).
7. If you want an FPGA-only bring-up build with board LEDs before HPS integration, start from [cnn_mmio_demo_top.qsf.template](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/cnn_mmio_demo_top.qsf.template).
8. If you want a DE1-SoC Quartus project skeleton based on the board pinout, use [soc_system_project.tcl](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/soc_system_project.tcl).
9. A one-shot helper for indexing the custom IP and creating `de1_soc/soc_system.qsys` is available at [generate_soc_project.sh](/homes/user/stud/fall25/lw3227/CNN_ACC/de1_soc/generate_soc_project.sh).

## Addressing model

- The HPS sees a flat MMIO region in bytes.
- Inside the accelerator wrapper, addresses are interpreted as 16-bit halfwords.
- `address[19] = 0`:
  scratchpad memory
- `address[19] = 1`:
  config/status register file

Shared definitions live in [include/cnn_mmio_regs.h](/homes/user/stud/fall25/lw3227/CNN_ACC/include/cnn_mmio_regs.h).

## Default scratchpad layout

- conv cfg:
  base `0`, words `45`
- conv wt:
  base `90`, words `225`
- fc bias:
  base `540`, words `10`
- fcw:
  base `560`, words `864`
- image:
  base `2288`, words `1024`

These bases are in halfwords, not bytes.

## HPS software path

There are now two host-side frontends:

- Python mock/runtime:
  [tools/run_mmio_inference.py](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/run_mmio_inference.py)
- C `/dev/mem` example:
  [tools/hps_mmio_infer.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_infer.c)
- C staged model-load tool:
  [tools/hps_mmio_load_model.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_load_model.c)
- C staged inference tool:
  [tools/hps_mmio_run_case.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_run_case.c)
- C status probe:
  [tools/hps_mmio_status.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/hps_mmio_status.c)

The C tools now share a reusable host runtime:

- [include/cnn_mmio_host.h](/homes/user/stud/fall25/lw3227/CNN_ACC/include/cnn_mmio_host.h)
- [tools/cnn_mmio_host.c](/homes/user/stud/fall25/lw3227/CNN_ACC/tools/cnn_mmio_host.c)

Example build on HPS Linux:

```bash
make -C tools
```

Example run:

```bash
./hps_mmio_infer 0xff200000 \
  Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test \
  Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

Split bring-up flow:

```bash
./hps_mmio_load_model 0xff200000 \
  Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test

./hps_mmio_run_case 0xff200000 \
  Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

Quick status readback:

```bash
./hps_mmio_status 0xff200000
```

## Expected software sequence

1. Program register file.
2. Write preload data to scratchpad memory.
3. Write image data to scratchpad memory.
4. Write `CONTROL = CLEAR_STATUS`.
5. Write `CONTROL = MODEL_LOAD`.
6. Poll `STATUS.model_loaded`.
7. Write `CONTROL = INFER`.
8. Poll `STATUS.predict_done`.
9. Read `STATUS.predict_class` and `IF_ERROR`.

## Current status

- Functional RTL path: verified in behavioral sim
- MMIO wrapper path: verified in behavioral sim
- HPS-side mock driver path: verified in software unit tests
- HPS-side C tools: compile successfully in the project root
- DE1-SoC Quartus project generator TCL: added
- DE1-SoC project helper shell script: added
- Quartus fit: successful
- Timing: still not closed at 50 MHz slow corner, so on-board use should start with a lower clock target or further timing optimization
