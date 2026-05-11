// wt_prepad_inserter: insert 3 zero words before real weight data.
//
// Sits between SRAM_A read stream and Conv wt port.
// When enabled (is_wt_read=1), inserts 3 zero beats then forwards real data.
// When disabled (is_wt_read=0), passes through transparently.
//
// Conv weight_buffer expects DOT_K+3 beats: 3 prepad zeros + DOT_K real weights.
// SRAM only stores DOT_K real weights. This module bridges the gap.

module wt_prepad_inserter (
  input  wire        clk,
  input  wire        rst_n,

  // Control: assert when current SRAM_A transaction is WT_READ
  input  wire        is_wt_read,

  // Upstream: SRAM_A read stream
  input  wire        up_valid,
  input  wire [31:0] up_data,
  input  wire        up_last,
  output wire        up_ready,

  // Downstream: to Conv wt port
  output wire        dn_valid,
  output wire [31:0] dn_data,
  output wire        dn_last,
  input  wire        dn_ready
);

  localparam [1:0] ST_IDLE   = 2'd0,
                   ST_PREPAD = 2'd1,
                   ST_PASS   = 2'd2;

  reg [1:0] state;
  reg [1:0] pad_cnt;  // counts 0,1,2 (3 zero beats)

  // Rising-edge detection on is_wt_read to avoid re-entering prepad
  reg is_wt_read_d;
  wire is_wt_read_rise = is_wt_read && !is_wt_read_d;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) is_wt_read_d <= 1'b0;
    else        is_wt_read_d <= is_wt_read;
  end

  // Pass-through when not in WT_READ mode
  wire passthrough = !is_wt_read || (state == ST_PASS);

  // SRAM wrapper read is 1-cycle pipelined. On the last zero-prepad beat,
  // request the first real weight so ST_PASS can start without a bubble.
  assign up_ready = passthrough ? dn_ready
                                : ((state == ST_PREPAD) && (pad_cnt == 2'd2) && dn_ready);
  assign dn_valid = passthrough ? up_valid : (state == ST_PREPAD);
  assign dn_data  = passthrough ? up_data  : 32'd0;
  assign dn_last  = passthrough ? up_last  : 1'b0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= ST_IDLE;
      pad_cnt <= 2'd0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (is_wt_read_rise) begin
            // is_wt_read just asserted: insert 3 prepad zeros before real data
            state   <= ST_PREPAD;
            pad_cnt <= 2'd0;
          end
        end

        ST_PREPAD: begin
          if (dn_ready) begin
            if (pad_cnt == 2'd2) begin
              state <= ST_PASS;  // prepad done, now forward real data
            end else begin
              pad_cnt <= pad_cnt + 2'd1;
            end
          end
        end

        ST_PASS: begin
          // Forward until upstream last beat is consumed
          if (up_valid && up_ready && up_last) begin
            state <= ST_IDLE;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
