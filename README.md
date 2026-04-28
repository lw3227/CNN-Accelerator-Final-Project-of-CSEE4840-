# CNN_ACC

This branch is the cleaned-up `submission` handoff for the current
`DE1-SoC + HPS + MMIO + FPGA + web demo` lane.

The validated execution chain is:

`browser -> host Python/Flask -> SSH/SCP -> HPS Linux userspace -> MMIO -> FPGA`

## Start Here

All teammate-facing high-level docs now live under [`docs/`](docs/README.md).

Read these first:

- [docs/README.md](docs/README.md)
- [docs/TEAMMATE_SETUP.md](docs/TEAMMATE_SETUP.md)
- [docs/TEAM_RUNBOOK.md](docs/TEAM_RUNBOOK.md)
- [docs/ARCHITECTURE_AND_FILE_MAP.md](docs/ARCHITECTURE_AND_FILE_MAP.md)
- [docs/MMIO_INTERFACE_GUIDE.md](docs/MMIO_INTERFACE_GUIDE.md)
- [docs/BUILD_TIMING_AND_RESOURCES.md](docs/BUILD_TIMING_AND_RESOURCES.md)
- [docs/FMAX_OPTIMIZATION_NOTES.md](docs/FMAX_OPTIMIZATION_NOTES.md)

## What Is In The Repo

- `input/RTL/`
  Accelerator RTL and the MMIO wrapper
- `include/`
  Shared register map and host-side C headers
- `tools/`
  HPS-side C tools plus host-side serial/programming helpers
- `gesture_runtime/`
  Host-side Python runtime, preprocess, SSH/SCP transport, and demo services
- `web_demo/`
  Flask app and frontend assets
- `de1_soc/`
  Quartus / Platform Designer project and generated SoC integration files
- `Golden-Module/`
  TFLite model plus hardware-aligned exported artifacts
- `test_data/`
  Lightweight mock/test entry points

## Quick Commands

Check host tool availability:

```bash
python de1_soc/build_soc_system.py --check
```

Rebuild the FPGA project:

```bash
python de1_soc/build_soc_system.py
```

Build HPS-side tools:

```bash
make -C tools
```

Run one local mock case:

```bash
python test_data/run_case.py digit_0_test
```

Run the board preparation helper:

```bash
python tools/prepare_web_demo.py --program-sof --build-tools
```

Launch the web demo:

```bash
python web_demo/app.py
```

## Current Model / Task Semantics

The active task is a **10-class sign-language gesture** classifier.

- labels are `0..9`
- the deployed TFLite file is `Golden-Module/models/v1.int8.tflite`
- legacy case-folder names such as `digit_7_test` are still used for the
  hardware-aligned exported artifacts

For more detail, read [docs/DATASET_GUIDE.md](docs/DATASET_GUIDE.md).
