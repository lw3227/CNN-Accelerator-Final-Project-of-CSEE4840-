`timescale 1ns/1ps

// sram_FCW_wrapper: dedicated FC-weight memory.
//   Depth  = 288 words (FC input K = 6*6*8)
//   Width  = 80 bits  (10 output channels x 8-bit INT8 kernel)
//
// Port signature matches Xilinx Block Memory Generator "Native" single-port RAM
// so the FPGA port can replace the behavioral body with a blk_mem_gen IP instance
// without changing the surrounding hookup.

module sram_FCW_wrapper # (
    parameter AW = 9,         // 2^9 = 512 >= 288
    parameter DW = 80
) (
    input                clka,
    input                rsta,       // sync active-high reset (Vivado BRAM convention)
    input                ena,
    input                wea,
    input  [AW-1:0]      addra,
    input  [DW-1:0]      dina,

    output reg [DW-1:0]  douta,
    output reg           douta_valid
);
    reg [DW-1:0] mem [0:(1<<AW)-1];

    always @(posedge clka) begin
        if (rsta) begin
            douta       <= {DW{1'b0}};
            douta_valid <= 1'b0;
        end else if (ena) begin
            if (wea) begin
                mem[addra] <= dina;
                douta_valid <= 1'b0;
            end else begin
                douta       <= mem[addra];
                douta_valid <= 1'b1;
            end
        end else begin
            douta_valid <= 1'b0;
        end
    end

endmodule
