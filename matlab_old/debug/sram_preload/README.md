# SRAM Preload Test Data

每个 case（paper/rock/scissors）目录下的文件，按 SRAM_ADDRESS_MAP.md 的布局生成。

所有文件均为十进制 signed int 文本格式（每行一个值），使用 `$fscanf(fd, "%d\n", val)` 加载。
文件名后缀 `_Nw` 表示映射到 SRAM 后占 N 个 32-bit word，不代表文件按 word 存储。

## Preload 输入文件（host → SRAM_A）

按 preload 3 段顺序，每文件内的值按地址顺序排列，每行一个 signed int 值。

| 文件 | 内容 | 值数 | 32-bit words | 对应地址 |
|------|------|------|-------------|---------|
| `sram_a_cfg_48w.txt` | 所有层 cfg 拼接 | 48 | 48 | 0x000-0x02F |
| `sram_a_wt_513w.txt` | 所有层 weight 拼接（int8 逐字节） | 2052 | 513 | 0x030-0x230 |
| `sram_a_image_1024w.txt` | 64×64 input image（int8 逐字节） | 4096 | 1024 | 0x231-0x630 |

### cfg 文件内部顺序（48 words）

```
word  0-8:   L1 cfg         (bias×4 + M×4 + sh_packed)
word  9-17:  L2 cfg pass0
word 18-26:  L2 cfg pass1
word 27-35:  L3 cfg pass0
word 36-44:  L3 cfg pass1
word 45-47:  FC bias        (eff_bias0, eff_bias1, eff_bias2)
```

cfg 文件里每行是一个 32-bit signed int（十进制），用 `$fscanf(fd, "%d\n", val)` 加载。

### weight 文件内部顺序（2052 bytes = 513 words）

```
byte    0-35:    L1 weight          (36 int8 = 9 words)
byte   36-179:   L2 weight pass0    (144 int8 = 36 words)
byte  180-323:   L2 weight pass1    (144 int8 = 36 words)
byte  324-611:   L3 weight pass0    (288 int8 = 72 words)
byte  612-899:   L3 weight pass1    (288 int8 = 72 words)
byte  900-2051:  FC weight interleaved (1152 int8 = 288 words, 每 word = {w0,w1,w2,pad})
```

weight 文件里每行是一个 signed int8 值，TB 加载时需要按 4 bytes 打包成 32-bit word。

### image 文件

每行一个 signed int8 值（64×64 = 4096 值），TB 加载时按 layer_sel 打包。

## 期望输出文件（用于 SRAM 写回验证）

| 文件 | 内容 | 值数 | 说明 |
|------|------|------|------|
| `expected_sram_b_l1_pool_961w.txt` | L1 pool output | 3844 int8 | 写入 SRAM_B 0x000-0x3C0 |
| `expected_sram_a_l2_pool_392w.txt` | L2 pool output (两 pass 拼接) | 1568 int8 | 写入 SRAM_A 0x231-0x3B8 |
| `expected_sram_b_l3_pool_72w.txt` | L3 pool output (两 pass 拼接) | 288 int8 | 写入 SRAM_B 0x000-0x047 |
| `expected_fc_out_i32_3.txt` | FC accumulator 期望值 | 3 int32 | argmax 取分类结果 |

## 使用方式

```verilog
// 在 Verilog TB 中加载 (所有文件统一用 $fscanf):
fd = $fopen("matlab/debug/sram_preload/paper/sram_a_cfg_48w.txt", "r");
for (i = 0; i < 48; i = i + 1) begin
    scan = $fscanf(fd, "%d\n", val);
    cfg_mem[i] = val;           // int32, 直接作为 1 个 SRAM word
end

fd = $fopen("matlab/debug/sram_preload/paper/sram_a_wt_513w.txt", "r");
for (i = 0; i < 2052; i = i + 4) begin
    scan = $fscanf(fd, "%d\n", b0);  // int8
    scan = $fscanf(fd, "%d\n", b1);
    scan = $fscanf(fd, "%d\n", b2);
    scan = $fscanf(fd, "%d\n", b3);
    wt_mem[i/4] = {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};  // 4 bytes → 1 word
end
```

- cfg 文件：int32 逐 word，每行直接对应 1 个 SRAM word
- weight / image / pool 文件：int8 逐字节，TB 加载时需按 4 bytes 打包成 1 个 SRAM word
