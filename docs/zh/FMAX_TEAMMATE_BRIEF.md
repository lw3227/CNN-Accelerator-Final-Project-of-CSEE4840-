# Fmax 提升简要说明

这是一份可以直接转给队友的短说明。

## 一句话结论

当前 `submission` 分支已经可以直接跑 `CLOCK_50 = 50 MHz`，不需要 `clk_div2` 或 PLL；当前 slow-corner Fmax 约为 `75.72 MHz`。

对应报告：

- [../../de1_soc/output_files/soc_system.sta.summary](../../de1_soc/output_files/soc_system.sta.summary)
- [../../de1_soc/output_files/soc_system.sta.rpt](../../de1_soc/output_files/soc_system.sta.rpt)

## 这次不是改算法，而是改硬件结构

主要思路是：

- 把同一拍里做太多事的地方拆成多拍
- 在 SA 入口前加寄存器 cut
- 把 FC 读侧重排逻辑搬进存储布局
- 把尾部宽比较树改成小状态机

## 最关键的 4 个 RTL 改动

### 1. `top_fsm.v`：启动拆成两拍

文件：

- [`../../input/RTL/fsm/top_fsm.v`](../../input/RTL/fsm/top_fsm.v)

做法：

- 新增 `runner_prepared`
- 先锁住 `layer/pass/is_fc`
- 下一拍再发 `runner_start`

作用：

- 降低 launch-side control fanout
- 避免下游同拍同时吃“新配置”和“启动边沿”

### 2. `top_fsm.v`：argmax 从宽比较树改成迭代扫描

做法：

- 不再一拍完成 10 路比较
- 改成逐拍扫描 `fc_acc_vec`
- 用 `argmax_best_val` / `argmax_best_idx` 记录当前最优

作用：

- 去掉 FC 尾部的大组合比较链
- 用几拍 latency 换更短的 critical path

### 3. `conv_top.v`：在 SA 前插显式寄存器边界

文件：

- [`../../input/RTL/conv_core/conv_top.v`](../../input/RTL/conv_core/conv_top.v)

做法：

- 把 `active_layer_sel_q`
- `sa_mode_cfg_q`
- `sa_valid_rows_cfg_q`
- `sa_start_pulse_q`
- `sa_a_in_flat_q`
- `sa_b_in_flat_q`

这些控制和 SA 输入 bundle 先在 `conv_top` 本地寄存

作用：

- 切断 `Conv_Buffer -> sa_skew_feeder -> SA input` 前的长组合链
- 让 SA 边界更像标准 pipeline stage

### 4. `top_sram_B.v`：新增 FC-order M10K buffer

文件：

- [`../../input/RTL/SRAM/top_sram_B.v`](../../input/RTL/SRAM/top_sram_B.v)

做法：

- 新增 `fc_input_mem`
- L3 `pass0` 写偶地址
- L3 `pass1` 写奇地址
- FC 顺序读 `0..71`

作用：

- 不再在 FC 读路径上做交错地址重排
- 用一点 RAM 换更简单的 FC read path

## 为什么总 cycle 反而可能更少

这次优化不是“只会加拍”。

虽然某些点上多了一拍，例如：

- `runner_prepared`

但同时也减少了：

- conv 边界上的 stall / bubble
- FC 读侧重排开销
- argmax 尾部的长组合压力

所以最终可能出现：

- 局部多一拍
- 整体 `total_cycles` 反而下降

这不是矛盾，是正常的 pipeline / datapath 整理结果。

## 如果队友只想继续看详细解释

看这份长文档：

- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)
