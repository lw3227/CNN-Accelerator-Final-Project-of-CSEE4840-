`timescale 1ns/1ps

// Generic conv layer testbench for L1/L2/L3.
// Layer selection via +define+LAYER_L2 or +define+LAYER_L3 at compile time.
// For layers with OUT_C > COLS, use +PASS_ID=0 / +PASS_ID=1 to select output channel group.

module tb_conv_layer_txt;

  localparam [8*128-1:0] DEFAULT_VCD_FILE = "/user/stud/fall25/lw3227/vcd/tb_conv_layer_txt.vcd";

  localparam integer DATA_W = 8;
  localparam integer ROWS   = 16;
  localparam integer COLS   = 4;
  localparam integer ACC_W  = 23;

`ifdef LAYER_L3
  localparam integer DOT_K = 72;
  localparam integer C_IN  = 8;
  localparam integer IMG_H = 14;
  localparam integer IMG_W = 14;
  localparam integer W     = 14;
  localparam integer OUT_H = 12;
  localparam integer OUT_W = 12;
  localparam integer OUT_C = 8;
  localparam [8*2-1:0] LAYER_NAME = "L3";
  localparam [1:0] LAYER_SEL = 2'b10;
  localparam integer BYTES_PER_BEAT = 4;  // 32-bit bus, 2 beats per wide pixel
`elsif LAYER_L2
  localparam integer DOT_K = 36;
  localparam integer C_IN  = 4;
  localparam integer IMG_H = 31;
  localparam integer IMG_W = 31;
  localparam integer W     = 31;
  localparam integer OUT_H = 29;
  localparam integer OUT_W = 29;
  localparam integer OUT_C = 8;
  localparam [8*2-1:0] LAYER_NAME = "L2";
  localparam [1:0] LAYER_SEL = 2'b01;
  localparam integer BYTES_PER_BEAT = 4;  // 32-bit bus, 1 beat per wide pixel
`else // L1 default
  localparam integer DOT_K = 9;
  localparam integer C_IN  = 1;
  localparam integer IMG_H = 64;
  localparam integer IMG_W = 64;
  localparam integer W     = 64;
  localparam integer OUT_H = 62;
  localparam integer OUT_W = 62;
  localparam integer OUT_C = 4;
  localparam [8*2-1:0] LAYER_NAME = "L1";
  localparam [1:0] LAYER_SEL = 2'b00;
  localparam integer BYTES_PER_BEAT = 1;  // 8-bit only
