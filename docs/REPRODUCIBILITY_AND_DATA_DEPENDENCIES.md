# Reproducibility and Data Dependency Note

Prepared to support reproduction of the submitted CNN accelerator project.

Design team:

- Cheng-wen Chu (cc5397)
- Chengcheng Xu (cx2355)
- Harvey Lu (hl3999)
- Linxiao Wu (lw3227)
- Mingyuan Zheng (mz3143)

Date: May 12, 2026

## Purpose

This note records the files, tools, operating steps, and data dependencies that
are required to reproduce the submitted DE1-SoC CNN accelerator flow. It is
written from the design perspective: the goal is to identify the source state
that defines the design, the artifacts that are intentionally generated, and
the external inputs that are not part of the source archive.

The expected reproduction path is:

```text
source archive -> Quartus / Platform Designer rebuild -> HPS C tools -> board
MMIO execution -> optional host Flask web demo
```

## Branch And Source Status

The local repository was inspected on May 12, 2026. The reproducible handoff
state described by this note is the `pre` branch after it was completed with the
source/configuration/reference files needed for the final project flow. The
files were taken from the `submission` branch or from the checked-out
`Golden-Module` source tree, while generated output directories were left out.

Before this cleanup, `pre` was a narrow source-only branch containing the core
web-to-board runtime files, HPS C files, and RTL files. The branch has now been
completed with the missing reproducibility resources:

- `docs/REPRODUCIBILITY_AND_DATA_DEPENDENCIES.md`
- `Golden-Module/` deployed model, exported parameters, MATLAB scripts, and
  per-case reference/preload data
- `platform_designer/cnn_mmio_interface_hw.tcl`
- `de1_soc/build_soc_system.py`
- `de1_soc/soc_system.qsys`
- `de1_soc/soc_system.sdc`
- `de1_soc/soc_system_project.tcl`
- `input/TB/sram_behav.v`
- `web_demo/static/`
- `web_demo/templates/`
- `web_demo/requirements.txt`

Generated Quartus and Platform Designer output is intentionally not copied into
`pre`; it should be regenerated from the source files listed below.

## Required Source Set

The following source groups define the reproducible submission. A source archive
should include these files or their final equivalents from the `submission`
branch.

### FPGA And Platform Designer Sources

- `input/RTL/`
  Custom accelerator RTL, including the MMIO wrapper, CNN datapath, SRAM
  controllers, quantization, pooling, and fully connected classifier.
- `de1_soc/soc_system_top.sv`
  DE1-SoC top-level wrapper.
- `de1_soc/soc_system.qsys`
  Saved Platform Designer system.
- `de1_soc/soc_system.sdc`
  Timing constraints for the board-level Quartus project.
- `de1_soc/soc_system_project.tcl`
  Quartus project creation and file assignment script.
- `de1_soc/build_soc_system.py`
  Cross-platform build wrapper for regenerating Platform Designer HDL and
  running Quartus.
- `platform_designer/cnn_mmio_interface_hw.tcl`
  Custom Platform Designer component descriptor for the CNN MMIO interface.

### HPS Runtime Sources

- `include/cnn_mmio_regs.h`
  Shared register and scratchpad layout.
- `include/cnn_mmio_host.h`
  Shared HPS host-side C declarations.
- `tools/cnn_mmio_host.c`
  Common MMIO mapping and transfer helper implementation.
- `tools/hps_mmio_status.c`
  Board status probe.
- `tools/hps_mmio_load_model.c`
  Board model preload command.
- `tools/hps_mmio_predict.c`
  Board FPGA prediction command.
- `tools/hps_cpu_reference.c`
  Board CPU reference path.
The tight `pre` handoff intentionally omits the development `tools/Makefile`
because that Makefile builds additional debug utilities that are not included in
this reduced source set. The core HPS tools can be compiled manually on the HPS
Linux environment:

```bash
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -c -o tools/cnn_mmio_host.o tools/cnn_mmio_host.c
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_status tools/hps_mmio_status.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_load_model tools/hps_mmio_load_model.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_predict tools/hps_mmio_predict.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_cpu_reference tools/hps_cpu_reference.c
```

### Host And Web Runtime Sources

- `gesture_runtime/`
  Host-side preprocessing, case export, CPU TFLite inference, SSH transport, and
  board orchestration.
- `web_demo/app.py`
  Flask entry point.
- `web_demo/config.py`
  Runtime configuration loader.
- `web_demo/static/`
  Browser JavaScript and CSS.
- `web_demo/templates/index.html`
  Browser UI template.
- `web_demo/requirements.txt`
  Host web runtime dependency list.

