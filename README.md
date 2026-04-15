# CNN_ACC — 0-9 手势识别 CNN 加速器

3-layer INT8 CNN 推理加速器，完成一张 64×64×1 灰度图到 0-9 手势类别 (`predict_class[3:0]`) 的端到端推理。

```
Host (32-bit stream)
    ↓ load_data / load_valid / load_sel / load_last
┌────────────────────────────────────────────────────┐
│ TopFSM (网络调度)                                   │
│   ├── MODEL_LOAD: CFG → WT → FC_CFG → FCW           │
│   └── INFER:   L1 → L2p0 → L2p1 → L3p0 → L3p1 → FC  │
│           → ARGMAX → predict_class[3:0]             │
│                                                    │
│ LayerRunnerFSM (单层调度)                           │
│   LOAD_CFG → LOAD_WT → STREAM → WAIT_DONE           │
└────────────────────────────────────────────────────┘
        ↓            ↓              ↓
   SRAM_A         SRAM_B         SRAM_FCW
   32b×1024       32b×1024       80b×288
   cfg/conv_wt    L1/L3 pool     FC weight
   L2 writeback   output         (新增)
   FC bias
        ↓            ↓              ↓
  ┌─────────────────────────────────────────┐
  │   conv_quant_pool                       │
  │     conv_top (systolic array)           │
  │      → Quantization_Top (4-PE)          │
  │      → pool_stream_top (2×2 maxpool)    │
  └─────────────────────────────────────────┘
        ↓  6×6×8 = 288 INT8 特征
  ┌─────────────────────────────────────────┐
  │  FC (10 路并行 MAC) + argmax            │
  └─────────────────────────────────────────┘
```

---

## 1. 网络结构

| 层 | 输入 | 参数 | 输出 | 说明 |
|---|---|---|---|---|
| **L1 Conv** | 64×64×1 | 3×3×1×4 | 62×62×4 | valid padding，stride 1 |
| **L1 Pool** | 62×62×4 | 2×2 stride 2 | 31×31×4 | maxpool，写入 SRAM_B |
| **L2 Conv** | 31×31×4 | 3×3×4×8（分 2 pass） | 29×29×8 | 每 pass 4 通道，L2 writeback 到 SRAM_A stride-2 交错 |
| **L2 Pool** | 29×29×8 | 2×2 stride 2 | 14×14×8 | |
| **L3 Conv** | 14×14×8 | 3×3×8×8（分 2 pass） | 12×12×8 | |
| **L3 Pool** | 12×12×8 | 2×2 stride 2 | 6×6×8 | 写入 SRAM_B，供 FC 读取 |
| **FC** | 288 (6×6×8 flatten) | 288×10 INT8 权重 + 10×INT32 bias | 10×INT32 | 10 路 MAC 并行 |
| **Argmax** | 10×INT32 | — | 4-bit 类别 id | strict-greater，tie 时低编号优先 |

量化：TFLite 风格对称量化，`acc = (rso × M) >> shift + eff_bias` 饱和到 `[-128, 127]`，每通道一组 `M / shift / bias`。

---

## 2. 顶层控制

### TopFSM ([input/RTL/fsm/top_fsm.v](input/RTL/fsm/top_fsm.v))

网络级顺序控制，19 个状态：

```
ST_IDLE
 ├─ MODEL_LOAD (一次性)：
 │    ST_PL_CFG    →  ST_PL_CFG_W     (45 words conv cfg → SRAM_A@0x000)
 │    ST_PL_WT     →  ST_PL_WT_W      (225 words conv wt → SRAM_A@0x030)
 │    ST_PL_FC_CFG →  ST_PL_FC_CFG_W  (10 words FC bias → SRAM_A@0x111)
 │    ST_PL_FCW    →  ST_PL_FCW_W     (864 host words → SRAM_FCW via packer)
 │    → ST_READY
 └─ INFER (可重复)：
      ST_L1 → ST_L2_P0 → ST_L2_P1 → ST_L3_P0 → ST_L3_P1 → ST_FC
         → ST_ARGMAX → ST_READY
```

