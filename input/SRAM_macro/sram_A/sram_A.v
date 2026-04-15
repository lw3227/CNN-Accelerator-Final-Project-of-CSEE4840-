// FE Release Version: 2.4.24 
//
//       CONFIDENTIAL AND PROPRIETARY SOFTWARE OF ARM PHYSICAL IP, INC.
//      
//       Copyright (c) 1993 - 2026 ARM Physical IP, Inc.  All Rights Reserved.
//      
//       Use of this Software is subject to the terms and conditions of the
//       applicable license agreement with ARM Physical IP, Inc.
//       In addition, this Software is protected by patents, copyright law 
//       and international treaties.
//      
//       The copyright notice(s) in this Software does not indicate actual or
//       intended publication of this Software.
//
//      Verilog model for Synchronous Single-Port Ram
//
//      Instance Name:              sram_A
//      Words:                      1024
//      Bits:                       32
//      Mux:                        8
//      Drive:                      6
//      Write Mask:                 Off
//      Extra Margin Adjustment:    On
//      Accelerated Retention Test: Off
//      Redundant Rows:             0
//      Redundant Columns:          0
//      Test Muxes                  Off
//
//      Creation Date:  Fri Apr 10 16:19:39 2026
//      Version: 	r0p0-00eac0
//
//      Modeling Assumptions: This model supports full gate level simulation
//          including proper x-handling and timing check behavior.  Unit
//          delay timing is included in the model. Back-annotation of SDF
//          (v2.1) is supported.  SDF can be created utilyzing the delay
//          calculation views provided with this generator and supported
//          delay calculators.  All buses are modeled [MSB:LSB].  All 
//          ports are padded with Verilog primitives.
//
//      Modeling Limitations: None.
//
//      Known Bugs: None.
//
//      Known Work Arounds: N/A
//
`ifdef ARM_UD_MODEL

`timescale 1 ns/1 ps

`ifdef ARM_UD_DP
`else
`define ARM_UD_DP #0.001
`endif
`ifdef ARM_UD_CP
`else
`define ARM_UD_CP
`endif
`ifdef ARM_UD_SEQ
`else
`define ARM_UD_SEQ #0.01
`endif

`celldefine
`ifdef POWER_PINS
module sram_A (Q, CLK, CEN, WEN, A, D, EMA, RETN, VSS, VDD);
`else
module sram_A (Q, CLK, CEN, WEN, A, D, EMA, RETN);
`endif

  parameter BITS = 32;
  parameter WORDS = 1024;
  parameter MUX = 8;
  parameter MEM_WIDTH = 256; // redun block size 8, 128 on left, 128 on right
  parameter MEM_HEIGHT = 128;
  parameter WP_SIZE = 32 ;
  parameter UPM_WIDTH = 3;

  output [31:0] Q;
  input  CLK;
  input  CEN;
  input  WEN;
  input [9:0] A;
  input [31:0] D;
  input [2:0] EMA;
  input  RETN;
