#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import scipy.io as sio
import tensorflow as tf


def _to_cell(items: list[object]) -> np.ndarray:
    arr = np.empty((len(items), 1), dtype=object)
    for i, v in enumerate(items):
        arr[i, 0] = v
    return arr


def collect_param_tensor_indices(interpreter: tf.lite.Interpreter) -> list[int]:
    details = interpreter.get_tensor_details()
    all_indices = {d["index"] for d in details}
    model_inputs = {d["index"] for d in interpreter.get_input_details()}

    op_inputs: set[int] = set()
    op_outputs: set[int] = set()
    for op in interpreter._get_ops_details():
        op_inputs.update(i for i in op["inputs"] if i >= 0)
        op_outputs.update(i for i in op["outputs"] if i >= 0)

    candidates = (op_inputs - op_outputs - model_inputs) & all_indices
    return sorted(candidates)


def collect_graph_tensor_indices(interpreter: tf.lite.Interpreter) -> list[int]:
    details = interpreter.get_tensor_details()
    all_indices = {d["index"] for d in details}
    model_inputs = {d["index"] for d in interpreter.get_input_details()}
    model_outputs = {d["index"] for d in interpreter.get_output_details()}

    op_inputs: set[int] = set()
    op_outputs: set[int] = set()
    for op in interpreter._get_ops_details():
        op_inputs.update(i for i in op["inputs"] if i >= 0)
        op_outputs.update(i for i in op["outputs"] if i >= 0)

    graph_indices = (op_inputs | op_outputs | model_inputs | model_outputs) & all_indices
    return sorted(graph_indices)


def collect_activation_tensor_indices(interpreter: tf.lite.Interpreter) -> list[int]:
    details = interpreter.get_tensor_details()
    all_indices = {d["index"] for d in details}

    op_outputs: set[int] = set()
    for op in interpreter._get_ops_details():
        op_outputs.update(i for i in op["outputs"] if i >= 0)

    return sorted(op_outputs & all_indices)


