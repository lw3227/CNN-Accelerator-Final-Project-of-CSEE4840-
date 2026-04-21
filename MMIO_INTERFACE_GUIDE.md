# MMIO Interface Guide

This document explains the shared host-to-FPGA MMIO contract used by the
current DE1-SoC board lane.

Use this file when you need to answer:

- what lives at `0xff200000`
- how the HPS tools pack model and image data for the RTL
- which registers and scratchpad regions matter
- what the canonical model-load and inference sequences are

The authoritative shared headers are:

- [include/cnn_mmio_regs.h](include/cnn_mmio_regs.h)
- [include/cnn_mmio_host.h](include/cnn_mmio_host.h)

## What The Contract Connects

The current working chain is:

`HPS userspace tool -> /dev/mem mmap -> lightweight HPS-FPGA bridge -> cnn_mmio_interface -> system_top`

Important code entry points:

- host helper library:
  [tools/cnn_mmio_host.c](tools/cnn_mmio_host.c)
- board CLI tools:
  [tools/hps_mmio_status.c](tools/hps_mmio_status.c),
  [tools/hps_mmio_load_model.c](tools/hps_mmio_load_model.c),
  [tools/hps_mmio_predict.c](tools/hps_mmio_predict.c)
- RTL wrapper:
  [input/RTL/interface/cnn_mmio_interface.v](input/RTL/interface/cnn_mmio_interface.v)
- compute core:
  [input/RTL/system_top.v](input/RTL/system_top.v)

## Base Address And Addressing Model

The validated board base address is:

```text
0xff200000
```

Userspace maps that region with:

- map span:
  `CNN_MMIO_MAP_SPAN_BYTES = 4 MiB`
- open path:
  `/dev/mem`

The shared contract is **halfword-indexed**, not byte-indexed.

That means:

- the RTL interprets addresses as 16-bit locations
- host helper code conceptually works in 16-bit register / scratchpad units
- the C helper then packs adjacent 16-bit values into 32-bit MMIO writes for
  convenience

From [include/cnn_mmio_regs.h](include/cnn_mmio_regs.h):

- `address[19] = 0`
  scratchpad memory space
- `address[19] = 1`
  config / status register space

## Space Layout

| Space | Range | Purpose |
| --- | --- | --- |
| Scratchpad memory | `0x00000..0x7FFFF` | staging area for preload data and inference image words |
| Config / status | `0x80000..0x8001F` | control, region base/length registers, predict/status/error, per-layer profile counters |

In practice, most code should use the helper APIs instead of hand-writing
addresses. The helpers already know how to pack the register pairs correctly.

## Config / Status Registers

These register indices come from
[include/cnn_mmio_regs.h](include/cnn_mmio_regs.h).

| Register | Meaning |
| --- | --- |
| `CONTROL` | write-only control register |
| `STATUS` | busy, model-loaded, predict-done, and predicted-class bits |
| `CONV_CFG_BASE`, `CONV_CFG_LEN` | preload region for convolution config words |
| `CONV_WT_BASE`, `CONV_WT_LEN` | preload region for packed convolution weights |
| `FC_BIAS_BASE`, `FC_BIAS_LEN` | preload region for FC bias words |
| `FCW_BASE`, `FCW_LEN` | preload region for FC weight words |
| `IMAGE_BASE`, `IMAGE_LEN` | inference-image region |
| `PREDICT` | logical predicted class, typically read back through `STATUS` helper paths |
| `IF_ERROR` | interface / flow error word from the MMIO wrapper |
| `PROFILE_*` | per-layer cycle counters exported by the RTL |

### Control Bits

| Bit mask | Meaning |
| --- | --- |
| `0x0001` | start model load |
| `0x0002` | start inference |
| `0x0004` | clear latched status |

### Status Bits

| Bit | Meaning |
| --- | --- |
| bit 1 | accelerator busy |
| bit 2 | preload model has been loaded into the hardware path |
| bit 3 | inference finished |
| bits starting at bit 4 | predicted class nibble |

Use the helpers when possible:

- `cnn_mmio_read_status(...)`
- `cnn_mmio_read_error(...)`
- `cnn_mmio_read_predict(...)`
- `cnn_mmio_wait_for_status_bit(...)`

## Default Scratchpad Layout

The current helpers program the following default regions before running
either model load or inference:

| Region | Base halfword address | Words |
| --- | --- | --- |
| Conv config | `0` | `45` |
| Conv weights | `90` | `225` |
| FC bias | `540` | `10` |
| FC weights | `560` | `864` |
| Input image | `2288` | `1024` |

