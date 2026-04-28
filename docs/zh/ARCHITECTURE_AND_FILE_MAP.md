# 架构与文件地图

这份文档回答的是：

- 当前这条主线的软件到硬件结构是什么
- 哪个目录负责哪一层
- 哪些文件才是真正该改的 source of truth
- Qsys 生成文件和手写 RTL 的边界在哪里

英文原版在：

- [../ARCHITECTURE_AND_FILE_MAP.md](../ARCHITECTURE_AND_FILE_MAP.md)

## 1. 一屏看完整结构

```text
browser
  -> web_demo/app.py
  -> gesture_runtime/*
  -> SSH/SCP 到板子
  -> 板子上的 tools/*.c
  -> /dev/mem mmap 0xff200000
  -> HPS lightweight bridge
  -> cnn_mmio_interface
  -> system_top
  -> conv / SRAM / FC / argmax RTL
  -> status / profile / predict_class 通过 MMIO 读回
  -> SSH 返回主机
  -> Flask 返回浏览器
```

## 2. 各目录负责什么

| 目录 | 责任 |
| --- | --- |
| `docs/` | 队友文档、架构说明、流程说明 |
| `web_demo/` | Flask 服务、前端页面、配置 |
| `gesture_runtime/` | 主机端预处理、导出 case、SSH/SCP、调用板子 |
| `tools/` | 板端 C 程序和少量主机辅助脚本 |
| `include/` | MMIO 共享头文件、地址常量、host API |
| `input/RTL/` | accelerator 真正 RTL |
| `de1_soc/` | Quartus / Qsys / 板级 top / 生成产物 |
| `Golden-Module/` | 模型文件、hardware-aligned 导出数据 |
| `test_data/` | 本地 mock 和轻量测试 |

## 3. 当前真正的 source of truth

### 浏览器 / host 层

- `web_demo/app.py`
- `web_demo/config.py`
- `web_demo/demo_config.json`

### 主机 runtime 层

- `gesture_runtime/preprocess.py`
- `gesture_runtime/case_export.py`
- `gesture_runtime/demo_compare.py`
- `gesture_runtime/fpga_service.py`
- `gesture_runtime/ssh_transport.py`

### 板端工具层

- `tools/cnn_mmio_host.c`
- `tools/hps_mmio_status.c`
- `tools/hps_mmio_load_model.c`
- `tools/hps_mmio_run_case.c`
- `tools/hps_mmio_predict.c`

### MMIO 协议层

- `include/cnn_mmio_regs.h`
- `include/cnn_mmio_host.h`
- `input/RTL/interface/cnn_mmio_interface.v`

### accelerator RTL 层

- `input/RTL/system_top.v`
- `input/RTL/fsm/top_fsm.v`
- `input/RTL/conv_core/conv_top.v`
- `input/RTL/SRAM/top_sram_B.v`

### Quartus / Qsys 集成层

- `de1_soc/soc_system.qsys`
- `de1_soc/soc_system_top.sv`
- `de1_soc/soc_system.sdc`
- `de1_soc/build_soc_system.py`

## 4. 自定义 IP 是怎么被当成一个整体的

这里最关键的文件是：

- [`../../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl`](../../de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl)

它做的事情是：

1. 声明这个 IP 的名字叫 `cnn_mmio_interface`
2. 声明顶层模块就是 `cnn_mmio_interface`
3. 把一整串 `input/RTL/*.v` 文件作为这个组件的一部分打包进去
4. 定义 clock/reset/Avalon-MM slave 等接口

所以：

- `input/RTL/*.v` 是原始 RTL
- `cnn_mmio_interface_hw.tcl` 是“把这些 RTL 包装成一个 Platform Designer 组件”的定义文件
- `soc_system.qsys` 里实例化的是这个组件

## 5. 哪些文件是手写的，哪些是生成的

### 你应该直接改的

- `input/RTL/**`
- `include/**`
- `tools/**`
- `gesture_runtime/**`
- `web_demo/**`
- `de1_soc/soc_system.qsys`
- `de1_soc/soc_system_top.sv`
- `de1_soc/soc_system.sdc`
- `de1_soc/ip/cnn_mmio_interface/cnn_mmio_interface_hw.tcl`

### 不应该手改，或者改了也会被覆盖的

- `de1_soc/soc_system/synthesis/**`
- `de1_soc/soc_system.sopcinfo`
- `de1_soc/soc_system/soc_system.xml`
- `de1_soc/soc_system/soc_system.html`

这些是 Qsys / Quartus 生成产物。

## 6. 如果你要改某件事，应该先改哪里

| 你要改什么 | 先看哪里 |
| --- | --- |
| Web 行为 | `web_demo/app.py` |
| 图像预处理 | `gesture_runtime/preprocess.py` |
| SSH/SCP / 调板子流程 | `gesture_runtime/ssh_transport.py`, `gesture_runtime/fpga_service.py` |
| MMIO 地址、寄存器含义 | `include/cnn_mmio_regs.h`, `cnn_mmio_interface.v` |
| 板端访问逻辑 | `tools/cnn_mmio_host.c` |
| conv / FC / SRAM 逻辑 | `input/RTL/**` |
| Qsys 连接和地址映射 | `de1_soc/soc_system.qsys` |
| 板级 IO / 时钟 / top | `de1_soc/soc_system_top.sv` |