每个 INFER 子态 pulse 一次 `runner_start`，等 `runner_done`。`ST_ARGMAX` 用 for 循环组合规约出 10 路 max 的 index，写入 `predict_class[3:0]`。

**L1 像素旁路**：`ST_L1` 期间 TopFSM 置 `pixel_stream_active=1`，`load_data` 直接送到 `conv_data_adapter`，不经 SRAM_A。

### LayerRunnerFSM ([input/RTL/fsm/layer_runner_fsm.v](input/RTL/fsm/layer_runner_fsm.v))

单层事务控制：

```
IDLE → LOAD_CFG → WAIT_CFG ─┬─(is_fc=0)→ LOAD_WT → WAIT_WT ──┐
                            └─(is_fc=1)────────────────────→ STREAM
                                                              ↓
                                                          WAIT_DONE → DONE
```

Conv 路径需要 `pool_frame_done` + `conv_frame_rearm` + `sram_a_done` + `sram_b_done`；FC 路径需要 `fc_done` + 两个 SRAM done。

---

## 3. SRAM 地址映射

### SRAM_A (32-bit × 1024) — [input/RTL/SRAM/top_sram_A.v](input/RTL/SRAM/top_sram_A.v)

| 地址 | 长度 | 用途 | 访问 |
|---|---|---|---|
| `0x000..0x02C` | 45 | PRELOAD_CFG（conv L1/L2/L3 的 bias/M/shift） | preload 写，inference 读 |
| `0x030..0x110` | 225 | PRELOAD_WT（conv L1/L2/L3 权重，按 SA 列交错） | preload 写，inference 读 |
| `0x111..0x11A` | 10 | FC_CFG（10 路 FC bias） | preload 写，inference 读 |
| `0x11B..0x230` | 278 | 空闲（原 3 类 FC 权重区迁出后留空） | — |
| `0x231..0x3B8` | 392 | L2 writeback（stride-2 交错，L3 读时按像素序） | L2 写，L3 读 |

### SRAM_FCW (80-bit × 288) — [input/RTL/SRAM/sram_FCW_wrapper.v](input/RTL/SRAM/sram_FCW_wrapper.v) 新增

| 地址 | 内容 |
|---|---|
| `0x000..0x11F`（288 slot） | 每 slot = `{k9,k8,k7,k6,k5,k4,k3,k2,k1,k0}`（每通道一字节） |

Vivado Block Memory IP 端口签名（`clka/ena/wea/addra/dina/douta/douta_valid`），FPGA 阶段可直接把内部 `reg mem[]` 替换为 `blk_mem_gen_0` IP。

### SRAM_B (32-bit × 1024) — [input/RTL/SRAM/top_sram_B.v](input/RTL/SRAM/top_sram_B.v)

L1 pool（961 words, 31×31×4 打包）和 L3 pool（72 words, 6×6×8 打包）复用同一片 SRAM_B；L3 写入时覆盖 L1 数据。

---

## 4. 预加载协议

Host 通过 `load_data[31:0] / load_valid / load_last` 32-bit 流连续写入；`load_sel=0` 表示 MODEL_LOAD，`load_sel=1` 启动 INFER。

| 阶段 | `layer_sel` | `data_sel` | 字数 | 落点 |
|---|---|---|---|---|
| conv CFG | `LAYER_PRELOAD` | `SEL_CFG` | 45 | SRAM_A @ 0x000 |
| conv WT | `LAYER_PRELOAD` | `SEL_WT` | 225 | SRAM_A @ 0x030 |
| FC bias | `LAYER_FC` | `SEL_CFG` | 10 | SRAM_A @ 0x111 |
| FC weight | `LAYER_PRELOAD` | `SEL_FCW` | 864 host beats → 288×80b | SRAM_FCW via [fcw_preload_packer.v](input/RTL/SRAM/fcw_preload_packer.v) |

