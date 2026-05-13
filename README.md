# CNN Accelerator on DE1-SoC: Project Source and Reproduction Guide

This document describes the source package for the CSEE4840 final project
implementing a compact INT8 CNN accelerator on the DE1-SoC platform. It is
intended to support an independent rebuild of the FPGA project, the HPS board
runtime, and the host web-to-board demonstration path from source files and
small reference artifacts only.

Design team:

- Cheng-wen Chu (cc5397)
- Chengcheng Xu (cx2355)
- Harvey Lu (hl3999)
- Linxiao Wu (lw3227)
- Mingyuan Zheng (mz3143)

Date: May 12, 2026

## 1. Project Source Scope

The source package is organized as a reproducible project handoff. It keeps the
files needed to recreate the final project state while intentionally omitting
generated build output, local debug captures, raw training data, and git history
from the course submission archive.

The expected reproduction path is:

```text
source tree
  -> Quartus / Platform Designer rebuild
  -> FPGA programming file
  -> HPS C runtime build
  -> MMIO model load and inference
  -> optional host Flask web demo
```

This project source package contains the deployed model, the exported hardware
parameters, and the compact per-case reference/preload artifacts needed for the
final board flow. It does not contain the raw external training dataset or
generated Quartus databases.

## 2. Repository Layout

The main directories are:

```text
.
|-- README.md
|-- de1_soc/
|   |-- build_soc_system.py
|   |-- soc_system.qsys
|   |-- soc_system.sdc
|   |-- soc_system_project.tcl
|   `-- soc_system_top.sv
|-- platform_designer/
|   `-- cnn_mmio_interface_hw.tcl
|-- input/
|   |-- RTL/
|   `-- TB/
|-- include/
|-- tools/
|-- gesture_runtime/
|-- web_demo/
`-- Golden-Module/
```

The roles of these directories are:

- `de1_soc/`: DE1-SoC top-level files, saved Platform Designer system,
  timing constraints, and Quartus rebuild wrapper.
- `platform_designer/`: custom Platform Designer component descriptor for the
  CNN MMIO interface.
- `input/RTL/`: synthesizable accelerator RTL, including the MMIO wrapper,
  CNN datapath, SRAM controllers, quantization, pooling, and fully connected
  classifier.
- `input/TB/`: compact SRAM behavioral model needed by the Quartus project
  script.
- `include/`: C register definitions and host helper declarations shared by
  the HPS tools.
- `tools/`: reduced HPS C runtime used by the final board path.
- `gesture_runtime/`: host-side preprocessing, case export, CPU inference,
  SSH transport, and board orchestration.
- `web_demo/`: Flask web application and browser assets.
- `Golden-Module/`: deployed INT8 model, exported parameter file, MATLAB
  hardware-aligned reference scripts, and compact reference/preload cases.

## 3. What Is Included

The source package includes the source and compact data artifacts required for the
final web-to-board accelerator path.

### FPGA and Platform Designer Sources

- `input/RTL/`
- `input/TB/sram_behav.v`
- `de1_soc/soc_system_top.sv`
- `de1_soc/soc_system.qsys`
- `de1_soc/soc_system.sdc`
- `de1_soc/soc_system_project.tcl`
- `de1_soc/build_soc_system.py`
- `platform_designer/cnn_mmio_interface_hw.tcl`

### HPS Runtime Sources

- `include/cnn_mmio_regs.h`
- `include/cnn_mmio_host.h`
- `tools/cnn_mmio_host.c`
- `tools/hps_mmio_status.c`
- `tools/hps_mmio_load_model.c`
- `tools/hps_mmio_predict.c`
- `tools/hps_cpu_reference.c`

The development `tools/Makefile` is intentionally not part of this reduced
handoff because it builds additional debug utilities that are not included in
the source set. The required HPS programs can be compiled directly with the
commands in Section 9.

### Host and Web Runtime Sources

- `gesture_runtime/board_transport.py`
- `gesture_runtime/case_export.py`
- `gesture_runtime/cpu_inference.py`
- `gesture_runtime/demo_compare.py`
- `gesture_runtime/fpga_service.py`
- `gesture_runtime/preprocess.py`
- `gesture_runtime/preprocess_selection.py`
- `gesture_runtime/quantization.py`
- `gesture_runtime/ssh_transport.py`
- `web_demo/app.py`
- `web_demo/config.py`
- `web_demo/requirements.txt`
- `web_demo/static/`
- `web_demo/templates/index.html`

