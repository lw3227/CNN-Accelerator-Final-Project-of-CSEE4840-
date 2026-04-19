module quant_param_loader(
  input  wire               clk,
  input  wire               rst_n,

  // Handshake config stream: fixed 9-word packet
  //   0..3: bias0..3
  //   4..7: M0..3
  //   8   : {sh0, sh1, sh2, sh3}
  input  wire               cfg_valid,
  output wire               cfg_ready,
  input  wire [31:0]        cfg_data,
  input  wire               cfg_last,

  output wire               param_load_done,
  output reg signed [31:0]  bias_in,
  output reg signed [31:0]  M_in,
  output reg        [31:0]  sh_in,
  output reg                load_bias1,
  output reg                load_bias2,
  output reg                load_bias3,
  output reg                load_bias4,
  output reg                load_M1,
  output reg                load_M2,
  output reg                load_M3,
  output reg                load_M4,
  output reg                load_sh
);

  localparam integer CFG_WORDS = 9;

  localparam [3:0] PL_IDLE  = 4'd0,
                   PL_BIAS0 = 4'd1,
                   PL_BIAS1 = 4'd2,
                   PL_BIAS2 = 4'd3,
                   PL_BIAS3 = 4'd4,
                   PL_M0    = 4'd5,
                   PL_M1    = 4'd6,
                   PL_M2    = 4'd7,
                   PL_M3    = 4'd8,
                   PL_SH    = 4'd9;

  reg signed [31:0] bias_reg0, bias_reg1, bias_reg2, bias_reg3;
  reg signed [31:0] M_reg0,    M_reg1,    M_reg2,    M_reg3;
  reg        [31:0] sh_reg;

  reg [3:0] rx_idx;
  reg [3:0] pl_state;
  reg       preload_active;
  reg       load_done_r;

  wire cfg_fire = cfg_valid && cfg_ready;

  assign cfg_ready = !preload_active && (rx_idx < CFG_WORDS);
  assign param_load_done = load_done_r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bias_reg0 <= 32'sd0;
      bias_reg1 <= 32'sd0;
      bias_reg2 <= 32'sd0;
      bias_reg3 <= 32'sd0;
      M_reg0    <= 32'sd0;
      M_reg1    <= 32'sd0;
      M_reg2    <= 32'sd0;
      M_reg3    <= 32'sd0;
      sh_reg    <= 32'd0;
      bias_in   <= 32'sd0;
      M_in      <= 32'sd0;
      sh_in     <= 32'd0;
      load_bias1 <= 1'b0;
      load_bias2 <= 1'b0;
      load_bias3 <= 1'b0;
      load_bias4 <= 1'b0;
      load_M1    <= 1'b0;
      load_M2    <= 1'b0;
      load_M3    <= 1'b0;
      load_M4    <= 1'b0;
      load_sh    <= 1'b0;
      rx_idx        <= 4'd0;
      pl_state      <= PL_IDLE;
      preload_active <= 1'b0;
      load_done_r   <= 1'b0;
    end else begin
      load_bias1 <= 1'b0;
      load_bias2 <= 1'b0;
      load_bias3 <= 1'b0;
      load_bias4 <= 1'b0;
      load_M1    <= 1'b0;
      load_M2    <= 1'b0;
      load_M3    <= 1'b0;
      load_M4    <= 1'b0;
      load_sh    <= 1'b0;

      if (cfg_fire) begin
        load_done_r <= 1'b0;
        case (rx_idx)
          4'd0: bias_reg0 <= $signed(cfg_data);
          4'd1: bias_reg1 <= $signed(cfg_data);
          4'd2: bias_reg2 <= $signed(cfg_data);
          4'd3: bias_reg3 <= $signed(cfg_data);
          4'd4: M_reg0    <= $signed(cfg_data);
          4'd5: M_reg1    <= $signed(cfg_data);
          4'd6: M_reg2    <= $signed(cfg_data);
          4'd7: M_reg3    <= $signed(cfg_data);
          4'd8: sh_reg    <= cfg_data;
          default: ;
        endcase

        if (rx_idx == CFG_WORDS - 1) begin
          rx_idx         <= 4'd0;
          preload_active <= 1'b1;
          pl_state       <= PL_BIAS0;
        end else begin
          rx_idx <= rx_idx + 4'd1;
        end
      end

      if (preload_active) begin
        case (pl_state)
          PL_BIAS0: begin
            bias_in    <= bias_reg0;
            load_bias1 <= 1'b1;
            pl_state   <= PL_BIAS1;
          end
          PL_BIAS1: begin
            bias_in    <= bias_reg1;
            load_bias2 <= 1'b1;
            pl_state   <= PL_BIAS2;
          end
          PL_BIAS2: begin
            bias_in    <= bias_reg2;
            load_bias3 <= 1'b1;
            pl_state   <= PL_BIAS3;
          end
          PL_BIAS3: begin
            bias_in    <= bias_reg3;
            load_bias4 <= 1'b1;
            pl_state   <= PL_M0;
          end
          PL_M0: begin
            M_in      <= M_reg0;
            load_M1   <= 1'b1;
            pl_state  <= PL_M1;
          end
          PL_M1: begin
            M_in      <= M_reg1;
            load_M2   <= 1'b1;
            pl_state  <= PL_M2;
          end
          PL_M2: begin
            M_in      <= M_reg2;
            load_M3   <= 1'b1;
            pl_state  <= PL_M3;
          end
          PL_M3: begin
            M_in      <= M_reg3;
            load_M4   <= 1'b1;
            pl_state  <= PL_SH;
          end
          PL_SH: begin
            sh_in          <= sh_reg;
            load_sh        <= 1'b1;
            pl_state       <= PL_IDLE;
            preload_active <= 1'b0;
            load_done_r    <= 1'b1;
          end
          default: begin
            pl_state       <= PL_IDLE;
            preload_active <= 1'b0;
          end
        endcase
      end

      // Keep cfg_last in the interface contract even though the current
      // fixed 9-word packet format is ordered by index.
      if (cfg_fire && cfg_last && rx_idx != CFG_WORDS - 1) begin
        rx_idx      <= 4'd0;
        load_done_r <= 1'b0;
      end
    end
  end

endmodule