`endif

  localparam integer IN_TOTAL   = IMG_H * IMG_W * C_IN;
  localparam integer OUT_PIX    = OUT_H * OUT_W;
  localparam integer OUT_VALS   = OUT_PIX * COLS;    // per pass
  localparam integer OUT_BLOCKS = (OUT_PIX + ROWS - 1) / ROWS;
  localparam integer WB_LOAD_CYCLES = DOT_K + COLS - 1;
  localparam integer WB_PREPAD = WB_LOAD_CYCLES - DOT_K;
  localparam integer MAX_ERR_PRINT = 30;
  localparam integer N_PASSES = (OUT_C + COLS - 1) / COLS;
  localparam integer WT_PER_PASS = COLS * DOT_K;

  reg clk;
  reg rst_n;
  reg in_valid;
  reg [31:0] in_data;
  reg [3:0]  in_byte_en;
  wire in_ready;
  reg wt_valid;
  wire wt_ready;
  reg wt_last;
  reg signed [COLS*DATA_W-1:0] wt_data;

  wire sa_done;
  wire signed [COLS*ACC_W-1:0] c_out_col_stream_flat;
  wire [COLS-1:0] c_out_col_valid;
  wire [COLS-1:0] c_out_col_last;

  // Input image in RTL streaming order (row-major, channels interleaved)
  reg signed [DATA_W-1:0] img_mem [0:IN_TOTAL-1];
  // Weight taps per channel in RTL rd_col order
  reg signed [DATA_W-1:0] w_raw [0:OUT_C*DOT_K-1];
  reg signed [DATA_W-1:0] w_tap [0:COLS*DOT_K-1];
  // Reference output for current pass
  reg signed [31:0] ref_out [0:OUT_PIX*COLS-1];

  integer pix_sent;
  integer timeout_cnt;
  integer wb_i;
  integer checked_cnt;
  integer err_cnt;
  integer start_cnt;
  integer sa_done_cnt;
  integer pass_id;

  integer col_i, out_idx_i;
  integer fd, scan, lin, val, y, x, t, ch, c_in_i, b;
  integer cycle_cnt;
  integer first_wt_cycle, last_wt_cycle;
  integer first_in_cycle, last_in_cycle;
  integer first_start_cycle, last_start_cycle;
  integer first_out_cycle, last_out_cycle;
  integer last_done_cycle;
  integer kh, kw, matlab_idx, rd_col_idx;
  integer stream_row_cnt [0:COLS-1];
  integer stream_blk_cnt [0:COLS-1];
  integer checked_pix_col [0:COLS-1];
  integer done_blocks_min;
  integer done_blocks_max;
  integer done_blocks;
  reg sa_done_d;
  reg expected_last;
  reg signed [ACC_W-1:0] act23;
  reg signed [31:0] act32;
  reg signed [31:0] exp32;
  reg signed [DATA_W-1:0] wt0, wt1, wt2, wt3;
  reg dump_en;
  reg [1023:0] vcd_file;
  reg [1023:0] case_name;
  reg [1023:0] in_txt_file;
  reg [1023:0] wt_txt_file;
  reg [1023:0] out_txt_file;

  conv_top #(
    .W(W),
    .DATA_W(DATA_W),
    .ROWS(ROWS),
    .COLS(COLS),
    .DOT_K(DOT_K),
    .ACC_W(ACC_W),
    .IMG_H(IMG_H),
    .IMG_W(IMG_W),
    .C_IN(C_IN)
  ) dut (
    .layer_sel(LAYER_SEL),
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .in_data(in_data),
    .in_byte_en(in_byte_en),
    .in_last(1'b0),
    .in_ready(in_ready),
    .wt_valid(wt_valid),
    .wt_ready(wt_ready),
    .wt_last(wt_last),
    .wt_data(wt_data),
    .sa_done(sa_done),
    .c_out_col_stream_flat(c_out_col_stream_flat),
    .c_out_col_valid(c_out_col_valid),
    .c_out_col_last(c_out_col_last)
  );

  // ---------------------------------------------------------------------------
  // Task: load input image from txt (MATLAB column-major [H,W,C] → row-major channel-interleaved)
  // ---------------------------------------------------------------------------
  task load_input_image;
    integer rtl_idx;
    begin
      fd = $fopen(in_txt_file, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open input txt: %0s", in_txt_file);
        $finish;
      end
      for (lin = 0; lin < IN_TOTAL; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin
          $display("FAIL: input txt parse error at line %0d", lin);
          $finish;
        end
        // MATLAB column-major: h varies fastest, then w, then c
        y      = lin % IMG_H;
        t      = lin / IMG_H;
        x      = t % IMG_W;
        c_in_i = t / IMG_W;
        // RTL streaming order: row-major with channels interleaved
        rtl_idx = y * IMG_W * C_IN + x * C_IN + c_in_i;
        img_mem[rtl_idx] = $signed(val[DATA_W-1:0]);
      end
      $fclose(fd);
      $display("INFO: loaded input image txt (%0d values): %0s", IN_TOTAL, in_txt_file);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Task: load weights, select channel group, reorder to RTL rd_col order
  // ---------------------------------------------------------------------------
  task load_weight_and_reorder;
    integer total_wt;
    integer wt_offset;
    begin
      total_wt = OUT_C * DOT_K;
      fd = $fopen(wt_txt_file, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open weight txt: %0s", wt_txt_file);
        $finish;
      end
      for (lin = 0; lin < total_wt; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin
          $display("FAIL: weight txt parse error at line %0d", lin);
          $finish;
        end
        w_raw[lin] = $signed(val[DATA_W-1:0]);
      end
      $fclose(fd);

      // Select channel group based on pass_id (each pass handles COLS output channels)
      wt_offset = pass_id * WT_PER_PASS;

      // Reorder: MATLAB column-major (kh,kw,c_in) → RTL rd_col order
      // MATLAB per output channel: w_raw[wt_offset + ch*DOT_K + kh + 3*kw + 9*c_in_i]
      // RTL rd_col index: (2-kh)*3*C_IN + kw*C_IN + c_in_i
      for (ch = 0; ch < COLS; ch = ch + 1) begin
        for (rd_col_idx = 0; rd_col_idx < DOT_K; rd_col_idx = rd_col_idx + 1) begin
          c_in_i = rd_col_idx % C_IN;
          kw     = (rd_col_idx / C_IN) % 3;
          kh     = 2 - (rd_col_idx / (3 * C_IN));
          matlab_idx = kh + 3*kw + 9*c_in_i;
          w_tap[ch*DOT_K + rd_col_idx] = w_raw[wt_offset + ch*DOT_K + matlab_idx];
        end
      end
      $display("INFO: loaded and reordered weights (pass %0d): %0s", pass_id, wt_txt_file);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Task: load output reference, select channel group
  // ---------------------------------------------------------------------------
  task load_output_reference;
    integer total_out;
    integer out_ch;
    begin
      total_out = OUT_PIX * OUT_C;
      fd = $fopen(out_txt_file, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open output txt: %0s", out_txt_file);
        $finish;
      end
      // Initialize ref_out to 0
      for (lin = 0; lin < OUT_PIX*COLS; lin = lin + 1)
        ref_out[lin] = 0;

      for (lin = 0; lin < total_out; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin
          $display("FAIL: output txt parse error at line %0d", lin);
          $finish;
        end
        // MATLAB column-major [OUT_H, OUT_W, OUT_C]
        y      = lin % OUT_H;
        t      = lin / OUT_H;
        x      = t % OUT_W;
        out_ch = t / OUT_W;
        // Only store channels belonging to current pass
        if (out_ch >= pass_id * COLS && out_ch < (pass_id + 1) * COLS) begin
          out_idx_i = y * OUT_W + x;
          ref_out[out_idx_i * COLS + (out_ch - pass_id * COLS)] = val;
        end
      end
      $fclose(fd);
      $display("INFO: loaded output reference (pass %0d): %0s", pass_id, out_txt_file);
    end
  endtask

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Output comparison (same structure as tb_conv1_txt.v)
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_cnt = 0;
      done_blocks = 0;
      checked_cnt = 0;
      err_cnt = 0;
      start_cnt = 0;
      sa_done_cnt = 0;
      first_wt_cycle = -1;
      last_wt_cycle = -1;
      first_in_cycle = -1;
      last_in_cycle = -1;
      first_start_cycle = -1;
      last_start_cycle = -1;
      first_out_cycle = -1;
      last_out_cycle = -1;
      last_done_cycle = -1;
      sa_done_d <= 1'b0;
      for (col_i = 0; col_i < COLS; col_i = col_i + 1) begin
        stream_row_cnt[col_i] = 0;
        stream_blk_cnt[col_i] = 0;
        checked_pix_col[col_i] = 0;
      end
    end else begin
      cycle_cnt = cycle_cnt + 1;

      if (wt_valid && wt_ready) begin
        if (first_wt_cycle < 0)
          first_wt_cycle = cycle_cnt;
        last_wt_cycle = cycle_cnt;
      end

      if (in_valid && in_ready) begin
        if (first_in_cycle < 0)
          first_in_cycle = cycle_cnt;
        last_in_cycle = cycle_cnt;
      end

      if (dut.start_pulse_r) begin
        start_cnt = start_cnt + 1;
        if (first_start_cycle < 0)
          first_start_cycle = cycle_cnt;
        last_start_cycle = cycle_cnt;
      end

      sa_done_d <= sa_done;
      if (sa_done && !sa_done_d) begin
        sa_done_cnt = sa_done_cnt + 1;
        last_done_cycle = cycle_cnt;
      end

      if (|c_out_col_valid) begin
        if (first_out_cycle < 0)
          first_out_cycle = cycle_cnt;
        last_out_cycle = cycle_cnt;
      end

      for (col_i = 0; col_i < COLS; col_i = col_i + 1) begin
        if (c_out_col_valid[col_i]) begin
          out_idx_i = stream_blk_cnt[col_i] * ROWS + stream_row_cnt[col_i];
          expected_last = (stream_row_cnt[col_i] == (ROWS-1));

          act23 = $signed(c_out_col_stream_flat[col_i*ACC_W +: ACC_W]);
          act32 = act23;

          if (c_out_col_last[col_i] !== expected_last) begin
            if (err_cnt < MAX_ERR_PRINT) begin
              $display("LAST_FLAG_ERR: col=%0d blk=%0d row=%0d exp_last=%0d act_last=%0d",
                       col_i, stream_blk_cnt[col_i], stream_row_cnt[col_i],
                       expected_last, c_out_col_last[col_i]);
            end
            err_cnt = err_cnt + 1;
          end

          if (out_idx_i < OUT_PIX) begin
            exp32 = ref_out[out_idx_i*COLS + col_i];
            if (act32 !== exp32) begin
              if (err_cnt < MAX_ERR_PRINT) begin
                $display("MISMATCH: col=%0d blk=%0d row=%0d idx=%0d exp=%0d act=%0d",
                         col_i, stream_blk_cnt[col_i], stream_row_cnt[col_i],
                         out_idx_i, exp32, act32);
              end
              err_cnt = err_cnt + 1;
            end
            checked_cnt = checked_cnt + 1;
            checked_pix_col[col_i] = checked_pix_col[col_i] + 1;
          end

          if (expected_last) begin
            stream_row_cnt[col_i] = 0;
            stream_blk_cnt[col_i] = stream_blk_cnt[col_i] + 1;
          end else begin
            stream_row_cnt[col_i] = stream_row_cnt[col_i] + 1;
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Main stimulus
  // ---------------------------------------------------------------------------
  initial begin
    rst_n = 1'b0;
    in_valid = 1'b0;
    in_data = 32'd0;
    in_byte_en = (BYTES_PER_BEAT == 1) ? 4'b0001 : 4'b1111;
    wt_valid = 1'b0;
    wt_last = 1'b0;
    wt_data = 'sd0;
    timeout_cnt = 0;
    pix_sent = 0;
    pass_id = 0;

    case_name    = "paper";
`ifdef LAYER_L3
    in_txt_file  = "matlab/debug/txt_cases/paper/tb_conv3_in_i8_14x14x8.txt";
    wt_txt_file  = "matlab/debug/txt_cases/paper/tb_conv3_w_i8_3x3x8x8.txt";
    out_txt_file = "matlab/debug/txt_cases/paper/tb_conv3_out_i32_12x12x8.txt";
