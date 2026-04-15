# MATLAB INT8 Golden Flow

This folder is intentionally small now. It keeps one main MATLAB pipeline and
the INT8 operator helpers needed to rebuild CNN inference.

## Main Entry Point

```matlab
run('matlab/rps_conv2.m')
```

Before running, export the TFLite parameters from the repository root:

```bash
.venv/bin/python pytorch/export_tflite_params_mat.py \
  --model models/v1.int8.tflite \
  --out models/v1.int8.params.mat
```

## Kept Scope

- `rps_conv2.m`: clean Conv/ReLU/Pool/Flatten/FC pipeline
- `*_int8.m`, `relu*.m`, `tflite_quantize_multiplier.m`: integer operator helpers
- No generated debug files, NPY dumps, or TXT golden writers are kept here.
