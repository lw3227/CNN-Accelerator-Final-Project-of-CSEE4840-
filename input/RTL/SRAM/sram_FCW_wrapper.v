`timescale 1ns/1ps

// sram_FCW_wrapper: dedicated FC-weight memory.
//   Depth  = 288 words (FC input K = 6*6*8)
//   Width  = 80 bits  (10 output channels x 8-bit INT8 kernel)
//
// Written so Quartus (Cyclone V M10K) and Xilinx Vivado both infer
// BRAM. Keys to inference:
//   (1) memory read/write in ONE tiny always block, no reset.
//   (2) no reset of `douta` inside the RAM block -- the M10K output
//       register cannot be reset and still map to BRAM. Any reset of
//       `douta` forces the tool into FFs.
//   (3) `douta_valid` tracking is in a SEPARATE always block so it
//       does not contaminate the RAM template.
//   (4) 80-bit width > M10K's 40-bit ceiling -> Quartus automatically
//       concatenates two M10K blocks (fine as long as (1)-(3) hold).

module sram_FCW_wrapper # (
    parameter AW = 9,         // 2^9 = 512 >= 288
    parameter DW = 80
) (
    input                clka,
    input                rsta,       // sync active-high reset (valid flag only)
    input                ena,
    input                wea,
    input  [AW-1:0]      addra,
    input  [DW-1:0]      dina,

    output reg [DW-1:0]  douta,
    output reg           douta_valid
);
    // -----------------------------------------------------------------
    //  RAM block: plain sync write / sync read, no reset (BRAM template)
    // -----------------------------------------------------------------
    (* ramstyle = "M10K" *)
    reg [DW-1:0] mem [0:(1<<AW)-1];

    always @(posedge clka) begin
        if (ena) begin
            if (wea)
                mem[addra] <= dina;
            else
                douta <= mem[addra];
        end
    end

    // -----------------------------------------------------------------
    //  Valid flag: separate always block so it does NOT inhibit
    //  BRAM inference of `mem` / `douta`.
    // -----------------------------------------------------------------
    always @(posedge clka) begin
        if (rsta)
            douta_valid <= 1'b0;
        else if (ena && !wea)
            douta_valid <= 1'b1;
        else
            douta_valid <= 1'b0;
    end

endmodule
