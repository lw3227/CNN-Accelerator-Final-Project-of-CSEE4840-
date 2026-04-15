`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// tb_conv_quant_pool_e2e.v
//
// Generalized E2E testbench for L1/L2/L3 Conv->Quant->Pool.
// DUT: conv_quant_pool (runtime layer_sel).
// Multi-pass support: loops N_PASSES times with inter-pass reset.
//
// Layer selection: +define+LAYER_L2 or +define+LAYER_L3 at compile time.
// Case selection:  +CASE_NAME=paper (runtime plusarg).
// Pass selection:  all passes run automatically unless +PASS_ID=<n> limits to one.
// ---------------------------------------------------------------------------

module tb_conv_quant_pool_e2e;

  localparam integer DATA_W = 8;
  localparam integer ROWS   = 16;
  localparam integer COLS   = 4;
  localparam integer ACC_W  = 23;

`ifdef LAYER_L3
  localparam integer DOT_K = 72;
  localparam integer C_IN  = 8;
  localparam integer IMG_H = 14;
  localparam integer IMG_W = 14;
  localparam integer OUT_H = 12;
  localparam integer OUT_W = 12;
  localparam integer OUT_C = 8;
  localparam integer POOL_H = 6;
  localparam integer POOL_W = 6;
  localparam [1:0] LAYER_SEL = 2'b10;
  localparam integer BYTES_PER_BEAT = 4;
  localparam [8*2-1:0] LAYER_TAG = "L3";
`elsif LAYER_L2
  localparam integer DOT_K = 36;
  localparam integer C_IN  = 4;
  localparam integer IMG_H = 31;
  localparam integer IMG_W = 31;
  localparam integer OUT_H = 29;
  localparam integer OUT_W = 29;
  localparam integer OUT_C = 8;
  localparam integer POOL_H = 14;
  localparam integer POOL_W = 14;
  localparam [1:0] LAYER_SEL = 2'b01;
  localparam integer BYTES_PER_BEAT = 4;
  localparam [8*2-1:0] LAYER_TAG = "L2";
`else // L1 default
  localparam integer DOT_K = 9;
  localparam integer C_IN  = 1;
  localparam integer IMG_H = 64;
  localparam integer IMG_W = 64;
  localparam integer OUT_H = 62;
  localparam integer OUT_W = 62;
  localparam integer OUT_C = 4;
  localparam integer POOL_H = 31;
  localparam integer POOL_W = 31;
  localparam [1:0] LAYER_SEL = 2'b00;
  localparam integer BYTES_PER_BEAT = 1;
  localparam [8*2-1:0] LAYER_TAG = "L1";
