# MMIO Interface Guide

This document explains the current **32-bit** shared MMIO contract used by the
DE1-SoC board lane on this branch.

Use it when you need to answer:

- what lives at `0xff200000`
- how addresses are constructed
- why the MMIO map looks "big" even though the actual BRAM is much smaller
- how model/image data is packed and transferred
- which registers and scratchpad regions matter

The authoritative shared headers are:

- [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h)
- [`../include/cnn_mmio_host.h`](../include/cnn_mmio_host.h)

## What The Contract Connects

The working chain is:

`HPS userspace tool -> /dev/mem mmap -> lightweight HPS-FPGA bridge -> cnn_mmio_interface -> system_top`

Important code entry points:

- host helper library:
  [`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c)
- board CLI tools:
  [`../tools/hps_mmio_status.c`](../tools/hps_mmio_status.c),
  [`../tools/hps_mmio_load_model.c`](../tools/hps_mmio_load_model.c),
  [`../tools/hps_mmio_predict.c`](../tools/hps_mmio_predict.c),
  [`../tools/hps_mmio_run_case.c`](../tools/hps_mmio_run_case.c)
- RTL wrapper:
  [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v)
- compute core:
  [`../input/RTL/system_top.v`](../input/RTL/system_top.v)

## Base Address And Address Construction

The validated board base address is:

```text
0xff200000
```

Userspace maps that region with:

- map span:
  `CNN_MMIO_MAP_SPAN_BYTES = 4 MiB`
- open path:
  `/dev/mem`

### Current Addressing Model

The current contract is **32-bit word-indexed**, not byte-indexed and not
16-bit halfword-indexed.

From [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h):

- `address[18] = 0`
  scratchpad memory space
- `address[18] = 1`
  config / status register space

The helpers construct addresses like this:

```c
cnn_mmio_cfg_addr(reg_idx) = (1u << 18) | reg_idx
cnn_mmio_mem_addr(word_addr) = word_addr
```

So software uses:

- register indices for config/status
- 32-bit word indices for staged memory

and the RTL uses `address[18]` to decide which subspace is being accessed.

## Why The MMIO Map Looks Large

There are three different "sizes" to keep straight:

| Layer | Size | Why |
| --- | --- | --- |
| Userspace `mmap` span | 4 MiB | simple `/dev/mem` mapping window with plenty of room |
| Logical scratchpad namespace | `0x00000..0x3FFFF` word indices | easy split between memory and config spaces using `address[18]` |
| Actual implemented scratchpad BRAM | `MEM_AW=13` -> `8192` words -> `32 KiB` | this is the real M10K-backed storage inside the wrapper |

That means the map is intentionally larger than the physically instantiated
scratchpad.

Why this is done:

1. the host-side contract becomes simple and stable
2. config space can live in a clearly separate address window
3. future growth does not require redefining the userspace addressing model
4. the low-level `/dev/mem` mapping code does not need a tiny custom span

The RTL still bounds actual scratchpad access with:

```verilog
wire mem_addr_ok = (address[17:0] < MEM_WORDS);
```

so only the low `8192` word slots are physically implemented.

## Memory And Register Space Layout

| Space | Range | Meaning |
| --- | --- | --- |
| Scratchpad memory | `0x00000..0x3FFFF` word indices | logical staging window for model and image data |
| Config / status | `0x40000..0x4001F` word indices | control, status, base/length, predict/error, profiles, debug |

In practice, most software should use the C helpers rather than hard-coding
indices.

## Register Map

The current register indices come from
[`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h).

| Index | Register | Direction | Meaning |
| --- | --- | --- | --- |
| `0` | `CONTROL` | W | command register |
| `1` | `STATUS` | R | busy/model_loaded/predict_done/predict_class |
| `2` | `CONV_CFG_BASE` | R/W | conv config scratchpad base |
| `3` | `CONV_CFG_LEN` | R/W | conv config word count |
| `4` | `CONV_WT_BASE` | R/W | conv weight scratchpad base |
| `5` | `CONV_WT_LEN` | R/W | conv weight word count |
| `6` | `FC_BIAS_BASE` | R/W | FC bias scratchpad base |
| `7` | `FC_BIAS_LEN` | R/W | FC bias word count |
| `8` | `FCW_BASE` | R/W | FC weight scratchpad base |
| `9` | `FCW_LEN` | R/W | FC weight word count |
| `10` | `IMAGE_BASE` | R/W | image scratchpad base |
| `11` | `IMAGE_LEN` | R/W | image word count |
| `12` | `PREDICT` | R | predicted class alias |
| `13` | `IF_ERROR` | R | interface error bits |
| `14..29` | `PROFILE_*` | R | per-layer cycle counters |
| `30` | `LAST_WRITE` | R | debug register showing last write data + byteenable |
| `31` | `MAGIC` | R | debug constant `0x434E4E32` (`"CNN2"`) |

### Control Bits

| Bit mask | Meaning |
| --- | --- |
| `0x0001` | start model load |
| `0x0002` | start inference |
| `0x0004` | clear latched status/error |

### Status Bits

The low 16 bits of `STATUS` keep the old ABI:

