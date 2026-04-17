

module ring_shift_reg #(
  parameter Length  = 75,   // max channel depth (DOT_K_MAX + 3)
  parameter DATA_W  = 8,
  parameter VALID_LEN = 72, // max valid window (DOT_K_MAX)
  parameter PERIOD    = 75  // max period (= Length)
) (
  input wire [1:0] layer_sel,
  input wire clk,
  input wire rst_n,
  input wire wr_en,
  input wire signed [DATA_W-1:0] in_data,
  input wire ring,
  input wire out_ready,
  output wire signed [DATA_W-1:0] out_data,
  output wire out_valid
);

reg signed [DATA_W-1:0] sr [Length-1:0];
reg signed [DATA_W-1:0] saved_sr [Length-1:0];

// Runtime decode: effective length, valid_len, period per channel
// These are set by the parent weight_buffer based on which channel instance this is.
// However, since ring_shift_reg is generic, we decode from layer_sel + compile-time
// Length offset. The key relationship:
//   eff_len = eff_dot_k + (Length - VALID_LEN)  -- channel offset preserved
//   eff_valid = eff_dot_k
//   eff_period = eff_dot_k + 3  -- always equal to max channel length
reg [6:0] eff_dot_k;
reg [6:0] eff_len;
reg [6:0] eff_valid;
reg [6:0] eff_period;

localparam integer CH_OFFSET = Length - VALID_LEN;  // 0, 1, 2, or 3
localparam [6:0] LENGTH_U7 = Length;

always @* begin
  case (layer_sel)
    2'b01:   eff_dot_k = 7'd36;
    2'b10:   eff_dot_k = 7'd72;
    default: eff_dot_k = 7'd9;
  endcase
  eff_valid  = eff_dot_k;
  eff_len    = eff_dot_k + CH_OFFSET[6:0];
  eff_period = eff_dot_k + 7'd3;
end

reg [$clog2(PERIOD)-1:0] phase;
reg [$clog2(PERIOD+1)-1:0] burst_cnt;
reg burst_active;
reg ring_d;

localparam integer ALIGN_MAX = Length - VALID_LEN;
wire [6:0] eff_align = eff_len - eff_valid;
wire [6:0] feedback_idx = eff_len - 7'd1;
wire feedback_idx_valid = (eff_len != 7'd0) && (eff_len <= LENGTH_U7);
wire in_valid_window = (phase >= eff_align) && (phase < eff_align + eff_valid);
wire ring_rise = ring && !ring_d;
wire step_en = burst_active && (!in_valid_window || out_ready);

// Runtime MUX: read from the effective end of the ring, not the physical end.
// When DOT_K < Length (e.g. L1: eff_len=9, Length=72), the data lives in
// sr[0..eff_len-1] and never reaches sr[Length-1] within the burst period.
reg signed [DATA_W-1:0] out_tap;
integer oi;
always @* begin
  out_tap = 0;
  for (oi = 0; oi < Length; oi = oi + 1)
    if (oi[6:0] == eff_len - 7'd1)
      out_tap = sr[oi];
end
assign out_data = (burst_active && in_valid_window) ? out_tap : 0;
assign out_valid = burst_active && in_valid_window;

integer i;
always@(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
    for(i=0;i<Length;i=i+1) begin
      sr[i] <= 0;
      saved_sr[i] <= 0;
    end
    phase <= 0;
    burst_cnt <= 0;
    burst_active <= 1'b0;
    ring_d <= 1'b0;
  end
  else begin
    ring_d <= ring;
    if(ring_rise) begin
      for (i=0; i<Length; i=i+1) saved_sr[i] <= sr[i];
      burst_active <= 1'b1;
      burst_cnt <= 0;
      phase <= 0;
    end
    else if(burst_active && step_en) begin
      if(burst_cnt == eff_period) begin
        for (i=0; i<Length; i=i+1) sr[i] <= saved_sr[i];
        phase <= 0;
        burst_cnt <= 0;
        burst_active <= 1'b0;
      end else begin
        // Runtime-select the feedback tap so smaller Length instances
        // never statically reference out-of-range sr[] entries.
        if (feedback_idx_valid) sr[0] <= sr[feedback_idx];
        else                    sr[0] <= 0;
        for (i=1; i<Length; i=i+1) sr[i] <= sr[i-1];
        phase <= phase + 1'b1;
        burst_cnt <= burst_cnt + 1'b1;
      end
    end
    else if(wr_en) begin
      sr[0] <= in_data;
      for (i=1; i<Length; i=i+1) sr[i] <= sr[i-1];
      phase <= 0;
      burst_cnt <= 0;
    end
  end
end
endmodule


module weight_buffer #(
  parameter integer DATA_W = 32,
  parameter integer COLS = 4,
  parameter integer L0 = 72, L1 = 73, L2 = 74, L3 = 75  // max depths
) (
  input wire [1:0] layer_sel,
  input wire clk,
  input wire rst_n,
  input wire ring,
  input wire wr_en,
  input wire signed [DATA_W-1:0] in_data,
  input wire out_ready,

  output wire signed [DATA_W/COLS-1:0] out0, out1, out2, out3,
  output wire [COLS-1:0] out_valid
);

  localparam integer CH_W = DATA_W/COLS;
  wire signed [CH_W-1:0] in0, in1, in2, in3;
  assign in0 = in_data[0*CH_W +: CH_W];
  assign in1 = in_data[1*CH_W +: CH_W];
  assign in2 = in_data[2*CH_W +: CH_W];
  assign in3 = in_data[3*CH_W +: CH_W];

  ring_shift_reg #(.Length(L0), .DATA_W(CH_W), .VALID_LEN(L0), .PERIOD(L3))
    u0_ring_shift_reg (
      .layer_sel(layer_sel), .clk(clk), .rst_n(rst_n),
      .wr_en(wr_en), .in_data(in0), .ring(ring), .out_ready(out_ready),
      .out_data(out0), .out_valid(out_valid[0])
    );

  ring_shift_reg #(.Length(L1), .DATA_W(CH_W), .VALID_LEN(L0), .PERIOD(L3))
    u1_ring_shift_reg (
      .layer_sel(layer_sel), .clk(clk), .rst_n(rst_n),
      .wr_en(wr_en), .in_data(in1), .ring(ring), .out_ready(out_ready),
      .out_data(out1), .out_valid(out_valid[1])
    );

  ring_shift_reg #(.Length(L2), .DATA_W(CH_W), .VALID_LEN(L0), .PERIOD(L3))
    u2_ring_shift_reg (
      .layer_sel(layer_sel), .clk(clk), .rst_n(rst_n),
      .wr_en(wr_en), .in_data(in2), .ring(ring), .out_ready(out_ready),
      .out_data(out2), .out_valid(out_valid[2])
    );

  ring_shift_reg #(.Length(L3), .DATA_W(CH_W), .VALID_LEN(L0), .PERIOD(L3))
    u3_ring_shift_reg (
      .layer_sel(layer_sel), .clk(clk), .rst_n(rst_n),
      .wr_en(wr_en), .in_data(in3), .ring(ring), .out_ready(out_ready),
      .out_data(out3), .out_valid(out_valid[3])
    );

endmodule
