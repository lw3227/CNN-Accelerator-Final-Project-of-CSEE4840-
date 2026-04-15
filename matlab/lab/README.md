# MATLAB Reference

This folder keeps the original MATLAB reference pipeline.

Run from the repository root or from MATLAB:

```matlab
run('matlab/lab/rps_conv2.m')
```

`rps_conv2.m` loads:

- parameters from `models/v1.int8.params.mat`
- sample image from `matlab/digit_9_test.png` by default

Use this path to inspect the model-level inference result and layer figures.
It is not the hardware TXT generator.
