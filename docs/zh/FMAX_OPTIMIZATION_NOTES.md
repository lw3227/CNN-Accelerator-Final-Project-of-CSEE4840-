# Fmax 提升说明

这份文档面向继续维护 RTL 和时序的硬件同学。

它重点回答 5 个问题：

- 这次为了把设计稳定拉回 `50 MHz` 以上，到底改了哪些硬件结构
- 这些改动分别落在什么文件、什么模块
- 原来的关键路径大概长什么样
- 为什么这些改动有利于 timing
- 为什么有些地方虽然多插了寄存器，`total_cycles` 反而可能下降

英文对应版：

- [../FMAX_OPTIMIZATION_NOTES.md](../FMAX_OPTIMIZATION_NOTES.md)

## 1. 先看结论

当前 `submission` 分支的关键结果是：

- 目标时钟：`clock_50 = 50 MHz`
- 当前 slow-corner Fmax：`75.72 MHz`
- 当前已经不需要 `clk_div2` 或 PLL 才能跑过 `50 MHz`

相关报告：

- [../../de1_soc/output_files/soc_system.sta.summary](../../de1_soc/output_files/soc_system.sta.summary)
- [../../de1_soc/output_files/soc_system.sta.rpt](../../de1_soc/output_files/soc_system.sta.rpt)

## 2. 这次不是重写整个加速器，而是集中改了 4 个地方

| 硬件区域 | 主文件 | 主要结构改动 |
| --- | --- | --- |
| 系统级控制 | [`../../input/RTL/fsm/top_fsm.v`](../../input/RTL/fsm/top_fsm.v) | 启动时序拆拍、argmax 结构改成迭代 |
| conv 前端 / SA 入口 | [`../../input/RTL/conv_core/conv_top.v`](../../input/RTL/conv_core/conv_top.v) | 在阵列前插显式寄存器边界 |
| SRAM_B 到 FC 路径 | [`../../input/RTL/SRAM/top_sram_B.v`](../../input/RTL/SRAM/top_sram_B.v) | 新增 FC-order M10K reorder buffer |
| MMIO wrapper | [`../../input/RTL/interface/cnn_mmio_interface.v`](../../input/RTL/interface/cnn_mmio_interface.v) | 32-bit 清理，wrapper 合同更简单 |

如果只想看最关键的硬件结构变化，优先读这 4 个文件。

## 3. 原来 timing 主要长在哪

这次主要不是 MMIO 在卡频，而是 conv/feed/control 一侧在卡频。

历史 fabric 关键路径的线索在：

- [../../de1_soc/output_files/fabric_timing_summary_latest.txt](../../de1_soc/output_files/fabric_timing_summary_latest.txt)

典型路径形状包括：

- `conv_engine_ctrl.rd_col_r[4] -> sa_skew_feeder.delay[36][3]`
- `pool_core.layer_sel_d[0] -> sa_skew_feeder.delay[36][3]`

这说明问题更像是：

1. 控制信号 launch 得太晚，扇出太大
2. Conv_Buffer / skew feeder / SA 入口之间的跨模块组合链太长
3. FC 尾部还有大组合比较和重排逻辑

所以这次优化的总思路不是改模型，而是改结构：

- 把同一拍做太多事的地方拆成多拍
- 在 SA 边界前增加明确寄存器 cut
- 把 FC 读侧重排移到存储组织
- 把宽比较树改成小状态机

## 4. 怎么判断这些改动属于“结构优化”

这里说的“结构优化”，不是改卷积核，也不是改模型参数。

它改的是这些东西：

- 寄存器边界放在哪里
- 控制信号在哪一拍锁存
- 数据在哪一拍稳定后再发
- 重排逻辑是放在主动数据通路里，还是放到 RAM 组织里

一句话讲：

> 不是改变算法，而是改变“这一拍必须做完的事情有多少”。

也可以理解成：

- 原来：一口气做太多事
- 现在：拆成两口气或三口气做，每一拍更短、更规整

## 5. `top_fsm.v`：把“配下一层”和“真正启动”拆成两拍

文件：