| Bit | Meaning |
| --- | --- |
| bit 1 | accelerator busy |
| bit 2 | model has been loaded |
| bit 3 | inference finished |
| bits 4..7 | predicted class nibble |

This is why the wrapper looks "mixed-width":

- the slave is now 32-bit wide
- but control/status semantics still live in the low 16 bits for software compatibility

### Error Bits

The current RTL sets:

| Bit | Meaning |
| --- | --- |
| bit 0 | `MODEL_LOAD` requested while engine/accelerator busy |
| bit 1 | `INFER` requested while engine/accelerator busy |
| bit 2 | `INFER` requested before model load completed |
| bit 3 | replay engine tried to read outside implemented scratchpad BRAM |

## Default Scratchpad Layout

The current default staged layout is:

| Region | Base word address | Words | Bytes |
| --- | --- | --- | --- |
| Conv config | `0` | `45` | `180` |
| Conv weights | `45` | `225` | `900` |
| FC bias | `270` | `10` | `40` |
| FC weights | `280` | `864` | `3456` |
| Input image | `1144` | `1024` | `4096` |

This means:

- model preload occupies `1144` words = `4576` bytes
- one image occupies `1024` words = `4096` bytes
- active total staged footprint is `2168` words = `8672` bytes

So even though the logical memory namespace is large, the current model/image
use only a small fraction of the available `8192` implemented word slots.

## What The Files In The Scratchpad Actually Contain

### Model Preload Directory

Typical directory:

```text
Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test
```

Files:

- `preload_conv_cfg_45w.txt`
  45 signed 32-bit configuration words
- `preload_conv_wt_225w_bytes.txt`
  225 host words, each packing four signed 8-bit weights
- `preload_fc_bias_10w.txt`
  10 signed 32-bit FC bias words
- `preload_fcw_864w.txt`
  864 signed 32-bit words carrying packed FC weights

### Inference Case Directory

Typical directory:

```text
Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_7_test
```

Files used by the FPGA path:

- `tb_conv1_in_i8_64x64x1.txt`
  `64*64 = 4096` signed 8-bit pixels
- `manifest.txt`
  expected-class metadata

Those pixels are packed by the host into:

- `1024` 32-bit words
- four signed INT8 values per word

## Host-Side Structures

From [`../include/cnn_mmio_host.h`](../include/cnn_mmio_host.h):

| Struct | Meaning |
| --- | --- |
| `cnn_mmio_preload_bundle` | full model preload payload |
| `cnn_mmio_inference_case` | one image payload plus expected class |
| `cnn_mmio_device` | `/dev/mem` mapping state |
| `cnn_mmio_profile` | per-layer cycle counters |

The key transport detail is:

- image values are logically INT8
- but the HPS writes them as packed `uint32_t` words

That packing happens in
[`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c).

## Canonical Model-Load Sequence

The model-load flow is:

1. read preload files into `cnn_mmio_preload_bundle`
2. open `/dev/mem`
3. `mmap` the MMIO window at `0xff200000`
4. program default base/length registers
5. write the preload bundle into the scratchpad
6. write `CONTROL = MODEL_LOAD`
7. poll `STATUS.model_loaded`

Key functions:

```c
cnn_mmio_load_preload_bundle(...)
cnn_mmio_open(...)
cnn_mmio_program_default_registers(...)
cnn_mmio_write_preload_bundle(...)
cnn_mmio_start_model_load(...)
cnn_mmio_wait_for_status_bit(...)
```

## Canonical Inference Sequence

The inference flow is:

1. read the case directory into `cnn_mmio_inference_case`
2. open `/dev/mem`
3. program default base/length registers
4. write the packed image into scratchpad
5. write `CONTROL = INFER`
6. poll `STATUS.predict_done`
7. read predicted class, error, and profiles

Key functions:

```c
cnn_mmio_load_inference_case(...)
cnn_mmio_open(...)
cnn_mmio_program_default_registers(...)
cnn_mmio_write_inference_case(...)
cnn_mmio_start_infer(...)
cnn_mmio_wait_for_status_bit(...)
cnn_mmio_read_error(...)
cnn_mmio_read_profile(...)
```

## What The RTL Wrapper Does With Those Words

Inside [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v):

1. host writes are stored into a 32-bit M10K-backed BRAM
2. config registers capture base/length values
3. `MODEL_LOAD` causes the wrapper to replay:
   - conv cfg
   - conv weights
   - FC bias
   - FC weights
4. `INFER` causes the wrapper to replay:
   - the uploaded image words
5. replayed 32-bit words are driven into `system_top`
6. `predict_class`, `predict_done`, and cycle profiles are latched for software readback

The wrapper no longer does 16-bit low/high stitching. The scratchpad and the
host contract are word-based.

## Practical Notes

- Reprogramming a volatile `.sof` clears FPGA fabric state, so the host must
  reload the model before the next inference.
- The helper APIs expect the register constants in
  [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h) to match the RTL.
- The large logical MMIO window does **not** mean the design consumes megabytes
  of on-chip RAM.
- The current slave expects full-word host writes into the scratchpad; partial
  byte-enabled writes are not the intended normal path.

## Read Next

- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)
