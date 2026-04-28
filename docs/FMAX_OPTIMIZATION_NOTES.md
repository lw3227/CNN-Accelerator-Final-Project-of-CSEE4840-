# Fmax Optimization Notes

This document is the hardware-design-facing explanation of the timing-driven
RTL changes that remain in the current `submission` branch.

Use it when you need to answer:

- which hardware blocks were changed
- where in the RTL those changes live
- what the old timing problem shape was
- why the new structure is friendlier to `50 MHz`

Current result to keep in mind:

- `clock_50` target: `50 MHz`
- current slow-corner Fmax: `75.72 MHz`
  from [`../de1_soc/output_files/soc_system.sta.rpt`](../de1_soc/output_files/soc_system.sta.rpt)

## 1. The Hardware Areas That Actually Changed

This branch did **not** rewrite the whole accelerator. The important changes are
concentrated in four places:

| Area | Main files | What changed |
| --- | --- | --- |
| system-level control | [`../input/RTL/fsm/top_fsm.v`](../input/RTL/fsm/top_fsm.v) | start sequencing, argmax structure |
| conv frontend / systolic-array feed | [`../input/RTL/conv_core/conv_top.v`](../input/RTL/conv_core/conv_top.v) | registered layer config and one-cycle input pipeline |
| SRAM_B to FC path | [`../input/RTL/SRAM/top_sram_B.v`](../input/RTL/SRAM/top_sram_B.v) | added dedicated FC-order M10K buffer |
| MMIO wrapper / preload path | [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v) | 32-bit cleanup, simpler wrapper contract |

If you are reviewing hardware structure, start from those four files.

## 2. Baseline Structure Before Thinking About Timing

The relevant fabric path is roughly:

```text
top_fsm
  -> layer/pass/fc control
  -> conv_top
  -> input_row_aligner
  -> Conv_Buffer
  -> sa_skew_feeder
  -> systolic-array datapath / PE MACs
  -> pool / SRAM writeback
  -> SRAM_B
  -> FC input path
  -> FC output vector
  -> argmax
```

The branch timing work mainly attacked three kinds of problems:

1. control fanout launched too late and too widely
2. data reordering happening in active datapaths instead of at storage
3. wide one-cycle combinational decisions sitting on the critical path

## 3A. What "Structural Optimization" Means Here

In this branch, "structural optimization" does **not** mean changing the model,
kernel sizes, or channel counts.

It means changing things such as:

- where register boundaries sit
- whether control launch and start pulse happen in the same cycle
- whether a consumer sees a same-cycle combinational bundle or a registered one
- whether data reordering happens on an active read path or inside memory layout

In short:

> the work was about reducing how much logic had to settle in one cycle

That is why many of the changes look small in code but are significant in
timing shape: a single extra register, buffer, or FSM phase can cut a long
cross-module combinational chain into two short ones.

## 3. Timing Evidence That Motivated The Changes

Historical fabric-only timing snapshots are kept in:

- [`../de1_soc/output_files/fabric_timing_summary_latest.txt`](../de1_soc/output_files/fabric_timing_summary_latest.txt)

Older fabric-critical paths included shapes such as:

- `conv_engine_ctrl.rd_col_r[4] -> sa_skew_feeder.delay[36][3]`
- `pool_core.layer_sel_d[0] -> sa_skew_feeder.delay[36][3]`

These are not MMIO-side paths. They point at the conv / feed / control region.
That is why the branch timing work focused on:

- pushing control registration closer to the conv block
- inserting a clean launch-preparation cycle
- reducing FC-side read reordering logic
- moving complexity into memory organization where possible

## 4. `top_fsm.v`: Add A Preparation Stage Before Launch

File:

- [`../input/RTL/fsm/top_fsm.v`](../input/RTL/fsm/top_fsm.v)

Key identifiers:

- `runner_prepared`
- `runner_started`
- `runner_layer_sel`
- `runner_pass_id`
- `runner_is_fc`
- `runner_start`

### What changed structurally

Before this cleanup, a layer transition could effectively do both of these in
the same immediate control action:

- choose the next layer / pass / FC mode
- pulse `runner_start`

Now the FSM gives the datapath one full cycle to settle the control values
before asserting the start pulse. In other words:

```text
old:
  state transition -> new control selection -> runner_start

new:
  state transition -> latch control -> next cycle runner_start
```