- [`../../input/RTL/fsm/top_fsm.v`](../../input/RTL/fsm/top_fsm.v)

关键标识符：

- `runner_prepared`
- `runner_started`
- `runner_layer_sel`
- `runner_pass_id`
- `runner_is_fc`
- `runner_start`

对应代码位置：

- `runner_prepared` 定义：[top_fsm.v:103](../../input/RTL/fsm/top_fsm.v#L103)
- L1/L2/L3/FC 启动流程：[top_fsm.v:325](../../input/RTL/fsm/top_fsm.v#L325)

### 5.1 改动前的大概结构

以前更接近：

```text
状态切换
  -> 同拍决定 layer/pass/is_fc
  -> 同拍发 runner_start
```

也就是说，下游模块在同一拍里既要看到新的控制配置，又要同时响应启动脉冲。

### 5.2 改动后的结构

现在变成：

```text
第 1 拍：先锁住 layer/pass/is_fc
第 2 拍：再发 runner_start
```

代码上就是：

- 先 `runner_prepared <= 1'b1`
- 下一拍再 `runner_start <= 1'b1`

### 5.3 为什么这样更快

这等于把原来一条控制长路径：

```text
FSM decode -> 新控制值 -> 下游同时启动
```

拆成：

```text
FSM decode -> 控制寄存器
下一拍 -> 下游看到稳定控制后再启动
```

收益：

- launch-side control fanout 压力下降
- 下游不需要在同拍同时吃掉“配置变化”和“start 边沿”
- sequencer 和 datapath 之间出现更清晰的同步边界

这类优化的本质是：

> 多花 1 个 cycle，换掉一条很长的 control-to-datapath 组合路径。

## 6. `top_fsm.v`：把 argmax 从一拍宽比较树改成迭代扫描

文件：

- [`../../input/RTL/fsm/top_fsm.v`](../../input/RTL/fsm/top_fsm.v)

关键标识符：

- `ST_ARGMAX`
- `argmax_scan_idx`
- `argmax_best_idx`
- `argmax_best_val`
- `fc_acc_vec`

对应代码位置：

- Argmax 状态实现：[top_fsm.v:417](../../input/RTL/fsm/top_fsm.v#L417)

### 6.1 改动前的大概结构

如果最后一拍要直接从 `fc_acc_vec[0..9]` 里找最大值，结构通常会很像：

```text
fc_acc_vec[0..9]
  -> 宽比较树
  -> 同拍给出 predict_class
```

这种宽比较树很容易变成 timing hotspot。

### 6.2 改动后的结构

现在改成了逐拍扫描：

```text
每拍比较一个 class
  -> 和当前 best_val 比
  -> 如果更大就更新 best_val / best_idx
  -> 扫完再输出 predict_class
```

也就是把：

```text
一拍做完 10 路比较
```

变成：

```text
多拍完成，每拍只做一个小比较
```

### 6.3 为什么这样更快

因为它把：

- 一个宽 compare tree

换成了：

- 一个小比较器
- 若干寄存器
- 一个小状态机

这是很典型的：

> 用少量额外 latency，换掉尾部的大组合比较链。

## 7. `conv_top.v`：在 SA 入口前明确插入寄存器 cut

文件：

- [`../../input/RTL/conv_core/conv_top.v`](../../input/RTL/conv_core/conv_top.v)

关键标识符：

- `active_layer_sel_q`
- `sa_mode_cfg_q`
- `sa_valid_rows_cfg_q`
- `sa_start_pulse_q`
- `sa_a_in_flat_q`
- `sa_b_in_flat_q`

对应代码位置：

- `active_layer_sel_q`：[conv_top.v:53](../../input/RTL/conv_core/conv_top.v#L53)
- SA 输入 pipeline：[conv_top.v:144](../../input/RTL/conv_core/conv_top.v#L144)

### 7.1 改动前的大概结构

原来更像：

```text
layer_sel / 控制 decode
  -> input_row_aligner
  -> Conv_Buffer
  -> sa_skew_feeder
  -> systolic array 输入边界
```

也就是 SA 入口前面连着一条跨模块组合链。

### 7.2 改动后的结构

现在 `conv_top` 先把两类东西本地寄存起来：

1. layer-dependent control
   - `active_layer_sel_q`
   - `sa_mode_cfg_q`
   - `sa_valid_rows_cfg_q`
   - `sa_start_pulse_q`
2. 真正送进 SA 的输入 bundle
   - `sa_a_in_flat_q`
   - `sa_b_in_flat_q`

等于在阵列门口多放了一道同步边界：

```text
上游组合逻辑
  -> conv_top 本地寄存器
  -> 下一拍再送进 SA
```

### 7.3 为什么这样更快

这一步是当前最重要的 datapath-side timing cleanup。

收益：

- 把跨模块长组合链切成两段
- 把 `layer_sel` 的影响本地化在 `conv_top`
- 让 SA 看到的是更像 pipeline stage 的输入合同
- 减少 `Conv_Buffer -> sa_skew_feeder -> SA input` 这条链的压力

简单说：

> 以前是“上游这拍现算、SA 这拍就吃”；现在是“先在 conv_top 门口站稳，再进 SA”。

## 8. `conv_top.v`：把 frame rearm / backend idle 的边界做得更显式

文件：

- [`../../input/RTL/conv_core/conv_top.v`](../../input/RTL/conv_core/conv_top.v)

关键标识符：

- `backend_idle`
- `backend_idle_d`
- `frame_rearm`
- `frame_rearm_out`
- `frame_done_out`

### 8.1 这块改的不是数学，而是时序边界

相邻 layer/pass 之间以前更容易依赖一些隐式条件，可能造成：

- stale state 传播
- producer / consumer 边界不清晰
- synthesis 很难把边界当作干净的同步 cut

### 8.2 现在的做法

现在把这些边界做成更显式的同步信号：

- backend idle
- frame drain complete
- safe re-arm timing

### 8.3 为什么有帮助

这块单独看不一定是最大 Fmax 提升来源，但它能让：

- 相邻 pass/layer 的边界更清楚
- pipeline 更稳定
- 前面插入的寄存器 cut 更可信

这属于“让结构更规整、更好 pipeline 化”的优化。

## 9. `top_sram_B.v`：用一个额外 M10K 换掉 FC 读侧的重排逻辑

文件：

- [`../../input/RTL/SRAM/top_sram_B.v`](../../input/RTL/SRAM/top_sram_B.v)
- [`../../input/RTL/SRAM/sram_B_controller.v`](../../input/RTL/SRAM/sram_B_controller.v)

关键标识符：

- `fc_input_mem`
- `fc_buf_write_mirror`
- `fc_buf_read_txn`
- `fc_buf_wr_addr`
- `fc_buf_rd_count`

对应代码位置：

- FC reorder buffer 说明：[top_sram_B.v:50](../../input/RTL/SRAM/top_sram_B.v#L50)
- `fc_input_mem` 和顺序读实现：[top_sram_B.v:118](../../input/RTL/SRAM/top_sram_B.v#L118)

### 9.1 改动前的大概结构

原来 L3 pass0 / pass1 的结果是按 pass 顺序存的。

这样 FC 想要按空间位置顺序消费时，读路径就得做交错地址访问，类似：

```text
0, 36, 1, 37, 2, 38, ...
```

也就是：

- 重排逻辑挂在 FC active read path 上
- 读侧组合地址逻辑更复杂

### 9.2 改动后的结构

现在新增一个专门给 FC 用的 reorder buffer：

```text
L3 pass0 -> 写偶地址
L3 pass1 -> 写奇地址
FC      -> 顺序读 0..71
```

所以不是“交替关系消失了”，而是：

- 以前：读的时候重排
- 现在：写的时候提前排好

### 9.3 为什么这样更快

收益：

- FC 读侧变成简单顺序读
- 实时地址重排不再挂在 active path 上
- 复杂度被移到存储布局里

这是最典型的一刀：

> 多花一点片上 RAM，换更短、更规整的组合逻辑。

而当前资源图也支持这么做：

- RAM block 只有 `11%`
- DSP 已经到 `99%`

说明这份设计是“DSP 紧、RAM 还宽松”，所以用 M10K 换 timing 很合理。

## 10. `cnn_mmio_interface.v`：这是接口清理，不是主要 Fmax 来源

文件：

- [`../../input/RTL/interface/cnn_mmio_interface.v`](../../input/RTL/interface/cnn_mmio_interface.v)
- [`../../include/cnn_mmio_regs.h`](../../include/cnn_mmio_regs.h)
- [`../../include/cnn_mmio_host.h`](../../include/cnn_mmio_host.h)
- [`../../tools/cnn_mmio_host.c`](../../tools/cnn_mmio_host.c)

### 10.1 改了什么

- scratchpad 改成 32-bit word addressing
- replay 直接送 32-bit word
- 去掉旧的 low/high halfword stitch
- 保留 low-16-bit control/status ABI 兼容语义

### 10.2 为什么它不是主要 Fmax 来源

因为真正最紧的 fabric path 主要在 conv/feed/FC 主链，而不是 MMIO wrapper。

它的价值主要在：

- host 协议更清楚
- wrapper 结构更简单
- 文档和软件逻辑更一致

所以这块属于“有帮助的清理”，不是“把 Fmax 拉回 50MHz 的主因”。

## 11. 为什么总 cycle 反而可能更少

这点很容易让人误会，所以单独说清楚。

直觉上会觉得：

- 多加寄存器
- 多一个准备拍

是不是应该让 `total_cycles` 增加？

答案是不一定。

### 11.1 原因

这次改动不是“单纯插寄存器”，而是同时做了两类事：

1. 在少数地方增加阶段
   - 比如 `runner_prepared`
2. 在更多地方减少 active path 上的拖慢和 bubble
   - conv 前的长组合链被切短
   - FC 读侧重排逻辑被移走
   - argmax 不再走尾部宽比较树

所以很可能出现：

- 局部多花 1 拍
- 但整条 inference 主流程少等了更多拍
- 最后 `total_cycles` 反而更低

### 11.2 要怎么理解 `total_cycles`

`top_fsm` 里的 `profile_total_cycles` 统计的是：

- 主状态机处在真正 inference 活跃状态时，一共走了多少拍

对应代码：

- [top_fsm.v:173](../../input/RTL/fsm/top_fsm.v#L173)

它不是在数：

- 纯理论计算量
- 软件 wall-clock
- 每个模块内部所有细枝末节

所以只要结构改动减少了：

- stall
- bubble
- awkward handshake
- FC 重排开销

那总拍数下降是完全可能的。

## 12. 为什么现在可以不靠 PLL

相关文件：

- [`../../de1_soc/soc_system_top.sv`](../../de1_soc/soc_system_top.sv)
- [`../../de1_soc/soc_system.sdc`](../../de1_soc/soc_system.sdc)

当前状态是：

- `soc_system_top.sv` 直接把 `CLOCK_50` 接给 `soc_system`
- `soc_system.sdc` 直接约束 `clock_50 = 20 ns`
- fitter 里 PLL 使用是 `0 / 6`

也就是说，当前这版不是靠 PLL “躲过 timing”，而是靠 RTL 结构整理本身把设计做稳了。

## 13. 一句话总结

如果要用一句话概括这次 Fmax 提升：

> 不是算法变了，而是把控制启动、SA 入口、FC 重排、argmax 这些容易形成长组合路径的地方拆拍、打寄存器边界，或者搬进存储组织里了。

换成更工程化一点的话：

- `top_fsm`：把启动控制切成两拍
- `conv_top`：在 SA 边界前插 pipeline cut
- `top_sram_B`：用 M10K 换掉 FC 读侧重排
- `argmax`：用小状态机换掉宽比较树

## 14. 继续往上提频时最值得看的地方

如果后面还想继续往上推频率，下一轮最值得继续盯的是：

- conv feed / SA 边界
- FC 读入和 FC 尾部
- SRAM 组织是否还能进一步 bank 化 / buffer 化

而不是优先再折腾 MMIO wrapper。

## 继续阅读

- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)
- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