**FC weight 打包约定**（每 3 个 host word 组成一个 80-bit slot）：
- word0 `[31:0]` = `{k3, k2, k1, k0}`
- word1 `[31:0]` = `{k7, k6, k5, k4}`
- word2 `[15:0]` = `{k9, k8}`（高 16 位丢弃）

---

## 5. 关键模块清单

### 顶层 & 控制
| 文件 | 角色 |
|---|---|
| [input/RTL/system_top.v](input/RTL/system_top.v) | 顶层，所有互联/MUX；`OUT_CHANNELS=10` 参数化 |
| [input/RTL/fsm/top_fsm.v](input/RTL/fsm/top_fsm.v) | 网络级 FSM + 10 路 argmax |
| [input/RTL/fsm/layer_runner_fsm.v](input/RTL/fsm/layer_runner_fsm.v) | 单层事务 FSM |
| [input/RTL/fsm/conv_data_adapter.v](input/RTL/fsm/conv_data_adapter.v) | L1 byte unpack / L2/L3 pass-through |
| [input/RTL/fsm/wt_prepad_inserter.v](input/RTL/fsm/wt_prepad_inserter.v) | conv 权重流 3-beat padding |

### Conv / Quant / Pool
| 文件 | 角色 |
|---|---|
| [input/RTL/conv_core/conv_quant_pool.v](input/RTL/conv_core/conv_quant_pool.v) | Conv+Quant+Pool 顶层 |
| [input/RTL/conv_core/conv_top.v](input/RTL/conv_core/conv_top.v) | conv engine / systolic array 控制 |
| [input/RTL/conv_core/systolic_array_top.v](input/RTL/conv_core/systolic_array_top.v) | 4-wide systolic array |
| [input/RTL/conv_core/Conv_Buffer.v](input/RTL/conv_core/Conv_Buffer.v) | 卷积中间缓存（flat reg 优化版） |
| [input/RTL/conv_core/Line_Buffer.v](input/RTL/conv_core/Line_Buffer.v) | 3×3 滑窗缓存 |
| [input/RTL/conv_core/weight_buffer.v](input/RTL/conv_core/weight_buffer.v) | 权重预载入 FIFO |
| [input/RTL/conv_core/input_row_aligner.v](input/RTL/conv_core/input_row_aligner.v) | 行对齐 |
| [input/RTL/conv_core/sa_skew_feeder.v](input/RTL/conv_core/sa_skew_feeder.v) | 对角线 skew 送料 |
| [input/RTL/quant_pool/quant/Quantization_Top.v](input/RTL/quant_pool/quant/Quantization_Top.v) | 4-PE 并行量化 |
| [input/RTL/quant_pool/quant/Quantization_PE.v](input/RTL/quant_pool/quant/Quantization_PE.v) | 单 PE（TFLite requant） |
| [input/RTL/quant_pool/pool/pool_stream_top.v](input/RTL/quant_pool/pool/pool_stream_top.v) | 2×2 stream maxpool |
| [input/RTL/quant_pool/pool/pool_core.v](input/RTL/quant_pool/pool/pool_core.v) | pool PE datapath |

### FC (10 路并行)
| 文件 | 角色 |
|---|---|
| [input/RTL/fc/FC.v](input/RTL/fc/FC.v) | `OUT_CHANNELS=10`，`generate for` 例化 10 个 MAC |
| [input/RTL/fc/fc_data_adapter.v](input/RTL/fc/fc_data_adapter.v) | 80b weight 解 10 路 kernel，pixel 广播 |
| [input/RTL/fc/fc_bias_loader.v](input/RTL/fc/fc_bias_loader.v) | 10-word bias 序列分发（一热 `load_bias_vec`） |
| [input/RTL/fc/mac.v](input/RTL/fc/mac.v) | 单通道 MAC（K=288 累积） |

