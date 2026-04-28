# Build, Timing, And Resource Notes

This document summarizes the current build outputs, model size, resource usage,
and timing numbers for the submission branch.

## Build Entry Point

The main build command is:

```bash
python de1_soc/build_soc_system.py
```

Key source/build files:

- build wrapper:
  [`../de1_soc/build_soc_system.py`](../de1_soc/build_soc_system.py)
- system definition:
  [`../de1_soc/soc_system.qsys`](../de1_soc/soc_system.qsys)
- board top:
  [`../de1_soc/soc_system_top.sv`](../de1_soc/soc_system_top.sv)
- timing constraint:
  [`../de1_soc/soc_system.sdc`](../de1_soc/soc_system.sdc)

Key outputs:

- volatile JTAG image:
  [`../de1_soc/output_files/soc_system.sof`](../de1_soc/output_files/soc_system.sof)
- boot-style raw binary:
  [`../de1_soc/output_files/soc_system.rbf`](../de1_soc/output_files/soc_system.rbf)
- fitter summary:
  [`../de1_soc/output_files/soc_system.fit.summary`](../de1_soc/output_files/soc_system.fit.summary)
- STA summary:
  [`../de1_soc/output_files/soc_system.sta.summary`](../de1_soc/output_files/soc_system.sta.summary)
- full STA report:
  [`../de1_soc/output_files/soc_system.sta.rpt`](../de1_soc/output_files/soc_system.sta.rpt)
- older fabric-focused timing snapshot:
  [`../de1_soc/output_files/fabric_timing_summary_latest.txt`](../de1_soc/output_files/fabric_timing_summary_latest.txt)

## Current Model Artifacts

Current deployed model files:

- TFLite model:
  [`../Golden-Module/models/v1.int8.tflite`](../Golden-Module/models/v1.int8.tflite)
- MATLAB/export parameter artifact:
  [`../Golden-Module/models/v1.int8.params.mat`](../Golden-Module/models/v1.int8.params.mat)

Current file sizes:

- `v1.int8.tflite`:
  `9232` bytes
- `v1.int8.params.mat`:
  `8306` bytes

## Current Model Shape Summary

The active deployed lane is a 10-class gesture classifier.

Useful derived structure from
[`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h):

- L1 conv:
  `3x3x1 -> 4 channels`
- L2 conv:
  `3x3x4 -> 8 channels`
- L3 conv:
  `3x3x8 -> 8 channels`
- FC:
  `6x6x8 = 288 inputs -> 10 outputs`

Host-staged model/image layout:

| Payload | Words | Bytes |
| --- | --- | --- |
| Conv config | `45` | `180` |
| Conv weights | `225` | `900` |
| FC bias | `10` | `40` |
| FC weights | `864` | `3456` |
| One input image | `1024` | `4096` |

## Current Resource Budget

From
[`../de1_soc/output_files/soc_system.fit.summary`](../de1_soc/output_files/soc_system.fit.summary):

| Resource | Usage |
| --- | --- |
| ALMs | `18,380 / 32,070 (57%)` |
| Registers | `27,025` |
| Pins | `164 / 457 (36%)` |
| Block memory bits | `372,736 / 4,065,280 (9%)` |
| RAM blocks | `45 / 397 (11%)` |
| DSP blocks | `86 / 87 (99%)` |
| PLLs | `0 / 6 (0%)` |
| DLLs | `1 / 4 (25%)` |

### Practical Reading Of The Budget

- DSP usage is the tightest resource at `99%`
- RAM usage is still relatively low at `11%`
- the design currently uses **no PLLs**
- this matches the current strategy of using more on-chip memory/pipelining to
  reduce timing pressure instead of adding extra clock-generation complexity

## Current Clocking

The current fabric path runs directly from board `CLOCK_50`.

Evidence:

- board top connects `CLOCK_50` into `soc_system`:
  [`../de1_soc/soc_system_top.sv`](../de1_soc/soc_system_top.sv)
- SDC creates only:
  `create_clock -name clock_50 -period 20ns [get_ports CLOCK_50]`
  in [`../de1_soc/soc_system.sdc`](../de1_soc/soc_system.sdc)
- fitter summary reports:
  `Total PLLs : 0 / 6`

So this branch does **not** rely on a PLL for the current 50 MHz fabric clock.

## Current Timing Summary

From
[`../de1_soc/output_files/soc_system.sta.summary`](../de1_soc/output_files/soc_system.sta.summary):

### Whole-Design Worst Setup

- worst setup path in the full SoC is still HPS DDR:
  `afi_clk_write_clk`
- slow `1100mV 85C` setup slack there is:
  `2.563 ns`

### CNN Fabric User Clock

For `clock_50`:

- slow `1100mV 85C` setup slack:
  `6.794 ns`
- slow `1100mV 85C` hold slack:
  `0.229 ns`
- slow `1100mV 0C` setup slack:
  `7.285 ns`

This means the branch comfortably meets the target `50 MHz` user clock.

## Current Fmax Numbers

From
[`../de1_soc/output_files/soc_system.sta.rpt`](../de1_soc/output_files/soc_system.sta.rpt):

- slow `1100mV 85C` `clock_50` Fmax:
  `75.72 MHz`
- slow `1100mV 0C` `clock_50` Fmax:
  `78.65 MHz`

These are the current useful "how much headroom do we have above 50 MHz"
numbers for the user fabric clock.

## Why The Worst Full-Design Path Can Still Be DDR

Even though the CNN accelerator does not use external DDR as its feature-map
store during inference, the SoC project still instantiates the HPS DDR
subsystem because:

- HPS Linux runs from that memory system
- the complete `soc_system` design still contains the HPS DDR PHY/controller

So Quartus timing still reports HPS DDR paths in the full-chip summary.

For accelerator-centric timing judgement, the most relevant line is the
`clock_50` result, not the HPS DDR `afi_clk_write_clk` result.

## Board Validation Snapshot

This branch was validated with the following board-side flow after rebuilding
tools and programming the new `.sof`:

```text
./tools/hps_mmio_status 0xff200000
./tools/hps_mmio_load_model 0xff200000 Golden-Module/.../sram_preload/digit_0_test
./tools/hps_mmio_run_case 0xff200000 Golden-Module/.../txt_cases/digit_7_test
./tools/hps_mmio_predict 0xff200000 Golden-Module/.../txt_cases/digit_0_test
./tools/hps_cpu_reference Golden-Module/.../digit_0_test Golden-Module/.../digit_0_test
```

Observed good outputs:

- `model_loaded=1` after model load
- `expected_class=7`, `predict_class=7`, `error=0x0000` for `digit_7_test`
- `predict_class=0`, `error=0x0000` for `digit_0_test`

One measured profile snapshot:

- `total_cycles=16269`
- at `50 MHz`, pure RTL time is about:
  `16269 / 50e6 = 325.38 us`

The board-side `hps_mmio_predict` command also reported:

- `board_infer_wait_ms=1.115`

which is larger because it includes the software polling boundary around the
same inference.

## Known Build Quirk

`qsys-generate` may still emit the known Windows/WSL HPS SDRAM sequencer-build
warning during generation. The build wrapper:

- detects that specific failure mode
- keeps going if the generated HDL is still usable
- then runs Quartus compile and `.rbf` conversion

That is why the build script remains the preferred entry point instead of
manually clicking Qsys and Quartus in separate steps.

## Read Next

- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
