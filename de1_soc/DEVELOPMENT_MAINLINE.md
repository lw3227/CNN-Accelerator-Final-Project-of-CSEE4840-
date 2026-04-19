# Development Mainline

This is the shortest path that keeps the current repository structure intact and
continues from `feature/de1-soc-mmio-integration` without a broad refactor.

## Recommended Mainline

Use a staged `HPS + MMIO` mainline, not a pure FPGA-only mainline.

Why this is the right default now:

- The MMIO wrapper already exists at `input/RTL/interface/cnn_mmio_interface.v`.
- The HPS-side software stack already exists in both C and Python.
- `de1_soc/soc_system.qsys` already contains `cnn_mmio_interface_0` on the HPS
  bridge, so the board path is not starting from zero.
- The FPGA-only LED demo is useful for bring-up, but it is only a side path for
  sanity checking wrapper status signals. It does not solve the real deployment
  problem of loading a model once and then running many images.

Recommended phases:

1. Keep `system_top` as the compute core.
2. Treat `cnn_mmio_interface` as the stable host-facing contract.
3. Use `de1_soc/` as the board integration layer.
4. Use the FPGA-only LED demo only as a quick fallback if HPS MMIO is blocked.

## Working Set

Read these first and keep them open while working:

- `input/RTL/interface/cnn_mmio_interface.v`
- `input/RTL/system_top.v`
- `include/cnn_mmio_regs.h`
- `tools/cnn_mmio_host.c`
- `tools/hps_mmio_status.c`
- `tools/hps_mmio_load_model.c`
- `tools/hps_mmio_run_case.c`
- `tools/run_mmio_inference.py`
- `gesture_runtime/mmio_driver.py`
- `gesture_runtime/mmio_runtime.py`
- `gesture_runtime/preprocess.py`
- `de1_soc/README.md`
- `de1_soc/BOARD_TEST_PLAN.md`
- `de1_soc/soc_system.qsys`
- `de1_soc/soc_system_top.sv`
- `de1_soc/device_tree/README.md`
- `test_data/README.md`
- `test_data/run_case.py`

Usually ignore these unless you are debugging a specific tool step:

- `de1_soc/soc_system/`
- `de1_soc/hps_isw_handoff/`
- `lab3-hw/linux-headers-4.19.0.tar.gz`
- `lab3-hw/lab3-sw.tar.gz`
- `matlab_old/`
- `vf/`
- `input/SRAM_macro/`
- top-level Quartus roots: `CNN_ACC.qpf`, `CNN_ACC.qsf`, `soc_system.qpf`, `soc_system.qsf`

## Must Read Now

- `input/RTL/interface/cnn_mmio_interface.v`
- `include/cnn_mmio_regs.h`
- `de1_soc/README.md`
- `de1_soc/BOARD_TEST_PLAN.md`
- `de1_soc/soc_system.qsys`
- `de1_soc/soc_system_top.sv`
- `tools/cnn_mmio_host.c`
- `tools/hps_mmio_load_model.c`
- `tools/hps_mmio_run_case.c`
- `gesture_runtime/mmio_driver.py`
- `gesture_runtime/mmio_runtime.py`
- `gesture_runtime/preprocess.py`
- `test_data/README.md`
- `test_data/run_case.py`

## Safe To Ignore For Now

- `matlab_old/`
- most of `vf/logs/`
- ASIC macro collateral under `input/SRAM_macro/`
- large generated contents under `de1_soc/soc_system/`
- old standalone Quartus roots unless you are debugging synthesis history:
  `CNN_ACC.qpf`, `CNN_ACC.qsf`, top-level `soc_system.qpf`, `soc_system.qsf`

## Code-Level Conclusions

- `de1_soc/` is mostly self-consistent for the intended board path:
  `soc_system.qsys` already instantiates `cnn_mmio_interface_0` and connects it
  to the HPS lightweight bridge.
- The current MMIO map is internally consistent across RTL, Python, and C:
  the split at `address[19]`, the register indices, and the default scratchpad
  layout match between `cnn_mmio_interface.v`, `cnn_mmio_regs.h`,
  `mmio_runtime.py`, and `cnn_mmio_host.c`.
- The current gap is not architectural. The main remaining work is bring-up and
  execution discipline:
  data availability, board compilation, and hardware validation sequence.
- The biggest software mismatch was file naming:
  Python/mock used `preload_conv_cfg_45w.txt`-style names while the C tools were
  using older `conv_cfg_words.txt`-style names. The C loader now accepts both.

## HPS Plus MMIO Self-Check

This is the current code-level verdict on the board path:

- `de1_soc/soc_system.qsys` already places `cnn_mmio_interface_0` on
  `hps_0.h2f_lw_axi_master`.
- `de1_soc/soc_system.sopcinfo` shows the HPS-visible base as `0xff200000`.
- `input/RTL/interface/cnn_mmio_interface.v` already implements:
  `CLEAR_STATUS`, `MODEL_LOAD`, `INFER`, status bits, predict latch, and
  interface error reporting.
- `de1_soc/cnn_mmio_demo_top.v` already mirrors the key wrapper state to LEDs.
- The host-side staged flow already exists in C:
  `status -> load_model -> run_case`.
- The Python path already mirrors the same register/memory contract and is good
  for software-side transaction validation.

What is still missing for board success:

- a matching `soc_system.rbf`
- a matching boot-time `soc_system.dtb`
- a clean bridge-enable boot sequence after FPGA configuration
- first-board runs at a timing-safe clock target