`elsif LAYER_L2
    in_txt_file  = "matlab/debug/txt_cases/paper/tb_conv2_in_i8_31x31x4.txt";
    wt_txt_file  = "matlab/debug/txt_cases/paper/tb_conv2_w_i8_3x3x4x8.txt";
    out_txt_file = "matlab/debug/txt_cases/paper/tb_conv2_out_i32_29x29x8.txt";
`else
    in_txt_file  = "matlab/debug/txt_cases/paper/tb_conv1_in_i8_64x64x1.txt";
    wt_txt_file  = "matlab/debug/txt_cases/paper/tb_conv1_w_i8_3x3x4.txt";
    out_txt_file = "matlab/debug/txt_cases/paper/tb_conv1_out_i32_62x62x4.txt";
`endif

    if (!$value$plusargs("CASE_NAME=%s", case_name))
      case_name = case_name;
    if (!$value$plusargs("IN_TXT=%s", in_txt_file))
      if (case_name == "rock")
`ifdef LAYER_L3
        in_txt_file = "matlab/debug/txt_cases/rock/tb_conv3_in_i8_14x14x8.txt";
`elsif LAYER_L2
        in_txt_file = "matlab/debug/txt_cases/rock/tb_conv2_in_i8_31x31x4.txt";
`else
        in_txt_file = "matlab/debug/txt_cases/rock/tb_conv1_in_i8_64x64x1.txt";
