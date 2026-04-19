module FC #(
  parameter PIX_W        = 8,
  parameter KER_W        = 8,
  parameter K            = 288,
  parameter ACC_W        = 32,
  parameter OUT_CHANNELS = 10
)(
  input  wire clk,
  input  wire rst_n,

  // cfg handshake for eff_bias loading (OUT_CHANNELS-word packet)
  input  wire        cfg_valid,
  output wire        cfg_ready,
  input  wire [31:0] cfg_data,
  input  wire        cfg_last,
  output wire        param_load_done,

  // MAC data path (packed vectors, LSB = channel 0)
  input  wire                             mul_en,
  input  wire [OUT_CHANNELS*PIX_W-1:0]    pixel_vec,
  input  wire [OUT_CHANNELS*KER_W-1:0]    kernel_vec,
  output wire [OUT_CHANNELS*ACC_W-1:0]    acc_vec,
  output wire [OUT_CHANNELS-1:0]          mul_done_vec,
  output wire                             all_done
);

  // Bias loader -> MAC wires
  wire signed [31:0]              bias_in_w;
  wire [OUT_CHANNELS-1:0]         load_bias_vec;

  fc_bias_loader #(
    .OUT_CHANNELS(OUT_CHANNELS)
  ) u_bias_loader (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_valid(cfg_valid),
    .cfg_ready(cfg_ready),
    .cfg_data(cfg_data),
    .cfg_last(cfg_last),
    .param_load_done(param_load_done),
    .bias_in(bias_in_w),
    .load_bias_vec(load_bias_vec)
  );

  // Per-channel MAC array
  genvar gi;
  generate
    for (gi = 0; gi < OUT_CHANNELS; gi = gi + 1) begin : g_mac
      wire signed [PIX_W-1:0]  pix_i = pixel_vec [gi*PIX_W +: PIX_W];
      wire signed [KER_W-1:0]  ker_i = kernel_vec[gi*KER_W +: KER_W];
      wire signed [ACC_W-1:0]  acc_i;
      wire                     done_i;

      mac #(
        .PIX_W(PIX_W),
        .KER_W(KER_W),
        .K(K),
        .ACC_W(ACC_W)
      ) u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .mul_en(mul_en),
        .pixel(pix_i),
        .kernel(ker_i),
        .load_bias(load_bias_vec[gi]),
        .bias_in(bias_in_w[ACC_W-1:0]),
        .acc(acc_i),
        .mul_done(done_i)
      );

      assign acc_vec[gi*ACC_W +: ACC_W] = acc_i;
      assign mul_done_vec[gi]            = done_i;
    end
  endgenerate

  assign all_done = &mul_done_vec;

endmodule
