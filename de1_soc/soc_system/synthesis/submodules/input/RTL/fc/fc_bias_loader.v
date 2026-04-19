module fc_bias_loader #(
  parameter OUT_CHANNELS = 10
)(
  input  wire        clk,
  input  wire        rst_n,

  // 4-wire cfg handshake: OUT_CHANNELS-word packet, one bias per word.
  input  wire        cfg_valid,
  output wire        cfg_ready,
  input  wire [31:0] cfg_data,
  input  wire        cfg_last,

  output wire                        param_load_done,
  output reg  signed [31:0]          bias_in,
  output reg  [OUT_CHANNELS-1:0]     load_bias_vec
);

  localparam integer CFG_WORDS = OUT_CHANNELS;
  localparam integer IDX_W     = (OUT_CHANNELS <= 1) ? 1 : $clog2(OUT_CHANNELS);

  localparam [1:0] PL_IDLE       = 2'd0,
                   PL_DISTRIBUTE = 2'd1;

  reg signed [31:0]       bias_reg [0:OUT_CHANNELS-1];
  reg [IDX_W:0]           rx_idx;    // one extra bit to compare against CFG_WORDS
  reg [IDX_W:0]           pl_idx;
  reg [1:0]               pl_state;
  reg                     preload_active;
  reg                     load_done_r;

  wire cfg_fire = cfg_valid && cfg_ready;

  assign cfg_ready       = !preload_active && (rx_idx < CFG_WORDS);
  assign param_load_done = load_done_r;

  always @(posedge clk or negedge rst_n) begin : bias_fsm
    integer i;
    if (!rst_n) begin
      for (i = 0; i < OUT_CHANNELS; i = i + 1)
        bias_reg[i] <= 32'sd0;
      bias_in        <= 32'sd0;
      load_bias_vec  <= {OUT_CHANNELS{1'b0}};
      rx_idx         <= {(IDX_W+1){1'b0}};
      pl_idx         <= {(IDX_W+1){1'b0}};
      pl_state       <= PL_IDLE;
      preload_active <= 1'b0;
      load_done_r    <= 1'b0;
    end else begin
      // Default: clear one-hot pulse
      load_bias_vec <= {OUT_CHANNELS{1'b0}};

      // ---- RX phase: accept OUT_CHANNELS cfg words ----
      if (cfg_fire) begin
        load_done_r <= 1'b0;
        bias_reg[rx_idx[IDX_W-1:0]] <= $signed(cfg_data);

        if (rx_idx == CFG_WORDS - 1) begin
          rx_idx         <= {(IDX_W+1){1'b0}};
          preload_active <= 1'b1;
          pl_state       <= PL_DISTRIBUTE;
          pl_idx         <= {(IDX_W+1){1'b0}};
        end else begin
          rx_idx <= rx_idx + 1'b1;
        end
      end

      // ---- Preload phase: one channel per cycle ----
      if (preload_active && pl_state == PL_DISTRIBUTE) begin
        bias_in                      <= bias_reg[pl_idx[IDX_W-1:0]];
        load_bias_vec[pl_idx[IDX_W-1:0]] <= 1'b1;

        if (pl_idx == OUT_CHANNELS - 1) begin
          pl_state       <= PL_IDLE;
          preload_active <= 1'b0;
          load_done_r    <= 1'b1;
          pl_idx         <= {(IDX_W+1){1'b0}};
        end else begin
          pl_idx <= pl_idx + 1'b1;
        end
      end

      // Early cfg_last resets RX if packet is short
      if (cfg_fire && cfg_last && rx_idx != CFG_WORDS - 1) begin
        rx_idx      <= {(IDX_W+1){1'b0}};
        load_done_r <= 1'b0;
      end
    end
  end

endmodule
