# Web To FPGA Workflow

This document explains the current end-to-end runtime path from one uploaded
image to one FPGA prediction result.

## One-Line Summary

The current demo path is:

`browser -> Flask on host -> host preprocess + case export -> SSH/SCP to board -> HPS userspace tools -> MMIO -> FPGA -> result back to Flask -> browser`

The FPGA does **not** host the web page directly.

## Files That Matter In This Flow

| Layer | Main files |
| --- | --- |
| Browser + Flask routes | [`../web_demo/app.py`](../web_demo/app.py) |
| Demo orchestration | [`../gesture_runtime/demo_compare.py`](../gesture_runtime/demo_compare.py) |
| Image preprocessing | [`../gesture_runtime/preprocess.py`](../gesture_runtime/preprocess.py) |
| Case-folder export | [`../gesture_runtime/case_export.py`](../gesture_runtime/case_export.py) |
| SSH / SCP transport | [`../gesture_runtime/ssh_transport.py`](../gesture_runtime/ssh_transport.py) |
| Board CPU baseline | [`../tools/hps_cpu_reference.c`](../tools/hps_cpu_reference.c) |
| Board FPGA path | [`../tools/hps_mmio_predict.c`](../tools/hps_mmio_predict.c) |
| Shared MMIO helper library | [`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c) |
| Shared MMIO constants | [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h) |
| RTL MMIO wrapper | [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v) |
| Compute core | [`../input/RTL/system_top.v`](../input/RTL/system_top.v) |

## What Stays On The Host Versus What Goes To The Board

### Host-only

- raw uploaded image bytes
- preprocess branch selection logic
- temporary preview image shown in the browser
- Flask request/response handling
- SSH/SCP transport orchestration

### Sent To The Board

- one exported case directory containing:
  - `tb_conv1_in_i8_64x64x1.txt`
  - `manifest.txt`
- shell commands that invoke:
  - `hps_cpu_reference`
  - `hps_mmio_status`
  - `hps_mmio_load_model`
  - `hps_mmio_predict`

### Already Present On The Board

- the repo checkout at `/root/cnn_acc_hps`
- the FPGA bitstream already loaded into fabric
- the model preload export under:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/...`

## Step-By-Step Runtime Flow

### 1. Browser Uploads One Image

The browser sends one image to:

```text
POST /api/infer
```

Entry point:
[`../web_demo/app.py`](../web_demo/app.py)

### 2. Flask Builds The Comparison Service

The Flask app creates a `ComparisonDemoService` using:

- `DemoConfig` from `web_demo/demo_config.json`
- a board SSH transport
- a board CPU service
- a board FPGA service
- the host-side TFLite preprocess-branch selector

### 3. Host-Side Preprocess Converts The Image

The uploaded bytes go through:

- grayscale conversion
- optional crop/plain variants
- resize to `64x64`
- quantization to signed INT8 with input zero point `-128`

File:
[`../gesture_runtime/preprocess.py`](../gesture_runtime/preprocess.py)

So the FPGA never sees the raw PNG/JPG file directly.

### 4. Host TFLite Chooses The Better Preprocess Branch

The host-side TFLite model is used only to decide which preprocess branch is
more stable for this request.

File:
[`../gesture_runtime/demo_compare.py`](../gesture_runtime/demo_compare.py)

This is **not** the main software baseline shown in the UI. The UI's software
baseline is the board-side HPS CPU tool.

### 5. Host Exports One Temporary Case Folder

The chosen quantized `64x64x1` tensor is exported as a board-consumable case
folder.

File:
[`../gesture_runtime/case_export.py`](../gesture_runtime/case_export.py)

That folder contains:

- `tb_conv1_in_i8_64x64x1.txt`
- `manifest.txt`

This is the exact payload shipped to the board.

### 6. The Board CPU Baseline Runs First

The host uploads the temp case folder over SCP and then runs:

```text
./tools/hps_cpu_reference <case_root> <reference_case_root>
```

The board CPU baseline uses:

- the uploaded image case as input
- the canonical reference exports under
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/<reference_case>`

File:
[`../tools/hps_cpu_reference.c`](../tools/hps_cpu_reference.c)

Returned values include:

- `predict_class`
- `board_cpu_infer_ms`

### 7. The FPGA Path Verifies Model State

Before FPGA inference, the host-side FPGA service runs:

```text
./tools/hps_mmio_status 0xff200000
```

If `model_loaded != 1`, it loads the model once:

```text
./tools/hps_mmio_load_model 0xff200000 <remote_preload_root>
```

That writes the model payload into the MMIO scratchpad and asserts
`MODEL_LOAD`.

### 8. The Host Uploads The Same Exported Case For FPGA Inference

For the FPGA path, the host again uploads the case directory and then runs:

```text
./tools/hps_mmio_predict 0xff200000 <remote_case_dir>
```

File:
[`../tools/hps_mmio_predict.c`](../tools/hps_mmio_predict.c)

### 9. The HPS Tool Converts Case Files Into MMIO Traffic

Inside:

- [`../tools/hps_mmio_predict.c`](../tools/hps_mmio_predict.c)
- [`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c)

