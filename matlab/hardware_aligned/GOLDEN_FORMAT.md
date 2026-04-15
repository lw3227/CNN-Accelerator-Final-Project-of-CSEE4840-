# Golden TXT 格式规范

所有 MATLAB / Python golden 模块输出的 `.txt` 必须严格遵守本规范，否则 RTL TB 的 `$readmemh / $readmemb / $fscanf` 解析会失败或读到错位数据。

适用范围：`matlab/debug/txt_cases/<case>/` 下所有 `tb_*.txt`，以及 SRAM preload 流（`sram_preload/<case>/` 下产物）。

---

## 1. 文件命名

```
tb_<layer>_<role>_<dtype>_<shape>.txt
```

| 字段 | 取值 | 说明 |
|---|---|---|
| `<layer>` | `conv1` / `conv2` / `conv3` / `fc` | 网络层 |
| `<role>` | `in` / `w` / `out` / `pool` / `requant` / `bias_eff` / `quant_M` / `quant_sh` / `w_interleaved` | 张量在层内的角色 |
| `<dtype>` | `i8` / `i32` | 元素类型（INT8 / INT32），见 §3 |
| `<shape>` | `HxWxC` / `Cout x Cin x H x W` / `N` | 维度，按 §4 顺序 |

示例：
- `tb_conv1_in_i8_64x64x1.txt`
- `tb_conv2_w_i8_3x3x4x8.txt`
- `tb_fc_bias_eff_i32_10.txt`
- `tb_fc_w_interleaved_i8_288x10.txt`

**反例**（不要这样写）：
- `conv1_input.txt`（缺 dtype/shape）
- `tb_conv1_in.txt`（同上）
- `tb_conv1_in_int8_64_64_1.txt`（用错分隔符；维度必须用 `x`）

---

## 2. 文件内容

### 2.1 通用规则

1. **每行一个标量**（十进制 ASCII），无前导/尾随空格，**无千位分隔符**。
2. 行尾用单个 `\n`（LF），**不允许 CRLF**。
3. **不允许**注释、空行、表头、尾注。整文件就是一列纯数字。
4. 文件**必须以换行结尾**（最后一行末尾有 `\n`）。
5. 所有数字都是**有符号十进制整数**：`-128`、`0`、`127`、`-1234567`。**不允许** 16 进制 / 浮点 / 科学计数。

### 2.2 元素行数 = 张量元素总数

张量 shape `D0 × D1 × ... × Dn` 的文件**必须恰好** `D0*D1*...*Dn` 行。
TB 会用 `wc -l` 或循环读取做强校验，多一行少一行都视为 fatal error。

| 文件 | 元素数 |
|---|---|
| `tb_conv1_in_i8_64x64x1.txt` | 4096 |
| `tb_conv1_pool_i8_31x31x4.txt` | 3844 |
| `tb_fc_in_i8_288.txt` | 288 |
| `tb_fc_w_i8_10x288.txt` | 2880 |
| `tb_fc_bias_eff_i32_10.txt` | 10 |
| `tb_fc_out_i32_10.txt` | 10 |

### 2.3 数值范围（dtype 对齐）

| dtype | 合法范围 | 越界处理 |
|---|---|---|
| `i8`  | `[-128, 127]`               | MATLAB 端 saturation 后写出，TB 端校验 |
| `i32` | `[-2147483648, 2147483647]` | 对 INT64 累加器先饱和到 INT32 再写出 |

---

## 3. dtype 选择规则

| dtype | 用在 |
|---|---|
| `i8`  | 输入图像、量化后激活、INT8 权重、`*_pool`、`*_requant` |
| `i32` | conv MAC 累积输出（未量化）、quant 参数（M、shift、bias_eff）、FC accumulator |

**禁止用 `u8`**：所有张量按有符号 INT8/INT32 处理（zero-point 通过 `bias_eff` 折叠，详见 §6）。

---

## 4. 维度顺序约定

### 4.1 张量遍历顺序：**outer → inner = 慢 → 快变维**

写入顺序 = `for d0: for d1: ... for dn: write(tensor[d0][d1]...[dn])`。

- **图像 / 激活 (HWC)**：`H × W × C`，`C` 最快变。
  ```
  for h in 0..H-1:
    for w in 0..W-1:
      for c in 0..C-1:
        write(tensor[h][w][c])
  ```
  → 像素 `(0,0,0), (0,0,1), ..., (0,0,C-1), (0,1,0), ...`

- **Conv 权重 (Cout, Cin, H, W) 即 OIHW**：
  ```
  for cout in 0..Cout-1:
    for cin in 0..Cin-1:
      for h in 0..H-1:
        for w in 0..W-1:
          write(W[cout][cin][h][w])
  ```

- **FC 权重 `(OUT_CHANNELS, K)`**：每个输出通道连续 `K=288` 个权重。
  ```
  for oc in 0..OUT_CHANNELS-1:
    for k in 0..K-1:
      write(W[oc][k])
  ```

- **FC 输入 `(K=288)`**：扁平化已经在 MATLAB 完成（`flatten_nhwc_int8.m`），直接按 `for k: write(x[k])`。

- **量化参数 `(C)`**：每输出通道一行，按 `c=0..C-1` 顺序。

