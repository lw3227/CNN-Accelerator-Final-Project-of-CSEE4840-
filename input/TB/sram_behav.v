// Behavioral SRAM macro models for simulation.
// These replace the ARM technology macros (sram_A / sram_B) so that
// the full system_top hierarchy can be simulated without foundry models.

`timescale 1ns / 1ps

module sram_A (
  input         CLK,
  input         CEN,   // chip enable, active low
  input         WEN,   // write enable, active low (CEN=0, WEN=0 → write)
  input  [9:0]  A,     // 10-bit address (4KB = 1024 words)
  input  [31:0] D,
  input  [2:0]  EMA,
  input         RETN,
  output reg [31:0] Q
);
  reg [31:0] mem [0:1023];

  always @(posedge CLK) begin
    if (!CEN) begin
      if (!WEN)
        mem[A] <= D;
      else
        Q <= mem[A];
    end
  end
endmodule

module sram_B (
  input         CLK,
  input         CEN,
  input         WEN,
  input  [9:0]  A,
  input  [31:0] D,
  input  [2:0]  EMA,
  input         RETN,
  output reg [31:0] Q
);
  reg [31:0] mem [0:1023];

  always @(posedge CLK) begin
    if (!CEN) begin
      if (!WEN)
        mem[A] <= D;
      else
        Q <= mem[A];
    end
  end
endmodule