These constants are shared between software and RTL through
[include/cnn_mmio_regs.h](include/cnn_mmio_regs.h).

## Host-Side Data Structures

From [include/cnn_mmio_host.h](include/cnn_mmio_host.h):

| Struct | Meaning |
| --- | --- |
| `cnn_mmio_preload_bundle` | one model payload containing conv config, conv weights, FC bias, and FC weights |
| `cnn_mmio_inference_case` | one inference case containing packed image words and an expected class from the manifest |
| `cnn_mmio_device` | `/dev/mem` mapping state |
| `cnn_mmio_profile` | per-layer cycle counters read back after inference |

### Important Data-Type Detail

The image tensor is logically **INT8**, but it is transported as packed
`uint32_t` words.

That is why the host-side struct uses:

```c
uint32_t image[1024];
```

The packing step happens in
[tools/cnn_mmio_host.c](tools/cnn_mmio_host.c):

- four signed INT8 values are read from `tb_conv1_in_i8_64x64x1.txt`
- they are packed into one 32-bit word
- those packed words are what the HPS writes into the MMIO scratchpad

The same idea is used for packed convolution weights.

## Canonical Model-Load Sequence

The model-load flow is:

1. Read the preload files into a `cnn_mmio_preload_bundle`
2. Open `/dev/mem` and map the CSR region
3. Program the default base/length registers
4. Write the preload bundle into the scratchpad regions
5. Assert `MODEL_LOAD`
6. Wait until `model_loaded = 1`
7. Read status and error

In helper-function form, that is:

```c
cnn_mmio_load_preload_bundle(...)
cnn_mmio_open(...)
cnn_mmio_program_default_registers(...)
cnn_mmio_write_preload_bundle(...)
cnn_mmio_start_model_load(...)
cnn_mmio_wait_for_status_bit(..., CNN_MMIO_STATUS_MODEL_LOADED_SHIFT, 1, ...)
```

The preload files normally come from a directory like:

```text
Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test
```

Typical files inside that directory:

- `preload_conv_cfg_45w.txt`
- `preload_conv_wt_225w_bytes.txt`
- `preload_fc_bias_10w.txt`
- `preload_fcw_864w.txt`

## Canonical Inference Sequence

The inference flow is:

1. Read the case directory into a `cnn_mmio_inference_case`
2. Open `/dev/mem` if it is not already open
3. Program the default base/length registers
4. Write the packed image into the image scratchpad region
5. Assert `INFER`
6. Wait until `predict_done = 1`
7. Read predicted class, error word, and per-layer profile counters

In helper-function form, that is:

```c
cnn_mmio_load_inference_case(...)
cnn_mmio_open(...)
cnn_mmio_program_default_registers(...)
cnn_mmio_write_inference_case(...)
cnn_mmio_start_infer(...)
cnn_mmio_wait_for_status_bit(..., CNN_MMIO_STATUS_PREDICT_DONE_SHIFT, 1, ...)
cnn_mmio_read_error(...)
cnn_mmio_read_profile(...)
```

The board-side CLI tool that implements this sequence is
[tools/hps_mmio_predict.c](tools/hps_mmio_predict.c).

## Per-Layer Cycle Profile

The current RTL exports cycle counts for:

- `L1`
- `L2 P0`
- `L2 P1`
- `L3 P0`
- `L3 P1`
- `FC`
- `Argmax`
- `Total`

The host helper reads these counters into `cnn_mmio_profile`.

For the current board mainline:

- fabric clock:
  `25 MHz`
- cycle-to-time conversion:
  `time_us = cycles / 25`

That is why the web demo can show both:

- `FPGA Wait Time`
  board-observed wait from `INFER` to `predict_done`
- `FPGA RTL Time`
  cycle counters converted to time at the configured fabric clock

## Practical Gotchas

- Reprogramming a volatile `.sof` clears the FPGA fabric state.
  After that, `model_loaded` becomes false again and the host must reload the
  model before the next inference.
- The helper APIs expect the shared constants in
  [include/cnn_mmio_regs.h](include/cnn_mmio_regs.h) to match the RTL wrapper.
  If those drift apart, model load and inference can silently target the wrong
  scratchpad regions.
- The userspace tool addresses **halfwords**, not bytes.
  Use the helper APIs unless you are intentionally debugging the raw contract.
- The image written by the host is not a raw PNG or JPG.
  It is already a quantized `64x64x1` INT8 tensor packed into 32-bit words.

## Read Next

- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- [web_demo/README.md](web_demo/README.md)
