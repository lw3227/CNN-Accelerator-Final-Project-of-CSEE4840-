# 中文文档入口

这一组文档是 `submission` 分支的中文交接版，面向需要继续做：

- FPGA / Quartus / Qsys 集成
- HPS + MMIO 上板验证
- web demo 运行与调试
- RTL 结构理解与 timing/Fmax 分析

英文文档仍然保留，作为原始命令和长期参考；中文文档的目标是让队友先把整套结构、流程、文件责任、硬件改动逻辑看明白。

## 建议阅读顺序

1. [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)  
   新同学先做什么，主机环境和板子环境怎么确认
2. [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)  
   重新编译、上板、验证、恢复流程怎么跑
3. [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)  
   哪些目录和文件分别负责什么
4. [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)  
   浏览器到 FPGA 再返回结果的完整软件到硬件链路
5. [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)  
   32-bit MMIO、地址构造、register map、scratchpad 布局、传输语义
6. [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)  
   模型大小、payload 大小、resource budget、timing 报告位置
7. [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)  
   为了把 Fmax 拉回 50MHz 以上，硬件结构具体改了哪里、为什么这样改

可选历史/诊断补充：

- [MODEL_DIAGNOSTICS.md](MODEL_DIAGNOSTICS.md)
- [PROJECT_STATUS_AND_PLAN.md](PROJECT_STATUS_AND_PLAN.md)

## 如果你只关心某一个问题

### “我只想先跑起来”

- [TEAMMATE_SETUP.md](TEAMMATE_SETUP.md)
- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- [../../web_demo/README.md](../../web_demo/README.md)

### “我想知道每个目录和文件是干什么的”

- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)

### “我想知道 browser -> host -> board -> FPGA 这一整条链怎么走”

- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)

### “我想知道 MMIO 里的地址为什么这样设计”

- [MMIO_INTERFACE_GUIDE.md](MMIO_INTERFACE_GUIDE.md)

### “我想知道现在模型有多大、占了多少资源、timing 怎么看”

- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)

### “我想知道为了提频，RTL 到底改了什么”

- [FMAX_OPTIMIZATION_NOTES.md](FMAX_OPTIMIZATION_NOTES.md)

## 英文原版

如果你需要对照英文原文或更完整的旧说明，从这里回跳：

- [../README.md](../README.md)
