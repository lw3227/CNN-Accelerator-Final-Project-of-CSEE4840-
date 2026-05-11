#!/usr/bin/env python3
"""Flask app for the upload-first CPU-vs-FPGA comparison demo.

This file is the browser-facing entry point of the web-to-board flow. The web
page sends an uploaded image to `/api/infer`; the route preprocesses the image,
exports a temporary hardware case, asks the DE1-SoC board to run both the HPS
CPU reference and the FPGA accelerator, and returns a JSON object that the UI
can render as labels, timing numbers, profile counters, and diagnostics.
"""

from __future__ import annotations

import os
import sys
import json
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from flask import Flask, jsonify, render_template, request

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from web_demo.config import load_demo_config
from gesture_runtime.cpu_inference import TFLiteCPUClassifier
from gesture_runtime.demo_compare import ComparisonDemoService, DemoLabels
from gesture_runtime.fpga_service import BoardCPUReferenceService, FPGABoardService, FPGAServiceConfig
from gesture_runtime.ssh_transport import SshBoardTransport


def build_service() -> ComparisonDemoService:
    """Construct the long-lived service graph used by all request handlers.

    The Flask routes stay intentionally thin: configuration loading, TFLite CPU
    setup, SSH transport creation, and FPGA/HPS service wiring are centralized
    here so each HTTP endpoint only has to validate inputs and format outputs.
    """
    cfg = load_demo_config()
    labels = DemoLabels(cfg.labels) if cfg.labels else DemoLabels.default_digits()
    cpu_classifier = TFLiteCPUClassifier(cfg.cpu_model)
    # All board access is done through SSH/SCP because the web server runs on
    # the host laptop/desktop while the accelerator and C commands run on HPS
    # Linux inside the DE1-SoC board.
    transport = SshBoardTransport(
        host=cfg.board_host,
        user=cfg.board_user,
        port=cfg.board_port,
        identity_file=cfg.ssh_key,
        known_hosts_file=cfg.ssh_known_hosts,
        bind_address=cfg.ssh_bind_address,
    )
    fpga_service = FPGABoardService(
        transport=transport,
        config=FPGAServiceConfig(
            remote_repo=cfg.remote_repo,
            csr_base=cfg.csr_base,
            remote_preload_root=cfg.remote_preload_root,
            remote_reference_case_root=cfg.remote_reference_case_root,
        ),
    )
    board_cpu_service = BoardCPUReferenceService(
        transport=transport,
        config=FPGAServiceConfig(
            remote_repo=cfg.remote_repo,
            csr_base=cfg.csr_base,
            remote_preload_root=cfg.remote_preload_root,
            remote_reference_case_root=cfg.remote_reference_case_root,
        ),
    )
    return ComparisonDemoService(
        cpu_classifier=cpu_classifier,
        board_cpu_service=board_cpu_service,
        fpga_service=fpga_service,
        labels=labels,
        fabric_mhz=cfg.fabric_mhz,
    )


app = Flask(__name__, template_folder="templates", static_folder="static")
SERVICE: ComparisonDemoService | None = None
SAMPLE_IMAGE_DIR = REPO_ROOT / "Golden-Module" / "matlab"
FEEDBACK_DIR = REPO_ROOT / "web_demo" / "feedback_samples"


def get_service() -> ComparisonDemoService:
    """Lazily create the service so importing this module is cheap and safe."""
    global SERVICE
    if SERVICE is None:
        SERVICE = build_service()
    return SERVICE


@app.route("/")
def index():
    return render_template("index.html")


@app.get("/api/health")
def health():
    """Report configuration visible to the browser without touching the FPGA."""
    cfg = load_demo_config()
    return jsonify(
        {
            "ok": True,
            "board_host": cfg.board_host,
            "board_user": cfg.board_user,
            "board_port": cfg.board_port,
            "ssh_bind_address": cfg.ssh_bind_address,
            "remote_repo": cfg.remote_repo,
            "remote_preload_root": cfg.remote_preload_root,
            "remote_reference_case_root": cfg.remote_reference_case_root,
            "cpu_model": str(cfg.cpu_model),
            "fabric_mhz": cfg.fabric_mhz,
            "labels": cfg.labels,
            "model_lane": cfg.model_lane,
            "model_warning": cfg.model_warning,
            "task_semantics": "gesture-classification",
            "dataset_name": cfg.dataset_name,
            "dataset_source_hint": cfg.dataset_source_hint,
        }
    )


