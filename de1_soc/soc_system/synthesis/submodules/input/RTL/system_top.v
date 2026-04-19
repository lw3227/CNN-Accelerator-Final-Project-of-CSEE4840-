// system_top: ASIC top-level module
//
// Instantiates:
//   TopFSM + LayerRunnerFSM    (control)
//   top_sram_A + top_sram_B    (storage, from teammate)
//   conv_quant_pool          (Conv-Quant-Pool)
//   FC + fc_data_adapter       (FC classifier)
//   wt_prepad_inserter         (3-zero-beat inserter for conv weights)
//
// Chip pins: clk, rst_n, load_data[31:0], load_valid, load_sel,
//            load_last, load_ready, busy, predict_valid, predict_class[1:0]

module system_top #(
  parameter integer OUT_CHANNELS = 10
) (
  input  wire        clk,
  input  wire        rst_n,

  // --- External data port ---
  input  wire        load_sel,
  input  wire        load_valid,
  input  wire [31:0] load_data,
  input  wire        load_last,
  output wire        load_ready,

  // --- Status ---
  output wire        busy,
  output wire        predict_valid,
  output wire [3:0]  predict_class
);

  // =============================================================
  // Internal wires
  // =============================================================

  // --- TopFSM ↔ LayerRunnerFSM ---
  wire        runner_start, runner_done;
  wire [1:0]  runner_layer_sel;
  wire        runner_pass_id, runner_is_fc;

  // --- TopFSM → SRAM_A preload control ---
  wire        top_sram_a_start;
  wire [2:0]  top_sram_a_layer_sel;
  wire [1:0]  top_sram_a_data_sel;
  wire        top_sram_a_done;
  wire        preload_wr_valid;
  wire [31:0] preload_wr_data;

  // --- LayerRunnerFSM → SRAM_A inference control ---
  wire        run_sram_a_start;
  wire [2:0]  run_sram_a_layer_sel;
  wire [1:0]  run_sram_a_data_sel;
  wire        run_sram_a_pass_id;

  // --- LayerRunnerFSM → SRAM_B control ---
  wire        run_sram_b_start;
  wire [2:0]  run_sram_b_layer_sel;
  wire [1:0]  run_sram_b_data_sel;
  wire        run_sram_b_pass_id;

  // --- SRAM_A muxed control ---
  wire        sram_a_start;
  wire [2:0]  sram_a_layer_sel;
  wire [1:0]  sram_a_data_sel;
  wire        sram_a_pass_id;
  wire        sram_a_done;

  // --- SRAM_A streams ---
  wire        sram_a_data_valid, sram_a_data_last;
  wire [31:0] sram_a_read_data;
  wire        sram_a_data_ready;
  wire        sram_a_pool_ready;

  // --- SRAM_B streams ---
  wire        sram_b_data_valid, sram_b_data_last;
  wire [31:0] sram_b_read_data;
  wire        sram_b_data_ready;
  wire        sram_b_pool_ready;
  wire        sram_b_done;

  // --- conv_quant_pool signals ---
  wire        conv_cfg_ready, conv_wt_ready, conv_in_ready;
  wire signed [31:0] conv_pool_data;
  wire        conv_pool_valid, conv_pool_last;
  wire        conv_cfg_load_done, conv_wt_load_done, conv_pool_frame_done;
  wire        conv_frame_rearm_done;

  // --- wt_prepad_inserter ---
  wire        wt_prepad_dn_valid, wt_prepad_dn_last;
  wire [31:0] wt_prepad_dn_data;
  wire        wt_prepad_dn_ready;
  wire        wt_prepad_up_ready;

  // --- conv_data_adapter ---
  wire        conv_in_adapter_up_ready;

  // --- L1 pixel bypass control ---
  wire        pixel_stream_active;

  // --- FC signals ---
  wire        fc_cfg_ready, fc_param_load_done;
  wire [OUT_CHANNELS*32-1:0] fc_acc_vec;
  wire [OUT_CHANNELS-1:0]    fc_mul_done_vec;
  wire        fc_all_done;

  // --- fc_data_adapter signals ---
  wire        fc_mul_en;
  wire [OUT_CHANNELS*8-1:0]  fc_pixel_vec;
  wire [OUT_CHANNELS*8-1:0]  fc_kernel_vec;
  wire        fc_adapter_wt_ready, fc_adapter_data_ready;
  wire        fc_done;

  // --- FC weight dedicated 80-bit stream (from SRAM_FCW via top_sram_A) ---
  wire [OUT_CHANNELS*8-1:0]  fc_wt_read_data;
  wire                       fc_wt_stream_valid;
  wire                       fc_wt_stream_last;

  // =============================================================
  // MUX control: who owns SRAM_A?
  // =============================================================
  // TopFSM drives SRAM_A during preload, LayerRunnerFSM during inference.
  // preload_mode latches on start pulse and HOLDS until the next start,
  // so layer_sel/data_sel/pass_id remain stable throughout the transaction
  // (wrapper requires stability until done).

  // preload_mode: latches on start pulse, determines MUX routing.
  // sram_a_start is delayed 1 cycle so that preload_mode is stable
  // when the SRAM wrapper samples layer_sel / data_sel / pass_id.
  reg preload_mode;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)                preload_mode <= 1'b1;
    else if (top_sram_a_start) preload_mode <= 1'b1;
    else if (run_sram_a_start) preload_mode <= 1'b0;
  end

  reg sram_a_start_d;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sram_a_start_d <= 1'b0;
    else        sram_a_start_d <= top_sram_a_start | run_sram_a_start;
  end

  assign sram_a_start     = sram_a_start_d;
  assign sram_a_layer_sel = preload_mode ? top_sram_a_layer_sel : run_sram_a_layer_sel;
  assign sram_a_data_sel  = preload_mode ? top_sram_a_data_sel  : run_sram_a_data_sel;
  assign sram_a_pass_id   = preload_mode ? 1'b0                : run_sram_a_pass_id;

  // =============================================================
  // SRAM_A write port MUX
  // =============================================================
  // Preload: load_data from external host
  // Inference: pool_data from Conv (L2 writeback to SRAM_A)
  wire [31:0] sram_a_pool_data  = preload_mode ? load_data      : conv_pool_data;
  wire        sram_a_pool_valid = preload_mode ? (preload_wr_valid && load_valid)
                                               : conv_pool_valid;
  wire        sram_a_pool_last  = preload_mode ? load_last       : conv_pool_last;

  // SRAM_A preload_wr_ready = sram_a_pool_ready (when in preload mode)
  wire        preload_wr_ready  = preload_mode ? sram_a_pool_ready : 1'b0;

  // =============================================================
  // SRAM_A read stream routing
  // =============================================================
  // Latched data_sel and is_fc to know where to route read data.
  reg [1:0]  active_data_sel;
  reg        active_is_fc;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_data_sel <= 2'd0;
      active_is_fc    <= 1'b0;
    end else if (run_sram_a_start) begin
      active_data_sel <= run_sram_a_data_sel;
      active_is_fc    <= runner_is_fc;
    end
  end

  localparam [1:0] SEL_CFG = 2'd0, SEL_WT = 2'd1, SEL_DATA = 2'd2;

  // Route SRAM_A read to correct consumer:
  //   CFG + conv → conv_quant_pool.cfg
  //   CFG + FC   → FC.cfg
  //   WT  + conv → wt_prepad_inserter → conv_quant_pool.wt
  //   WT  + FC   → fc_data_adapter.wt (no prepad for FC)
  //   DATA + conv (L1/L3) → conv_quant_pool.in
  //   DATA + FC   → never (FC data comes from SRAM_B)

  wire route_conv_cfg = !active_is_fc && (active_data_sel == SEL_CFG);
  wire route_conv_wt  = !active_is_fc && (active_data_sel == SEL_WT);
  wire route_conv_in  = !active_is_fc && (active_data_sel == SEL_DATA);
  wire route_fc_cfg   =  active_is_fc && (active_data_sel == SEL_CFG);
  // FC weights no longer flow through the 32-bit SRAM_A read bus; they travel
  // via the dedicated 80-bit fc_wt_read_data port out of top_sram_A.

  // Conv cfg port
  wire        conv_cfg_valid = route_conv_cfg ? sram_a_data_valid : 1'b0;
  wire [31:0] conv_cfg_data  = sram_a_read_data;
  wire        conv_cfg_last  = route_conv_cfg ? sram_a_data_last  : 1'b0;

  // Conv wt port (through prepad inserter)
  wire        conv_wt_sram_valid = route_conv_wt ? sram_a_data_valid : 1'b0;
  wire        conv_wt_sram_last  = route_conv_wt ? sram_a_data_last  : 1'b0;

  // Conv in port (L1/L3 data from SRAM_A; L2 data from SRAM_B handled below)
  wire        conv_in_from_a_valid = route_conv_in ? sram_a_data_valid : 1'b0;
  wire        conv_in_from_a_last  = route_conv_in ? sram_a_data_last  : 1'b0;

  // FC cfg port
  wire        fc_cfg_valid = route_fc_cfg ? sram_a_data_valid : 1'b0;
  wire [31:0] fc_cfg_data  = sram_a_read_data;
  wire        fc_cfg_last  = route_fc_cfg ? sram_a_data_last  : 1'b0;

  // SRAM_A data_ready: OR of all active consumers on the shared 32-bit bus.
  assign sram_a_data_ready = preload_mode ? 1'b0 :
                             (route_conv_cfg ? conv_cfg_ready            : 1'b0) |
                             (route_conv_wt  ? wt_prepad_up_ready        : 1'b0) |
                             (route_conv_in  ? conv_in_adapter_up_ready  : 1'b0) |
                             (route_fc_cfg   ? fc_cfg_ready              : 1'b0);

  // =============================================================
  // SRAM_B read stream routing
  // =============================================================
  // L2: SRAM_B → conv in port
  // FC: SRAM_B → fc_data_adapter data port
  // L1/L3 must not see SRAM_B read-side signals while SRAM_B is the pool sink.
  wire route_conv_in_b = !active_is_fc && (runner_layer_sel == 2'b01);
  wire route_fc_data_b =  active_is_fc;

  wire        conv_in_from_b_valid = route_conv_in_b ? sram_b_data_valid : 1'b0;
  wire        conv_in_from_b_last  = route_conv_in_b ? sram_b_data_last  : 1'b0;

  wire        fc_data_valid = route_fc_data_b ? sram_b_data_valid : 1'b0;
  wire        fc_data_last  = route_fc_data_b ? sram_b_data_last  : 1'b0;

  assign sram_b_data_ready = (route_conv_in_b ? conv_in_adapter_up_ready : 1'b0) |
                             (route_fc_data_b ? fc_adapter_data_ready    : 1'b0);

  // =============================================================
  // Conv input MUX: L1 from external load_data (bypass SRAM_A),
  //                 L2 from SRAM_B, L3 from SRAM_A
  // =============================================================
  wire        conv_in_from_ext_valid = pixel_stream_active ? load_valid : 1'b0;
  wire        conv_in_from_ext_last  = pixel_stream_active ? load_last  : 1'b0;

  wire        conv_in_raw_valid = conv_in_from_ext_valid
                                | conv_in_from_a_valid
                                | conv_in_from_b_valid;
  wire [31:0] conv_in_raw_data  = conv_in_from_ext_valid ? load_data        :
                                  conv_in_from_a_valid   ? sram_a_read_data :
                                                           sram_b_read_data;
  wire        conv_in_raw_last  = conv_in_from_ext_last
                                | conv_in_from_a_last
                                | conv_in_from_b_last;

  // conv_data_adapter: L1 byte unpack (1 word → 4 beats), L2/L3 pass-through
  wire        conv_in_valid;
  wire [31:0] conv_in_data;
  wire [3:0]  conv_in_byte_en;
  wire        conv_in_last;

  // =============================================================
  // SRAM_B write port: pool output from Conv (L1/L3 writeback)
  // =============================================================
  // Only connected during L1/L3 STREAM phase; SRAM_B controller
  // ignores pool_valid when not in write mode.
  wire [31:0] sram_b_pool_data  = conv_pool_data;
  wire        sram_b_pool_valid = conv_pool_valid;
  wire        sram_b_pool_last  = conv_pool_last;

  // Conv pool_ready: from whichever SRAM is the write sink
  // L1 (00) / L3 (10): SRAM_B is sink → pool_ready from SRAM_B
  // L2 (01): SRAM_A is sink → pool_ready from SRAM_A (when not in preload)
  wire        pool_sink_is_b  = (runner_layer_sel != 2'b01);  // L1/L3 → B; L2 → A
  wire        conv_pool_ready = preload_mode ? 1'b0 :
                                (pool_sink_is_b ? sram_b_pool_ready
                                                : sram_a_pool_ready);

  // =============================================================
  // Module instantiations
  // =============================================================

  // --- TopFSM ---
  top_fsm #(.ACC_W(32), .OUT_CHANNELS(OUT_CHANNELS)) u_top_fsm (
    .clk(clk), .rst_n(rst_n),
    .load_sel(load_sel), .load_valid(load_valid),
    .load_data(load_data), .load_last(load_last),
    .load_ready(load_ready),
    .busy(busy), .predict_valid(predict_valid), .predict_class(predict_class),
    .runner_start(runner_start),
    .runner_layer_sel(runner_layer_sel),
    .runner_pass_id(runner_pass_id),
    .runner_is_fc(runner_is_fc),
    .runner_done(runner_done),
    .sram_a_start(top_sram_a_start),
    .sram_a_layer_sel(top_sram_a_layer_sel),
    .sram_a_data_sel(top_sram_a_data_sel),
    .sram_a_done(sram_a_done),
    .preload_wr_valid(preload_wr_valid),
    .preload_wr_data(preload_wr_data),
    .preload_wr_ready(preload_wr_ready),
    .pixel_stream_active(pixel_stream_active),
    .conv_adapter_up_ready(conv_in_adapter_up_ready),
    .conv_frame_rearm(conv_frame_rearm_done),
    .fc_acc_vec(fc_acc_vec)
  );

  // --- LayerRunnerFSM ---
  layer_runner_fsm u_runner (
    .clk(clk), .rst_n(rst_n),
    .start(runner_start),
    .layer_sel(runner_layer_sel),
    .pass_id(runner_pass_id),
    .is_fc(runner_is_fc),
    .busy(), .done(runner_done),
    .sram_a_start(run_sram_a_start),
    .sram_a_layer_sel(run_sram_a_layer_sel),
    .sram_a_data_sel(run_sram_a_data_sel),
    .sram_a_pass_id(run_sram_a_pass_id),
    .sram_a_done(sram_a_done),
    .sram_b_start(run_sram_b_start),
    .sram_b_layer_sel(run_sram_b_layer_sel),
    .sram_b_data_sel(run_sram_b_data_sel),
    .sram_b_pass_id(run_sram_b_pass_id),
    .sram_b_done(sram_b_done),
    .cfg_load_done(runner_is_fc ? fc_param_load_done : conv_cfg_load_done),
    .wt_load_done(conv_wt_load_done),
    .pool_frame_done(conv_pool_frame_done),
    .conv_frame_rearm(conv_frame_rearm_done),
    .fc_done(fc_done)
  );

  // --- SRAM_A (shared 32-bit pool + SRAM_FCW 80-bit peer for FC weights) ---
  top_sram_A u_sram_a (
    .clk(clk), .rst_n(rst_n),
    .layer_sel(sram_a_layer_sel),
    .data_sel(sram_a_data_sel),
    .pass_id(sram_a_pass_id),
    .start(sram_a_start),
    .busy(), .done(sram_a_done),
    .data_ready(sram_a_data_ready),
    .read_data(sram_a_read_data),
    .data_valid(sram_a_data_valid),
    .data_last(sram_a_data_last),
    .pool_ready(sram_a_pool_ready),
    .pool_data(sram_a_pool_data),
    .pool_valid(sram_a_pool_valid),
    .pool_last(sram_a_pool_last),
    .fc_wt_ready(fc_adapter_wt_ready),
    .fc_wt_read_data(fc_wt_read_data),
    .fc_wt_valid(fc_wt_stream_valid),
    .fc_wt_last(fc_wt_stream_last)
  );

  // --- SRAM_B (from teammate) ---
  top_sram_B u_sram_b (
    .clk(clk), .rst_n(rst_n),
    .layer_sel(run_sram_b_layer_sel),
    .data_sel(run_sram_b_data_sel),
    .pass_id(run_sram_b_pass_id),
    .start(run_sram_b_start),
    .busy(), .done(sram_b_done),
    .data_ready(sram_b_data_ready),
    .read_data(sram_b_read_data),
    .data_valid(sram_b_data_valid),
    .data_last(sram_b_data_last),
    .pool_ready(sram_b_pool_ready),
    .pool_data(sram_b_pool_data),
    .pool_valid(sram_b_pool_valid),
    .pool_last(sram_b_pool_last)
  );

  // --- WT Prepad Inserter (between SRAM_A read and Conv wt port) ---
  wt_prepad_inserter u_wt_prepad (
    .clk(clk), .rst_n(rst_n),
    .is_wt_read(route_conv_wt),
    .up_valid(conv_wt_sram_valid),
    .up_data(sram_a_read_data),
    .up_last(conv_wt_sram_last),
    .up_ready(wt_prepad_up_ready),
    .dn_valid(wt_prepad_dn_valid),
    .dn_data(wt_prepad_dn_data),
    .dn_last(wt_prepad_dn_last),
    .dn_ready(wt_prepad_dn_ready)
  );

  // --- Conv Data Adapter (L1 byte unpack, L2/L3 pass-through) ---
  conv_data_adapter u_conv_data_adapter (
    .clk(clk), .rst_n(rst_n),
    .layer_sel(runner_layer_sel),
    .up_valid(conv_in_raw_valid),
    .up_data(conv_in_raw_data),
    .up_last(conv_in_raw_last),
    .up_ready(conv_in_adapter_up_ready),
    .dn_valid(conv_in_valid),
    .dn_data(conv_in_data),
    .dn_byte_en(conv_in_byte_en),
    .dn_last(conv_in_last),
    .dn_ready(conv_in_ready)
  );

  // --- Conv-Quant-Pool ---
  conv_quant_pool u_conv (
    .layer_sel(runner_layer_sel),
    .clk(clk), .rst_n(rst_n),
    // Image stream (from conv_data_adapter)
    .in_valid(conv_in_valid),
    .in_data(conv_in_data),
    .in_byte_en(conv_in_byte_en),
    .in_last(conv_in_last),
    .in_ready(conv_in_ready),
    // Weight stream (from prepad inserter)
    .wt_valid(wt_prepad_dn_valid),
    .wt_ready(wt_prepad_dn_ready),
    .wt_last(wt_prepad_dn_last),
    .wt_data(wt_prepad_dn_data),
    // Cfg stream
    .cfg_valid(conv_cfg_valid),
    .cfg_ready(conv_cfg_ready),
    .cfg_data(conv_cfg_data),
    .cfg_last(conv_cfg_last),
    // Pool output
    .pool_ready(conv_pool_ready),
    .pool_data(conv_pool_data),
    .pool_valid(conv_pool_valid),
    .pool_last(conv_pool_last),
    // Control observation
    .cfg_load_done(conv_cfg_load_done),
    .wt_load_done(conv_wt_load_done),
    .pool_frame_done(conv_pool_frame_done),
    .conv_frame_rearm_out(conv_frame_rearm_done)
  );

  // --- FC Data Adapter ---
  fc_data_adapter #(
    .OUT_CHANNELS(OUT_CHANNELS),
    .PIX_W(8), .KER_W(8)
  ) u_fc_adapter (
    .clk(clk), .rst_n(rst_n),
    // 80-bit weight stream from SRAM_FCW (via top_sram_A FCW peer)
    .wt_valid(fc_wt_stream_valid),
    .wt_data(fc_wt_read_data),
    .wt_last(fc_wt_stream_last),
    .wt_ready(fc_adapter_wt_ready),
    // Data stream from SRAM_B (packed pixels, 32b)
    .data_valid(fc_data_valid),
    .data_data(sram_b_read_data),
    .data_last(fc_data_last),
    .data_ready(fc_adapter_data_ready),
    // To FC
    .mul_en(fc_mul_en),
    .pixel_vec(fc_pixel_vec),
    .kernel_vec(fc_kernel_vec),
    .all_done(fc_all_done),
    .fc_done(fc_done)
  );

  // --- FC ---
  FC #(
    .PIX_W(8), .KER_W(8), .K(288), .ACC_W(32),
    .OUT_CHANNELS(OUT_CHANNELS)
  ) u_fc (
    .clk(clk), .rst_n(rst_n),
    .cfg_valid(fc_cfg_valid),
    .cfg_ready(fc_cfg_ready),
    .cfg_data(fc_cfg_data),
    .cfg_last(fc_cfg_last),
    .param_load_done(fc_param_load_done),
    .mul_en(fc_mul_en),
    .pixel_vec(fc_pixel_vec),
    .kernel_vec(fc_kernel_vec),
    .acc_vec(fc_acc_vec),
    .mul_done_vec(fc_mul_done_vec),
    .all_done(fc_all_done)
  );

endmodule
