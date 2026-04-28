# Architecture And File Map

This document is the teammate-facing map of the current submission branch.

Use it when you need to answer:

- which directory owns which part of the project
- which file is the real source of truth for a given layer
- how the software path reaches the hardware path
- which files you should edit for a specific kind of change

## One-Screen Architecture

The current validated path is:

```text
browser
  -> web_demo/app.py
  -> gesture_runtime/*
  -> SSH/SCP to board
  -> board-side HPS tools in tools/
  -> /dev/mem mmap at 0xff200000
  -> lightweight HPS-to-FPGA bridge
  -> cnn_mmio_interface
  -> system_top
  -> conv / SRAM / FC / argmax RTL
  -> status + profile + predict_class back through MMIO
  -> SSH response to host
  -> Flask JSON response
  -> browser UI
```

## Directory Ownership

| Directory | What it owns | Files to start with |
| --- | --- | --- |
| `docs/` | teammate-facing documentation | `README.md`, `TEAM_RUNBOOK.md` |
| `web_demo/` | Flask app and UI | [`../web_demo/app.py`](../web_demo/app.py), [`../web_demo/README.md`](../web_demo/README.md) |
| `gesture_runtime/` | host-side preprocess, export, SSH/SCP, demo orchestration | [`../gesture_runtime/preprocess.py`](../gesture_runtime/preprocess.py), [`../gesture_runtime/demo_compare.py`](../gesture_runtime/demo_compare.py), [`../gesture_runtime/fpga_service.py`](../gesture_runtime/fpga_service.py) |
| `tools/` | board-side C tools and host-side bring-up helpers | [`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c), [`../tools/hps_mmio_predict.c`](../tools/hps_mmio_predict.c), [`../tools/prepare_web_demo.py`](../tools/prepare_web_demo.py) |
| `include/` | shared MMIO constants and C structs | [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h), [`../include/cnn_mmio_host.h`](../include/cnn_mmio_host.h) |
| `input/RTL/` | actual accelerator RTL | [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v), [`../input/RTL/system_top.v`](../input/RTL/system_top.v) |
| `de1_soc/` | Quartus / Qsys / board top-level integration | [`../de1_soc/build_soc_system.py`](../de1_soc/build_soc_system.py), [`../de1_soc/soc_system.qsys`](../de1_soc/soc_system.qsys), [`../de1_soc/soc_system_top.sv`](../de1_soc/soc_system_top.sv) |
| `Golden-Module/` | model artifacts and hardware-aligned exported inputs | [`../Golden-Module/README.md`](../Golden-Module/README.md) |
| `test_data/` | lightweight local/mock entry points | [`../test_data/README.md`](../test_data/README.md), [`../test_data/run_case.py`](../test_data/run_case.py) |

## Current Source Of Truth By Layer

### 1. Browser / Host App

- HTTP/API entry:
  [`../web_demo/app.py`](../web_demo/app.py)
- host/board config:
  [`../web_demo/config.py`](../web_demo/config.py)
- local board/demo settings:
  `../web_demo/demo_config.json`
- UI templates and JS:
  `../web_demo/templates/`, `../web_demo/static/`

### 2. Host Runtime And Transport

- preprocess and quantized `64x64x1` tensor construction:
  [`../gesture_runtime/preprocess.py`](../gesture_runtime/preprocess.py)
- temporary exported case folder:
  [`../gesture_runtime/case_export.py`](../gesture_runtime/case_export.py)
- host-side orchestration:
  [`../gesture_runtime/demo_compare.py`](../gesture_runtime/demo_compare.py)
- board SSH/SCP transport:
  [`../gesture_runtime/ssh_transport.py`](../gesture_runtime/ssh_transport.py)
- FPGA-service command wrapper:
  [`../gesture_runtime/fpga_service.py`](../gesture_runtime/fpga_service.py)

### 3. Board-Side C Tools

- shared devmem/MMIO helper library:
  [`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c)
- board status:
  [`../tools/hps_mmio_status.c`](../tools/hps_mmio_status.c)
- one-time model preload:
  [`../tools/hps_mmio_load_model.c`](../tools/hps_mmio_load_model.c)
- board run after model is loaded:
  [`../tools/hps_mmio_run_case.c`](../tools/hps_mmio_run_case.c)
- board FPGA timing/predict path used by web demo:
  [`../tools/hps_mmio_predict.c`](../tools/hps_mmio_predict.c)