`endif

  // DUT hardware parameters: always use system max so that standalone tests
  // exercise the same physical hardware as system_top.
  localparam integer DUT_DOT_K = 72;   // max (L3: 9*8)
  localparam integer DUT_C_IN  = 8;    // max (L3)

  localparam integer IN_TOTAL     = IMG_H * IMG_W * C_IN;
  localparam integer IN_BEATS     = IN_TOTAL / BYTES_PER_BEAT;
  localparam integer OUT_PIX      = OUT_H * OUT_W;
  localparam integer POOL_PIX     = POOL_H * POOL_W;
  localparam integer POOL_VALS    = POOL_PIX * COLS;
  localparam integer POOL_DEPTH   = POOL_H;
  localparam integer N_PASSES     = (OUT_C + COLS - 1) / COLS;
  localparam integer WT_PER_PASS  = COLS * DOT_K;
  localparam integer WB_LOAD_CYCLES = DOT_K + COLS - 1;
  localparam integer WB_PREPAD   = WB_LOAD_CYCLES - DOT_K;
  localparam integer MAX_ERR_PRINT = 30;

  // ---------------------------------------------------------------
  // Clock & Reset
  // ---------------------------------------------------------------
  reg clk;
  reg rst_n;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------
  reg                        in_valid;
  reg        [31:0]          in_data;
  reg        [3:0]           in_byte_en;
  reg                        in_last;
  wire                       in_ready;
  reg                        wt_valid;
  wire                       wt_ready;
  reg                        wt_last;
  reg signed [COLS*DATA_W-1:0] wt_data;
  reg                        cfg_valid;
  wire                       cfg_ready;
  reg        [31:0]          cfg_data;
  reg                        cfg_last;
  reg                        pool_ready;
  wire signed [31:0]         pool_data;
  wire                       pool_valid;
  wire                       pool_last;

  // ---------------------------------------------------------------
  // Data arrays
  // ---------------------------------------------------------------
  reg signed [DATA_W-1:0] img_mem [0:IN_TOTAL-1];
  reg signed [DATA_W-1:0] w_raw   [0:OUT_C*DOT_K-1];
  reg signed [DATA_W-1:0] w_tap   [0:COLS*DOT_K-1];  // per pass
  reg signed [7:0]        ref_pool [0:POOL_VALS-1];   // per pass
  reg signed [31:0]       quant_bias [0:COLS-1];
  reg signed [31:0]       quant_M    [0:COLS-1];
  reg        [7:0]        quant_sh   [0:COLS-1];

  // ---------------------------------------------------------------
  // TB state
  // ---------------------------------------------------------------
  integer fd, scan, lin, val, y, x, t, ch, b;
  integer pix_sent, timeout_cnt, wb_i;
  reg signed [DATA_W-1:0] wt0, wt1, wt2, wt3;
  integer pool_checked, pool_err;
  integer pool_burst_idx, pool_shift_cnt, pool_pix_idx;
  reg signed [7:0] pool_act_ch0, pool_act_ch1, pool_act_ch2, pool_act_ch3;
  reg signed [7:0] pool_exp_ch0, pool_exp_ch1, pool_exp_ch2, pool_exp_ch3;
  integer pass_id, total_pool_err;
  integer cfg_word_idx;

  reg [1023:0] case_name;
  reg [1023:0] in_txt_file, wt_txt_file, pool_txt_file;
  reg [1023:0] bias_txt_file, m_txt_file, sh_txt_file;

  // Per-pass file path construction
  integer single_pass;  // -1 = run all, >=0 = run only that pass
  integer sa_dbg_cnt;
  integer cut_dbg_cnt;
  wire cfg_load_done_unused;
  wire wt_load_done_unused;
  wire pool_frame_done_unused;
  wire conv_frame_rearm_out_unused;

  // ---------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------
  conv_quant_pool #(
    .DOT_K(DUT_DOT_K), .C_IN(DUT_C_IN)
  ) dut (
    .layer_sel(LAYER_SEL),
    .clk(clk), .rst_n(rst_n),
    .in_valid(in_valid), .in_data(in_data), .in_byte_en(in_byte_en),
    .in_last(in_last), .in_ready(in_ready),
    .wt_valid(wt_valid), .wt_ready(wt_ready),
    .wt_last(wt_last), .wt_data(wt_data),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
    .cfg_data(cfg_data), .cfg_last(cfg_last),
    .pool_ready(pool_ready),
    .pool_data(pool_data), .pool_valid(pool_valid), .pool_last(pool_last),
    .cfg_load_done(cfg_load_done_unused),
    .wt_load_done(wt_load_done_unused),
    .pool_frame_done(pool_frame_done_unused),
    .conv_frame_rearm_out(conv_frame_rearm_out_unused)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      sa_dbg_cnt <= 0;
      cut_dbg_cnt <= 0;
    end else begin
      if (pass_id == 1 && dut.u_conv1.c_out_col_valid[0] && sa_dbg_cnt < 4) begin
        $display("DIAG_SA_STANDALONE: pass=%0d idx=%0d col0=%0d col1=%0d col2=%0d col3=%0d valid=%b",
                 pass_id, sa_dbg_cnt,
                 $signed(dut.u_conv1.c_out_col_stream_flat[22:0]),
                 $signed(dut.u_conv1.c_out_col_stream_flat[45:23]),
                 $signed(dut.u_conv1.c_out_col_stream_flat[68:46]),
                 $signed(dut.u_conv1.c_out_col_stream_flat[91:69]),
                 dut.u_conv1.c_out_col_valid);
        sa_dbg_cnt <= sa_dbg_cnt + 1;
      end

      if (pass_id == 1 && dut.u_pool.u_pool_core.lane_cut_valid1 && cut_dbg_cnt < 8) begin
        $display("DIAG_CUT_STANDALONE: pass=%0d idx=%0d c1=%0d c2=%0d c3=%0d c4=%0d",
                 pass_id, cut_dbg_cnt,
                 $signed(dut.u_pool.u_pool_core.cut1),
                 $signed(dut.u_pool.u_pool_core.cut2),
                 $signed(dut.u_pool.u_pool_core.cut3),
                 $signed(dut.u_pool.u_pool_core.cut4));
        cut_dbg_cnt <= cut_dbg_cnt + 1;
      end
    end
  end

  // ---------------------------------------------------------------
  // Data loading tasks
  // ---------------------------------------------------------------
  task load_input_image;
    begin
      fd = $fopen(in_txt_file, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", in_txt_file); $finish; end
      for (lin = 0; lin < IN_TOTAL; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin $display("FAIL: parse error line %0d", lin); $finish; end
        // MATLAB column-major [H, W, C] -> row-major interleaved
        y  = lin % IMG_H;
        t  = lin / IMG_H;
        x  = t % IMG_W;
        ch = t / IMG_W;
        img_mem[(y*IMG_W + x)*C_IN + ch] = $signed(val[DATA_W-1:0]);
      end
      $fclose(fd);
      $display("INFO: loaded input image: %0s (%0d values)", in_txt_file, IN_TOTAL);
    end
  endtask

  task load_all_weights;
    integer wt_offset, raw_idx, kh, kw, c_in_i, rd_col_idx, matlab_idx;
    begin
      fd = $fopen(wt_txt_file, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", wt_txt_file); $finish; end
      for (lin = 0; lin < OUT_C*DOT_K; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin $display("FAIL: wt parse error line %0d", lin); $finish; end
        w_raw[lin] = $signed(val[DATA_W-1:0]);
      end
      $fclose(fd);
      $display("INFO: loaded weights: %0s (%0d values)", wt_txt_file, OUT_C*DOT_K);
    end
  endtask

  task reorder_weights_for_pass;
    input integer pid;
    integer wt_offset, rd_col_idx, kh, kw, c_in_i, matlab_idx;
    begin
      wt_offset = pid * WT_PER_PASS;
      for (ch = 0; ch < COLS; ch = ch + 1) begin
        for (rd_col_idx = 0; rd_col_idx < DOT_K; rd_col_idx = rd_col_idx + 1) begin
          c_in_i = rd_col_idx % C_IN;
          kw     = (rd_col_idx / C_IN) % 3;
          kh     = 2 - (rd_col_idx / (3 * C_IN));
          matlab_idx = kh + 3*kw + 9*c_in_i;
          w_tap[ch*DOT_K + rd_col_idx] = w_raw[wt_offset + ch*DOT_K + matlab_idx];
        end
      end
    end
  endtask

  task load_quant_params_for_pass;
    input integer pid;
    reg [1023:0] bp, mp, sp;
    begin
      $sformat(bp, "%0s", bias_txt_file);
      $sformat(mp, "%0s", m_txt_file);
      $sformat(sp, "%0s", sh_txt_file);

      fd = $fopen(bp, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", bp); $finish; end
      // Skip to pass_id * COLS entries
      for (lin = 0; lin < (pid+1)*COLS; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (lin >= pid*COLS) quant_bias[lin - pid*COLS] = val;
      end
      $fclose(fd);

      fd = $fopen(mp, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", mp); $finish; end
      for (lin = 0; lin < (pid+1)*COLS; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (lin >= pid*COLS) quant_M[lin - pid*COLS] = val;
      end
      $fclose(fd);

      fd = $fopen(sp, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", sp); $finish; end
      for (lin = 0; lin < (pid+1)*COLS; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (lin >= pid*COLS) quant_sh[lin - pid*COLS] = val[7:0];
      end
      $fclose(fd);
    end
  endtask

  task load_pool_reference_for_pass;
    input integer pid;
    integer pool_ch_offset;
    begin
      fd = $fopen(pool_txt_file, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", pool_txt_file); $finish; end
      pool_ch_offset = pid * COLS;
      // MATLAB col-major [POOL_H, POOL_W, OUT_C]. Read all, pick this pass's channels.
      for (lin = 0; lin < POOL_PIX * OUT_C; lin = lin + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        if (scan != 1) begin $display("FAIL: pool parse error line %0d", lin); $finish; end
        y  = lin % POOL_H;
        t  = lin / POOL_H;
        x  = t % POOL_W;
        ch = t / POOL_W;
        if (ch >= pool_ch_offset && ch < pool_ch_offset + COLS)
          ref_pool[(y*POOL_W + x)*COLS + (ch - pool_ch_offset)] = $signed(val[7:0]);
      end
      $fclose(fd);
    end
  endtask

  // ---------------------------------------------------------------
  // Pool output checker (always block)
  // ---------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      pool_checked   <= 0;
      pool_err       <= 0;
      pool_burst_idx <= 0;
      pool_shift_cnt <= 0;
    end else if (pool_valid && pool_ready) begin
      pool_pix_idx = pool_burst_idx * POOL_W + pool_shift_cnt;

      pool_act_ch0 = $signed(pool_data[31:24]);
      pool_act_ch1 = $signed(pool_data[23:16]);
      pool_act_ch2 = $signed(pool_data[15:8]);
      pool_act_ch3 = $signed(pool_data[7:0]);

      if (pool_pix_idx < POOL_PIX) begin
        pool_exp_ch0 = ref_pool[pool_pix_idx*COLS + 0];
        pool_exp_ch1 = ref_pool[pool_pix_idx*COLS + 1];
        pool_exp_ch2 = ref_pool[pool_pix_idx*COLS + 2];
        pool_exp_ch3 = ref_pool[pool_pix_idx*COLS + 3];

        if (pool_act_ch0 !== pool_exp_ch0) begin
          if (pool_err < MAX_ERR_PRINT)
            $display("POOL_ERR: pass=%0d burst=%0d shift=%0d pix=%0d ch0 exp=%0d act=%0d",
                     pass_id, pool_burst_idx, pool_shift_cnt, pool_pix_idx,
                     pool_exp_ch0, pool_act_ch0);
          pool_err = pool_err + 1;
        end
        if (pool_act_ch1 !== pool_exp_ch1) begin
          if (pool_err < MAX_ERR_PRINT)
            $display("POOL_ERR: pass=%0d burst=%0d shift=%0d pix=%0d ch1 exp=%0d act=%0d",
                     pass_id, pool_burst_idx, pool_shift_cnt, pool_pix_idx,
                     pool_exp_ch1, pool_act_ch1);
          pool_err = pool_err + 1;
        end
        if (pool_act_ch2 !== pool_exp_ch2) begin
          if (pool_err < MAX_ERR_PRINT)
            $display("POOL_ERR: pass=%0d burst=%0d shift=%0d pix=%0d ch2 exp=%0d act=%0d",
                     pass_id, pool_burst_idx, pool_shift_cnt, pool_pix_idx,
                     pool_exp_ch2, pool_act_ch2);
          pool_err = pool_err + 1;
        end
        if (pool_act_ch3 !== pool_exp_ch3) begin
          if (pool_err < MAX_ERR_PRINT)
            $display("POOL_ERR: pass=%0d burst=%0d shift=%0d pix=%0d ch3 exp=%0d act=%0d",
                     pass_id, pool_burst_idx, pool_shift_cnt, pool_pix_idx,
                     pool_exp_ch3, pool_act_ch3);
          pool_err = pool_err + 1;
        end
        pool_checked = pool_checked + 4;
      end

      if (pool_last) begin
        pool_shift_cnt <= 0;
        pool_burst_idx <= pool_burst_idx + 1;
      end else begin
        pool_shift_cnt <= pool_shift_cnt + 1;
      end
    end
  end

  // ---------------------------------------------------------------
  // Main stimulus
  // ---------------------------------------------------------------
  initial begin
    rst_n = 1'b0;
    in_valid = 1'b0;
    in_data = 32'd0;
    in_byte_en = (BYTES_PER_BEAT == 1) ? 4'b0001 : 4'b1111;
    in_last = 1'b0;
    wt_valid = 1'b0;
    wt_last = 1'b0;
    wt_data = 'sd0;
    cfg_valid = 1'b0;
    cfg_data = 32'd0;
    cfg_last = 1'b0;
    pool_ready = 1'b1;
    total_pool_err = 0;
    single_pass = -1;
    pass_id = 0;

    case_name = "paper";
    if ($value$plusargs("CASE_NAME=%s", case_name)) ;
    if ($value$plusargs("PASS_ID=%d", single_pass)) ;

    if (single_pass >= N_PASSES) begin
      $display("FAIL: PASS_ID=%0d out of range (N_PASSES=%0d)", single_pass, N_PASSES);
      $finish;
    end

    if ($value$plusargs("IN_TXT=%s", in_txt_file)) ;
    else $sformat(in_txt_file, "unset");
    if ($value$plusargs("WT_TXT=%s", wt_txt_file)) ;
    else $sformat(wt_txt_file, "unset");
    if ($value$plusargs("POOL_TXT=%s", pool_txt_file)) ;
    else $sformat(pool_txt_file, "unset");
    if ($value$plusargs("BIAS_TXT=%s", bias_txt_file)) ;
    else $sformat(bias_txt_file, "unset");
    if ($value$plusargs("M_TXT=%s", m_txt_file)) ;
    else $sformat(m_txt_file, "unset");
    if ($value$plusargs("SH_TXT=%s", sh_txt_file)) ;
    else $sformat(sh_txt_file, "unset");

    if (!$test$plusargs("NO_VCD")) begin
      $dumpfile("/user/stud/fall25/lw3227/vcd/tb_conv_quant_pool_e2e.vcd");
      $dumpvars(0, tb_conv_quant_pool_e2e);
    end

    $display("INFO: %0s E2E case=%0s passes=%0d single_pass=%0d",
             LAYER_TAG, case_name, N_PASSES, single_pass);

    // Load input image and all weights (shared across passes)
    load_input_image();
    load_all_weights();

    // === Multi-pass loop ===
    for (pass_id = 0; pass_id < N_PASSES; pass_id = pass_id + 1) begin
      if (single_pass >= 0 && pass_id != single_pass) begin
        // skip this pass
      end else begin
        $display("INFO: === pass %0d / %0d ===", pass_id, N_PASSES);

        // Prepare per-pass data
        reorder_weights_for_pass(pass_id);
        load_quant_params_for_pass(pass_id);
        load_pool_reference_for_pass(pass_id);

        // Reset DUT
        @(negedge clk);
        rst_n <= 1'b0;
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        // ---- Phase 1: Load quant params via cfg stream (9-word packet) ----
        begin : cfg_load
          reg [31:0] cfg_words [0:8];
          integer cfg_i;
          cfg_words[0] = quant_bias[0];
          cfg_words[1] = quant_bias[1];
          cfg_words[2] = quant_bias[2];
          cfg_words[3] = quant_bias[3];
          cfg_words[4] = quant_M[0];
          cfg_words[5] = quant_M[1];
          cfg_words[6] = quant_M[2];
          cfg_words[7] = quant_M[3];
          cfg_words[8] = {quant_sh[0], quant_sh[1], quant_sh[2], quant_sh[3]};
          cfg_i = 0;
          while (cfg_i < 9) begin
            @(negedge clk);
            if (cfg_ready) begin
              cfg_valid <= 1'b1;
              cfg_data  <= cfg_words[cfg_i];
              cfg_last  <= (cfg_i == 8);
              cfg_i = cfg_i + 1;
            end else begin
              cfg_valid <= 1'b0;
              cfg_data  <= 32'd0;
              cfg_last  <= 1'b0;
            end
          end
          @(negedge clk);
          cfg_valid <= 1'b0;
          cfg_data  <= 32'd0;
          cfg_last  <= 1'b0;
        end
        $display("INFO: quant params loaded for pass %0d", pass_id);

        // ---- Phase 2: Preload weights ----
        wb_i = 0;
        while (wb_i < WB_LOAD_CYCLES) begin
          @(negedge clk);
          if (wt_ready) begin
            wt_valid <= 1'b1;
            wt_last  <= (wb_i == WB_LOAD_CYCLES - 1);
            if (wb_i < WB_PREPAD) begin
              wt0 = 8'sd0; wt1 = 8'sd0; wt2 = 8'sd0; wt3 = 8'sd0;
            end else begin
              wt0 = w_tap[0*DOT_K + (wb_i - WB_PREPAD)];
              wt1 = w_tap[1*DOT_K + (wb_i - WB_PREPAD)];
              wt2 = w_tap[2*DOT_K + (wb_i - WB_PREPAD)];
              wt3 = w_tap[3*DOT_K + (wb_i - WB_PREPAD)];
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
        $display("INFO: weights loaded for pass %0d", pass_id);

        // ---- Phase 3: Stream input image (32-bit bus packing) ----
        pix_sent = 0;
        while (pix_sent < IN_TOTAL) begin
          @(negedge clk);
          if (in_ready) begin
            in_valid <= 1'b1;
            if (BYTES_PER_BEAT == 1) begin
              in_data <= {24'd0, img_mem[pix_sent][7:0]};
              in_last <= (pix_sent == IN_TOTAL - 1);
              pix_sent = pix_sent + 1;
            end else begin
              in_data <= {img_mem[pix_sent+3][7:0], img_mem[pix_sent+2][7:0],
                          img_mem[pix_sent+1][7:0], img_mem[pix_sent+0][7:0]};
              in_last <= (pix_sent + 4 >= IN_TOTAL);
              pix_sent = pix_sent + 4;
            end
          end else begin
            in_valid <= 1'b0;
            in_data  <= 32'd0;
            in_last  <= 1'b0;
          end
        end
        @(negedge clk);
        in_valid <= 1'b0;
        in_data  <= 32'd0;
        in_last  <= 1'b0;

        // ---- Phase 4: Wait for pool outputs ----
        timeout_cnt = 0;
        while ((pool_checked < POOL_VALS) && (timeout_cnt < 2000000)) begin
          @(posedge clk);
          timeout_cnt = timeout_cnt + 1;
        end

        // ---- Per-pass verdict ----
        if (pool_checked < POOL_VALS) begin
          $display("FAIL: pass %0d pool coverage incomplete. checked=%0d expected=%0d",
                   pass_id, pool_checked, POOL_VALS);
          $stop;
        end
        if (pool_err != 0) begin
          $display("FAIL: pass %0d pool mismatches=%0d", pass_id, pool_err);
          total_pool_err = total_pool_err + pool_err;
        end else begin
          $display("PASS: pass %0d pool check OK. checked=%0d", pass_id, pool_checked);
        end
      end
    end

    // ---- Final verdict ----
    $display("------- E2E Verdict -------");
    if (total_pool_err != 0) begin
      $display("FAIL: %0s case=%0s total_pool_err=%0d", LAYER_TAG, case_name, total_pool_err);
      $stop;
    end
    if (single_pass >= 0)
      $display("PASS: %0s case=%0s pass=%0d OK (single-pass mode)", LAYER_TAG, case_name, single_pass);
    else
      $display("PASS: %0s case=%0s ALL %0d PASSES OK", LAYER_TAG, case_name, N_PASSES);
    repeat (10) @(posedge clk);
    $finish;
  end

endmodule
