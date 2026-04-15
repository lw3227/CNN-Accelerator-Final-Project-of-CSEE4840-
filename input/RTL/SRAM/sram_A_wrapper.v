`timescale 1ns/1ps
`define DELAY #1

module sram_A_wrapper # (
    parameter AW = 10
) (
    input clk,
    input rst_n,
    input write_en,
    input read_en,
    input [AW-1:0] addr,
    input [31:0] write_data,

    output [31:0] read_data,
    output reg read_valid
);
    wire do_write;
    wire do_read;

    wire CEN;
    wire WEN;
    wire [AW-1:0] addr_delayed;
    wire [31:0] write_data_delayed;

    assign do_write = write_en & ~read_en;
    assign do_read = read_en & ~write_en;

    assign `DELAY CEN = ~(do_write | do_read);
    assign `DELAY WEN = ~do_write;
    assign `DELAY addr_delayed = addr;
    assign `DELAY write_data_delayed = write_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            read_valid <= 1'b0;
        else 
            read_valid <= do_read;
    end

    sram_A sram_A_inst (
        .CLK(clk),
        .CEN(CEN),
        .WEN(WEN),
        .A(addr_delayed),
        .D(write_data_delayed),
        .EMA(3'b000),
        .RETN(1'b1),
        .Q(read_data)
    );


endmodule
