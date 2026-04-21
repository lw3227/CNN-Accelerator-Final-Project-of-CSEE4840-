"""Unified CPU-vs-FPGA comparison flow for the web demo."""

from __future__ import annotations

import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

from .case_export import write_inference_case
from .cpu_inference import TFLiteCPUClassifier
from .fpga_service import BoardCPUReferenceService, FPGABoardService
from .preprocess import preprocess_image_bytes_variants
from .preprocess_selection import choose_best_variant


@dataclass
class DemoLabels:
    labels: List[str]

    @classmethod
    def default_digits(cls) -> "DemoLabels":
        return cls(labels=[str(i) for i in range(10)])

    def label_for(self, idx: int) -> str:
        if 0 <= idx < len(self.labels):
            return self.labels[idx]
        return str(idx)


class ComparisonDemoService:
    def __init__(
        self,
        cpu_classifier: TFLiteCPUClassifier,
        board_cpu_service: BoardCPUReferenceService,
        fpga_service: FPGABoardService,
        labels: DemoLabels,
        fabric_mhz: float = 25.0,
    ):
        self.cpu_classifier = cpu_classifier
        self.board_cpu_service = board_cpu_service
        self.fpga_service = fpga_service
        self.labels = labels
        self.fabric_mhz = fabric_mhz

    def _cycles_to_us(self, cycles: int) -> float:
        if self.fabric_mhz <= 0:
            return 0.0
        return float(cycles) / self.fabric_mhz

    def _score_variants(self, variants):
        scored = []
        for variant in variants:
            cpu_result = self.cpu_classifier.predict_int8_image(variant.values)
            scored.append((variant, cpu_result))
        return scored

    def _build_branch_diagnostics(self, scored) -> List[Dict[str, object]]:
        diagnostics = []
        for variant, cpu_result in scored:
            diagnostics.append(
                {
                    "mode": variant.mode,
                    "predicted_class": int(cpu_result.predicted_class),
                    "predicted_label": self.labels.label_for(int(cpu_result.predicted_class)),
                    "margin": float(cpu_result.margin),
                    "top_score": float(cpu_result.top_score),
                }
            )
        return diagnostics

    def _build_fpga_profile(self, fpga_result: Dict[str, object]) -> Dict[str, object]:
        raw_profile = fpga_result.get("profile", {})
        stage_specs = [
            ("L1", "l1_cycles"),
            ("L2 P0", "l2_p0_cycles"),
            ("L2 P1", "l2_p1_cycles"),
            ("L3 P0", "l3_p0_cycles"),
            ("L3 P1", "l3_p1_cycles"),
            ("FC", "fc_cycles"),
            ("Argmax", "argmax_cycles"),
        ]
        stages = []
        for label, key in stage_specs:
            cycles = int(raw_profile.get(key, 0))
            stages.append(
                {
                    "label": label,
                    "cycles": cycles,
                    "time_us": self._cycles_to_us(cycles),
                }
            )
        total_cycles = int(raw_profile.get("total_cycles", 0))
        return {
            "fabric_mhz": self.fabric_mhz,
            "total_cycles": total_cycles,
            "rtl_time_us": self._cycles_to_us(total_cycles),
            "rtl_time_ms": self._cycles_to_us(total_cycles) / 1000.0,
            "stages": stages,
        }

    def _compare_preprocessed_image(self, image_values: List[int], preview_b64: str) -> Dict[str, object]:
        cpu_result = self.cpu_classifier.predict_int8_image(image_values)

        with tempfile.TemporaryDirectory(prefix="cnn_acc_case_") as tmp_dir:
            case_root = Path(tmp_dir) / "gesture_upload_case"
            write_inference_case(case_root, image_values, case_name="gesture_upload", expected_class=-1)
            board_cpu_result = self.board_cpu_service.predict_case_dir(case_root)
            fpga_result = self.fpga_service.predict_case_dir(case_root)

        cpu_ms = float(board_cpu_result["board_cpu_infer_ms"])
        fpga_kernel_ms = float(fpga_result["board_infer_wait_ms"])
        fpga_request_ms = float(fpga_result["request_elapsed_ms"])
        fpga_profile = self._build_fpga_profile(fpga_result)
        speedup = (cpu_ms / fpga_kernel_ms) if fpga_kernel_ms > 0 else None

        cpu_class = int(board_cpu_result["predict_class"])
        fpga_class = int(fpga_result["predict_class"])
        return {
            "predicted_class": fpga_class,
            "predicted_label": self.labels.label_for(fpga_class),
            "cpu_predicted_class": cpu_class,
            "cpu_predicted_label": self.labels.label_for(cpu_class),
            "cpu_time_ms": cpu_ms,
            "fpga_time_ms": fpga_kernel_ms,
            "fpga_rtl_time_ms": fpga_profile["rtl_time_ms"],
            "fpga_rtl_time_us": fpga_profile["rtl_time_us"],
            "fpga_request_time_ms": fpga_request_ms,
            "fpga_board_total_time_ms": float(fpga_result["board_total_ms"]),
            "fpga_board_program_time_ms": float(fpga_result["board_program_ms"]),
            "fpga_board_case_load_time_ms": float(fpga_result["board_case_load_ms"]),
            "speedup": speedup,
            "fpga_status": fpga_result["status"],
            "fpga_error": fpga_result["error"],
            "chart": {
                "labels": ["CPU", "FPGA wait"],
                "values_ms": [cpu_ms, fpga_kernel_ms],
            },
            "fpga_profile": fpga_profile,
            "preprocessed_preview_url": f"data:image/png;base64,{preview_b64}",
        }

    def compare_image_bytes(self, image_bytes: bytes, preferred_mode: str = "auto") -> Dict[str, object]:
        variants = preprocess_image_bytes_variants(image_bytes)
        scored = self._score_variants(variants)

        if preferred_mode != "auto":
            matches = [(variant, cpu_result) for variant, cpu_result in scored if variant.mode == preferred_mode]
            if not matches:
                raise ValueError(f"unknown preprocess mode: {preferred_mode}")
            best_variant, best_cpu_result = matches[0]
        else:
            best_variant, best_cpu_result = choose_best_variant(scored)

        with tempfile.TemporaryDirectory(prefix="cnn_acc_case_") as tmp_dir:
            case_root = Path(tmp_dir) / "gesture_upload_case"
            write_inference_case(case_root, best_variant.values, case_name="gesture_upload", expected_class=-1)
            board_cpu_result = self.board_cpu_service.predict_case_dir(case_root)
            fpga_result = self.fpga_service.predict_case_dir(case_root)

        cpu_ms = float(board_cpu_result["board_cpu_infer_ms"])
        fpga_kernel_ms = float(fpga_result["board_infer_wait_ms"])
        fpga_request_ms = float(fpga_result["request_elapsed_ms"])
        fpga_profile = self._build_fpga_profile(fpga_result)
        speedup = (cpu_ms / fpga_kernel_ms) if fpga_kernel_ms > 0 else None

        cpu_class = int(board_cpu_result["predict_class"])
        fpga_class = int(fpga_result["predict_class"])
        return {
            "predicted_class": fpga_class,
            "predicted_label": self.labels.label_for(fpga_class),
            "cpu_predicted_class": cpu_class,
            "cpu_predicted_label": self.labels.label_for(cpu_class),
            "cpu_time_ms": cpu_ms,
            "fpga_time_ms": fpga_kernel_ms,
            "fpga_rtl_time_ms": fpga_profile["rtl_time_ms"],
            "fpga_rtl_time_us": fpga_profile["rtl_time_us"],
            "fpga_request_time_ms": fpga_request_ms,
            "fpga_board_total_time_ms": float(fpga_result["board_total_ms"]),
            "fpga_board_program_time_ms": float(fpga_result["board_program_ms"]),
            "fpga_board_case_load_time_ms": float(fpga_result["board_case_load_ms"]),
            "speedup": speedup,
            "fpga_status": fpga_result["status"],
            "fpga_error": fpga_result["error"],
            "chart": {
                "labels": ["CPU", "FPGA wait"],
                "values_ms": [cpu_ms, fpga_kernel_ms],
            },
            "fpga_profile": fpga_profile,
            "branch_diagnostics": self._build_branch_diagnostics(scored),
            "preprocessed_preview_url": f"data:image/png;base64,{best_variant.preview_b64}",
            "preprocess_mode": best_variant.mode,
            "cpu_confidence_margin": best_cpu_result.margin,
        }

    def compare_image_path(self, image_path: Path) -> Dict[str, object]:
        image_bytes = Path(image_path).read_bytes()
        return self.compare_image_bytes(image_bytes)
