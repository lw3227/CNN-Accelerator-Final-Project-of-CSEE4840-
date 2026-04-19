// conv_data_adapter: unpack 32-bit SRAM words into Conv input beats.
//
// L1 (layer_sel=00): 1 SRAM word → 4 byte beats (1-word holding register)
//   SRAM outputs 1024 words, Conv receives 4096 beats × 8-bit, in_byte_en=0001
// L2/L3 also use a 1-word holding register so the adapter can safely absorb
// the SRAM wrapper's 1-cycle read pipeline under downstream backpressure.

module conv_data_adapter (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [1:0]  layer_sel,

  // Upstream: from SRAM read stream
  input  wire        up_valid,
  input  wire [31:0] up_data,
  input  wire        up_last,
  output wire        up_ready,

  // Downstream: to Conv in port
  output wire        dn_valid,
  output wire [31:0] dn_data,
  output wire [3:0]  dn_byte_en,
  output wire        dn_last,
  input  wire        dn_ready
);

  wire is_l1 = (layer_sel == 2'b00);

  // ---------------------------------------------------------------
  // L1: byte unpack with 1-word holding register
  // L2/L3: buffered word pass-through
  // ---------------------------------------------------------------

  reg [31:0] hold_reg;
  reg        hold_valid;
  reg [1:0]  byte_sel;     // 0,1,2,3
  reg        hold_is_last; // the held word was the last SRAM word

  wire [31:0] cur_word_l1   = hold_valid ? hold_reg : up_data;
  wire [1:0]  cur_byte_sel  = hold_valid ? byte_sel : 2'd0;
  wire        cur_is_last_l1 = hold_valid ? hold_is_last : up_last;

  // Current pixel byte from active word (held word or fresh bypass)
  wire [7:0] pixel_byte = (cur_byte_sel == 2'd0) ? cur_word_l1[ 7: 0] :
                          (cur_byte_sel == 2'd1) ? cur_word_l1[15: 8] :
                          (cur_byte_sel == 2'd2) ? cur_word_l1[23:16] :
                                                   cur_word_l1[31:24];

  // L1 downstream signals
  wire l1_dn_valid = hold_valid || up_valid;
  wire l1_dn_last  = l1_dn_valid && cur_is_last_l1 && (cur_byte_sel == 2'd3);

  // L1 up_ready: assert only when adapter WILL BE free next cycle.
  // SRAM wrapper has 1-cycle read pipeline (read_en → data_valid next cycle),
  // so up_ready must predict availability 1 cycle ahead.
  //   Case A: hold_valid=1, last byte being consumed → free next cycle
  //   Case B: hold_valid=0 AND no data arriving → already free
  // When data is arriving (up_valid=1, hold_valid=0), the adapter is latching
  // this cycle — NOT free for another read next cycle.
  wire l1_will_be_free = (hold_valid && dn_ready && byte_sel == 2'd3)
                       || (!hold_valid && !up_valid);
  wire l1_up_ready = l1_will_be_free;

  // L2/L3: one-word buffer to absorb the upstream read pipeline.
  // Byte-swap: pool_data stores {ch0,ch1,ch2,ch3} with ch0 at MSB,
  // but Conv pixel_serializer expects ch0 at LSB (in_data[7:0]=ch0).
  wire [31:0] nonl1_raw  = hold_valid ? hold_reg : up_data;
  wire [31:0] nonl1_word = {nonl1_raw[7:0], nonl1_raw[15:8],
                            nonl1_raw[23:16], nonl1_raw[31:24]};
  wire        nonl1_is_last = hold_valid ? hold_is_last : up_last;
  wire nonl1_dn_valid = hold_valid || up_valid;
  wire nonl1_dn_last  = nonl1_dn_valid && nonl1_is_last;
  wire nonl1_will_be_free = (hold_valid && dn_ready)
                         || (!hold_valid && (!up_valid || dn_ready));
  wire nonl1_up_ready = nonl1_will_be_free;

  // Muxed outputs
  assign dn_valid   = is_l1 ? l1_dn_valid : nonl1_dn_valid;
  assign dn_data    = is_l1 ? {24'd0, pixel_byte} : nonl1_word;
  assign dn_byte_en = is_l1 ? 4'b0001 : 4'b1111;
  assign dn_last    = is_l1 ? l1_dn_last : nonl1_dn_last;
  assign up_ready   = is_l1 ? l1_up_ready : nonl1_up_ready;

  // ---------------------------------------------------------------
  // L1 holding register and byte_sel control
  // ---------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hold_reg    <= 32'd0;
      hold_valid  <= 1'b0;
      byte_sel    <= 2'd0;
      hold_is_last <= 1'b0;
    end else if (is_l1) begin
      if (!hold_valid) begin
        if (up_valid) begin
          hold_reg    <= up_data;
          hold_is_last <= up_last;
          hold_valid  <= 1'b1;
          // Fresh word can emit byte0 immediately; keep byte1 queued next.
          byte_sel    <= dn_ready ? 2'd1 : 2'd0;
        end
      end else if (dn_ready) begin
        if (byte_sel == 2'd3) begin
          // Finished current word
          hold_valid <= 1'b0;
          byte_sel   <= 2'd0;
        end else begin
          byte_sel <= byte_sel + 2'd1;
        end
      end
    end else begin
      if (!hold_valid) begin
        if (up_valid) begin
          if (!dn_ready) begin
            hold_reg     <= up_data;
            hold_valid   <= 1'b1;
            hold_is_last <= up_last;
          end
          byte_sel     <= 2'd0;
        end
      end else if (dn_ready) begin
        hold_valid <= 1'b0;
        byte_sel   <= 2'd0;
      end
    end
  end

endmodule