`endif
      else if (case_name == "scissors")
`ifdef LAYER_L3
        in_txt_file = "matlab/debug/txt_cases/scissors/tb_conv3_in_i8_14x14x8.txt";
`elsif LAYER_L2
        in_txt_file = "matlab/debug/txt_cases/scissors/tb_conv2_in_i8_31x31x4.txt";
`else
        in_txt_file = "matlab/debug/txt_cases/scissors/tb_conv1_in_i8_64x64x1.txt";
`endif
      else
`ifdef LAYER_L3
        in_txt_file = "matlab/debug/txt_cases/paper/tb_conv3_in_i8_14x14x8.txt";
`elsif LAYER_L2
        in_txt_file = "matlab/debug/txt_cases/paper/tb_conv2_in_i8_31x31x4.txt";
`else
        in_txt_file = "matlab/debug/txt_cases/paper/tb_conv1_in_i8_64x64x1.txt";
`endif
    if (!$value$plusargs("WT_TXT=%s", wt_txt_file))
      if (case_name == "rock")
`ifdef LAYER_L3
        wt_txt_file = "matlab/debug/txt_cases/rock/tb_conv3_w_i8_3x3x8x8.txt";
`elsif LAYER_L2
        wt_txt_file = "matlab/debug/txt_cases/rock/tb_conv2_w_i8_3x3x4x8.txt";
`else
        wt_txt_file = "matlab/debug/txt_cases/rock/tb_conv1_w_i8_3x3x4.txt";
