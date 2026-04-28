# 从 Web 到 FPGA 的完整流程

这份文档专门讲“数据是怎么一路传过去、又怎么一路传回来的”。

英文原版在：

- [../WEB_TO_FPGA_WORKFLOW.md](../WEB_TO_FPGA_WORKFLOW.md)

## 1. 总流程

```text
浏览器上传图片
  -> Flask 接收
  -> 主机预处理成 64x64x1 int8
  -> 导出成 board-side case folder
  -> SCP 到板子
  -> 板子上运行 hps_mmio_predict / hps_mmio_run_case
  -> /dev/mem mmap MMIO
  -> 写 scratchpad 和寄存器
  -> 触发 MODEL_LOAD / INFER
  -> FPGA wrapper replay 给 system_top
  -> accelerator 跑完
  -> 读回 predict/status/profile
  -> SSH 返回主机
  -> Flask 返回 JSON
  -> 浏览器展示结果
```

## 2. 浏览器到 Flask

入口通常是：

- [`../../web_demo/app.py`](../../web_demo/app.py)

它负责：

- 接收上传的图片
- 调用 CPU 路径和 FPGA 路径
- 把结果整理成网页或 JSON

## 3. 主机端预处理

关键文件：

- [`../../gesture_runtime/preprocess.py`](../../gesture_runtime/preprocess.py)
- [`../../gesture_runtime/case_export.py`](../../gesture_runtime/case_export.py)

主机端会做这些事：

1. 读取上传图片
2. resize / 灰度化 / 量化
3. 变成 accelerator 需要的 `64x64x1 int8`
4. 导出成板端工具能直接消费的 case 目录

这个 case 目录会包含类似：

- 图像 payload
- manifest / label
- 调试用文本

## 4. 主机如何把数据送到板子

关键文件：

- [`../../gesture_runtime/ssh_transport.py`](../../gesture_runtime/ssh_transport.py)
- [`../../gesture_runtime/fpga_service.py`](../../gesture_runtime/fpga_service.py)

主机不会直接碰 FPGA。它是：

1. 通过 SSH 登录板子
2. 通过 SCP/目录同步把 case 和工具同步过去
3. 在板子上执行 `tools/` 里的 C 程序

## 5. 板子上的 C 程序在做什么

关键程序：

- `hps_mmio_status`
- `hps_mmio_load_model`
- `hps_mmio_run_case`
- `hps_mmio_predict`

它们共享的底层库是：

- [`../../tools/cnn_mmio_host.c`](../../tools/cnn_mmio_host.c)

这个底层库负责：

- 打开 `/dev/mem`
- `mmap` 到 `0xff200000`
- 写 scratchpad
- 写 config/status registers
- 触发 `CONTROL` 命令
- 读回 `STATUS / PREDICT / PROFILE / IF_ERROR`

## 6. HPS 怎么碰到 FPGA

这里的关键不是 DDR，而是 MMIO bridge。

当前 base 地址是：

- `0xff200000`

这对应 HPS lightweight bridge 挂出来的 `cnn_mmio_interface`。

也就是说：

- HPS 用户态程序通过 `/dev/mem`
- mmap 到 `0xff200000`
- 对这块地址做 32-bit 读写
- 最终进入 `cnn_mmio_interface.v`

## 7. FPGA wrapper 里发生了什么

关键文件：

- [`../../input/RTL/interface/cnn_mmio_interface.v`](../../input/RTL/interface/cnn_mmio_interface.v)

它做了三件事：

1. 提供 scratchpad memory space
2. 提供 config/status register space
3. 在 host 触发后，把 staged 数据 replay 成 `system_top` 原本需要的流接口

也就是说，HPS 并不是直接一拍一拍喂 accelerator，而是：

- 先把 payload 写进 wrapper 的 scratchpad
- 再写控制寄存器触发一次“回放”
- wrapper 按既定顺序把数据送给 `system_top`

## 8. `system_top` 以后怎么走

进入 accelerator 之后，大致是：

```text
system_top
  -> top_fsm
  -> conv_top
  -> SRAM_A / SRAM_B
  -> FC
  -> argmax
  -> predict_class
```

这些模块的细节分工见：

- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)

## 9. 结果怎么回到浏览器

accelerator 跑完以后：

1. `cnn_mmio_interface` 把 `predict_done / predict_class / profile / error` 放到寄存器里
2. 板端 C 程序读回这些寄存器
3. SSH 把 stdout / 解析结果带回主机
4. Flask 把结果整成 JSON / HTML
5. 浏览器显示最终预测

## 10. 你看这条链时最该盯的文件

如果你要顺着整条链 debug，顺序建议是：

1. `web_demo/app.py`
2. `gesture_runtime/fpga_service.py`
3. `tools/cnn_mmio_host.c`
4. `include/cnn_mmio_regs.h`
5. `input/RTL/interface/cnn_mmio_interface.v`
6. `input/RTL/system_top.v`

