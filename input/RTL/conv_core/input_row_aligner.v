`timescale 1ns/1ns

module input_row_aligner #(
    parameter integer W    = 64,
    parameter integer DW   = 8,
    parameter integer C_IN = 8
)(
    input  wire                      [1:0]         layer_sel,
    input  wire                                     clk,
    input  wire                                     rst_n,
    input  wire                                     frame_rearm,
    input  wire                                     in_valid,
    input  wire                      [31:0]         in_data,
    input  wire                      [3:0]          in_byte_en,
    output wire                                     pix3_valid,
    output wire signed              [C_IN*DW-1:0] row0_out,
    output wire signed              [C_IN*DW-1:0] row1_out,
    output wire signed              [C_IN*DW-1:0] row2_out
);

    localparam integer PIX_W = C_IN * DW;

    reg        [31:0]            saved_lo;
    reg                           half_r;
    reg                           ser_valid_r;
    reg signed [PIX_W-1:0]        ser_data_r;

    wire [31:0] in_masked = { in_byte_en[3] ? in_data[31:24] : 8'd0,
                              in_byte_en[2] ? in_data[23:16] : 8'd0,
                              in_byte_en[1] ? in_data[15:8]  : 8'd0,
                              in_byte_en[0] ? in_data[7:0]   : 8'd0 };

    integer pb;
    always @* begin
      ser_valid_r = 1'b0;
      ser_data_r  = {PIX_W{1'b0}};
      case (layer_sel)
        2'b00: begin
          ser_valid_r   = in_valid;
          ser_data_r[7:0] = in_masked[7:0];
        end
        2'b01: begin
          ser_valid_r = in_valid;
          for (pb = 0; pb < 4 && pb < PIX_W/8; pb = pb + 1)
            ser_data_r[pb*8 +: 8] = in_masked[pb*8 +: 8];
        end
        default: begin
          ser_valid_r = in_valid && half_r;
          for (pb = 0; pb < 4 && pb < PIX_W/8; pb = pb + 1)
            ser_data_r[pb*8 +: 8] = saved_lo[pb*8 +: 8];
          for (pb = 4; pb < 8 && pb < PIX_W/8; pb = pb + 1)
            ser_data_r[pb*8 +: 8] = in_masked[(pb-4)*8 +: 8];
        end
      endcase
    end

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        saved_lo <= 32'd0;
        half_r   <= 1'b0;
      end else if (frame_rearm) begin
        saved_lo <= 32'd0;
        half_r   <= 1'b0;
      end else if (in_valid) begin
        case (layer_sel)
          2'b10: begin
            if (!half_r)
              saved_lo <= in_masked;
            half_r <= ~half_r;
          end
          default: begin
            half_r <= 1'b0;
          end
        endcase
      end
    end

    wire signed [PIX_W-1:0] row0;
    wire signed [PIX_W-1:0] row1;
    wire signed [PIX_W-1:0] row2;
    wire row0_valid;
    wire row1_valid;
    wire row2_valid;

    assign row0       = ser_data_r;
    assign row0_valid = ser_valid_r;

    Line_Buffer #(
        .W(W),
        .DW(PIX_W)
    ) Line_Buffer_row1 (
        .layer_sel  (layer_sel),
        .clk        (clk),
        .rst_n      (rst_n),
        .frame_rearm(frame_rearm),
        .in_valid   (row0_valid),
        .in_data    (row0),
        .out_valid  (row1_valid),
        .out_data   (row1)
    );

    Line_Buffer #(
        .W(W),
        .DW(PIX_W)
    ) Line_Buffer_row2 (
        .layer_sel  (layer_sel),
        .clk        (clk),
        .rst_n      (rst_n),
        .frame_rearm(frame_rearm),
        .in_valid   (row1_valid),
        .in_data    (row1),
        .out_valid  (row2_valid),
        .out_data   (row2)
    );

    assign pix3_valid = row2_valid & row1_valid & row0_valid;
    assign row0_out   = row0;
    assign row1_out   = row1;
    assign row2_out   = row2;

endmodule
