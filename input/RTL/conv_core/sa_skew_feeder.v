module sa_skew_feeder #(
    parameter integer ROWS = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 frame_rearm,
    input  wire                 rd_en,
    input  wire signed [ROWS*8-1:0]    in_firstcol_flat,
    output wire signed [ROWS*8-1:0]    out_firstcol_flat
);

  // Skew-only stage: row r is delayed by r cycles to create the systolic
  // wavefront. The large full-window banks now live in Conv_Buffer instead.
  reg signed [7:0] delay [0:119];
  reg       rd_en_d;

  function integer base;
    input integer r;
    begin
      base = (r * (r - 1)) / 2;
    end
  endfunction

  wire rd_start = rd_en & ~rd_en_d;

  wire signed [7:0] raw0  = in_firstcol_flat[7:0];
  wire signed [7:0] raw1  = in_firstcol_flat[15:8];
  wire signed [7:0] raw2  = in_firstcol_flat[23:16];
  wire signed [7:0] raw3  = in_firstcol_flat[31:24];
  wire signed [7:0] raw4  = in_firstcol_flat[39:32];
  wire signed [7:0] raw5  = in_firstcol_flat[47:40];
  wire signed [7:0] raw6  = in_firstcol_flat[55:48];
  wire signed [7:0] raw7  = in_firstcol_flat[63:56];
  wire signed [7:0] raw8  = in_firstcol_flat[71:64];
  wire signed [7:0] raw9  = in_firstcol_flat[79:72];
  wire signed [7:0] raw10 = in_firstcol_flat[87:80];
  wire signed [7:0] raw11 = in_firstcol_flat[95:88];
  wire signed [7:0] raw12 = in_firstcol_flat[103:96];
  wire signed [7:0] raw13 = in_firstcol_flat[111:104];
  wire signed [7:0] raw14 = in_firstcol_flat[119:112];
  wire signed [7:0] raw15 = in_firstcol_flat[127:120];

  integer x;
  integer s;
  integer b;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_en_d <= 1'b0;
      for (x = 0; x < 120; x = x + 1)
        delay[x] <= 8'h00;
    end else if (frame_rearm) begin
      rd_en_d <= 1'b0;
      for (x = 0; x < 120; x = x + 1)
        delay[x] <= 8'h00;
    end else begin
      rd_en_d <= rd_en;
      if (rd_en) begin
        for (x = 1; x <= 15; x = x + 1) begin
          b = base(x);
          if (rd_start) begin
            for (s = x - 1; s >= 1; s = s - 1)
              delay[b + s] <= 8'h00;
          end else begin
            for (s = x - 1; s >= 1; s = s - 1)
              delay[b + s] <= delay[b + s - 1];
          end

          case (x)
            1:  delay[b] <= raw1;
            2:  delay[b] <= raw2;
            3:  delay[b] <= raw3;
            4:  delay[b] <= raw4;
            5:  delay[b] <= raw5;
            6:  delay[b] <= raw6;
            7:  delay[b] <= raw7;
            8:  delay[b] <= raw8;
            9:  delay[b] <= raw9;
            10: delay[b] <= raw10;
            11: delay[b] <= raw11;
            12: delay[b] <= raw12;
            13: delay[b] <= raw13;
            14: delay[b] <= raw14;
            15: delay[b] <= raw15;
            default: delay[b] <= 8'h00;
          endcase
        end
      end
    end
  end

  wire signed [7:0] out0  = rd_en ? raw0 : 8'h00;
  wire signed [7:0] out1  = delay[base(1)  + 0];
  wire signed [7:0] out2  = delay[base(2)  + 1];
  wire signed [7:0] out3  = delay[base(3)  + 2];
  wire signed [7:0] out4  = delay[base(4)  + 3];
  wire signed [7:0] out5  = delay[base(5)  + 4];
  wire signed [7:0] out6  = delay[base(6)  + 5];
  wire signed [7:0] out7  = delay[base(7)  + 6];
  wire signed [7:0] out8  = delay[base(8)  + 7];
  wire signed [7:0] out9  = delay[base(9)  + 8];
  wire signed [7:0] out10 = delay[base(10) + 9];
  wire signed [7:0] out11 = delay[base(11) + 10];
  wire signed [7:0] out12 = delay[base(12) + 11];
  wire signed [7:0] out13 = delay[base(13) + 12];
  wire signed [7:0] out14 = delay[base(14) + 13];
  wire signed [7:0] out15 = delay[base(15) + 14];

  assign out_firstcol_flat = {
      out15, out14, out13, out12, out11, out10, out9, out8,
      out7,  out6,  out5,  out4,  out3,  out2,  out1, out0
  };

endmodule
