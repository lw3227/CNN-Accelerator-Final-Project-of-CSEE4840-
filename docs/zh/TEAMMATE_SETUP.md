# 队友上手说明

这份文档是给第一次接手这个分支的同学看的，目标是先把环境和角色分清楚，再进入实际构建和上板。

更完整的命令式操作请看：

- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- 英文原版：[../TEAMMATE_SETUP.md](../TEAMMATE_SETUP.md)

## 1. 你现在接手的是哪条主线

当前验证过的主线是：

`browser -> host Python/Flask -> SSH/SCP -> HPS Linux userspace -> MMIO -> FPGA`

也就是说，系统不是“纯 FPGA top”，而是：

- 主机上跑 Python / Flask / 预处理 / SSH
- 板子上的 HPS Linux 跑 `tools/` 里的 C 程序
- HPS 通过 MMIO 把数据送进 FPGA wrapper
- FPGA wrapper 再把 staged 数据 replay 给 accelerator

## 2. 主机上需要什么

最关键的是这几类工具：

- Python 3
- Quartus Lite / Qsys / `quartus_pgm`
- `make`
- SSH 连板能力

建议先在 repo 根目录做两个检查：

```bash
python de1_soc/build_soc_system.py --check
python -m compileall gesture_runtime web_demo tools
```

如果这两步通过，说明：

- Quartus 相关工具能找到
- Python 侧脚本至少能正常 import

## 3. 板子侧需要什么

当前板子侧假设是：

- DE1-SoC 已经能启动 HPS Linux
- 板子和主机之间有直连网口
- 主机能通过 SSH 登录板子
- 远端 repo 路径默认是 `/root/cnn_acc_hps`

配置入口通常在：

- [`../../web_demo/demo_config.json`](../../web_demo/demo_config.json)
- [`../../web_demo/config.py`](../../web_demo/config.py)

## 4. 先搞清楚谁在负责什么

- `web_demo/`：浏览器和 Flask API
- `gesture_runtime/`：主机端预处理、导出 case、SSH/SCP、调用板子
- `tools/`：板子上真正去访问 `/dev/mem`、load model、run inference 的 C 程序
- `include/`：MMIO 协议和 host 侧共享头文件
- `input/RTL/`：真正的 accelerator RTL
- `de1_soc/`：Quartus / Qsys / 板级 top

如果你现在还不知道这些目录的关系，下一份直接看：

- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)

## 5. 新同学最先要做的检查

### 主机环境检查

```bash
python de1_soc/build_soc_system.py --check
python web_demo/check_board.py --help
python tools/run_hps_board_flow.py --help
```

### 连板检查

```bash
python web_demo/check_board.py
```

如果这一步失败，先不要碰 RTL，先解决：

- SSH 密钥
- 直连网口 IP
- 板子是否开机
- 远端 repo 路径是否正确

## 6. 你应该先看哪几份文档

建议顺序：

1. [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
2. [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
3. [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)
4. [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)

如果你是做硬件的，再加：

5. [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)
6. [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)

