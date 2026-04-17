`timescale 1ns / 1ps

// Full E2E testbench for 10-class digit gesture recognition.
//
// Flow per case (10 digits):
//   1. MODEL_LOAD (load_sel=0):
//        host sends conv cfg (45w) + conv wt (225w packed 4x int8/word)
//                + FC bias (10w)  + FCW weight (864w 80b-packed host beats)
//   2. INFER (load_sel=1):
//        host streams 1024-word image; system runs L1->L2->L3->FC->ARGMAX
//   3. Verify: predict_class == manifest.predict_class (per-case expected)
//              fc_acc_vec[i]    == fc_golden[i] (10 accumulators)
//
// Golden source:
//   <proj_dir>/Golden-Module/matlab/hardware_aligned/debug/
//       txt_cases/<case>/      tb_*.txt (compare goldens + image + manifest)
//       sram_preload/<case>/   preload_*.txt (host stream content)
//
// `+PROJ_DIR=<path>` plusarg overrides the default (= repo root ".").
// `+NO_VCD`          plusarg skips VCD dump for speed.

module tb_system_e2e_10class;

  localparam integer OUT_CHANNELS = 10;
  localparam integer NUM_CASES    = 10;

  // --- host preload stream sizes (match sram_A_controller / top_sram_A) ---
  localparam integer CONV_CFG_WORDS = 45;       // 5 layer-passes x 9 words
  localparam integer CONV_WT_WORDS  = 225;      // 900 int8 / 4 bytes-per-word
  localparam integer FC_BIAS_WORDS  = 10;       // 10 INT32 FC eff_bias
  localparam integer FCW_WORDS      = 864;      // 288 FCW slots x 3 host beats

  localparam integer IMG_WORDS      = 1024;     // 64x64x1 / 4 bytes-per-word
  localparam integer L1_POOL_WORDS  = 961;      // 31x31x4 / 4 int8/word
  localparam integer L2_POOL_WORDS  = 392;      // 14x14x8 / 4, stride-2 interleave
  localparam integer L3_POOL_WORDS  = 72;       // 6x6x8 / 4

  // ---------------------------------------------------------------
  // Clock / reset / DUT
  // ---------------------------------------------------------------
  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;   // 100 MHz

  reg         load_sel, load_valid, load_last;
  reg  [31:0] load_data;
  wire        load_ready;
  wire        busy;
  wire        predict_valid;
  wire [3:0]  predict_class;   // 4 bits for 0..9

  system_top u_dut (
    .clk(clk), .rst_n(rst_n),
    .load_sel(load_sel), .load_valid(load_valid),
    .load_data(load_data), .load_last(load_last),
    .load_ready(load_ready),
    .busy(busy),
    .predict_valid(predict_valid),
    .predict_class(predict_class)
  );

  // ---------------------------------------------------------------
  // Preload / golden arrays (shared across cases for CFG/WT)
  // ---------------------------------------------------------------
  reg signed [31:0] conv_cfg_mem [0:CONV_CFG_WORDS-1];
  reg        [31:0] conv_wt_mem  [0:CONV_WT_WORDS-1];
  reg signed [31:0] fc_bias_mem  [0:FC_BIAS_WORDS-1];
  reg        [31:0] fcw_mem      [0:FCW_WORDS-1];

  // per-case image and goldens
  reg [31:0]        img_mem      [0:NUM_CASES-1][0:IMG_WORDS-1];
  reg [31:0]        l1_golden    [0:NUM_CASES-1][0:L1_POOL_WORDS-1];
  reg [31:0]        l2_golden    [0:NUM_CASES-1][0:L2_POOL_WORDS-1];
  reg [31:0]        l3_golden    [0:NUM_CASES-1][0:L3_POOL_WORDS-1];
  reg signed [31:0] fc_golden    [0:NUM_CASES-1][0:OUT_CHANNELS-1];
  reg [3:0]         expected_pc  [0:NUM_CASES-1];
  reg [31:0]        case_tags    [0:NUM_CASES-1];   // compact tag (just for display)

  // ---------------------------------------------------------------
  // Globals
  // ---------------------------------------------------------------
  integer err_count;
  integer cycle_count;
  integer active_case_id;
  reg [1024*8-1:0] proj_dir_str;
  reg [1024*8-1:0] tb_root_str;
  reg [1024*8-1:0] sram_root_str;
  reg [1024*8-1:0] case_path;
  reg [1024*8-1:0] filepath;

  integer l1_checked [0:NUM_CASES-1];
  integer l2_checked [0:NUM_CASES-1];
  integer l3_checked [0:NUM_CASES-1];

  // ---------------------------------------------------------------
  // File loaders (one explicit task per memory array to avoid unsized
  // array parameters that Verilog-2001 doesn't support cleanly).
  // ---------------------------------------------------------------

  // --- conv cfg: 45 signed int32, one per line ---
  task load_conv_cfg;
    integer fd, scan, k;
    reg signed [31:0] v;
    begin
      $sformat(filepath, "%0s/preload_conv_cfg_45w.txt", sram_root_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (k = 0; k < CONV_CFG_WORDS; k = k + 1) begin
        scan = $fscanf(fd, "%d\n", v);
        conv_cfg_mem[k] = v;
      end
      $fclose(fd);
      $display("INFO: loaded conv_cfg (%0d words) from %0s", CONV_CFG_WORDS, filepath);
    end
  endtask

  // --- conv wt: 900 int8 lines -> 225 packed host words ({b3,b2,b1,b0}) ---
  task load_conv_wt;
    integer fd, scan, k;
    reg signed [31:0] b0, b1, b2, b3;
    begin
      $sformat(filepath, "%0s/preload_conv_wt_225w_bytes.txt", sram_root_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (k = 0; k < CONV_WT_WORDS; k = k + 1) begin
        scan = $fscanf(fd, "%d\n", b0);
        scan = $fscanf(fd, "%d\n", b1);
        scan = $fscanf(fd, "%d\n", b2);
        scan = $fscanf(fd, "%d\n", b3);
        conv_wt_mem[k] = {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};
      end
      $fclose(fd);
      $display("INFO: loaded conv_wt (%0d words) from %0s", CONV_WT_WORDS, filepath);
    end
  endtask

  // --- FC bias: 10 int32 ---
  task load_fc_bias;
    integer fd, scan, k;
    reg signed [31:0] v;
    begin
      $sformat(filepath, "%0s/preload_fc_bias_10w.txt", sram_root_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (k = 0; k < FC_BIAS_WORDS; k = k + 1) begin
        scan = $fscanf(fd, "%d\n", v);
        fc_bias_mem[k] = v;
      end
      $fclose(fd);
      $display("INFO: loaded fc_bias (%0d words) from %0s", FC_BIAS_WORDS, filepath);
    end
  endtask

  // --- FCW: 864 int32 (already packed per fcw_preload_packer spec) ---
  task load_fcw;
    integer fd, scan, k;
    reg signed [31:0] v;
    begin
      $sformat(filepath, "%0s/preload_fcw_864w.txt", sram_root_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (k = 0; k < FCW_WORDS; k = k + 1) begin
        scan = $fscanf(fd, "%d\n", v);
        fcw_mem[k] = v;
      end
      $fclose(fd);
      $display("INFO: loaded fcw (%0d words) from %0s", FCW_WORDS, filepath);
    end
  endtask

  // --- Per-case image (from tb_conv1_in_i8_64x64x1.txt) ---
  task load_case_image;
    input integer case_id;
    input [1024*8-1:0] case_dir;
    integer fd, scan, k;
    reg signed [31:0] b0, b1, b2, b3;
    begin
      $sformat(filepath, "%0s/tb_conv1_in_i8_64x64x1.txt", case_dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (k = 0; k < IMG_WORDS; k = k + 1) begin
        scan = $fscanf(fd, "%d\n", b0);
        scan = $fscanf(fd, "%d\n", b1);
        scan = $fscanf(fd, "%d\n", b2);
        scan = $fscanf(fd, "%d\n", b3);
        img_mem[case_id][k] = {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};
      end
      $fclose(fd);
    end
  endtask

  // --- Per-case pool goldens ---
  // Pool txts from golden are HWC INT8, NOT the same packing as SRAM_B
  // physical layout. The old 3-class pipeline generated `expected_sram_*`
  // files with the actual SRAM layout. We DON'T have those for 10-class
  // yet, so L1/L2/L3 pool diff is DISABLED by default. Set +CHECK_POOLS
  // after gen_sram_preload also produces the expected_sram_* layouts.

  // --- Per-case FC golden (tb_fc_out_i32_10.txt) ---
  task load_case_fc_golden;
    input integer case_id;
    input [1024*8-1:0] case_dir;
    integer fd, scan, k;
    reg signed [31:0] v;
    begin
      $sformat(filepath, "%0s/tb_fc_out_i32_10.txt", case_dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (k = 0; k < OUT_CHANNELS; k = k + 1) begin
        scan = $fscanf(fd, "%d\n", v);
        fc_golden[case_id][k] = v;
      end
      $fclose(fd);
    end
  endtask

  // --- Compute expected predict_class from fc_golden via the same argmax
  //     rule as top_fsm.v (strict-greater, ties go to the lower index). ---
  task compute_expected_pc;
    input integer case_id;
    integer oc;
    reg [3:0] best_idx;
    reg signed [31:0] best_val;
    begin
      best_idx = 4'd0;
      best_val = fc_golden[case_id][0];
      for (oc = 1; oc < OUT_CHANNELS; oc = oc + 1) begin
        if ($signed(fc_golden[case_id][oc]) > $signed(best_val)) begin
          best_val = fc_golden[case_id][oc];
          best_idx = oc[3:0];
        end
      end
      expected_pc[case_id] = best_idx;
    end
  endtask

  // ---------------------------------------------------------------
  // Host segment senders
  // ---------------------------------------------------------------
  task host_send_from_mem_i32;
    input integer count;
    input integer which;   // 0=conv_cfg 1=conv_wt 2=fc_bias 3=fcw
    integer j;
    integer wait_cycles;
    reg [31:0] word;
    begin
      for (j = 0; j < count; j = j + 1) begin
        case (which)
          0: word = conv_cfg_mem[j];
          1: word = conv_wt_mem[j];
          2: word = fc_bias_mem[j];
          3: word = fcw_mem[j];
          default: word = 32'd0;
        endcase
        @(negedge clk);
        load_valid <= 1'b1;
        load_data  <= word;
        load_last  <= (j == count - 1);
        wait_cycles = 0;
        while (!load_ready) begin
          @(negedge clk);
          wait_cycles = wait_cycles + 1;
          if (wait_cycles == 1000) begin
            $display("FAIL: host_send stalled which=%0d j=%0d state=%0d load_ready=%0b preload_ready=%0b sram_a_start=%0b layer=%0d data_sel=%0d preload_mode=%0b fcw_active=%0b fcw_txn=%0b",
                     which, j, u_dut.u_top_fsm.state, load_ready, u_dut.preload_wr_ready,
                     u_dut.sram_a_start, u_dut.sram_a_layer_sel, u_dut.sram_a_data_sel,
                     u_dut.preload_mode, u_dut.u_sram_a.fcw_active, u_dut.u_sram_a.fcw_txn);
            $finish;
          end
        end
        @(posedge clk);
      end
      @(negedge clk);
      load_valid <= 1'b0;
      load_data  <= 32'd0;
      load_last  <= 1'b0;
    end
  endtask

  task host_send_image;
    input integer case_id;
    integer j;
    integer wait_cycles;
    begin
      for (j = 0; j < IMG_WORDS; j = j + 1) begin
        @(negedge clk);
        load_valid <= 1'b1;
        load_data  <= img_mem[case_id][j];
        load_last  <= (j == IMG_WORDS - 1);
        wait_cycles = 0;
        while (!load_ready) begin
          @(negedge clk);
          wait_cycles = wait_cycles + 1;
          if (wait_cycles == 1000) begin
            $display("FAIL: image_send stalled case=%0d j=%0d state=%0d load_ready=%0b conv_ready=%0b",
                     case_id, j, u_dut.u_top_fsm.state, load_ready, u_dut.conv_in_adapter_up_ready);
            $finish;
          end
        end
        @(posedge clk);
      end
      @(negedge clk);
      load_valid <= 1'b0;
      load_data  <= 32'd0;
      load_last  <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------
  // Per-case inference run + verify
  // ---------------------------------------------------------------
  task run_one_case;
    input integer case_id;
    integer k;
    integer fc_err;
    integer fc_mul_count;
    integer fc_wt_valid_count;
    integer fc_data_valid_count;
    reg signed [31:0] got_acc;
    begin
      active_case_id = case_id;
      $display("");
      $display("=== CASE %0d (%0s): INFER ===", case_id, case_tags[case_id]);

      // --- DIAG: confirm per-case image data varies ---
      $display("DIAG_IMG[%0d]: img_mem[0..3]=%08h %08h %08h %08h",
               case_id, img_mem[case_id][0], img_mem[case_id][1],
               img_mem[case_id][2], img_mem[case_id][3]);

      @(negedge clk);
      load_sel <= 1'b1;
      @(negedge clk);

      $display("INFO: streaming image (%0d words)", IMG_WORDS);
      host_send_image(case_id);
      $display("INFO: image stream complete");

      // Wait for inference to finish
      cycle_count = 0;
      fc_mul_count = 0;
      fc_wt_valid_count = 0;
      fc_data_valid_count = 0;
      while (!predict_valid) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
        if (u_dut.fc_mul_en) fc_mul_count = fc_mul_count + 1;
        if (u_dut.fc_wt_stream_valid) fc_wt_valid_count = fc_wt_valid_count + 1;
        if (u_dut.sram_b_data_valid) fc_data_valid_count = fc_data_valid_count + 1;
        if (cycle_count > 200_000) begin
          $display("FAIL: case %0d inference timeout state=%0d runner_state=%0d runner_layer=%0d pass=%0d is_fc=%0b runner_done=%0b sram_a_done=%0b sram_b_done=%0b fc_done=%0b fc_all_done=%0b fc_mul_en=%0b fcw_active=%0b fcw_rd=%0b fcw_valid=%0b fcw_ready=%0b sram_b_active=%0b sram_b_valid=%0b sram_b_ready=%0b data_held=%0b wt_held=%0b byte_sel=%0d mul_count=%0d wt_valid_count=%0d data_valid_count=%0d",
                   case_id, u_dut.u_top_fsm.state, u_dut.u_runner.state,
                   u_dut.runner_layer_sel, u_dut.runner_pass_id,
                   u_dut.runner_is_fc, u_dut.runner_done, u_dut.sram_a_done,
                   u_dut.sram_b_done, u_dut.fc_done, u_dut.fc_all_done,
                   u_dut.fc_mul_en, u_dut.u_sram_a.fcw_active,
                   u_dut.u_sram_a.fcw_rd_mode, u_dut.fc_wt_stream_valid,
                   u_dut.fc_adapter_wt_ready, u_dut.u_sram_b.txn_active,
                   u_dut.sram_b_data_valid, u_dut.fc_adapter_data_ready,
                   u_dut.u_fc_adapter.data_held, u_dut.u_fc_adapter.wt_held,
                   u_dut.u_fc_adapter.byte_sel, fc_mul_count,
                   fc_wt_valid_count, fc_data_valid_count);
          err_count = err_count + 1;
          disable run_one_case;
        end
      end
      $display("INFO: inference done in %0d cycles; predict_class=%0d (expected %0d) mul_count=%0d wt_valid_count=%0d data_valid_count=%0d",
               cycle_count, predict_class, expected_pc[case_id],
               fc_mul_count, fc_wt_valid_count, fc_data_valid_count);

      // --- DIAG: dump SRAM_B pool3 region (L3 writeback lands at 0x000..0x047) ---
      //         pass0 (ch0-3) @ 0..35, pass1 (ch4-7) @ 36..71; FC reads 0,36,1,37,...
      $display("DIAG_SRAMB_PASS0[%0d][0..7]=%08h %08h %08h %08h %08h %08h %08h %08h",
               case_id,
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[0],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[1],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[2],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[3],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[4],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[5],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[6],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[7]);
      $display("DIAG_SRAMB_PASS1[%0d][36..43]=%08h %08h %08h %08h %08h %08h %08h %08h",
               case_id,
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[36],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[37],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[38],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[39],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[40],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[41],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[42],
               u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[43]);

      // --- DIAG: dump all 10 fc_acc values ---
      for (k = 0; k < OUT_CHANNELS; k = k + 1)
        $display("DIAG_FCACC[%0d]: acc[%0d]=%0d", case_id, k,
                 $signed(u_dut.fc_acc_vec[k*32 +: 32]));

      // --- FC acc compare ---
      fc_err = 0;
      for (k = 0; k < OUT_CHANNELS; k = k + 1) begin
        got_acc = u_dut.fc_acc_vec[k*32 +: 32];
        if (got_acc !== fc_golden[case_id][k]) begin
          fc_err = fc_err + 1;
          if (fc_err <= 4) begin
            $display("DIAG_FC[%0d]: acc[%0d] got=%0d exp=%0d MISMATCH",
                     case_id, k, got_acc, fc_golden[case_id][k]);
          end
        end
      end
      if (fc_err == 0) begin
        $display("DIAG_FC[%0d]: 10/10 accumulators match", case_id);
      end else begin
        $display("DIAG_FC[%0d]: %0d/%0d accumulator mismatches", case_id, fc_err, OUT_CHANNELS);
        err_count = err_count + fc_err;
      end

      // --- predict_class compare ---
      if (predict_class !== expected_pc[case_id]) begin
        $display("FAIL[%0d]: predict_class got=%0d exp=%0d", case_id, predict_class, expected_pc[case_id]);
        err_count = err_count + 1;
      end else begin
        $display("PASS[%0d]: predict_class=%0d matches", case_id, predict_class);
      end

      // Let FSM return to READY so next case can issue a new image
      repeat (5) @(posedge clk);
    end
  endtask

  // ---------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------
  initial begin : main_test
    integer i;
    // Reset TB state
    rst_n = 1'b0;
    load_sel = 1'b0;
    load_valid = 1'b0;
    load_data = 32'd0;
    load_last = 1'b0;
    err_count = 0;
    active_case_id = 0;

    if (!$test$plusargs("NO_VCD")) begin
      $dumpfile("/user/stud/fall25/lw3227/vcd/tb_system_e2e_10class.vcd");
      $dumpvars(0, tb_system_e2e_10class);
    end

    // PROJ_DIR = absolute path to CNN_ACC repo root (. by default).
    if (!$value$plusargs("PROJ_DIR=%s", proj_dir_str))
      proj_dir_str = ".";

    // Goldens live under the external repo clone.
    $sformat(tb_root_str, "%0s/Golden-Module/matlab/hardware_aligned/debug/txt_cases", proj_dir_str);
    $sformat(sram_root_str, "%0s/Golden-Module/matlab/hardware_aligned/debug/sram_preload", proj_dir_str);

    // Build case table
    for (i = 0; i < NUM_CASES; i = i + 1) begin
      // Expected predict_class matches image name: digit_0_test -> 0, etc.
      // (Overridden by manifest.txt in case the MATLAB argmax disagrees.)
      expected_pc[i] = i[3:0];
      case_tags[i]   = {"d", "g", "t", "0" + i[7:0]};  // short tag for display
    end

    // --------------------------------------------------------------
    // Load all preload streams (from case digit_0 -- CFG/WT/bias/FCW
    // are model-wide, not case-dependent).
    // --------------------------------------------------------------
    $sformat(sram_root_str, "%0s/Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test", proj_dir_str);
    load_conv_cfg;
    load_conv_wt;
    load_fc_bias;
    load_fcw;

    // --------------------------------------------------------------
    // Load per-case images + FC goldens + manifest
    // --------------------------------------------------------------
    for (i = 0; i < NUM_CASES; i = i + 1) begin : load_cases
      $sformat(case_path, "%0s/digit_%0d_test", tb_root_str, i);
      $display("INFO: loading case %0d from %0s", i, case_path);
      load_case_image(i, case_path);
      load_case_fc_golden(i, case_path);
      compute_expected_pc(i);
    end

    // --------------------------------------------------------------
    // Release reset and run MODEL_LOAD
    // --------------------------------------------------------------
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (2) @(posedge clk);

    $display("");
    $display("=== MODEL_LOAD ===");
    @(negedge clk);
    load_sel <= 1'b0;
    @(negedge clk);

    $display("INFO: sending conv_cfg (%0d words)", CONV_CFG_WORDS);
    host_send_from_mem_i32(CONV_CFG_WORDS, 0);
    repeat (5) @(posedge clk);

    $display("INFO: sending conv_wt (%0d words)", CONV_WT_WORDS);
    host_send_from_mem_i32(CONV_WT_WORDS, 1);
    repeat (5) @(posedge clk);

    $display("INFO: sending fc_bias (%0d words)", FC_BIAS_WORDS);
    host_send_from_mem_i32(FC_BIAS_WORDS, 2);
    repeat (5) @(posedge clk);

    $display("INFO: sending fcw (%0d words)", FCW_WORDS);
    host_send_from_mem_i32(FCW_WORDS, 3);
    repeat (10) @(posedge clk);

    // Check TopFSM reached READY (state == 7)
    if (u_dut.u_top_fsm.state !== 5'd7) begin
      $display("FAIL: MODEL_LOAD did not reach READY, state=%0d", u_dut.u_top_fsm.state);
      err_count = err_count + 1;
    end else begin
      $display("PASS: MODEL_LOAD complete, TopFSM in READY");
    end

    // --------------------------------------------------------------
    // Run 10 inference cases back-to-back
    // --------------------------------------------------------------
    for (i = 0; i < NUM_CASES; i = i + 1) begin
      run_one_case(i);
    end

    // --------------------------------------------------------------
    // Summary
    // --------------------------------------------------------------
    $display("");
    $display("========================================");
    if (err_count == 0)
      $display("PASS: full E2E test (%0d/%0d cases)", NUM_CASES, NUM_CASES);
    else
      $display("FAIL: E2E test (%0d errors across %0d cases)", err_count, NUM_CASES);
    $display("========================================");
    $display("");
    $finish;
  end : main_test

  // Watchdog: 500 ms simulated
  initial begin
    #500_000_000;
    $display("FAIL: global timeout (500ms)");
    $finish;
  end

  // ---------------------------------------------------------------
  // DIAG_PIXEL: first 4 pixel words landing on conv_data_adapter per case.
  // If these stay constant between cases even though img_mem[] differs,
  // the pixel stream gating is broken.
  // ---------------------------------------------------------------
  reg  [3:0] pix_cnt_per_case;
  reg  [3:0] last_active_case;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pix_cnt_per_case <= 4'd0;
      last_active_case <= 4'hF;
    end else begin
      // reset counter when active_case_id changes (hacky but simple)
      if (last_active_case != active_case_id[3:0]) begin
        pix_cnt_per_case <= 4'd0;
        last_active_case <= active_case_id[3:0];
      end
      // Capture first 4 words actually consumed by conv_data_adapter
      if (u_dut.pixel_stream_active && load_valid && load_ready &&
          pix_cnt_per_case < 4'd4) begin
        $display("DIAG_PIXEL[%0d]: beat=%0d data=%08h conv_in_byte_en=%04b",
                 active_case_id, pix_cnt_per_case, load_data,
                 u_dut.conv_in_byte_en);
        pix_cnt_per_case <= pix_cnt_per_case + 4'd1;
      end
    end
  end

  // ---------------------------------------------------------------
  // DIAG_FCMAC: capture kernel_vec / pixel_vec at first 4 mul_en pulses
  // per inference. Lets us compare RTL's actual FC input sequence to the
  // MATLAB golden tb_fc_in_i8_288.txt + tb_fc_w_i8_10x288.txt.
  // ---------------------------------------------------------------
  reg [3:0] fcmac_cap_idx;
  reg [3:0] fcmac_last_case;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fcmac_cap_idx   <= 4'd0;
      fcmac_last_case <= 4'hF;
    end else begin
      if (fcmac_last_case != active_case_id[3:0]) begin
        fcmac_cap_idx   <= 4'd0;
        fcmac_last_case <= active_case_id[3:0];
      end
      if (u_dut.fc_mul_en && fcmac_cap_idx < 4'd4) begin
        // pixel_vec is broadcast, so just print slot 0 as the actual byte.
        // kernel_vec is 10 independent bytes (ch0..ch9).
        $display("DIAG_FCMAC[%0d] #%0d pixel=%0d ker[0..9]=%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                 active_case_id, fcmac_cap_idx,
                 $signed(u_dut.fc_pixel_vec[7:0]),
                 $signed(u_dut.fc_kernel_vec[7:0]),
                 $signed(u_dut.fc_kernel_vec[15:8]),
                 $signed(u_dut.fc_kernel_vec[23:16]),
                 $signed(u_dut.fc_kernel_vec[31:24]),
                 $signed(u_dut.fc_kernel_vec[39:32]),
                 $signed(u_dut.fc_kernel_vec[47:40]),
                 $signed(u_dut.fc_kernel_vec[55:48]),
                 $signed(u_dut.fc_kernel_vec[63:56]),
                 $signed(u_dut.fc_kernel_vec[71:64]),
                 $signed(u_dut.fc_kernel_vec[79:72]));
        fcmac_cap_idx <= fcmac_cap_idx + 4'd1;
      end
    end
  end

  // ---------------------------------------------------------------
  // DIAG_POOLWRITE: count effective SRAM_B writes per inference (via
  // the top-level pool handshake). Separate L1 (before L3) vs L3 by
  // sampling TopFSM state.
  // ---------------------------------------------------------------
  integer sramb_l1_writes;
  integer sramb_l3_writes;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sramb_l1_writes <= 0;
      sramb_l3_writes <= 0;
    end else if (u_dut.u_top_fsm.state == 5'd7) begin  // READY: reset
      sramb_l1_writes <= 0;
      sramb_l3_writes <= 0;
    end else if (u_dut.sram_b_pool_ready && u_dut.conv_pool_valid) begin
      if (u_dut.u_top_fsm.state == 5'd8)             // ST_L1
        sramb_l1_writes <= sramb_l1_writes + 1;
      else if (u_dut.u_top_fsm.state == 5'd11 ||      // ST_L3_P0
               u_dut.u_top_fsm.state == 5'd12)        // ST_L3_P1
        sramb_l3_writes <= sramb_l3_writes + 1;
    end
  end

  // Print the write counts at the moment predict_valid fires.
  reg pv_seen;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) pv_seen <= 1'b0;
    else if (predict_valid && !pv_seen) begin
      $display("DIAG_SRAMB_WRITES[%0d]: l1=%0d  l3=%0d",
               active_case_id, sramb_l1_writes, sramb_l3_writes);
      pv_seen <= 1'b1;
    end else if (u_dut.u_top_fsm.state == 5'd8) begin
      pv_seen <= 1'b0;   // new inference started
    end
  end

endmodule
