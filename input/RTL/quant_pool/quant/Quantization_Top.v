module Quantization_Top(
    input clk, rst_n,
    
    // triggered by its owm layer's finish signal by 2 cycles delay.
    input start1, start2, start3, start4,
    input in_valid1, in_valid2, in_valid3, in_valid4,

    // bias 32 bits, only one bias_in is loaded at a cycle; same M.
    input load_bias1, load_bias2, load_bias3, load_bias4,
    input load_M1, load_M2, load_M3, load_M4,

    // sh1, sh2, sh3, sh4 are 8 bits, can loaded all of them at a same cycle as 32 bits.
    input load_sh,

    input signed [31:0] bias_in,
    input signed [31:0] M_in,

    // sh_in 32 bits [31:24] is sh_in1, [23:16] is sh_in2, ...
    input [31:0] sh_in,

    input signed [22:0] rso0,
    input signed [22:0] rso1,
    input signed [22:0] rso2,
    input signed [22:0] rso3,
    output signed [7:0] cut1, cut2, cut3, cut4,
    output cut_valid1, cut_valid2, cut_valid3, cut_valid4
);

Quantization_PE u_QPE1(
    .clk(clk), .rst_n(rst_n), .start(start1), .in_valid(in_valid1),
    .load_bias(load_bias1), .load_M(load_M1), .load_sh(load_sh),
    .bias_in(bias_in), .M_in(M_in), .sh_in(sh_in[31:24]),
    .rso(rso0), .cut(cut1), .cut_valid(cut_valid1)
);

Quantization_PE u_QPE2(
    .clk(clk), .rst_n(rst_n), .start(start2), .in_valid(in_valid2),
    .load_bias(load_bias2), .load_M(load_M2), .load_sh(load_sh),
    .bias_in(bias_in), .M_in(M_in), .sh_in(sh_in[23:16]),
    .rso(rso1), .cut(cut2), .cut_valid(cut_valid2)
);

Quantization_PE u_QPE3(
    .clk(clk), .rst_n(rst_n), .start(start3), .in_valid(in_valid3),
    .load_bias(load_bias3), .load_M(load_M3), .load_sh(load_sh),
    .bias_in(bias_in), .M_in(M_in), .sh_in(sh_in[15:8]),
    .rso(rso2), .cut(cut3), .cut_valid(cut_valid3)
);

Quantization_PE u_QPE4(
    .clk(clk), .rst_n(rst_n), .start(start4), .in_valid(in_valid4),
    .load_bias(load_bias4), .load_M(load_M4), .load_sh(load_sh),
    .bias_in(bias_in), .M_in(M_in), .sh_in(sh_in[7:0]),
    .rso(rso3), .cut(cut4), .cut_valid(cut_valid4)
);

endmodule
