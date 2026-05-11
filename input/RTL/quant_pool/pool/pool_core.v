module pool_core_lane #(
  parameter integer POOL_DEPTH = 31   // max across all layers
)(
  input  wire        [1:0] layer_sel,
  input  wire              clk,
  input  wire              rst_n,
  input  wire              lane_reset,
  input  wire signed [7:0] cut,
  input  wire              cut_valid,
  input  wire              emit_step,
  input  wire              emit_done,
  output wire              bank_ready,
  output wire signed [7:0] emit_head
);

  // --- runtime decode from layer_sel ---
  reg [4:0] eff_pool_depth;
  reg [5:0] eff_in_w;
  reg [5:0] eff_in_h;
  always @* begin
    case (layer_sel)
      2'b01:   begin eff_pool_depth = 5'd14; eff_in_w = 6'd29; eff_in_h = 6'd29; end
      2'b10:   begin eff_pool_depth = 5'd6;  eff_in_w = 6'd12; eff_in_h = 6'd12; end
      default: begin eff_pool_depth = 5'd31; eff_in_w = 6'd62; eff_in_h = 6'd62; end
    endcase
  end

  reg              cnt1;
  reg        [4:0] cnt2;
  reg              cnt3;
  reg              ready_r;
  reg signed [7:0] accum_bank [0:POOL_DEPTH-1];
  reg signed [7:0] emit_bank  [0:POOL_DEPTH-1];
  reg signed [7:0] next_accum_val;
  integer i;

  // --- orphan pixel suppression counters ---
  reg [5:0] col_in_row;
  reg [5:0] row_cnt;
  wire pixel_ok = (col_in_row < {1'b0, eff_pool_depth} << 1)
               && (row_cnt    < {1'b0, eff_pool_depth} << 1);

  wire tile_complete = cut_valid && pixel_ok
                    && cnt1 && (cnt2 == eff_pool_depth - 5'd1) && cnt3;

  wire [4:0] cnt2_next =
      (cnt1 && (cnt2 != eff_pool_depth - 5'd1)) ? (cnt2 + 5'd1) :
      (cnt1 && (cnt2 == eff_pool_depth - 5'd1)) ? 5'd0 :
                                                   cnt2;
  wire cnt3_next = (cnt1 && (cnt2 == eff_pool_depth - 5'd1)) ? ~cnt3 : cnt3;

  always @* begin
    if (cnt3)
      next_accum_val = (cut > accum_bank[cnt2]) ? cut : accum_bank[cnt2];
    else if (cnt1)
      next_accum_val = (cut > accum_bank[cnt2]) ? cut : accum_bank[cnt2];
    else
      next_accum_val = cut;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt1       <= 1'b0;
      cnt2       <= 5'd0;
      cnt3       <= 1'b0;
      ready_r    <= 1'b0;
      col_in_row <= 6'd0;
      row_cnt    <= 6'd0;
      for (i = 0; i < POOL_DEPTH; i = i + 1) begin
        accum_bank[i] <= 8'sd0;
        emit_bank[i]  <= 8'sd0;
      end
    end else if (lane_reset) begin
      cnt1       <= 1'b0;
      cnt2       <= 5'd0;
      cnt3       <= 1'b0;
      ready_r    <= 1'b0;
      col_in_row <= 6'd0;
      row_cnt    <= 6'd0;
      for (i = 0; i < POOL_DEPTH; i = i + 1) begin
        accum_bank[i] <= 8'sd0;
        emit_bank[i]  <= 8'sd0;
      end
    end else begin
      if (emit_step) begin
        for (i = 0; i < POOL_DEPTH-1; i = i + 1)
          emit_bank[i] <= emit_bank[i+1];
        emit_bank[POOL_DEPTH-1] <= 8'sd0;
      end

      if (emit_done)
        ready_r <= 1'b0;

      if (cut_valid) begin
        // advance orphan counters; auto-wrap at frame boundary
        if (col_in_row == eff_in_w - 6'd1) begin
          col_in_row <= 6'd0;
          if (row_cnt == eff_in_h - 6'd1)
            row_cnt <= 6'd0;          // frame complete → ready for next
          else
            row_cnt <= row_cnt + 6'd1;
        end else begin
          col_in_row <= col_in_row + 6'd1;
        end

        if (pixel_ok) begin
          if (tile_complete) begin
            for (i = 0; i < POOL_DEPTH; i = i + 1) begin
              if (i == cnt2)
                emit_bank[i] <= next_accum_val;
              else
                emit_bank[i] <= accum_bank[i];
              accum_bank[i] <= 8'sd0;
            end
            ready_r <= 1'b1;
            cnt1    <= 1'b0;
            cnt2    <= 5'd0;
            cnt3    <= 1'b0;
          end else begin
            accum_bank[cnt2] <= next_accum_val;
            cnt1             <= ~cnt1;
            cnt2             <= cnt2_next;
            cnt3             <= cnt3_next;
          end
        end
        // !pixel_ok → orphan pixel, only counters advanced, accum/cnt untouched
      end
    end
  end

  assign bank_ready = ready_r;
  assign emit_head  = emit_bank[0];

endmodule

module pool_core #(
  parameter integer POOL_DEPTH = 31
)(
  input  wire        [1:0]  layer_sel,
  input  wire               clk,
  input  wire               rst_n,
  input  wire signed [7:0]  cut1,
  input  wire signed [7:0]  cut2,
  input  wire signed [7:0]  cut3,
  input  wire signed [7:0]  cut4,
  input  wire               en1,
  input  wire               en2,
  input  wire               en3,
  input  wire               en4,
  input  wire               frame_rearm,
  input  wire               pool_ready,
  output wire signed [31:0] pool_data,
  output wire               pool_valid,
  output wire               pool_last,
  output wire               pool_frame_done
);

  // runtime decode for emit_last
  reg [4:0] eff_pool_depth;
  always @* begin
    case (layer_sel)
      2'b01:   eff_pool_depth = 5'd14;
      2'b10:   eff_pool_depth = 5'd6;
      default: eff_pool_depth = 5'd31;
    endcase
  end

  // Delay frame_rearm by 8 cycles so quant pipeline residual is flushed.
  // Reset on layer_changed so stale frame_rearm from previous layer doesn't
  // prematurely clear drop_until_idle in the new layer context.
  reg        emit_active;
  reg  [5:0] emit_count;
  reg        lane_reset_r;
  reg        drop_until_idle;
  reg [1:0]  layer_sel_d;
  wire       layer_changed;
  wire       l2_to_l3_change = (layer_sel_d == 2'b01) && (layer_sel == 2'b10);
  reg [7:0]  frame_rearm_sr;
  reg        frame_rearm_hold_active;
  reg        frame_rearm_pending;
  wire       frame_rearm_delayed = frame_rearm_sr[7];
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)             frame_rearm_sr <= 8'd0;
    else                    frame_rearm_sr <= {frame_rearm_sr[6:0], frame_rearm};
  end

  assign layer_changed = (layer_sel != layer_sel_d);
  wire       lane1_ready, lane2_ready, lane3_ready, lane4_ready;
  wire signed [7:0] lane1_emit, lane2_emit, lane3_emit, lane4_emit;
  wire       all_ready = lane1_ready & lane2_ready & lane3_ready & lane4_ready;
  wire       emit_last = (emit_count == {1'b0, eff_pool_depth} - 6'd1);
  wire       emit_fire = emit_active && pool_ready;
  wire       emit_step = emit_fire;
  wire       emit_done = emit_fire && emit_last;
  wire       any_cut_valid = en1 | en2 | en3 | en4;
  wire       lane_cut_valid1 = drop_until_idle ? 1'b0 : en1;
  wire       lane_cut_valid2 = drop_until_idle ? 1'b0 : en2;
  wire       lane_cut_valid3 = drop_until_idle ? 1'b0 : en3;
  wire       lane_cut_valid4 = drop_until_idle ? 1'b0 : en4;

  pool_core_lane #(.POOL_DEPTH(POOL_DEPTH)) u_lane1 (
    .layer_sel(layer_sel),
    .clk(clk), .rst_n(rst_n),
    .lane_reset(lane_reset_r),
    .cut(cut1), .cut_valid(lane_cut_valid1),
    .emit_step(emit_step), .emit_done(emit_done),
    .bank_ready(lane1_ready), .emit_head(lane1_emit)
  );

  pool_core_lane #(.POOL_DEPTH(POOL_DEPTH)) u_lane2 (
    .layer_sel(layer_sel),
    .clk(clk), .rst_n(rst_n),
    .lane_reset(lane_reset_r),
    .cut(cut2), .cut_valid(lane_cut_valid2),
    .emit_step(emit_step), .emit_done(emit_done),
    .bank_ready(lane2_ready), .emit_head(lane2_emit)
  );

  pool_core_lane #(.POOL_DEPTH(POOL_DEPTH)) u_lane3 (
    .layer_sel(layer_sel),
    .clk(clk), .rst_n(rst_n),
    .lane_reset(lane_reset_r),
    .cut(cut3), .cut_valid(lane_cut_valid3),
    .emit_step(emit_step), .emit_done(emit_done),
    .bank_ready(lane3_ready), .emit_head(lane3_emit)
  );

  pool_core_lane #(.POOL_DEPTH(POOL_DEPTH)) u_lane4 (
    .layer_sel(layer_sel),
    .clk(clk), .rst_n(rst_n),
    .lane_reset(lane_reset_r),
    .cut(cut4), .cut_valid(lane_cut_valid4),
    .emit_step(emit_step), .emit_done(emit_done),
    .bank_ready(lane4_ready), .emit_head(lane4_emit)
  );

  assign pool_data  = {lane1_emit, lane2_emit, lane3_emit, lane4_emit};
  assign pool_valid = emit_active;
  assign pool_last  = emit_active && emit_last;

  // --- frame-level burst counter for pool_frame_done ---
  reg [4:0] eff_burst_total;
  always @* begin
    case (layer_sel)
      2'b01:   eff_burst_total = 5'd14;  // L2
      2'b10:   eff_burst_total = 5'd6;   // L3
      default: eff_burst_total = 5'd31;  // L1
    endcase
  end

  reg [4:0] burst_cnt;
  reg       frame_done_r;

  assign pool_frame_done = frame_done_r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      emit_active  <= 1'b0;
      emit_count   <= 6'd0;
      burst_cnt    <= 5'd0;
      frame_done_r <= 1'b0;
      lane_reset_r <= 1'b0;
      drop_until_idle <= 1'b0;
      layer_sel_d    <= 2'b00;
      frame_rearm_hold_active <= 1'b0;
      frame_rearm_pending <= 1'b0;
    end else begin
      frame_done_r <= 1'b0;
      lane_reset_r <= 1'b0;
      layer_sel_d  <= layer_sel;

      if (frame_rearm)
        frame_rearm_pending <= 1'b1;

      if (layer_changed) begin
        emit_active     <= 1'b0;
        emit_count      <= 6'd0;
        burst_cnt       <= 5'd0;
        lane_reset_r    <= 1'b1;
        drop_until_idle <= l2_to_l3_change;
        frame_rearm_hold_active <= l2_to_l3_change;
        frame_rearm_pending <= 1'b0;
      end else begin
        if (frame_rearm_hold_active && frame_rearm_delayed) begin
          drop_until_idle <= 1'b0;
          lane_reset_r    <= 1'b1;
          frame_rearm_hold_active <= 1'b0;
          frame_rearm_pending <= 1'b0;
        end

        if (!emit_active) begin
          emit_count <= 6'd0;
          if (all_ready)
            emit_active <= 1'b1;
        end else if (emit_fire) begin
          if (emit_last) begin
            emit_active <= 1'b0;
            emit_count  <= 6'd0;
            if (burst_cnt == eff_burst_total - 5'd1) begin
              burst_cnt       <= 5'd0;
              frame_done_r    <= 1'b1;
              lane_reset_r    <= 1'b1;
              if (frame_rearm_pending) begin
                frame_rearm_pending <= 1'b0;
              end else begin
                drop_until_idle         <= 1'b1;
                frame_rearm_hold_active <= 1'b1;
              end
            end else begin
              burst_cnt <= burst_cnt + 5'd1;
            end
          end else begin
            emit_count <= emit_count + 6'd1;
          end
        end
      end
    end
  end

endmodule
