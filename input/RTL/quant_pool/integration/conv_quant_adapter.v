module conv_quant_adapter #(
  parameter integer ACC_W = 23,
  parameter integer COLS  = 4,
  parameter integer ROWS  = 16
)(
  input  wire clk,
  input  wire rst_n,

  // From Conv1_top
  input  wire signed [COLS*ACC_W-1:0] c_out_col_stream_flat,
  input  wire [COLS-1:0]              c_out_col_valid,
  input  wire [COLS-1:0]              c_out_col_last,
  input  wire                         sa_done,

  // To Quantization_Top
  output wire signed [ACC_W-1:0]      qp_rso0,
  output wire signed [ACC_W-1:0]      qp_rso1,
  output wire signed [ACC_W-1:0]      qp_rso2,
  output wire signed [ACC_W-1:0]      qp_rso3,
  output wire                         in_valid1,
  output wire                         in_valid2,
  output wire                         in_valid3,
  output wire                         in_valid4,
  output reg                          start1,
  output reg                          start2,
  output reg                          start3,
  output reg                          start4,
  // Deprecated: en1..4 are not consumed by any active-path module.
  // Retained only for legacy TB compatibility; do not rely on in new logic.
  output wire                         en1,
  output wire                         en2,
  output wire                         en3,
  output wire                         en4,

  // Quant parameter loading
  output wire signed [31:0]           bias_in,
  output wire signed [31:0]           M_in,
  output wire        [31:0]           sh_in,
  output wire                         load_bias1,
  output wire                         load_bias2,
  output wire                         load_bias3,
  output wire                         load_bias4,
  output wire                         load_M1,
  output wire                         load_M2,
  output wire                         load_M3,
  output wire                         load_M4,
  output wire                         load_sh,
  input  wire signed [31:0]           param_bias0,
  input  wire signed [31:0]           param_bias1,
  input  wire signed [31:0]           param_bias2,
  input  wire signed [31:0]           param_bias3,
  input  wire signed [31:0]           param_M0,
  input  wire signed [31:0]           param_M1,
  input  wire signed [31:0]           param_M2,
  input  wire signed [31:0]           param_M3,
  input  wire        [7:0]            param_sh0,
  input  wire        [7:0]            param_sh1,
  input  wire        [7:0]            param_sh2,
  input  wire        [7:0]            param_sh3,
  input  wire                         param_load_start,
  output wire                         param_load_done
);

  // Reserved for future boundary cleanup when c_out_col_last / sa_done become
  // part of the explicit Conv->Quant transaction contract.
  wire unused_last  = ^c_out_col_last;
  wire unused_done  = sa_done;
  wire _unused_ok   = unused_last ^ unused_done;

  wire signed [ACC_W-1:0] col0 = c_out_col_stream_flat[0*ACC_W +: ACC_W];
  wire signed [ACC_W-1:0] col1 = c_out_col_stream_flat[1*ACC_W +: ACC_W];
  wire signed [ACC_W-1:0] col2 = c_out_col_stream_flat[2*ACC_W +: ACC_W];
  wire signed [ACC_W-1:0] col3 = c_out_col_stream_flat[3*ACC_W +: ACC_W];

  reg signed [ACC_W-1:0] qp_rso0_r;
  reg signed [ACC_W-1:0] qp_rso1_r;
  reg signed [ACC_W-1:0] qp_rso2_r;
  reg signed [ACC_W-1:0] qp_rso3_r;
  reg [COLS-1:0] col_valid_d1;
  reg [COLS-1:0] col_valid_d2;

  reg        cfg_compat_active;
  reg [3:0]  cfg_compat_idx;
  wire       cfg_valid_i;
  wire       cfg_ready_i;
  wire [31:0] cfg_data_i;
  wire       cfg_last_i;

  reg [3:0] en1_sr, en2_sr, en3_sr, en4_sr;
  reg       en1_raw, en2_raw, en3_raw, en4_raw;

  assign qp_rso0   = qp_rso0_r;
  assign qp_rso1   = qp_rso1_r;
  assign qp_rso2   = qp_rso2_r;
  assign qp_rso3   = qp_rso3_r;
  assign in_valid1 = col_valid_d1[0];
  assign in_valid2 = col_valid_d1[1];
  assign in_valid3 = col_valid_d1[2];
  assign in_valid4 = col_valid_d1[3];
  assign en1       = en1_raw;
  assign en2       = en2_raw;
  assign en3       = en3_raw;
  assign en4       = en4_raw;

  assign cfg_valid_i = cfg_compat_active;
  assign cfg_last_i  = (cfg_compat_idx == 4'd8);
  assign cfg_data_i  =
      (cfg_compat_idx == 4'd0) ? param_bias0 :
      (cfg_compat_idx == 4'd1) ? param_bias1 :
      (cfg_compat_idx == 4'd2) ? param_bias2 :
      (cfg_compat_idx == 4'd3) ? param_bias3 :
      (cfg_compat_idx == 4'd4) ? param_M0    :
      (cfg_compat_idx == 4'd5) ? param_M1    :
      (cfg_compat_idx == 4'd6) ? param_M2    :
      (cfg_compat_idx == 4'd7) ? param_M3    :
                                 {param_sh0, param_sh1, param_sh2, param_sh3};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      qp_rso0_r    <= {ACC_W{1'b0}};
      qp_rso1_r    <= {ACC_W{1'b0}};
      qp_rso2_r    <= {ACC_W{1'b0}};
      qp_rso3_r    <= {ACC_W{1'b0}};
      col_valid_d1 <= {COLS{1'b0}};
      col_valid_d2 <= {COLS{1'b0}};
      start1       <= 1'b0;
      start2       <= 1'b0;
      start3       <= 1'b0;
      start4       <= 1'b0;
      en1_sr       <= 4'b0;
      en2_sr       <= 4'b0;
      en3_sr       <= 4'b0;
      en4_sr       <= 4'b0;
      en1_raw      <= 1'b0;
      en2_raw      <= 1'b0;
      en3_raw      <= 1'b0;
      en4_raw      <= 1'b0;
      cfg_compat_active <= 1'b0;
      cfg_compat_idx    <= 4'd0;
    end else begin
      qp_rso0_r <= col0;
      qp_rso1_r <= col1;
      qp_rso2_r <= col2;
      qp_rso3_r <= col3;

      col_valid_d1 <= c_out_col_valid;
      col_valid_d2 <= col_valid_d1;
      start1 <= col_valid_d1[0] | col_valid_d2[0];
      start2 <= col_valid_d1[1] | col_valid_d2[1];
      start3 <= col_valid_d1[2] | col_valid_d2[2];
      start4 <= col_valid_d1[3] | col_valid_d2[3];

      en1_sr  <= {en1_sr[2:0], col_valid_d1[0]};
      en2_sr  <= {en2_sr[2:0], col_valid_d1[1]};
      en3_sr  <= {en3_sr[2:0], col_valid_d1[2]};
      en4_sr  <= {en4_sr[2:0], col_valid_d1[3]};
      en1_raw <= en1_sr[3];
      en2_raw <= en2_sr[3];
      en3_raw <= en3_sr[3];
      en4_raw <= en4_sr[3];

      if (!cfg_compat_active) begin
        if (param_load_start) begin
          cfg_compat_active <= 1'b1;
          cfg_compat_idx    <= 4'd0;
        end
      end else if (cfg_valid_i && cfg_ready_i) begin
        if (cfg_compat_idx == 4'd8) begin
          cfg_compat_active <= 1'b0;
          cfg_compat_idx    <= 4'd0;
        end else begin
          cfg_compat_idx <= cfg_compat_idx + 4'd1;
        end
      end
    end
  end

  quant_param_loader u_quant_param_loader (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_valid(cfg_valid_i),
    .cfg_ready(cfg_ready_i),
    .cfg_data(cfg_data_i),
    .cfg_last(cfg_last_i),
    .param_load_done(param_load_done),
    .bias_in(bias_in),
    .M_in(M_in),
    .sh_in(sh_in),
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

endmodule