### Golden Model and Reference Data

- `Golden-Module/models/v1.int8.tflite`
- `Golden-Module/models/v1.int8.params.mat`
- `Golden-Module/matlab/digit_0_test.png` through `digit_9_test.png`
- `Golden-Module/matlab/hardware_aligned/*.m`
- `Golden-Module/matlab/hardware_aligned/debug/txt_cases/`
- `Golden-Module/matlab/hardware_aligned/debug/sram_preload/`
- `Golden-Module/pytorch/export_tflite_params_mat.py`
- `Golden-Module/pytorch/retrain_digits_cnn.py`

In the development repository, `Golden-Module/` may be managed as a Git
submodule. For a standalone course source archive, the checked-out files listed
above should be included directly, not only as a submodule pointer.

## 4. What Should Not Be Included in the Course Archive

The course `.tar.gz` archive should be small and source-oriented. It should not
contain generated, bulky, or machine-local files.

Exclude:

- `.git/` and other version-control metadata
- Quartus `db/`
- Quartus `incremental_db/`
- Quartus `output_files/`
- generated Platform Designer HDL under `de1_soc/soc_system/`
- generated QIP/SOPCINFO/handoff reports
- `.sof`, `.rbf`, and other programming files
- Python `__pycache__/` and `.pyc` files
- HPS object files and compiled executables under `tools/`
- simulator work directories, waveform dumps, and temporary logs
- `web_demo/feedback_samples/`
- local `web_demo/demo_config.json`
- raw training datasets such as `dataset_wlx/`
- notebooks, alternate models, unused media, and other files from development
  experiments that are not needed for the final board/web path

A normal source archive for this project should be only a few megabytes.

## 5. Required Tools

### FPGA Build Host

Required:

- Intel Quartus Prime Lite or compatible Quartus installation for DE1-SoC
- Platform Designer command-line tools, including `qsys-generate`
- `quartus_sh`
- `quartus_cpf`
- Python 3

Optional:

- `quartus_pgm` for command-line JTAG programming

The build wrapper searches common Intel FPGA install paths and also honors tool
locations available on `PATH`. If Quartus is installed in a custom location,
set `QUARTUS_ROOTDIR` or add the Quartus binary directory to `PATH`.

### HPS Board Runtime

Required on the DE1-SoC Linux side:

- GCC
- root access or equivalent permission to open `/dev/mem`
- a copy of this source tree on the board, commonly under
  `/root/cnn_acc_hps`

### Host Web Demo Runtime

Required on the development host:

- Python 3
- Flask
- NumPy
- Pillow
- either `tflite-runtime` or TensorFlow with `tf.lite.Interpreter`
- SSH/SCP access from the host to the DE1-SoC board

The minimal web dependencies are listed in `web_demo/requirements.txt`.

### Golden Model Regeneration

Required only if regenerating reference tensors or preload bundles:

- MATLAB
- `Golden-Module/models/v1.int8.params.mat`

Required only if retraining or re-exporting the model:

- Python 3
- TensorFlow 2.15-compatible environment
- NumPy
- SciPy
- OpenCV Python
- Matplotlib
- scikit-learn

The final board/web demonstration does not require retraining.

## 6. Data Dependencies

The included deployed model and reference artifacts are sufficient to run the
final board flow:

- INT8 TFLite model:
  `Golden-Module/models/v1.int8.tflite`
- exported MATLAB parameter file:
  `Golden-Module/models/v1.int8.params.mat`
- model preload bundles:
  `Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_*_test/`
- expected tensors and image cases:
  `Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_*_test/`

The raw training dataset is external and is not part of this source package. The
training script expects a local dataset root named `dataset_wlx/` with this
layout:

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

The active classification task uses ten sign-language digit classes labeled
`0` through `9`. The `digit_*_test` folder names are legacy case names and do
not indicate MNIST-style handwritten digit recognition.

## 7. Initial Source Check

After cloning or extracting the source archive, confirm that the required files
exist:

```bash
test -f de1_soc/soc_system.qsys
test -f de1_soc/soc_system.sdc
test -f de1_soc/soc_system_project.tcl
test -f de1_soc/build_soc_system.py
test -f platform_designer/cnn_mmio_interface_hw.tcl
test -f input/RTL/system_top.v
test -f input/RTL/interface/cnn_mmio_interface.v
test -f Golden-Module/models/v1.int8.tflite
test -f Golden-Module/models/v1.int8.params.mat
```

On Windows PowerShell, the same check can be done with:

```powershell
Test-Path de1_soc/soc_system.qsys
Test-Path de1_soc/soc_system.sdc
Test-Path de1_soc/soc_system_project.tcl
Test-Path de1_soc/build_soc_system.py
Test-Path platform_designer/cnn_mmio_interface_hw.tcl
Test-Path input/RTL/system_top.v
Test-Path input/RTL/interface/cnn_mmio_interface.v
Test-Path Golden-Module/models/v1.int8.tflite
Test-Path Golden-Module/models/v1.int8.params.mat
```

Each command should return success or `True`.

## 8. Rebuild the Quartus Project

Run the build from the repository root:

```bash
python de1_soc/build_soc_system.py --check
python de1_soc/build_soc_system.py
```

The `--check` command verifies that the required Quartus tools can be found.
The full build command performs the expected project regeneration and compile
flow:

1. generate Platform Designer HDL from `de1_soc/soc_system.qsys`
2. create or refresh the Quartus project using
   `de1_soc/soc_system_project.tcl`
3. compile the project through `quartus_sh --flow compile`
4. generate FPGA programming outputs

Expected generated outputs include:

```text
de1_soc/output_files/soc_system.sof
de1_soc/output_files/soc_system.rbf
```

These outputs are generated products. They should not be committed or included
in the source archive.

If the build wrapper cannot find Quartus, first confirm that `quartus_sh` and
`qsys-generate` are callable from the same shell. If not, add the Quartus binary
directory to `PATH` or set `QUARTUS_ROOTDIR`.

## 9. Program the FPGA

Program `de1_soc/output_files/soc_system.sof` with Quartus Programmer or the
command-line programmer.

The exact command depends on the local JTAG chain. On many DE1-SoC setups, the
FPGA is the second device in the chain, so command-line programming may require
an operation string with `@2`. If using the GUI, select the generated SOF file
and program the FPGA device.

The HPS MMIO tests in later sections assume the FPGA has already been
programmed with this bitstream.

## 10. Copy the Source Tree to the HPS

Copy the source tree to the DE1-SoC Linux environment. A common destination is:

```text
/root/cnn_acc_hps
```

For example, from the host:

```bash
scp -r cnn_accelerator_source root@192.168.0.2:/root/cnn_acc_hps
```

Adjust the source directory, board user, and board IP address to match the
local setup. The web demo defaults to board host `192.168.0.2`, user `root`,
and remote repository path `/root/cnn_acc_hps`, but these can be configured as
described in Section 14.

## 11. Build the HPS Runtime Tools

On the DE1-SoC Linux shell:

```bash
cd /root/cnn_acc_hps
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -c -o tools/cnn_mmio_host.o tools/cnn_mmio_host.c
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_status tools/hps_mmio_status.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_load_model tools/hps_mmio_load_model.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_mmio_predict tools/hps_mmio_predict.c tools/cnn_mmio_host.o
gcc -O2 -std=c11 -Wall -Wextra -Iinclude -o tools/hps_cpu_reference tools/hps_cpu_reference.c
```

These commands create the five board-side executables used by the final flow:

- `tools/hps_mmio_status`
- `tools/hps_mmio_load_model`
- `tools/hps_mmio_predict`
- `tools/hps_cpu_reference`
- the shared object file `tools/cnn_mmio_host.o`

The object file and executables are build outputs and should not be included in
the course source archive.

## 12. Check MMIO Access

From the HPS Linux shell:

```bash
cd /root/cnn_acc_hps
./tools/hps_mmio_status 0xff200000
```

Expected output is a set of key-value lines similar to:

```text
status=0x....
predict_class=...
error=0x0000
model_loaded=...
predict_done=...
```

`error=0x0000` indicates that the software-visible interface has not latched an
interface error. If this command fails to map `/dev/mem`, run it as root or
check permissions. If it maps successfully but returns unexpected values,
confirm that the FPGA was programmed with the current bitstream and that the
HPS-to-FPGA bridge is enabled.

