`timescale 1ns/1ps

module tb_conv1_txt;

  localparam [8*128-1:0] DEFAULT_VCD_FILE = "/user/stud/fall25/lw3227/vcd/tb_conv1_txt.vcd";

  localparam integer W      = 64;
  localparam integer DATA_W = 8;
  localparam integer ROWS   = 16;
  localparam integer COLS   = 4;
  localparam integer DOT_K  = 9;
  localparam integer ACC_W  = 23;
  localparam integer IMG_H  = 64;
  localparam integer IMG_W  = 64;

  localparam integer OUT_H = IMG_H - 2;                 // 62
  localparam integer OUT_W = IMG_W - 2;                 // 62
  localparam integer OUT_PIX = OUT_H * OUT_W;           // 3844
  localparam integer OUT_VALS = OUT_PIX * COLS;         // 15376
  localparam integer OUT_BLOCKS = (OUT_PIX + ROWS - 1) / ROWS; // 241
  localparam integer WB_LOAD_CYCLES = DOT_K + COLS - 1; // 12
  localparam integer WB_PREPAD = WB_LOAD_CYCLES - DOT_K; // 3
  localparam integer MAX_ERR_PRINT = 30;

  reg clk;
  reg rst_n;
  reg in_valid;
  reg signed [DATA_W-1:0] in_data;
  wire in_ready;
  reg wt_valid;
`ifdef SIM_POSTSYNTH
  wire wt_ready = 1'b1;
