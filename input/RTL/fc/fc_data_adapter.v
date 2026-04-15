// FC Data Adapter: synchronize SRAM_FCW weight stream and SRAM_B pixel stream
// into FC pixel_vec/kernel_vec + mul_en.
//
// SRAM_FCW (weight): 288 words x 80b, one word per MAC cycle.
//   Packing (LSB = channel 0): {k9, k8, k7, k6, k5, k4, k3, k2, k1, k0}
// SRAM_B (data):    72 words x 32b, one word per 4 MAC cycles (byte-serial).
//
// The same pixel byte is broadcast to all OUT_CHANNELS MACs in the same cycle;
// per-channel differentiation lives entirely in the 80-bit weight word.

module fc_data_adapter #(
  parameter OUT_CHANNELS = 10,
  parameter PIX_W        = 8,
  parameter KER_W        = 8
)(
  input  wire        clk,
  input  wire        rst_n,

  // FC weight stream (from SRAM_FCW, 288 words x 80b)
  input  wire                               wt_valid,
  input  wire [OUT_CHANNELS*KER_W-1:0]      wt_data,
  input  wire                               wt_last,
  output wire                               wt_ready,

  // FC data stream (from SRAM_B, 72 packed words)
  input  wire                               data_valid,
  input  wire [31:0]                        data_data,
  input  wire                               data_last,
  output wire                               data_ready,

  // FC data path (packed vectors, LSB = channel 0)
  output wire                               mul_en,
  output wire [OUT_CHANNELS*PIX_W-1:0]      pixel_vec,
  output wire [OUT_CHANNELS*KER_W-1:0]      kernel_vec,

  // FC completion
  input  wire        all_done,
  output wire        fc_done
);
  localparam integer WT_W = OUT_CHANNELS*KER_W;

  // --- Holding registers ---
  reg [WT_W-1:0]  wt_reg;
  reg             wt_held;
  reg [31:0]      data_reg;
  reg             data_held;
  reg [1:0]       byte_sel;

  wire wt_avail    = wt_held;
  wire pixel_avail = data_held;

  assign mul_en     = wt_avail && pixel_avail && !all_done;
  assign wt_ready   = (wt_held   && mul_en) || (!wt_held   && !wt_valid);
  assign data_ready = (data_held && mul_en && (byte_sel == 2'd3))
                   || (!data_held && !data_valid);

  // Kernel vector: directly drive from held 80-bit weight word
  assign kernel_vec = wt_reg;

  // Pixel byte selection (SRAM_B packs high byte first, matching current behavior)
  wire [7:0] pixel_byte = (byte_sel == 2'd0) ? data_reg[31:24] :
                          (byte_sel == 2'd1) ? data_reg[23:16] :
                          (byte_sel == 2'd2) ? data_reg[15: 8] :
                                               data_reg[ 7: 0];

  // Broadcast one pixel byte to all OUT_CHANNELS slots
  genvar gi;
  generate
    for (gi = 0; gi < OUT_CHANNELS; gi = gi + 1) begin : g_pix
      assign pixel_vec[gi*PIX_W +: PIX_W] = $signed(pixel_byte);
    end
  endgenerate

  assign fc_done = all_done;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wt_reg    <= {WT_W{1'b0}};
      wt_held   <= 1'b0;
      data_reg  <= 32'd0;
      data_held <= 1'b0;
      byte_sel  <= 2'd0;
    end else begin
      if (!wt_held) begin
        if (wt_valid) begin
          wt_reg  <= wt_data;
          wt_held <= 1'b1;
        end
      end else if (mul_en) begin
        wt_held <= 1'b0;
      end

      if (!data_held) begin
        if (data_valid) begin
          data_reg  <= data_data;
          data_held <= 1'b1;
          byte_sel  <= 2'd0;
        end
      end else if (mul_en) begin
        if (byte_sel == 2'd3) begin
          byte_sel  <= 2'd0;
          data_held <= 1'b0;
        end else begin
          byte_sel <= byte_sel + 2'd1;
        end
      end
    end
  end

endmodule
