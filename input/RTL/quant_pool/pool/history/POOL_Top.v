module POOL_pipeline_Top(
    input         clk, rst_n,
    input         shift_en,
    input signed [7:0]  cut1, cut2, cut3, cut4,
    input         en1, en2, en3, en4,
    output        POOL_REG_full,
    output        POOL_REG_empty,
    output reg signed [31:0] data_to_sram
);

    wire signed [7:0] byte3, byte2, byte1, byte0;
    wire              wait1, wait2, wait3, wait4;
    reg signed [31:0] next_data_to_sram;

    POOL_pipeline_PE u_PE1 (
    .clk(clk), .rst_n(rst_n), .shift_en(shift_en),
    .shift_finish(POOL_REG_empty), .cut(cut1), .en(en1), .byte_out(byte3),
    .waitt(wait1)
    );

    POOL_pipeline_PE u_PE2 (
    .clk(clk), .rst_n(rst_n), .shift_en(shift_en),
    .shift_finish(POOL_REG_empty), .cut(cut2), .en(en2), .byte_out(byte2),
    .waitt(wait2)
    );

    POOL_pipeline_PE u_PE3 (
    .clk(clk), .rst_n(rst_n), .shift_en(shift_en),
    .shift_finish(POOL_REG_empty), .cut(cut3), .en(en3), .byte_out(byte1),
    .waitt(wait3)
    );

    POOL_pipeline_PE u_PE4 (
    .clk(clk), .rst_n(rst_n), .shift_en(shift_en),
    .shift_finish(POOL_REG_empty), .cut(cut4), .en(en4), .byte_out(byte0),
    .waitt(wait4));

    always @* begin
        if (shift_en) next_data_to_sram = {byte3, byte2, byte1, byte0};
        else next_data_to_sram = data_to_sram;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) data_to_sram <= 32'sd0;
        else data_to_sram <= next_data_to_sram;
    end
    
    assign POOL_REG_full = wait1 & wait2 & wait3 & wait4;
    assign POOL_REG_empty = POOL_REG_full && (next_data_to_sram == 32'sd0) && (next_data_to_sram != data_to_sram);

endmodule