@app.post("/api/infer")
def infer():
    """Handle one uploaded image and return CPU-vs-FPGA comparison results."""
    uploaded = request.files.get("image")
    if uploaded is None or not uploaded.filename:
        return jsonify({"error": "image upload is required"}), 400

    preprocess_mode = request.form.get("preprocess_mode", "auto").strip() or "auto"
    try:
        cfg = load_demo_config()
        # The service owns the end-to-end path: preprocessing variants,
        # temporary case export, board transfer, C command execution, and result
        # parsing. The route only passes raw bytes and the requested mode.
        result = get_service().compare_image_bytes(uploaded.read(), preferred_mode=preprocess_mode)
    except Exception as exc:  # pragma: no cover - integration path
        return jsonify({"error": str(exc)}), 500
    result["model_lane"] = cfg.model_lane
    result["model_warning"] = cfg.model_warning
    result["task_semantics"] = "gesture-classification"
    result["dataset_name"] = cfg.dataset_name
    result["dataset_source_hint"] = cfg.dataset_source_hint
    return jsonify(result)


@app.post("/api/feedback")
def save_feedback():
    """Save a misprediction sample for later retraining/debugging."""
    uploaded = request.files.get("image")
    corrected_label = request.form.get("corrected_label", "").strip()
    predicted_label = request.form.get("predicted_label", "").strip()
    preprocess_mode = request.form.get("preprocess_mode", "").strip()
    note = request.form.get("note", "").strip()

    if uploaded is None or not uploaded.filename:
        return jsonify({"error": "image upload is required"}), 400
    if corrected_label not in {str(i) for i in range(10)}:
        return jsonify({"error": "corrected_label must be one of 0..9"}), 400

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    sample_id = f"{stamp}_{uuid4().hex[:8]}"
    sample_dir = FEEDBACK_DIR / sample_id
    sample_dir.mkdir(parents=True, exist_ok=True)

    filename = Path(uploaded.filename).name or "capture.png"
    raw_ext = Path(filename).suffix or ".png"
    raw_path = sample_dir / f"input{raw_ext}"
    uploaded.save(raw_path)

    metadata = {
        "id": sample_id,
        "captured_at": datetime.now().isoformat(),
        "source_filename": filename,
        "raw_image": str(raw_path.relative_to(REPO_ROOT)),
        "corrected_label": corrected_label,
        "predicted_label": predicted_label,
        "preprocess_mode": preprocess_mode,
        "note": note,
    }
    metadata_path = sample_dir / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    return jsonify(
        {
            "ok": True,
            "sample_id": sample_id,
            "saved_dir": str(sample_dir.relative_to(REPO_ROOT)),
            "corrected_label": corrected_label,
        }
    )


@app.get("/api/sample-suite")
def sample_suite():
    """Run the built-in digit sample images through the same board path."""
    try:
        cfg = load_demo_config()
        sample_paths = sorted(SAMPLE_IMAGE_DIR.glob("digit_*_test.png"))
        if not sample_paths:
            return jsonify({"error": f"no sample images found under {SAMPLE_IMAGE_DIR}"}), 500

        rows = []
        passed = 0
        service = get_service()
        for sample_path in sample_paths:
            stem = sample_path.stem
            expected = int(stem.split("_")[1])
            result = service.compare_image_path(sample_path)
            cpu_ok = int(result["cpu_predicted_class"]) == expected
            fpga_ok = int(result["predicted_class"]) == expected
            both_ok = cpu_ok and fpga_ok
            if both_ok:
                passed += 1
            rows.append(
                {
                    "case": stem,
                    "expected_class": expected,
                    "cpu_predicted_class": int(result["cpu_predicted_class"]),
                    "fpga_predicted_class": int(result["predicted_class"]),
                    "cpu_time_ms": result["cpu_time_ms"],
                    "fpga_time_ms": result["fpga_time_ms"],
                    "preprocess_mode": result.get("preprocess_mode", ""),
                    "cpu_confidence_margin": result.get("cpu_confidence_margin"),
                    "cpu_ok": cpu_ok,
                    "fpga_ok": fpga_ok,
                    "pass": both_ok,
                }
            )

        return jsonify(
            {
                "ok": True,
                "dataset_name": cfg.dataset_name,
                "model_lane": cfg.model_lane,
                "task_semantics": "gesture-classification",
                "total": len(rows),
                "passed": passed,
                "rows": rows,
            }
        )
    except Exception as exc:  # pragma: no cover - integration path
        return jsonify({"error": str(exc)}), 500


if __name__ == "__main__":
    cfg = load_demo_config()
    app.run(host=cfg.local_host, port=cfg.local_port, debug=cfg.debug)
