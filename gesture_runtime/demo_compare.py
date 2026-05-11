"""Web demo 的 CPU-vs-FPGA 统一对比流程。

`ComparisonDemoService` 是 `/api/infer` 背后的主协调器。它接收上传图片的
原始 bytes，生成多个预处理分支，选择更可靠的分支，导出硬件对齐的 case
目录，然后让 HPS CPU reference 和 FPGA accelerator 处理同一个 case，最后
返回浏览器需要的预测、计时、profile 计数器和置信度诊断信息。
"""

from __future__ import annotations

import math
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
    """把数字类别转换成前端显示用 label 的小工具。"""

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
        """用 FPGA fabric 频率把 RTL cycle counter 转成微秒。"""
        if self.fabric_mhz <= 0:
            return 0.0
        return float(cycles) / self.fabric_mhz

    def _score_variants(self, variants):
        """用 host 端 TFLite 模型给每个预处理分支打分。"""
        scored = []
        for variant in variants:
            cpu_result = self.cpu_classifier.predict_int8_image(variant.values)
            scored.append((variant, cpu_result))
        return scored

    def _softmax_probabilities(self, scores: List[float]) -> List[float]:
        """把 CPU 原始分数稳定地转换成前端显示用概率。"""
        if not scores:
            return []
        max_score = max(scores)
        exp_scores = [math.exp(score - max_score) for score in scores]
        total = sum(exp_scores)
        if total <= 0:
            return [0.0 for _ in scores]
        return [value / total for value in exp_scores]

    def _build_cpu_score_report(self, cpu_result) -> Dict[str, object]:
        """构造前端诊断面板需要的逐类别置信度信息。"""
        probabilities = self._softmax_probabilities(cpu_result.scores)
        channels = []
        for idx, (score, probability) in enumerate(zip(cpu_result.scores, probabilities)):
            channels.append(
                {
                    "class_id": idx,
                    "label": self.labels.label_for(idx),
                    "raw_score": float(score),
                    "probability": float(probability),
                    "probability_pct": float(probability * 100.0),
                }
            )

        top_channels = sorted(channels, key=lambda row: row["raw_score"], reverse=True)[:3]
        note = ""
        if len(top_channels) >= 2 and abs(top_channels[0]["raw_score"] - top_channels[1]["raw_score"]) < 1e-6:
            note = "Top classes are tied, so this sample is currently low-confidence."
        elif float(cpu_result.margin) < 5.0:
            note = "Top classes are close, so this sample is currently low-confidence."

        return {
            "predicted_class": int(cpu_result.predicted_class),
            "predicted_label": self.labels.label_for(int(cpu_result.predicted_class)),
            "top_score": float(cpu_result.top_score),
            "margin": float(cpu_result.margin),
            "confidence": float(top_channels[0]["probability"]) if top_channels else 0.0,
            "confidence_pct": float(top_channels[0]["probability_pct"]) if top_channels else 0.0,
            "top_channels": top_channels,
            "channels": channels,
            "note": note,
        }

    def _build_branch_diagnostics(self, scored) -> List[Dict[str, object]]:
        """暴露每个预处理分支在最终选择前的得分情况。"""
        diagnostics = []
        for variant, cpu_result in scored:
            top_channels = self._build_cpu_score_report(cpu_result)["top_channels"]
            diagnostics.append(
                {
                    "mode": variant.mode,
                    "predicted_class": int(cpu_result.predicted_class),
                    "predicted_label": self.labels.label_for(int(cpu_result.predicted_class)),
                    "margin": float(cpu_result.margin),
                    "top_score": float(cpu_result.top_score),
                    "top_channels": top_channels,
                }
            )
        return diagnostics

    def _build_fpga_profile(self, fpga_result: Dict[str, object]) -> Dict[str, object]:
        """把 FPGA 原始 cycle counter 转成带标签的 timing rows。"""
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
        """对一个已经选好的 INT8 图片同时跑 HPS CPU 和 FPGA。"""
        cpu_result = self.cpu_classifier.predict_int8_image(image_values)

        # 板端 C 工具读取的是目录，不是 Python 对象。这里创建临时 case
        # 目录并使用硬件 testbench 的文件名，这样上传图片和固定测试样例
        # 可以复用同一套 C loader。
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
        """从上传图片 bytes 开始，跑完整流程并返回前端 JSON。"""
        variants = preprocess_image_bytes_variants(image_bytes)
        scored = self._score_variants(variants)

        # auto 模式让 CPU 模型在 literal resize 和 foreground crop 之间选择。
        # 手动模式用于演示不同预处理方式如何影响结果。
        if preferred_mode != "auto":
            matches = [(variant, cpu_result) for variant, cpu_result in scored if variant.mode == preferred_mode]
            if not matches:
                raise ValueError(f"unknown preprocess mode: {preferred_mode}")
            best_variant, best_cpu_result = matches[0]
        else:
            best_variant, best_cpu_result = choose_best_variant(scored)

        cpu_score_report = self._build_cpu_score_report(best_cpu_result)

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
            "cpu_score_report": cpu_score_report,
        }

    def compare_image_path(self, image_path: Path) -> Dict[str, object]:
        image_bytes = Path(image_path).read_bytes()
        return self.compare_image_bytes(image_bytes)
