#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import tensorflow as tf


def q_input_from_image(img_path: Path, in_scale: float, in_zero: int) -> np.ndarray:
    img = tf.keras.utils.load_img(img_path, color_mode="grayscale", target_size=(64, 64))
    x = tf.keras.utils.img_to_array(img).astype(np.float32) / 255.0
    x = x[np.newaxis, ...]
    x_q = np.clip(np.round(x / in_scale + in_zero), -128, 127).astype(np.int8)
    return x_q


def find_tensor_index(td: list[dict], keyword: str) -> int:
    hits = [d for d in td if keyword in d["name"]]
    if not hits:
        raise RuntimeError(f"Tensor not found for keyword: {keyword}")
    return int(hits[0]["index"])


def main() -> None:
    ap = argparse.ArgumentParser(description="Dump int8 conv/dense activations from TFLite")
    ap.add_argument("--model", type=Path, default=Path("models/v2.int8.tflite"))
    ap.add_argument("--image", type=Path, default=Path("matlab/scissors_200_v1_test_1644.png"))
    ap.add_argument("--outdir", type=Path, default=Path("matlab/debug"))
    args = ap.parse_args()

    interp = tf.lite.Interpreter(
        model_path=str(args.model),
        experimental_preserve_all_tensors=True,
        experimental_delegates=[],
    )
    interp.allocate_tensors()

    in_d = interp.get_input_details()[0]
    in_scale, in_zero = in_d["quantization"]
    x_q = q_input_from_image(args.image, in_scale, in_zero)
    interp.set_tensor(in_d["index"], x_q)
    interp.invoke()

    td = interp.get_tensor_details()
    idx_conv1_relu = find_tensor_index(td, "sequential/conv2d/Relu")
    idx_conv2_relu = find_tensor_index(td, "sequential/conv2d_1/Relu")
    idx_conv3_relu = find_tensor_index(td, "sequential/conv2d_2/Relu")
    idx_dense = find_tensor_index(td, "sequential/dense/MatMul;sequential/dense/BiasAdd")
    idx_final = find_tensor_index(td, "StatefulPartitionedCall:0")

    y1 = interp.get_tensor(idx_conv1_relu)[0]
    y2 = interp.get_tensor(idx_conv2_relu)[0]
    y3 = interp.get_tensor(idx_conv3_relu)[0]
    y_dense = interp.get_tensor(idx_dense)[0]
    y_final = interp.get_tensor(idx_final)[0]

    args.outdir.mkdir(parents=True, exist_ok=True)
    np.save(args.outdir / "tflite_input_q.npy", x_q[0, :, :, 0])
    np.save(args.outdir / "tflite_conv1_relu.npy", y1)
    np.save(args.outdir / "tflite_conv2_relu.npy", y2)
    np.save(args.outdir / "tflite_conv3_relu.npy", y3)
    np.save(args.outdir / "tflite_dense_i8.npy", y_dense)
    np.save(args.outdir / "tflite_final_i8.npy", y_final)

    print("[OK] dumped:")
    print(args.outdir / "tflite_input_q.npy", x_q[0, :, :, 0].shape, x_q.min(), x_q.max())
    print(args.outdir / "tflite_conv1_relu.npy", y1.shape, y1.min(), y1.max())
    print(args.outdir / "tflite_conv2_relu.npy", y2.shape, y2.min(), y2.max())
    print(args.outdir / "tflite_conv3_relu.npy", y3.shape, y3.min(), y3.max())
    print(args.outdir / "tflite_dense_i8.npy", y_dense.shape, y_dense.min(), y_dense.max())
    print(args.outdir / "tflite_final_i8.npy", y_final.shape, y_final.min(), y_final.max())


if __name__ == "__main__":
    main()
