# MATLAB INT8 Golden Flow — 0-9 手势识别 (10 类)

两条流水线并存：

1. **TFLite 软参考** — `rps_conv2.m`：完整 Conv/ReLU/Pool/FC + requant，对单张图做 sanity check。
2. **硬件对齐 golden 生成** — 给 RTL TB 喂 `tb_*.txt` 和 SRAM preload 流，**严格匹配硬件不带 ReLU、Quant 用 eff_bias、FC 不做 quant** 的语义。

---

## 0. 准备模型

```bash
# 在 repo 根目录运行
.venv/bin/python pytorch/export_tflite_params_mat.py \
  --model models/v1.int8.tflite \
  --out models/v1.int8.params.mat
```

把 0-9 各类的样例图丢到 `matlab/main/digit_<N>_*.png`（任意尺寸，自动 resize 到 64×64 灰度）。

---

## 1. TFLite 软参考

```matlab
cd matlab/main
rps_conv2          % 单图，看可视化 + 打印 fc_i32/fc_i8/pred
```

适合 debug 模型本身、检查量化参数有没有问题。**不会** 写 txt 文件。

---

## 2. 硬件对齐 golden 生成

```matlab
cd matlab/main
run_all            % 多图驱动，自动扫 digit_*.png
```

或单图：

```matlab
P = load_params('../../models/v1.int8.params.mat');
R = export_case('digit_3_test.png', P, 'digit_3');
gen_sram_preload('digit_3', R, P);
```

输出（per case）：

```
debug/txt_cases/<case>/
  tb_conv1_in_i8_64x64x1.txt
  tb_conv1_w_i8_3x3x4.txt
  tb_conv1_out_i32_62x62x4.txt          ← raw MAC (x_zp=0,w_zp=0,bias=0)
  tb_conv1_quant_bias_eff_i32_4.txt     ← eff_bias = b - x_zp*sum(W)
  tb_conv1_quant_M_i32_4.txt            ← TFLite 定点乘子 (per-channel)
  tb_conv1_quant_sh_i32_4.txt           ← shift (per-channel)
  tb_conv1_requant_i8_62x62x4.txt       ← clamp((MAC+eff_bias)*M >> sh + zp_out, -128, 127)
  tb_conv1_pool_i8_31x31x4.txt          ← 纯 maxpool (无 ReLU)
  ... conv2 / conv3 同上
  tb_fc_in_i8_288.txt                   ← flatten(pool3) NHWC
  tb_fc_w_i8_10x288.txt                 ← FC 权重 [Cout=10, K=288]
  tb_fc_w_interleaved_i8_288x10.txt     ← SRAM_FCW 字节序 (288×10, ch0=LSB)
  tb_fc_bias_eff_i32_10.txt             ← FC eff_bias
  tb_fc_out_i32_10.txt                  ← FC 累加器 (HW 直接 argmax 的对象)
  manifest.txt                          ← 含 predict_class

debug/sram_preload/<case>/
  preload_conv_cfg_45w.txt              ← (placeholder, 待对齐 RTL cfg packing)
  preload_conv_wt_225w_bytes.txt        ← byte stream (4 字节/host word)
  preload_fc_bias_10w.txt               ← 10 个 INT32, 写 SRAM_A@0x111
  preload_fcw_864w.txt                  ← 864 个 INT32, fcw_preload_packer 打包
```

**所有 txt 严格遵守 [GOLDEN_FORMAT.md](GOLDEN_FORMAT.md)**（一行一整数、LF 行尾、行数 = 元素数）。

---

## 3. 硬件对齐三条铁律（与 RTL 一一对应）

### 3.1 Conv MAC 阶段 — `x_zp = 0, w_zp = 0, bias = 0`

`tb_convN_out_i32_*.txt` 是裸 MAC 输出（不含 bias 折叠、不含 zero-point 折叠）。Quant 阶段独立加 eff_bias。

### 3.2 Quant 用 effective bias

```
eff_bias[oc] = bias[oc] - x_zp * sum(W[oc, :, :, :])
y = clamp(((MAC + eff_bias) * M) >> (31 - sh) + zp_out, -128, 127)
```

- `eff_bias / M / sh` 三件套对应 RTL `Quantization_PE.v`
- `bias_eff` 已经把上游 zero-point 折进去；RTL 不再做 zp 折叠
- M 是 TFLite 定点 INT32（Q0.31）；sh 是非负移位

