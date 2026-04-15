`timescale 1ns/1ns

// Line_Buffer: runtime-compatible version.
// Fixed 124-byte shift register (992 bits).
// layer_sel selects effective depth and stride:
//   L1 (2'b00): stride=1 byte,  depth=64 → tap at byte 63
//   L2 (2'b01): stride=4 bytes, depth=31 → tap at byte 120..123
//   L3 (2'b10): stride=8 bytes, depth=14 → tap at byte 104..111
module Line_Buffer #(
    parameter integer W  = 64,
    parameter integer DW = 64   // max pixel bit-width
)(
    input  wire        [1:0]  layer_sel,
    input  wire               clk,
    input  wire               rst_n,
    input  wire               frame_rearm,//frame_rearm 的作用是清零移位寄存器和填充计数器
    input  wire               in_valid,
    input  wire signed [DW-1:0] in_data,
    output wire               out_valid,
    output wire signed [DW-1:0] out_data//输出数据根据 layer_sel 从移位寄存器的不同位置提取
);

    localparam integer N = 124;  // total bytes

    reg [7:0] shreg [0:N-1];

    // Runtime parameters
    reg [6:0] eff_w;        // effective depth (pixels)
    reg [3:0] eff_stride;   // bytes per pixel
    always @* begin
      case (layer_sel)
        2'b01:   begin eff_w = 7'd31; eff_stride = 4'd4; end//L2
        2'b10:   begin eff_w = 7'd14; eff_stride = 4'd8; end//L3  
        default: begin eff_w = 7'd64; eff_stride = 4'd1; end//L1
      endcase
    end

    // Fill counter
    reg [6:0] fill_cnt;
    assign out_valid = in_valid && (fill_cnt == eff_w);

    // Output tap: read eff_stride bytes from the oldest position.
    // Use byte-level MUX to avoid negative replication for any DW.
    reg signed [DW-1:0] out_r;
    integer ob;
    always @* begin
      out_r = {DW{1'b0}};
      case (layer_sel)
        2'b01: begin // L2: 4 bytes at [120..123]
          for (ob = 0; ob < DW/8 && ob < 4; ob = ob + 1)
            out_r[ob*8 +: 8] = shreg[120 + ob];
        end
        2'b10: begin // L3: 8 bytes at [104..111]
          for (ob = 0; ob < DW/8 && ob < 8; ob = ob + 1)
            out_r[ob*8 +: 8] = shreg[104 + ob];
        end
        default: begin // L1: 1 byte at [63]
          out_r[7:0] = shreg[63];
        end
      endcase
    end
    assign out_data = out_r;

    // Shift register: on each in_valid, shift by eff_stride bytes.
    integer i;
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        fill_cnt <= 7'd0;
        for (i = 0; i < N; i = i + 1)
          shreg[i] <= 8'd0;
      end else if (frame_rearm) begin
        fill_cnt <= 7'd0;
        for (i = 0; i < N; i = i + 1)
          shreg[i] <= 8'd0;
      end else if (in_valid) begin
        case (eff_stride)
          4'd4: begin
            for (i = N-1; i >= 4; i = i - 1) shreg[i] <= shreg[i-4];
            shreg[3] <= in_data[31:24];
            shreg[2] <= in_data[23:16];
            shreg[1] <= in_data[15:8];
            shreg[0] <= in_data[7:0];
          end
          4'd8: begin
            for (i = N-1; i >= 8; i = i - 1) shreg[i] <= shreg[i-8];
            for (ob = 0; ob < 8; ob = ob + 1) begin
              if (ob < DW/8)
                shreg[ob] <= in_data[ob*8 +: 8];
              else
                shreg[ob] <= 8'd0;
            end
          end
          default: begin  // stride=1
            for (i = N-1; i >= 1; i = i - 1) shreg[i] <= shreg[i-1];
            shreg[0] <= in_data[7:0];
          end
        endcase

        if (fill_cnt < eff_w)
          fill_cnt <= fill_cnt + 7'd1;
      end
    end

endmodule