- board CPU software baseline:
  [`../tools/hps_cpu_reference.c`](../tools/hps_cpu_reference.c)

### 4. Shared MMIO Contract

- register indices, scratchpad base addresses, control bits:
  [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h)
- C-side structures for preload/image/profile:
  [`../include/cnn_mmio_host.h`](../include/cnn_mmio_host.h)

### 5. RTL Source Of Truth

- board-facing MMIO wrapper:
  [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v)
- compute-core integration top:
  [`../input/RTL/system_top.v`](../input/RTL/system_top.v)
- network-level sequencing / model-load / infer control:
  [`../input/RTL/fsm/top_fsm.v`](../input/RTL/fsm/top_fsm.v)
- convolution frontend / SA feed path:
  [`../input/RTL/conv_core/conv_top.v`](../input/RTL/conv_core/conv_top.v)
- SRAM_B / FC reorder path:
  [`../input/RTL/SRAM/top_sram_B.v`](../input/RTL/SRAM/top_sram_B.v)

### 6. Board Project Assembly

- custom-IP packaging for the current active MMIO block:
  [`../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl`](../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl)
- system-level interconnect / HPS instantiation:
  [`../de1_soc/soc_system.qsys`](../de1_soc/soc_system.qsys)
- real Quartus top-level entity:
  [`../de1_soc/soc_system_top.sv`](../de1_soc/soc_system_top.sv)
- build wrapper that regenerates HDL, patches debug ports, compiles, and emits `.rbf`:
  [`../de1_soc/build_soc_system.py`](../de1_soc/build_soc_system.py)

### 7. Generated Files Versus Hand-Edited Files

Hand-edit these:

- `../input/RTL/**`
- `../include/**`
- `../tools/**`
- `../gesture_runtime/**`
- `../web_demo/**`
- `../de1_soc/soc_system.qsys`
- `../de1_soc/soc_system_top.sv`
- `../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl`

Do not treat these as the first place to edit logic:

- `../de1_soc/soc_system/synthesis/**`
- `../de1_soc/soc_system.sopcinfo`
- `../de1_soc/soc_system/soc_system.xml`

Those are generated artifacts produced by Qsys/Quartus.

## How The Custom IP Becomes "One Block"

The project treats the accelerator-side RTL as one Platform Designer component
through:

- [`../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl`](../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl)

That file:

- names the component `cnn_mmio_interface`
- declares its top-level RTL module
- lists the RTL files that belong to the component
- declares the clock/reset/Avalon-MM interfaces seen by Qsys

Then:

1. `soc_system.qsys` instantiates `cnn_mmio_interface_0`
2. `qsys-generate` expands the system into `de1_soc/soc_system/synthesis/*`
3. `build_soc_system.py` patches generated debug ports in `soc_system.v`
4. Quartus compiles `soc_system_top` around that generated `soc_system`

## Where To Edit For Common Tasks

| Goal | Edit here first |
| --- | --- |
| Change web request flow | `web_demo/app.py`, `gesture_runtime/demo_compare.py` |
| Change preprocess | `gesture_runtime/preprocess.py` |
| Change SSH/SCP behavior | `gesture_runtime/ssh_transport.py` |
| Change MMIO register layout | `include/cnn_mmio_regs.h`, `input/RTL/interface/cnn_mmio_interface.v`, then host tools |
| Change HPS C tool behavior | `tools/cnn_mmio_host.c`, `tools/hps_mmio_*.c` |
| Change load/infer RTL sequencing | `input/RTL/fsm/top_fsm.v` |
| Change conv datapath timing/pipelining | `input/RTL/conv_core/conv_top.v` |
| Change SRAM_B / FC reordering | `input/RTL/SRAM/top_sram_B.v`, `input/RTL/SRAM/sram_B_controller.v` |
| Change board top pins / seven-seg debug | `de1_soc/soc_system_top.sv` |
| Change the board system wiring | `de1_soc/soc_system.qsys` |
| Repackage the custom MMIO IP | `de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl` |

## Current "Mainline" Rule

For this branch, treat the current development lane as:

`HPS Linux userspace + MMIO wrapper + FPGA compute core`

Do not treat these as the primary current lane:

- `platform_designer/` template/index files
- older root-level Quartus projects moved under `archive_unused/`
- `matlab_old/`, `vf/`, `lab3-hw/`

Those are useful references, but not the branch's main execution path.
