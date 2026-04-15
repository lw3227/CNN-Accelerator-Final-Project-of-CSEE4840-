# MATLAB INT8 Golden Flow

This folder now separates the model reference path from the RTL-oriented TXT
generator.

## Reference Path

```matlab
run('matlab/lab/rps_conv2.m')
```

Use this to inspect the original MATLAB/TFLite-style inference path and layer
figures.

## Hardware-Aligned TXT Generator

```matlab
run('matlab/hardware_aligned/run_all.m')
```

This writes `tb_*.txt` files under:

```text
matlab/hardware_aligned/debug/txt_cases/<case>/
```

The hardware-aligned path is intentionally separate from the reference path
because the RTL uses raw conv MAC, separate effective bias quantization, pure
maxpool, and INT32 FC argmax.

## Model Export

Before running either path, export the TFLite parameters from the repository
root:

```bash
.venv/bin/python pytorch/export_tflite_params_mat.py \
  --model models/v1.int8.tflite \
  --out models/v1.int8.params.mat
```