`endif
      else if (case_name == "scissors")
`ifdef LAYER_L3
        wt_txt_file = "matlab/debug/txt_cases/scissors/tb_conv3_w_i8_3x3x8x8.txt";
`elsif LAYER_L2
        wt_txt_file = "matlab/debug/txt_cases/scissors/tb_conv2_w_i8_3x3x4x8.txt";
`else
        wt_txt_file = "matlab/debug/txt_cases/scissors/tb_conv1_w_i8_3x3x4.txt";
`endif
      else
`ifdef LAYER_L3
        wt_txt_file = "matlab/debug/txt_cases/paper/tb_conv3_w_i8_3x3x8x8.txt";
`elsif LAYER_L2
        wt_txt_file = "matlab/debug/txt_cases/paper/tb_conv2_w_i8_3x3x4x8.txt";
`else
        wt_txt_file = "matlab/debug/txt_cases/paper/tb_conv1_w_i8_3x3x4.txt";
`endif
    if (!$value$plusargs("OUT_TXT=%s", out_txt_file))
      if (case_name == "rock")
`ifdef LAYER_L3
        out_txt_file = "matlab/debug/txt_cases/rock/tb_conv3_out_i32_12x12x8.txt";
`elsif LAYER_L2
        out_txt_file = "matlab/debug/txt_cases/rock/tb_conv2_out_i32_29x29x8.txt";
`else
        out_txt_file = "matlab/debug/txt_cases/rock/tb_conv1_out_i32_62x62x4.txt";
