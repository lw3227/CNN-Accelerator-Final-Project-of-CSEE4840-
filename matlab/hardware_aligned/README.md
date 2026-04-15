# Hardware-Aligned TXT Generator

This folder contains the MATLAB generator used for RTL/TB golden TXT files.
It is separate from `matlab/lab/rps_conv2.m` because the RTL path is not the
same as the TFLite-style reference path.

Run:

```matlab
run('matlab/hardware_aligned/run_all.m')
```

Default paths:

- parameters: `models/v1.int8.params.mat`
- images: `matlab/digit_*_test.png`
- output: `matlab/hardware_aligned/debug/txt_cases/<case>/`

Main files:

- `run_all.m`: batch entry point
- `export_case.m`: one image to `tb_*.txt` plus `manifest.txt`
- `hw_forward.m`: hardware-style forward pass
- `dump_txt.m`: one signed integer per line writer
- `load_params.m`: load exported TFLite params for hardware flow

Important behavior:

- Conv MAC uses raw INT32 MAC with `x_zp = 0`, `w_zp = 0`, `bias = 0`.
- Quantization adds `eff_bias = bias - x_zp * sum(W)` separately.
- Pooling is pure 2x2 maxpool.
- FC output is INT32 accumulator for argmax, not final int8 softmax/logit output.

`gen_sram_preload.m` is kept here for reference, but its conv config packing
still needs RTL verification before relying on it for full-system preload.