## 13. Load the Model into the Accelerator

Load the default compact preload bundle:

```bash
cd /root/cnn_acc_hps
./tools/hps_mmio_load_model 0xff200000 Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test
```

Expected output includes:

```text
model_loaded=1
error=0x0000
```

The preload directory contains four streams consumed by the MMIO replay path:

- convolution configuration words
- convolution weight words
- fully-connected bias words
- fully-connected weight words

The `digit_0_test` preload folder is used as the default model bundle location.
It contains model parameters, not a digit-specific model. Other `digit_*_test`
preload folders are compact reference bundles generated by the same golden
flow.

## 14. Run a Board FPGA Prediction

Run one exported reference case through the FPGA:

```bash
cd /root/cnn_acc_hps
./tools/hps_mmio_predict 0xff200000 Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

Expected output includes:

```text
predict_class=<class id>
status=0x....
error=0x0000
l1_cycles=...
l2_p0_cycles=...
l2_p1_cycles=...
l3_p0_cycles=...
l3_p1_cycles=...
fc_cycles=...
argmax_cycles=...
total_cycles=...
board_total_ms=...
```

The result is printed in a machine-readable `key=value` format so that the
host-side web service can parse it.

For a board-side CPU comparison, run:

```bash
cd /root/cnn_acc_hps
./tools/hps_cpu_reference \
  Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test \
  Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

The first argument is the image case root. The second argument is the reference
case root containing weights, biases, quantization parameters, and expected
tensors.

## 15. Configure the Host Web Demo

The web demo is optional for low-level board validation, but it is the final
user-facing demonstration path. It performs:

```text
browser upload/capture
  -> Flask preprocessing
  -> host CPU TFLite comparison
  -> SCP case transfer to HPS
  -> HPS CPU reference command
  -> HPS MMIO FPGA command
  -> browser result rendering
```

The demo can be configured through environment variables or through a local
JSON file at `web_demo/demo_config.json`. The JSON file is machine-specific and
should not be included in the source archive.

Common environment variables:

```bash
export CNN_ACC_BOARD_HOST=192.168.0.2
export CNN_ACC_BOARD_USER=root
export CNN_ACC_BOARD_PORT=22
export CNN_ACC_REMOTE_REPO=/root/cnn_acc_hps
export CNN_ACC_CSR_BASE=0xff200000
export CNN_ACC_FABRIC_MHZ=50
```

Optional SSH variables:

```bash
export CNN_ACC_SSH_KEY=/path/to/private_key
export CNN_ACC_SSH_KNOWN_HOSTS=/path/to/known_hosts
```

Optional model/path variables:

```bash
export CNN_ACC_CPU_MODEL=Golden-Module/models/v1.int8.tflite
export CNN_ACC_REMOTE_PRELOAD_ROOT=Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test
export CNN_ACC_REMOTE_REFERENCE_CASE_ROOT=Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

If using `web_demo/demo_config.json`, the same values can be represented as:

```json
{
  "board_host": "192.168.0.2",
  "board_user": "root",
  "board_port": 22,
  "remote_repo": "/root/cnn_acc_hps",
  "csr_base": "0xff200000",
  "fabric_mhz": 50,
  "cpu_model": "Golden-Module/models/v1.int8.tflite",
  "remote_preload_root": "Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test",
  "remote_reference_case_root": "Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test"
}
```

## 16. Run the Host Web Demo

On the host machine:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r web_demo/requirements.txt
python web_demo/app.py
```

