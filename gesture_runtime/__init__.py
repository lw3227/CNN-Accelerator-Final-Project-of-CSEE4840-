"""Host-side helpers for the CNN_ACC gesture accelerator."""

from .network import FeatureMap, ConvLayer, FullyConnectedLayer, GestureNetwork
from .mmio_runtime import (
    ScratchpadLayout,
    PreloadBundle,
    InferenceCase,
    load_preload_bundle,
    load_inference_case,
    build_mmio_image,
    build_mmio_register_file,
)