### SRAM
| 文件 | 角色 |
|---|---|
| [input/RTL/SRAM/top_sram_A.v](input/RTL/SRAM/top_sram_A.v) | SRAM_A (32b) + SRAM_FCW (80b) 双路 top |
| [input/RTL/SRAM/sram_A_wrapper.v](input/RTL/SRAM/sram_A_wrapper.v) | SRAM_A 行为级/foundry 接口（ARM macro 风格） |
| [input/RTL/SRAM/sram_A_controller.v](input/RTL/SRAM/sram_A_controller.v) | SRAM_A 地址表 |
| [input/RTL/SRAM/sram_FCW_wrapper.v](input/RTL/SRAM/sram_FCW_wrapper.v) | 288×80b，Vivado BRAM IP 端口签名（新增） |
| [input/RTL/SRAM/fcw_preload_packer.v](input/RTL/SRAM/fcw_preload_packer.v) | 3×32b → 80b 打包器（新增） |
| [input/RTL/SRAM/top_sram_B.v](input/RTL/SRAM/top_sram_B.v) | SRAM_B top，FC data word-interleave 读 |
| [input/RTL/SRAM/sram_B_wrapper.v](input/RTL/SRAM/sram_B_wrapper.v) | SRAM_B 行为级/foundry 接口 |
| [input/RTL/SRAM/sram_B_controller.v](input/RTL/SRAM/sram_B_controller.v) | SRAM_B 地址表 |
| [input/RTL/SRAM/Addr_Gen.v](input/RTL/SRAM/Addr_Gen.v) | 通用地址计数器（base + counter） |

### 存储后端（两选一）
- 行为级：[input/TB/sram_behav.v](input/TB/sram_behav.v)（仿真默认）
- TSMC 65nm foundry macro：[input/SRAM_macro/sram_A/sram_A.v](input/SRAM_macro/sram_A/sram_A.v) / [sram_B.v](input/SRAM_macro/sram_B/sram_B.v)（ASIC-only）
- FPGA：后期用 Vivado Block Memory IP 替换 `sram_FCW_wrapper` 内部存储；`sram_A/B_wrapper` 还需独立重写为 Vivado 原生端口（TODO）

---

## 6. 目录结构

```
CNN_ACC/
├── input/
│   ├── RTL/                synthesizable RTL
│   │   ├── system_top.v
│   │   ├── fsm/            TopFSM, LayerRunnerFSM, adapters
│   │   ├── conv_core/      conv engine + systolic array
│   │   ├── quant_pool/     quantization + pooling
│   │   │   ├── quant/      Quantization_Top/PE
│   │   │   ├── pool/       pool_stream_top/pool_core
│   │   │   └── integration/  conv↔quant, quant↔pool adapters
│   │   ├── fc/             FC.v, mac.v, data adapter, bias loader
│   │   └── SRAM/           wrappers + controllers + FCW (新)
│   ├── TB/                 testbench + behavioral SRAM
│   ├── SDC/                system_top.sdc (50ns clk period)
│   └── SRAM_macro/         ARM foundry macros (ASIC-only)
├── matlab/                 golden 生成、量化脚本
├── vf/                     仿真基础设施
│   ├── work/               run_vsim_*.tcsh 启动脚本
│   ├── scripts/            runtb_*.tcl 编译/运行脚本
│   └── logs/               仿真日志
├── work/                   ModelSim 编译工件
└── README.md
```

---

## 7. 仿真