On Windows PowerShell, environment activation is commonly:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r web_demo\requirements.txt
python web_demo\app.py
```

Then open:

```text
http://127.0.0.1:5000
```

Before running a web inference, confirm that:

- the FPGA is programmed
- HPS tools have been compiled on the board
- the source tree is present at the configured `remote_repo`
- SSH from the host to the board works
- `hps_mmio_status` reports a usable MMIO interface

## 17. Optional: Regenerate Golden Reference Cases

The included reference and preload artifacts are already sufficient for the
final board flow. To regenerate them, use MATLAB from the
`Golden-Module/matlab/hardware_aligned/` directory and run:

```matlab
run_all
```

This consumes:

```text
Golden-Module/models/v1.int8.params.mat
Golden-Module/matlab/digit_0_test.png ... digit_9_test.png
```

and refreshes:

```text
Golden-Module/matlab/hardware_aligned/debug/txt_cases/
Golden-Module/matlab/hardware_aligned/debug/sram_preload/
```

If the MATLAB output changes, rerun both the HPS CPU reference and the FPGA
prediction path to verify that the updated artifacts remain aligned with the
RTL.

## 18. Optional: Retrain or Re-export the Model

Retraining is not required for reproduction of the submitted board demo. If
retraining is needed, prepare the external `dataset_wlx/` dataset root described
in Section 6 and use:

```bash
python Golden-Module/pytorch/retrain_digits_cnn.py
```

After generating or replacing a TFLite model, export MATLAB parameters with:

```bash
python Golden-Module/pytorch/export_tflite_params_mat.py
```

Then regenerate the MATLAB hardware-aligned reference cases and preload
bundles. Because retraining depends on external data, TensorFlow version, and
split details, it is not expected to produce bit-identical source artifacts
unless the full training environment is controlled.

## 19. Creating the Course Source Archive

The preferred archive is generated from tracked source files rather than by
compressing an existing build directory. From a clean source checkout:

```bash
git archive --format=tar.gz -o cnn_accelerator_source.tar.gz HEAD
```

If creating an archive from an extracted folder without git metadata, first
delete generated files listed in Section 4. Then create the archive from the
source tree root.

A quick check for common generated paths can be done with:

```bash
find . \( \
  -path './.git' -o \
  -path './de1_soc/db' -o \
  -path './de1_soc/incremental_db' -o \
  -path './de1_soc/output_files' -o \
  -path './de1_soc/soc_system' -o \
  -path './web_demo/feedback_samples' -o \
  -path '*/__pycache__' \
\) -print
```

The command should not report files intended for the final source archive.

## 20. Troubleshooting Guide

### Quartus tools are not found

Run:

```bash
quartus_sh --version
qsys-generate --version
```

If either command fails, add the Quartus binary directory to `PATH` or set
`QUARTUS_ROOTDIR`.

### Platform Designer generation fails

Confirm that:

- `de1_soc/soc_system.qsys` exists
- `platform_designer/cnn_mmio_interface_hw.tcl` exists
- the custom component path is visible to the project script
- generated `de1_soc/soc_system/` output from old builds has not been mixed
  with a different source revision

When in doubt, remove generated build folders and rebuild from the saved source files.

### HPS command cannot open `/dev/mem`

Run as root or with equivalent permissions. The HPS programs map the FPGA MMIO
window directly through `/dev/mem`.

### MMIO status reports an interface error

Check that:

- the FPGA was programmed with the current SOF
- the HPS-to-FPGA bridge is enabled
- the CSR base address is `0xff200000`
- the model was loaded before inference
- the scratchpad case directory matches the expected file format

### Web demo can open but inference fails

Check SSH and remote paths first:

```bash
ssh root@192.168.0.2 'cd /root/cnn_acc_hps && ./tools/hps_mmio_status 0xff200000'
```

If this command fails from the host, the Flask app will also fail because it
uses the same SSH/SCP path.

### CPU and FPGA predictions differ

Likely causes include:

- stale model preload in FPGA memory
- mismatched `txt_cases/` and `sram_preload/` artifacts
- wrong remote repository path
- changed preprocessing without regenerating a case
- interface error during MMIO replay

Reload the model, rerun `hps_mmio_status`, and compare the FPGA output against
`hps_cpu_reference` on the same case directory.

## 21. Minimal Completion Checklist

Before submitting or handing off the project source package, confirm:

- `README.md` is present at the repository root
- no additional README files are needed elsewhere
- `de1_soc/soc_system.qsys` is present
- `de1_soc/soc_system.sdc` is present
- `platform_designer/cnn_mmio_interface_hw.tcl` is present
- `input/RTL/` contains the accelerator RTL
- `include/` and `tools/` contain the HPS runtime sources
- `web_demo/` and `gesture_runtime/` contain the host demo sources
- `Golden-Module/models/v1.int8.tflite` is present
- `Golden-Module/models/v1.int8.params.mat` is present
- `Golden-Module/matlab/hardware_aligned/debug/` contains compact reference
  and preload cases
- generated Quartus/Platform Designer outputs are absent from the source
  archive

This checklist is intended to keep the project reproducible while preserving the
small source-only archive required for the final submission.
