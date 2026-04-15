module conv_quant_pool #(
  parameter integer W          = 64,
  parameter integer DATA_W     = 8,
  parameter integer ROWS       = 16,
  parameter integer COLS       = 4,
  parameter integer DOT_K      = 72,   // max (L3: 9*8)
  parameter integer ACC_W      = 23,
  parameter integer IMG_H      = 64,
  parameter integer IMG_W      = 64,
  parameter integer C_IN       = 8,    // max (L3)
  parameter integer OUT_H      = IMG_H - 2,
  parameter integer OUT_W      = IMG_W - 2,
  parameter integer POOL_DEPTH = 31    // max (L1)
)(
  input  wire [1:0]                layer_sel,
  input  wire                      clk,
  input  wire                      rst_n,
  input  wire                      in_valid,
  input  wire        [31:0]        in_data,
  input  wire        [3:0]         in_byte_en,
  input  wire                      in_last,
  output wire                      in_ready,
  input  wire                      wt_valid,
  output wire                      wt_ready,
  input  wire                      wt_last,
  input  wire signed [COLS*DATA_W-1:0] wt_data,
  input  wire                      cfg_valid,
  output wire                      cfg_ready,
  input  wire [31:0]               cfg_data,
  input  wire                      cfg_last,
  input  wire                      pool_ready,
  output wire signed [31:0]        pool_data,
  output wire                      pool_valid,
  output wire                      pool_last,
  // Control observation signals for FSM integration
  output wire                      cfg_load_done,
  output wire                      wt_load_done,
  output wire                      pool_frame_done,
  output wire                      conv_frame_rearm_out
);

  wire                         sa_done;
  wire signed [COLS*ACC_W-1:0] c_out_col_stream_flat;
  wire [COLS-1:0]              c_out_col_valid;
  wire [COLS-1:0]              c_out_col_last;
  wire                         conv_frame_rearm;
  wire                         conv_frame_done;

  wire signed [ACC_W-1:0]      qp_rso0;
  wire signed [ACC_W-1:0]      qp_rso1;
  wire signed [ACC_W-1:0]      qp_rso2;
  wire signed [ACC_W-1:0]      qp_rso3;
  wire                         in_valid1;
  wire                         in_valid2;
  wire                         in_valid3;
  wire                         in_valid4;
  wire                         start1;
  wire                         start2;
  wire                         start3;
  wire                         start4;

  wire signed [31:0]           bias_in_w;
  wire signed [31:0]           M_in_w;
  wire [31:0]                  sh_in_w;
  wire                         load_bias1;
  wire                         load_bias2;
  wire                         load_bias3;
  wire                         load_bias4;
  wire                         load_M1;
  wire                         load_M2;
  wire                         load_M3;
  wire                         load_M4;
  wire                         load_sh;

  wire signed [7:0]            cut1;
  wire signed [7:0]            cut2;
  wire signed [7:0]            cut3;
  wire signed [7:0]            cut4;
  wire                         cut_valid1;
  wire                         cut_valid2;
  wire                         cut_valid3;
  wire                         cut_valid4;

  wire signed [7:0]            cut1_out;
  wire signed [7:0]            cut2_out;
  wire signed [7:0]            cut3_out;
  wire signed [7:0]            cut4_out;
  wire                         cut_valid1_out;
  wire                         cut_valid2_out;
  wire                         cut_valid3_out;
  wire                         cut_valid4_out;

  conv_top #(
    .W(W),
    .DATA_W(DATA_W),
    .ROWS(ROWS),
    .COLS(COLS),
    .DOT_K(DOT_K),
    .ACC_W(ACC_W),
    .IMG_H(IMG_H),
    .IMG_W(IMG_W),
    .C_IN(C_IN)
  ) u_conv1 (
    .layer_sel(layer_sel),
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .in_data(in_data),
    .in_byte_en(in_byte_en),
    .in_last(in_last),
    .in_ready(in_ready),
    .wt_valid(wt_valid),
    .wt_ready(wt_ready),
    .wt_last(wt_last),
    .wt_data(wt_data),
    .wt_load_done(wt_load_done),
    .sa_done(sa_done),
    .c_out_col_stream_flat(c_out_col_stream_flat),
    .c_out_col_valid(c_out_col_valid),
    .c_out_col_last(c_out_col_last),
    .frame_rearm_out(conv_frame_rearm),
    .frame_done_out(conv_frame_done)
  );

  conv_quant_adapter #(
    .ACC_W(ACC_W),
    .COLS(COLS),
    .ROWS(ROWS)
  ) u_conv_quant_adapter (
    .clk(clk),
    .rst_n(rst_n),
    .c_out_col_stream_flat(c_out_col_stream_flat),
    .c_out_col_valid(c_out_col_valid),
    .c_out_col_last(c_out_col_last),
    .sa_done(sa_done),
    .qp_rso0(qp_rso0),
    .qp_rso1(qp_rso1),
    .qp_rso2(qp_rso2),
    .qp_rso3(qp_rso3),
    .in_valid1(in_valid1),
    .in_valid2(in_valid2),
    .in_valid3(in_valid3),
    .in_valid4(in_valid4),
    .start1(start1),
    .start2(start2),
    .start3(start3),
    .start4(start4),
    .en1(),
    .en2(),
    .en3(),
    .en4(),
    .bias_in(),
    .M_in(),
    .sh_in(),
    .load_bias1(),
    .load_bias2(),
    .load_bias3(),
    .load_bias4(),
    .load_M1(),
    .load_M2(),
    .load_M3(),
    .load_M4(),
    .load_sh(),
    .param_bias0(32'sd0),
    .param_bias1(32'sd0),
    .param_bias2(32'sd0),
    .param_bias3(32'sd0),
    .param_M0(32'sd0),
    .param_M1(32'sd0),
    .param_M2(32'sd0),
    .param_M3(32'sd0),
    .param_sh0(8'd0),
    .param_sh1(8'd0),
    .param_sh2(8'd0),
    .param_sh3(8'd0),
    .param_load_start(1'b0),
    .param_load_done()
  );

  quant_param_loader u_quant_param_loader (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_valid(cfg_valid),
    .cfg_ready(cfg_ready),
    .cfg_data(cfg_data),
    .cfg_last(cfg_last),
    .param_load_done(cfg_load_done),
    .bias_in(bias_in_w),
    .M_in(M_in_w),
    .sh_in(sh_in_w),
    .load_bias1(load_bias1),
    .load_bias2(load_bias2),
    .load_bias3(load_bias3),
    .load_bias4(load_bias4),
    .load_M1(load_M1),
    .load_M2(load_M2),
    .load_M3(load_M3),
    .load_M4(load_M4),
    .load_sh(load_sh)
  );

  Quantization_Top u_quant (
    .clk(clk),
    .rst_n(rst_n),
    .start1(start1),
    .start2(start2),
    .start3(start3),
    .start4(start4),
    .in_valid1(in_valid1),
    .in_valid2(in_valid2),
    .in_valid3(in_valid3),
    .in_valid4(in_valid4),
    .load_bias1(load_bias1),
    .load_bias2(load_bias2),
    .load_bias3(load_bias3),
    .load_bias4(load_bias4),
    .load_M1(load_M1),
    .load_M2(load_M2),
    .load_M3(load_M3),
    .load_M4(load_M4),
    .load_sh(load_sh),
    .bias_in(bias_in_w),
    .M_in(M_in_w),
    .sh_in(sh_in_w),
    .rso0(qp_rso0),
    .rso1(qp_rso1),
    .rso2(qp_rso2),
    .rso3(qp_rso3),
    .cut1(cut1),
    .cut2(cut2),
    .cut3(cut3),
    .cut4(cut4),
    .cut_valid1(cut_valid1),
    .cut_valid2(cut_valid2),
    .cut_valid3(cut_valid3),
    .cut_valid4(cut_valid4)
  );

  quant_pool_adapter u_quant_pool_adapter (
    .clk(clk),
    .rst_n(rst_n),
    .cut1_in(cut1),
    .cut2_in(cut2),
    .cut3_in(cut3),
    .cut4_in(cut4),
    .cut_valid1(cut_valid1),
    .cut_valid2(cut_valid2),
    .cut_valid3(cut_valid3),
    .cut_valid4(cut_valid4),
    .cut1_out(cut1_out),
    .cut2_out(cut2_out),
    .cut3_out(cut3_out),
    .cut4_out(cut4_out),
    .cut_valid1_out(cut_valid1_out),
    .cut_valid2_out(cut_valid2_out),
    .cut_valid3_out(cut_valid3_out),
    .cut_valid4_out(cut_valid4_out)
  );

  pool_stream_top #(
    .POOL_DEPTH(POOL_DEPTH)
  ) u_pool (
    .layer_sel(layer_sel),
    .clk(clk),
    .rst_n(rst_n),
    .cut1(cut1_out),
    .cut2(cut2_out),
    .cut3(cut3_out),
    .cut4(cut4_out),
    .cut_valid1(cut_valid1_out),
    .cut_valid2(cut_valid2_out),
    .cut_valid3(cut_valid3_out),
    .cut_valid4(cut_valid4_out),
    .frame_rearm(conv_frame_rearm),
    .pool_ready(pool_ready),
    .pool_data(pool_data),
    .pool_valid(pool_valid),
    .pool_last(pool_last),
    .pool_frame_done(pool_frame_done)
  );

  assign conv_frame_rearm_out = conv_frame_rearm;

endmodule
