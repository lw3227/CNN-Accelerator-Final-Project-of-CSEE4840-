#!/usr/bin/env python3

import argparse
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REMOTE_REPO = "/root/cnn_acc_hps"
PRELOAD_ROOT = REPO_ROOT / "Golden-Module" / "matlab" / "hardware_aligned" / "debug" / "sram_preload"
CASE_ROOT = REPO_ROOT / "Golden-Module" / "matlab" / "hardware_aligned" / "debug" / "txt_cases"


def run_local(args):
    completed = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="ignore")
    if completed.returncode != 0:
        raise RuntimeError(
            "command failed\n"
            f"command: {' '.join(str(x) for x in args)}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )
    return completed.stdout


def serial_exec(port, timeout_s, command):
    return run_local(
        [
            sys.executable,
            str(REPO_ROOT / "tools" / "hps_serial_exec.py"),
            "--port",
            port,
            "--timeout",
            str(timeout_s),
            command,
        ]
    )


def serial_put(port, local_path, remote_path, decode_timeout_s=180.0):
    return run_local(
        [
            sys.executable,
            str(REPO_ROOT / "tools" / "hps_serial_put.py"),
            "--port",
            port,
            "--decode-timeout",
            str(decode_timeout_s),
            str(local_path),
            remote_path,
        ]
    )


def bundle_cases(case_names):
    tmp_dir = Path(tempfile.mkdtemp(prefix="digit_suite_"))
    bundle = tmp_dir / "digit_suite_bundle.tar.gz"
    with tarfile.open(bundle, "w:gz") as tf:
        for case_name in case_names:
            tf.add(PRELOAD_ROOT / case_name, arcname=f"Golden-Module/matlab/hardware_aligned/debug/sram_preload/{case_name}")
            tf.add(CASE_ROOT / case_name, arcname=f"Golden-Module/matlab/hardware_aligned/debug/txt_cases/{case_name}")
    return bundle


def parse_result(output):
    expected = re.search(r"expected_class=(\d+)", output)
    predicted = re.search(r"predict_class=(\d+)", output)
    status = re.search(r"status=0x([0-9a-fA-F]+)", output)
    error = re.search(r"error=0x([0-9a-fA-F]+)", output)
    return {
        "expected": int(expected.group(1)) if expected else None,
        "predicted": int(predicted.group(1)) if predicted else None,
        "status": status.group(1).lower() if status else None,
        "error": error.group(1).lower() if error else None,
    }


def read_case_manifest_label(case_name):
    manifest_path = CASE_ROOT / case_name / "manifest.txt"
    if not manifest_path.is_file():
        return None
    for line in manifest_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if line.startswith("predict_class="):
            try:
                return int(line.split("=", 1)[1].strip())
            except ValueError:
                return None
    return None


def parse_case_name_label(case_name):
    match = re.fullmatch(r"digit_(\d+)_test", case_name)
    return int(match.group(1)) if match else None


def main():
    parser = argparse.ArgumentParser(description="Upload and run digit_0_test..digit_9_test on DE1-SoC over serial")
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--csr-base", default="0xff200000")
    parser.add_argument("--remote-repo", default=DEFAULT_REMOTE_REPO)
    parser.add_argument("--skip-upload", action="store_true", help="assume all digit_* cases are already on the board")
    parser.add_argument("--skip-build", action="store_true", help="skip remote make -C tools")
    parser.add_argument("--timeout", type=float, default=40.0)
    args = parser.parse_args()

    case_names = [f"digit_{i}_test" for i in range(10)]

    if not args.skip_upload:
        bundle = bundle_cases(case_names)
        try:
            remote_bundle = "/root/digit_suite_bundle.tar.gz"
            print(f"Uploading {bundle.name} to board...")
            serial_put(args.port, bundle, remote_bundle)
            print("Extracting digit cases on board...")
            serial_exec(
                args.port,
                120.0,
                f"cd '{args.remote_repo}' && tar -xzf '{remote_bundle}' && rm -f '{remote_bundle}'",
            )
        finally:
            bundle.unlink(missing_ok=True)
            bundle.parent.rmdir()

    if not args.skip_build:
        print("Building HPS tools on board...")
        serial_exec(args.port, 120.0, f"cd '{args.remote_repo}/tools' && make")

    manifest_mismatches = []
    local_labels = {}
    for case_name in case_names:
        local_label = read_case_manifest_label(case_name)
        local_labels[case_name] = local_label
        case_name_label = parse_case_name_label(case_name)
        if (
            local_label is not None
            and case_name_label is not None
            and local_label != case_name_label
        ):
            manifest_mismatches.append((case_name, case_name_label, local_label))

    if manifest_mismatches:
        print("Warning: case directory names do not match manifest labels:")
        for case_name, name_label, manifest_label in manifest_mismatches:
            print(
                f"  {case_name}: directory implies {name_label}, "
                f"but manifest says {manifest_label}"
            )
        print()

    print()
    print("Case           Name  Exp  Pred  Status  Error  Result")
    print("-------------  ----  ---  ----  ------  -----  ------")

    failures = 0
    for case_name in case_names:
        command = (
            f"cd '{args.remote_repo}' && "
            f"./tools/hps_mmio_infer {args.csr_base} "
            f"'Golden-Module/matlab/hardware_aligned/debug/sram_preload/{case_name}' "
            f"'Golden-Module/matlab/hardware_aligned/debug/txt_cases/{case_name}'"
        )
        output = serial_exec(args.port, args.timeout, command)
        parsed = parse_result(output)
        ok = (
            parsed["expected"] is not None
            and parsed["predicted"] is not None
            and parsed["expected"] == parsed["predicted"]
            and parsed["error"] == "0000"
        )
        if not ok:
            failures += 1
        print(
            f"{case_name:<13}  "
            f"{str(local_labels[case_name]):>4}  "
            f"{str(parsed['expected']):>3}  "
            f"{str(parsed['predicted']):>4}  "
            f"{str(parsed['status']):>6}  "
            f"{str(parsed['error']):>5}  "
            f"{'PASS' if ok else 'FAIL'}"
        )

    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