```bash
# 行为级 RTL（默认，最快；仍用 paper/rock/scissors TB，10-class 未上线）
NO_VCD=1 ./vf/work/run_vsim_system_e2e_behav.tcsh

# 行为级 RTL + foundry SRAM macro
NO_VCD=1 ./vf/work/run_vsim_system_e2e_behav.tcsh gate

# conv-only 单层回归（L1/L2/L3）
./vf/work/run_vsim_conv_only.tcsh [l1|l2|l3|all]

# 综合后（需先跑 Genus + link_library）
./vf/work/run_vsim_system_e2e_syn.tcsh

# PNR 后
./vf/work/run_vsim_system_e2e_pnr.tcsh [min|typ|max]
```

**Lint（无需 TB）**：

```bash
vlog -sv -nologo -work work_full \
  $(find input/RTL -name "*.v") input/TB/sram_behav.v
```

当前状态：`Errors: 0, Warnings: 0`。

---

## 8. MATLAB / Golden 生成

```bash
python3 matlab/gen_sram_preload.py              # 所有 case
python3 matlab/gen_sram_preload.py paper rock   # 指定 case
```

主要脚本（`matlab/`）：

| 文件 | 作用 |
|---|---|
| `gen_sram_preload.py` | 从每层权重/图像生成 SRAM_A/B 预加载流 |
| `gen_fc_golden.py` | 计算 FC 累积 golden（待扩展到 10 路） |
| `export_conv1_quant_params.m` | L1 量化参数 + golden |
| `export_conv23_quant_params.m` | L2/L3 量化参数 + golden |
| `conv2D_int8.m` | INT8 卷积参考模型 |
| `requant_int32_to_int8.m` | TFLite requant 参考 |
| `relu_maxpool2x2_int8.m` | 激活 + maxpool 参考 |
| `fully_connected_int8.m` | FC 参考模型 |
| `flatten_nhwc_int8.m` | NHWC flatten |

---

## 9. 迁移状态

**历史基线**：TSMC 65nm ASIC，3 分类（paper / rock / scissors），System E2E PASS 3/3。

**当前**：FPGA 目标，10 分类（0-9 手势）。

RTL 已完成：
- FC 扩到 10 路并行 MAC，`generate for` 例化，参数化 `OUT_CHANNELS`
- 新增 80-bit 专用 `sram_FCW`（288 slots）+ `fcw_preload_packer`
- TopFSM 新增 `ST_PL_FC_CFG / ST_PL_FCW` 预加载子态
- 10 路组合 argmax，`predict_class` 扩到 4-bit
- SRAM_A 地址图：FC bias 迁到 0x111，原 FC 权重区留空
- `vlog -sv` 全量 lint 0 errors / 0 warnings

待办：
1. MATLAB 生成器出 10 类 FC 权重/bias preload 流（含 80-bit 打包约定）
2. TB 更新：`fc_golden` 扩到 10 项、`predict_class` 比较扩到 4-bit、FC-WT probe 宽度改 80b、新增 0-9 各一个测试 case
3. FPGA port：用 Block Memory Generator IP 替换 `sram_FCW_wrapper` 内部行为级 `mem`
4. SRAM_A/B wrapper 后续也需改造为 Vivado 原生端口（与主线迁移解耦，可延后）

---

## 10. 参数总表

| 参数 | 值 | 位置 |
|---|---|---|
| 图像尺寸 | 64×64×1 | L1 输入 |
| Pixel / Kernel 位宽 | 8 bit (INT8) | `PIX_W=KER_W=8` |
| Accumulator 位宽 | 32 bit | `ACC_W=32` |
| FC 输入维度 K | 288 | `FC.K` |
| FC 输出通道 | 10 | `OUT_CHANNELS=10` |
| SRAM_A | 32b × 1024 | 4 KB |
| SRAM_B | 32b × 1024 | 4 KB |
| SRAM_FCW | 80b × 288 | 2.88 KB |
| Systolic array 宽 | 4 columns | conv_top |
| Quantization PE 数 | 4 并行 | Quantization_Top |
| 时钟周期约束 | 50 ns (20 MHz) | system_top.sdc |
| 输出类别 | 10 (0-9) | `predict_class[3:0]` |
