# Web Demo

This folder contains the host-side upload-first comparison demo.

Important semantic note:

- the current deployed lane is **10-class sign-language gesture classification**
- labels are currently shown as gesture IDs `0..9`
- legacy board artifact folders still use `digit_*` names, but in this demo
  they refer to gesture-class IDs rather than handwritten-digit semantics

## Current Flow

- browser uploads one image
- host preprocesses the image
- host uses a local TFLite pass only to choose the more stable preprocess branch
- board runs a software CPU baseline through `hps_cpu_reference`
- host sends the same preprocessed image to the board
- board runs FPGA inference through the existing HPS tools
- the UI compares same-platform board CPU vs FPGA time and predicted class

The current transport default is SSH.

The short version is:

`browser -> Flask on host -> preprocess + case export -> SSH/SCP -> board tools -> MMIO -> FPGA -> JSON response -> browser`

The currently configured board-validated artifact path still points at:

- `Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test`

That is an artifact-path naming convention, not the intended user-facing task
name. See [DATASET_GUIDE.md](../docs/DATASET_GUIDE.md).

For the end-to-end runtime explanation, read:

- [WEB_TO_FPGA_WORKFLOW.md](../docs/WEB_TO_FPGA_WORKFLOW.md)
- [MMIO_INTERFACE_GUIDE.md](../docs/MMIO_INTERFACE_GUIDE.md)
- [TEAMMATE_SETUP.md](../docs/TEAMMATE_SETUP.md)

## Files

- `app.py`
  Flask entry point
- `config.py`
  Loads host/board/demo configuration
- `demo_config.example.json`
  Copy this to `demo_config.json` and fill in your board settings
- `requirements.txt`
  Host-side Python dependencies for the web demo

## Config Setup

1. Copy:

```bash
cp web_demo/demo_config.example.json web_demo/demo_config.json
```

2. Fill in:

- `board_host`
- `board_user`
- `board_port`
- `ssh_key` if you use key-based auth
- `ssh_known_hosts` if you want a dedicated host-key file
- `ssh_bind_address` if your host has multiple NICs and you need to force the direct Ethernet path
- `remote_repo`
- `remote_preload_root`
- `cpu_model`

You can also override any of these with environment variables. The app reads
`web_demo/demo_config.json` by default, or `CNN_ACC_DEMO_CONFIG` if you want to
point to a different config file.

## Python Dependencies

Install the web demo dependencies:

```bash
python -m pip install -r web_demo/requirements.txt
```

You also need one TFLite runtime path:

- `tflite-runtime`, or
- `tensorflow`

## Board Requirements

The board must already have:

- SSH access working
- the repo present at `remote_repo`
- `make -C tools` already run, or ready to run
- the new `hps_mmio_predict` and `hps_cpu_reference` tools built on the board
- `python3` installed on the board if you want to extend the software baseline later

## One-Command Prep

From the repository root, the shortest current bring-up command is:

```powershell
python tools\prepare_web_demo.py --program-sof --build-tools
```

If the FPGA is already programmed and you only need to recover the board
Ethernet + SSH path, use:

```powershell
python tools\prepare_web_demo.py --build-tools
```

This helper:

- optionally programs the current `soc_system.sof`
- brings up board `eth0` over serial
- assigns the board direct-link IP
- starts SSH on the board
- verifies host-to-board SSH using the active `demo_config.json`

## Run

```bash
python web_demo/app.py
```

Then open:

```text
http://127.0.0.1:5000
```

You can also check the active config with:

```text
GET /api/health
```

## Find Or Verify The Board

Probe likely SSH targets discovered from the local machine:

```bash
python web_demo/find_ssh_targets.py
```

You can also add an explicit subnet:

```bash
python web_demo/find_ssh_targets.py --subnet 192.168.1.0/24
```

After updating `demo_config.json`, verify the remote board and optionally build
the required FPGA-side tool:

```bash
python web_demo/check_board.py --build-tools
```

## Timing Semantics

- `Board CPU Time`: software reference inference measured on the HPS ARM CPU
- `FPGA Wait Time`: accelerator wait time from `INFER` to `predict_done`
- `Remote request`: host-side SSH/upload/process overhead, reported separately and not used as the main speedup metric

For the current direct host-to-board Ethernet setup on this machine, the
working values are:

- `board_host`: `169.254.217.241`
- `ssh_bind_address`: `169.254.217.240`
