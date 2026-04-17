"""Network and tensor loaders adapted to the CNN_ACC debug/golden format."""

from pathlib import Path


def _load_scalar_txt(path):
    with path.open("r", encoding="utf-8") as fp:
        return [int(line.strip()) for line in fp if line.strip()]


def _parse_shape_from_name(path):
    stem = path.stem
    dims = stem.split("_")[-1]
    return tuple(int(part) for part in dims.split("x"))


def load_manifest(path):
    manifest = {}
    with path.open("r", encoding="utf-8") as fp:
        for raw_line in fp:
            line = raw_line.strip()
            if not line:
                continue
            key, value = line.split("=", 1)
            manifest[key] = value
    return manifest


class FeatureMap(object):
    def __init__(self, width, height, depth, values):
        self.width = width
        self.height = height
        self.depth = depth
        self.values = values

    @classmethod
    def from_txt(cls, path):
        shape = _parse_shape_from_name(path)
        if len(shape) == 1:
            width, height, depth = shape[0], 1, 1
        elif len(shape) == 3:
            width, height, depth = shape[1], shape[0], shape[2]
        else:
            raise ValueError("Unsupported feature-map shape in {}".format(path))
        return cls(width=width, height=height, depth=depth, values=_load_scalar_txt(path))


class ConvLayer(object):
    def __init__(self, out_channels, in_channels, kernel_h, kernel_w, weights, bias, quant_m, quant_shift):
        self.out_channels = out_channels
        self.in_channels = in_channels
        self.kernel_h = kernel_h
        self.kernel_w = kernel_w
        self.weights = weights
        self.bias = bias
        self.quant_m = quant_m
        self.quant_shift = quant_shift

    @classmethod
    def from_case_dir(cls, case_dir, prefix):
        weight_path = next(case_dir.glob("tb_{}_w_i8_*.txt".format(prefix)))
        bias_path = next(case_dir.glob("tb_{}_quant_bias_eff_i32_*.txt".format(prefix)))
        quant_m_path = next(case_dir.glob("tb_{}_quant_M_i32_*.txt".format(prefix)))
        quant_shift_path = next(case_dir.glob("tb_{}_quant_sh_i32_*.txt".format(prefix)))
        dims = _parse_shape_from_name(weight_path)
        kh, kw = dims[0], dims[1]
        rest = dims[2:]
        if len(rest) == 1:
            in_channels, out_channels = 1, rest[0]
        elif len(rest) == 2:
            in_channels, out_channels = rest[0], rest[1]
        else:
            raise ValueError("Unsupported conv weight shape in {}".format(weight_path))
        return cls(
            out_channels=out_channels,
            in_channels=in_channels,
            kernel_h=kh,
            kernel_w=kw,
            weights=_load_scalar_txt(weight_path),
            bias=_load_scalar_txt(bias_path),
            quant_m=_load_scalar_txt(quant_m_path),
            quant_shift=_load_scalar_txt(quant_shift_path),
        )


class FullyConnectedLayer(object):
    def __init__(self, out_channels, in_channels, weights, bias):
        self.out_channels = out_channels
        self.in_channels = in_channels
        self.weights = weights
        self.bias = bias

    @classmethod
    def from_case_dir(cls, case_dir):
        weight_path = next(case_dir.glob("tb_fc_w_i8_*.txt"))
        bias_path = next(case_dir.glob("tb_fc_bias_eff_i32_*.txt"))
        out_channels, in_channels = _parse_shape_from_name(weight_path)
        return cls(
            out_channels=out_channels,
            in_channels=in_channels,
            weights=_load_scalar_txt(weight_path),
            bias=_load_scalar_txt(bias_path),
        )


class GestureNetwork(object):
    def __init__(self, conv1, conv2, conv3, fc):
        self.conv1 = conv1
        self.conv2 = conv2
        self.conv3 = conv3
        self.fc = fc

    @classmethod
    def from_debug_case(cls, case_dir):
        return cls(
            conv1=ConvLayer.from_case_dir(case_dir, "conv1"),
            conv2=ConvLayer.from_case_dir(case_dir, "conv2"),
            conv3=ConvLayer.from_case_dir(case_dir, "conv3"),
            fc=FullyConnectedLayer.from_case_dir(case_dir),
        )
