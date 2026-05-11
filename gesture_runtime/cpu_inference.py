"""CPU-side TFLite inference helpers for the web comparison demo.

The FPGA result is easier to explain when the browser also shows a host-side
model score. This module loads the exported INT8 TFLite model, adapts the
preprocessed INT8 image into the interpreter's expected input dtype, and returns
the class scores used for confidence and preprocessing-mode selection.
"""

from dataclasses import dataclass
from pathlib import Path
from time import perf_counter
from typing import List, Optional


def _load_interpreter(model_path: Path):
    """Load either the small tflite-runtime package or full TensorFlow."""
    try:
        from tflite_runtime.interpreter import Interpreter  # type: ignore
    except ImportError:
        try:
            import tensorflow as tf  # type: ignore

            Interpreter = tf.lite.Interpreter
        except ImportError as exc:  # pragma: no cover - optional dependency
            raise RuntimeError(
                "A TFLite interpreter is required. Install tflite-runtime or tensorflow."
            ) from exc

    return Interpreter(model_path=str(model_path))


@dataclass
class CPUInferenceResult:
    """Result bundle returned by the host-side classifier."""

    predicted_class: int
    elapsed_ms: float
    scores: List[float]
    top_score: float
    margin: float


class TFLiteCPUClassifier:
    """Thin wrapper around a TFLite interpreter for 64x64 INT8 images."""

    def __init__(self, model_path: Path):
        self.model_path = Path(model_path)
        self.interpreter = _load_interpreter(self.model_path)
        self.interpreter.allocate_tensors()
        self.input_details = self.interpreter.get_input_details()[0]
        self.output_details = self.interpreter.get_output_details()[0]

        import numpy as np

        self.np = np

    def _prepare_input(self, image_values: List[int]):
        """Convert RTL-style signed INT8 pixels into the model input dtype."""
        np = self.np
        input_shape = self.input_details["shape"]
        input_dtype = self.input_details["dtype"]
        quant = self.input_details.get("quantization", (0.0, 0))

        arr = np.array(image_values, dtype=np.int16).reshape((1, 64, 64, 1))

        if input_dtype == np.int8:
            return arr.astype(np.int8)
        if input_dtype == np.uint8:
            return (arr + 128).astype(np.uint8)
        if input_dtype in (np.float32, np.float64):
            return ((arr.astype(np.float32) + 128.0) / 255.0).astype(input_dtype)

        scale, zero_point = quant
        if scale:
            return ((arr.astype(np.float32) / scale) + zero_point).astype(input_dtype)
        return arr.astype(input_dtype)

    def predict_int8_image(self, image_values: List[int]) -> CPUInferenceResult:
        """Run one inference and summarize top score plus confidence margin."""
        np = self.np
        input_tensor = self._prepare_input(image_values)

        started = perf_counter()
        self.interpreter.set_tensor(self.input_details["index"], input_tensor)
        self.interpreter.invoke()
        output = self.interpreter.get_tensor(self.output_details["index"])
        elapsed_ms = (perf_counter() - started) * 1000.0

        scores = np.array(output).reshape(-1).astype(np.float32).tolist()
        predicted_class = int(np.argmax(scores))
        ordered = sorted(scores, reverse=True)
        top_score = float(ordered[0]) if ordered else 0.0
        second_score = float(ordered[1]) if len(ordered) > 1 else float("-inf")
        margin = top_score - second_score if ordered else 0.0
        return CPUInferenceResult(
            predicted_class=predicted_class,
            elapsed_ms=elapsed_ms,
            scores=scores,
            top_score=top_score,
            margin=margin,
        )