def export_params_to_mat(model_path: Path, out_path: Path) -> None:
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()

    tensor_details = {d["index"]: d for d in interpreter.get_tensor_details()}
    op_details = interpreter._get_ops_details()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    param_indices = collect_param_tensor_indices(interpreter)
    graph_indices = collect_graph_tensor_indices(interpreter)
    activation_indices = collect_activation_tensor_indices(interpreter)

    # Parameter tensors (weights/bias/const tensors consumed by ops)
    names: list[str] = []
    tensor_indices: list[int] = []
    dtypes: list[str] = []
    shapes: list[np.ndarray] = []
    shape_signatures: list[np.ndarray] = []
    quantized_dims: list[int] = []
    values: list[np.ndarray] = []
    scales: list[np.ndarray] = []
    zero_points: list[np.ndarray] = []

    for idx in param_indices:
        d = tensor_details[idx]
        q = d["quantization_parameters"]
        v = interpreter.get_tensor(idx)

        names.append(d["name"])
        tensor_indices.append(int(idx))
        dtypes.append(str(v.dtype))
        shapes.append(np.asarray(d["shape"], dtype=np.int64))
        shape_signatures.append(np.asarray(d["shape_signature"], dtype=np.int64))
        quantized_dims.append(int(q["quantized_dimension"]))
        values.append(v)
        scales.append(np.asarray(q["scales"], dtype=np.float32))
        zero_points.append(np.asarray(q["zero_points"], dtype=np.int32))

    # Activation tensors (op outputs)
    act_names: list[str] = []
    act_indices: list[int] = []
    act_dtypes: list[str] = []
    act_shapes: list[np.ndarray] = []
    act_shape_signatures: list[np.ndarray] = []
    act_quantized_dims: list[int] = []
    act_scales: list[np.ndarray] = []
    act_zero_points: list[np.ndarray] = []

    for idx in activation_indices:
        d = tensor_details[idx]
        q = d["quantization_parameters"]

        act_names.append(d["name"])
        act_indices.append(int(idx))
        act_dtypes.append(str(np.dtype(d["dtype"])))
        act_shapes.append(np.asarray(d["shape"], dtype=np.int64))
        act_shape_signatures.append(np.asarray(d["shape_signature"], dtype=np.int64))
        act_quantized_dims.append(int(q["quantized_dimension"]))
        act_scales.append(np.asarray(q["scales"], dtype=np.float32))
        act_zero_points.append(np.asarray(q["zero_points"], dtype=np.int32))

    # Model IO tensor specs
    input_names: list[str] = []
    input_indices: list[int] = []
    input_dtypes: list[str] = []
    input_shapes: list[np.ndarray] = []
    input_shape_signatures: list[np.ndarray] = []
    input_quantized_dims: list[int] = []
    input_scales: list[np.ndarray] = []
    input_zero_points: list[np.ndarray] = []

    for d in input_details:
        q = d["quantization_parameters"]
        input_names.append(d["name"])
        input_indices.append(int(d["index"]))
        input_dtypes.append(str(np.dtype(d["dtype"])))
        input_shapes.append(np.asarray(d["shape"], dtype=np.int64))
        input_shape_signatures.append(np.asarray(d["shape_signature"], dtype=np.int64))
        input_quantized_dims.append(int(q["quantized_dimension"]))
        input_scales.append(np.asarray(q["scales"], dtype=np.float32))
        input_zero_points.append(np.asarray(q["zero_points"], dtype=np.int32))

    output_names: list[str] = []
    output_indices: list[int] = []
    output_dtypes: list[str] = []
    output_shapes: list[np.ndarray] = []
    output_shape_signatures: list[np.ndarray] = []
    output_quantized_dims: list[int] = []
    output_scales: list[np.ndarray] = []
    output_zero_points: list[np.ndarray] = []

    for d in output_details:
        q = d["quantization_parameters"]
        output_names.append(d["name"])
        output_indices.append(int(d["index"]))
        output_dtypes.append(str(np.dtype(d["dtype"])))
        output_shapes.append(np.asarray(d["shape"], dtype=np.int64))
        output_shape_signatures.append(np.asarray(d["shape_signature"], dtype=np.int64))
        output_quantized_dims.append(int(q["quantized_dimension"]))
        output_scales.append(np.asarray(q["scales"], dtype=np.float32))
        output_zero_points.append(np.asarray(q["zero_points"], dtype=np.int32))

    # Operator graph connectivity
    op_indices: list[int] = []
    op_names: list[str] = []
    op_inputs: list[np.ndarray] = []
    op_outputs: list[np.ndarray] = []

    for op in op_details:
        op_indices.append(int(op["index"]))
        op_names.append(op["op_name"])
        op_inputs.append(np.asarray(op["inputs"], dtype=np.int32))
        op_outputs.append(np.asarray(op["outputs"], dtype=np.int32))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sio.savemat(
        str(out_path),
        {
            "model_path": str(model_path),
            "num_graph_tensors": np.int32(len(graph_indices)),
            "graph_tensor_indices": np.asarray(graph_indices, dtype=np.int32).reshape(-1, 1),
            "num_params": np.int32(len(param_indices)),
            "names": _to_cell(names),
            "tensor_indices": np.asarray(tensor_indices, dtype=np.int32).reshape(-1, 1),
            "dtypes": _to_cell(dtypes),
            "shapes": _to_cell(shapes),
            "shape_signatures": _to_cell(shape_signatures),
            "quantized_dimensions": np.asarray(quantized_dims, dtype=np.int32).reshape(-1, 1),
            "values": _to_cell(values),
            "scales": _to_cell(scales),
            "zero_points": _to_cell(zero_points),
            "num_inputs": np.int32(len(input_details)),
            "input_names": _to_cell(input_names),
            "input_indices": np.asarray(input_indices, dtype=np.int32).reshape(-1, 1),
            "input_dtypes": _to_cell(input_dtypes),
            "input_shapes": _to_cell(input_shapes),
            "input_shape_signatures": _to_cell(input_shape_signatures),
            "input_quantized_dimensions": np.asarray(input_quantized_dims, dtype=np.int32).reshape(-1, 1),
            "input_scales": _to_cell(input_scales),
            "input_zero_points": _to_cell(input_zero_points),
            "num_outputs": np.int32(len(output_details)),
            "output_names": _to_cell(output_names),
            "output_indices": np.asarray(output_indices, dtype=np.int32).reshape(-1, 1),
            "output_dtypes": _to_cell(output_dtypes),
            "output_shapes": _to_cell(output_shapes),
            "output_shape_signatures": _to_cell(output_shape_signatures),
            "output_quantized_dimensions": np.asarray(output_quantized_dims, dtype=np.int32).reshape(-1, 1),
            "output_scales": _to_cell(output_scales),
            "output_zero_points": _to_cell(output_zero_points),
            "num_activations": np.int32(len(activation_indices)),
            "activation_names": _to_cell(act_names),
            "activation_indices": np.asarray(act_indices, dtype=np.int32).reshape(-1, 1),
            "activation_dtypes": _to_cell(act_dtypes),
            "activation_shapes": _to_cell(act_shapes),
            "activation_shape_signatures": _to_cell(act_shape_signatures),
            "activation_quantized_dimensions": np.asarray(act_quantized_dims, dtype=np.int32).reshape(-1, 1),
            "activation_scales": _to_cell(act_scales),
            "activation_zero_points": _to_cell(act_zero_points),
            "num_ops": np.int32(len(op_details)),
            "op_indices": np.asarray(op_indices, dtype=np.int32).reshape(-1, 1),
            "op_names": _to_cell(op_names),
            "op_inputs": _to_cell(op_inputs),
            "op_outputs": _to_cell(op_outputs),
        },
        do_compression=True,
    )

    print(f"[OK] Exported {len(param_indices)} parameter tensors")
    print(f"[OK] Exported {len(input_details)} input tensor specs")
    print(f"[OK] Exported {len(output_details)} output tensor specs")
    print(f"[OK] Exported {len(activation_indices)} activation tensor specs")
    print(f"[OK] Exported {len(op_details)} operator nodes")
    print(f"[OK] Saved: {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export int8 TFLite parameter tensors to a MATLAB .mat file."
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("models/v2.int8.tflite"),
        help="Path to .tflite model",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("models/v2.int8.params.mat"),
        help="Output .mat path",
    )
    args = parser.parse_args()

    if not args.model.exists():
        raise FileNotFoundError(f"Model not found: {args.model}")

    export_params_to_mat(args.model.resolve(), args.out.resolve())


if __name__ == "__main__":
    main()