### 3.3 No ReLU + FC No Quant

- 每层 `out_zp = -128` 时，`clamp(.., -128, 127)` 自动等价于 ReLU；MATLAB 这边**不要**单独调 `relu()`，pool 用纯 `maxpool2x2_int8.m`
- FC 没有 requant 阶段。RTL 把 INT32 累加器（含 eff_bias）直接送 argmax。golden 也写 `tb_fc_out_i32_10.txt`，**不要** 输出 `tb_fc_out_i8_10.txt`
- argmax 用 strict-greater，tie 时低编号优先（与 `top_fsm.v::ST_ARGMAX` 一致）

---

## 4. 文件清单

| 文件 | 角色 | 读/写 |
|---|---|---|
| `rps_conv2.m` | TFLite 软参考（带 ReLU + FC quant，仅供 sanity） | — |
| `load_params.m` | 加载 `.mat`，TFLite OHWI → OIHW 转换，算 (qm, sh) | 入口 |
| `hw_forward.m` | **硬件对齐前向** — 拆出 raw MAC / eff_bias / requant / pool / FC INT32 | 核心 |
| `dump_txt.m` | 按 GOLDEN_FORMAT 写一行一整数（HWC/OIHW/FC interleave 顺序） | 工具 |
| `maxpool2x2_int8.m` | 纯 2×2 maxpool（无 ReLU 折叠） | 工具 |
| `export_case.m` | 单 case：跑前向 + 写所有 `tb_*.txt` + manifest | 入口 |
| `gen_sram_preload.m` | 单 case：写 4 条 host preload 流（FC 完整、conv cfg 待对齐） | 入口 |
| `run_all.m` | 扫 `digit_*.png` 批量驱动 | 入口 |
| `conv2D_int8.m` / `fully_connected_int8.m` / `flatten_nhwc_int8.m` | 软参考算子（rps_conv2 用） | 工具 |
| `relu.m` / `relu_maxpool2x2_int8.m` / `pad_int8_hw.m` | 软参考辅助（rps_conv2 用，hw_forward 不用） | 工具 |
| `requant_int32_to_int8.m` / `tflite_quantize_multiplier.m` | 量化辅助 | 工具 |
| `int32_8.m` / `load_tflite_params_mat.m` | 历史脚手架 | 不用 |

---

## 5. 已知 TODO / Caveat

1. **`gen_sram_preload.m::conv_cfg_stream`** — 目前只把 `[eff_bias(1..4), M(1..4), sh(1)]` 凑成 9 个 word，**这是 placeholder**。真正的 9 cfg word 内部位段排布要查 `input/RTL/quant_pool/integration/quant_param_loader.v`，对照 standalone L1/L2/L3 cfg 文件确认后再用。
2. **`gen_sram_preload.m::conv_wt_pass`** — 已从 `matlab_old/gen_sram_preload.py` 的 `reorder_weights / interleave_for_sram` 移植，包内部读 OIHW 张量；如果 SA reorder 公式有更新需同步。
3. **图像不够 10 类** — 当前只有 `digit_0_test.png`。`run_all.m` 用 `dir('digit_*.png')` 自动扫，加更多图就能跑全。
4. **模型还没出来** — `models/v1.int8.params.mat` 尚未生成；脚本会在 `load_params` 报错。等 PyTorch 那边 export 出来即可跑通。

---

## 6. 与 TB 对接

TB 应该按 GOLDEN_FORMAT.md 读对应的 `tb_*.txt`。建议的对接顺序：

1. **conv1_out / requant / pool**：standalone L1 conv-only TB 验
2. **conv2 / conv3**：同上
3. **FC**：用 `tb_fc_in_i8_288.txt` + `tb_fc_w_interleaved_i8_288x10.txt` + `tb_fc_bias_eff_i32_10.txt` 喂 SRAM_B / SRAM_FCW，比对 `tb_fc_out_i32_10.txt` 和 `manifest.predict_class`
4. **Argmax**：用 `tb_fc_out_i32_10.txt` 单独验 `top_fsm.v::ST_ARGMAX`
5. **System E2E**：用 `preload_*` 4 条流走全链路，比对最终 `predict_class`