the board does this:

1. Read `tb_conv1_in_i8_64x64x1.txt`
2. Pack every four INT8 values into one 32-bit word
3. `mmap` `/dev/mem` at `0xff200000`
4. Program the default MMIO base/length registers
5. Write the packed image into the image region of the scratchpad
6. Assert `INFER`
7. Poll `STATUS` until `predict_done = 1`
8. Read back:
   - predicted class
   - status
   - error register
   - per-layer cycle counters
   - board-side timing breakdown

## What Happens Inside The RTL

The board-facing wrapper is:

- [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v)

It does two jobs:

1. expose a host-visible MMIO contract
2. replay staged scratchpad contents into the load/control interface expected
   by [`../input/RTL/system_top.v`](../input/RTL/system_top.v)

The runtime datapath is therefore:

`host writes staged 32-bit words -> MMIO wrapper BRAM -> replay sequencer -> system_top`

not:

`host continuously streams raw pixels into conv logic every FPGA clock`

During inference:

- the uploaded image is injected for the L1 pass
- later layers run from the accelerator's on-chip SRAM/dataflow path
- the final predicted class is latched back into MMIO-visible status bits

## What Returns To The Browser

The Flask backend returns a JSON payload containing:

- FPGA predicted class
- board CPU predicted class
- board CPU time
- board FPGA wait time
- FPGA cycle-profile breakdown
- remote request time
- board-side `load/program/infer` timing breakdown
- selected preprocess mode
- preview image for the quantized model input

The browser UI renders:

- the selected input preview
- CPU-vs-FPGA result cards
- timing comparison
- per-layer profile summary

## Timing Fields In The UI

| UI field | Meaning |
| --- | --- |
| `Board CPU Time` | HPS ARM software inference time from `hps_cpu_reference` |
| `FPGA Wait Time` | board-observed wait from `INFER` to `predict_done` |
| `FPGA RTL Time` | cycle counters converted using the configured fabric clock |
| `Remote request time` | host SSH/SCP/process overhead around the board command |
| `Board total / load / program` | board-side breakdowns emitted by `hps_mmio_predict` |

`FPGA Wait Time` and `FPGA RTL Time` are intentionally not identical:

- `FPGA RTL Time` is the pure on-chip cycle view
- `FPGA Wait Time` includes the board-side software polling boundary

## Build-Time Files That Enable This Runtime

This runtime path depends on the FPGA build chain:

1. [`../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl`](../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl)
   packages the RTL as one Qsys component
2. [`../de1_soc/soc_system.qsys`](../de1_soc/soc_system.qsys)
   instantiates that IP on the HPS bridge
3. [`../de1_soc/build_soc_system.py`](../de1_soc/build_soc_system.py)
   regenerates HDL, patches debug ports, compiles Quartus, and emits `.sof`
   / `.rbf`

The generated files under `../de1_soc/soc_system/synthesis/` are outputs of
that process, not the first place to edit logic.

## Read Next

- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
- [../web_demo/README.md](../web_demo/README.md)
