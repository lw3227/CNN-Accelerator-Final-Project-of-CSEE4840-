# 构建、资源与 Timing 说明

这份文档回答的是：

- 现在主工程怎么编
- 当前模型文件有多大
- staged payload 各有多大
- fit summary / timing report 去哪里看
- 当前 resource budget 和 timing budget 是多少

英文原版在：

- [../BUILD_TIMING_AND_RESOURCES.md](../BUILD_TIMING_AND_RESOURCES.md)

## 1. 主构建入口

主命令：

```bash
python de1_soc/build_soc_system.py
```

关键输入：

- [`../../de1_soc/build_soc_system.py`](../../de1_soc/build_soc_system.py)
- [`../../de1_soc/soc_system.qsys`](../../de1_soc/soc_system.qsys)
- [`../../de1_soc/soc_system_top.sv`](../../de1_soc/soc_system_top.sv)
- [`../../de1_soc/soc_system.sdc`](../../de1_soc/soc_system.sdc)

关键输出：

- [`../../de1_soc/output_files/soc_system.sof`](../../de1_soc/output_files/soc_system.sof)
- [`../../de1_soc/output_files/soc_system.rbf`](../../de1_soc/output_files/soc_system.rbf)
- [`../../de1_soc/output_files/soc_system.fit.summary`](../../de1_soc/output_files/soc_system.fit.summary)
- [`../../de1_soc/output_files/soc_system.sta.summary`](../../de1_soc/output_files/soc_system.sta.summary)
- [`../../de1_soc/output_files/soc_system.sta.rpt`](../../de1_soc/output_files/soc_system.sta.rpt)

## 2. 当前模型文件大小

当前部署模型：

- [`../../Golden-Module/models/v1.int8.tflite`](../../Golden-Module/models/v1.int8.tflite)
- [`../../Golden-Module/models/v1.int8.params.mat`](../../Golden-Module/models/v1.int8.params.mat)

当前大小：

- `v1.int8.tflite`：`9232` bytes
- `v1.int8.params.mat`：`8306` bytes

## 3. 当前模型结构摘要

从硬件 payload 角度看，当前 active lane 是一个 10 类 gesture classifier：

- L1 conv：`3x3x1 -> 4 channels`
- L2 conv：`3x3x4 -> 8 channels`
- L3 conv：`3x3x8 -> 8 channels`
- FC：`6x6x8 = 288 inputs -> 10 outputs`

## 4. 当前 staged payload 大小

| Payload | Words | Bytes |
| --- | ---: | ---: |
| Conv config | `45` | `180` |
| Conv weights | `225` | `900` |
| FC bias | `10` | `40` |
| FC weights | `864` | `3456` |
| One input image | `1024` | `4096` |

## 5. 当前资源占用

来自：

- [`../../de1_soc/output_files/soc_system.fit.summary`](../../de1_soc/output_files/soc_system.fit.summary)

| Resource | Usage |
| --- | --- |
| ALMs | `18,380 / 32,070 (57%)` |
| Registers | `27,025` |
| Pins | `164 / 457 (36%)` |
| Block memory bits | `372,736 / 4,065,280 (9%)` |
| RAM blocks | `45 / 397 (11%)` |
| DSP blocks | `86 / 87 (99%)` |
| PLLs | `0 / 6 (0%)` |
| DLLs | `1 / 4 (25%)` |

### 这组数字怎么读

- 最紧的是 DSP：`99%`
- RAM 还比较宽松：`11%`
- PLL 没用：`0%`

这也解释了为什么这条分支更倾向于：

- 用一点额外 M10K / buffer / pipeline
- 换更容易闭 timing 的路径

而不是再去加 PLL。

## 6. 当前时钟与 timing 结果

当前 fabric 是直接跑：

- `CLOCK_50`

关键报告：

- [`../../de1_soc/output_files/soc_system.sta.summary`](../../de1_soc/output_files/soc_system.sta.summary)
- [`../../de1_soc/output_files/soc_system.sta.rpt`](../../de1_soc/output_files/soc_system.sta.rpt)

当前重点数字：

- `clock_50` slow-corner setup slack：`6.794 ns`
- `clock_50` slow-corner Fmax：`75.72 MHz`

所以现在直接跑 `50 MHz` 是安全的。

## 7. 为什么全局最差 path 还会看到 DDR

这不代表 accelerator 在用外部 DDR 做 feature map。

原因是：

- 当前工程里 HPS + DDR PHY 仍然是整个 SoC 设计的一部分
- Quartus/STA 会把整颗 SoC 一起分析

所以全局最差 path 可能还是落在：

- HPS DDR 相关时钟域

但这不等于你这条 CNN fabric 的 `clock_50` 没过。

如果你要判断 accelerator 自己能不能在 50MHz 跑，重点看：

- `clock_50` 的 setup slack / Fmax

不要只看 whole-design worst path。

