# Model Diagnostics

This is a point-in-time diagnostic note, not the main bring-up guide. Start
with [README.md](README.md) if you are orienting to the repo for the first
time.

This note records the current findings from the web-demo validation path.

## Current Built-In Suite Result

Using the built-in `digit_0_test` through `digit_9_test` sample images through
the **same upload-style web path**, the current deployed model path reaches:

- `9 / 10` pass

The current remaining failing case is:

- `digit_4_test`

## What The Failure Means

For `digit_4_test`, the current deployed CPU model already shows an internal
ambiguity, even before the FPGA path is considered.

Observed behavior:

- CPU predicts `6`
- FPGA predicts `7`
- expected class is `4`

The important part is that the CPU-side raw output is already weak and
ambiguous for this case. In one recent diagnostic run, the top scores for
classes `6` and `7` were tied, while class `4` was not competitive.

That strongly suggests the remaining error is **not primarily a transport bug**
or an HPS/FPGA inconsistency. It is more likely one of:

- the deployed artifact is not the best available checkpoint
- the exported artifact differs from the originally intended training result
- this specific class is weakly separated in the current model
- the hardware-aligned exported sample differs slightly from the training
  distribution

## What Has Improved Already

The upload path originally suffered from unstable preprocessing. After adding:

- foreground-aware crop mode
- plain-resize fallback mode
- automatic branch selection based on CPU confidence margin

the built-in suite improved from:

- `8 / 10` to `9 / 10`

and `digit_0_test` recovered.

## Current Practical Interpretation

At this point:

- CPU and FPGA are usually aligned
- the deployed path is mostly working
- the remaining issue is concentrated in model/sample semantics, not just in
  the browser-upload plumbing

## Best Next Steps

1. Confirm whether a better trained/exported checkpoint exists than the current
   `Golden-Module/models/v1.int8.tflite`
2. Inspect the original `dataset_wlx` examples for class `4`
3. Re-export hardware-aligned artifacts after confirming the intended model
4. Keep using the built-in suite as the regression gate for every preprocessing
   or model change
