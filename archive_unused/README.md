# Archived Non-Mainline Files

This directory keeps high-confidence files and folders that are not required by
the current FPGA-to-web-demo submission flow, but are still worth preserving in
the repository for reference.

## Current submission mainline

The active end-to-end flow keeps and uses:

- `de1_soc/`
- `input/RTL/`
- `include/`
- `tools/`
- `gesture_runtime/`
- `web_demo/`
- `test_data/`
- the model and case assets under `Golden-Module/`

## Archived here

- `legacy_projects/`
  Older root-level Quartus project files that are not used by
  `de1_soc/build_soc_system.py`.
- `historical_materials/`
  Older lab collateral, MATLAB-era reference material, waveform helper scripts,
  and legacy simulation support folders.
- `temp_sync/`
  Temporary sync copies created during earlier board/web bring-up work.

This is an archive move, not a deletion, so these files can still be recovered
if a future workflow needs them.
