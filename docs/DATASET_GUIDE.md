# Dataset Guide

This project's current 10-class gesture lane is based on a **sign-language
digits** dataset, not handwritten digits and not the older
`paper / rock / scissors` exploration lane.

## Current Meaning Of The 10 Classes

- The deployed board/demo path currently uses **10 gesture class IDs**
- These class IDs are `0..9`
- They should be interpreted as **sign-language number gestures**
- Existing hardware-aligned artifact folders still use legacy names such as
  `digit_0_test`, `digit_7_test`, and so on

Those filenames are a historical naming convention for exported case folders.
They do **not** mean the current demo should be interpreted as MNIST-style
handwritten digit recognition.

## Dataset Root Used By The Training Lane

The Python-side training and preprocessing lane expects a dataset root named:

```text
dataset_wlx/
```

The clearest local references are:

- [../Golden-Module/pytorch/save_preprocessed_dataset.py](../Golden-Module/pytorch/save_preprocessed_dataset.py)
- [../Golden-Module/pytorch/wlx_build_dataset.ipynb](../Golden-Module/pytorch/wlx_build_dataset.ipynb)
- [../Golden-Module/pytorch/wlx_train_cnn.ipynb](../Golden-Module/pytorch/wlx_train_cnn.ipynb)

Expected split structure:

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

## External Source

The local notebooks point to the **Sign Language Digits Dataset** lane commonly
hosted on Kaggle. The likely source family is:

- `ardamavi/sign-language-digits-dataset`

This matches the 10-class `0..9` structure used by the current `wlx_*`
notebooks.

## What Is In The Repo Today

Present in the repo:

- deployed model artifact:
  `Golden-Module/models/v1.int8.tflite`
- exported MATLAB parameter artifact:
  `Golden-Module/models/v1.int8.params.mat`
- hardware-aligned case folders under:
  `Golden-Module/matlab/hardware_aligned/debug/`

Not present in the repo:

- the original full `dataset_wlx/` dataset tree

So the current repository has the **deployed/exported artifacts**, but not the
full raw dataset itself.

## Historical Lanes To Treat Carefully

There are older materials in the repo that should not override the current
10-class gesture interpretation:

- `Golden-Module/matlab/lab/`
- `matlab_old/`
- `Golden-Module/pytorch/wlx_rps_main.ipynb`

Those are useful references, but they are not the active dataset definition for
the current board/web-demo line.

## Practical Rule

For current board and web-demo work:

- treat the task as **10-class gesture classification**
- treat labels `0..9` as **gesture IDs**
- treat `digit_*` directory names as **legacy file naming only**
