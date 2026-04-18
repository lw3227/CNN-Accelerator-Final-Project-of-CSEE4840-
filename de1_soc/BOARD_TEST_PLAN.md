# Board Test Plan

This document records the two validation paths for the current `soc_system`
bitstream:

1. FPGA/HPS hardware alive check without running HPS software
2. HPS userspace MMIO functional check

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
