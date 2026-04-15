`timescale 1ns / 1ps

// Full E2E testbench for system_top.
//
// Flow:
//   1. MODEL_LOAD (load_sel=0): host sends cfg(48w) + wt(513w) + image(1024w)
//   2. LOAD_IMAGE (load_sel=1): send same/new image → auto inference → predict
//   3. Repeat for rock / scissors images
//
// Golden data loaded from matlab/debug/sram_preload/{paper,rock,scissors}/

// =============================================================================
// tb_system_e2e_gate.v — gate-level variant of tb_system_e2e.v
//
// Identical to tb_system_e2e.v EXCEPT that SRAM mem[] probes are adapted for
// the foundry macro's packed layout: reg [255:0] mem [0:127], with 8 words
// packed per 256-bit row (column mux ratio 8).
//
// Word extraction from address A[9:0]:
//   row  = mem[A[9:3]];
//   word = row[A[2:0] * 32 +: 32];
//
// Two helper functions (get_word_sram_a / get_word_sram_b) wrap this so the
// probe call sites look the same as the behavioral TB.
//
// DO NOT add new features here directly — keep this file mechanically derived
// from tb_system_e2e.v. If tb_system_e2e.v changes, re-sync by copying and
// re-applying the probe patches in DIAG_L1POOL / DIAG_L2POOL / DIAG_L3POOL /
// DIAG_L3IN.
// =============================================================================

module tb_system_e2e_gate;

  // ---------------------------------------------------------------
  // Gate-level SRAM word extraction helpers
  //
  // Foundry macro mem[] layout: reg [255:0] mem [0:127]
  // Column mux ratio = 8. Bits are BIT-INTERLEAVED, not packed:
  //   D[i] of address A goes to row[i*8 + A[2:0]]
  // Read (mirroring sram_A.v line 277-283):
  //   data_shifted = row >> A[2:0];
  //   word[i] = data_shifted[i*8]   for i in 0..31
  // ---------------------------------------------------------------
  function automatic [31:0] get_word_sram_a;
    input [9:0] addr;
    reg [255:0] row;
    reg [255:0] data_shifted;
    integer bi;
    begin
      row = u_dut.u_sram_a.u_sram_A_wrapper.sram_A_inst.mem[addr[9:3]];
      data_shifted = row >> addr[2:0];
      for (bi = 0; bi < 32; bi = bi + 1)
        get_word_sram_a[bi] = data_shifted[bi * 8];
    end
  endfunction

  function automatic [31:0] get_word_sram_b;
    input [9:0] addr;
    reg [255:0] row;
    reg [255:0] data_shifted;
    integer bi;
    begin
      row = u_dut.u_sram_b.u_sram_B_wrapper.sram_B_inst.mem[addr[9:3]];
      data_shifted = row >> addr[2:0];
      for (bi = 0; bi < 32; bi = bi + 1)
        get_word_sram_b[bi] = data_shifted[bi * 8];
    end
  endfunction

  // ---------------------------------------------------------------
  // Clock / Reset
  // ---------------------------------------------------------------
  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;  // 100 MHz

  // ---------------------------------------------------------------
  // DUT interface
  // ---------------------------------------------------------------
  reg         load_sel, load_valid;
  reg  [31:0] load_data;
  reg         load_last;
  wire        load_ready;
  wire        busy;
  wire        predict_valid;
  wire [1:0]  predict_class;

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
  // Golden data arrays
  // ---------------------------------------------------------------
  // CFG: 48 words (int32)
  reg signed [31:0] cfg_mem [0:47];

  // WT: 513 words (packed from 2052 int8)
  reg [31:0] wt_mem [0:512];

  // Image: 1024 words per case (packed from 4096 int8)
  reg [31:0] img_paper [0:1023];
  reg [31:0] img_rock  [0:1023];
  reg [31:0] img_scissors [0:1023];

  // Expected FC outputs
  reg signed [31:0] expected_fc [0:2];

  // ---------------------------------------------------------------
  // Data loading helpers
  // ---------------------------------------------------------------
  integer fd, scan_ret, i;
  reg signed [31:0] val;
  reg signed [7:0] b0, b1, b2, b3;
  reg [1024*8-1:0] proj_dir_str;
  reg [1024*8-1:0] filepath;
  reg [31:0] active_case_id;
  reg l1_dump_done;
  reg l2_checked;
  reg l3_input_checked;
  reg fc_checked;
  reg [31:0] l1_pool_rm [0:960];  // row-major golden (961 words)
  reg [31:0] l2_golden [0:391];
  reg [31:0] l3_golden [0:71];
  reg signed [31:0] fc_golden [0:2];

  // ---------------------------------------------------------------
  // Performance counters
  // ---------------------------------------------------------------
  localparam [3:0] TOP_ST_PL_CFG     = 4'd1,
                   TOP_ST_PL_CFG_W   = 4'd2,
                   TOP_ST_PL_WT      = 4'd3,
                   TOP_ST_PL_WT_W    = 4'd4,
                   TOP_ST_PL_PIXEL   = 4'd5,
                   TOP_ST_PL_PIXEL_W = 4'd6,
                   TOP_ST_L1         = 4'd8,
                   TOP_ST_L2_P0      = 4'd9,
                   TOP_ST_L2_P1      = 4'd10,
                   TOP_ST_L3_P0      = 4'd11,
                   TOP_ST_L3_P1      = 4'd12,
                   TOP_ST_FC         = 4'd13,
                   TOP_ST_ARGMAX     = 4'd14;

  localparam [2:0] RUN_ST_IDLE      = 3'd0,
                   RUN_ST_LOAD_CFG  = 3'd1,
                   RUN_ST_WAIT_CFG  = 3'd2,
                   RUN_ST_LOAD_WT   = 3'd3,
                   RUN_ST_WAIT_WT   = 3'd4,
                   RUN_ST_STREAM    = 3'd5,
                   RUN_ST_WAIT_DONE = 3'd6,
                   RUN_ST_DONE      = 3'd7;

  integer model_cfg_cycles, model_wt_cycles, model_pixel_cycles;
  integer infer_pixel_cycles, infer_argmax_cycles;
  integer l1_total_cycles,   l1_cfg_cycles,   l1_wt_cycles,   l1_data_cycles;
  integer l2p0_total_cycles, l2p0_cfg_cycles, l2p0_wt_cycles, l2p0_data_cycles;
  integer l2p1_total_cycles, l2p1_cfg_cycles, l2p1_wt_cycles, l2p1_data_cycles;
  integer l3p0_total_cycles, l3p0_cfg_cycles, l3p0_wt_cycles, l3p0_data_cycles;
  integer l3p1_total_cycles, l3p1_cfg_cycles, l3p1_wt_cycles, l3p1_data_cycles;
  integer fc_total_cycles,   fc_cfg_cycles,   fc_wt_cycles,   fc_data_cycles;

  task reset_model_load_counters;
    begin
      model_cfg_cycles   = 0;
      model_wt_cycles    = 0;
      model_pixel_cycles = 0;
    end
  endtask

  task reset_infer_counters;
    begin
      infer_pixel_cycles = 0;
      infer_argmax_cycles = 0;

      l1_total_cycles = 0;   l1_cfg_cycles = 0;   l1_wt_cycles = 0;   l1_data_cycles = 0;
      l2p0_total_cycles = 0; l2p0_cfg_cycles = 0; l2p0_wt_cycles = 0; l2p0_data_cycles = 0;
      l2p1_total_cycles = 0; l2p1_cfg_cycles = 0; l2p1_wt_cycles = 0; l2p1_data_cycles = 0;
      l3p0_total_cycles = 0; l3p0_cfg_cycles = 0; l3p0_wt_cycles = 0; l3p0_data_cycles = 0;
      l3p1_total_cycles = 0; l3p1_cfg_cycles = 0; l3p1_wt_cycles = 0; l3p1_data_cycles = 0;
      fc_total_cycles = 0;   fc_cfg_cycles = 0;   fc_wt_cycles = 0;   fc_data_cycles = 0;
    end
  endtask

  task print_model_load_cycle_summary;
    integer model_total_cycles;
    begin
      model_total_cycles = model_cfg_cycles + model_wt_cycles + model_pixel_cycles;
      $display("CYCLE_SUMMARY[MODEL_LOAD]: cfg=%0d wt=%0d pixel=%0d total=%0d",
               model_cfg_cycles, model_wt_cycles, model_pixel_cycles, model_total_cycles);
    end
  endtask

  task print_infer_cycle_summary;
    input [8*16-1:0] case_name;
    integer l2_total_cycles;
    integer l3_total_cycles;
    integer layer_total_cycles;
    integer infer_total_cycles;
    begin
      l2_total_cycles = l2p0_total_cycles + l2p1_total_cycles;
      l3_total_cycles = l3p0_total_cycles + l3p1_total_cycles;
      layer_total_cycles = l1_total_cycles + l2_total_cycles + l3_total_cycles + fc_total_cycles;
      infer_total_cycles = infer_pixel_cycles + layer_total_cycles + infer_argmax_cycles;

      $display("CYCLE_SUMMARY[%0s]: preload_pixel=%0d argmax=%0d end_to_end=%0d",
               case_name, infer_pixel_cycles, infer_argmax_cycles, infer_total_cycles);
      $display("CYCLE_SUMMARY[%0s]: L1    total=%0d cfg=%0d wt=%0d data=%0d",
               case_name, l1_total_cycles, l1_cfg_cycles, l1_wt_cycles, l1_data_cycles);
      $display("CYCLE_SUMMARY[%0s]: L2_P0 total=%0d cfg=%0d wt=%0d data=%0d",
               case_name, l2p0_total_cycles, l2p0_cfg_cycles, l2p0_wt_cycles, l2p0_data_cycles);
      $display("CYCLE_SUMMARY[%0s]: L2_P1 total=%0d cfg=%0d wt=%0d data=%0d",
               case_name, l2p1_total_cycles, l2p1_cfg_cycles, l2p1_wt_cycles, l2p1_data_cycles);
      $display("CYCLE_SUMMARY[%0s]: L2    total=%0d",
               case_name, l2_total_cycles);
      $display("CYCLE_SUMMARY[%0s]: L3_P0 total=%0d cfg=%0d wt=%0d data=%0d",
               case_name, l3p0_total_cycles, l3p0_cfg_cycles, l3p0_wt_cycles, l3p0_data_cycles);
      $display("CYCLE_SUMMARY[%0s]: L3_P1 total=%0d cfg=%0d wt=%0d data=%0d",
               case_name, l3p1_total_cycles, l3p1_cfg_cycles, l3p1_wt_cycles, l3p1_data_cycles);
      $display("CYCLE_SUMMARY[%0s]: L3    total=%0d",
               case_name, l3_total_cycles);
      $display("CYCLE_SUMMARY[%0s]: FC    total=%0d cfg=%0d wt=%0d data=%0d",
               case_name, fc_total_cycles, fc_cfg_cycles, fc_wt_cycles, fc_data_cycles);
      $display("CYCLE_SUMMARY[%0s]: layers_total=%0d",
               case_name, layer_total_cycles);
    end
  endtask

  task load_cfg_file;
    input [1024*8-1:0] dir;
    begin
      $sformat(filepath, "%0s/sram_a_cfg_48w.txt", dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (i = 0; i < 48; i = i + 1) begin
        scan_ret = $fscanf(fd, "%d\n", val);
        cfg_mem[i] = val;
      end
      $fclose(fd);
    end
  endtask

  task load_wt_file;
    input [1024*8-1:0] dir;
    integer j;
    reg signed [31:0] tb0, tb1, tb2, tb3;
    begin
      $sformat(filepath, "%0s/sram_a_wt_513w.txt", dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (j = 0; j < 513; j = j + 1) begin
        scan_ret = $fscanf(fd, "%d\n", tb0);
        scan_ret = $fscanf(fd, "%d\n", tb1);
        scan_ret = $fscanf(fd, "%d\n", tb2);
        scan_ret = $fscanf(fd, "%d\n", tb3);
        wt_mem[j] = {tb3[7:0], tb2[7:0], tb1[7:0], tb0[7:0]};
      end
      $fclose(fd);
    end
  endtask

  task load_image_file;
    input [1024*8-1:0] dir;
    integer j;
    reg signed [31:0] ib0, ib1, ib2, ib3;
    begin
      $sformat(filepath, "%0s/sram_a_image_1024w.txt", dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (j = 0; j < 1024; j = j + 1) begin
        scan_ret = $fscanf(fd, "%d\n", ib0);
        scan_ret = $fscanf(fd, "%d\n", ib1);
        scan_ret = $fscanf(fd, "%d\n", ib2);
        scan_ret = $fscanf(fd, "%d\n", ib3);
        img_paper[j] = {ib3[7:0], ib2[7:0], ib1[7:0], ib0[7:0]};
      end
      $fclose(fd);
    end
  endtask

  task load_image_file_to;
    input [1024*8-1:0] dir;
    // output goes to a temp, caller copies
    integer j;
    reg signed [31:0] ib0, ib1, ib2, ib3;
    begin
      $sformat(filepath, "%0s/sram_a_image_1024w.txt", dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (j = 0; j < 1024; j = j + 1) begin
        scan_ret = $fscanf(fd, "%d\n", ib0);
        scan_ret = $fscanf(fd, "%d\n", ib1);
        scan_ret = $fscanf(fd, "%d\n", ib2);
        scan_ret = $fscanf(fd, "%d\n", ib3);
        img_rock[j] = {ib3[7:0], ib2[7:0], ib1[7:0], ib0[7:0]};
      end
      $fclose(fd);
    end
  endtask

  task load_l1_pool_golden;
    input [1024*8-1:0] dir;
    integer j, fd_local, scan_local;
    reg signed [31:0] gb0, gb1, gb2, gb3;
    begin
      $sformat(filepath, "%0s/expected_sram_b_l1_pool_961w.txt", dir);
      fd_local = $fopen(filepath, "r");
      if (fd_local == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (j = 0; j < 961; j = j + 1) begin
        scan_local = $fscanf(fd_local, "%d\n", gb0);
        scan_local = $fscanf(fd_local, "%d\n", gb1);
        scan_local = $fscanf(fd_local, "%d\n", gb2);
        scan_local = $fscanf(fd_local, "%d\n", gb3);
        l1_pool_rm[j] = {gb0[7:0], gb1[7:0], gb2[7:0], gb3[7:0]};
      end
      $fclose(fd_local);
    end
  endtask

  task load_l2_pool_golden;
    input [1024*8-1:0] dir;
    integer j, fd_local, scan_local;
    reg signed [31:0] gb0, gb1, gb2, gb3;
    begin
      $sformat(filepath, "%0s/expected_sram_a_l2_pool_392w.txt", dir);
      fd_local = $fopen(filepath, "r");
      if (fd_local == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (j = 0; j < 392; j = j + 1) begin
        scan_local = $fscanf(fd_local, "%d\n", gb0);
        scan_local = $fscanf(fd_local, "%d\n", gb1);
        scan_local = $fscanf(fd_local, "%d\n", gb2);
        scan_local = $fscanf(fd_local, "%d\n", gb3);
        l2_golden[j] = {gb0[7:0], gb1[7:0], gb2[7:0], gb3[7:0]};
      end
      $fclose(fd_local);
    end
  endtask

  task load_l3_pool_golden;
    input [1024*8-1:0] dir;
    integer j, fd_local, scan_local;
    reg signed [31:0] gb0, gb1, gb2, gb3;
    begin
      $sformat(filepath, "%0s/expected_sram_b_l3_pool_72w.txt", dir);
      fd_local = $fopen(filepath, "r");
      if (fd_local == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (j = 0; j < 72; j = j + 1) begin
        scan_local = $fscanf(fd_local, "%d\n", gb0);
        scan_local = $fscanf(fd_local, "%d\n", gb1);
        scan_local = $fscanf(fd_local, "%d\n", gb2);
        scan_local = $fscanf(fd_local, "%d\n", gb3);
        l3_golden[j] = {gb0[7:0], gb1[7:0], gb2[7:0], gb3[7:0]};
      end
      $fclose(fd_local);
    end
  endtask

  task load_fc_golden;
    input [1024*8-1:0] dir;
    integer j, fd_local, scan_local;
    reg signed [31:0] gval;
    begin
      $sformat(filepath, "%0s/expected_fc_out_i32_3.txt", dir);
      fd_local = $fopen(filepath, "r");
      if (fd_local == 0) begin
        $display("FAIL: cannot open %0s", filepath);
        $finish;
      end
      for (j = 0; j < 3; j = j + 1) begin
        scan_local = $fscanf(fd_local, "%d\n", gval);
        fc_golden[j] = gval;
      end
      $fclose(fd_local);
    end
  endtask

  task load_case_goldens;
    input [1024*8-1:0] dir;
    begin
      load_l1_pool_golden(dir);
      load_l2_pool_golden(dir);
      load_l3_pool_golden(dir);
      load_fc_golden(dir);
    end
  endtask

  // ---------------------------------------------------------------
  // Host send tasks
  // ---------------------------------------------------------------
  // Send one word with valid/ready handshake
  task host_send_word;
    input [31:0] word;
    input        last;
    begin
      @(negedge clk);
      load_valid <= 1'b1;
      load_data  <= word;
      load_last  <= last;
      @(posedge clk);
      while (!load_ready) @(posedge clk);
      // Handshake succeeded on this posedge
      @(negedge clk);
      load_valid <= 1'b0;
      load_data  <= 32'd0;
      load_last  <= 1'b0;
    end
  endtask

  // Send a segment from memory array
  task host_send_cfg_segment;
    integer j;
    begin
      for (j = 0; j < 48; j = j + 1) begin
        @(negedge clk);
        load_valid <= 1'b1;
        load_data  <= cfg_mem[j];
        load_last  <= (j == 47);
        @(posedge clk);
        while (!load_ready) @(posedge clk);
      end
      @(negedge clk);
      load_valid <= 1'b0;
      load_data  <= 32'd0;
      load_last  <= 1'b0;
    end
  endtask

  task host_send_wt_segment;
    integer j;
    begin
      for (j = 0; j < 513; j = j + 1) begin
        @(negedge clk);
        load_valid <= 1'b1;
        load_data  <= wt_mem[j];
        load_last  <= (j == 512);
        @(posedge clk);
        while (!load_ready) @(posedge clk);
      end
      @(negedge clk);
      load_valid <= 1'b0;
      load_data  <= 32'd0;
      load_last  <= 1'b0;
    end
  endtask

  // Send image from one of the image arrays
  // img_sel: 0=paper, 1=rock, 2=scissors
  task host_send_image_segment;
    input [1:0] img_sel;
    integer j;
    reg [31:0] word;
    begin
      for (j = 0; j < 1024; j = j + 1) begin
        case (img_sel)
          2'd0: word = img_paper[j];
          2'd1: word = img_rock[j];
          2'd2: word = img_scissors[j];
          default: word = 32'd0;
        endcase
        @(negedge clk);
        load_valid <= 1'b1;
        load_data  <= word;
        load_last  <= (j == 1023);
        @(posedge clk);
        while (!load_ready) @(posedge clk);
      end
      @(negedge clk);
      load_valid <= 1'b0;
      load_data  <= 32'd0;
      load_last  <= 1'b0;
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reset_model_load_counters;
      reset_infer_counters;
    end else begin
      case (u_dut.u_top_fsm.state)
        TOP_ST_PL_CFG,
        TOP_ST_PL_CFG_W: begin
          if (!load_sel)
            model_cfg_cycles = model_cfg_cycles + 1;
        end

        TOP_ST_PL_WT,
        TOP_ST_PL_WT_W: begin
          if (!load_sel)
            model_wt_cycles = model_wt_cycles + 1;
        end

        // PL_PIXEL states removed: pixels now stream during L1.
        // model_pixel_cycles stays 0; infer_pixel_cycles measured via L1.
        TOP_ST_PL_PIXEL,
        TOP_ST_PL_PIXEL_W: begin
          // never hit
        end

        TOP_ST_L1: begin
          l1_total_cycles = l1_total_cycles + 1;
          case (u_dut.u_runner.state)
            RUN_ST_IDLE,
            RUN_ST_LOAD_CFG,
            RUN_ST_WAIT_CFG: l1_cfg_cycles = l1_cfg_cycles + 1;
            RUN_ST_LOAD_WT,
            RUN_ST_WAIT_WT:  l1_wt_cycles = l1_wt_cycles + 1;
            RUN_ST_STREAM,
            RUN_ST_WAIT_DONE,
            RUN_ST_DONE:     l1_data_cycles = l1_data_cycles + 1;
          endcase
        end

        TOP_ST_L2_P0: begin
          l2p0_total_cycles = l2p0_total_cycles + 1;
          case (u_dut.u_runner.state)
            RUN_ST_IDLE,
            RUN_ST_LOAD_CFG,
            RUN_ST_WAIT_CFG: l2p0_cfg_cycles = l2p0_cfg_cycles + 1;
            RUN_ST_LOAD_WT,
            RUN_ST_WAIT_WT:  l2p0_wt_cycles = l2p0_wt_cycles + 1;
            RUN_ST_STREAM,
            RUN_ST_WAIT_DONE,
            RUN_ST_DONE:     l2p0_data_cycles = l2p0_data_cycles + 1;
          endcase
        end

        TOP_ST_L2_P1: begin
          l2p1_total_cycles = l2p1_total_cycles + 1;
          case (u_dut.u_runner.state)
            RUN_ST_IDLE,
            RUN_ST_LOAD_CFG,
            RUN_ST_WAIT_CFG: l2p1_cfg_cycles = l2p1_cfg_cycles + 1;
            RUN_ST_LOAD_WT,
            RUN_ST_WAIT_WT:  l2p1_wt_cycles = l2p1_wt_cycles + 1;
            RUN_ST_STREAM,
            RUN_ST_WAIT_DONE,
            RUN_ST_DONE:     l2p1_data_cycles = l2p1_data_cycles + 1;
          endcase
        end

        TOP_ST_L3_P0: begin
          l3p0_total_cycles = l3p0_total_cycles + 1;
          case (u_dut.u_runner.state)
            RUN_ST_IDLE,
            RUN_ST_LOAD_CFG,
            RUN_ST_WAIT_CFG: l3p0_cfg_cycles = l3p0_cfg_cycles + 1;
            RUN_ST_LOAD_WT,
            RUN_ST_WAIT_WT:  l3p0_wt_cycles = l3p0_wt_cycles + 1;
            RUN_ST_STREAM,
            RUN_ST_WAIT_DONE,
            RUN_ST_DONE:     l3p0_data_cycles = l3p0_data_cycles + 1;
          endcase
        end

        TOP_ST_L3_P1: begin
          l3p1_total_cycles = l3p1_total_cycles + 1;
          case (u_dut.u_runner.state)
            RUN_ST_IDLE,
            RUN_ST_LOAD_CFG,
            RUN_ST_WAIT_CFG: l3p1_cfg_cycles = l3p1_cfg_cycles + 1;
            RUN_ST_LOAD_WT,
            RUN_ST_WAIT_WT:  l3p1_wt_cycles = l3p1_wt_cycles + 1;
            RUN_ST_STREAM,
            RUN_ST_WAIT_DONE,
            RUN_ST_DONE:     l3p1_data_cycles = l3p1_data_cycles + 1;
          endcase
        end

        TOP_ST_FC: begin
          fc_total_cycles = fc_total_cycles + 1;
          case (u_dut.u_runner.state)
            RUN_ST_IDLE,
            RUN_ST_LOAD_CFG,
            RUN_ST_WAIT_CFG: fc_cfg_cycles = fc_cfg_cycles + 1;
            RUN_ST_LOAD_WT,
            RUN_ST_WAIT_WT:  fc_wt_cycles = fc_wt_cycles + 1;
            RUN_ST_STREAM,
            RUN_ST_WAIT_DONE,
            RUN_ST_DONE:     fc_data_cycles = fc_data_cycles + 1;
          endcase
        end

        TOP_ST_ARGMAX: begin
          infer_argmax_cycles = infer_argmax_cycles + 1;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------
  integer err_count;
  integer cycle_count;
  reg [1024*8-1:0] case_dir;
  reg stop_after_l3pool;
  reg l3_checked;

  initial begin : main_test
    rst_n = 1'b0;
    load_sel = 1'b0;
    load_valid = 1'b0;
    load_data = 32'd0;
    load_last = 1'b0;
    active_case_id = 0;
    err_count = 0;
    stop_after_l3pool = $test$plusargs("STOP_AFTER_L3POOL");

    // VCD dump (controlled by plusarg)
    if (!$test$plusargs("NO_VCD")) begin
      $dumpfile("/user/stud/fall25/lw3227/vcd/tb_system_e2e_gate.vcd");
      $dumpvars(0, tb_system_e2e_gate);
    end

    // ---- Load golden data from files ----
    if ($value$plusargs("PROJ_DIR=%s", proj_dir_str)) begin
      // use plusarg
    end else begin
      proj_dir_str = ".";
    end

    // Load cfg & weight (same for all cases)
    $sformat(case_dir, "%0s/matlab/debug/sram_preload/paper", proj_dir_str);
    $display("INFO: loading cfg from %0s", case_dir);
    load_cfg_file(case_dir);
    $display("INFO: loading weight from %0s", case_dir);
    load_wt_file(case_dir);

    // Load paper image
    $display("INFO: loading paper image");
    load_image_file(case_dir);
    // img_paper is now loaded

    // Load rock image into img_rock
    $sformat(case_dir, "%0s/matlab/debug/sram_preload/rock", proj_dir_str);
    $display("INFO: loading rock image");
    begin : load_rock_blk
      integer j;
      reg signed [31:0] ib0, ib1, ib2, ib3;
      $sformat(filepath, "%0s/sram_a_image_1024w.txt", case_dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", filepath); $finish; end
      for (j = 0; j < 1024; j = j + 1) begin
        scan_ret = $fscanf(fd, "%d\n", ib0);
        scan_ret = $fscanf(fd, "%d\n", ib1);
        scan_ret = $fscanf(fd, "%d\n", ib2);
        scan_ret = $fscanf(fd, "%d\n", ib3);
        img_rock[j] = {ib3[7:0], ib2[7:0], ib1[7:0], ib0[7:0]};
      end
      $fclose(fd);
    end

    // Load scissors image into img_scissors
    $sformat(case_dir, "%0s/matlab/debug/sram_preload/scissors", proj_dir_str);
    $display("INFO: loading scissors image");
    begin : load_scissors_blk
      integer j;
      reg signed [31:0] ib0, ib1, ib2, ib3;
      $sformat(filepath, "%0s/sram_a_image_1024w.txt", case_dir);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin $display("FAIL: cannot open %0s", filepath); $finish; end
      for (j = 0; j < 1024; j = j + 1) begin
        scan_ret = $fscanf(fd, "%d\n", ib0);
        scan_ret = $fscanf(fd, "%d\n", ib1);
        scan_ret = $fscanf(fd, "%d\n", ib2);
        scan_ret = $fscanf(fd, "%d\n", ib3);
        img_scissors[j] = {ib3[7:0], ib2[7:0], ib1[7:0], ib0[7:0]};
      end
      $fclose(fd);
    end

    $display("INFO: all golden data loaded");

    // ---- Reset ----
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (2) @(posedge clk);

    // ================================================================
    // TEST 1: MODEL_LOAD (CFG + WT only — pixels stream during inference)
    // ================================================================
    reset_model_load_counters;
    $display("\n=== TEST: MODEL_LOAD ===");
    load_sel <= 1'b0;
    @(negedge clk);

    $display("INFO: sending CFG segment (48 words)...");
    host_send_cfg_segment;
    repeat (5) @(posedge clk);

    $display("INFO: sending WEIGHT segment (513 words)...");
    host_send_wt_segment;
    repeat (10) @(posedge clk);

    // Check TopFSM reached READY (no PL_PIXEL anymore)
    if (u_dut.u_top_fsm.state != 4'd7) begin
      $display("FAIL: MODEL_LOAD did not reach READY, state=%0d", u_dut.u_top_fsm.state);
      err_count = err_count + 1;
    end else begin
      $display("PASS: MODEL_LOAD complete, TopFSM in READY");
    end
    print_model_load_cycle_summary;

    // ================================================================
    // TEST 2: LOAD_IMAGE + INFERENCE (paper)
    // ================================================================
    $display("\n=== TEST: PAPER INFERENCE ===");
    active_case_id = 0;
    $sformat(case_dir, "%0s/matlab/debug/sram_preload/paper", proj_dir_str);
    load_case_goldens(case_dir);
    l1_dump_done = 0;
    l2_checked = 0;
    l3_checked = 0;
    l3_input_checked = 0;
    fc_checked = 0;
    reset_infer_counters;
    load_sel <= 1'b1;
    @(negedge clk);

    $display("INFO: sending paper image for inference...");
    host_send_image_segment(2'd0);

    if (stop_after_l3pool) begin
      $display("INFO: STOP_AFTER_L3POOL enabled, waiting for L3 pool verdict...");
      cycle_count = 0;
      while (!l3_checked) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
        if (cycle_count > 50_000_000) begin
          $display("FAIL: L3 pool timeout (paper)");
          err_count = err_count + 1;
          disable main_test;
        end
      end
      $display("INFO: L3 pool verdict reached in %0d cycles", cycle_count);
      repeat (20) @(posedge clk);
      if (err_count == 0)
        $display("PASS: STOP_AFTER_L3POOL quick check completed");
      else
        $display("FAIL: STOP_AFTER_L3POOL quick check saw %0d errors", err_count);
      $finish;
    end

    // Wait for predict_valid
    $display("INFO: waiting for inference to complete...");
    cycle_count = 0;
    while (!predict_valid) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      if (cycle_count > 50_000_000) begin
        $display("FAIL: inference timeout (paper)");
        err_count = err_count + 1;
        disable main_test;
      end
    end
    $display("INFO: inference done in %0d cycles", cycle_count);
    $display("INFO: predict_class=%0d (expected 0=paper)", predict_class);
    $display("INFO: fc_acc0=%0d, fc_acc1=%0d, fc_acc2=%0d",
             $signed(u_dut.fc_acc0), $signed(u_dut.fc_acc1), $signed(u_dut.fc_acc2));
    print_infer_cycle_summary("paper");

    if (predict_class != 2'd0) begin
      $display("FAIL: paper expected class=0, got %0d", predict_class);
      err_count = err_count + 1;
    end else begin
      $display("PASS: paper classified correctly");
    end

    // Wait for FSM to return to READY
    repeat (5) @(posedge clk);
    if (u_dut.u_top_fsm.state != 4'd7) begin
      $display("FAIL: FSM not back to READY after paper inference, state=%0d",
               u_dut.u_top_fsm.state);
      err_count = err_count + 1;
    end

    // ================================================================
    // TEST 3: LOAD_IMAGE + INFERENCE (rock)
    // ================================================================
    $display("\n=== TEST: ROCK INFERENCE ===");
    active_case_id = 1;
    $sformat(case_dir, "%0s/matlab/debug/sram_preload/rock", proj_dir_str);
    load_case_goldens(case_dir);
    l1_dump_done = 0;
    l2_checked = 0;
    l3_checked = 0;
    l3_input_checked = 0;
    fc_checked = 0;
    reset_infer_counters;
    load_sel <= 1'b1;
    @(negedge clk);

    $display("INFO: sending rock image for inference...");
    host_send_image_segment(2'd1);

    cycle_count = 0;
    while (!predict_valid) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      if (cycle_count > 50_000_000) begin
        $display("FAIL: inference timeout (rock)");
        err_count = err_count + 1;
        disable main_test;
      end
    end
    $display("INFO: inference done in %0d cycles", cycle_count);
    $display("INFO: predict_class=%0d (expected 1=rock)", predict_class);
    $display("INFO: fc_acc0=%0d, fc_acc1=%0d, fc_acc2=%0d",
             $signed(u_dut.fc_acc0), $signed(u_dut.fc_acc1), $signed(u_dut.fc_acc2));
    print_infer_cycle_summary("rock");

    if (predict_class != 2'd1) begin
      $display("FAIL: rock expected class=1, got %0d", predict_class);
      err_count = err_count + 1;
    end else begin
      $display("PASS: rock classified correctly");
    end

    repeat (5) @(posedge clk);

    // ================================================================
    // TEST 4: LOAD_IMAGE + INFERENCE (scissors)
    // ================================================================
    $display("\n=== TEST: SCISSORS INFERENCE ===");
    active_case_id = 2;
    $sformat(case_dir, "%0s/matlab/debug/sram_preload/scissors", proj_dir_str);
    load_case_goldens(case_dir);
    l1_dump_done = 0;
    l2_checked = 0;
    l3_checked = 0;
    l3_input_checked = 0;
    fc_checked = 0;
    reset_infer_counters;
    load_sel <= 1'b1;
    @(negedge clk);

    $display("INFO: sending scissors image for inference...");
    host_send_image_segment(2'd2);

    cycle_count = 0;
    while (!predict_valid) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      if (cycle_count > 50_000_000) begin
        $display("FAIL: inference timeout (scissors)");
        err_count = err_count + 1;
        disable main_test;
      end
    end
    $display("INFO: inference done in %0d cycles", cycle_count);
    $display("INFO: predict_class=%0d (expected 2=scissors)", predict_class);
    $display("INFO: fc_acc0=%0d, fc_acc1=%0d, fc_acc2=%0d",
             $signed(u_dut.fc_acc0), $signed(u_dut.fc_acc1), $signed(u_dut.fc_acc2));
    print_infer_cycle_summary("scissors");

    if (predict_class != 2'd2) begin
      $display("FAIL: scissors expected class=2, got %0d", predict_class);
      err_count = err_count + 1;
    end else begin
      $display("PASS: scissors classified correctly");
    end

    repeat (10) @(posedge clk);

    // ================================================================
    // Summary
    // ================================================================
    $display("\n========================================");
    if (err_count == 0)
      $display("PASS: Full E2E test passed (3/3 classifications correct)");
    else
      $display("FAIL: E2E test failed (%0d errors)", err_count);
    $display("========================================\n");

    $finish;
  end : main_test

  // Watchdog timer
  initial begin
    #500_000_000;
    $display("FAIL: global timeout (500ms)");
    $finish;
  end

  // ---------------------------------------------------------------
  // Progress monitoring: track layer transitions
  // ---------------------------------------------------------------
  always @(posedge clk) begin
    if (u_dut.runner_done)
      $display("INFO: [%0t] runner_done (layer_sel=%0b, pass_id=%0b, is_fc=%0b)",
               $time, u_dut.runner_layer_sel, u_dut.runner_pass_id, u_dut.runner_is_fc);
  end

  always @(posedge clk) begin
    if (u_dut.u_top_fsm.sram_a_start)
      $display("INFO: [%0t] top_fsm sram_a_start (layer_sel=%0d, data_sel=%0d)",
               $time, u_dut.u_top_fsm.sram_a_layer_sel, u_dut.u_top_fsm.sram_a_data_sel);
  end

  // Debug: track TopFSM state transitions
  reg [3:0] prev_top_state;
  always @(posedge clk) begin
    prev_top_state <= u_dut.u_top_fsm.state;
    if (u_dut.u_top_fsm.state != prev_top_state)
      $display("INFO: [%0t] TopFSM state %0d -> %0d",
               $time, prev_top_state, u_dut.u_top_fsm.state);
  end

  // Debug: track runner state transitions
  reg [2:0] prev_run_state;
  always @(posedge clk) begin
    prev_run_state <= u_dut.u_runner.state;
    if (u_dut.u_runner.state != prev_run_state)
      $display("INFO: [%0t] Runner state %0d -> %0d (layer=%0b fc=%0b)",
               $time, prev_run_state, u_dut.u_runner.state,
               u_dut.u_runner.layer_sel_r, u_dut.u_runner.is_fc_r);
  end

  // Debug: track actual sram_a_start going to wrapper
  always @(posedge clk) begin
    if (u_dut.sram_a_start)
      $display("INFO: [%0t] SRAM_A start (layer_sel=%0d, data_sel=%0d, pass_id=%0b, preload_mode=%0b)",
               $time, u_dut.sram_a_layer_sel, u_dut.sram_a_data_sel, u_dut.sram_a_pass_id, u_dut.preload_mode);
  end

  // Debug: track sram_a_done
  always @(posedge clk) begin
    if (u_dut.sram_a_done)
      $display("INFO: [%0t] SRAM_A done", $time);
  end

  // Debug: track sram_b_start and done
  always @(posedge clk) begin
    if (u_dut.run_sram_b_start)
      $display("INFO: [%0t] SRAM_B start (layer_sel=%0d, data_sel=%0d, pass_id=%0b)",
               $time, u_dut.run_sram_b_layer_sel, u_dut.run_sram_b_data_sel, u_dut.run_sram_b_pass_id);
    if (u_dut.sram_b_done)
      $display("INFO: [%0t] SRAM_B done", $time);
  end

  // On SRAM_B done during write mode, report write count/address progress.
  always @(posedge clk) begin
    if (u_dut.sram_b_done && u_dut.u_sram_b.u_sram_B_controller.write_mode)
      $display("DIAG_WRB: [%0t] SRAM_B write txn done: count=%0d addr_counter=%0d layer_sel=%0d data_sel=%0d pass_id=%0b",
               $time,
               u_dut.u_sram_b.u_addr_gen.counter + 1,
               u_dut.u_sram_b.u_addr_gen.counter,
               u_dut.run_sram_b_layer_sel,
               u_dut.run_sram_b_data_sel,
               u_dut.run_sram_b_pass_id);
  end

  // Pool frame done pulse visibility
  always @(posedge clk) begin
    if (u_dut.conv_pool_frame_done)
      $display("DIAG_PFD: [%0t] pool_frame_done layer=%0b pass=%0b burst=%0d emit_cnt=%0d",
               $time,
               u_dut.runner_layer_sel,
               u_dut.runner_pass_id,
               u_dut.u_conv.u_pool.u_pool_core.burst_cnt,
               u_dut.u_conv.u_pool.u_pool_core.emit_count);
  end

  // =============================================================
  // Debug: count SRAM_A pool writes per L2 pass
  reg [31:0] sram_a_wr_cnt;
  reg [1:0]  sram_a_wr_pass;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin sram_a_wr_cnt <= 0; sram_a_wr_pass <= 0; end
    else begin
      // Reset counter on each SRAM_A write-mode txn start
      if (u_dut.u_sram_a.start && u_dut.u_sram_a.u_sram_A_controller.write_mode)
        sram_a_wr_cnt <= 0;
      // Count writes
      if (u_dut.u_sram_a.write_en)
        sram_a_wr_cnt <= sram_a_wr_cnt + 1;
      // On SRAM_A done during write mode, report
      if (u_dut.u_sram_a.done && u_dut.u_sram_a.u_sram_A_controller.write_mode) begin
        $display("DIAG_WR: [%0t] SRAM_A write txn done: %0d writes, addr_gen_counter=%0d, layer_sel=%0d data_sel=%0d pass_id=%0b",
                 $time, sram_a_wr_cnt + 1,
                 u_dut.u_sram_a.u_addr_gen.counter,
                 u_dut.sram_a_layer_sel, u_dut.sram_a_data_sel, u_dut.sram_a_pass_id);
      end
    end
  end

  // First pool_valid beat after each SRAM_A write txn starts
  reg sram_a_wr_first;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sram_a_wr_first <= 0;
    else begin
      if (u_dut.u_sram_a.start && u_dut.u_sram_a.u_sram_A_controller.write_mode)
        sram_a_wr_first <= 0;
      if (u_dut.u_sram_a.write_en && !sram_a_wr_first) begin
        sram_a_wr_first <= 1;
        $display("DIAG_WR: [%0t] SRAM_A FIRST write: data=%h addr=%0d",
                 $time, u_dut.u_sram_a.u_sram_A_wrapper.write_data,
                 u_dut.u_sram_a.u_addr_gen.addr);
      end
    end
  end

  // Debug: frame_done / frame_rearm events
  reg frame_done_d;
  always @(posedge clk) frame_done_d <= u_dut.u_conv.u_conv1.frame_done;
  always @(posedge clk) begin
    if (u_dut.u_conv.u_conv1.frame_done && !frame_done_d)
      $display("DIAG_FRAME: [%0t] frame_done RISES pix_cnt=%0d layer=%0b",
               $time, u_dut.u_conv.u_conv1.pix_cnt, u_dut.runner_layer_sel);
    if (u_dut.u_conv.u_conv1.frame_rearm)
      $display("DIAG_FRAME: [%0t] frame_rearm layer=%0b pix_cnt=%0d",
               $time, u_dut.runner_layer_sel, u_dut.u_conv.u_conv1.pix_cnt);
  end

  // Debug: wt/cfg load done events
  always @(posedge clk) begin
    if (u_dut.conv_wt_load_done)
      $display("DIAG_WT: [%0t] wt_load_done! layer_sel=%0b weights_loaded=%b",
               $time, u_dut.runner_layer_sel, u_dut.u_conv.u_conv1.weights_loaded);
    // DIAG_CFG removed: cfg_load_done stays high (known issue), floods log
  end

  // Debug: runner_start / runner_done / TopFSM interaction
  // =============================================================
  always @(posedge clk) begin
    if (u_dut.runner_start)
      $display("DBG_FSM: [%0t] runner_start=1  top_state=%0d runner_state=%0d layer_sel=%0b is_fc=%0b",
               $time, u_dut.u_top_fsm.state, u_dut.u_runner.state,
               u_dut.runner_layer_sel, u_dut.runner_is_fc);
  end

  // =============================================================
  // L1 STREAM debug probes — trace image data path
  // =============================================================
  // Trigger: Runner enters ST_STREAM (state 5) during L1
  reg l1_stream_active;
  reg [31:0] l1_dbg_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      l1_stream_active <= 1'b0;
      l1_dbg_cnt <= 0;
    end else begin
      if (u_dut.u_runner.state == 3'd5 &&
          u_dut.u_runner.layer_sel_r == 2'b00 &&
          !u_dut.u_runner.is_fc_r)
        l1_stream_active <= 1'b1;
      if (u_dut.u_runner.state == 3'd7 && l1_stream_active)
        l1_stream_active <= 1'b0;
      if (l1_stream_active)
        l1_dbg_cnt <= l1_dbg_cnt + 1;
      else
        l1_dbg_cnt <= 0;
    end
  end

  // Probe A: SRAM_A data path (first 20 cycles of L1 STREAM + every 500th)
  always @(posedge clk) begin
    if (l1_stream_active && (l1_dbg_cnt < 20 || l1_dbg_cnt % 500 == 0))
      $display("DBG_A: [%0t] cnt=%0d sram_a: txn_active=%b read_mode=%b read_en=%b data_valid=%b data_last=%b data_ready=%b read_data=%h | route_conv_in=%b",
               $time, l1_dbg_cnt,
               u_dut.u_sram_a.txn_active,
               u_dut.u_sram_a.read_mode,
               u_dut.u_sram_a.read_en,
               u_dut.u_sram_a.data_valid,
               u_dut.u_sram_a.data_last,
               u_dut.sram_a_data_ready,
               u_dut.sram_a_read_data,
               u_dut.route_conv_in);
  end

  // Probe B: conv_data_adapter state
  always @(posedge clk) begin
    if (l1_stream_active && (l1_dbg_cnt < 20 || l1_dbg_cnt % 500 == 0))
      $display("DBG_B: [%0t] cnt=%0d adapter: up_valid=%b up_ready=%b up_data=%h | dn_valid=%b dn_ready=%b dn_data=%h byte_en=%b | hold_valid=%b byte_sel=%0d",
               $time, l1_dbg_cnt,
               u_dut.conv_in_raw_valid,
               u_dut.conv_in_adapter_up_ready,
               u_dut.conv_in_raw_data,
               u_dut.conv_in_valid,
               u_dut.conv_in_ready,
               u_dut.conv_in_data,
               u_dut.conv_in_byte_en,
               u_dut.u_conv_data_adapter.hold_valid,
               u_dut.u_conv_data_adapter.byte_sel);
  end

  // Probe C: Conv1_top input acceptance
  always @(posedge clk) begin
    if (l1_stream_active && (l1_dbg_cnt < 20 || l1_dbg_cnt % 500 == 0))
      $display("DBG_C: [%0t] cnt=%0d conv: in_valid=%b in_ready=%b pix_cnt=%0d frame_done=%b bank_can_write=%b | wt_loaded=%b backend_idle=%b",
               $time, l1_dbg_cnt,
               u_dut.u_conv.u_conv1.in_valid,
               u_dut.u_conv.u_conv1.in_ready,
               u_dut.u_conv.u_conv1.pix_cnt,
               u_dut.u_conv.u_conv1.frame_done,
               u_dut.u_conv.u_conv1.bank_can_write,
               u_dut.u_conv.u_conv1.weights_loaded,
               u_dut.u_conv.u_conv1.backend_idle_d);
  end

  // Probe D: preload_mode and active_data_sel context
  always @(posedge clk) begin
    if (l1_stream_active && l1_dbg_cnt < 5)
      $display("DBG_D: [%0t] cnt=%0d preload_mode=%b active_data_sel=%0d active_is_fc=%b layer_sel=%0b",
               $time, l1_dbg_cnt,
               u_dut.preload_mode,
               u_dut.active_data_sel,
               u_dut.active_is_fc,
               u_dut.runner_layer_sel);
  end

  // Probe G: first aligned 3-row pulse from the input row aligner
  reg win_seen;
  reg [3:0] win_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin win_seen <= 0; win_cnt <= 0; end
    else if (l1_stream_active && u_dut.u_conv.u_conv1.pix3_valid && win_cnt < 3) begin
      win_seen <= 1;
      win_cnt <= win_cnt + 1;
      $display("DBG_G: [%0t] pix3[%0d]: row0=%h row1=%h row2=%h",
               $time, win_cnt,
               u_dut.u_conv.u_conv1.row0_pix,
               u_dut.u_conv.u_conv1.row1_pix,
               u_dut.u_conv.u_conv1.row2_pix);
    end
  end

  // Probe J: full SRAM_B dump after L1 — compare against row-major golden
  integer l1d_i, l1d_fd, l1d_err, l1d_scan;
  reg signed [31:0] l1d_b0, l1d_b1, l1d_b2, l1d_b3;
  initial begin
    l1_dump_done = 0;
  end

  always @(posedge clk) begin
    if (u_dut.runner_done && u_dut.runner_layer_sel == 2'b00 &&
        !u_dut.runner_is_fc && !l1_dump_done) begin
      l1_dump_done <= 1;
      l1d_err = 0;
      for (l1d_i = 0; l1d_i < 961; l1d_i = l1d_i + 1) begin
        if (get_word_sram_b(l1d_i[9:0]) !== l1_pool_rm[l1d_i]) begin
          l1d_err = l1d_err + 1;
          if (l1d_err <= 5)
            $display("DIAG_L1POOL: word[%0d] MISMATCH: got=%h exp=%h",
                     l1d_i,
                     get_word_sram_b(l1d_i[9:0]),
                     l1_pool_rm[l1d_i]);
        end
      end
      $display("DIAG_L1POOL[%0d]: 961 words checked, %0d errors", active_case_id, l1d_err);
      if (l1d_err != 0)
        err_count = err_count + l1d_err;
    end
  end

  // Probe I: first quant outputs (cut1..4)
  reg cut_seen;
  reg [3:0] cut_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin cut_seen <= 0; cut_cnt <= 0; end
    else if (l1_stream_active && u_dut.u_conv.cut_valid1 && cut_cnt < 5) begin
      cut_seen <= 1;
      cut_cnt <= cut_cnt + 1;
      $display("DBG_I: [%0t] cut[%0d]: c1=%0d c2=%0d c3=%0d c4=%0d  v=%b%b%b%b",
               $time, cut_cnt,
               $signed(u_dut.u_conv.cut1), $signed(u_dut.u_conv.cut2),
               $signed(u_dut.u_conv.cut3), $signed(u_dut.u_conv.cut4),
               u_dut.u_conv.cut_valid1, u_dut.u_conv.cut_valid2,
               u_dut.u_conv.cut_valid3, u_dut.u_conv.cut_valid4);
    end
  end

  // Probe: L3 P0 first SA col0 output (only after L3 STREAM has started)
  reg l3_sa_checked;
  reg l3_stream_started;
  initial begin l3_sa_checked = 0; l3_stream_started = 0; end
  always @(posedge clk) begin
    // L3 STREAM: runner in WAIT_DONE(6) with layer=10, SRAM started
    if (u_dut.u_runner.state == 3'd6 && u_dut.u_runner.layer_sel_r == 2'b10)
      l3_stream_started <= 1;
    if (l3_stream_started && !l3_sa_checked &&
        u_dut.u_conv.u_conv1.c_out_col_valid[0]) begin
      l3_sa_checked <= 1;
      $display("DIAG_L3SA: [%0t] L3 P0 first SA (after stream): col0=%0d col1=%0d col2=%0d col3=%0d",
               $time,
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[22:0]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[45:23]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[68:46]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[91:69]));
    end
  end

  // Probe H2: SA output for each L2 pass - first col0 value
  reg [3:0] sa_l2_capture_cnt;
  initial sa_l2_capture_cnt = 0;
  always @(posedge clk) begin
    if (u_dut.u_conv.u_conv1.c_out_col_valid[0] &&
        u_dut.runner_layer_sel == 2'b01 && sa_l2_capture_cnt < 4) begin
      sa_l2_capture_cnt <= sa_l2_capture_cnt + 1;
      $display("DIAG_SA_L2: [%0t] SA col0=%0d col1=%0d col2=%0d col3=%0d valid=%b  (#%0d)",
               $time,
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[22:0]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[45:23]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[68:46]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[91:69]),
               u_dut.u_conv.u_conv1.c_out_col_valid,
               sa_l2_capture_cnt);
    end
    // Reset counter at each L2 SRAM_B start (new pass)
    if (u_dut.run_sram_b_start && u_dut.run_sram_b_layer_sel == 3'd2)
      sa_l2_capture_cnt <= 0;
  end

  // Probe H: first SA col_stream output
  reg sa_out_seen;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sa_out_seen <= 0;
    else if (l1_stream_active && u_dut.u_conv.u_conv1.c_out_col_valid[0] && !sa_out_seen) begin
      sa_out_seen <= 1;
      $display("DBG_H: [%0t] FIRST SA out: col0=%0d col1=%0d col2=%0d col3=%0d valid=%b",
               $time,
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[22:0]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[45:23]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[68:46]),
               $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[91:69]),
               u_dut.u_conv.u_conv1.c_out_col_valid);
    end
  end

  // Probe F: weight buffer output during first SA launch
  reg wt_ring_seen;
  reg [7:0] wt_burst_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin wt_ring_seen <= 0; wt_burst_cnt <= 0; end
    else if (l1_stream_active && u_dut.u_conv.u_conv1.u_weight_buffer.ring && !wt_ring_seen)
      begin wt_ring_seen <= 1; wt_burst_cnt <= 0; end
    else if (wt_ring_seen && wt_burst_cnt < 20)
      wt_burst_cnt <= wt_burst_cnt + 1;
  end
  always @(posedge clk) begin
    if (wt_ring_seen && wt_burst_cnt < 16)
      $display("DBG_F: [%0t] wt_burst[%0d]: out0=%0d(%b) out1=%0d(%b) out2=%0d(%b) out3=%0d(%b) ov=%b",
               $time, wt_burst_cnt,
               $signed(u_dut.u_conv.u_conv1.u_weight_buffer.out0),
               u_dut.u_conv.u_conv1.u_weight_buffer.out_valid[0],
               $signed(u_dut.u_conv.u_conv1.u_weight_buffer.out1),
               u_dut.u_conv.u_conv1.u_weight_buffer.out_valid[1],
               $signed(u_dut.u_conv.u_conv1.u_weight_buffer.out2),
               u_dut.u_conv.u_conv1.u_weight_buffer.out_valid[2],
               $signed(u_dut.u_conv.u_conv1.u_weight_buffer.out3),
               u_dut.u_conv.u_conv1.u_weight_buffer.out_valid[3],
               u_dut.u_conv.u_conv1.u_weight_buffer.out_valid);
  end

  // Probe E: first 10 pool outputs
  reg [31:0] pool_out_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pool_out_cnt <= 0;
    else if (l1_stream_active && u_dut.conv_pool_valid && u_dut.conv_pool_ready)
      pool_out_cnt <= pool_out_cnt + 1;
    else if (!l1_stream_active)
      pool_out_cnt <= 0;
  end
  always @(posedge clk) begin
    if (l1_stream_active && u_dut.conv_pool_valid && pool_out_cnt < 10)
      $display("DBG_E: [%0t] pool_out[%0d]: data=%h valid=%b ready=%b last=%b",
               $time, pool_out_cnt,
               u_dut.conv_pool_data,
               u_dut.conv_pool_valid,
               u_dut.conv_pool_ready,
               u_dut.conv_pool_last);
  end

  // =============================================================
  // L1 DIAGNOSTIC MONITOR — golden comparison + counters
  // =============================================================
  // Golden arrays
  reg signed [31:0] sa_golden [0:15375];    // tb_conv1_out_i32_62x62x4.txt
  reg signed [7:0]  rq_golden [0:15375];    // tb_conv1_requant_i8_62x62x4.txt
  reg signed [7:0]  pool_golden [0:3843];   // tb_conv1_pool_i8_31x31x4.txt

  // Counters
  reg [31:0] diag_sa_cnt  [0:3];
  reg [31:0] diag_cut_cnt [0:3];
  reg [31:0] diag_pool_cnt;
  reg        diag_backpressure;
  reg [31:0] diag_sa_err  [0:3];
  reg [31:0] diag_cut_err [0:3];
  reg [31:0] diag_pool_err;
  reg        diag_loaded;
  reg        diag_bp_prev;
  reg [3:0]  diag_bp_log_cnt;
  // Track first SA mismatch per col
  reg        diag_sa_first_err [0:3];

  integer dfd, dscan, di;
  reg signed [31:0] dval;

  // Load golden at simulation start
  initial begin
    diag_loaded = 0;
    @(posedge rst_n);
    // Load SA golden
    $sformat(filepath, "%0s/matlab/debug/txt_cases/paper/tb_conv1_out_i32_62x62x4.txt", proj_dir_str);
    dfd = $fopen(filepath, "r");
    if (dfd != 0) begin
      for (di = 0; di < 15376; di = di + 1) begin
        dscan = $fscanf(dfd, "%d\n", dval);
        sa_golden[di] = dval;
      end
      $fclose(dfd);
    end else $display("DIAG: WARN: cannot open SA golden");

    // Load requant golden
    $sformat(filepath, "%0s/matlab/debug/txt_cases/paper/tb_conv1_requant_i8_62x62x4.txt", proj_dir_str);
    dfd = $fopen(filepath, "r");
    if (dfd != 0) begin
      for (di = 0; di < 15376; di = di + 1) begin
        dscan = $fscanf(dfd, "%d\n", dval);
        rq_golden[di] = dval[7:0];
      end
      $fclose(dfd);
    end else $display("DIAG: WARN: cannot open requant golden");

    // Load pool golden
    $sformat(filepath, "%0s/matlab/debug/txt_cases/paper/tb_conv1_pool_i8_31x31x4.txt", proj_dir_str);
    dfd = $fopen(filepath, "r");
    if (dfd != 0) begin
      for (di = 0; di < 3844; di = di + 1) begin
        dscan = $fscanf(dfd, "%d\n", dval);
        pool_golden[di] = dval[7:0];
      end
      $fclose(dfd);
    end else $display("DIAG: WARN: cannot open pool golden");

    diag_loaded = 1;
    $display("DIAG: golden loaded (SA=15376, requant=15376, pool=3844)");
  end

  // Init counters
  integer dci;
  initial begin
    for (dci = 0; dci < 4; dci = dci + 1) begin
      diag_sa_cnt[dci]  = 0; diag_cut_cnt[dci]  = 0;
      diag_sa_err[dci]  = 0; diag_cut_err[dci]  = 0;
      diag_sa_first_err[dci] = 0;
    end
    diag_pool_cnt = 0; diag_pool_err = 0; diag_backpressure = 0;
    diag_bp_prev = 0; diag_bp_log_cnt = 0;
  end

  // --- A: SA col_stream golden compare ---
  always @(posedge clk) begin
    if (l1_stream_active && diag_loaded) begin
      for (dci = 0; dci < 4; dci = dci + 1) begin
        if (u_dut.u_conv.u_conv1.c_out_col_valid[dci]) begin
          // Compare SA output (23-bit signed) with golden (32-bit signed, but should fit in 23)
          if ($signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[dci*23 +: 23])
              !== $signed(sa_golden[diag_sa_cnt[dci]][22:0])) begin
            diag_sa_err[dci] <= diag_sa_err[dci] + 1;
            if (!diag_sa_first_err[dci]) begin
              diag_sa_first_err[dci] <= 1;
              $display("DIAG_SA: col%0d FIRST ERR at idx=%0d: got=%0d exp=%0d [%0t]",
                       dci, diag_sa_cnt[dci],
                       $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[dci*23 +: 23]),
                       $signed(sa_golden[diag_sa_cnt[dci]]),
                       $time);
            end
          end
          diag_sa_cnt[dci] <= diag_sa_cnt[dci] + 1;
        end
      end
    end
  end

  // --- B: QPE cut golden compare ---
  wire [3:0] cut_valids = {u_dut.u_conv.cut_valid4, u_dut.u_conv.cut_valid3,
                           u_dut.u_conv.cut_valid2, u_dut.u_conv.cut_valid1};
  wire signed [7:0] cut_vals [0:3];
  assign cut_vals[0] = u_dut.u_conv.cut1;
  assign cut_vals[1] = u_dut.u_conv.cut2;
  assign cut_vals[2] = u_dut.u_conv.cut3;
  assign cut_vals[3] = u_dut.u_conv.cut4;

  reg diag_cut_first_err [0:3];
  initial begin for (dci=0;dci<4;dci=dci+1) diag_cut_first_err[dci]=0; end

  always @(posedge clk) begin
    if (l1_stream_active && diag_loaded) begin
      for (dci = 0; dci < 4; dci = dci + 1) begin
        if (cut_valids[dci]) begin
          if (cut_vals[dci] !== rq_golden[diag_cut_cnt[dci]]) begin
            diag_cut_err[dci] <= diag_cut_err[dci] + 1;
            if (!diag_cut_first_err[dci]) begin
              diag_cut_first_err[dci] <= 1;
              $display("DIAG_CUT: ch%0d FIRST ERR at idx=%0d: got=%0d exp=%0d [%0t]",
                       dci, diag_cut_cnt[dci],
                       $signed(cut_vals[dci]), $signed(rq_golden[diag_cut_cnt[dci]]),
                       $time);
            end
          end
          diag_cut_cnt[dci] <= diag_cut_cnt[dci] + 1;
        end
      end
    end
  end

  // --- C: Pool output golden compare ---
  reg diag_pool_first_err;
  initial diag_pool_first_err = 0;
  always @(posedge clk) begin
    if (l1_stream_active && diag_loaded) begin
      if (u_dut.conv_pool_valid && u_dut.conv_pool_ready) begin
        // pool_data = {lane1(cut1), lane2(cut2), lane3(cut3), lane4(cut4)}
        // golden is stored as ch0,ch1,ch2,ch3 per pixel = cut1,cut2,cut3,cut4
        if ({pool_golden[diag_pool_cnt*4+0],
             pool_golden[diag_pool_cnt*4+1],
             pool_golden[diag_pool_cnt*4+2],
             pool_golden[diag_pool_cnt*4+3]} !== u_dut.conv_pool_data) begin
          diag_pool_err <= diag_pool_err + 1;
          if (!diag_pool_first_err) begin
            diag_pool_first_err <= 1;
            $display("DIAG_POOL: FIRST ERR at word=%0d: got=%h exp=%02h%02h%02h%02h [%0t]",
                     diag_pool_cnt, u_dut.conv_pool_data,
                     pool_golden[diag_pool_cnt*4+0], pool_golden[diag_pool_cnt*4+1],
                     pool_golden[diag_pool_cnt*4+2], pool_golden[diag_pool_cnt*4+3],
                     $time);
          end
        end
        diag_pool_cnt <= diag_pool_cnt + 1;
      end
    end
  end

  // --- D: Input backpressure + pix_cnt + frame_done check ---
  always @(posedge clk) begin
    if (!rst_n) begin
      diag_bp_prev <= 1'b0;
      diag_bp_log_cnt <= 4'd0;
    end else begin
      diag_bp_prev <= l1_stream_active &&
                      u_dut.u_conv.u_conv1.in_valid &&
                      !u_dut.u_conv.u_conv1.in_ready;
      if (l1_stream_active &&
          u_dut.u_conv.u_conv1.in_valid &&
          !u_dut.u_conv.u_conv1.in_ready) begin
        diag_backpressure <= 1;
        if (!diag_bp_prev && diag_bp_log_cnt < 4'd8) begin
          diag_bp_log_cnt <= diag_bp_log_cnt + 1'b1;
          $display("DIAG: BACKPRESSURE rise at %0t pix_cnt=%0d", $time,
                   u_dut.u_conv.u_conv1.pix_cnt);
        end
      end
    end
  end

  // --- Summary on L1 done ---
  reg l1_diag_done;
  initial l1_diag_done = 0;
  always @(posedge clk) begin
    if (l1_stream_active && u_dut.u_runner.state == 3'd7 && !l1_diag_done) begin
      l1_diag_done <= 1;
      $display("DIAG_SUMMARY: === L1 Diagnostic Results ===");
      $display("DIAG_SUMMARY: SA  col0=%0d col1=%0d col2=%0d col3=%0d  (expect ~3856 each)",
               diag_sa_cnt[0], diag_sa_cnt[1], diag_sa_cnt[2], diag_sa_cnt[3]);
      $display("DIAG_SUMMARY: SA  err0=%0d err1=%0d err2=%0d err3=%0d",
               diag_sa_err[0], diag_sa_err[1], diag_sa_err[2], diag_sa_err[3]);
      $display("DIAG_SUMMARY: CUT cnt0=%0d cnt1=%0d cnt2=%0d cnt3=%0d  (expect 3844 each)",
               diag_cut_cnt[0], diag_cut_cnt[1], diag_cut_cnt[2], diag_cut_cnt[3]);
      $display("DIAG_SUMMARY: CUT err0=%0d err1=%0d err2=%0d err3=%0d",
               diag_cut_err[0], diag_cut_err[1], diag_cut_err[2], diag_cut_err[3]);
      $display("DIAG_SUMMARY: POOL cnt=%0d err=%0d  (expect 961 words)",
               diag_pool_cnt, diag_pool_err);
      $display("DIAG_SUMMARY: backpressure=%b pix_cnt=%0d frame_done=%b",
               diag_backpressure, u_dut.u_conv.u_conv1.pix_cnt, u_dut.u_conv.u_conv1.frame_done);
    end
  end

  // =============================================================
  // Probe: pool_core lane_cut_valid during L2_P1 — first few
  reg [5:0] pool_lane_probe_cnt;
  reg pool_lane_probing;
  initial begin pool_lane_probe_cnt = 0; pool_lane_probing = 0; end
  always @(posedge clk) begin
    // Start probing at second L2 SRAM_B start (=P1)
    if (u_dut.run_sram_b_start && u_dut.run_sram_b_layer_sel == 3'd2) begin
      if (pool_lane_probing) begin end // already probing
      else pool_lane_probing <= 1; // first was P0, this arm catches P1 start
    end
    if (pool_lane_probing && u_dut.u_conv.u_pool.u_pool_core.lane_cut_valid1 && pool_lane_probe_cnt < 8) begin
      pool_lane_probe_cnt <= pool_lane_probe_cnt + 1;
      $display("DIAG_PLCUT: [%0t] P1 lane_cut[%0d]: c1=%0d c2=%0d c3=%0d c4=%0d  drop=%b burst=%0d",
               $time, pool_lane_probe_cnt,
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut1),
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut2),
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut3),
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut4),
               u_dut.u_conv.u_pool.u_pool_core.drop_until_idle,
               u_dut.u_conv.u_pool.u_pool_core.burst_cnt);
    end
  end

  // L3 P0 first bank write + SA launch probe
  reg l3_bank_checked;
  initial l3_bank_checked = 0;
  always @(posedge clk) begin
    if (u_dut.runner_layer_sel == 2'b10 && !u_dut.runner_is_fc &&
        u_dut.u_conv.u_conv1.u_conv_buffer.accepting_input_col && !l3_bank_checked) begin
      l3_bank_checked <= 1;
      $display("DIAG_L3BANK: [%0t] first bank_wr: row=%0d bank=%b data[71:0]=%h",
               $time, u_dut.u_conv.u_conv1.u_conv_buffer.fill_cols_r,
               u_dut.u_conv.u_conv1.u_conv_buffer.wr_bank_r,
               u_dut.u_conv.u_conv1.u_conv_buffer.write_sample_flat[71:0]);
    end
  end
  // L3 P0 SA launch probe
  reg l3_sa_launch_checked;
  initial l3_sa_launch_checked = 0;
  always @(posedge clk) begin
    if (u_dut.runner_layer_sel == 2'b10 && !u_dut.runner_is_fc &&
        u_dut.u_conv.u_conv1.u_conv_engine_ctrl.start_pulse_r && !l3_sa_launch_checked) begin
      l3_sa_launch_checked <= 1;
      $display("DIAG_L3LAUNCH: [%0t] SA launch! state=%0d weights_loaded=%b have_ready=%b bank=%b cur_k=%0d",
               $time,
               u_dut.u_conv.u_conv1.u_conv_engine_ctrl.state_r,
               u_dut.u_conv.u_conv1.weights_loaded,
               u_dut.u_conv.u_conv1.have_ready_block,
               u_dut.u_conv.u_conv1.u_conv_engine_ctrl.rd_bank_r,
               u_dut.u_conv.u_conv1.u_systolic_array_top.cur_k);
    end
  end

  // L3 P0 first aligned-row probe
  reg l3_win_checked;
  initial l3_win_checked = 0;
  always @(posedge clk) begin
    if (u_dut.runner_layer_sel == 2'b10 && !u_dut.runner_is_fc &&
        u_dut.u_conv.u_conv1.pix3_valid && !l3_win_checked) begin
      l3_win_checked <= 1;
      $display("DIAG_L3ALIGN: [%0t] first pix3 rows:",  $time);
      $display("  row0=%h", u_dut.u_conv.u_conv1.row0_pix);
      $display("  row1=%h", u_dut.u_conv.u_conv1.row1_pix);
      $display("  row2=%h", u_dut.u_conv.u_conv1.row2_pix);
    end
  end

  // L2→L3 drop_until_idle transition trace
  reg dt_prev_drop, dt_prev_cut;
  reg [1:0] dt_prev_layer;
  reg [7:0] dt_log_cnt;
  initial begin dt_prev_drop = 0; dt_prev_cut = 0; dt_prev_layer = 0; dt_log_cnt = 0; end
  always @(posedge clk) begin
    dt_prev_layer <= u_dut.runner_layer_sel;
    // Only trace during L2→L3 transition window
    if (u_dut.runner_layer_sel == 2'b10 && dt_prev_layer == 2'b01)
      dt_log_cnt <= 1;
    if (dt_log_cnt > 0 && dt_log_cnt < 200)
      dt_log_cnt <= dt_log_cnt + 1;
    // Log transitions
    if (dt_log_cnt > 0 && dt_log_cnt < 200) begin
      if (u_dut.u_conv.u_pool.u_pool_core.drop_until_idle !== dt_prev_drop ||
          u_dut.u_conv.u_pool.u_pool_core.any_cut_valid !== dt_prev_cut)
        $display("DIAG_DROP: [%0t] drop=%b any_cut=%b lane_reset=%b",
                 $time,
                 u_dut.u_conv.u_pool.u_pool_core.drop_until_idle,
                 u_dut.u_conv.u_pool.u_pool_core.any_cut_valid,
                 u_dut.u_conv.u_pool.u_pool_core.lane_reset_r);
      dt_prev_drop <= u_dut.u_conv.u_pool.u_pool_core.drop_until_idle;
      dt_prev_cut  <= u_dut.u_conv.u_pool.u_pool_core.any_cut_valid;
    end
  end

  // L3 P0 first pixel probe
  reg [3:0] l3_pix_cnt_dbg;
  initial l3_pix_cnt_dbg = 0;
  always @(posedge clk) begin
    if (u_dut.runner_layer_sel == 2'b10 && !u_dut.runner_is_fc &&
        u_dut.conv_in_valid && u_dut.conv_in_ready && l3_pix_cnt_dbg < 4) begin
      l3_pix_cnt_dbg <= l3_pix_cnt_dbg + 1;
      $display("DIAG_L3PIX: [%0t] L3 pix[%0d]: data=%h byte_en=%b",
               $time, l3_pix_cnt_dbg, u_dut.conv_in_data, u_dut.conv_in_byte_en);
    end
  end

  // L3 P0 quant output probe — first 8 cut_valid beats
  reg [3:0] l3p0_cut_cnt;
  initial l3p0_cut_cnt = 0;
  always @(posedge clk) begin
    if (l3_stream_started && u_dut.u_conv.cut_valid1 && l3p0_cut_cnt < 8) begin
      l3p0_cut_cnt <= l3p0_cut_cnt + 1;
      $display("DIAG_L3CUT: [%0t] cut[%0d]: c1=%0d c2=%0d c3=%0d c4=%0d",
               $time, l3p0_cut_cnt,
               $signed(u_dut.u_conv.cut1), $signed(u_dut.u_conv.cut2),
               $signed(u_dut.u_conv.cut3), $signed(u_dut.u_conv.cut4));
    end
  end

  // L3 P0 first pool emit probe
  reg l3_emit_checked;
  initial l3_emit_checked = 0;
  always @(posedge clk) begin
    if (l3_stream_started && u_dut.u_conv.u_pool.u_pool_core.emit_active &&
        !l3_emit_checked) begin
      l3_emit_checked <= 1;
      $display("DIAG_L3EMIT: [%0t] first emit: burst=%0d cnt=%0d data=%h ready=%b",
               $time,
               u_dut.u_conv.u_pool.u_pool_core.burst_cnt,
               u_dut.u_conv.u_pool.u_pool_core.emit_count,
               {u_dut.u_conv.u_pool.u_pool_core.lane1_emit,
                u_dut.u_conv.u_pool.u_pool_core.lane2_emit,
                u_dut.u_conv.u_pool.u_pool_core.lane3_emit,
                u_dut.u_conv.u_pool.u_pool_core.lane4_emit},
               u_dut.conv_pool_ready);
    end
  end

  // L3 P0 lane state probe
  reg l3p0_lane_checked;
  initial l3p0_lane_checked = 0;
  always @(posedge clk) begin
    if (u_dut.runner_layer_sel == 2'b10 && !u_dut.runner_is_fc &&
        u_dut.u_conv.u_pool.u_pool_core.lane_cut_valid1 && !l3p0_lane_checked) begin
      l3p0_lane_checked <= 1;
      $display("DIAG_L3P0LANE: [%0t] FIRST L3 lane_cut: col=%0d row=%0d cnt1=%b cnt2=%0d cnt3=%b drop=%b burst=%0d emit=%b",
               $time,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.col_in_row,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.row_cnt,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.cnt1,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.cnt2,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.cnt3,
               u_dut.u_conv.u_pool.u_pool_core.drop_until_idle,
               u_dut.u_conv.u_pool.u_pool_core.burst_cnt,
               u_dut.u_conv.u_pool.u_pool_core.emit_active);
    end
  end

  // Track L2 pass number by counting SRAM_B starts for layer=L2
  reg [1:0] l2_pass_num;
  initial l2_pass_num = 0;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) l2_pass_num <= 0;
    else if (u_dut.run_sram_b_start && u_dut.run_sram_b_layer_sel == 3'd2)
      l2_pass_num <= l2_pass_num + 1;
  end

  reg [3:0] l2p1_wt_cnt;
  initial l2p1_wt_cnt = 0;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      l2p1_wt_cnt <= 0;
    end else begin
      if (u_dut.run_sram_a_start &&
          u_dut.run_sram_a_layer_sel == 3'd2 &&
          u_dut.run_sram_a_data_sel == 2'd1 &&
          u_dut.run_sram_a_pass_id)
        l2p1_wt_cnt <= 0;
      else if (u_dut.wt_prepad_dn_valid && u_dut.wt_prepad_dn_ready &&
               u_dut.runner_layer_sel == 2'b01 && u_dut.runner_pass_id) begin
        if (l2p1_wt_cnt < 8)
          $display("DIAG_L2P1WT: [%0t] beat[%0d]=%h last=%b",
                   $time, l2p1_wt_cnt, u_dut.wt_prepad_dn_data, u_dut.wt_prepad_dn_last);
        l2p1_wt_cnt <= l2p1_wt_cnt + 1;
      end
    end
  end

  // Dump pool_valid beats during L2_P1 only (l2_pass_num == 2)
  reg [31:0] l2p1_pool_cnt;
  reg [3:0]  l2p1_cut_cnt_clean;
  initial l2p1_pool_cnt = 0;
  initial l2p1_cut_cnt_clean = 0;
  always @(posedge clk) begin
    if (l2_pass_num == 2 && u_dut.conv_pool_valid && u_dut.conv_pool_ready) begin
      if (l2p1_pool_cnt < 5)
        $display("DIAG_P1POOL: [%0t] pool_word[%0d]=%h  burst=%0d emit_cnt=%0d",
                 $time, l2p1_pool_cnt, u_dut.conv_pool_data,
                 u_dut.u_conv.u_pool.u_pool_core.burst_cnt,
                 u_dut.u_conv.u_pool.u_pool_core.emit_count);
      l2p1_pool_cnt <= l2p1_pool_cnt + 1;
    end

    if (u_dut.run_sram_b_start &&
        u_dut.run_sram_b_layer_sel == 3'd2 &&
        u_dut.run_sram_b_pass_id)
      l2p1_cut_cnt_clean <= 0;
    else if (u_dut.runner_layer_sel == 2'b01 &&
             u_dut.runner_pass_id &&
             u_dut.u_conv.u_pool.u_pool_core.lane_cut_valid1 &&
             l2p1_cut_cnt_clean < 8) begin
      $display("DIAG_CUT_SYSTEM: [%0t] idx=%0d c1=%0d c2=%0d c3=%0d c4=%0d",
               $time, l2p1_cut_cnt_clean,
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut1),
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut2),
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut3),
               $signed(u_dut.u_conv.u_pool.u_pool_core.cut4));
      l2p1_cut_cnt_clean <= l2p1_cut_cnt_clean + 1;
    end
  end

  // Dump lane1 state at P1 first cut_valid
  reg l2p1_lane_checked;
  initial l2p1_lane_checked = 0;
  always @(posedge clk) begin
    if (u_dut.run_sram_b_start &&
        u_dut.run_sram_b_layer_sel == 3'd2 &&
        u_dut.run_sram_b_pass_id) begin
      $display("DIAG_L2P1Q: [%0t] QPE bias/M/sh = (%h,%h,%0d) (%h,%h,%0d) (%h,%h,%0d) (%h,%h,%0d)",
               $time,
               u_dut.u_conv.u_quant.u_QPE1.bias, u_dut.u_conv.u_quant.u_QPE1.M, u_dut.u_conv.u_quant.u_QPE1.sh,
               u_dut.u_conv.u_quant.u_QPE2.bias, u_dut.u_conv.u_quant.u_QPE2.M, u_dut.u_conv.u_quant.u_QPE2.sh,
               u_dut.u_conv.u_quant.u_QPE3.bias, u_dut.u_conv.u_quant.u_QPE3.M, u_dut.u_conv.u_quant.u_QPE3.sh,
               u_dut.u_conv.u_quant.u_QPE4.bias, u_dut.u_conv.u_quant.u_QPE4.M, u_dut.u_conv.u_quant.u_QPE4.sh);
    end

    if (l2_pass_num == 2 && u_dut.u_conv.u_pool.u_pool_core.lane_cut_valid1 && !l2p1_lane_checked) begin
      l2p1_lane_checked <= 1;
      $display("DIAG_P1LANE: [%0t] FIRST P1 lane_cut: col=%0d row=%0d cnt1=%b cnt2=%0d cnt3=%b drop=%b burst=%0d emit=%b ready=%b%b%b%b",
               $time,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.col_in_row,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.row_cnt,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.cnt1,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.cnt2,
               u_dut.u_conv.u_pool.u_pool_core.u_lane1.cnt3,
               u_dut.u_conv.u_pool.u_pool_core.drop_until_idle,
               u_dut.u_conv.u_pool.u_pool_core.burst_cnt,
               u_dut.u_conv.u_pool.u_pool_core.emit_active,
               u_dut.u_conv.u_pool.u_pool_core.lane1_ready,
               u_dut.u_conv.u_pool.u_pool_core.lane2_ready,
               u_dut.u_conv.u_pool.u_pool_core.lane3_ready,
               u_dut.u_conv.u_pool.u_pool_core.lane4_ready);
    end
  end

  reg l2p1_win_checked, l2p1_bank_checked;
  initial begin
    l2p1_win_checked = 0;
    l2p1_bank_checked = 0;
  end
  always @(posedge clk) begin
    if (u_dut.run_sram_b_start && u_dut.run_sram_b_layer_sel == 3'd2 && u_dut.run_sram_b_pass_id) begin
      l2p1_win_checked <= 0;
      l2p1_bank_checked <= 0;
    end

    if (l2_pass_num == 2 && !l2p1_win_checked && u_dut.u_conv.u_conv1.pix3_valid) begin
      l2p1_win_checked <= 1;
      $display("DIAG_L2P1ALIGN: [%0t] first pix3 rows:", $time);
      $display("  row0=%h", u_dut.u_conv.u_conv1.row0_pix);
      $display("  row1=%h", u_dut.u_conv.u_conv1.row1_pix);
      $display("  row2=%h", u_dut.u_conv.u_conv1.row2_pix);
    end

    if (l2_pass_num == 2 && !l2p1_bank_checked &&
        u_dut.u_conv.u_conv1.u_conv_buffer.accepting_input_col) begin
      l2p1_bank_checked <= 1;
      $display("DIAG_L2P1BANK: [%0t] first bank_wr: row=%0d bank=%b data[127:0]=%h",
               $time,
               u_dut.u_conv.u_conv1.u_conv_buffer.fill_cols_r,
               u_dut.u_conv.u_conv1.u_conv_buffer.wr_bank_r,
               u_dut.u_conv.u_conv1.u_conv_buffer.write_sample_flat[127:0]);
    end
  end

  // L3 P1 pool write progress
  reg [7:0] l3p1_pool_cnt;
  initial l3p1_pool_cnt = 0;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      l3p1_pool_cnt <= 0;
    end else begin
      if (u_dut.run_sram_b_start &&
          u_dut.run_sram_b_layer_sel == 3'd3 &&
          u_dut.run_sram_b_pass_id)
        l3p1_pool_cnt <= 0;
      else if (u_dut.runner_layer_sel == 2'b10 &&
               u_dut.runner_pass_id &&
               u_dut.conv_pool_valid && u_dut.conv_pool_ready)
        l3p1_pool_cnt <= l3p1_pool_cnt + 1;
    end
  end

  always @(posedge clk) begin
    if (u_dut.runner_layer_sel == 2'b10 &&
        u_dut.runner_pass_id &&
        u_dut.conv_pool_valid && u_dut.conv_pool_ready &&
        l3p1_pool_cnt < 8)
      $display("DIAG_L3P1POOL: [%0t] word[%0d]=%h last=%b burst=%0d emit_cnt=%0d",
               $time, l3p1_pool_cnt, u_dut.conv_pool_data, u_dut.conv_pool_last,
               u_dut.u_conv.u_pool.u_pool_core.burst_cnt,
               u_dut.u_conv.u_pool.u_pool_core.emit_count);

    if (u_dut.runner_layer_sel == 2'b10 &&
        u_dut.runner_pass_id &&
        u_dut.u_runner.state == 3'd6 &&
        u_dut.u_conv.u_conv1.frame_rearm)
      $display("DIAG_L3P1SUM: [%0t] before runner_done pool_words=%0d sram_b_busy=%b txn_active=%b addr_counter=%0d",
               $time,
               l3p1_pool_cnt,
               u_dut.u_sram_b.busy,
               u_dut.u_sram_b.txn_active,
               u_dut.u_sram_b.u_addr_gen.counter);
  end

  reg l3p1_sa_seen, l3p1_cut_seen;
  reg l3p1_prev_drop;
  initial begin
    l3p1_sa_seen = 0;
    l3p1_cut_seen = 0;
    l3p1_prev_drop = 0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      l3p1_sa_seen <= 0;
      l3p1_cut_seen <= 0;
      l3p1_prev_drop <= 0;
    end else begin
      if (u_dut.run_sram_b_start &&
          u_dut.run_sram_b_layer_sel == 3'd3 &&
          u_dut.run_sram_b_pass_id) begin
        l3p1_sa_seen <= 0;
        l3p1_cut_seen <= 0;
        l3p1_prev_drop <= u_dut.u_conv.u_pool.u_pool_core.drop_until_idle;
      end

      if (u_dut.runner_layer_sel == 2'b10 &&
          u_dut.runner_pass_id &&
          !l3p1_sa_seen &&
          u_dut.u_conv.u_conv1.c_out_col_valid[0]) begin
        l3p1_sa_seen <= 1;
        $display("DIAG_L3P1SA: [%0t] first SA col0=%0d col1=%0d col2=%0d col3=%0d",
                 $time,
                 $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[22:0]),
                 $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[45:23]),
                 $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[68:46]),
                 $signed(u_dut.u_conv.u_conv1.c_out_col_stream_flat[91:69]));
      end

      if (u_dut.runner_layer_sel == 2'b10 &&
          u_dut.runner_pass_id &&
          !l3p1_cut_seen &&
          u_dut.u_conv.cut_valid1) begin
        l3p1_cut_seen <= 1;
        $display("DIAG_L3P1CUT: [%0t] first cut c1=%0d c2=%0d c3=%0d c4=%0d drop=%b",
                 $time,
                 $signed(u_dut.u_conv.cut1), $signed(u_dut.u_conv.cut2),
                 $signed(u_dut.u_conv.cut3), $signed(u_dut.u_conv.cut4),
                 u_dut.u_conv.u_pool.u_pool_core.drop_until_idle);
      end

      if (u_dut.runner_layer_sel == 2'b10 &&
          u_dut.runner_pass_id &&
          u_dut.u_conv.u_pool.u_pool_core.drop_until_idle !== l3p1_prev_drop) begin
        $display("DIAG_L3P1DROP: [%0t] drop=%b any_cut=%b lane_reset=%b",
                 $time,
                 u_dut.u_conv.u_pool.u_pool_core.drop_until_idle,
                 u_dut.u_conv.u_pool.u_pool_core.any_cut_valid,
                 u_dut.u_conv.u_pool.u_pool_core.lane_reset_r);
        l3p1_prev_drop <= u_dut.u_conv.u_pool.u_pool_core.drop_until_idle;
      end
    end
  end

  // Adapter state probe — check for stale hold_reg between passes
  // =============================================================
  reg [3:0] adapter_probe_cnt;
  initial adapter_probe_cnt = 0;
  always @(posedge clk) begin
    // Trigger on each SRAM_B start during L2 (marks beginning of each pass STREAM)
    if (u_dut.run_sram_b_start && u_dut.run_sram_b_layer_sel == 3'd2) begin
      $display("DIAG_ADAPTER: [%0t] L2 SRAM_B start: hold_valid=%b hold_reg=%h byte_sel=%0d is_l1=%b dn_ready=%b",
               $time,
               u_dut.u_conv_data_adapter.hold_valid,
               u_dut.u_conv_data_adapter.hold_reg,
               u_dut.u_conv_data_adapter.byte_sel,
               u_dut.u_conv_data_adapter.is_l1,
               u_dut.conv_in_ready);
    end
  end

  // =============================================================
  // L2 STREAM pixel probe — verify first few pixels reaching Conv
  // =============================================================
  reg l2_stream_active;
  reg [31:0] l2_pix_cnt_dbg;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin l2_stream_active <= 0; l2_pix_cnt_dbg <= 0; end
    else begin
      if (u_dut.u_runner.state == 3'd5 && u_dut.u_runner.layer_sel_r == 2'b01)
        l2_stream_active <= 1;
      if (u_dut.u_runner.state == 3'd7 && l2_stream_active)
        l2_stream_active <= 0;
      if (l2_stream_active && u_dut.conv_in_valid && u_dut.conv_in_ready)
        l2_pix_cnt_dbg <= l2_pix_cnt_dbg + 1;
      if (!l2_stream_active) l2_pix_cnt_dbg <= 0;
    end
  end
  always @(posedge clk) begin
    if (l2_stream_active && u_dut.conv_in_valid && u_dut.conv_in_ready && l2_pix_cnt_dbg < 5)
      $display("DIAG_L2PIX: [%0t] pix[%0d]: data=%h byte_en=%b",
               $time, l2_pix_cnt_dbg, u_dut.conv_in_data, u_dut.conv_in_byte_en);
  end

  // =============================================================
  // L2 / L3 / FC Diagnostic — dump SRAM after each layer
  // =============================================================
  reg [3:0] prev_top_fsm_state_d;
  always @(posedge clk) prev_top_fsm_state_d <= u_dut.u_top_fsm.state;

  // L2 done: TopFSM transitions from ST_L2_P1(10) → ST_L3_P0(11)
  // At that point, SRAM_A 0x231..0x3B8 should have L2 pool output (2 passes, 392 words)
  integer l2_i, l2_err, l2_fd2, l2_scan2;
  reg signed [31:0] l2_b0, l2_b1, l2_b2, l2_b3;
  initial begin
    l2_checked = 0;
  end

  always @(posedge clk) begin
    if (u_dut.u_top_fsm.state == 4'd11 && prev_top_fsm_state_d == 4'd10 && !l2_checked) begin
      l2_checked <= 1;
      l2_err = 0;
      // L2 pass0 at SRAM_A addr 0x231 (561), pass1 at 0x2F5 (757)
      for (l2_i = 0; l2_i < 196; l2_i = l2_i + 1) begin
        if (get_word_sram_a(561 + l2_i) !== l2_golden[l2_i])
          l2_err = l2_err + 1;
      end
      for (l2_i = 0; l2_i < 196; l2_i = l2_i + 1) begin
        if (get_word_sram_a(757 + l2_i) !== l2_golden[196 + l2_i])
          l2_err = l2_err + 1;
      end
      // Count pass0 and pass1 errors separately
      begin : l2_err_detail
        integer l2_p0_err, l2_p1_err;
        l2_p0_err = 0; l2_p1_err = 0;
        for (l2_i = 0; l2_i < 196; l2_i = l2_i + 1)
          if (get_word_sram_a(561 + l2_i) !== l2_golden[l2_i])
            l2_p0_err = l2_p0_err + 1;
        for (l2_i = 0; l2_i < 196; l2_i = l2_i + 1)
          if (get_word_sram_a(757 + l2_i) !== l2_golden[196 + l2_i])
            l2_p1_err = l2_p1_err + 1;
        $display("DIAG_L2POOL[%0d]: total=%0d  pass0=%0d/196  pass1=%0d/196", active_case_id, l2_err, l2_p0_err, l2_p1_err);
      end
      $display("DIAG_L2POOL[%0d]: pass0[0]: actual=%h exp=%h", active_case_id,
               get_word_sram_a(10'd561), l2_golden[0]);
      $display("DIAG_L2POOL[%0d]: pass0[195]: actual=%h exp=%h", active_case_id,
               get_word_sram_a(10'd756), l2_golden[195]);
      $display("DIAG_L2POOL[%0d]: pass1[0]: actual=%h exp=%h", active_case_id,
               get_word_sram_a(10'd757), l2_golden[196]);
      $display("DIAG_L2POOL[%0d]: pass1[1]: actual=%h exp=%h", active_case_id,
               get_word_sram_a(10'd758), l2_golden[197]);
      if (l2_err != 0)
        err_count = err_count + l2_err;
    end
  end

  // L3 input check: dump first few words from SRAM_A L2 pool area before L3 starts
  initial l3_input_checked = 0;
  always @(posedge clk) begin
    if (u_dut.u_top_fsm.state == 4'd11 && !l3_input_checked) begin
      l3_input_checked <= 1;
      $display("DIAG_L3IN: SRAM_A L2 pool area at L3 start:");
      $display("  [561]=%h [562]=%h [563]=%h [564]=%h",
               get_word_sram_a(10'd561),
               get_word_sram_a(10'd562),
               get_word_sram_a(10'd563),
               get_word_sram_a(10'd564));
    end
  end

  // L3 done: TopFSM transitions from ST_FC(13) — after L3_P1 done
  // SRAM_B 0x000..0x023 = L3 pass0 (36 words), 0x024..0x047 = L3 pass1 (36 words)
  integer l3_i, l3_err, l3_fd2, l3_scan2;
  reg signed [31:0] l3_b0, l3_b1, l3_b2, l3_b3;
  initial begin
    l3_checked = 0;
  end

  always @(posedge clk) begin
    if (u_dut.u_top_fsm.state == 4'd13 && prev_top_fsm_state_d == 4'd12 && !l3_checked) begin
      l3_checked <= 1;
      l3_err = 0;
      for (l3_i = 0; l3_i < 36; l3_i = l3_i + 1) begin
        if (get_word_sram_b(l3_i) !== l3_golden[l3_i])
          l3_err = l3_err + 1;
      end
      for (l3_i = 0; l3_i < 36; l3_i = l3_i + 1) begin
        if (get_word_sram_b(36 + l3_i) !== l3_golden[36 + l3_i])
          l3_err = l3_err + 1;
      end
      $display("DIAG_L3POOL[%0d]: 72 words checked (2 passes), %0d errors", active_case_id, l3_err);
      if (l3_err > 0) begin
        $display("DIAG_L3POOL[%0d]: pass0[0]: actual=%h exp=%h", active_case_id,
                 get_word_sram_b(10'd0), l3_golden[0]);
        $display("DIAG_L3POOL[%0d]: pass1[0]: actual=%h exp=%h", active_case_id,
                 get_word_sram_b(10'd36), l3_golden[36]);
      end
      if (l3_err != 0)
        err_count = err_count + l3_err;
    end
  end

  // FC done: TopFSM transitions to ST_ARGMAX(14)
  // Compare fc_acc0/1/2 with golden
  integer fc_fd2, fc_scan2, fc_i2;
  reg signed [31:0] fc_val;
  initial begin
    fc_checked = 0;
  end

  always @(posedge clk) begin
    if (u_dut.u_top_fsm.state == 4'd14 && prev_top_fsm_state_d == 4'd13 && !fc_checked) begin
      fc_checked <= 1;
      $display("DIAG_FC[%0d]: acc0=%0d (exp %0d) %s", active_case_id,
               $signed(u_dut.fc_acc0), $signed(fc_golden[0]),
               ($signed(u_dut.fc_acc0) == $signed(fc_golden[0])) ? "OK" : "FAIL");
      $display("DIAG_FC[%0d]: acc1=%0d (exp %0d) %s", active_case_id,
               $signed(u_dut.fc_acc1), $signed(fc_golden[1]),
               ($signed(u_dut.fc_acc1) == $signed(fc_golden[1])) ? "OK" : "FAIL");
      $display("DIAG_FC[%0d]: acc2=%0d (exp %0d) %s", active_case_id,
               $signed(u_dut.fc_acc2), $signed(fc_golden[2]),
               ($signed(u_dut.fc_acc2) == $signed(fc_golden[2])) ? "OK" : "FAIL");
      if (($signed(u_dut.fc_acc0) != $signed(fc_golden[0])) ||
          ($signed(u_dut.fc_acc1) != $signed(fc_golden[1])) ||
          ($signed(u_dut.fc_acc2) != $signed(fc_golden[2])))
        err_count = err_count + 1;
    end
  end

  reg        fc_probe_active;
  reg [3:0]  fc_probe_wt_cnt;
  reg [3:0]  fc_probe_data_cnt;
  reg [3:0]  fc_probe_mul_cnt;
  integer    fc_probe_wt_total;
  integer    fc_probe_data_total;
  integer    fc_probe_mul_total;
  initial begin
    fc_probe_active   = 1'b0;
    fc_probe_wt_cnt   = 4'd0;
    fc_probe_data_cnt = 4'd0;
    fc_probe_mul_cnt  = 4'd0;
    fc_probe_wt_total = 0;
    fc_probe_data_total = 0;
    fc_probe_mul_total = 0;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      fc_probe_active   <= 1'b0;
      fc_probe_wt_cnt   <= 4'd0;
      fc_probe_data_cnt <= 4'd0;
      fc_probe_mul_cnt  <= 4'd0;
      fc_probe_wt_total <= 0;
      fc_probe_data_total <= 0;
      fc_probe_mul_total <= 0;
    end else begin
      if (!fc_probe_active && u_dut.u_top_fsm.state == 4'd13 && prev_top_fsm_state_d == 4'd12) begin
        fc_probe_active   <= 1'b1;
        fc_probe_wt_cnt   <= 4'd0;
        fc_probe_data_cnt <= 4'd0;
        fc_probe_mul_cnt  <= 4'd0;
        fc_probe_wt_total <= 0;
        fc_probe_data_total <= 0;
        fc_probe_mul_total <= 0;
      end

      if (fc_probe_active && predict_valid) begin
        $display("DIAG_FC_SUM: wt_words=%0d data_words=%0d muls=%0d",
                 fc_probe_wt_total, fc_probe_data_total, fc_probe_mul_total);
        fc_probe_active <= 1'b0;
      end

      if (fc_probe_active && u_dut.fc_cfg_valid && u_dut.fc_cfg_ready) begin
        $display("DIAG_FC_CFG: [%0t] data=%h last=%b",
                 $time, u_dut.fc_cfg_data, u_dut.fc_cfg_last);
      end

      if (fc_probe_active && u_dut.fc_wt_valid) begin
        fc_probe_wt_total <= fc_probe_wt_total + 1;
        if (fc_probe_wt_cnt < 4'd8) begin
          $display("DIAG_FC_WT:  [%0t] idx=%0d data=%h k0=%0d k1=%0d k2=%0d",
                   $time, fc_probe_wt_cnt, u_dut.sram_a_read_data,
                   $signed(u_dut.sram_a_read_data[31:24]),
                   $signed(u_dut.sram_a_read_data[23:16]),
                   $signed(u_dut.sram_a_read_data[15:8]));
          fc_probe_wt_cnt <= fc_probe_wt_cnt + 4'd1;
        end
      end

      if (fc_probe_active && u_dut.fc_data_valid) begin
        fc_probe_data_total <= fc_probe_data_total + 1;
        if (fc_probe_data_cnt < 4'd8) begin
          $display("DIAG_FC_DATA:[%0t] idx=%0d data=%h b3=%0d b2=%0d b1=%0d b0=%0d",
                   $time, fc_probe_data_cnt, u_dut.sram_b_read_data,
                   $signed(u_dut.sram_b_read_data[31:24]),
                   $signed(u_dut.sram_b_read_data[23:16]),
                   $signed(u_dut.sram_b_read_data[15:8]),
                   $signed(u_dut.sram_b_read_data[7:0]));
          fc_probe_data_cnt <= fc_probe_data_cnt + 4'd1;
        end
      end

      if (fc_probe_active && u_dut.fc_mul_en && (fc_probe_mul_cnt < 4'd8)) begin
        $display("DIAG_FC_MUL: [%0t] idx=%0d px=%0d k0=%0d k1=%0d k2=%0d acc0=%0d acc1=%0d acc2=%0d",
                 $time, fc_probe_mul_cnt,
                 $signed(u_dut.fc_pixel0),
                 $signed(u_dut.fc_kernel0),
                 $signed(u_dut.fc_kernel1),
                 $signed(u_dut.fc_kernel2),
                 $signed(u_dut.fc_acc0),
                 $signed(u_dut.fc_acc1),
                 $signed(u_dut.fc_acc2));
        fc_probe_mul_cnt <= fc_probe_mul_cnt + 4'd1;
      end

      if (fc_probe_active && u_dut.fc_mul_en)
        fc_probe_mul_total <= fc_probe_mul_total + 1;
    end
  end

endmodule
