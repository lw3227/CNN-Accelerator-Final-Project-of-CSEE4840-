#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import subprocess
import sys
import textwrap
from pathlib import Path

from tensorflow.keras import callbacks
from tensorflow.keras.layers import Conv2D, Dense, Flatten, InputLayer, MaxPooling2D
from tensorflow.keras.models import Sequential
from tensorflow.keras.preprocessing.image import ImageDataGenerator


def build_model(num_classes: int = 10) -> Sequential:
    model = Sequential(
        [
            InputLayer(input_shape=(64, 64, 1)),
            Conv2D(filters=4, kernel_size=(3, 3), strides=(1, 1), padding="valid", activation="relu"),
            MaxPooling2D(pool_size=(2, 2)),
            Conv2D(filters=8, kernel_size=(3, 3), strides=(1, 1), padding="valid", activation="relu"),
            MaxPooling2D(pool_size=(2, 2)),
            Conv2D(filters=8, kernel_size=(3, 3), strides=(1, 1), padding="valid", activation="relu"),
            MaxPooling2D(pool_size=(2, 2)),
            Flatten(),
            Dense(units=num_classes, activation="softmax"),
        ]
    )
    model.compile(loss="categorical_crossentropy", optimizer="adam", metrics=["accuracy"])
    return model


def main() -> None:
    parser = argparse.ArgumentParser(description="Retrain the 64x64 grayscale 0-9 sign-language CNN and export INT8 TFLite.")
    parser.add_argument("--dataset", type=Path, required=True, help="Merged dataset root with train/validation/test splits.")
    parser.add_argument("--models-dir", type=Path, default=Path("../models"), help="Model output directory (default: ../models).")
    parser.add_argument("--name", type=str, default="v3_merged", help="Base model name (default: v3_merged).")
    parser.add_argument("--epochs", type=int, default=60, help="Training epochs (default: 60).")
    parser.add_argument("--batch-size", type=int, default=32, help="Batch size (default: 32).")
    parser.add_argument("--rep-per-class", type=int, default=120, help="Representative samples per class for INT8 export.")
    args = parser.parse_args()

    dataset_root = args.dataset.resolve()
    train_folder = dataset_root / "train"
    validation_folder = dataset_root / "validation"
    test_folder = dataset_root / "test"
    if not train_folder.exists():
        raise FileNotFoundError(f"Missing train split: {train_folder}")
    if not validation_folder.exists():
        raise FileNotFoundError(f"Missing validation split: {validation_folder}")
    if not test_folder.exists():
        raise FileNotFoundError(f"Missing test split: {test_folder}")

    train_gen_cfg = ImageDataGenerator(
        rescale=1.0 / 255.0,
        rotation_range=12,
        width_shift_range=0.10,
        height_shift_range=0.10,
        shear_range=0.10,
        zoom_range=0.10,
        horizontal_flip=False,
        vertical_flip=False,
        fill_mode="nearest",
    )
    eval_gen_cfg = ImageDataGenerator(rescale=1.0 / 255.0)

    train_gen = train_gen_cfg.flow_from_directory(
        train_folder,
        target_size=(64, 64),
        color_mode="grayscale",
        batch_size=args.batch_size,
        class_mode="categorical",
        shuffle=True,
    )
    validation_gen = eval_gen_cfg.flow_from_directory(
        validation_folder,
        target_size=(64, 64),
        color_mode="grayscale",
        batch_size=args.batch_size,
        class_mode="categorical",
        shuffle=False,
    )
    test_gen = eval_gen_cfg.flow_from_directory(
        test_folder,
        target_size=(64, 64),
        color_mode="grayscale",
        batch_size=args.batch_size,
        class_mode="categorical",
        shuffle=False,
    )

    expected_mapping = {str(i): i for i in range(10)}
    if train_gen.class_indices != expected_mapping:
        raise ValueError(f"Unexpected class mapping: {train_gen.class_indices}")

    models_dir = args.models_dir.resolve()
    models_dir.mkdir(parents=True, exist_ok=True)
    h5_path = models_dir / f"{args.name}.h5"
    tflite_path = models_dir / f"{args.name}.int8.tflite"

    model = build_model(num_classes=10)
    checkpoint = callbacks.ModelCheckpoint(str(h5_path), monitor="val_accuracy", save_best_only=True, verbose=1)
    early_stop = callbacks.EarlyStopping(monitor="val_accuracy", patience=10, restore_best_weights=True)

    history = model.fit(
        train_gen,
        epochs=args.epochs,
        steps_per_epoch=math.ceil(train_gen.samples / train_gen.batch_size),
        validation_data=validation_gen,
        validation_steps=math.ceil(validation_gen.samples / validation_gen.batch_size),
        callbacks=[checkpoint, early_stop],
        verbose=2,
    )

    test_loss, test_acc = model.evaluate(test_gen, verbose=0)
    print(f"[TEST] loss={test_loss:.4f} acc={test_acc:.4f}")

    export_script = textwrap.dedent(
        """
        import sys
        from pathlib import Path

        import numpy as np
        import tensorflow as tf

        model_path = Path(sys.argv[1])
        rep_dir = Path(sys.argv[2])
        out_path = Path(sys.argv[3])
        per_class_samples = int(sys.argv[4])

        model = tf.keras.models.load_model(str(model_path), compile=False)
        model(np.zeros((1, 64, 64, 1), dtype=np.float32))

        def representative_dataset_gen():
            exts = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
            class_dirs = sorted([d for d in rep_dir.iterdir() if d.is_dir()], key=lambda p: int(p.name))
            picked = []
            for d in class_dirs:
                files = [p for p in sorted(d.rglob('*')) if p.suffix.lower() in exts]
                picked.extend(files[: min(per_class_samples, len(files))])
            if not picked:
                raise FileNotFoundError(f'No representative images found in {rep_dir}')
            for p in picked:
                img = tf.keras.utils.load_img(p, color_mode='grayscale', target_size=(64, 64))
                arr = tf.keras.utils.img_to_array(img).astype(np.float32) / 255.0
                arr = np.expand_dims(arr, axis=0)
                yield [arr]

        serving_fn = tf.function(lambda x: model(x))
        concrete = serving_fn.get_concrete_function(tf.TensorSpec([1, 64, 64, 1], tf.float32))
        converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete], model)
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = representative_dataset_gen
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type = tf.int8
        converter.inference_output_type = tf.int8
        out_path.write_bytes(converter.convert())

        print(f'[OK] wrote {out_path}')
        """
    )
    cmd = [sys.executable, "-c", export_script, str(h5_path), str(train_folder), str(tflite_path), str(args.rep_per_class)]
    subprocess.run(cmd, check=True)

    summary = {
        "name": args.name,
        "dataset": str(dataset_root),
        "train_samples": int(train_gen.samples),
        "validation_samples": int(validation_gen.samples),
        "test_samples": int(test_gen.samples),
        "best_val_accuracy": max(history.history.get("val_accuracy", [0.0])),
        "test_accuracy": float(test_acc),
        "h5_path": str(h5_path),
        "tflite_path": str(tflite_path),
    }
    print(summary)


if __name__ == "__main__":
    main()
