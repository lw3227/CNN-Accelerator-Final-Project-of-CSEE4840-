# CNN Systolic-Array Accelerator for Gesture Recognition

This repository contains the algorithm exploration and hardware-aware CNN design used in an Apple-sponsored student ASIC tape-out project.

The work explores small CNN architectures for 64x64 grayscale gesture recognition and maps them to a systolic-array based INT8 CNN accelerator implemented in 65 nm.

Tools:
- PyTorch
- MATLAB
- Verilog (hardware design not fully released)

Note: Some hardware design files are omitted due to course policy.

![RPS Title](pytorch/medias/rps_title.png)

## Highlights

- End-to-end INT8 TFLite export and evaluation pipeline
- MATLAB implementation covering Conv/ReLU/Pool/Flatten/FC
- Golden comparison against TFLite intermediate tensors, with `dense_i8` reaching `0 diff`

## Model-to-MATLAB Flow (as used in the design review)

1. CNN model exploration and training (Python/TensorFlow)
- Gesture task: Rock / Paper / Scissors classification
- Input setting used for hardware-oriented design: `64x64x1` grayscale
- Architecture used for accelerator mapping: 3 convolution layers + ReLU + max-pooling + flatten + fully connected
- Hardware-oriented target model: ~464k MACs per inference (matching accelerator sizing)

2. Post-training quantization (PTQ) to INT8 (TensorFlow Lite)
- Train in FP32, then convert to full INT8 inference using TFLite
- Quantized artifacts include INT8 weights/activations, INT32 bias, and tensor quantization parameters (scale/zero-point)
- INT8 model keeps practical classification performance (project flow target: around 92%+)

3. Parameter export and transfer to MATLAB
- Export tensor parameters and quantization metadata from `.tflite` to `.mat`
- Import all required tensors in MATLAB to build an integer-only reference pipeline
- Use preprocessed `64x64` grayscale test images that are outside the training split for validation

4. MATLAB golden module construction
- Rebuild Conv/ReLU/Pool/Flatten/FC with integer arithmetic and TFLite-compatible requantization
- Run layer-by-layer checks against TFLite intermediate dumps (`input_q`, `conv1/2/3_relu`, `dense_i8`)
- Treat the verified MATLAB golden model as the functional reference for hardware mapping/RTL comparison

## Repository Layout

- `pytorch/`: training, quantized export, evaluation, and demo resources
- `matlab/`: INT8 operator implementations and alignment scripts
- `models/`: shared model artifacts used by both pipelines

## Quick Start

1. Create and activate a Python environment

```bash
python3 -m venv .venv_tflite
source .venv_tflite/bin/activate
pip install -r pytorch/requirements.txt
```

2. Follow the pipeline-specific guides

- Python pipeline: `pytorch/README.md`
- MATLAB pipeline: `matlab/README.md`

## Repro Commands

Run from repository root:

```bash
.venv_tflite/bin/python pytorch/export_tflite_params_mat.py \
  --model models/v2.int8.tflite \
  --out models/v2.int8.params.mat

.venv_tflite/bin/python matlab/dump_tflite_conv_acts.py \
  --model models/v2.int8.tflite \
  --image matlab/scissors_200_v1_test_1644.png \
  --outdir matlab/debug
```

## Public Release

See `docs/PUBLIC_RELEASE_CHECKLIST.md` before switching the repository to public.

## Acknowledgment

This work references and builds on ideas from:
- https://github.com/alexdjulin/RockPaperScissorsCNN.git
