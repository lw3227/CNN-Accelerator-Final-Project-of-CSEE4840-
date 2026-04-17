`timescale 1ns / 1ps

module tb_cnn_mmio_interface;

  localparam integer CONV_CFG_WORDS = 45;
  localparam integer CONV_WT_WORDS  = 225;
  localparam integer FC_BIAS_WORDS  = 10;
  localparam integer FCW_WORDS      = 864;
  localparam integer IMG_WORDS      = 1024;

  reg         clk;
  reg         reset;
  reg  [15:0] writedata;
  reg         write;
  reg         chipselect;
  reg  [19:0] address;
  wire [15:0] readdata;

  integer     timeout_cycles;
  integer     i;
  integer     fd;
  integer     scan;
  reg signed [31:0] val;
  reg signed [31:0] b0, b1, b2, b3;
  reg [1024*8-1:0]  proj_dir_str;
  reg [1024*8-1:0]  filepath;

  reg signed [31:0] conv_cfg_mem [0:CONV_CFG_WORDS-1];
  reg        [31:0] conv_wt_mem  [0:CONV_WT_WORDS-1];
  reg signed [31:0] fc_bias_mem  [0:FC_BIAS_WORDS-1];
  reg        [31:0] fcw_mem      [0:FCW_WORDS-1];
  reg        [31:0] img_mem      [0:IMG_WORDS-1];

  cnn_mmio_interface u_dut (
    .clk(clk),
    .reset(reset),
    .writedata(writedata),
    .write(write),
    .chipselect(chipselect),
    .address(address),
    .readdata(readdata)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task mmio_write_reg;
    input [4:0] reg_idx;
    input [15:0] data;
    begin
      @(negedge clk);
      chipselect <= 1'b1;
      write      <= 1'b1;
      address    <= {1'b1, 14'd0, reg_idx};
      writedata  <= data;
      @(negedge clk);
      chipselect <= 1'b0;
      write      <= 1'b0;
      address    <= 20'd0;
      writedata  <= 16'd0;
    end
  endtask

  task mmio_write_halfword;
    input [18:0] mem_addr;
    input [15:0] data;
    begin
      @(negedge clk);
      chipselect <= 1'b1;
      write      <= 1'b1;
      address    <= {1'b0, mem_addr};
      writedata  <= data;
      @(negedge clk);
      chipselect <= 1'b0;
      write      <= 1'b0;
      address    <= 20'd0;
      writedata  <= 16'd0;
    end
  endtask

  task mmio_read_reg;
    input  [4:0] reg_idx;
    output [15:0] data;
    begin
      @(negedge clk);
      chipselect <= 1'b1;
      write      <= 1'b0;
      address    <= {1'b1, 14'd0, reg_idx};
      #1 data = readdata;
      @(negedge clk);
      chipselect <= 1'b0;
      address    <= 20'd0;
    end
  endtask

  task load_conv_cfg;
    begin
      $sformat(filepath, "%0s/Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test/preload_conv_cfg_45w.txt", proj_dir_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (i = 0; i < CONV_CFG_WORDS; i = i + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        conv_cfg_mem[i] = val;
      end
      $fclose(fd);
    end
  endtask

  task load_conv_wt;
    begin
      $sformat(filepath, "%0s/Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test/preload_conv_wt_225w_bytes.txt", proj_dir_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (i = 0; i < CONV_WT_WORDS; i = i + 1) begin
        scan = $fscanf(fd, "%d\n", b0);
        scan = $fscanf(fd, "%d\n", b1);
        scan = $fscanf(fd, "%d\n", b2);
        scan = $fscanf(fd, "%d\n", b3);
        conv_wt_mem[i] = {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};
      end
      $fclose(fd);
    end
  endtask

  task load_fc_bias;
    begin
      $sformat(filepath, "%0s/Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test/preload_fc_bias_10w.txt", proj_dir_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (i = 0; i < FC_BIAS_WORDS; i = i + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        fc_bias_mem[i] = val;
      end
      $fclose(fd);
    end
  endtask

  task load_fcw;
    begin
      $sformat(filepath, "%0s/Golden-Module/matlab/hardware_aligned/debug/sram_preload/digit_0_test/preload_fcw_864w.txt", proj_dir_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (i = 0; i < FCW_WORDS; i = i + 1) begin
        scan = $fscanf(fd, "%d\n", val);
        fcw_mem[i] = val;
      end
      $fclose(fd);
    end
  endtask

  task load_case0_image;
    begin
      $sformat(filepath, "%0s/Golden-Module/matlab/hardware_aligned/debug/txt_cases/digit_0_test/tb_conv1_in_i8_64x64x1.txt", proj_dir_str);
      fd = $fopen(filepath, "r");
      if (fd == 0) begin
        $display("FATAL: cannot open %0s", filepath);
        $finish;
      end
      for (i = 0; i < IMG_WORDS; i = i + 1) begin
        scan = $fscanf(fd, "%d\n", b0);
        scan = $fscanf(fd, "%d\n", b1);
        scan = $fscanf(fd, "%d\n", b2);
        scan = $fscanf(fd, "%d\n", b3);
        img_mem[i] = {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};
      end
      $fclose(fd);
    end
  endtask

  task write_word_stream;
    input [18:0] base_halfword;
    input integer words;
    input integer kind;
    reg [31:0] packed_word;
    begin
      for (i = 0; i < words; i = i + 1) begin
        case (kind)
          0: packed_word = conv_cfg_mem[i];
          1: packed_word = conv_wt_mem[i];
          2: packed_word = fc_bias_mem[i];
          3: packed_word = fcw_mem[i];
          default: packed_word = img_mem[i];
        endcase
        mmio_write_halfword(base_halfword + (i * 2), packed_word[15:0]);
        mmio_write_halfword(base_halfword + (i * 2) + 1, packed_word[31:16]);
      end
    end
  endtask

  task wait_status_bit;
    input integer bit_idx;
    input [15:0] expected;
    reg [15:0] status_word;
    begin
      timeout_cycles = 0;
      status_word = 16'd0;
      while (status_word[bit_idx] !== expected[0]) begin
        mmio_read_reg(5'd1, status_word);
        timeout_cycles = timeout_cycles + 1;
        if (timeout_cycles > 20000) begin
          $display("FAIL: timeout waiting status bit %0d == %0d, status=%h", bit_idx, expected[0], status_word);
          $finish;
        end
      end
    end
  endtask

  reg [15:0] reg_data;
  reg [15:0] status_word;

  initial begin
    if (!$value$plusargs("PROJ_DIR=%s", proj_dir_str))
      proj_dir_str = ".";

    reset      = 1'b1;
    writedata  = 16'd0;
    write      = 1'b0;
    chipselect = 1'b0;
    address    = 20'd0;

    load_conv_cfg;
    load_conv_wt;
    load_fc_bias;
    load_fcw;
    load_case0_image;

    repeat (5) @(posedge clk);
    reset <= 1'b0;
    repeat (2) @(posedge clk);

    // Program config space explicitly so the MMIO contract is test-visible.
    mmio_write_reg(5'd2, 16'd0);
    mmio_write_reg(5'd3, 16'd45);
    mmio_write_reg(5'd4, 16'd90);
    mmio_write_reg(5'd5, 16'd225);
    mmio_write_reg(5'd6, 16'd540);
    mmio_write_reg(5'd7, 16'd10);
    mmio_write_reg(5'd8, 16'd560);
    mmio_write_reg(5'd9, 16'd864);
    mmio_write_reg(5'd10, 16'd2288);
    mmio_write_reg(5'd11, 16'd1024);

    mmio_read_reg(5'd10, reg_data);
    if (reg_data !== 16'd2288) begin
      $display("FAIL: image_base readback mismatch got=%0d", reg_data);
      $finish;
    end

    // Fill scratchpad memory: cfg, wt, fc bias, fcw, image.
    write_word_stream(19'd0,    CONV_CFG_WORDS, 0);
    write_word_stream(19'd90,   CONV_WT_WORDS,  1);
    write_word_stream(19'd540,  FC_BIAS_WORDS,  2);
    write_word_stream(19'd560,  FCW_WORDS,      3);
    write_word_stream(19'd2288, IMG_WORDS,      4);

    mmio_write_reg(5'd0, 16'h0001);
    wait_status_bit(2, 16'd1);
    repeat (10) @(posedge clk);

    mmio_write_reg(5'd0, 16'h0002);
    wait_status_bit(3, 16'd1);
    mmio_read_reg(5'd1, status_word);

    if (status_word[7:4] !== 4'd0) begin
      $display("FAIL: predict_class mismatch got=%0d status=%h", status_word[7:4], status_word);
      $finish;
    end

    mmio_read_reg(5'd13, reg_data);
    if (reg_data !== 16'd0) begin
      $display("FAIL: interface_error=%h", reg_data);
      $finish;
    end

    $display("PASS: cnn_mmio_interface smoke test predict_class=%0d status=%h", status_word[7:4], status_word);
    $finish;
  end

endmodule
