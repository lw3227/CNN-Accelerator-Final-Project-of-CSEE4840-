module conv_top #(
  parameter integer W      = 64,    // max line buffer width (L1)
  parameter integer DATA_W = 8,
  parameter integer ROWS   = 16,
  parameter integer COLS   = 4,
  parameter integer DOT_K  = 72,    // max dot product length (L3: 9*8)
  parameter integer ACC_W  = 23,
  parameter integer IMG_H  = 64,
  parameter integer IMG_W  = 64,
  parameter integer C_IN   = 8      // max input channels (L3)
)(
  input  wire [1:0]                layer_sel,
  input  wire clk,
  input  wire rst_n,

  // 像素流输入（ready/valid 握手）
  input  wire                      in_valid,
  input  wire        [31:0]        in_data,
  input  wire        [3:0]         in_byte_en,
  input  wire                      in_last,
  output wire                      in_ready,

  // 权重装载通道
  input  wire                      wt_valid,
  output wire                      wt_ready,
  input  wire                      wt_last,
  input  wire signed [COLS*DATA_W-1:0] wt_data,

  // Weight load done (1-cycle pulse on weights_loaded rising edge)
  output wire                        wt_load_done,

  // SA 输出
  output wire                        sa_done,
  // 每列实时串流输出
  output wire signed [COLS*ACC_W-1:0] c_out_col_stream_flat,//4*23bits,输出一行
  output wire        [COLS-1:0]        c_out_col_valid,
  output wire        [COLS-1:0]        c_out_col_last,

  // Frame rearm: Conv backend fully drained, ready for next frame/pass
  output wire                          frame_rearm_out,
  // Frame done: all input pixels received, SA may still be draining
  output wire                          frame_done_out
);

  // Debug-visible state encoding kept in top hierarchy for TB/wave compatibility.
  localparam [1:0] ST_IDLE     = 2'd0;

  // Runtime IMG_PIXELS decode from layer_sel
  // Counts input BEATS (not bytes). Each beat is one pix_accept.
  //   L1: 4096 beats (1 byte/beat, 64*64*1 bytes)
  //   L2: 961 beats  (4 bytes/beat, 31*31 wide pixels)
  //   L3: 392 beats  (4 bytes/beat, 14*14*8/4 half-pixels)
  reg [31:0] eff_img_pixels;
  always @* begin
    case (layer_sel)
      2'b01:   eff_img_pixels = 32'd961;   // 31*31
      2'b10:   eff_img_pixels = 32'd392;   // 14*14*2
      default: eff_img_pixels = 32'd4096;  // 64*64
    endcase
  end

  reg [31:0] pix_cnt;
  reg        frame_done;

  wire [1:0] state;
  wire [8:0] feed_cnt;
  wire [8:0] wt_load_cnt;
  wire [8:0] rd_col_r;
  wire       rd_en_r;
  wire       rd_bank_r;
  wire       wb_ring_r;
  wire       start_pulse_r;
  wire       weights_loaded;
  reg        weights_loaded_d;
  assign     wt_load_done = weights_loaded && !weights_loaded_d;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) weights_loaded_d <= 1'b0;
    else        weights_loaded_d <= weights_loaded;
  end
  wire       wt_load_active;
  wire       consume_ready_bank;
  wire       consume_bank_sel;
  wire [4:0] valid_rows_A, valid_rows_B;
  wire       partial_pending;
  // Frame re-arm: declared here, driven below after backend idle detection.
  wire frame_rearm;

  // Internal observation signals kept hierarchical for TB and wave scripts.
  wire                        pix3_valid;
  wire signed [C_IN*DATA_W-1:0] row0_pix;
  wire signed [C_IN*DATA_W-1:0] row1_pix;
  wire signed [C_IN*DATA_W-1:0] row2_pix;
  wire signed [DATA_W-1:0] wb_out0, wb_out1, wb_out2, wb_out3;
  wire [COLS-1:0] wb_out_valid;
  wire                       bank_can_write;

  // Input-side flow control.
  wire pix_accept = in_valid && in_ready;
  assign in_ready = !frame_done && bank_can_write;

  // Bank write-side control.
  wire rd_active = (state != ST_IDLE);

  // Launch arbitration and weight-side handshake.
  wire have_ready_block;
  wire wt_fire = wt_valid && wt_ready;
  wire launch_from_A;
  wire have_launchable_block = have_ready_block && weights_loaded;
  // Prevent SA launch after frame_done (avoid stale bank data between layers/passes)
  wire can_launch = have_launchable_block && !wt_fire && !frame_done;
  wire [1:0] sa_mode_cfg = layer_sel;

  // SA input gating.
  wire signed [ROWS*DATA_W-1:0] a_in_flat;
  wire signed [ROWS*DATA_W-1:0] a_in_from_bank;
  wire signed [ROWS*DATA_W-1:0] raw_firstcol_flat;
  wire signed [ROWS*COLS*ACC_W-1:0] c_out_raw_flat;
  wire signed [DATA_W-1:0] wb_col0 = wb_out_valid[0] ? wb_out0 : {DATA_W{1'b0}};
  wire signed [DATA_W-1:0] wb_col1 = wb_out_valid[1] ? wb_out1 : {DATA_W{1'b0}};
  wire signed [DATA_W-1:0] wb_col2 = wb_out_valid[2] ? wb_out2 : {DATA_W{1'b0}};
  wire signed [DATA_W-1:0] wb_col3 = wb_out_valid[3] ? wb_out3 : {DATA_W{1'b0}};
  wire sa_a_gate = rd_en_r || ((state == ST_IDLE) && can_launch);
  wire rd_bank_sel = ((state == ST_IDLE) && can_launch) ? (launch_from_A ? 1'b0 : 1'b1) : rd_bank_r;
  wire signed [COLS*DATA_W-1:0] b_in_to_sa =
      rd_en_r ? {wb_col3, wb_col2, wb_col1, wb_col0} : {(COLS*DATA_W){1'b0}};
  // in_last is consumed by frame_done logic below (no longer unused).

  // 空闲状态下用 0 门控 A 输入，避免 SA 在非发射期积分垃圾值
  assign a_in_flat = sa_a_gate ? a_in_from_bank : {ROWS*DATA_W{1'b0}};

  input_row_aligner #(
    .W   (W),
    .DW  (DATA_W),
    .C_IN(C_IN)
  ) u_input_row_aligner (
    .layer_sel  (layer_sel),
    .clk        (clk),
    .rst_n      (rst_n),
    .frame_rearm(frame_rearm),
    .in_valid   (pix_accept),
    .in_data    (in_data),
    .in_byte_en (in_byte_en),
    .pix3_valid (pix3_valid),
    .row0_out   (row0_pix),
    .row1_out   (row1_pix),
    .row2_out   (row2_pix)
  );

  weight_buffer #(
    .DATA_W(COLS*DATA_W),
    .COLS  (COLS),
    .L0    (DOT_K),
    .L1    (DOT_K + 1),
    .L2    (DOT_K + 2),
    .L3    (DOT_K + 3)
  ) u_weight_buffer (
    .layer_sel(layer_sel),
    .clk      (clk),
    .rst_n    (rst_n),
    .ring     (wb_ring_r),
    .wr_en    (wt_fire),
    .in_data  (wt_data),
    .out_ready(rd_en_r),
    .out0     (wb_out0),
    .out1     (wb_out1),
    .out2     (wb_out2),
    .out3     (wb_out3),
    .out_valid(wb_out_valid)
  );

  Conv_Buffer #(
    .DATA_W(DATA_W),
    .ROWS  (ROWS),
    .DOT_K (DOT_K),
    .C_IN  (C_IN)
  ) u_conv_buffer (
    .layer_sel         (layer_sel),
    .clk               (clk),
    .rst_n             (rst_n),
    .frame_rearm       (frame_rearm),
    .pix3_valid        (pix3_valid),
    .row0_pix          (row0_pix),
    .row1_pix          (row1_pix),
    .row2_pix          (row2_pix),
    .rd_active         (rd_active),
    .rd_en             (rd_en_r),
    .rd_bank           (rd_bank_sel),
    .rd_col            (rd_col_r),
    .consume_ready_bank(consume_ready_bank),
    .consume_bank_sel  (consume_bank_sel),
    .bank_can_write    (bank_can_write),
    .have_ready_block  (have_ready_block),
    .launch_from_A     (launch_from_A),
    .valid_rows_A      (valid_rows_A),
    .valid_rows_B      (valid_rows_B),
    .partial_pending   (partial_pending),
    .raw_firstcol_flat (raw_firstcol_flat)
  );

  sa_skew_feeder #(
    .ROWS(ROWS)
  ) u_sa_skew_feeder (
    .clk             (clk),
    .rst_n           (rst_n),
    .frame_rearm     (frame_rearm),
    .rd_en           (rd_en_r),
    .in_firstcol_flat(raw_firstcol_flat),
    .out_firstcol_flat(a_in_from_bank)
  );

  conv_engine_ctrl #(
    .DOT_K(DOT_K),
    .COLS (COLS),
    .ROWS (ROWS)
  ) u_conv_engine_ctrl (
    .layer_sel         (layer_sel),
    .clk               (clk),
    .rst_n             (rst_n),
    .wt_valid          (wt_valid),
    .wt_last           (wt_last),
    .have_ready_block  (have_ready_block),
    .launch_from_A     (launch_from_A),
    .launch_valid_rows (launch_from_A ? valid_rows_A : valid_rows_B),
    .frame_rearm       (frame_rearm),
    .sa_done           (sa_done),
    .wt_ready          (wt_ready),
    .weights_loaded    (weights_loaded),
    .wt_load_active    (wt_load_active),
    .wt_load_cnt       (wt_load_cnt),
    .state_dbg         (state),
    .feed_cnt_dbg      (feed_cnt),
    .consume_ready_bank(consume_ready_bank),
    .consume_bank_sel  (consume_bank_sel),
    .rd_en             (rd_en_r),
    .rd_bank           (rd_bank_r),
    .rd_col            (rd_col_r),
    .wb_ring           (wb_ring_r),
    .start_pulse       (start_pulse_r)
  );

  // Backend drain detection: all SA work complete, window FIFO truly empty,
  // and no ready/partial block pending.
  wire backend_idle = frame_done
                   && (state == ST_IDLE)
                   && !have_ready_block
                   && !partial_pending;

  // Re-arm: one cycle after backend_idle, clear frame state for next transaction.
  reg backend_idle_d;
  assign frame_rearm = backend_idle && !backend_idle_d;
  assign frame_rearm_out = frame_rearm;
  assign frame_done_out  = frame_done;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      backend_idle_d <= 1'b0;
    else
      backend_idle_d <= backend_idle;
  end

  // 帧结束：beat 计数达到 eff_img_pixels 或上游断言 in_last 均视为帧结束。
  // frame_rearm 在后端排空后自动清零，允许 back-to-back transaction。
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pix_cnt <= 32'd0;
      frame_done <= 1'b0;
    end else begin
      if (frame_rearm) begin
        pix_cnt <= 32'd0;
        frame_done <= 1'b0;
      end else if (pix_accept && !frame_done) begin
        if (pix_cnt == (eff_img_pixels - 32'd1) || in_last) begin
          frame_done <= 1'b1;
        end
        pix_cnt <= pix_cnt + 32'd1;
      end
    end
  end

  systolic_array_top #(
    .DATA_W(DATA_W),
    .ROWS  (ROWS),
    .COLS  (COLS),
    .DOT_K (DOT_K),
    .ACC_W (ACC_W)
  ) u_systolic_array_top (
    .clk        (clk),
    .rst_n      (rst_n),
    .start_pulse(start_pulse_r),
    .mode_cfg   (sa_mode_cfg),
    .valid_rows_cfg(rd_bank_sel ? valid_rows_B : valid_rows_A),
    .a_in_flat  (a_in_flat),
    .b_in_flat  (b_in_to_sa),
    .c_out_flat (c_out_raw_flat),
    .done       (sa_done),
    .col_stream_data_flat(c_out_col_stream_flat),
    .col_stream_valid    (c_out_col_valid),
    .col_stream_last     (c_out_col_last)
  );

endmodule