### Golden Model And Reference Data

In the development repository, `Golden-Module/` is managed as a Git submodule.
For the course source archive, do not rely on a submodule pointer alone. Include
the checked-out files listed below, or provide an equivalent source archive that
contains those files directly.

- `Golden-Module/models/v1.int8.tflite`
  Deployed INT8 TFLite model.
- `Golden-Module/models/v1.int8.params.mat`
  Exported quantized parameters for MATLAB reference generation.
- `Golden-Module/matlab/digit_0_test.png` through
  `Golden-Module/matlab/digit_9_test.png`
  Small reference input images.
- `Golden-Module/matlab/hardware_aligned/`
  MATLAB hardware-aligned forward path and SRAM preload generation scripts.
- `Golden-Module/matlab/hardware_aligned/debug/txt_cases/`
  Per-case reference tensors consumed by the board CPU reference and by RTL
  simulation checks.
- `Golden-Module/matlab/hardware_aligned/debug/sram_preload/`
  Per-case SRAM preload bundles consumed by the HPS model load command.
- `Golden-Module/pytorch/export_tflite_params_mat.py`
  TFLite-to-MAT parameter export helper.
- `Golden-Module/pytorch/retrain_digits_cnn.py`
  Training and export script for the compact digit gesture CNN.

## Files To Exclude From A Source Archive

The source archive should not include generated, bulky, or machine-local files.
The following categories should be excluded:

- `.git/` and other version-control metadata
- Quartus `db/`, `incremental_db/`, and `output_files/`
- generated Platform Designer HDL under `de1_soc/soc_system/`
- generated handoff reports and local board captures unless explicitly needed
- Python `__pycache__/` directories and compiled `.pyc` files
- HPS object files and compiled executables under `tools/`
- waveform dumps, simulator work directories, and temporary logs
- `web_demo/feedback_samples/`
- local `web_demo/demo_config.json`
- unused media, notebooks, and alternate model files from `Golden-Module/` that
  are not needed for the final board/web path
- full raw training datasets such as `dataset_wlx/`

This keeps the archive focused on files needed to regenerate the design rather
than files produced by a previous run.

## Tool Dependencies

### FPGA Build Host

Required:

- Intel Quartus Prime Lite or compatible Quartus installation for DE1-SoC
- Platform Designer command-line tools, especially `qsys-generate`
- `quartus_sh`
- `quartus_cpf`

Optional but useful:

- `quartus_pgm` for JTAG programming

The current project scripts were validated against the DE1-SoC / Cyclone V
flow. The build wrapper searches common Intel FPGA install locations and also
honors tool locations available on `PATH`.

### Host Python Runtime

Required for the web demo:

- Python 3
- Flask
- NumPy
- Pillow
- either `tflite-runtime` or TensorFlow with `tf.lite.Interpreter`

The web package dependencies are listed in `web_demo/requirements.txt`. The
TFLite interpreter is loaded at runtime by `gesture_runtime/cpu_inference.py`.

### Golden Model And Training Runtime

Required for regenerating the hardware-aligned MATLAB cases:

- MATLAB
- the included `Golden-Module/models/v1.int8.params.mat`

Required for retraining or re-exporting model parameters:

- Python 3
- TensorFlow 2.15 compatible environment
- NumPy
- SciPy
- OpenCV Python
- Matplotlib
- scikit-learn

The Python training dependency set is listed in
`Golden-Module/pytorch/requirements.txt`.

### HPS Board Runtime

Required on the DE1-SoC Linux side:

- root access or equivalent permission for `/dev/mem`
- GCC
- the source tree copied to a board directory such as `/root/cnn_acc_hps`

Required host-to-board access for the web demo:

- SSH/SCP from the host to the board
- board IP address and user configured in `web_demo/config.py` or in
  `web_demo/demo_config.json`

## Data Dependencies

The submitted source archive should contain the deployed model and board
reference artifacts needed to run the final demonstration path:

- the INT8 model: `Golden-Module/models/v1.int8.tflite`
- the exported MATLAB parameters:
  `Golden-Module/models/v1.int8.params.mat`
- per-case preload bundles:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_*_test/`
- per-case expected tensors:
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_*_test/`

The raw training dataset is not included in the source archive. The training
lane expects a local dataset root named `dataset_wlx/` with this structure:

```text
dataset_wlx/
  train/
    0/
    1/
    ...
    9/
  validation/
    0/
    1/
    ...
    9/
  test/
    0/
    1/
    ...
    9/
```

