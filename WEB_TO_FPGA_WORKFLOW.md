# Web To FPGA Workflow

This document explains the current end-to-end path from the browser UI to the
FPGA accelerator and back.

Use this file when a teammate asks:

- where preprocessing happens
- what is sent over SSH
- what the board-side CPU and FPGA tools actually do
- where the predicted class and timing numbers come from

## One-Line Summary

The current demo path is:

`browser -> Flask on host -> host preprocess + case export -> SSH/SCP to board -> HPS userspace tools -> MMIO -> FPGA -> result back to Flask -> browser`

The FPGA does **not** host the web page directly.

## Main Files In The Flow

| Layer | Main files |
| --- | --- |
| Browser + Flask routes | [web_demo/app.py](web_demo/app.py) |
| Demo orchestration | [gesture_runtime/demo_compare.py](gesture_runtime/demo_compare.py) |
| Image preprocessing | [gesture_runtime/preprocess.py](gesture_runtime/preprocess.py) |
| Temp case-folder export | [gesture_runtime/case_export.py](gesture_runtime/case_export.py) |
| SSH / SCP transport | [gesture_runtime/ssh_transport.py](gesture_runtime/ssh_transport.py) |
| Board CPU baseline | [tools/hps_cpu_reference.c](tools/hps_cpu_reference.c) |
| Board FPGA path | [tools/hps_mmio_predict.c](tools/hps_mmio_predict.c) |
| MMIO helper library | [tools/cnn_mmio_host.c](tools/cnn_mmio_host.c) |
| RTL MMIO wrapper | [input/RTL/interface/cnn_mmio_interface.v](input/RTL/interface/cnn_mmio_interface.v) |
| Compute core | [input/RTL/system_top.v](input/RTL/system_top.v) |

## Step-By-Step Workflow

### 1. The Browser Sends One Image

The user either:

- uploads a file, or
- captures a frame from the browser webcam

The browser then posts that image to:

```text
POST /api/infer
```

Route entry point:
[web_demo/app.py](web_demo/app.py)

### 2. Flask Builds Or Reuses The Comparison Service

[web_demo/app.py](web_demo/app.py) creates a
`ComparisonDemoService` with:

- a host-side TFLite classifier
- a board CPU reference service
- a board FPGA service
- an SSH transport configured from `web_demo/demo_config.json`

### 3. Host-Side Preprocessing Happens In Python

The uploaded bytes go to:

[gesture_runtime/preprocess.py](gesture_runtime/preprocess.py)

The current preprocess pipeline can produce more than one candidate branch,
including:

- `plain`
- `crop`

Important points:

- preprocessing is done on the **host**
- the input is converted to grayscale
- it is resized to `64x64`
- it is quantized to signed INT8 with input zero point `-128`

So the FPGA never receives the raw PNG or JPG file directly.

### 4. Host TFLite Chooses The Best Preprocess Branch

[gesture_runtime/demo_compare.py](gesture_runtime/demo_compare.py) evaluates
the candidate preprocess variants with the host TFLite model and selects the
best branch.

This TFLite pass is used for **branch selection**, not as the main speed
comparison baseline.

### 5. The Host Writes A Temporary Case Folder

The chosen INT8 tensor is exported by:

[gesture_runtime/case_export.py](gesture_runtime/case_export.py)

That temporary case directory contains:

- `tb_conv1_in_i8_64x64x1.txt`
- `manifest.txt`

This exported folder is the exact payload shipped to the board.

### 6. The Board CPU Baseline Runs Over SSH

[gesture_runtime/fpga_service.py](gesture_runtime/fpga_service.py) uses
[gesture_runtime/ssh_transport.py](gesture_runtime/ssh_transport.py) to:

- `scp` the temp case folder to the board
- run `./tools/hps_cpu_reference <case_root> <reference_case_root>`

That board CPU path runs on the HPS ARM CPU and returns:

- predicted class
- board CPU inference time

