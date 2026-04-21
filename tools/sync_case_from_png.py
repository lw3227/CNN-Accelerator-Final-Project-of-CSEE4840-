#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from gesture_runtime.cpu_inference import TFLiteCPUClassifier
from gesture_runtime.preprocess import preprocess_image_bytes_variants
from gesture_runtime.preprocess_selection import choose_best_variant


def write_image_txt(path: Path, values):
    path.write_text("".join(f"{int(v)}\n" for v in values), encoding="utf-8")


def update_manifest(manifest_path: Path, image_file: str, predict_class: int):
    lines = manifest_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    out = []
    saw_image = False
    saw_predict = False
    for line in lines:
        if line.startswith("image_file="):
            out.append(f"image_file={image_file}")
            saw_image = True
        elif line.startswith("predict_class="):
            out.append(f"predict_class={predict_class}")
            saw_predict = True
        else:
            out.append(line)
    if not saw_image:
        out.append(f"image_file={image_file}")
    if not saw_predict:
        out.append(f"predict_class={predict_class}")
    manifest_path.write_text("\n".join(out) + "\n", encoding="utf-8")


def choose_variant(classifier, image_path: Path, mode: str, expected_class):
    variants = preprocess_image_bytes_variants(image_path.read_bytes())
    if mode != "auto":
        variants = [v for v in variants if v.mode == mode]
        if not variants:
            raise RuntimeError(f"preprocess mode {mode} not available")

    scored = []
    for variant in variants:
        result = classifier.predict_int8_image(variant.values)
        scored.append((variant, result))

    if expected_class is not None:
        matching = [(v, r) for (v, r) in scored if r.predicted_class == expected_class]
        if matching:
            matching.sort(key=lambda item: item[1].margin, reverse=True)
            return matching[0][0], matching[0][1], scored

    variant, result = choose_best_variant(scored)
    return variant, result, scored


def main():
    parser = argparse.ArgumentParser(description="Regenerate a hardware-aligned case input from a PNG using the current Python preprocessing/model.")
    parser.add_argument("case_root", help="Case directory containing manifest.txt and tb_conv1_in_i8_64x64x1.txt")
    parser.add_argument("image_path", help="Source PNG/JPG")
    parser.add_argument("--model", default=str(REPO_ROOT / "Golden-Module" / "models" / "v1.int8.tflite"))
    parser.add_argument("--mode", choices=["auto", "plain", "crop"], default="auto")
    parser.add_argument("--expected-class", type=int, default=None)
    parser.add_argument("--strict", action="store_true", help="Fail if the chosen variant does not predict expected-class")
    args = parser.parse_args()

    case_root = Path(args.case_root)
    image_path = Path(args.image_path)
    manifest_path = case_root / "manifest.txt"
    image_txt_path = case_root / "tb_conv1_in_i8_64x64x1.txt"

    if not manifest_path.is_file():
        raise SystemExit(f"missing manifest: {manifest_path}")
    if not image_path.is_file():
        raise SystemExit(f"missing image: {image_path}")

    classifier = TFLiteCPUClassifier(Path(args.model))
    variant, result, scored = choose_variant(classifier, image_path, args.mode, args.expected_class)

    if args.strict and args.expected_class is not None and result.predicted_class != args.expected_class:
        print(f"Could not match expected class {args.expected_class} for {image_path.name}.")
        for candidate, candidate_result in scored:
            print(
                f"  mode={candidate.mode} pred={candidate_result.predicted_class} "
                f"margin={candidate_result.margin:.3f} top={candidate_result.top_score:.3f}"
            )
        raise SystemExit(1)

    write_image_txt(image_txt_path, variant.values)
    update_manifest(manifest_path, image_path.name, result.predicted_class)

    print(
        f"synced {case_root.name}: image={image_path.name} mode={variant.mode} "
        f"predicted_class={result.predicted_class} margin={result.margin:.3f}"
    )


if __name__ == "__main__":
    main()
