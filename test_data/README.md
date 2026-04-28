# Test Data Entry

This folder is a lightweight entry point for the hardware-aligned test data.
It does not duplicate the real data files; it points to the canonical copies
under `Golden-Module/matlab/hardware_aligned/debug/`.

The current case folders still use `digit_*` names. Treat that as the existing
hardware-artifact naming convention, not as the top-level documentation source
for the whole project task definition.

For the current active lane, these case names should be read as **gesture class
IDs** in a 10-class sign-language gesture task. See
[DATASET_GUIDE.md](../docs/DATASET_GUIDE.md).

## Real data locations

- Preload bundles:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/`
- Per-case inputs and goldens:
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/`

Available digit cases:

- `digit_0_test`
- `digit_1_test`
- `digit_2_test`
- `digit_3_test`
- `digit_4_test`
- `digit_5_test`
- `digit_6_test`
- `digit_7_test`
- `digit_8_test`
- `digit_9_test`

## Quick mock test

From the repo root:

```bash
python3 test_data/run_case.py digit_0_test
```

You can switch the case name, for example:

```bash
python3 test_data/run_case.py digit_7_test
```

## What the wrapper does

The wrapper maps a case name such as `digit_0_test` to:

- preload root:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/<case>`
- case root:
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/<case>`

and then calls `tools/run_mmio_inference.py --backend mock`.
