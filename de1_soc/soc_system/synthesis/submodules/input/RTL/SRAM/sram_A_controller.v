module sram_A_controller #(
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
localparam [1:0] SEL_FCW       = 2'd3;  // FC weights in dedicated 80b SRAM_FCW

localparam [ADDR_WIDTH-1:0] PRELOAD_CFG_BASE  = 10'h000;
localparam [ADDR_WIDTH-1:0] PRELOAD_CFG_LEN   = 10'd45; // conv L1/L2/L3 cfg only; FC bias moved to dedicated slot
localparam [ADDR_WIDTH-1:0] PRELOAD_WT_BASE   = 10'h030;
localparam [ADDR_WIDTH-1:0] PRELOAD_WT_LEN    = 10'd225; // conv L1/L2/L3 weights only; FC weights moved to SRAM_FCW

// FC bias preload reuses SRAM_A (32b words) but at its own base outside
// the conv region. Preload writes 10 bias words to the free zone that used
// to hold the 3-class FC weight table.
localparam [ADDR_WIDTH-1:0] PRELOAD_FC_CFG_BASE = 10'h111;
localparam [ADDR_WIDTH-1:0] PRELOAD_FC_CFG_LEN  = 10'd10;

// FC weight preload streams through SRAM_A write port (host 32b) into the
// SRAM_FCW packer: 288 FCW slots x 3 host words = 864 beats.
localparam [ADDR_WIDTH-1:0] PRELOAD_FCW_LEN   = 10'd864;
// DATA preload is no longer stored in SRAM_A.
localparam [ADDR_WIDTH-1:0] PRELOAD_DATA_BASE = 10'h231;
localparam [ADDR_WIDTH-1:0] PRELOAD_DATA_LEN  = 10'd0;

localparam [ADDR_WIDTH-1:0] L1_CFG_BASE       = 10'h000;
localparam [ADDR_WIDTH-1:0] L1_CFG_LEN        = 10'd9;
localparam [ADDR_WIDTH-1:0] L1_WT_BASE        = 10'h030;
localparam [ADDR_WIDTH-1:0] L1_WT_LEN         = 10'd9;
// L1 input data is no longer read from SRAM_A.
localparam [ADDR_WIDTH-1:0] L1_DATA_BASE      = 10'h231;
localparam [ADDR_WIDTH-1:0] L1_DATA_LEN       = 10'd0;

localparam [ADDR_WIDTH-1:0] L2_PASS0_CFG_BASE = 10'h009;
localparam [ADDR_WIDTH-1:0] L2_PASS0_CFG_LEN  = 10'd9;
localparam [ADDR_WIDTH-1:0] L2_PASS1_CFG_BASE = 10'h012;
localparam [ADDR_WIDTH-1:0] L2_PASS1_CFG_LEN  = 10'd9;
localparam [ADDR_WIDTH-1:0] L2_PASS0_WT_BASE  = 10'h039;
localparam [ADDR_WIDTH-1:0] L2_PASS0_WT_LEN   = 10'd36;
localparam [ADDR_WIDTH-1:0] L2_PASS1_WT_BASE  = 10'h05D;
localparam [ADDR_WIDTH-1:0] L2_PASS1_WT_LEN   = 10'd36;
localparam [ADDR_WIDTH-1:0] L2_PASS0_OUT_BASE = 10'h231;
localparam [ADDR_WIDTH-1:0] L2_PASS0_OUT_LEN  = 10'd196;
// L2 pass1 uses same base as pass0; stride-2 interleave done in top_sram_A
localparam [ADDR_WIDTH-1:0] L2_PASS1_OUT_BASE = 10'h231;
localparam [ADDR_WIDTH-1:0] L2_PASS1_OUT_LEN  = 10'd196;

localparam [ADDR_WIDTH-1:0] L3_PASS0_CFG_BASE = 10'h01B;
localparam [ADDR_WIDTH-1:0] L3_PASS0_CFG_LEN  = 10'd9;
localparam [ADDR_WIDTH-1:0] L3_PASS1_CFG_BASE = 10'h024;
localparam [ADDR_WIDTH-1:0] L3_PASS1_CFG_LEN  = 10'd9;
localparam [ADDR_WIDTH-1:0] L3_PASS0_WT_BASE  = 10'h081;
localparam [ADDR_WIDTH-1:0] L3_PASS0_WT_LEN   = 10'd72;
localparam [ADDR_WIDTH-1:0] L3_PASS1_WT_BASE  = 10'h0C9;
localparam [ADDR_WIDTH-1:0] L3_PASS1_WT_LEN   = 10'd72;
localparam [ADDR_WIDTH-1:0] L3_DATA_BASE      = 10'h231;
localparam [ADDR_WIDTH-1:0] L3_DATA_LEN       = 10'd392;