This is the software baseline shown as `Board CPU Time` in the UI.

### 7. The Board FPGA Service Ensures The Model Is Loaded

Before FPGA inference, `FPGABoardService` checks the board status with:

```text
./tools/hps_mmio_status 0xff200000
```

If `model_loaded != 1`, it reloads the model with:

```text
./tools/hps_mmio_load_model 0xff200000 <remote_preload_root>
```

That preload step writes the conv / FC parameters into the FPGA-facing MMIO
scratchpad and triggers `MODEL_LOAD`.

The current validated preload root is configured in `demo_config.json`.

### 8. The Host Ships The Same Exported Case To The FPGA Path

For FPGA inference, the host again:

- uploads the case directory to the board
- runs `./tools/hps_mmio_predict 0xff200000 <remote_case_dir>`

Entry point:
[tools/hps_mmio_predict.c](tools/hps_mmio_predict.c)

### 9. The HPS Tool Converts The Case Folder Into MMIO Traffic

Inside [tools/hps_mmio_predict.c](tools/hps_mmio_predict.c) and
[tools/cnn_mmio_host.c](tools/cnn_mmio_host.c), the board does this:

1. Read `tb_conv1_in_i8_64x64x1.txt`
2. Pack every four INT8 values into one 32-bit word
3. `mmap` `/dev/mem` at `0xff200000`
4. Program the MMIO base/length registers
5. Write the packed image into the MMIO image scratchpad region
6. Assert `INFER`
7. Poll until `predict_done = 1`
8. Read back:
   - predicted class
   - status
   - error word
   - per-layer cycle counters

## What Happens Inside The RTL

The RTL-facing wrapper is:

[input/RTL/interface/cnn_mmio_interface.v](input/RTL/interface/cnn_mmio_interface.v)

Conceptually it does two jobs:

- expose a host-visible MMIO contract
- replay staged scratchpad contents into the accelerator-facing stream / control
  interface expected by [input/RTL/system_top.v](input/RTL/system_top.v)

So the data path is not:

`host streams raw camera pixels directly into conv on every clock`

Instead, it is:

`host writes staged words -> MMIO wrapper replays them -> accelerator runs`

During inference:

- the image is injected for `L1`
- later layers run from on-chip SRAM / local RTL dataflow
- the final predicted class is latched back into MMIO-visible status bits

## What Returns To The Browser

The Flask service returns a JSON payload containing:

- FPGA predicted class
- board CPU predicted class
- board CPU time
- FPGA wait time
- FPGA RTL per-layer profile
- request overhead and board-side breakdowns
- the selected preprocess mode
- a preview of the preprocessed `64x64` model input

The browser UI then renders:

- the selected input preview
- result cards
- execution-time comparison
- per-layer RTL profile

## Timing Semantics

The UI shows multiple time domains on purpose.

| UI field | Meaning |
| --- | --- |
| `Board CPU Time` | HPS ARM software inference time from `hps_cpu_reference` |
| `FPGA Wait Time` | board-observed wait from `INFER` to `predict_done` |
| `FPGA RTL Time` | cycle counters converted using the configured fabric clock |
| `Remote request time` | host SSH / SCP / process overhead around the board command |
| `Board total / load / program` | board-side breakdowns emitted by `hps_mmio_predict` |

This is why `FPGA Wait Time` and `FPGA RTL Time` are close but not identical:

- `FPGA RTL Time` is the pure on-chip cycle count view
- `FPGA Wait Time` includes the board-side polling boundary around the same run

## Cross-Platform Note

This workflow is intentionally split so teammates on different host OSes can
still contribute:

- Windows is the validated Quartus + JTAG + serial bring-up lane
- Windows, Linux, and macOS can all work on the host-side web / preprocess /
  SSH lane once the board is reachable

That is why the browser, Flask app, preprocess code, and SSH transport all run
on the host instead of on the FPGA board.

## Read Next

- [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)
- [web_demo/README.md](web_demo/README.md)
