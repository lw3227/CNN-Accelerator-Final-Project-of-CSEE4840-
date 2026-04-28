# MMIO 接口说明

这份文档讲的是：

- 现在 MMIO 为什么是 32-bit word 索引
- 地址为什么看起来那么大
- register map 怎么构造
- scratchpad / config space 是怎么分开的
- 数据到底是怎么被传到 accelerator 里的

英文原版在：

- [../MMIO_INTERFACE_GUIDE.md](../MMIO_INTERFACE_GUIDE.md)

## 1. 当前 MMIO 合同是什么

关键文件：

- [`../../include/cnn_mmio_regs.h`](../../include/cnn_mmio_regs.h)
- [`../../input/RTL/interface/cnn_mmio_interface.v`](../../input/RTL/interface/cnn_mmio_interface.v)

当前这版已经不是旧的 16-bit halfword 语义，而是：

- **32-bit Avalon-MM slave**
- **32-bit word 编址**
- **memory space 和 config space 用 `address[18]` 分开**

也就是：

- `address[18] = 0`：scratchpad memory
- `address[18] = 1`：config/status registers

## 2. 地址为什么看起来这么大

这类地址要分三层看。

### 第一层：主机 mmap 的地址范围

host 侧默认把一整段 MMIO 空间映射出来：

- `CNN_MMIO_MAP_SPAN_BYTES = 4 * 1024 * 1024`

这只是为了让 `/dev/mem + mmap` 操作简单稳定，不代表 FPGA 里真的有 4MB BRAM。

### 第二层：逻辑地址命名空间

wrapper 对外暴露了一个“逻辑地址空间”：

- 低半区：memory space
- 高半区：config space

因为 `address[18]` 用来分区，所以逻辑上会看到：

- `0x00000..0x3FFFF`：memory
- `0x40000..0x4001F`：config

这还是“逻辑空间”，不是说 memory 真的这么大。

### 第三层：FPGA 里实际实现的 scratchpad

真正的 BRAM 大小由 `cnn_mmio_interface.v` 里的参数决定：

- `MEM_AW = 13`
- `MEM_WORDS = 1 << 13 = 8192`

所以实际 scratchpad 是：

- `8192` 个 32-bit words
- 一共 `32 KiB`

所以这就是为什么你会看到：

- mmap span 很大
- 逻辑地址空间也不小
- 但真正实现的 BRAM 只有 32KiB

## 3. Host 侧地址是怎么构造的

关键 helper 在：

- [`../../include/cnn_mmio_regs.h`](../../include/cnn_mmio_regs.h)

### config 地址

```c
cnn_mmio_cfg_addr(reg_idx)
```

本质上是：

```text
CFG_SPACE_BIT | reg_idx
```

也就是把 `address[18]` 置成 `1`，表示“我要访问寄存器区”。

### memory 地址

```c
cnn_mmio_mem_addr(word_addr)
```

本质上是：

```text
MEM_SPACE_BIT | word_addr
```

也就是把 `address[18]` 置成 `0`，表示“我要访问 scratchpad”。

## 4. 为什么 register map 看起来只有一小段

因为寄存器本身不多。

config space 里真正用的只是 `0..31` 这些 slot，主要包括：

- `CONTROL`
- `STATUS`
- `CONV_CFG_BASE / LEN`
- `CONV_WT_BASE / LEN`
- `FC_BIAS_BASE / LEN`
- `FCW_BASE / LEN`
- `IMAGE_BASE / LEN`
- `PREDICT`
- `IF_ERROR`
- `PROFILE_*`
- `LAST_WRITE`
- `MAGIC`

## 5. 当前寄存器语义的重点

### `CONTROL`

控制 host 触发：

- model load
- inference

### `STATUS`

低 16 位里保留了原来兼容的状态位语义，常见关心的是：

- busy
- model_loaded
- predict_done
- predict_class

### `IF_ERROR`

接口错误位，当前主要用于：

- busy 时又发 model load
- busy 时又发 infer
- model 没 load 完就 infer
- replay 读出实际 BRAM 范围

## 6. 为什么现在是 32-bit，但状态还保留低 16 位风格

因为这次改动的目标是：

- 把 scratchpad / host contract 统一成 32-bit
- 但不要把已有 host 工具、旧寄存器位定义全打碎

所以现在是：

- 总线宽度：32-bit
- scratchpad 单位：32-bit word
- 但 control/status ABI 仍尽量兼容旧低 16 位语义

这也是你在代码里会看到“看起来有点 mixed-width”的原因。

## 7. 当前默认 scratchpad 布局

默认布局在：

- [`../../include/cnn_mmio_regs.h`](../../include/cnn_mmio_regs.h)

| 段 | base(word) | len(word) | bytes |
| --- | ---: | ---: | ---: |
| conv_cfg | `0` | `45` | `180` |
| conv_wt | `45` | `225` | `900` |
| fc_bias | `270` | `10` | `40` |
| fcw | `280` | `864` | `3456` |
| image | `1144` | `1024` | `4096` |

## 8. model load 时怎么传

host 侧大致会做：

1. 往 scratchpad 写 `conv_cfg`
2. 往 scratchpad 写 `conv_wt`
3. 往 scratchpad 写 `fc_bias`
4. 往 scratchpad 写 `fcw`
5. 写对应的 `BASE / LEN` 寄存器
6. 写 `CONTROL` 触发 model load

然后 wrapper 的 replay engine 会按这些 base/len：

- 一段一段从 scratchpad 读
- 组成 `system_top` 需要的 `load_valid / load_data / load_last`
- 送进去完成 model preload

## 9. inference 时怎么传

inference 阶段更简单：

1. host 往 scratchpad 的 `image` 区写 1024 words
2. 写 `IMAGE_BASE / IMAGE_LEN`
3. 写 `CONTROL` 触发 infer
4. wrapper 回放 image 数据给 `system_top`
5. accelerator 跑完后在 `STATUS / PREDICT / PROFILE` 里给结果

## 10. 为什么要“先存再回放”

因为 HPS 软件最擅长的是：

- 写内存
- 写寄存器
- 等待状态

而 accelerator 更自然的接口是：

- 一段一段有顺序地收流数据

所以 wrapper 的设计思想是：

- host 先把数据放进 scratchpad
- 再由 RTL 自己稳定地 replay 给 accelerator

这样 host 不用直接手搓流接口时序。

## 11. 真正应该配合看的文件

想看 host 怎么算地址：

- [`../../include/cnn_mmio_regs.h`](../../include/cnn_mmio_regs.h)

想看 host 怎么写寄存器和 scratchpad：

- [`../../tools/cnn_mmio_host.c`](../../tools/cnn_mmio_host.c)

想看 RTL 怎么 decode 地址和 replay：

- [`../../input/RTL/interface/cnn_mmio_interface.v`](../../input/RTL/interface/cnn_mmio_interface.v)

