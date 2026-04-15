# PyTorch / TFLite Workflow

This directory contains Python-side training, quantized export, evaluation, and demo assets.

## Main Files

- `wlx_train_cnn.ipynb`: training + INT8 TFLite export + tensor inspection
- `wlx_test_cnn.ipynb`: INT8 model evaluation (accuracy / per-class / confusion matrix)
- `export_tflite_params_mat.py`: export TFLite parameters to MATLAB `.mat`
- `wlx_rps_main.ipynb`: inference demo using `icons/` assets

## Environment

```bash
python3 -m venv .venv_tflite
source .venv_tflite/bin/activate
pip install -r pytorch/requirements.txt
```

## Typical Command (run from repo root)

Export `.mat` parameters for MATLAB:

```bash
.venv_tflite/bin/python pytorch/export_tflite_params_mat.py \
  --model models/v2.int8.tflite \
  --out models/v2.int8.params.mat
```

## Notes

- Notebook model paths are written relative to root-level `models/`.
- If you launch the kernel from the `pytorch/` subdirectory, adjust paths to `../models/...`.
