# Fmax 优化说明

这份文档是给硬件同学看的，重点回答：

- 为了把设计重新稳定跑回 `50 MHz` 以上，到底改了哪些硬件结构
- 改动发生在哪些模块
- 这些改动为什么有助于 timing
- 哪些改动是主要贡献，哪些只是顺手清理

英文原版在：

- [../FMAX_OPTIMIZATION_NOTES.md](../FMAX_OPTIMIZATION_NOTES.md)

## 1. 先看最终结果

当前 `submission` 分支的关键结果是：

- 目标时钟：`clock_50 = 50 MHz`
- 当前 slow-corner Fmax：`75.72 MHz`
- 所以已经不需要再靠 `clk_div2` 或 PLL 才能过

报告位置：

- [`../../de1_soc/output_files/soc_system.sta.summary`](../../de1_soc/output_files/soc_system.sta.summary)
- [`../../de1_soc/output_files/soc_system.sta.rpt`](../../de1_soc/output_files/soc_system.sta.rpt)

## 2. 主要改动集中在哪些硬件模块

不是全项目都大改，真正和 Fmax 关系最大的主要是这四块：

| 模块区域 | 文件 | 改动类型 |
| --- | --- | --- |
| 顶层控制序列器 | `input/RTL/fsm/top_fsm.v` | 启动时序、argmax 结构 |
| conv 前端和 SA 入口 | `input/RTL/conv_core/conv_top.v` | 把 layer-dependent 控制和 SA 输入打拍 |
| SRAM_B 到 FC 的读路径 | `input/RTL/SRAM/top_sram_B.v` | 新增 FC-order M10K reorder buffer |
| MMIO wrapper | `input/RTL/interface/cnn_mmio_interface.v` | 32-bit 清理，简化 wrapper |

如果你是硬件同学，优先从这四个文件看。

## 3. 原来最值得担心的路径长什么样

历史上的 fabric timing 线索保存在：

- [`../../de1_soc/output_files/fabric_timing_summary_latest.txt`](../../de1_soc/output_files/fabric_timing_summary_latest.txt)

里面出现过的路径形状像：

- `conv_engine_ctrl.rd_col_r[4] -> sa_skew_feeder.delay[36][3]`
- `pool_core.layer_sel_d[0] -> sa_skew_feeder.delay[36][3]`

这类路径说明问题主要不在 MMIO，而在：

- conv 控制信号
- layer 选择信号
- skew feeder / SA feed 路径

所以优化方向自然就变成：

1. 把控制信号更早、更本地化地锁住
2. 给 SA 入口前面加明确的寄存器边界
3. 把 FC 读侧的重排逻辑搬到存储组织里
4. 把宽组合比较变成小状态机

## 4. `top_fsm.v`：在真正发 `runner_start` 前多给一拍准备

关键标识符：

- `runner_prepared`
- `runner_started`
- `runner_layer_sel`
- `runner_pass_id`
- `runner_is_fc`
- `runner_start`

### 改动前的问题

原来的控制序列更接近：

```text
切换到下一层
  -> 同时决定 layer/pass/fc_mode
  -> 同时打出 start
```

也就是说，下游模块在同一个周期里既要看到新的配置，又要吃到启动脉冲。

### 现在的结构

现在变成：

```text
先切换状态并锁住 control
  -> 下一拍再打 runner_start
```

### 为什么这有用

- 把 control decode 和 start launch 拆成两拍
- 降低 sequencer 到 datapath 的控制扇出压力
- 给下游模块一个完整周期去吸收新的 layer/pass/fc 配置

这个改动的本质是：

`用 1 拍延迟换掉 launch-side 的长组合路径`

## 5. `top_fsm.v`：把 argmax 从“一拍宽比较”改成“小状态机扫描”

关键标识符：

- `ST_ARGMAX`
- `argmax_scan_idx`
- `argmax_best_idx`
- `argmax_best_val`
- `fc_acc_vec`

### 改动前的问题

如果最后要在一个周期内从 10 个 FC 输出里直接选最大值，很容易形成：

- 宽比较树
- 大量比较器级联
- 最终 `predict_class` 的临界组合路径

### 现在的结构

现在的做法是：

- 每个周期只看一个 channel
- 把当前最好值存进寄存器
- 扫完 10 个 channel 后再得出最终结果

### 为什么这有用

- 把一个宽比较网络变成一个很小的迭代状态机
- 关键路径从“多路 compare tree”变成“单次 compare + 寄存器写回”

这是非常典型的 timing tradeoff：

`多花几拍，换掉最后一拍的大组合比较`

## 6. `conv_top.v`：把 layer-dependent 控制和 SA 输入尽量在本地锁住

关键标识符：

- `active_layer_sel_q`
- `sa_mode_cfg_q`
- `sa_valid_rows_cfg_q`
- `sa_start_pulse_q`
- `sa_a_in_flat_q`
- `sa_b_in_flat_q`

