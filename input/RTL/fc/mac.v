module mac #(
  parameter PIX_W = 8,
  parameter KER_W = 8,
  parameter K = 288,
  parameter ACC_W = 32
)(
  input  wire clk,
  input  wire rst_n,
  input  wire mul_en,
  input  wire signed [PIX_W-1:0] pixel,
  input  wire signed [KER_W-1:0] kernel,
  // Bias preload
  input  wire               load_bias,
  input  wire signed [ACC_W-1:0] bias_in,
  output reg  signed [ACC_W-1:0] acc,
  output reg  mul_done
);

  wire signed [PIX_W+KER_W-1:0] product;
  wire signed [ACC_W-1:0] product_ext;

  reg [$clog2(K)-1:0] cnt;
  reg signed [ACC_W-1:0] bias_reg;

  assign product = $signed(pixel) * $signed(kernel);
  assign product_ext = {{(ACC_W-(PIX_W+KER_W)){product[PIX_W+KER_W-1]}}, product};

  // Bias register: latch on load_bias pulse
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      bias_reg <= {ACC_W{1'b0}};
    else if (load_bias)
      bias_reg <= bias_in;
  end

  // MAC accumulator
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc      <= {ACC_W{1'b0}};
      mul_done <= 1'b0;
      cnt      <= {$clog2(K){1'b0}};
    end else if (load_bias) begin
      // Reset for new inference: clear accumulator state so mul_en can fire
      acc      <= {ACC_W{1'b0}};
      mul_done <= 1'b0;
      cnt      <= {$clog2(K){1'b0}};
    end else if (mul_en) begin
      if (cnt == 0) begin
        acc      <= bias_reg + product_ext;
        mul_done <= 1'b0;
        cnt      <= cnt + 1'b1;
      end else if (cnt == K - 1) begin
        acc      <= acc + product_ext;
        mul_done <= 1'b1;
        cnt      <= {$clog2(K){1'b0}};
      end else begin
        acc      <= acc + product_ext;
        mul_done <= 1'b0;
        cnt      <= cnt + 1'b1;
      end
    end
  end

endmodule
