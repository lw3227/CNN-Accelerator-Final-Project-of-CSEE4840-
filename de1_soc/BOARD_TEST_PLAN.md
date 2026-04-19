# Board Test Plan

This document records the two validation paths for the current `soc_system`
bitstream:

1. FPGA/HPS hardware alive check without running HPS software
2. HPS userspace MMIO functional check

## Current Validated State

As of the latest board bring-up on the restored SD boot flow:

- boot-time `soc_system.dtb` now exposes `cnn_mmio_interface@0x100000000`
  under `/proc/device-tree/sopc@0/bridge@0xc0000000`
- Linux registers all three bridges successfully
- the current `de1_soc/output_files/soc_system.sof` responds at `0xff200000`
- the practical HPS-side fix was to use packed 32-bit MMIO transactions in
  `tools/cnn_mmio_host.c`, not raw 16-bit halfword stores
- board-validated commands now succeed:
  - `./tools/hps_mmio_load_model 0xff200000 Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test`
  - `./tools/hps_mmio_run_case 0xff200000 Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test`
  - `./tools/hps_mmio_infer 0xff200000 Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test`

Observed board result:

```text
expected_class=0
predict_class=0
status=0x000c
error=0x0000
```

## 1. Hardware Alive Check

Use SignalTap on the programmed FPGA image.

Recommended nodes:

- `soc_system_top|CLOCK_50`
- `soc_system_top|u_soc_system|clk_clk`
- `soc_system_top|u_soc_system|cnn_mmio_interface_0|reset`
- `soc_system_top|u_soc_system|cnn_mmio_interface_0|model_loaded`
- `soc_system_top|u_soc_system|cnn_mmio_interface_0|predict_done`
- `soc_system_top|u_soc_system|cnn_mmio_interface_0|predict_class_latched[3:0]`
- `soc_system_top|u_soc_system|cnn_mmio_interface_0|interface_error[15:0]`
- `soc_system_top|u_soc_system|hps_0|h2f_lw_axi_clock`

Expected idle behavior before any HPS software runs:

- `CLOCK_50` toggles
- `clk_clk` toggles
- `h2f_lw_axi_clock` toggles
- `reset = 0` after configuration
- `model_loaded = 0`
- `predict_done = 0`
- `interface_error = 0x0000`

If those hold, the programmed hardware is alive and the MMIO block is idle and
stable.

## 2. HPS MMIO Functional Check

Preflight:

- The FPGA image on the board must be the `de1_soc` MMIO design, not the older
  lab framebuffer / VGA design.
- If the FPGA fabric was reprogrammed by JTAG after Linux already booted, do
  not assume the HPS-to-FPGA bridges are still usable. The `lab3.pdf` flow
  explicitly enables the bridges again after FPGA configuration in U-Boot via
  `run bridge_enable_handoff`.
- A quick Linux-side smell test is to inspect `/proc/device-tree/sopc@0`:
  if the active bridge subtree only exposes something like `vga@...` and does
  not expose the MMIO accelerator node, `hps_mmio_status` will read garbage
  data from the bridge window and the rest of this section is not meaningful.
- If Linux-side MMIO reads return all zeros from both `0xff200000` and
  `0xc0000000` even after the correct `.sof` is programmed, treat that as a
  bridge/boot-sequence problem first:
  reboot with the new `.rbf` and matching `.dtb`, or re-enter U-Boot and run
  the bridge-enable handoff sequence before blaming the accelerator RTL.

Host-side boot artifact prep:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc/device_tree/build_soc_system_dtb.ps1 `
  -BaseDtb path\to\board_base.dtb
```

Safety rule:

- only use a complete bootable base DTB/DTS as input
- do not flash a tiny generated DTB fragment as `soc_system.dtb`
- if the helper refuses to build because the output is too small, treat that as
  a protection against bricking the boot flow

If the SD boot partition is mounted directly on the host, prefer staging via:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc/device_tree/stage_boot_partition.ps1 `
  -BootDriveLetter X
```

Expected host outputs:

- `de1_soc/output_files/soc_system.rbf`
- `de1_soc/device_tree/build/soc_system.dtb`

One-command serial bring-up from the host:

```powershell
python tools/run_hps_board_flow.py --port COM3 --case digit_0_test
```

If you also want to stage the new boot artifacts onto the board filesystem over
serial before rebooting:

```powershell
python tools/run_hps_board_flow.py --port COM3 --case digit_0_test `
  --upload-boot-artifacts
```

That flow performs these steps on HPS Linux:

- `make -C tools`
- inspect `/proc/device-tree/sopc@0`
- run `./tools/hps_mmio_status 0xff200000`
- run `./tools/hps_mmio_load_model 0xff200000 .../sram_preload/<case>`
- run `./tools/hps_mmio_run_case 0xff200000 .../txt_cases/<case>`

Board-side replacement goal:

- replace the boot `soc_system.rbf` with `de1_soc/output_files/soc_system.rbf`
- replace the boot `soc_system.dtb` with `de1_soc/device_tree/build/soc_system.dtb`
- do a clean reboot so the bridge handoff runs during normal boot

Recovery if the board stops booting after DTB replacement:

- restore the last known-good `soc_system.dtb` on the SD boot partition
- restore the last known-good `soc_system.rbf` if needed
- confirm serial boot logs come back before re-attempting MMIO bring-up

If backup files already exist on the boot partition, you can restore them with:

```powershell
powershell -ExecutionPolicy Bypass -File de1_soc/device_tree/restore_boot_partition.ps1 `
  -BootDriveLetter X
```

Linux-side smell test before MMIO:

```bash
find /proc/device-tree/sopc@0 -maxdepth 3 | sort
```

Expected:

- a lightweight-bridge subtree exists
- it exposes a `cnn_mmio_interface@0`-style child
- it does not only expose the old `vga@...` node

If the active tree is still describing the old VGA design, stop here and fix
the boot artifacts before continuing.

Important host-side note:

- if `hps_mmio_status` looks sane but `hps_mmio_load_model` never sets
  `model_loaded`, do not jump back to RTL first
- the confirmed failure mode on this project was a host access-width mismatch
  when using raw 16-bit MMIO stores through the HPS bridge
- the current validated path is the packed 32-bit access logic in
  `tools/cnn_mmio_host.c`

On HPS Linux:

```bash
cd /homes/user/stud/fall25/lw3227/CNN_ACC
make -C tools
```

The CSR base passed to the tools should be the HPS-visible base of the
`cnn_mmio_interface` Avalon slave. For the current system, start with:

```bash
0xff200000
```

### 2.1 Status Probe

```bash
./tools/hps_mmio_status 0xff200000
```

Expected:

- command returns normally
- prints `status=...`
- prints `error=0x0000`

### 2.2 Model Load

```bash
./tools/hps_mmio_load_model 0xff200000 \
  Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test
```

Expected:

- `model_loaded=1`
- no timeout

### 2.3 Single-Case Inference

```bash
./tools/hps_mmio_run_case 0xff200000 \
  Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

Expected:

- `predict_class` equals `expected_class`
- `error=0x0000`

### 2.4 End-to-End Inference

```bash
./tools/hps_mmio_infer 0xff200000 \
  Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test \
  Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

Expected:

- `predict_class` equals `expected_class`
- `status` shows both model-loaded and predict-done bits set
- `error=0x0000`

## 3. Local Pre-Board Result

The software path has already been checked locally with the mock backend:

```text
expected_class=0
predict_class=0
status=0x000c
error=0x0000
```

This confirms the host-side runtime and the expected control/status flow are
consistent before board execution.
