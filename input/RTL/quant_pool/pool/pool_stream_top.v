module pool_stream_top #(
  parameter integer POOL_DEPTH = 31
)(
  input  wire        [1:0]  layer_sel,
  input  wire               clk,
  input  wire               rst_n,
  input  wire signed [7:0]  cut1,
  input  wire signed [7:0]  cut2,
  input  wire signed [7:0]  cut3,
  input  wire signed [7:0]  cut4,
  input  wire               cut_valid1,
  input  wire               cut_valid2,
  input  wire               cut_valid3,
  input  wire               cut_valid4,
  input  wire               frame_rearm,
  input  wire               pool_ready,
  output wire signed [31:0] pool_data,
  output wire               pool_valid,
  output wire               pool_last,
  output wire               pool_frame_done
);

  pool_core #(
    .POOL_DEPTH(POOL_DEPTH)
  ) u_pool_core (
    .layer_sel(layer_sel),
    .clk(clk),
    .rst_n(rst_n),
    .cut1(cut1),
    .cut2(cut2),
    .cut3(cut3),
    .cut4(cut4),
    .en1(cut_valid1),
    .en2(cut_valid2),
    .en3(cut_valid3),
    .en4(cut_valid4),
    .frame_rearm(frame_rearm),
    .pool_ready(pool_ready),
    .pool_data(pool_data),
    .pool_valid(pool_valid),
    .pool_last(pool_last),
    .pool_frame_done(pool_frame_done)
  );

endmodule
