module sram_B_controller #(
    parameter ADDR_WIDTH = 10
)(
    input [2:0] layer_sel,
    input [1:0] data_sel,
    input       pass_id,

    output reg [ADDR_WIDTH-1:0] base_addr,
    output reg [ADDR_WIDTH-1:0] length,
    output reg                  read_mode,
    output reg                  write_mode
);

localparam [2:0] LAYER_PRELOAD = 3'd0;
localparam [2:0] LAYER_L1      = 3'd1;
localparam [2:0] LAYER_L2      = 3'd2;
localparam [2:0] LAYER_L3      = 3'd3;
localparam [2:0] LAYER_FC      = 3'd4;

localparam [1:0] SEL_CFG       = 2'd0;
localparam [1:0] SEL_WT        = 2'd1;
localparam [1:0] SEL_DATA      = 2'd2;

// SRAM_B only stores runtime feature maps in the current top-level memory plan.
// There is no preload transaction on SRAM_B.
// It is reused in time:
// - L1 pooled output shares the same 31x31x4 buffer used as L2 input.
// - L3 pooled output reuses the front part of SRAM_B as the FC input buffer.

localparam [ADDR_WIDTH-1:0] L1_OUT_BASE       = 10'h000;
localparam [ADDR_WIDTH-1:0] L1_OUT_LEN        = 10'd961; // 31*31*4 bytes / 4

localparam [ADDR_WIDTH-1:0] L2_DATA_BASE      = 10'h000;
localparam [ADDR_WIDTH-1:0] L2_DATA_LEN       = 10'd961; // 31*31*4 bytes / 4

localparam [ADDR_WIDTH-1:0] L3_PASS0_OUT_BASE = 10'h000;
localparam [ADDR_WIDTH-1:0] L3_PASS0_OUT_LEN  = 10'd36;  // 6*6*4 bytes / 4
localparam [ADDR_WIDTH-1:0] L3_PASS1_OUT_BASE = 10'h024;
localparam [ADDR_WIDTH-1:0] L3_PASS1_OUT_LEN  = 10'd36;  // 6*6*4 bytes / 4

localparam [ADDR_WIDTH-1:0] FC_DATA_BASE      = 10'h000;
localparam [ADDR_WIDTH-1:0] FC_DATA_LEN       = 10'd72;  // 6*6*8 bytes / 4

always @(*) begin
    base_addr  = {ADDR_WIDTH{1'b0}};
    length     = {ADDR_WIDTH{1'b0}};
    read_mode  = 1'b0;
    write_mode = 1'b0;

    case (layer_sel)
        LAYER_L1: begin
            if (data_sel == SEL_DATA) begin
                write_mode = 1'b1;
                base_addr  = L1_OUT_BASE;
                length     = L1_OUT_LEN;
            end
        end

        LAYER_L2: begin
            if (data_sel == SEL_DATA) begin
                read_mode = 1'b1;
                base_addr = L2_DATA_BASE;
                length    = L2_DATA_LEN;
            end
        end

        LAYER_L3: begin
            if (data_sel == SEL_DATA) begin
                write_mode = 1'b1;
                base_addr  = pass_id ? L3_PASS1_OUT_BASE : L3_PASS0_OUT_BASE;
                length     = pass_id ? L3_PASS1_OUT_LEN  : L3_PASS0_OUT_LEN;
            end
        end

        LAYER_FC: begin
            if (data_sel == SEL_DATA) begin
                read_mode = 1'b1;
                base_addr = FC_DATA_BASE;
                length    = FC_DATA_LEN;
            end
        end

        default: begin
        end
    endcase
end

endmodule