### Why this helps

- the launch-side control fanout is smaller per cycle
- downstream blocks do not need to absorb "configuration decode" and "start
  edge" in the same cycle
- this creates a cleaner synchronous boundary between sequencer and datapath

This is a classic trade:

- spend `1` cycle of latency
- reduce control-to-datapath critical path pressure

## 5. `top_fsm.v`: Replace The Wide Argmax With An Iterative Argmax

File:

- [`../input/RTL/fsm/top_fsm.v`](../input/RTL/fsm/top_fsm.v)

Key identifiers:

- `ST_ARGMAX`
- `argmax_scan_idx`
- `argmax_best_idx`
- `argmax_best_val`
- `fc_acc_vec`

### What changed structurally

The branch no longer tries to decide the winning class with a one-cycle
multi-way comparator tree. Instead it scans one FC output channel per cycle and
keeps the current best value in registers.

```text
old:
  fc_acc_vec[0..9] -> wide compare network -> predict_class

new:
  fc_acc_vec[i] -> compare against argmax_best_val -> update registers
  repeat over multiple cycles
```

### Why this helps

- wide compare trees are timing hotspots
- the result is small-state, low-fanout logic instead of a large final compare
- the FC stage now hands off to a tiny sequential argmax block instead of a
  dense one-cycle decision

This is a good example of:

`trade a few cycles for a much shorter worst-case combinational path`

## 5A. Why Total Cycle Count Can Still Go Down

It is easy to assume that once the branch adds extra sequencing, the total
inference cycle count must go up. That is not always true.

The reason is that the branch does **two different things at once**:

1. it adds a few deliberate stages
2. it removes longer-path stalls, bubbles, and active-path complexity elsewhere

Examples in this branch:

- `runner_prepared` adds a clean preparation cycle before launch
- the conv-side register cut reduces pressure at the SA boundary
- the FC-order buffer removes active read-side reordering logic
- the iterative argmax removes a dense tail-end compare tree

So the final result can be:

- a few places spend one more cycle locally
- the full inference path spends fewer cycles overall

That is consistent with the way `profile_total_cycles` is counted in
[`../input/RTL/fsm/top_fsm.v`](../input/RTL/fsm/top_fsm.v): it measures active
inference-state residency, not abstract algorithmic work or board-level wall
clock time.

## 6. `conv_top.v`: Register Layer-Dependent Configuration Near The Consumer

File:

- [`../input/RTL/conv_core/conv_top.v`](../input/RTL/conv_core/conv_top.v)

Key identifiers:

- `active_layer_sel_q`
- `sa_mode_cfg_q`
- `sa_valid_rows_cfg_q`
- `sa_start_pulse_q`
- `sa_a_in_flat_q`
- `sa_b_in_flat_q`

### What changed structurally

The conv wrapper now locally registers both:

- layer-dependent control
- actual SA input vectors

That means the systolic-array side sees registered versions of:

- decoded layer mode
- valid-row information
- start pulse
- A/B input bundles

instead of consuming a longer same-cycle chain from upstream selection and
buffering logic.

### Why this helps

The previous pressure point was roughly:

```text
layer_sel / control decode
  -> Conv_Buffer
  -> skew/feed path
  -> systolic array input / MAC boundary
```

The current structure inserts a deliberate register cut before the array-facing
interface, which:

- localizes `layer_sel` effects inside `conv_top`
- reduces cross-module combinational depth
- gives the SA boundary a more regular, pipeline-like contract

This is the most important datapath-side timing cleanup in the branch.

Another way to say it:

```text
old:
  upstream selection/buffering -> same-cycle SA-facing consume

new:
  upstream selection/buffering -> local conv_top registers
  next cycle                   -> SA-facing consume
```

So the array no longer has to absorb a long same-cycle chain from several
upstream blocks.

## 7. `conv_top.v`: Clean Up Frame Rearm And Backend Idle Boundaries

File:

- [`../input/RTL/conv_core/conv_top.v`](../input/RTL/conv_core/conv_top.v)

Key identifiers:

- `backend_idle`
- `backend_idle_d`
- `frame_rearm`
- `frame_rearm_out`
- `frame_done_out`

### What changed structurally

The control boundary around frame draining and re-arming is more explicit now.
Instead of letting adjacent passes/layers depend on looser implicit conditions,
the block exposes cleaner registered handshake-style boundaries for:

- backend becoming idle
- frame drain completion
- safe re-arm timing

### Why this helps

This is partly a correctness cleanup, but it also helps timing because:

- producer/consumer phase boundaries are easier to pipeline
- it prevents stale-state dependencies between adjacent passes
- it gives synthesis a clearer synchronous cut than mixed implicit state

It is not the single biggest Fmax gain by itself, but it makes the rest of the
pipeline staging easier to trust.

## 8. `top_sram_B.v`: Spend One Extra M10K To Simplify The FC Read Path

File:

- [`../input/RTL/SRAM/top_sram_B.v`](../input/RTL/SRAM/top_sram_B.v)

Key identifiers:

- `fc_input_mem`
- `fc_buf_write_mirror`
- `fc_buf_read_txn`
- `fc_buf_wr_addr`
- `fc_buf_rd_count`

### What changed structurally

This branch moved FC input reordering away from active FC read-side address
logic and into a dedicated reorder buffer.

The new structure is:

```text
L3 pass0 output -> even addresses in fc_input_mem
L3 pass1 output -> odd addresses in fc_input_mem
FC read side    -> sequential 0..71 read
```

Instead of:

```text
store in pass order
  -> reconstruct desired FC order while reading
```

The important point is not that interleave information disappeared. It did not.
It moved from:

- "reconstruct on the FC read path"

to:

- "encode the desired FC order while writing the mirror buffer"

### Why this helps

- FC read logic becomes a simple sequential read
- address interleave/reconstruction is no longer on the FC active path
- complexity is pushed into storage organization, which is usually a better
  place to spend cost on an FPGA

This is the clearest example in the branch of:

`use more on-chip memory to buy simpler timing`

It also matches the resource picture:

- RAM blocks are only `11%`
- DSPs are already `99%`

So the design had memory headroom but almost no DSP headroom.

## 9. `cnn_mmio_interface.v`: 32-Bit Cleanup, But Not The Main Fmax Win

Files:

- [`../input/RTL/interface/cnn_mmio_interface.v`](../input/RTL/interface/cnn_mmio_interface.v)
- [`../include/cnn_mmio_regs.h`](../include/cnn_mmio_regs.h)
- [`../include/cnn_mmio_host.h`](../include/cnn_mmio_host.h)
- [`../tools/cnn_mmio_host.c`](../tools/cnn_mmio_host.c)

### What changed structurally

- scratchpad is now 32-bit word-addressed
- replay engine sends one staged 32-bit word directly
- old low/high halfword stitch behavior is gone
- low-16-bit control/status ABI is preserved for compatibility

### Why this matters

This cleanup mostly affects:

- host/software clarity
- wrapper simplicity
- MMIO-side consistency

It is **not** the main reason the fabric got back above `50 MHz`, but it
removes avoidable wrapper complexity and makes the project easier to explain.

## 10. Why There Is No PLL In The Current Solution

Relevant files:

- [`../de1_soc/soc_system_top.sv`](../de1_soc/soc_system_top.sv)
- [`../de1_soc/soc_system.sdc`](../de1_soc/soc_system.sdc)

Current state:

- `soc_system_top.sv` feeds `CLOCK_50` directly into `soc_system`
- `soc_system.sdc` constrains `clock_50` with a `20 ns` period
- fitter summary shows `0 / 6` PLLs used

Reason:

- after the datapath/control cleanups above, the design no longer needed a
  divided fabric clock just to close timing
- direct `CLOCK_50` is simpler to hand off and easier to reason about

## 11. Current Result

Current timing evidence:

- [`../de1_soc/output_files/soc_system.sta.summary`](../de1_soc/output_files/soc_system.sta.summary)
- [`../de1_soc/output_files/soc_system.sta.rpt`](../de1_soc/output_files/soc_system.sta.rpt)

Useful current numbers:

- `clock_50` slow-corner setup slack: `6.794 ns`
- `clock_50` slow-corner Fmax: `75.72 MHz`

That is why the branch can now run directly at `50 MHz` without a PLL.

## Read Next

- [BUILD_TIMING_AND_RESOURCES.md](BUILD_TIMING_AND_RESOURCES.md)
- [ARCHITECTURE_AND_FILE_MAP.md](ARCHITECTURE_AND_FILE_MAP.md)
