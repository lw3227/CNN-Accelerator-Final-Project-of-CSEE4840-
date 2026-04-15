// Conv_Buffer — dual-bank stripe buffer for conv_top.
//
// Storage: flat 8-bit regs (2 × 432 entries) — cheap write-enable per register.
// Read path: hardwired concat into 24 × 144-bit "group" wires (zero gate cost),
//   then a single 24:1 MUX + 3:1 barrel shift extract 16 consecutive bytes.
// Address decode: counter-based (ch_r, dx_r, dy_r) advances with rd_col — no
//   runtime division/modulo.
// zero_fill_tail: eliminated; read path masks out unfilled columns via fill_cols.
//
// Synthesis: ~84K um² (vs ~114K baseline with 16× 432:1 MUX + div/mod).

module Conv_Buffer #(
  parameter integer DATA_W = 8,
  parameter integer ROWS   = 16,
  parameter integer DOT_K  = 72,
  parameter integer C_IN   = 8
)(
  input  wire [1:0]                    layer_sel,
  input  wire                          clk,
  input  wire                          rst_n,
  input  wire                          frame_rearm,
  input  wire                          pix3_valid,
  input  wire signed [C_IN*DATA_W-1:0] row0_pix,
  input  wire signed [C_IN*DATA_W-1:0] row1_pix,
  input  wire signed [C_IN*DATA_W-1:0] row2_pix,
  input  wire                          rd_active,
  input  wire                          rd_en,
  input  wire                          rd_bank,
  input  wire [8:0]                    rd_col,
  input  wire                          consume_ready_bank,
  input  wire                          consume_bank_sel,
  output wire                          bank_can_write,
  output wire                          have_ready_block,
  output wire                          launch_from_A,
  output wire [4:0]                    valid_rows_A,
  output wire [4:0]                    valid_rows_B,
  output wire                          partial_pending,
  output wire signed [ROWS*DATA_W-1:0] raw_firstcol_flat
);

  // ----------------------------------------------------------------
  // Constants
  // ----------------------------------------------------------------
  localparam integer PIX_W        = C_IN * DATA_W;
  localparam integer STRIPE_ROWS  = 3;
  localparam integer STRIPE_COLS  = 18;
  localparam integer STRIPE_STEP  = 16;
  localparam integer STRIPE_BYTES = STRIPE_ROWS * STRIPE_COLS * C_IN;
  localparam integer WORD_W       = STRIPE_COLS * DATA_W;  // 144
  localparam integer MAX_WORDS    = STRIPE_ROWS * C_IN;    // 24

  // ----------------------------------------------------------------
  // Flat 8-bit storage (same as Conv_Buffer — cheap writes)
  // ----------------------------------------------------------------
  reg signed [7:0] bank_A [0:STRIPE_BYTES-1];
  reg signed [7:0] bank_B [0:STRIPE_BYTES-1];

  // ----------------------------------------------------------------
  // Control registers
  // ----------------------------------------------------------------
  reg [6:0] x_pos_r;
  reg [6:0] fill_base_x_r;
  reg [4:0] fill_cols_r;
  reg       wr_bank_r;
  reg       ready_A_r;
  reg       ready_B_r;
  reg [4:0] valid_rows_A_r;
  reg [4:0] valid_rows_B_r;
  reg       seed_pending_r;
  reg       seed_src_bank_r;
  // Per-bank fill column count (replaces zero_fill_tail)
  reg [4:0] fill_cols_A_r;
  reg [4:0] fill_cols_B_r;

  // ----------------------------------------------------------------
  // Layer-dependent parameters
  // ----------------------------------------------------------------
  reg [6:0] eff_w;
  reg [3:0] eff_c;
  reg [6:0] eff_out_w;
  reg [8:0] eff_dot_k;

  always @* begin
    case (layer_sel)
      2'b01: begin
        eff_w     = 7'd31;
        eff_c     = 4'd4;
        eff_out_w = 7'd29;
        eff_dot_k = 9'd36;
      end
      2'b10: begin
        eff_w     = 7'd14;
        eff_c     = 4'd8;
        eff_out_w = 7'd12;
        eff_dot_k = 9'd72;
      end
      default: begin
        eff_w     = 7'd64;
        eff_c     = 4'd1;
        eff_out_w = 7'd62;
        eff_dot_k = 9'd9;
      end
    endcase
  end

  // ----------------------------------------------------------------
  // TB-visible diagnostic wires (same as Conv_Buffer)
  // ----------------------------------------------------------------
  wire stripe_window_open =
      (x_pos_r >= fill_base_x_r) && (x_pos_r < (fill_base_x_r + 7'd18));
  wire write_bank_blocked = ready_A_r && ready_B_r;
  wire write_read_conflict = rd_active && (wr_bank_r == rd_bank);
  wire input_stall = write_bank_blocked || write_read_conflict;
  wire accepting_input_col = pix3_valid && !input_stall && stripe_window_open;
  wire signed [DOT_K*DATA_W-1:0] write_sample_flat =
      {{(DOT_K*DATA_W - 3*PIX_W){1'b0}}, row2_pix, row1_pix, row0_pix};

  // ----------------------------------------------------------------
  // Functions
  // ----------------------------------------------------------------
  function integer stripe_idx;
    input integer row_idx;
    input integer col_idx;
    input integer ch_idx;
    begin
      stripe_idx = ((row_idx * STRIPE_COLS) + col_idx) * C_IN + ch_idx;
    end
  endfunction

  function [4:0] calc_valid_rows;
    input [6:0] base_x;
    input [6:0] out_w;
    reg [6:0] remaining;
    begin
      if (base_x >= out_w)
        calc_valid_rows = 5'd0;
      else begin
        remaining = out_w - base_x;
        if (remaining >= ROWS[6:0])
          calc_valid_rows = ROWS[4:0];
        else
          calc_valid_rows = {1'b0, remaining[3:0]};
      end
    end
  endfunction

  // ----------------------------------------------------------------
  // Write tasks (from Conv_Buffer — simple flat-reg writes)
  // ----------------------------------------------------------------
  integer col_off_i;
  reg [4:0] new_valid_rows;
  integer real_cols_i;

  task write_input_column;
    input dst_bank;
    input integer col_idx;
    integer ch_i;
    begin
      for (ch_i = 0; ch_i < C_IN; ch_i = ch_i + 1) begin
        if (dst_bank) begin
          bank_B[stripe_idx(0, col_idx, ch_i)] <= row0_pix[ch_i*DATA_W +: DATA_W];
          bank_B[stripe_idx(1, col_idx, ch_i)] <= row1_pix[ch_i*DATA_W +: DATA_W];
          bank_B[stripe_idx(2, col_idx, ch_i)] <= row2_pix[ch_i*DATA_W +: DATA_W];
        end else begin
          bank_A[stripe_idx(0, col_idx, ch_i)] <= row0_pix[ch_i*DATA_W +: DATA_W];
          bank_A[stripe_idx(1, col_idx, ch_i)] <= row1_pix[ch_i*DATA_W +: DATA_W];
          bank_A[stripe_idx(2, col_idx, ch_i)] <= row2_pix[ch_i*DATA_W +: DATA_W];
        end
      end
    end
  endtask

  task copy_overlap_cols;
    input dst_bank;
    input src_bank;
    integer row_i;
    integer ch_i;
    begin
      for (row_i = 0; row_i < STRIPE_ROWS; row_i = row_i + 1) begin
        for (ch_i = 0; ch_i < C_IN; ch_i = ch_i + 1) begin
          if (dst_bank) begin
            if (src_bank) begin
              bank_B[stripe_idx(row_i, 0, ch_i)] <= bank_B[stripe_idx(row_i, 16, ch_i)];
              bank_B[stripe_idx(row_i, 1, ch_i)] <= bank_B[stripe_idx(row_i, 17, ch_i)];
            end else begin
              bank_B[stripe_idx(row_i, 0, ch_i)] <= bank_A[stripe_idx(row_i, 16, ch_i)];
              bank_B[stripe_idx(row_i, 1, ch_i)] <= bank_A[stripe_idx(row_i, 17, ch_i)];
            end
          end else begin
            if (src_bank) begin
              bank_A[stripe_idx(row_i, 0, ch_i)] <= bank_B[stripe_idx(row_i, 16, ch_i)];
              bank_A[stripe_idx(row_i, 1, ch_i)] <= bank_B[stripe_idx(row_i, 17, ch_i)];
            end else begin
              bank_A[stripe_idx(row_i, 0, ch_i)] <= bank_A[stripe_idx(row_i, 16, ch_i)];
              bank_A[stripe_idx(row_i, 1, ch_i)] <= bank_A[stripe_idx(row_i, 17, ch_i)];
            end
          end
        end
      end
    end
  endtask

  // zero_fill_tail: ELIMINATED — read-side fill_cols mask handles this

  task mark_ready_bank;
    input dst_bank;
    input [4:0] valid_rows;
    input [4:0] fill_cols;
    begin
      if (dst_bank) begin
        ready_B_r      <= (valid_rows != 5'd0);
        valid_rows_B_r <= valid_rows;
        fill_cols_B_r  <= fill_cols;
      end else begin
        ready_A_r      <= (valid_rows != 5'd0);
        valid_rows_A_r <= valid_rows;
        fill_cols_A_r  <= fill_cols;
      end
    end
  endtask

  // ----------------------------------------------------------------
  // Output assignments
  // ----------------------------------------------------------------
  assign bank_can_write   = !input_stall;
  assign have_ready_block = ready_A_r || ready_B_r;
  assign launch_from_A    = ready_A_r;
  assign valid_rows_A     = valid_rows_A_r;
  assign valid_rows_B     = valid_rows_B_r;
  assign partial_pending  = seed_pending_r || (fill_cols_r != 5'd0);

  // ================================================================
  // READ PATH — counter-based decode + hardwired concatenation
  // ================================================================

  // Hardwired 144-bit group wires: zero gate cost, pure wiring.
  // group_X[dy*C_IN+ch] concatenates 18 flat regs into a 144-bit word.
  wire [WORD_W-1:0] group_A [0:MAX_WORDS-1];
  wire [WORD_W-1:0] group_B [0:MAX_WORDS-1];

  genvar g_dy, g_ch, g_col;
  generate
    for (g_dy = 0; g_dy < STRIPE_ROWS; g_dy = g_dy + 1) begin : gen_dy
      for (g_ch = 0; g_ch < C_IN; g_ch = g_ch + 1) begin : gen_ch
        for (g_col = 0; g_col < STRIPE_COLS; g_col = g_col + 1) begin : gen_col
          localparam integer WADDR = g_dy * C_IN + g_ch;
          localparam integer SIDX  = (g_dy * STRIPE_COLS + g_col) * C_IN + g_ch;
          assign group_A[WADDR][g_col*DATA_W +: DATA_W] = bank_A[SIDX];
          assign group_B[WADDR][g_col*DATA_W +: DATA_W] = bank_B[SIDX];
        end
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // Counter-based im2col decode (replaces runtime div/mod on rd_col)
  // ----------------------------------------------------------------
  reg [3:0] ch_r;
  reg [1:0] dx_r;
  reg [1:0] dy_r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ch_r <= 4'd0;
      dx_r <= 2'd0;
      dy_r <= 2'd0;
    end else if (frame_rearm) begin
      ch_r <= 4'd0;
      dx_r <= 2'd0;
      dy_r <= 2'd0;
    end else if (rd_en && rd_col < eff_dot_k) begin
      if (rd_col == 9'd0) begin
        if (eff_c == 4'd1) begin
          ch_r <= 4'd0;
          dx_r <= 2'd1;
          dy_r <= 2'd0;
        end else begin
          ch_r <= 4'd1;
          dx_r <= 2'd0;
          dy_r <= 2'd0;
        end
      end else begin
        if (ch_r == eff_c - 4'd1) begin
          ch_r <= 4'd0;
          if (dx_r == 2'd2) begin
            dx_r <= 2'd0;
            dy_r <= dy_r + 2'd1;
          end else begin
            dx_r <= dx_r + 2'd1;
          end
        end else begin
          ch_r <= ch_r + 4'd1;
        end
      end
    end else if (!rd_en) begin
      ch_r <= 4'd0;
      dx_r <= 2'd0;
      dy_r <= 2'd0;
    end
  end

  // Current-cycle combinational decode
  reg [3:0] cur_ch;
  reg [1:0] cur_dx;
  reg [1:0] cur_dy;
  always @* begin
    if (!rd_en || rd_col >= eff_dot_k) begin
      cur_ch = 4'd0;
      cur_dx = 2'd0;
      cur_dy = 2'd0;
    end else if (rd_col == 9'd0) begin
      cur_ch = 4'd0;
      cur_dx = 2'd0;
      cur_dy = 2'd0;
    end else begin
      cur_ch = ch_r;
      cur_dx = dx_r;
      cur_dy = dy_r;
    end
  end

  // ----------------------------------------------------------------
  // Read MUX: 24:1 group select → shift extract → fill_cols mask
  // ----------------------------------------------------------------
  reg [WORD_W-1:0] rd_word;
  reg [4:0] selected_valid_rows;
  reg [4:0] rd_fill_cols;
  reg signed [ROWS*DATA_W-1:0] raw_col_r;
  integer ri;

  // Word address — always use C_IN stride to match generate block indexing
  reg [4:0] rd_word_addr;
  always @* begin
    rd_word_addr = {cur_dy, 3'b000} + {1'b0, cur_ch};  // dy * 8 + ch
  end

  always @* begin
    selected_valid_rows = rd_bank ? valid_rows_B_r : valid_rows_A_r;
    rd_fill_cols        = rd_bank ? fill_cols_B_r  : fill_cols_A_r;
    rd_word             = rd_bank ? group_B[rd_word_addr] : group_A[rd_word_addr];

    raw_col_r = {(ROWS*DATA_W){1'b0}};
    if (rd_en && rd_col < eff_dot_k) begin
      for (ri = 0; ri < ROWS; ri = ri + 1) begin
        if (ri < selected_valid_rows && (ri + cur_dx) < rd_fill_cols)
          raw_col_r[ri*DATA_W +: DATA_W] =
              rd_word[(ri + cur_dx) * DATA_W +: DATA_W];
      end
    end
  end

  assign raw_firstcol_flat = raw_col_r;

  // ----------------------------------------------------------------
  // Main sequential block — stripe fill FSM
  // ----------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_pos_r         <= 7'd0;
      fill_base_x_r   <= 7'd0;
      fill_cols_r     <= 5'd0;
      wr_bank_r       <= 1'b0;
      ready_A_r       <= 1'b0;
      ready_B_r       <= 1'b0;
      valid_rows_A_r  <= 5'd0;
      valid_rows_B_r  <= 5'd0;
      seed_pending_r  <= 1'b0;
      seed_src_bank_r <= 1'b0;
      fill_cols_A_r   <= 5'd18;
      fill_cols_B_r   <= 5'd18;
    end else if (frame_rearm) begin
      x_pos_r         <= 7'd0;
      fill_base_x_r   <= 7'd0;
      fill_cols_r     <= 5'd0;
      wr_bank_r       <= 1'b0;
      ready_A_r       <= 1'b0;
      ready_B_r       <= 1'b0;
      valid_rows_A_r  <= 5'd0;
      valid_rows_B_r  <= 5'd0;
      seed_pending_r  <= 1'b0;
      seed_src_bank_r <= 1'b0;
      fill_cols_A_r   <= 5'd18;
      fill_cols_B_r   <= 5'd18;
    end else begin
      if (consume_ready_bank) begin
        if (consume_bank_sel == 1'b0)
          ready_A_r <= 1'b0;
        else
          ready_B_r <= 1'b0;
      end

      if (seed_pending_r && !pix3_valid && !input_stall) begin
        copy_overlap_cols(wr_bank_r, seed_src_bank_r);
        fill_cols_r    <= 5'd2;
        seed_pending_r <= 1'b0;
      end else if (pix3_valid && !input_stall) begin
        if (seed_pending_r) begin
          copy_overlap_cols(wr_bank_r, seed_src_bank_r);
          fill_cols_r    <= 5'd2;
          seed_pending_r <= 1'b0;
        end

        col_off_i = x_pos_r - fill_base_x_r;
        if (stripe_window_open) begin
          write_input_column(wr_bank_r, col_off_i);
          fill_cols_r <= col_off_i[4:0] + 5'd1;
        end

        if (x_pos_r == eff_w - 7'd1) begin
          if (fill_base_x_r < eff_out_w) begin
            real_cols_i = x_pos_r - fill_base_x_r + 1;
            // zero_fill_tail REMOVED — read-side fill_cols mask handles it
            new_valid_rows = calc_valid_rows(fill_base_x_r, eff_out_w);
            mark_ready_bank(wr_bank_r, new_valid_rows, real_cols_i[4:0]);
            wr_bank_r <= ~wr_bank_r;
          end

          x_pos_r         <= 7'd0;
          fill_base_x_r   <= 7'd0;
          fill_cols_r     <= 5'd0;
          seed_pending_r  <= 1'b0;
        end else if (x_pos_r == fill_base_x_r + 7'd17) begin
          new_valid_rows = calc_valid_rows(fill_base_x_r, eff_out_w);
          mark_ready_bank(wr_bank_r, new_valid_rows, 5'd18);

          seed_src_bank_r <= wr_bank_r;
          wr_bank_r       <= ~wr_bank_r;
          fill_base_x_r   <= fill_base_x_r + STRIPE_STEP[6:0];
          fill_cols_r     <= 5'd0;
          seed_pending_r  <= ((fill_base_x_r + STRIPE_STEP[6:0]) < eff_out_w);
          x_pos_r         <= x_pos_r + 7'd1;
        end else begin
          x_pos_r <= x_pos_r + 7'd1;
        end
      end
    end
  end

endmodule
