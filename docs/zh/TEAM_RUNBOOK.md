# 团队运行手册

这份文档是中文的“实际操作版”。它不讲太多历史背景，重点是：

- 怎么重新编译
- 怎么重新上板
- 怎么做最小验证
- web demo 怎么启动
- 出问题先查哪里

英文完整版本在：

- [../TEAM_RUNBOOK.md](../TEAM_RUNBOOK.md)

## 1. 本地快速健康检查

在 repo 根目录先跑：

```bash
python de1_soc/build_soc_system.py --check
python -m compileall gesture_runtime web_demo tools
```

## 2. 重新编译 FPGA 工程

```bash
python de1_soc/build_soc_system.py
```

关键输入文件：

- [`../../de1_soc/soc_system.qsys`](../../de1_soc/soc_system.qsys)
- [`../../de1_soc/soc_system_top.sv`](../../de1_soc/soc_system_top.sv)
- [`../../de1_soc/soc_system.sdc`](../../de1_soc/soc_system.sdc)

关键输出文件：

- [`../../de1_soc/output_files/soc_system.sof`](../../de1_soc/output_files/soc_system.sof)
- [`../../de1_soc/output_files/soc_system.rbf`](../../de1_soc/output_files/soc_system.rbf)

## 3. 重新编译 HPS 侧工具

本地主机如果只是维护源码，一般先做：

```bash
make -C tools
```

真正板子上还会再同步并重新 `make` 一次。

## 4. 连板检查

```bash
python web_demo/check_board.py
```

这一步会帮你确认：

- 配置文件里的板子 IP 是否可达
- SSH 是否正常
- 远端 repo 是否存在

## 5. 烧 FPGA 并准备 web demo 运行环境

常用的一步到位命令：

```bash
python tools/prepare_web_demo.py --program-sof --build-tools
```

它通常会处理这些事情：

- 用 `quartus_pgm` 烧当前 `.sof`
- 检查板子网络
- 同步或准备板端工具
- 在远端构建 `tools/`

## 6. 最小板端验证流程

最小验证建议顺序：

### 先看状态

```bash
./tools/hps_mmio_status 0xff200000
```

### 只加载模型

```bash
./tools/hps_mmio_load_model 0xff200000 Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test
```

### 跑一个端到端 case

```bash
./tools/hps_mmio_run_case 0xff200000 Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_7_test
```

### 或者只跑一次预测

```bash
./tools/hps_mmio_predict 0xff200000 Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test
```

## 7. 启动 web demo

```bash
python web_demo/app.py
```

然后浏览器访问 Flask 提示的本地地址。

## 8. 最常见的故障分流

### `check_board.py` 不通

优先检查：

- 板子是否开机
- 直连网口 IP 是否还对
- SSH key / known_hosts
- `web_demo/demo_config.json`

### `load_model` 失败

优先检查：

- `csr_base` 是否正确
- 当前 bitstream 是否真的是这次新编的
- MMIO wrapper 是否和 `include/cnn_mmio_regs.h` 一致

### `predict` 失败但 `status` 正常

优先检查：

- preload 路径和 case 路径是否匹配
- 板端 `tools/` 是否重新编译
- 是否仍在跑旧 bitstream

### timing / 频率相关问题

先看：

- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)
- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)

## 9. 推荐的每日最短流程

```bash
python de1_soc/build_soc_system.py --check
python web_demo/check_board.py
python tools/prepare_web_demo.py --program-sof --build-tools
python web_demo/app.py
```

如果这条最短链能通，再去做 deeper debug。