### 改动前的问题

原来的 conv 前端更容易出现这种路径：

```text
layer_sel / 控制解码
  -> Conv_Buffer
  -> sa_skew_feeder
  -> systolic array 入口
```

也就是 layer 相关的变化会穿过更多层逻辑，最后才到 SA 边界。

### 现在的结构

现在在 `conv_top` 里把这些东西先寄存起来：

- active layer select
- SA mode
- valid rows
- start pulse
- A 输入 bundle
- B 输入 bundle

也就是给 SA 前面明确加了一层寄存器边界。

### 为什么这有用

- 把 layer-dependent 影响限制在 `conv_top` 内部
- 把跨模块组合深度切短
- 让 SA 看到的是更像 pipeline stage 的输入，而不是同拍一路传过来的组合结果

这部分是当前分支最核心的 datapath timing 改动。

## 7. `conv_top.v`：把 frame rearm / backend idle 的边界做得更显式

关键标识符：

- `backend_idle`
- `backend_idle_d`
- `frame_rearm`
- `frame_rearm_out`
- `frame_done_out`

### 改动前的问题

如果相邻 layer/pass 之间的重启时机靠更隐式的组合条件判断，容易带来：

- stale state 传播
- producer/consumer 边界不清晰
- synthesis 很难把这些边界当作好切的同步点

### 现在的结构

现在把：

- backend idle
- frame done
- frame rearm

这些边界都做成更清楚的同步控制信号。

### 为什么这有用

这类改动不一定单独带来巨大 Fmax 提升，但它会让：

- 相邻 pass/layer 的边界更干净
- pipeline 化更可靠
- 时序和功能正确性一起更稳

## 8. `top_sram_B.v`：多用一个 M10K，把 FC 读侧重排逻辑挪走

关键标识符：

- `fc_input_mem`
- `fc_buf_write_mirror`
- `fc_buf_read_txn`
- `fc_buf_wr_addr`
- `fc_buf_rd_count`

### 改动前的问题

原来的 FC 输入更像：

```text
L3 pass0 / pass1 按原顺序存
  -> FC 读的时候再通过地址逻辑拼回正确顺序
```

这意味着 FC active read path 上要承担更多：

- interleave address logic
- reorder logic

### 现在的结构

现在新加了一块专门给 FC 用的 reorder buffer：

- L3 pass0 写到偶地址
- L3 pass1 写到奇地址
- FC 侧直接顺序读 `0..71`

### 为什么这有用

- FC 读路径变成单纯顺序读
- 复杂的重排不再挂在 FC active path 上
- 把复杂度搬到“写入时如何组织存储”上，通常比在读路径上实时算地址更好做 timing

这是这条分支最典型的策略：

`用多一点片上存储，换更简单的组合逻辑`

而这在当前资源分布下也很合理：

- RAM 只用了 `11%`
- DSP 已经用了 `99%`

## 9. `cnn_mmio_interface.v`：这是清理，不是主要 Fmax 来源

关键文件：

- `input/RTL/interface/cnn_mmio_interface.v`
- `include/cnn_mmio_regs.h`
- `include/cnn_mmio_host.h`
- `tools/cnn_mmio_host.c`

### 改了什么

- scratchpad 改成 32-bit word addressing
- replay 直接送 32-bit word
- 去掉旧的 low/high halfword stitch
- 保留 low-16-bit 的 control/status ABI 兼容语义

### 为什么它不是主要提频来源

因为真正最紧的 fabric path 不是这块 wrapper，而是 conv/feed/FC 这条主链。

但这个改动仍然有价值，因为它让：

- host 协议更干净
- wrapper 更容易理解
- MMIO 文档和软件行为更一致

## 10. 为什么现在可以不用 PLL

相关文件：

- [`../../de1_soc/soc_system_top.sv`](../../de1_soc/soc_system_top.sv)
- [`../../de1_soc/soc_system.sdc`](../../de1_soc/soc_system.sdc)

当前状态是：

- `soc_system_top.sv` 直接把 `CLOCK_50` 喂给 `soc_system`
- `soc_system.sdc` 直接约束 `clock_50 = 20ns`
- fitter 里 PLL 使用是 `0 / 6`

也就是说，这条分支当前是靠 RTL 结构整理和 pipeline/M10K tradeoff 把 timing 做稳的，不是靠额外时钟生成器“躲过去”。

## 11. 结论

如果你要一句话概括这次 Fmax 优化：

**主要不是“算法变了”，而是把控制 launch、conv 入口、FC 读重排、argmax 这些容易形成长组合路径的地方拆开、打拍、或者搬进存储组织里了。**

如果你要继续往上提频，下一轮最值得继续盯的还是：

- conv feed / SA 边界
- FC 路径
- SRAM 组织与 buffer 化

而不是先去折腾 MMIO wrapper。

