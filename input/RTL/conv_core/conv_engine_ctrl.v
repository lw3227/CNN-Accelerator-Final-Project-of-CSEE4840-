module conv_engine_ctrl #(
  parameter integer DOT_K = 72,
  parameter integer COLS  = 4,
  parameter integer ROWS  = 16
)(
  input  wire [1:0] layer_sel,
  input  wire       clk,
  input  wire       rst_n,
  input  wire       wt_valid,
  input  wire       wt_last,
  input  wire       have_ready_block,
  input  wire       launch_from_A,
  input  wire [4:0] launch_valid_rows,
  input  wire       frame_rearm,
  input  wire       sa_done,
  output wire       wt_ready,
  output wire       weights_loaded,
  output wire       wt_load_active,
  output wire [8:0] wt_load_cnt,
  output wire [1:0] state_dbg,
  output wire [8:0] feed_cnt_dbg,
  output wire       consume_ready_bank,
  output wire       consume_bank_sel,
  output wire       rd_en,
  output wire       rd_bank,
  output wire [8:0] rd_col,
  output wire       wb_ring,
  output wire       start_pulse
);

  localparam [1:0] ST_IDLE     = 2'd0;
  localparam [1:0] ST_PRERING  = 2'd1;
  localparam [1:0] ST_FEED     = 2'd2;
  localparam [1:0] ST_WAITDONE = 2'd3;

  // Runtime decode: eff_dot_k, FEED_CYCLES, WT_LOAD_CYCLES
  reg [8:0] eff_dot_k;
  reg [8:0] eff_feed_last_base;
  reg [8:0] eff_wt_load_cycles;
  always @* begin
    case (layer_sel)
      2'b01:   begin eff_dot_k = 9'd36; eff_feed_last_base = 9'd50;  eff_wt_load_cycles = 9'd39; end // 36+16-1-1=50, 36+4-1=39
      2'b10:   begin eff_dot_k = 9'd72; eff_feed_last_base = 9'd86;  eff_wt_load_cycles = 9'd75; end // 72+16-1-1=86, 72+4-1=75
      default: begin eff_dot_k = 9'd9;  eff_feed_last_base = 9'd23;  eff_wt_load_cycles = 9'd12; end // 9+16-1-1=23, 9+4-1=12
    endcase
  end

  reg [1:0] state_r;
  reg [8:0] feed_cnt_r;
  reg [8:0] wt_load_cnt_r;
  reg       rd_en_r;
  reg       rd_bank_r;
  reg [8:0] rd_col_r;
  reg       wb_ring_r;
  reg       start_pulse_r;
  reg       weights_loaded_r;
  reg       wt_load_active_r;
  reg [4:0] active_valid_rows_r;
  reg [8:0] active_feed_last_r;

  wire wt_fire = wt_valid && wt_ready;
  wire have_launchable_block = have_ready_block && weights_loaded_r;
  wire can_launch = have_launchable_block && !wt_fire;

  assign wt_ready           = (state_r == ST_IDLE);
  assign weights_loaded     = weights_loaded_r;
  assign wt_load_active     = wt_load_active_r;
  assign wt_load_cnt        = wt_load_cnt_r;
  assign state_dbg          = state_r;
  assign feed_cnt_dbg       = feed_cnt_r;
  assign rd_en              = rd_en_r;
  assign rd_bank            = rd_bank_r;
  assign rd_col             = rd_col_r;
  assign wb_ring            = wb_ring_r;
  assign start_pulse        = start_pulse_r;
  assign consume_ready_bank =
      ((state_r == ST_IDLE) && can_launch) ||
      ((state_r == ST_FEED) && (feed_cnt_r == active_feed_last_r) && have_launchable_block) ||
      ((state_r == ST_WAITDONE) && sa_done && have_launchable_block);
  assign consume_bank_sel   = launch_from_A ? 1'b0 : 1'b1;

  // 权重装载协议：
  // 1) wt_valid/wt_ready 握手后，weight_buffer 接收一拍新权重；
  // 2) wt_last 标识当前权重组的最后一拍；
  // 3) 只有 weights_loaded=1 时，SA 才允许从 ready bank 发射。
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weights_loaded_r <= 1'b0;
      wt_load_active_r <= 1'b0;
      wt_load_cnt_r    <= 9'd0;
    end else if (frame_rearm) begin
      weights_loaded_r <= 1'b0;
      wt_load_active_r <= 1'b0;
      wt_load_cnt_r    <= 9'd0;
    end else if (wt_fire) begin
      if (!wt_load_active_r) begin
        weights_loaded_r <= wt_last;
        wt_load_active_r <= !wt_last;
        wt_load_cnt_r    <= 9'd1;
      end else begin
        weights_loaded_r <= wt_last;
        wt_load_active_r <= !wt_last;
        if (wt_load_cnt_r < eff_wt_load_cycles)
          wt_load_cnt_r <= wt_load_cnt_r + 9'd1;
        else
          wt_load_cnt_r <= wt_load_cnt_r;
      end
    end
  end

  // SA 发射控制：
  // ST_IDLE、ST_FEED 尾拍或 ST_WAITDONE 发现 ready block 后，先进入 ST_PRERING 发 ring；
  // 下一拍 ST_PRERING 同时拉高 start_pulse 和 rd_en；
  // ST_FEED 按 rd_col 送 0..DOT_K-1 列，再送越界列做冲刷。
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_r       <= ST_IDLE;
      feed_cnt_r    <= 9'd0;
      rd_col_r      <= 9'd0;
      rd_en_r       <= 1'b0;
      rd_bank_r     <= 1'b0;
      wb_ring_r     <= 1'b0;
      start_pulse_r <= 1'b0;
      active_valid_rows_r <= 5'd0;
      active_feed_last_r  <= 9'd0;
    end else if (frame_rearm) begin
      state_r       <= ST_IDLE;
      feed_cnt_r    <= 9'd0;
      rd_col_r      <= 9'd0;
      rd_en_r       <= 1'b0;
      rd_bank_r     <= 1'b0;
      wb_ring_r     <= 1'b0;
      start_pulse_r <= 1'b0;
      active_valid_rows_r <= 5'd0;
      active_feed_last_r  <= 9'd0;
    end else begin
      rd_en_r       <= 1'b0;
      wb_ring_r     <= 1'b0;
      start_pulse_r <= 1'b0;

      case (state_r)
        ST_IDLE: begin
          feed_cnt_r <= 9'd0;
          rd_col_r   <= 9'd0;
          if (can_launch) begin
            rd_bank_r <= launch_from_A ? 1'b0 : 1'b1;
            active_valid_rows_r <= launch_valid_rows;
            if (launch_valid_rows > 5'd0)
              active_feed_last_r <= eff_dot_k + {{4{1'b0}}, launch_valid_rows} - 9'd2;
            else
              active_feed_last_r <= eff_feed_last_base;
            wb_ring_r <= 1'b1;
            state_r   <= ST_PRERING;
          end
        end

        ST_PRERING: begin
          rd_col_r      <= 9'd0;
          rd_en_r       <= 1'b1;
          start_pulse_r <= 1'b1;
          feed_cnt_r    <= 9'd1;
          state_r       <= ST_FEED;
        end

        ST_FEED: begin
          rd_en_r <= 1'b1;
          if (feed_cnt_r < eff_dot_k) begin
            rd_col_r <= feed_cnt_r;
          end else begin
            rd_col_r <= 9'd511;  // out-of-range → get_byte returns 0 (flush)
          end

          if (feed_cnt_r == active_feed_last_r) begin
            feed_cnt_r <= 9'd0;
            rd_col_r   <= 9'd0;
            if (have_launchable_block) begin
              rd_bank_r <= launch_from_A ? 1'b0 : 1'b1;
              active_valid_rows_r <= launch_valid_rows;
              if (launch_valid_rows > 5'd0)
                active_feed_last_r <= eff_dot_k + {{4{1'b0}}, launch_valid_rows} - 9'd2;
              else
                active_feed_last_r <= eff_feed_last_base;
              wb_ring_r <= 1'b1;
              state_r   <= ST_PRERING;
            end else begin
              state_r <= ST_WAITDONE;
            end
          end else begin
            feed_cnt_r <= feed_cnt_r + 9'd1;
          end
        end

        ST_WAITDONE: begin
          if (sa_done) begin
            if (have_launchable_block) begin
              rd_bank_r <= launch_from_A ? 1'b0 : 1'b1;
              active_valid_rows_r <= launch_valid_rows;
              if (launch_valid_rows > 5'd0)
                active_feed_last_r <= eff_dot_k + {{4{1'b0}}, launch_valid_rows} - 9'd2;
              else
                active_feed_last_r <= eff_feed_last_base;
              wb_ring_r <= 1'b1;
              state_r   <= ST_PRERING;
            end else begin
              state_r <= ST_IDLE;
            end
          end
        end

        default: begin
          state_r <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