`else
  wire wt_ready;
`endif
  reg wt_last;
  reg signed [COLS*DATA_W-1:0] wt_data;

  wire sa_done;
  wire signed [COLS*ACC_W-1:0] c_out_col_stream_flat;
  wire [COLS-1:0] c_out_col_valid;
  wire [COLS-1:0] c_out_col_last;
  wire wt_load_done_unused;
  wire frame_rearm_out_unused;
  wire frame_done_out_unused;

  // Input image prepared in row-major order for streaming to Conv1_top.
  reg signed [DATA_W-1:0] img_mem [0:IMG_H*IMG_W-1];
  // Raw W1 from MATLAB txt order (column-major over [3,3,4]).
  reg signed [DATA_W-1:0] w_raw [0:COLS*DOT_K-1];
  // Reordered tap sequence per channel for RTL rd_col order.
  reg signed [DATA_W-1:0] w_tap [0:COLS*DOT_K-1];
  // Reference Conv1 MAC outputs indexed as [out_idx*COLS + ch].
  reg signed [31:0] ref_out [0:OUT_PIX*COLS-1];

  integer pix_sent;
  integer timeout_cnt;
  integer wb_i;
  integer done_blocks;
  integer checked_cnt;
  integer err_cnt;
  integer start_cnt;
  integer sa_done_cnt;

  integer lane_i, col_i, out_idx_i;
  integer fd, scan, lin, val, y, x, t, ch, b;
  integer cycle_cnt;
  integer first_wt_cycle, last_wt_cycle;
  integer first_in_cycle, last_in_cycle;
  integer first_start_cycle, last_start_cycle;
  integer first_out_cycle, last_out_cycle;
  integer last_done_cycle;
  integer stream_row_cnt [0:COLS-1];
  integer stream_blk_cnt [0:COLS-1];
  integer checked_pix_col [0:COLS-1];
  integer done_blocks_min;
  integer done_blocks_max;
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
    .C_IN(1)
  ) dut (
    .layer_sel(2'b00),
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .in_data({24'd0, in_data}),
    .in_byte_en(4'b0001),
    .in_last(1'b0),
    .in_ready(in_ready),
`ifdef SIM_POSTSYNTH
    .rd_en(wt_valid),
    .b_in_flat(wt_data),
`else
    .wt_valid(wt_valid),
    .wt_ready(wt_ready),
    .wt_last(wt_last),
    .wt_data(wt_data),
`endif
    .wt_load_done(wt_load_done_unused),
    .sa_done(sa_done),
    .c_out_col_stream_flat(c_out_col_stream_flat),
    .c_out_col_valid(c_out_col_valid),
    .c_out_col_last(c_out_col_last),
    .frame_rearm_out(frame_rearm_out_unused),
    .frame_done_out(frame_done_out_unused)
  );

  task load_input_image;
    begin
      fd = $fopen(in_txt_file, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open input txt: %0s", in_txt_file);
        $finish;
      end
      for (lin = 0; lin < IMG_H*IMG_W; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin
          $display("FAIL: input txt parse error at line %0d", lin);
          $finish;
        end
        // MATLAB txt is column-major over [H,W], convert to row-major stream index.
        y = lin % IMG_H;
        x = lin / IMG_H;
        img_mem[y*IMG_W + x] = $signed(val[DATA_W-1:0]);
      end
      $fclose(fd);
      $display("INFO: loaded input image txt: %0s", in_txt_file);
    end
  endtask

  task load_weight_and_reorder;
    begin
      fd = $fopen(wt_txt_file, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open weight txt: %0s", wt_txt_file);
        $finish;
      end
      for (lin = 0; lin < COLS*DOT_K; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin
          $display("FAIL: weight txt parse error at line %0d", lin);
          $finish;
        end
        w_raw[lin] = $signed(val[DATA_W-1:0]);
      end
      $fclose(fd);

      // MATLAB raw order for each channel:
      // [(r0,c0),(r1,c0),(r2,c0),(r0,c1),(r1,c1),(r2,c1),(r0,c2),(r1,c2),(r2,c2)]
      // RTL tap order by rd_col:
      // [(r2,c0),(r2,c1),(r2,c2),(r1,c0),(r1,c1),(r1,c2),(r0,c0),(r0,c1),(r0,c2)]
      for (ch = 0; ch < COLS; ch = ch + 1) begin
        b = ch * DOT_K;
        w_tap[b + 0] = w_raw[b + 2];
        w_tap[b + 1] = w_raw[b + 5];
        w_tap[b + 2] = w_raw[b + 8];
        w_tap[b + 3] = w_raw[b + 1];
        w_tap[b + 4] = w_raw[b + 4];
        w_tap[b + 5] = w_raw[b + 7];
        w_tap[b + 6] = w_raw[b + 0];
        w_tap[b + 7] = w_raw[b + 3];
        w_tap[b + 8] = w_raw[b + 6];
      end
      $display("INFO: loaded and reordered conv1 weights txt: %0s", wt_txt_file);
    end
  endtask

  task load_output_reference;
    begin
      fd = $fopen(out_txt_file, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open output txt: %0s", out_txt_file);
        $finish;
      end
      for (lin = 0; lin < OUT_PIX*COLS; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin
          $display("FAIL: output txt parse error at line %0d", lin);
          $finish;
        end
        // MATLAB txt is column-major over [OUT_H, OUT_W, COLS].
        y = lin % OUT_H;
        t = lin / OUT_H;
        x = t % OUT_W;
        ch = t / OUT_W;
        out_idx_i = y*OUT_W + x; // row-major pixel index used by this TB.
        ref_out[out_idx_i*COLS + ch] = val;
      end
      $fclose(fd);
      $display("INFO: loaded output reference txt: %0s", out_txt_file);
    end
  endtask

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // 按列串流比较：每列 valid 时都对一笔 golden，last 必须每 16 拍对齐一次。
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

  initial begin
    rst_n = 1'b0;
    in_valid = 1'b0;
    in_data = 'sd0;
    wt_valid = 1'b0;
    wt_last = 1'b0;
    wt_data = 'sd0;
    timeout_cnt = 0;
    pix_sent = 0;

    case_name = "conv1_txt_default";
    in_txt_file = "matlab/debug/tb_conv1_in_i8_64x64x1.txt";
    wt_txt_file = "matlab/debug/tb_conv1_w_i8_3x3x4.txt";
    out_txt_file = "matlab/debug/tb_conv1_out_i32_62x62x4.txt";

    if (!$value$plusargs("CASE_NAME=%s", case_name))
      case_name = case_name;
    if (!$value$plusargs("IN_TXT=%s", in_txt_file))
      in_txt_file = in_txt_file;
    if (!$value$plusargs("WT_TXT=%s", wt_txt_file))
      wt_txt_file = wt_txt_file;
    if (!$value$plusargs("OUT_TXT=%s", out_txt_file))
      out_txt_file = out_txt_file;

    $display("INFO: running case %0s", case_name);

    load_input_image();
    load_weight_and_reorder();
    load_output_reference();

    dump_en = !$test$plusargs("NO_VCD");
    if (dump_en) begin
      if (!$value$plusargs("VCD_FILE=%s", vcd_file))
        vcd_file = DEFAULT_VCD_FILE;
      $display("INFO: dumping VCD to %0s", vcd_file);
      $dumpfile(vcd_file);
      $dumpvars(0, tb_conv1_txt);
    end else begin
      $display("INFO: VCD dump disabled by +NO_VCD");
    end

    repeat (5) @(posedge clk);
    rst_n <= 1'b1;

    // Preload weight_buffer:
    // first WB_PREPAD cycles are dummy, then DOT_K cycles are reordered taps.
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

    // Stream input image in row-major order.
    while (pix_sent < IMG_H*IMG_W) begin
      @(negedge clk);
      if (in_ready) begin
        in_valid <= 1'b1;
        in_data <= img_mem[pix_sent];
        pix_sent = pix_sent + 1;
      end else begin
        in_valid <= 1'b0;
        in_data <= 'sd0;
      end
    end
    @(negedge clk);
    in_valid <= 1'b0;
    in_data  <= 'sd0;

    timeout_cnt = 0;
    while (((checked_cnt < OUT_VALS) ||
            (stream_blk_cnt[0] < OUT_BLOCKS) ||
            (stream_blk_cnt[1] < OUT_BLOCKS) ||
            (stream_blk_cnt[2] < OUT_BLOCKS) ||
            (stream_blk_cnt[3] < OUT_BLOCKS)) &&
           (timeout_cnt < 800000)) begin
      @(posedge clk);
      timeout_cnt = timeout_cnt + 1;
    end

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

    $display("PASS: txt-driven conv1 check passed. outputs=%0d blocks=%0d mismatches=%0d",
             checked_pix_col[0], done_blocks, err_cnt);
    $display("PERF: case=%0s layer=L1 pass=0 rst->last_out=%0d wt_first->last_out=%0d in_first->last_out=%0d start_first->last_out=%0d start_first->last_done=%0d starts=%0d sa_done=%0d",
             case_name,
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