In other words: the remaining risk is bring-up integration, not missing host or
wrapper architecture.

## Latest Board Checkpoint

This mainline is now board-validated for the `digit_0_test` path.

- `hps_mmio_load_model` succeeds on-board and sets `model_loaded=1`
- `hps_mmio_run_case` succeeds on-board for `digit_0_test`
- `hps_mmio_infer` succeeds end-to-end on-board for `digit_0_test`
- the key software fix was in `tools/cnn_mmio_host.c`:
  use packed 32-bit MMIO transactions across the HPS bridge instead of raw
  16-bit halfword accesses

Validated board output:

```text
expected_class=0
predict_class=0
status=0x000c
error=0x0000
```

## Current Critical Blockers

- Timing is still documented as not closed at 50 MHz, so first board runs should
  assume a reduced FPGA clock target or expect timing-related instability.
- On a board that still boots the old lab image, the HPS Linux device tree will
  still describe the old `vga@...` peripheral under the bridge instead of the
  MMIO accelerator. In that state, `hps_mmio_status 0xff200000` is expected to
  return garbage and should be treated as a wrong-bitstream symptom, not as an
  accelerator logic result.
- `lab3-hw/lab3.pdf` adds one more board-specific caveat: after FPGA
  reconfiguration, the HPS-to-FPGA bridges may need to be re-enabled through
  the normal boot handoff path. If Linux was already running when a new `.sof`
  was pushed over JTAG, an all-zero MMIO window can still be a bridge state
  problem rather than a broken `cnn_mmio_interface`.

## Executable Next Step

Do these in order:

1. Re-run the local software path:
   `python test_data/run_case.py digit_0_test`
2. Build HPS tools:
   `make -C tools`
3. Build or stage the current board artifacts:
   `de1_soc/output_files/soc_system.rbf` and a matching `soc_system.dtb`
4. If you only have a bootable base DTB, patch it using
   `de1_soc/device_tree/patch_socfpga_dts.py` and rebuild it with `dtc`.
5. Prefer a clean boot with the new `.rbf` and matching `.dtb` so bridge
   handoff happens normally.
6. On Linux, inspect `/proc/device-tree/sopc@0` first. If you only see the old
   `vga@...` node under the lightweight bridge, stop and fix boot artifacts
   before trusting MMIO results.
7. Run:
   `./tools/hps_mmio_status <csr_base>`
8. Run model load once:
   `./tools/hps_mmio_load_model <csr_base> <preload_root>`
9. Run one case:
   `./tools/hps_mmio_run_case <csr_base> <case_root>`
10. Only if HPS access is blocked, fall back to the LED demo top for wrapper
   alive/status debugging.

Use this base address unless you have contradictory board evidence:

- `csr_base = 0xff200000`

Use these canonical data roots:

- preload root:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/<case>`
- case root:
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/<case>`

## Mock To Real HPS Transition

Do not introduce a third runtime. The smooth transition path is already here:

1. Validate layout and case selection with
   `python test_data/run_case.py <case>`.
2. Keep using `tools/run_mmio_inference.py` for transaction planning.
3. Switch backend from `mock` to `devmem` only when the board boots the correct
   FPGA image and DTB:
   `python tools/run_mmio_inference.py --backend devmem --base-addr 0xff200000 ...`
4. For board bring-up, prefer the C tools first because they isolate each stage:
   `hps_mmio_status`, `hps_mmio_load_model`, then `hps_mmio_run_case`.
5. Once staged C bring-up is stable, treat `hps_mmio_infer` or the Python
   `devmem` path as convenience wrappers, not as the first debug tool.

## Model-Load-Once Flow

This should be the default operational flow:

1. Preprocess an image into the hardware-aligned case format.
2. Write register layout once.
3. Write model preload bundle once.
4. Trigger `MODEL_LOAD` once.
5. For each image:
   write image words only, trigger `INFER`, read prediction.

Interpretation:

- `sram_preload/<case>/` is really model payload plus fixed preload-format data.
- `txt_cases/<case>/` is per-image input plus expected-class metadata.
- If the model is unchanged, only `txt_cases/...` should vary across repeated
  inferences.

## Preprocess Placement

Keep preprocess in `gesture_runtime/preprocess.py`.

Recommended data ownership:

- Raw images belong outside the hardware debug tree, for example a future
  `test_data/images/` or another dataset folder.
- Hardware-facing canonical artifacts belong under the existing hardware-aligned
  export tree:
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/`
- Model preload artifacts belong under:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/`

Rule of thumb:

- `preprocess.py` should convert raw images into the same 64x64 int8 format that
  `tb_conv1_in_i8_64x64x1.txt` already represents.
- Board and mock flows should consume the exported TXT artifacts, not raw image
  files directly.

Practical flow ownership:

- image source:
  external dataset files or a future `test_data/images/`
- preprocessing code:
  `gesture_runtime/preprocess.py`
- canonical exported hardware case:
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/<case>/`
- canonical model payload:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/<case>/`

That split keeps the host/runtime code stable:

- model data changes rarely and should be loaded once
- case/image data changes per inference
- host tools should consume exported TXT artifacts, not own image decoding

## FPGA-Only Fallback

If you must temporarily leave HPS aside, keep it minimal:

1. Compile `de1_soc/cnn_mmio_demo_top.v`.
2. Use LED status only to confirm reset, model-load completion, predict-done,
   and class latch.
3. Do not design a separate long-term FPGA-only host path.

That path is a debug aid, not the project mainline.
