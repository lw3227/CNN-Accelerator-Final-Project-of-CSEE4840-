module quant_pool_adapter #(
  parameter integer OUT_W      = 62,
  parameter integer POOL_DEPTH = 31
)(
  input  wire              clk,
  input  wire              rst_n,
  input  wire signed [7:0] cut1_in,
  input  wire signed [7:0] cut2_in,
  input  wire signed [7:0] cut3_in,
  input  wire signed [7:0] cut4_in,
  input  wire              cut_valid1,
  input  wire              cut_valid2,
  input  wire              cut_valid3,
  input  wire              cut_valid4,
  output wire signed [7:0] cut1_out,
  output wire signed [7:0] cut2_out,
  output wire signed [7:0] cut3_out,
  output wire signed [7:0] cut4_out,
  output wire              cut_valid1_out,
  output wire              cut_valid2_out,
  output wire              cut_valid3_out,
  output wire              cut_valid4_out
);

  // Reserved for future continuity smoothing or skid buffering if a later
  // streaming pool revision adds input backpressure. The active stream-top
  // path currently accepts continuous lane traffic directly.
  wire unused_clk = clk;
  wire unused_rst = rst_n;
  wire _unused_ok = unused_clk ^ unused_rst;

  assign cut1_out       = cut1_in;
  assign cut2_out       = cut2_in;
  assign cut3_out       = cut3_in;
  assign cut4_out       = cut4_in;
  assign cut_valid1_out = cut_valid1;
  assign cut_valid2_out = cut_valid2;
  assign cut_valid3_out = cut_valid3;
  assign cut_valid4_out = cut_valid4;

endmodule
