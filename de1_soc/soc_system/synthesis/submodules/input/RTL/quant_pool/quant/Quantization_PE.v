module Quantization_PE(
    input clk, rst_n,
    input start,
    input in_valid,
    input load_bias, load_M, load_sh,
    input signed [31:0] bias_in,
    input signed [31:0] M_in,
    input [7:0] sh_in,
    input signed [22:0] rso,
    output reg signed [7:0] cut,
    output reg cut_valid
);

reg load_delay; // created by load_sh by one cycle delay to activate round_term calculation
reg [3:0] valid_sr;
reg signed [31:0] bias;
reg signed [31:0] next_bias; 
reg signed [31:0] M;
reg signed [31:0] next_M; 
reg [7:0] sh;
reg [7:0] next_sh; 
reg signed [63:0] round_term;
reg signed [63:0] next_round_term;
reg signed [31:0] acc;
reg signed [31:0] next_acc;
reg signed [63:0] mul;
reg signed [63:0] next_mul;
reg signed [63:0] correct;
reg signed [63:0] next_correct;
reg signed [63:0] shiftt;
reg signed [63:0] next_shiftt;
reg signed [63:0] y;
reg signed [7:0] next_cut;
wire signed [31:0] MM;

// create load_delay by one cycle delay from load_sh
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) load_delay <= 1'd0;
    else load_delay <= load_sh;
end

// Output-valid tracks true input samples, not the tail-extended start signal.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_sr  <= 4'b0;
        cut_valid <= 1'b0;
    end
    else if (load_sh) begin
        valid_sr  <= 4'b0;
        cut_valid <= 1'b0;
    end
    else begin
        valid_sr  <= {valid_sr[2:0], in_valid};
        cut_valid <= valid_sr[3];
    end
end

// Bias(32-bits) loaded from outside to bias branch
always @* begin
    next_bias = bias;
    if (load_bias) begin
        next_bias = bias_in;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin 
        bias <= 32'sd0;
    end
    else begin
        bias <= next_bias;
    end
end

// M(32-bits) loaded from outside to M branch
always @* begin
    next_M = M;
    if (load_M) begin
        next_M = M_in;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin 
        M <= 32'sd0;
    end
    else begin
        M <= next_M;
    end
end

assign MM = start ? M : 32'sd0;

// sh loaded from outside to sh(shifter) branch
always @* begin
    next_sh = sh;
    if (load_sh) begin
        next_sh = sh_in;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin 
        sh <= 8'd0;
    end
    else begin
        sh <= next_sh;
    end
end

// one cycle delay to generate round_term
always @* begin
    if (!load_delay) begin
        next_round_term = round_term;
    end
    else begin
        next_round_term = 64'sd1 << (sh - 8'd1);
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        round_term <= 64'sd0;
    end
    else if (load_sh) begin
        round_term <= 64'sd0;
    end
    else begin
        round_term <= next_round_term;
    end
end

// main branch
// step 1. adding bias
always @* begin
    next_acc = rso + bias;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc <= 32'sd0;
    end
    else if (load_sh) begin
        acc <= 32'sd0;
    end
    else begin
        acc <= next_acc;
    end
end

// step 2. acc * M
always @* begin
    next_mul = acc * MM;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mul <= 64'sd0;
    end
    else if (load_sh) begin
        mul <= 64'sd0;
    end
    else begin
        mul <= next_mul;
    end
end

// step 3. Correctness: adding round_term & negative correctness
always @* begin
    next_correct = mul + round_term - mul[63];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        correct <= 64'sd0;
    end
    else if (load_sh) begin
        correct <= 64'sd0;
    end
    else begin
        correct <= next_correct;
    end
end

// step 4. shifting sh-bits
always @* begin
    next_shiftt = correct >>> sh;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        shiftt <= 64'sd0;
    end
    else if (load_sh) begin
        shiftt <= 64'sd0;
    end
    else begin
        shiftt <= next_shiftt;
    end
end

// step 5.  sdding zeropoint & cutting LSB 8 bits
always @* begin
    y = shiftt - 64'sd128;  // 128 is the zp

    // saturating clamp
    if (y > 64'sd127) next_cut = 8'sd127;
    else if (y < -64'sd128) next_cut = -8'sd128;
    else next_cut = y[7:0];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cut <= 8'sd0;
    end
    else if (load_sh) begin
        cut <= 8'sd0;
    end
    else begin
        cut <= next_cut;
    end
end

endmodule