`endif
      else if (case_name == "scissors")
`ifdef LAYER_L3
        out_txt_file = "matlab/debug/txt_cases/scissors/tb_conv3_out_i32_12x12x8.txt";
`elsif LAYER_L2
        out_txt_file = "matlab/debug/txt_cases/scissors/tb_conv2_out_i32_29x29x8.txt";
`else
        out_txt_file = "matlab/debug/txt_cases/scissors/tb_conv1_out_i32_62x62x4.txt";
`endif
      else
`ifdef LAYER_L3
        out_txt_file = "matlab/debug/txt_cases/paper/tb_conv3_out_i32_12x12x8.txt";
`elsif LAYER_L2
        out_txt_file = "matlab/debug/txt_cases/paper/tb_conv2_out_i32_29x29x8.txt";
`else
        out_txt_file = "matlab/debug/txt_cases/paper/tb_conv1_out_i32_62x62x4.txt";
`endif
    if (!$value$plusargs("PASS_ID=%d", pass_id))
      pass_id = 0;

    $display("INFO: running case %0s pass %0d (DOT_K=%0d C_IN=%0d IMG=%0dx%0d OUT=%0dx%0dx%0d)",
             case_name, pass_id, DOT_K, C_IN, IMG_H, IMG_W, OUT_H, OUT_W, OUT_C);

    load_input_image();
    load_weight_and_reorder();
    load_output_reference();

    dump_en = !$test$plusargs("NO_VCD");
    if (dump_en) begin
      if (!$value$plusargs("VCD_FILE=%s", vcd_file))
        vcd_file = DEFAULT_VCD_FILE;
      $display("INFO: dumping VCD to %0s", vcd_file);
      $dumpfile(vcd_file);
      $dumpvars(0, tb_conv_layer_txt);
    end else begin
      $display("INFO: VCD dump disabled by +NO_VCD");
    end

    repeat (5) @(posedge clk);
    rst_n <= 1'b1;

    // Preload weight_buffer
    wb_i = 0;
    while (wb_i < WB_LOAD_CYCLES) begin
      @(negedge clk);
      if (wt_ready) begin
        wt_valid <= 1'b1;
        wt_last  <= (wb_i == (WB_LOAD_CYCLES-1));
        if (wb_i < WB_PREPAD) begin
          wt0 = 8'sd0; wt1 = 8'sd0; wt2 = 8'sd0; wt3 = 8'sd0;
        end else begin
          wt0 = w_tap[0*DOT_K + (wb_i-WB_PREPAD)];
          wt1 = w_tap[1*DOT_K + (wb_i-WB_PREPAD)];
          wt2 = w_tap[2*DOT_K + (wb_i-WB_PREPAD)];
          wt3 = w_tap[3*DOT_K + (wb_i-WB_PREPAD)];
        end
        wt_data[7:0]   <= wt0;
        wt_data[15:8]  <= wt1;
        wt_data[23:16] <= wt2;
        wt_data[31:24] <= wt3;
        wb_i = wb_i + 1;
      end else begin
        wt_valid <= 1'b0;
        wt_last  <= 1'b0;
        wt_data  <= 'sd0;
      end
    end
    @(negedge clk);
    wt_valid <= 1'b0;
    wt_last  <= 1'b0;
    wt_data  <= 'sd0;

    // Stream input in RTL order, packing bytes into 32-bit bus
    in_byte_en <= (BYTES_PER_BEAT == 1) ? 4'b0001 : 4'b1111;
    while (pix_sent < IN_TOTAL) begin
      @(negedge clk);
      if (in_ready) begin
        in_valid <= 1'b1;
        if (BYTES_PER_BEAT == 1) begin
          in_data <= {24'd0, img_mem[pix_sent][7:0]};
          pix_sent = pix_sent + 1;
        end else begin
          in_data <= {img_mem[pix_sent+3][7:0], img_mem[pix_sent+2][7:0],
                      img_mem[pix_sent+1][7:0], img_mem[pix_sent+0][7:0]};
          pix_sent = pix_sent + 4;
        end
      end else begin
        in_valid <= 1'b0;
        in_data <= 32'd0;
      end
    end
    @(negedge clk);
    in_valid <= 1'b0;
    in_data  <= 32'd0;

    // Wait for all outputs
    timeout_cnt = 0;
    while (((checked_cnt < OUT_VALS) ||
            (stream_blk_cnt[0] < OUT_BLOCKS) ||
            (stream_blk_cnt[1] < OUT_BLOCKS) ||
            (stream_blk_cnt[2] < OUT_BLOCKS) ||
            (stream_blk_cnt[3] < OUT_BLOCKS)) &&
           (timeout_cnt < 2000000)) begin
      @(posedge clk);
      timeout_cnt = timeout_cnt + 1;
    end

    // ---------- Result checks ----------
    if (checked_cnt != OUT_VALS) begin
      $display("FAIL: output coverage incomplete. checked_vals=%0d expected_vals=%0d",
               checked_cnt, OUT_VALS);
      $display("DBG: pix_sent=%0d start=%0d sa_done=%0d timeout=%0d",
               pix_sent, start_cnt, sa_done_cnt, timeout_cnt);
      $stop;
    end

    for (col_i = 0; col_i < COLS; col_i = col_i + 1) begin
      if (checked_pix_col[col_i] != OUT_PIX) begin
        $display("FAIL: col%0d coverage mismatch. checked=%0d expected=%0d",
                 col_i, checked_pix_col[col_i], OUT_PIX);
        $stop;
      end
      if (stream_blk_cnt[col_i] < OUT_BLOCKS) begin
        $display("FAIL: col%0d blocks insufficient. blocks=%0d expected>=%0d",
                 col_i, stream_blk_cnt[col_i], OUT_BLOCKS);
        $stop;
      end
    end

    done_blocks_min = stream_blk_cnt[0];
    done_blocks_max = stream_blk_cnt[0];
    for (col_i = 1; col_i < COLS; col_i = col_i + 1) begin
      if (stream_blk_cnt[col_i] < done_blocks_min)
        done_blocks_min = stream_blk_cnt[col_i];
      if (stream_blk_cnt[col_i] > done_blocks_max)
        done_blocks_max = stream_blk_cnt[col_i];
    end
    if (done_blocks_min != done_blocks_max) begin
      $display("FAIL: column block counters diverged. min=%0d max=%0d",
               done_blocks_min, done_blocks_max);
      $stop;
    end
    done_blocks = done_blocks_min;

    if (err_cnt != 0) begin
      $display("FAIL: total mismatches=%0d checked_vals=%0d", err_cnt, checked_cnt);
      $stop;
    end

    $display("PASS: conv layer check passed (pass %0d). outputs=%0d blocks=%0d mismatches=%0d",
             pass_id, checked_pix_col[0], done_blocks, err_cnt);
    $display("PERF: case=%0s layer=%0s pass=%0d rst->last_out=%0d wt_first->last_out=%0d in_first->last_out=%0d start_first->last_out=%0d start_first->last_done=%0d starts=%0d sa_done=%0d",
             case_name, LAYER_NAME, pass_id,
             last_out_cycle,
             (first_wt_cycle >= 0 && last_out_cycle >= 0) ? (last_out_cycle - first_wt_cycle + 1) : -1,
             (first_in_cycle >= 0 && last_out_cycle >= 0) ? (last_out_cycle - first_in_cycle + 1) : -1,
             (first_start_cycle >= 0 && last_out_cycle >= 0) ? (last_out_cycle - first_start_cycle + 1) : -1,
             (first_start_cycle >= 0 && last_done_cycle >= 0) ? (last_done_cycle - first_start_cycle + 1) : -1,
             start_cnt, sa_done_cnt);
    repeat (10) @(posedge clk);
    $finish;
  end

endmodule