### 4.2 SRAM 交错布局：`*_interleaved` 单独命名

凡是要被 RTL **直接当 SRAM 字读** 的文件，文件名带 `interleaved`，shape 写**字节-级布局**而非张量逻辑形状。例如 FC 10-class 的 SRAM_FCW 预加载：

- 文件名：`tb_fc_w_interleaved_i8_288x10.txt` （288 个 SRAM_FCW slot × 10 字节/ slot）
- 元素总数：2880
- 写入顺序：`for k in 0..287: for oc in 0..9: write(W[oc][k])`
- 等价于：每个 80-bit slot 内 LSB→MSB 依次为 `k0,k1,...,k9`

3-class 旧版的 `tb_fc_w_interleaved_i8_288x4.txt` 是 32-bit slot × 288 = 1152 字节（每 slot 内 `{k0,k1,k2,pad}`），按上同规则推导。

---

## 5. Manifest 文件

每个 case 目录必须有 `manifest.txt`，**键值对格式**，等号分隔：

```
key=value
```

**约束**：
- 每行一对；`key` 在等号左侧（无空格），`value` 在右侧（无引号）。
- 没有空行、没有注释（`#` 不是注释）。
- 必须包含的 key（按出现顺序无要求）：

  | key | 例 | 说明 |
  |---|---|---|
  | `case` | `rock` / `digit_3` | case 名（与目录名一致） |
  | `image_file` | `rock_200_v1_test_1484.png` | 源图 |
  | `conv1_input` ... `conv3_output` | 文件名 | 各层 in/w/out 文件名（不含路径） |
  | `fc_input` | `tb_fc_in_i8_288.txt` | |
  | `fc_weight_interleaved` | `tb_fc_w_interleaved_i8_288x10.txt` | |
  | `fc_bias_eff` | `tb_fc_bias_eff_i32_10.txt` | |
  | `fc_output` | `tb_fc_out_i32_10.txt` | 10-way FC accumulator golden |
  | `predict_class` | `0`..`9` | argmax 期望值（**新增字段**，4-bit） |
  | `input_zero_point` | `-128` | INT8 zp |
  | `conv1/2/3_output_zero_point` | `-128` | |
  | `conv_rule` | （字符串） | 与 §6 一致的描述 |
  | `conv1/2/3_input_shape` / `_output_shape` | `64x64x1` | 校验用 |
  | `conv1/2/3_output_range` | `[min,max]` | 调试参考 |

`value` 中**不允许** 包含 `=`、换行、tab。

---

## 6. 量化语义约定

`tb_*_quant_M_i32_C.txt` / `_quant_sh_i32_C.txt` / `_quant_bias_eff_i32_C.txt` 三件套对应 RTL 量化通路：

```
acc_int32 = conv_mac_out + bias_eff[c]      // MAC 端用 x_zp=0, w_zp=0, bias=0
y_int32   = (acc_int32 * M[c]) >>> sh[c]    // arithmetic shift right, signed
y_int8    = clamp(y_int32 + out_zp, -128, 127)
```

**约束**：
- `bias_eff` 已经把上游 zero-point 折叠进去（即 `bias_eff = bias_orig + Σ(x_zp × w)`）；RTL 不再做 zp 折叠。
- `M` 是 INT32（TFLite quantized_multiplier，固定点）。
- `sh` 是非负整数，表示**右移位数**；写出时直接写十进制（如 `40`），**不要写负数也不要把方向写反**。
- `out_zp` 写在 `manifest.txt` 的 `convN_output_zero_point` 字段，不另出 .txt。

---

## 7. 文件大小 sanity

每个文件大小约 `行数 × (avg 5~6 字节)`。生成完后用：

```bash
wc -l matlab/debug/txt_cases/<case>/*.txt
```

对照 §2.2 表格交叉校验。任何长度不符立即视为 bug，不要让其流入仿真。

---

## 8. 端到端 sanity 列表（每个新 case 上线前必跑）

1. ✅ 文件名匹配 `tb_<layer>_<role>_<dtype>_<shape>.txt` 正则
2. ✅ `wc -l` 等于 shape 元素总数
3. ✅ `awk '{ if ($1+0 < -128 || $1+0 > 127) print NR, $1 }'` 对 `i8` 文件无输出
4. ✅ `manifest.txt` 含全部必填 key
5. ✅ `manifest.predict_class` 与 `tb_fc_out_i32_10.txt` 的 argmax 一致（用 strict-greater，tie 时低 index 优先；与 RTL `top_fsm.v::ST_ARGMAX` 行为一致）
6. ✅ 文件以 `\n` 结尾，无 CRLF（`file <name>` 应报 "ASCII text"，不带 "with CRLF line terminators"）

---

## 9. 反例速查

| ❌ | ✅ |
|---|---|
| `0x80` | `-128` |
| `1.0` | `1` |
| `1,234` | `1234` |
| ` 5` (前导空格) | `5` |
| `5\r\n` (CRLF) | `5\n` (LF) |
| 多列 / 表头 / 注释 | 单列纯数字 |
| 文件末尾无 `\n` | 末行带 `\n` |
| `tb_fc_w_interleaved_i8_288x10.txt` 含 2879 行 | 必须 2880 行 |
| `bias_eff` 用 `i64` | 必须饱和到 `i32` |