// FC bias lives at 0x111 (the region freed by moving FC weights to SRAM_FCW).
// FC weights no longer live in SRAM_A at all -- LAYER_FC+SEL_WT is a no-op
// here; top_sram_A routes that transaction to the SRAM_FCW peer instead.
localparam [ADDR_WIDTH-1:0] FC_CFG_BASE       = 10'h111;
localparam [ADDR_WIDTH-1:0] FC_CFG_LEN        = 10'd10;

always @(*) begin
    base_addr  = {ADDR_WIDTH{1'b0}};
    length     = {ADDR_WIDTH{1'b0}};
    read_mode  = 1'b0;
    write_mode = 1'b0;

    case (layer_sel)
        LAYER_PRELOAD: begin
            write_mode = 1'b1;
            case (data_sel)
                SEL_CFG: begin
                    base_addr = PRELOAD_CFG_BASE;
                    length    = PRELOAD_CFG_LEN;
                end
                SEL_WT: begin
                    base_addr = PRELOAD_WT_BASE;
                    length    = PRELOAD_WT_LEN;
                end
                SEL_DATA: begin
                    // Preload DATA no longer uses SRAM_A.
                    write_mode = 1'b0;
                end
                SEL_FCW: begin
                    // FC weight preload: top_sram_A redirects the write stream
                    // to the SRAM_FCW packer. length counts host 32b beats.
                    base_addr = {ADDR_WIDTH{1'b0}};
                    length    = PRELOAD_FCW_LEN;
                end
                default: begin
                    write_mode = 1'b0;
                end
            endcase
        end

        LAYER_L1: begin
            read_mode = 1'b1;
            case (data_sel)
                SEL_CFG: begin
                    base_addr = L1_CFG_BASE;
                    length    = L1_CFG_LEN;
                end
                SEL_WT: begin
                    base_addr = L1_WT_BASE;
                    length    = L1_WT_LEN;
                end
                SEL_DATA: begin
                    // L1 DATA no longer reads from SRAM_A.
                    read_mode = 1'b0;
                end
                default: begin
                    read_mode = 1'b0;
                end
            endcase
        end

        LAYER_L2: begin
            case (data_sel)
                SEL_CFG: begin
                    read_mode = 1'b1;
                    base_addr = pass_id ? L2_PASS1_CFG_BASE : L2_PASS0_CFG_BASE;
                    length    = pass_id ? L2_PASS1_CFG_LEN  : L2_PASS0_CFG_LEN;
                end
                SEL_WT: begin
                    read_mode = 1'b1;
                    base_addr = pass_id ? L2_PASS1_WT_BASE : L2_PASS0_WT_BASE;
                    length    = pass_id ? L2_PASS1_WT_LEN  : L2_PASS0_WT_LEN;
                end
                SEL_DATA: begin
                    write_mode = 1'b1;
                    base_addr  = pass_id ? L2_PASS1_OUT_BASE : L2_PASS0_OUT_BASE;
                    length     = pass_id ? L2_PASS1_OUT_LEN  : L2_PASS0_OUT_LEN;
                end
                default: begin
                end
            endcase
        end

        LAYER_L3: begin
            read_mode = 1'b1;
            case (data_sel)
                SEL_CFG: begin
                    base_addr = pass_id ? L3_PASS1_CFG_BASE : L3_PASS0_CFG_BASE;
                    length    = pass_id ? L3_PASS1_CFG_LEN  : L3_PASS0_CFG_LEN;
                end
                SEL_WT: begin
                    base_addr = pass_id ? L3_PASS1_WT_BASE : L3_PASS0_WT_BASE;
                    length    = pass_id ? L3_PASS1_WT_LEN  : L3_PASS0_WT_LEN;
                end
                SEL_DATA: begin
                    base_addr = L3_DATA_BASE;
                    length    = L3_DATA_LEN;
                end
                default: begin
                    read_mode = 1'b0;
                end
            endcase
        end

        LAYER_FC: begin
            case (data_sel)
                SEL_CFG: begin
                    // FC bias lives in the freed old-FC-WT region of SRAM_A.
                    // Enable BOTH read and write so the same transaction can
                    // preload (write via pool_valid from host load_data) or
                    // fetch at inference time (read via data_ready from FC).
                    // Only one of read_en/write_en actually fires per cycle
                    // because pool_valid and data_ready are mutually exclusive
                    // in their respective modes.
                    read_mode  = 1'b1;
                    write_mode = 1'b1;
                    base_addr  = FC_CFG_BASE;
                    length     = FC_CFG_LEN;
                end
                SEL_WT: begin
                    // FC weights live in SRAM_FCW, not here.
                    // top_sram_A routes this transaction to the FCW peer and
                    // leaves the 32b SRAM_A idle; length=0 so Addr_Gen never
                    // asserts done on this path.
                end
                default: begin
                end
            endcase
        end

        default: begin
        end
    endcase
end

endmodule
