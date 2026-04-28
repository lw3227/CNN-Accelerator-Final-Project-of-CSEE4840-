# Project Status And Plan

This is a historical snapshot from an earlier integration stage. For the
current validated `submission` flow, start with [README.md](README.md),
[TEAM_RUNBOOK.md](TEAM_RUNBOOK.md), and
[BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md).

This document snapshots the repository after the DE1-SoC HPS+MMIO bring-up work
and before the web-demo extension work starts.

## Current State

- Main active line: `HPS Linux + MMIO + FPGA accelerator` on DE1-SoC
- Current integration branch base: `feature/de1-soc-mmio-integration`
- Board-facing wrapper is in `input/RTL/interface/cnn_mmio_interface.v`
- Board project and bring-up assets live under `de1_soc/`
- Shared host/MMIO contract lives in `include/cnn_mmio_regs.h`
- HPS userspace host tools live in `tools/`
- Python-side runtime helpers live in `gesture_runtime/`

## What Is Working

- The repository now has a real board path, not just simulation artifacts.
- The DE1-SoC project contains `cnn_mmio_interface` on the HPS lightweight bridge.
- HPS-side staged tools exist and have been used as the main bring-up path:
  - `hps_mmio_status`
  - `hps_mmio_load_model`
  - `hps_mmio_run_case`
  - `hps_mmio_infer`
- The host runtime in `tools/cnn_mmio_host.c` has already been aligned to the
  board-proven packed 32-bit MMIO access behavior.
- Seven-segment display support was added so the board can show the predicted
  class directly after inference.

## What Is Still Messy

- The repo still contains mixed historical lanes:
  - old 3-class paper/rock/scissors assets
  - current 10-class case assets under `digit_*`
  - newer project intent framed as gesture recognition
- The current repo is good enough for continued development, but it still needs
  a cleaner top-level path for the upcoming web demo.
- Some temporary local exploration folders and local Quartus report snapshots
  were produced during board bring-up and should not be committed.

## Cleanup Rule For This Snapshot

This snapshot only removes files that are clearly disposable:

- local temporary directories such as `tmp/` and `tmp_wsl/`
- local Quartus report snapshots such as `de1_soc/soc_system_top.*`

It intentionally keeps:

- generated SoC/HPS handoff contents that are part of the current board state
- lab reference archives and PDFs
- Platform Designer outputs currently used by the DE1-SoC line

## Recommended Next Development Line

Build the web demo on top of the current board path instead of replacing it.

- Keep board side as `HPS + MMIO + FPGA`
- Keep current HPS C tools as the board execution contract
- Add a host-side Python service layer
- Add a host-to-board transport abstraction
- Prefer one transport first, then grow

## Proposed Plan

### Phase 0: Stabilize Current Snapshot

- Keep the current board bring-up files together
- Commit the current known-good DE1-SoC integration state
- Push a dedicated snapshot branch to GitHub before larger demo work

### Phase 1: Service Layer For Comparison Demo

- Add a reusable host-side comparison module
- Keep CPU inference on the host machine
- Keep FPGA inference on the board through the current HPS tools
- Normalize outputs into one structured result payload

### Phase 2: Web Demo MVP

- Add Flask backend
- Add upload-only browser UI first
- Show:
  - predicted class
  - CPU inference time
  - FPGA inference time
  - speedup
  - simple chart

### Phase 3: Camera And UX Expansion

- Add browser webcam capture
- Keep webcam on the PC/browser side, not on the FPGA board
- Reuse the same backend compare path as upload mode

## Branching Intent

Before the web-demo work begins, create and push a dedicated snapshot branch so
the current board-integrated state is easy to return to and review.
