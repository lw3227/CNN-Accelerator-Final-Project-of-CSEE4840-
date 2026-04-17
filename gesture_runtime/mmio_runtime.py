"""Driver-like MMIO transaction planning for cnn_mmio_interface."""

from .network import load_manifest


def _load_i32_words(path):
    with path.open("r", encoding="utf-8") as fp:
        return [int(line.strip()) for line in fp if line.strip()]


def _load_packed_i8_words(path):
    values = _load_i32_words(path)
    if len(values) % 4 != 0:
        raise ValueError("{} does not contain groups of 4 bytes".format(path))
    words = []
    for idx in range(0, len(values), 4):
        b0 = values[idx + 0] & 0xFF
        b1 = values[idx + 1] & 0xFF
        b2 = values[idx + 2] & 0xFF
        b3 = values[idx + 3] & 0xFF
        words.append(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
    return words


class PreloadBundle(object):
    def __init__(self, conv_cfg_words, conv_wt_words, fc_bias_words, fcw_words):
        self.conv_cfg_words = conv_cfg_words
        self.conv_wt_words = conv_wt_words
        self.fc_bias_words = fc_bias_words
        self.fcw_words = fcw_words


class InferenceCase(object):
    def __init__(self, case_name, image_words, expected_class, manifest):
        self.case_name = case_name
        self.image_words = image_words
        self.expected_class = expected_class
        self.manifest = manifest


class ScratchpadLayout(object):
    def __init__(
        self,
        conv_cfg_base_hw=0,
        conv_cfg_words=45,
        conv_wt_base_hw=90,
        conv_wt_words=225,
        fc_bias_base_hw=540,
        fc_bias_words=10,
        fcw_base_hw=560,
        fcw_words=864,
        image_base_hw=2288,
        image_words=1024,
    ):
        self.conv_cfg_base_hw = conv_cfg_base_hw
        self.conv_cfg_words = conv_cfg_words
        self.conv_wt_base_hw = conv_wt_base_hw
        self.conv_wt_words = conv_wt_words
        self.fc_bias_base_hw = fc_bias_base_hw
        self.fc_bias_words = fc_bias_words
        self.fcw_base_hw = fcw_base_hw
        self.fcw_words = fcw_words
        self.image_base_hw = image_base_hw
        self.image_words = image_words

    def ranges(self):
        return {
            "conv_cfg": (self.conv_cfg_base_hw, self.conv_cfg_base_hw + self.conv_cfg_words * 2),
            "conv_wt": (self.conv_wt_base_hw, self.conv_wt_base_hw + self.conv_wt_words * 2),
            "fc_bias": (self.fc_bias_base_hw, self.fc_bias_base_hw + self.fc_bias_words * 2),
            "fcw": (self.fcw_base_hw, self.fcw_base_hw + self.fcw_words * 2),
            "image": (self.image_base_hw, self.image_base_hw + self.image_words * 2),
        }

    def assert_non_overlapping(self):
        ranges = list(self.ranges().items())
        for idx, lhs in enumerate(ranges):
            lhs_name, lhs_range = lhs
            for rhs_name, rhs_range in ranges[idx + 1 :]:
                if lhs_range[0] < rhs_range[1] and rhs_range[0] < lhs_range[1]:
                    raise ValueError("scratchpad ranges overlap: {} vs {}".format(lhs_name, rhs_name))


def load_preload_bundle(preload_root):
    return PreloadBundle(
        conv_cfg_words=_load_i32_words(preload_root / "preload_conv_cfg_45w.txt"),
        conv_wt_words=_load_packed_i8_words(preload_root / "preload_conv_wt_225w_bytes.txt"),
        fc_bias_words=_load_i32_words(preload_root / "preload_fc_bias_10w.txt"),
        fcw_words=_load_i32_words(preload_root / "preload_fcw_864w.txt"),
    )


def load_inference_case(case_root):
    manifest = load_manifest(case_root / "manifest.txt")
    return InferenceCase(
        case_name=manifest["case"],
        image_words=_load_packed_i8_words(case_root / manifest["conv1_input"]),
        expected_class=int(manifest["predict_class"]),
        manifest=manifest,
    )


def _store_word(mem16, base_halfword, word_index, value):
    raw = int(value) & 0xFFFFFFFF
    mem16[base_halfword + word_index * 2] = raw & 0xFFFF
    mem16[base_halfword + word_index * 2 + 1] = (raw >> 16) & 0xFFFF


def build_mmio_image(layout, preload, case):
    layout.assert_non_overlapping()
    if len(preload.conv_cfg_words) != layout.conv_cfg_words:
        raise ValueError("conv_cfg length mismatch")
    if len(preload.conv_wt_words) != layout.conv_wt_words:
        raise ValueError("conv_wt length mismatch")
    if len(preload.fc_bias_words) != layout.fc_bias_words:
        raise ValueError("fc_bias length mismatch")
    if len(preload.fcw_words) != layout.fcw_words:
        raise ValueError("fcw length mismatch")
    if len(case.image_words) != layout.image_words:
        raise ValueError("image length mismatch")

    mem16 = {}
    for idx, word in enumerate(preload.conv_cfg_words):
        _store_word(mem16, layout.conv_cfg_base_hw, idx, word)
    for idx, word in enumerate(preload.conv_wt_words):
        _store_word(mem16, layout.conv_wt_base_hw, idx, word)
    for idx, word in enumerate(preload.fc_bias_words):
        _store_word(mem16, layout.fc_bias_base_hw, idx, word)
    for idx, word in enumerate(preload.fcw_words):
        _store_word(mem16, layout.fcw_base_hw, idx, word)
    for idx, word in enumerate(case.image_words):
        _store_word(mem16, layout.image_base_hw, idx, word)
    return mem16


def build_mmio_register_file(layout):
    return {
        2: layout.conv_cfg_base_hw,
        3: layout.conv_cfg_words,
        4: layout.conv_wt_base_hw,
        5: layout.conv_wt_words,
        6: layout.fc_bias_base_hw,
        7: layout.fc_bias_words,
        8: layout.fcw_base_hw,
        9: layout.fcw_words,
        10: layout.image_base_hw,
        11: layout.image_words,
    }