The active classification task uses ten sign-language digit classes. Labels
`0` through `9` are gesture class IDs. The `digit_*_test` folder names are a
legacy artifact naming convention and do not imply MNIST-style handwritten
digit recognition.

The likely external dataset family is the Kaggle sign-language digits dataset
lane referenced by the training scripts. Because the raw dataset is external,
retraining results can vary if the dataset split, preprocessing, or TensorFlow
version differs. The deployed board/web path does not require the raw dataset
because the model and exported reference artifacts are already included.

## Reproduction Procedure

### 1. Extract The Source Archive

Extract the submitted source archive into a clean directory. The archive should
contain source files and reference artifacts, but not Quartus build databases,
programming files, local logs, or version-control metadata.

### 2. Check The Expected Source Files

Confirm that the following files exist before rebuilding:

```text
de1_soc/soc_system.qsys
de1_soc/soc_system.sdc
de1_soc/soc_system_project.tcl
de1_soc/build_soc_system.py
platform_designer/cnn_mmio_interface_hw.tcl
input/RTL/system_top.v
input/RTL/interface/cnn_mmio_interface.v
Golden-Module/models/v1.int8.tflite
Golden-Module/models/v1.int8.params.mat
```

If these files are missing from a reduced `pre` branch checkout, copy them from
the `submission` branch or from the final source archive.

### 3. Rebuild The Quartus Project

From the repository root:

```bash
python de1_soc/build_soc_system.py --check
python de1_soc/build_soc_system.py
```

Expected generated outputs after a successful build include:

```text
de1_soc/output_files/soc_system.sof
de1_soc/output_files/soc_system.rbf
```

These files are generated outputs. They do not need to be present in the source
archive.

### 4. Program The FPGA

Program the generated `soc_system.sof` through Quartus Programmer or
`quartus_pgm`. On a DE1-SoC JTAG chain, the FPGA is commonly the second device
in the chain, so a command-line programming operation may need `@2` on the SOF
operation string.

### 5. Build The HPS Runtime Tools

Copy the source tree to the board, for example:

```text
/root/cnn_acc_hps
```

Then build on the board:

```bash
cd /root/cnn_acc_hps
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -c -o tools/cnn_mmio_host.o tools/cnn_mmio_host.c
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_status tools/hps_mmio_status.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_load_model tools/hps_mmio_load_model.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_predict tools/hps_mmio_predict.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_cpu_reference tools/hps_cpu_reference.c
```

### 6. Confirm MMIO Access

Run the board status command:

```bash
cd /root/cnn_acc_hps
./tools/hps_mmio_status 0xff200000
```

A useful idle response has `error=0x0000`. If the command cannot read the MMIO
window, check that the FPGA was programmed with the current bitstream and that
the HPS-to-FPGA bridge is enabled.

### 7. Load The Model

Load the board preload bundle:

```bash
cd /root/cnn_acc_hps
./tools/hps_mmio_load_model 0xff200000 Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test
```

The command should report `model_loaded=1` when the replayed preload has been
accepted by the accelerator.

### 8. Run One FPGA Prediction Case

Run one exported reference case:

```bash
cd /root/cnn_acc_hps
./tools/hps_mmio_predict 0xff200000 Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

The result should include:

```text
predict_class=<class id>
error=0x0000
```

For a stricter check, compare the FPGA result with the expected label stored in
the case manifest and with the HPS CPU reference path.

### 9. Run The Host Web Demo

On the host machine, install the host dependencies and run:

```bash
python web_demo/app.py
```

Open:

```text
http://127.0.0.1:5000
```

The web path uses:

```text
browser -> Flask host process -> SSH/SCP -> HPS C tools -> MMIO -> FPGA
```

Board address, SSH user, model path, remote repository path, and CSR base can be
configured through environment variables or through `web_demo/demo_config.json`.
The local demo config file is machine-specific and should not be included in
the source archive.

## Minimal Reproduction Checklist

Use this checklist to decide whether a source package is complete enough for an
independent rebuild:

- Platform Designer source is present: `de1_soc/soc_system.qsys`
- custom component descriptor is present:
  `platform_designer/cnn_mmio_interface_hw.tcl`
- Quartus project script and SDC are present:
  `de1_soc/soc_system_project.tcl`, `de1_soc/soc_system.sdc`
- accelerator RTL is present under `input/RTL/`
- HPS headers and C tools are present under `include/` and `tools/`
- deployed model and exported parameter file are present under
  `Golden-Module/models/`
- board preload and reference cases are present under
  `Golden-Module/matlab/hardware_aligned/debug/`
- generated Quartus output and local debug data are absent from the archive

The `pre` branch should be checked against this list before creating the final
course `.tar.gz` archive.
