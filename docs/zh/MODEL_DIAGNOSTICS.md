# 模型诊断说明

这份文档是当前 web-demo 验证路径下的一个诊断快照，不是主运行手册。

英文原版在：

- [../MODEL_DIAGNOSTICS.md](../MODEL_DIAGNOSTICS.md)

## 当前结论

这份快照记录的是某一阶段的内置样例验证结果：

- `digit_0_test` 到 `digit_9_test`
- 使用和 web 上传相同的整体调用链

当时的诊断现象是：

- 大部分 case 已经通过
- 剩余失败 case 更像模型本身区分度不足或导出 checkpoint 差异
- 而不像纯粹的 transport / MMIO / HPS-FPGA 不一致

## 为什么这份文档还保留

它的价值主要是：

- 告诉队友“不是所有错误都一定是硬件接口 bug”
- 记录 CPU 和 FPGA 路径在某些 case 上的分歧现象
- 给后面继续做模型质量诊断的人留一个起点

## 怎么使用这份文档

如果你现在是在做：

- bring-up
- MMIO debug
- 上板验证

先不要从这份文档开始看，先看：

- [README.md](README.md)
- [TEAM_RUNBOOK.md](TEAM_RUNBOOK.md)
- [WEB_TO_FPGA_WORKFLOW.md](WEB_TO_FPGA_WORKFLOW.md)

如果你现在已经确认系统通了，但怀疑模型效果本身，再回来看这份文档。