`ifdef POWER_PINS
  inout VSS;
  inout VDD;
`endif

  integer row_address;
  integer mux_address;
  reg [255:0] mem [0:127];
  reg [255:0] row;
  reg LAST_CLK;
  reg [255:0] data_out;
  reg [255:0] row_mask;
  reg [255:0] new_data;
  reg [31:0] Q_int;
  reg [31:0] writeEnable;
  reg clk0_int;
  reg CREN_legal;
  initial CREN_legal = 1'b1;

  wire [31:0] Q_;
 wire  CLK_;
  wire  CEN_;
  reg  CEN_int;
  wire  WEN_;
  reg  WEN_int;
  wire [9:0] A_;
  reg [9:0] A_int;
  wire [31:0] D_;
  reg [31:0] D_int;
  wire [2:0] EMA_;
  reg [2:0] EMA_int;
  wire  RETN_;
  reg  RETN_int;

  assign Q[0] = Q_[0]; 
  assign Q[1] = Q_[1]; 
  assign Q[2] = Q_[2]; 
  assign Q[3] = Q_[3]; 
  assign Q[4] = Q_[4]; 
  assign Q[5] = Q_[5]; 
  assign Q[6] = Q_[6]; 
  assign Q[7] = Q_[7]; 
  assign Q[8] = Q_[8]; 
  assign Q[9] = Q_[9]; 
  assign Q[10] = Q_[10]; 
  assign Q[11] = Q_[11]; 
  assign Q[12] = Q_[12]; 
  assign Q[13] = Q_[13]; 
  assign Q[14] = Q_[14]; 
  assign Q[15] = Q_[15]; 
  assign Q[16] = Q_[16]; 
  assign Q[17] = Q_[17]; 
  assign Q[18] = Q_[18]; 
  assign Q[19] = Q_[19]; 
  assign Q[20] = Q_[20]; 
  assign Q[21] = Q_[21]; 
  assign Q[22] = Q_[22]; 
  assign Q[23] = Q_[23]; 
  assign Q[24] = Q_[24]; 
  assign Q[25] = Q_[25]; 
  assign Q[26] = Q_[26]; 
  assign Q[27] = Q_[27]; 
  assign Q[28] = Q_[28]; 
  assign Q[29] = Q_[29]; 
  assign Q[30] = Q_[30]; 
  assign Q[31] = Q_[31]; 
  assign CLK_ = CLK;
  assign CEN_ = CEN;
  assign WEN_ = WEN;
  assign A_[0] = A[0];
  assign A_[1] = A[1];
  assign A_[2] = A[2];
  assign A_[3] = A[3];
  assign A_[4] = A[4];
  assign A_[5] = A[5];
  assign A_[6] = A[6];
  assign A_[7] = A[7];
  assign A_[8] = A[8];
  assign A_[9] = A[9];
  assign D_[0] = D[0];
  assign D_[1] = D[1];
  assign D_[2] = D[2];
  assign D_[3] = D[3];
  assign D_[4] = D[4];
  assign D_[5] = D[5];
  assign D_[6] = D[6];
  assign D_[7] = D[7];
  assign D_[8] = D[8];
  assign D_[9] = D[9];
  assign D_[10] = D[10];
  assign D_[11] = D[11];
  assign D_[12] = D[12];
  assign D_[13] = D[13];
  assign D_[14] = D[14];
  assign D_[15] = D[15];
  assign D_[16] = D[16];
  assign D_[17] = D[17];
  assign D_[18] = D[18];
  assign D_[19] = D[19];
  assign D_[20] = D[20];
  assign D_[21] = D[21];
  assign D_[22] = D[22];
  assign D_[23] = D[23];
  assign D_[24] = D[24];
  assign D_[25] = D[25];
  assign D_[26] = D[26];
  assign D_[27] = D[27];
  assign D_[28] = D[28];
  assign D_[29] = D[29];
  assign D_[30] = D[30];
  assign D_[31] = D[31];
  assign EMA_[0] = EMA[0];
  assign EMA_[1] = EMA[1];
  assign EMA_[2] = EMA[2];
  assign RETN_ = RETN;

  assign `ARM_UD_SEQ Q_ = RETN_ ? (Q_int) : {32{1'b0}};

`ifdef INITIALIZE_MEMORY
  integer i;
  initial
    for (i = 0; i < MEM_HEIGHT; i = i + 1)
      mem[i] = {MEM_WIDTH{1'b0}};
`endif

  task failedWrite;
  input port;
  integer i;
  begin
    for (i = 0; i < MEM_HEIGHT; i = i + 1)
      mem[i] = {MEM_WIDTH{1'bx}};
  end
  endtask

  function isBitX;
    input bitIn;
    begin
      isBitX = ( bitIn===1'bx || bitIn===1'bz ) ? 1'b1 : 1'b0;
    end
  endfunction


  task readWrite;
  begin
    if (RETN_int === 1'bx) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (RETN_int === 1'b0 && CEN_int === 1'b0) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (RETN_int === 1'b0) begin
      // no cycle in retention mode
    end else if (^{CEN_int, EMA_int} === 1'bx) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if ((A_int >= WORDS) && (CEN_int === 1'b0)) begin
      writeEnable = ~{32{WEN_int}};
      Q_int = ((writeEnable & D_int) | (~writeEnable & {32{1'bx}}));
    end else if (CEN_int === 1'b0 && (^A_int) === 1'bx) begin
      if (WEN_int !== 1'b1) failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (CEN_int === 1'b0) begin
      mux_address = (A_int & 3'b111);
      row_address = (A_int >> 3);
      if (row_address >= 128)
        row = {256{1'bx}};
      else
        row = mem[row_address];
      writeEnable = ~{32{WEN_int}};
      row_mask =  ( {7'b0000000, writeEnable[31], 7'b0000000, writeEnable[30], 7'b0000000, writeEnable[29],
          7'b0000000, writeEnable[28], 7'b0000000, writeEnable[27], 7'b0000000, writeEnable[26],
          7'b0000000, writeEnable[25], 7'b0000000, writeEnable[24], 7'b0000000, writeEnable[23],
          7'b0000000, writeEnable[22], 7'b0000000, writeEnable[21], 7'b0000000, writeEnable[20],
          7'b0000000, writeEnable[19], 7'b0000000, writeEnable[18], 7'b0000000, writeEnable[17],
          7'b0000000, writeEnable[16], 7'b0000000, writeEnable[15], 7'b0000000, writeEnable[14],
          7'b0000000, writeEnable[13], 7'b0000000, writeEnable[12], 7'b0000000, writeEnable[11],
          7'b0000000, writeEnable[10], 7'b0000000, writeEnable[9], 7'b0000000, writeEnable[8],
          7'b0000000, writeEnable[7], 7'b0000000, writeEnable[6], 7'b0000000, writeEnable[5],
          7'b0000000, writeEnable[4], 7'b0000000, writeEnable[3], 7'b0000000, writeEnable[2],
          7'b0000000, writeEnable[1], 7'b0000000, writeEnable[0]} << mux_address);
      new_data =  ( {7'b0000000, D_int[31], 7'b0000000, D_int[30], 7'b0000000, D_int[29],
          7'b0000000, D_int[28], 7'b0000000, D_int[27], 7'b0000000, D_int[26], 7'b0000000, D_int[25],
          7'b0000000, D_int[24], 7'b0000000, D_int[23], 7'b0000000, D_int[22], 7'b0000000, D_int[21],
          7'b0000000, D_int[20], 7'b0000000, D_int[19], 7'b0000000, D_int[18], 7'b0000000, D_int[17],
          7'b0000000, D_int[16], 7'b0000000, D_int[15], 7'b0000000, D_int[14], 7'b0000000, D_int[13],
          7'b0000000, D_int[12], 7'b0000000, D_int[11], 7'b0000000, D_int[10], 7'b0000000, D_int[9],
          7'b0000000, D_int[8], 7'b0000000, D_int[7], 7'b0000000, D_int[6], 7'b0000000, D_int[5],
          7'b0000000, D_int[4], 7'b0000000, D_int[3], 7'b0000000, D_int[2], 7'b0000000, D_int[1],
          7'b0000000, D_int[0]} << mux_address);
      row = (row & ~row_mask) | (row_mask & (~row_mask | new_data));
      mem[row_address] = row;
      data_out = (row >> mux_address);
      Q_int = {data_out[248], data_out[240], data_out[232], data_out[224], data_out[216],
        data_out[208], data_out[200], data_out[192], data_out[184], data_out[176],
        data_out[168], data_out[160], data_out[152], data_out[144], data_out[136],
        data_out[128], data_out[120], data_out[112], data_out[104], data_out[96], data_out[88],
        data_out[80], data_out[72], data_out[64], data_out[56], data_out[48], data_out[40],
        data_out[32], data_out[24], data_out[16], data_out[8], data_out[0]};
    end
  end
  endtask

  always @ RETN_ begin
    if (RETN_ == 1'b0) begin
      Q_int = {32{1'b0}};
      CEN_int = 1'b0;
      WEN_int = 1'b0;
      A_int = {10{1'b0}};
      D_int = {32{1'b0}};
      EMA_int = {3{1'b0}};
      RETN_int = 1'b0;
    end else begin
      Q_int = {32{1'bx}};
      CEN_int = 1'bx;
      WEN_int = 1'bx;
      A_int = {10{1'bx}};
      D_int = {32{1'bx}};
      EMA_int = {3{1'bx}};
      RETN_int = 1'bx;
    end
    RETN_int = RETN_;
  end

  always @ CLK_ begin
`ifdef POWER_PINS
    if (VSS === 1'bx || VSS === 1'bz)
      $display("ERROR: Illegal value for VSS %b", VSS);
    if (VDD === 1'bx || VDD === 1'bz)
      $display("ERROR: Illegal value for VDD %b", VDD);
`endif
    if (CLK_ === 1'bx && (CEN_ !== 1'b1)) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (CLK_ === 1'b1 && LAST_CLK === 1'b0) begin
      CEN_int = CEN_;
      WEN_int = WEN_;
      A_int = A_;
      D_int = D_;
      EMA_int = EMA_;
      RETN_int = RETN_;
      clk0_int = 1'b0;
      readWrite;
    end
    LAST_CLK = CLK_;
  end


endmodule
`endcelldefine
`else
`timescale 1 ns/1 ps
`celldefine
`ifdef POWER_PINS
module sram_A (Q, CLK, CEN, WEN, A, D, EMA, RETN, VSS, VDD);
`else
module sram_A (Q, CLK, CEN, WEN, A, D, EMA, RETN);
`endif

  parameter BITS = 32;
  parameter WORDS = 1024;
  parameter MUX = 8;
  parameter MEM_WIDTH = 256; // redun block size 8, 128 on left, 128 on right
  parameter MEM_HEIGHT = 128;
  parameter WP_SIZE = 32 ;
  parameter UPM_WIDTH = 3;

  output [31:0] Q;
  input  CLK;
  input  CEN;
  input  WEN;
  input [9:0] A;
  input [31:0] D;
  input [2:0] EMA;
  input  RETN;
`ifdef POWER_PINS
  inout VSS;
  inout VDD;
`endif

  integer row_address;
  integer mux_address;
  reg [255:0] mem [0:127];
  reg [255:0] row;
  reg LAST_CLK;
  reg [255:0] data_out;
  reg [255:0] row_mask;
  reg [255:0] new_data;
  reg [31:0] Q_int;
  reg [31:0] writeEnable;

  reg NOT_A0, NOT_A1, NOT_A2, NOT_A3, NOT_A4, NOT_A5, NOT_A6, NOT_A7, NOT_A8, NOT_A9;
  reg NOT_CEN, NOT_CLK_MINH, NOT_CLK_MINL, NOT_CLK_PER, NOT_D0, NOT_D1, NOT_D10, NOT_D11;
  reg NOT_D12, NOT_D13, NOT_D14, NOT_D15, NOT_D16, NOT_D17, NOT_D18, NOT_D19, NOT_D2;
  reg NOT_D20, NOT_D21, NOT_D22, NOT_D23, NOT_D24, NOT_D25, NOT_D26, NOT_D27, NOT_D28;
  reg NOT_D29, NOT_D3, NOT_D30, NOT_D31, NOT_D4, NOT_D5, NOT_D6, NOT_D7, NOT_D8, NOT_D9;
  reg NOT_EMA0, NOT_EMA1, NOT_EMA2, NOT_RETN, NOT_WEN;
  reg clk0_int;
  reg CREN_legal;
  initial CREN_legal = 1'b1;

  wire [31:0] Q_;
 wire  CLK_;
  wire  CEN_;
  reg  CEN_int;
  wire  WEN_;
  reg  WEN_int;
  wire [9:0] A_;
  reg [9:0] A_int;
  wire [31:0] D_;
  reg [31:0] D_int;
  wire [2:0] EMA_;
  reg [2:0] EMA_int;
  wire  RETN_;
  reg  RETN_int;

  buf B0(Q[0], Q_[0]);
  buf B1(Q[1], Q_[1]);
  buf B2(Q[2], Q_[2]);
  buf B3(Q[3], Q_[3]);
  buf B4(Q[4], Q_[4]);
  buf B5(Q[5], Q_[5]);
  buf B6(Q[6], Q_[6]);
  buf B7(Q[7], Q_[7]);
  buf B8(Q[8], Q_[8]);
  buf B9(Q[9], Q_[9]);
  buf B10(Q[10], Q_[10]);
  buf B11(Q[11], Q_[11]);
  buf B12(Q[12], Q_[12]);
  buf B13(Q[13], Q_[13]);
  buf B14(Q[14], Q_[14]);
  buf B15(Q[15], Q_[15]);
  buf B16(Q[16], Q_[16]);
  buf B17(Q[17], Q_[17]);
  buf B18(Q[18], Q_[18]);
  buf B19(Q[19], Q_[19]);
  buf B20(Q[20], Q_[20]);
  buf B21(Q[21], Q_[21]);
  buf B22(Q[22], Q_[22]);
  buf B23(Q[23], Q_[23]);
  buf B24(Q[24], Q_[24]);
  buf B25(Q[25], Q_[25]);
  buf B26(Q[26], Q_[26]);
  buf B27(Q[27], Q_[27]);
  buf B28(Q[28], Q_[28]);
  buf B29(Q[29], Q_[29]);
  buf B30(Q[30], Q_[30]);
  buf B31(Q[31], Q_[31]);
  buf B32(CLK_, CLK);
  buf B33(CEN_, CEN);
  buf B34(WEN_, WEN);
  buf B35(A_[0], A[0]);
  buf B36(A_[1], A[1]);
  buf B37(A_[2], A[2]);
  buf B38(A_[3], A[3]);
  buf B39(A_[4], A[4]);
  buf B40(A_[5], A[5]);
  buf B41(A_[6], A[6]);
  buf B42(A_[7], A[7]);
  buf B43(A_[8], A[8]);
  buf B44(A_[9], A[9]);
  buf B45(D_[0], D[0]);
  buf B46(D_[1], D[1]);
  buf B47(D_[2], D[2]);
  buf B48(D_[3], D[3]);
  buf B49(D_[4], D[4]);
  buf B50(D_[5], D[5]);
  buf B51(D_[6], D[6]);
  buf B52(D_[7], D[7]);
  buf B53(D_[8], D[8]);
  buf B54(D_[9], D[9]);
  buf B55(D_[10], D[10]);
  buf B56(D_[11], D[11]);
  buf B57(D_[12], D[12]);
  buf B58(D_[13], D[13]);
  buf B59(D_[14], D[14]);
  buf B60(D_[15], D[15]);
  buf B61(D_[16], D[16]);
  buf B62(D_[17], D[17]);
  buf B63(D_[18], D[18]);
  buf B64(D_[19], D[19]);
  buf B65(D_[20], D[20]);
  buf B66(D_[21], D[21]);
  buf B67(D_[22], D[22]);
  buf B68(D_[23], D[23]);
  buf B69(D_[24], D[24]);
  buf B70(D_[25], D[25]);
  buf B71(D_[26], D[26]);
  buf B72(D_[27], D[27]);
  buf B73(D_[28], D[28]);
  buf B74(D_[29], D[29]);
  buf B75(D_[30], D[30]);
  buf B76(D_[31], D[31]);
  buf B77(EMA_[0], EMA[0]);
  buf B78(EMA_[1], EMA[1]);
  buf B79(EMA_[2], EMA[2]);
  buf B80(RETN_, RETN);

  assign Q_ = RETN_ ? (Q_int) : {32{1'b0}};

`ifdef INITIALIZE_MEMORY
  integer i;
  initial
    for (i = 0; i < MEM_HEIGHT; i = i + 1)
      mem[i] = {MEM_WIDTH{1'b0}};
`endif

  task failedWrite;
  input port;
  integer i;
  begin
    for (i = 0; i < MEM_HEIGHT; i = i + 1)
      mem[i] = {MEM_WIDTH{1'bx}};
  end
  endtask

  function isBitX;
    input bitIn;
    begin
      isBitX = ( bitIn===1'bx || bitIn===1'bz ) ? 1'b1 : 1'b0;
    end
  endfunction


  task readWrite;
  begin
    if (RETN_int === 1'bx) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (RETN_int === 1'b0 && CEN_int === 1'b0) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (RETN_int === 1'b0) begin
      // no cycle in retention mode
    end else if (^{CEN_int, EMA_int} === 1'bx) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if ((A_int >= WORDS) && (CEN_int === 1'b0)) begin
      writeEnable = ~{32{WEN_int}};
      Q_int = ((writeEnable & D_int) | (~writeEnable & {32{1'bx}}));
    end else if (CEN_int === 1'b0 && (^A_int) === 1'bx) begin
      if (WEN_int !== 1'b1) failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (CEN_int === 1'b0) begin
      mux_address = (A_int & 3'b111);
      row_address = (A_int >> 3);
      if (row_address >= 128)
        row = {256{1'bx}};
      else
        row = mem[row_address];
      writeEnable = ~{32{WEN_int}};
      row_mask =  ( {7'b0000000, writeEnable[31], 7'b0000000, writeEnable[30], 7'b0000000, writeEnable[29],
          7'b0000000, writeEnable[28], 7'b0000000, writeEnable[27], 7'b0000000, writeEnable[26],
          7'b0000000, writeEnable[25], 7'b0000000, writeEnable[24], 7'b0000000, writeEnable[23],
          7'b0000000, writeEnable[22], 7'b0000000, writeEnable[21], 7'b0000000, writeEnable[20],
          7'b0000000, writeEnable[19], 7'b0000000, writeEnable[18], 7'b0000000, writeEnable[17],
          7'b0000000, writeEnable[16], 7'b0000000, writeEnable[15], 7'b0000000, writeEnable[14],
          7'b0000000, writeEnable[13], 7'b0000000, writeEnable[12], 7'b0000000, writeEnable[11],
          7'b0000000, writeEnable[10], 7'b0000000, writeEnable[9], 7'b0000000, writeEnable[8],
          7'b0000000, writeEnable[7], 7'b0000000, writeEnable[6], 7'b0000000, writeEnable[5],
          7'b0000000, writeEnable[4], 7'b0000000, writeEnable[3], 7'b0000000, writeEnable[2],
          7'b0000000, writeEnable[1], 7'b0000000, writeEnable[0]} << mux_address);
      new_data =  ( {7'b0000000, D_int[31], 7'b0000000, D_int[30], 7'b0000000, D_int[29],
          7'b0000000, D_int[28], 7'b0000000, D_int[27], 7'b0000000, D_int[26], 7'b0000000, D_int[25],
          7'b0000000, D_int[24], 7'b0000000, D_int[23], 7'b0000000, D_int[22], 7'b0000000, D_int[21],
          7'b0000000, D_int[20], 7'b0000000, D_int[19], 7'b0000000, D_int[18], 7'b0000000, D_int[17],
          7'b0000000, D_int[16], 7'b0000000, D_int[15], 7'b0000000, D_int[14], 7'b0000000, D_int[13],
          7'b0000000, D_int[12], 7'b0000000, D_int[11], 7'b0000000, D_int[10], 7'b0000000, D_int[9],
          7'b0000000, D_int[8], 7'b0000000, D_int[7], 7'b0000000, D_int[6], 7'b0000000, D_int[5],
          7'b0000000, D_int[4], 7'b0000000, D_int[3], 7'b0000000, D_int[2], 7'b0000000, D_int[1],
          7'b0000000, D_int[0]} << mux_address);
      row = (row & ~row_mask) | (row_mask & (~row_mask | new_data));
      mem[row_address] = row;
      data_out = (row >> mux_address);
      Q_int = {data_out[248], data_out[240], data_out[232], data_out[224], data_out[216],
        data_out[208], data_out[200], data_out[192], data_out[184], data_out[176],
        data_out[168], data_out[160], data_out[152], data_out[144], data_out[136],
        data_out[128], data_out[120], data_out[112], data_out[104], data_out[96], data_out[88],
        data_out[80], data_out[72], data_out[64], data_out[56], data_out[48], data_out[40],
        data_out[32], data_out[24], data_out[16], data_out[8], data_out[0]};
    end
  end
  endtask

  always @ RETN_ begin
    if (RETN_ == 1'b0) begin
      Q_int = {32{1'b0}};
      CEN_int = 1'b0;
      WEN_int = 1'b0;
      A_int = {10{1'b0}};
      D_int = {32{1'b0}};
      EMA_int = {3{1'b0}};
      RETN_int = 1'b0;
    end else begin
      Q_int = {32{1'bx}};
      CEN_int = 1'bx;
      WEN_int = 1'bx;
      A_int = {10{1'bx}};
      D_int = {32{1'bx}};
      EMA_int = {3{1'bx}};
      RETN_int = 1'bx;
    end
    RETN_int = RETN_;
  end

  always @ CLK_ begin
`ifdef POWER_PINS
    if (VSS === 1'bx || VSS === 1'bz)
      $display("ERROR: Illegal value for VSS %b", VSS);
    if (VDD === 1'bx || VDD === 1'bz)
      $display("ERROR: Illegal value for VDD %b", VDD);
`endif
    if (CLK_ === 1'bx && (CEN_ !== 1'b1)) begin
      failedWrite(0);
      Q_int = {32{1'bx}};
    end else if (CLK_ === 1'b1 && LAST_CLK === 1'b0) begin
      CEN_int = CEN_;
      WEN_int = WEN_;
      A_int = A_;
      D_int = D_;
      EMA_int = EMA_;
      RETN_int = RETN_;
      clk0_int = 1'b0;
      readWrite;
    end
    LAST_CLK = CLK_;
  end

  reg globalNotifier0;
  initial globalNotifier0 = 1'b0;

  always @ globalNotifier0 begin
    if ($realtime == 0) begin
    end else if (CEN_int === 1'bx || EMA_int[0] === 1'bx || EMA_int[1] === 1'bx || 
      EMA_int[2] === 1'bx || RETN_int === 1'bx || clk0_int === 1'bx) begin
      Q_int = {32{1'bx}};
      failedWrite(0);
    end else begin
      readWrite;
   end
    globalNotifier0 = 1'b0;
  end

  always @ NOT_A0 begin
    A_int[0] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A1 begin
    A_int[1] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A2 begin
    A_int[2] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A3 begin
    A_int[3] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A4 begin
    A_int[4] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A5 begin
    A_int[5] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A6 begin
    A_int[6] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A7 begin
    A_int[7] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A8 begin
    A_int[8] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_A9 begin
    A_int[9] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_CEN begin
    CEN_int = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D0 begin
    D_int[0] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D10 begin
    D_int[10] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D11 begin
    D_int[11] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D12 begin
    D_int[12] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D13 begin
    D_int[13] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D14 begin
    D_int[14] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D15 begin
    D_int[15] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D16 begin
    D_int[16] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D17 begin
    D_int[17] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D18 begin
    D_int[18] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D19 begin
    D_int[19] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D1 begin
    D_int[1] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D20 begin
    D_int[20] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D21 begin
    D_int[21] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D22 begin
    D_int[22] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D23 begin
    D_int[23] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D24 begin
    D_int[24] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D25 begin
    D_int[25] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D26 begin
    D_int[26] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D27 begin
    D_int[27] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D28 begin
    D_int[28] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D29 begin
    D_int[29] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D2 begin
    D_int[2] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D30 begin
    D_int[30] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D31 begin
    D_int[31] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D3 begin
    D_int[3] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D4 begin
    D_int[4] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D5 begin
    D_int[5] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D6 begin
    D_int[6] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D7 begin
    D_int[7] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D8 begin
    D_int[8] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_D9 begin
    D_int[9] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_EMA0 begin
    EMA_int[0] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_EMA1 begin
    EMA_int[1] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_EMA2 begin
    EMA_int[2] = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_RETN begin
    RETN_int = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_WEN begin
    WEN_int = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_CLK_MINH begin
    clk0_int = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_CLK_MINL begin
    clk0_int = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end
  always @ NOT_CLK_PER begin
    clk0_int = 1'bx;
    if ( globalNotifier0 === 1'b0 ) globalNotifier0 = 1'bx;
  end

  wire CEN_flag;
  wire flag;
  wire D_flag;
  wire cyc_flag;
  wire EMA2eq0andEMA1eq0andEMA0eq0;
  wire EMA2eq0andEMA1eq0andEMA0eq1;
  wire EMA2eq0andEMA1eq1andEMA0eq0;
  wire EMA2eq0andEMA1eq1andEMA0eq1;
  wire EMA2eq1andEMA1eq0andEMA0eq0;
  wire EMA2eq1andEMA1eq0andEMA0eq1;
  wire EMA2eq1andEMA1eq1andEMA0eq0;
  wire EMA2eq1andEMA1eq1andEMA0eq1;
  assign CEN_flag = 1'b1;
  assign flag = !CEN_;
  assign D_flag = !(CEN_ || WEN_);
  assign cyc_flag = !CEN_;
  assign EMA2eq0andEMA1eq0andEMA0eq0 = !EMA_[2] && !EMA_[1] && !EMA_[0] && cyc_flag;
  assign EMA2eq0andEMA1eq0andEMA0eq1 = !EMA_[2] && !EMA_[1] && EMA_[0] && cyc_flag;
  assign EMA2eq0andEMA1eq1andEMA0eq0 = !EMA_[2] && EMA_[1] && !EMA_[0] && cyc_flag;
  assign EMA2eq0andEMA1eq1andEMA0eq1 = !EMA_[2] && EMA_[1] && EMA_[0] && cyc_flag;
  assign EMA2eq1andEMA1eq0andEMA0eq0 = EMA_[2] && !EMA_[1] && !EMA_[0] && cyc_flag;
  assign EMA2eq1andEMA1eq0andEMA0eq1 = EMA_[2] && !EMA_[1] && EMA_[0] && cyc_flag;
  assign EMA2eq1andEMA1eq1andEMA0eq0 = EMA_[2] && EMA_[1] && !EMA_[0] && cyc_flag;
  assign EMA2eq1andEMA1eq1andEMA0eq1 = EMA_[2] && EMA_[1] && EMA_[0] && cyc_flag;

  specify
      $hold(posedge CEN, negedge RETN, 1.000, NOT_RETN);
      $setuphold(posedge CLK &&& CEN_flag, posedge CEN, 1.000, 0.500, NOT_CEN);
      $setuphold(posedge CLK &&& CEN_flag, negedge CEN, 1.000, 0.500, NOT_CEN);
      $setuphold(posedge CLK &&& flag, posedge WEN, 1.000, 0.500, NOT_WEN);
      $setuphold(posedge CLK &&& flag, negedge WEN, 1.000, 0.500, NOT_WEN);
      $setuphold(posedge CLK &&& flag, posedge A[9], 1.000, 0.500, NOT_A9);
      $setuphold(posedge CLK &&& flag, negedge A[9], 1.000, 0.500, NOT_A9);
      $setuphold(posedge CLK &&& flag, posedge A[8], 1.000, 0.500, NOT_A8);
      $setuphold(posedge CLK &&& flag, negedge A[8], 1.000, 0.500, NOT_A8);
      $setuphold(posedge CLK &&& flag, posedge A[7], 1.000, 0.500, NOT_A7);
      $setuphold(posedge CLK &&& flag, negedge A[7], 1.000, 0.500, NOT_A7);
      $setuphold(posedge CLK &&& flag, posedge A[6], 1.000, 0.500, NOT_A6);
      $setuphold(posedge CLK &&& flag, negedge A[6], 1.000, 0.500, NOT_A6);
      $setuphold(posedge CLK &&& flag, posedge A[5], 1.000, 0.500, NOT_A5);
      $setuphold(posedge CLK &&& flag, negedge A[5], 1.000, 0.500, NOT_A5);
      $setuphold(posedge CLK &&& flag, posedge A[4], 1.000, 0.500, NOT_A4);
      $setuphold(posedge CLK &&& flag, negedge A[4], 1.000, 0.500, NOT_A4);
      $setuphold(posedge CLK &&& flag, posedge A[3], 1.000, 0.500, NOT_A3);
      $setuphold(posedge CLK &&& flag, negedge A[3], 1.000, 0.500, NOT_A3);
      $setuphold(posedge CLK &&& flag, posedge A[2], 1.000, 0.500, NOT_A2);
      $setuphold(posedge CLK &&& flag, negedge A[2], 1.000, 0.500, NOT_A2);
      $setuphold(posedge CLK &&& flag, posedge A[1], 1.000, 0.500, NOT_A1);
      $setuphold(posedge CLK &&& flag, negedge A[1], 1.000, 0.500, NOT_A1);
      $setuphold(posedge CLK &&& flag, posedge A[0], 1.000, 0.500, NOT_A0);
      $setuphold(posedge CLK &&& flag, negedge A[0], 1.000, 0.500, NOT_A0);
      $setuphold(posedge CLK &&& D_flag, posedge D[31], 1.000, 0.500, NOT_D31);
      $setuphold(posedge CLK &&& D_flag, negedge D[31], 1.000, 0.500, NOT_D31);
      $setuphold(posedge CLK &&& D_flag, posedge D[30], 1.000, 0.500, NOT_D30);
      $setuphold(posedge CLK &&& D_flag, negedge D[30], 1.000, 0.500, NOT_D30);
      $setuphold(posedge CLK &&& D_flag, posedge D[29], 1.000, 0.500, NOT_D29);
      $setuphold(posedge CLK &&& D_flag, negedge D[29], 1.000, 0.500, NOT_D29);
      $setuphold(posedge CLK &&& D_flag, posedge D[28], 1.000, 0.500, NOT_D28);
      $setuphold(posedge CLK &&& D_flag, negedge D[28], 1.000, 0.500, NOT_D28);
      $setuphold(posedge CLK &&& D_flag, posedge D[27], 1.000, 0.500, NOT_D27);
      $setuphold(posedge CLK &&& D_flag, negedge D[27], 1.000, 0.500, NOT_D27);
      $setuphold(posedge CLK &&& D_flag, posedge D[26], 1.000, 0.500, NOT_D26);
      $setuphold(posedge CLK &&& D_flag, negedge D[26], 1.000, 0.500, NOT_D26);
      $setuphold(posedge CLK &&& D_flag, posedge D[25], 1.000, 0.500, NOT_D25);
      $setuphold(posedge CLK &&& D_flag, negedge D[25], 1.000, 0.500, NOT_D25);
      $setuphold(posedge CLK &&& D_flag, posedge D[24], 1.000, 0.500, NOT_D24);
      $setuphold(posedge CLK &&& D_flag, negedge D[24], 1.000, 0.500, NOT_D24);
      $setuphold(posedge CLK &&& D_flag, posedge D[23], 1.000, 0.500, NOT_D23);
      $setuphold(posedge CLK &&& D_flag, negedge D[23], 1.000, 0.500, NOT_D23);
      $setuphold(posedge CLK &&& D_flag, posedge D[22], 1.000, 0.500, NOT_D22);
      $setuphold(posedge CLK &&& D_flag, negedge D[22], 1.000, 0.500, NOT_D22);
      $setuphold(posedge CLK &&& D_flag, posedge D[21], 1.000, 0.500, NOT_D21);
      $setuphold(posedge CLK &&& D_flag, negedge D[21], 1.000, 0.500, NOT_D21);
      $setuphold(posedge CLK &&& D_flag, posedge D[20], 1.000, 0.500, NOT_D20);
      $setuphold(posedge CLK &&& D_flag, negedge D[20], 1.000, 0.500, NOT_D20);
      $setuphold(posedge CLK &&& D_flag, posedge D[19], 1.000, 0.500, NOT_D19);
      $setuphold(posedge CLK &&& D_flag, negedge D[19], 1.000, 0.500, NOT_D19);
      $setuphold(posedge CLK &&& D_flag, posedge D[18], 1.000, 0.500, NOT_D18);
      $setuphold(posedge CLK &&& D_flag, negedge D[18], 1.000, 0.500, NOT_D18);
      $setuphold(posedge CLK &&& D_flag, posedge D[17], 1.000, 0.500, NOT_D17);
      $setuphold(posedge CLK &&& D_flag, negedge D[17], 1.000, 0.500, NOT_D17);
      $setuphold(posedge CLK &&& D_flag, posedge D[16], 1.000, 0.500, NOT_D16);
      $setuphold(posedge CLK &&& D_flag, negedge D[16], 1.000, 0.500, NOT_D16);
      $setuphold(posedge CLK &&& D_flag, posedge D[15], 1.000, 0.500, NOT_D15);
      $setuphold(posedge CLK &&& D_flag, negedge D[15], 1.000, 0.500, NOT_D15);
      $setuphold(posedge CLK &&& D_flag, posedge D[14], 1.000, 0.500, NOT_D14);
      $setuphold(posedge CLK &&& D_flag, negedge D[14], 1.000, 0.500, NOT_D14);
      $setuphold(posedge CLK &&& D_flag, posedge D[13], 1.000, 0.500, NOT_D13);
      $setuphold(posedge CLK &&& D_flag, negedge D[13], 1.000, 0.500, NOT_D13);
      $setuphold(posedge CLK &&& D_flag, posedge D[12], 1.000, 0.500, NOT_D12);
      $setuphold(posedge CLK &&& D_flag, negedge D[12], 1.000, 0.500, NOT_D12);
      $setuphold(posedge CLK &&& D_flag, posedge D[11], 1.000, 0.500, NOT_D11);
      $setuphold(posedge CLK &&& D_flag, negedge D[11], 1.000, 0.500, NOT_D11);
      $setuphold(posedge CLK &&& D_flag, posedge D[10], 1.000, 0.500, NOT_D10);
      $setuphold(posedge CLK &&& D_flag, negedge D[10], 1.000, 0.500, NOT_D10);
      $setuphold(posedge CLK &&& D_flag, posedge D[9], 1.000, 0.500, NOT_D9);
      $setuphold(posedge CLK &&& D_flag, negedge D[9], 1.000, 0.500, NOT_D9);
      $setuphold(posedge CLK &&& D_flag, posedge D[8], 1.000, 0.500, NOT_D8);
      $setuphold(posedge CLK &&& D_flag, negedge D[8], 1.000, 0.500, NOT_D8);
      $setuphold(posedge CLK &&& D_flag, posedge D[7], 1.000, 0.500, NOT_D7);
      $setuphold(posedge CLK &&& D_flag, negedge D[7], 1.000, 0.500, NOT_D7);
      $setuphold(posedge CLK &&& D_flag, posedge D[6], 1.000, 0.500, NOT_D6);
      $setuphold(posedge CLK &&& D_flag, negedge D[6], 1.000, 0.500, NOT_D6);
      $setuphold(posedge CLK &&& D_flag, posedge D[5], 1.000, 0.500, NOT_D5);
      $setuphold(posedge CLK &&& D_flag, negedge D[5], 1.000, 0.500, NOT_D5);
      $setuphold(posedge CLK &&& D_flag, posedge D[4], 1.000, 0.500, NOT_D4);
      $setuphold(posedge CLK &&& D_flag, negedge D[4], 1.000, 0.500, NOT_D4);
      $setuphold(posedge CLK &&& D_flag, posedge D[3], 1.000, 0.500, NOT_D3);
      $setuphold(posedge CLK &&& D_flag, negedge D[3], 1.000, 0.500, NOT_D3);
      $setuphold(posedge CLK &&& D_flag, posedge D[2], 1.000, 0.500, NOT_D2);
      $setuphold(posedge CLK &&& D_flag, negedge D[2], 1.000, 0.500, NOT_D2);
      $setuphold(posedge CLK &&& D_flag, posedge D[1], 1.000, 0.500, NOT_D1);
      $setuphold(posedge CLK &&& D_flag, negedge D[1], 1.000, 0.500, NOT_D1);
      $setuphold(posedge CLK &&& D_flag, posedge D[0], 1.000, 0.500, NOT_D0);
      $setuphold(posedge CLK &&& D_flag, negedge D[0], 1.000, 0.500, NOT_D0);
      $setuphold(posedge CLK &&& cyc_flag, posedge EMA[2], 1.000, 0.500, NOT_EMA2);
      $setuphold(posedge CLK &&& cyc_flag, negedge EMA[2], 1.000, 0.500, NOT_EMA2);
      $setuphold(posedge CLK &&& cyc_flag, posedge EMA[1], 1.000, 0.500, NOT_EMA1);
      $setuphold(posedge CLK &&& cyc_flag, negedge EMA[1], 1.000, 0.500, NOT_EMA1);
      $setuphold(posedge CLK &&& cyc_flag, posedge EMA[0], 1.000, 0.500, NOT_EMA0);
      $setuphold(posedge CLK &&& cyc_flag, negedge EMA[0], 1.000, 0.500, NOT_EMA0);
      $setuphold(posedge CLK, posedge RETN, 1.000, 0.500, NOT_RETN);
      $setuphold(posedge CLK, negedge RETN, 1.000, 0.500, NOT_RETN);
      $hold(posedge RETN, negedge CEN, 1.000, NOT_RETN);

      $width(posedge CLK &&& cyc_flag, 1.000, 0, NOT_CLK_MINH);
      $width(negedge CLK &&& cyc_flag, 1.000, 0, NOT_CLK_MINL);
`ifdef NO_SDTC
      $period(posedge CLK  &&& cyc_flag, 3.000, NOT_CLK_PER);
`else
      $period(posedge CLK &&& EMA2eq0andEMA1eq0andEMA0eq0, 3.000, NOT_CLK_PER);
      $period(posedge CLK &&& EMA2eq0andEMA1eq0andEMA0eq1, 3.000, NOT_CLK_PER);
      $period(posedge CLK &&& EMA2eq0andEMA1eq1andEMA0eq0, 3.000, NOT_CLK_PER);
      $period(posedge CLK &&& EMA2eq0andEMA1eq1andEMA0eq1, 3.000, NOT_CLK_PER);
      $period(posedge CLK &&& EMA2eq1andEMA1eq0andEMA0eq0, 3.000, NOT_CLK_PER);
      $period(posedge CLK &&& EMA2eq1andEMA1eq0andEMA0eq1, 3.000, NOT_CLK_PER);
      $period(posedge CLK &&& EMA2eq1andEMA1eq1andEMA0eq0, 3.000, NOT_CLK_PER);
      $period(posedge CLK &&& EMA2eq1andEMA1eq1andEMA0eq1, 3.000, NOT_CLK_PER);
`endif

      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[31]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[30]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[29]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[28]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[27]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[26]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[25]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[24]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[23]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[22]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[21]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[20]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[19]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[18]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[17]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[16]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[15]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[14]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[13]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[12]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[11]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[10]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[9]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[8]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[7]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[6]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[5]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[4]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[3]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[2]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[1]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b0) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b0) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b0))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);
      if ((EMA[2] == 1'b1) && (EMA[1] == 1'b1) && (EMA[0] == 1'b1))
        (posedge CLK => (Q[0]:1'b0))=(1.000, 1.000);

      (RETN => (Q[31] +: 1'b0)) = (1.000);
      (RETN => (Q[30] +: 1'b0)) = (1.000);
      (RETN => (Q[29] +: 1'b0)) = (1.000);
      (RETN => (Q[28] +: 1'b0)) = (1.000);
      (RETN => (Q[27] +: 1'b0)) = (1.000);
      (RETN => (Q[26] +: 1'b0)) = (1.000);
      (RETN => (Q[25] +: 1'b0)) = (1.000);
      (RETN => (Q[24] +: 1'b0)) = (1.000);
      (RETN => (Q[23] +: 1'b0)) = (1.000);
      (RETN => (Q[22] +: 1'b0)) = (1.000);
      (RETN => (Q[21] +: 1'b0)) = (1.000);
      (RETN => (Q[20] +: 1'b0)) = (1.000);
      (RETN => (Q[19] +: 1'b0)) = (1.000);
      (RETN => (Q[18] +: 1'b0)) = (1.000);
      (RETN => (Q[17] +: 1'b0)) = (1.000);
      (RETN => (Q[16] +: 1'b0)) = (1.000);
      (RETN => (Q[15] +: 1'b0)) = (1.000);
      (RETN => (Q[14] +: 1'b0)) = (1.000);
      (RETN => (Q[13] +: 1'b0)) = (1.000);
      (RETN => (Q[12] +: 1'b0)) = (1.000);
      (RETN => (Q[11] +: 1'b0)) = (1.000);
      (RETN => (Q[10] +: 1'b0)) = (1.000);
      (RETN => (Q[9] +: 1'b0)) = (1.000);
      (RETN => (Q[8] +: 1'b0)) = (1.000);
      (RETN => (Q[7] +: 1'b0)) = (1.000);
      (RETN => (Q[6] +: 1'b0)) = (1.000);
      (RETN => (Q[5] +: 1'b0)) = (1.000);
      (RETN => (Q[4] +: 1'b0)) = (1.000);
      (RETN => (Q[3] +: 1'b0)) = (1.000);
      (RETN => (Q[2] +: 1'b0)) = (1.000);
      (RETN => (Q[1] +: 1'b0)) = (1.000);
      (RETN => (Q[0] +: 1'b0)) = (1.000);
  endspecify

endmodule
`endcelldefine
`endif
