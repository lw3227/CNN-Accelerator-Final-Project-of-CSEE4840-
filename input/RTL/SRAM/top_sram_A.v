module top_sram_A(
    input clk,
    input rst_n,

    input [2:0] layer_sel,
    input [1:0] data_sel,
    input       pass_id,
    input       start,
    output      busy,
    output      done,

    // Read path from SRAM_A to conv / pool pipeline (32b, shared).
    input        data_ready,
    output [31:0] read_data,
    output        data_valid,
    output        data_last,

    // Write path from pool pipeline back to SRAM_A (32b, shared).
    output               pool_ready,
    input signed [31:0]  pool_data,
    input                pool_valid,
    input                pool_last,

    // FC weight read path (80b, dedicated SRAM_FCW).
    input                fc_wt_ready,
    output [79:0]        fc_wt_read_data,
    output               fc_wt_valid,
    output               fc_wt_last
);

localparam ADDR_WIDTH    = 10;
localparam FCW_ADDR_WIDTH = 9;     // 512 depth covers 288 entries
localparam FCW_DATA_WIDTH = 80;    // 10 x 8-bit kernels
localparam FCW_LEN        = 10'd288;

// SRAM_A controller localparams -- mirror sram_A_controller encodings.
localparam [2:0] LAYER_PRELOAD = 3'd0;
localparam [2:0] LAYER_FC      = 3'd4;
localparam [1:0] SEL_CFG       = 2'd0;
localparam [1:0] SEL_WT        = 2'd1;
localparam [1:0] SEL_FCW       = 2'd3;

// ------------------------------------------------------------------
// Classify incoming transaction
// ------------------------------------------------------------------
wire fcw_preload_txn = (layer_sel == LAYER_PRELOAD) && (data_sel == SEL_FCW);
wire fcw_read_txn    = (layer_sel == LAYER_FC)      && (data_sel == SEL_WT);
wire fcw_txn         = fcw_preload_txn | fcw_read_txn;

// ==================================================================
// Existing 32b SRAM_A path (conv L1/L2/L3, FC CFG, preload CFG/WT)
// ==================================================================

wire [ADDR_WIDTH-1:0] addr;
wire [ADDR_WIDTH-1:0] base_addr;
wire [ADDR_WIDTH-1:0] length;
wire        read_mode;
wire        write_mode;
wire        read_en;
wire        write_en;
wire        addr_step;
wire        txn_done;
wire        pool_ready_int;
wire        unused_pool_last;

reg         read_last_d;
reg         txn_active;

// Active-transaction flag is shared: only ONE of (32b SRAM_A, SRAM_FCW) runs
// at a time. fcw_txn diverts start/done to the FCW datapath below.
wire        a32_start = start && !fcw_txn;

assign addr_step  = read_en | write_en;
assign read_en    = txn_active && read_mode  && data_ready;
assign write_en   = txn_active && write_mode && pool_valid;
assign pool_ready_int = txn_active && write_mode;
assign data_last  = read_last_d & data_valid;
assign unused_pool_last = pool_last;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        read_last_d <= 1'b0;
    else
        read_last_d <= txn_done && read_en;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        txn_active <= 1'b0;
    else if (a32_start)
        txn_active <= (length != {ADDR_WIDTH{1'b0}}) && (read_mode || write_mode);
    else if (txn_done)
        txn_active <= 1'b0;
end

Addr_Gen #(
    .ADDR_WIDTH(ADDR_WIDTH)
) u_addr_gen (
    .clk(clk),
    .rst_n(rst_n),
    .start(a32_start),
    .enable(addr_step),
    .base_addr(base_addr),
    .length(length),
    .addr(addr),
    .done(txn_done)
);

// L2 DATA write interleave: pass0 writes even offsets, pass1 writes odd offsets.
wire l2_data_write = (layer_sel == 3'd2) && (data_sel == 2'd2) && write_mode;
wire [ADDR_WIDTH-1:0] counter_val = addr - base_addr;
wire [ADDR_WIDTH-1:0] addr_final  = l2_data_write
    ? (base_addr + {counter_val[ADDR_WIDTH-2:0], pass_id})
    : addr;

sram_A_wrapper #(
    .AW(ADDR_WIDTH)
) u_sram_A_wrapper (
    .clk(clk),
    .rst_n(rst_n),
    .write_en(write_en),
    .read_en(read_en),
    .addr(addr_final),
    .write_data(pool_data),
    .read_data(read_data),
    .read_valid(data_valid)
);

sram_A_controller #(
    .ADDR_WIDTH(ADDR_WIDTH)
) u_sram_A_controller(
    .layer_sel(layer_sel),
    .data_sel(data_sel),
    .pass_id(pass_id),
    .base_addr(base_addr),
    .length(length),
    .read_mode(read_mode),
    .write_mode(write_mode)
);

// ==================================================================
// SRAM_FCW dedicated 80b path (FC weight preload + inference read)
// ==================================================================

wire                        fcw_start   = start && fcw_txn;
reg                         fcw_active;
reg                         fcw_rd_mode;   // 1 = inference read, 0 = preload write

wire                        fcw_rd_done;
wire [FCW_ADDR_WIDTH-1:0]   fcw_rd_addr;
wire [FCW_ADDR_WIDTH-1:0]   fcw_rd_base = {FCW_ADDR_WIDTH{1'b0}};
wire [FCW_ADDR_WIDTH-1:0]   fcw_rd_len  = FCW_LEN[FCW_ADDR_WIDTH-1:0];

// Read-side enable: on inference, advance when adapter is ready.
wire fcw_read_en = fcw_active && fcw_rd_mode && fc_wt_ready;

// Read address generator
Addr_Gen #(
    .ADDR_WIDTH(FCW_ADDR_WIDTH)
) u_fcw_read_addr (
    .clk(clk),
    .rst_n(rst_n),
    .start(fcw_start && fcw_read_txn),
    .enable(fcw_read_en),
    .base_addr(fcw_rd_base),
    .length(fcw_rd_len),
    .addr(fcw_rd_addr),
    .done(fcw_rd_done)
);

// Track last flag for 80b reads: pulses in the cycle the registered data
// for the final FCW entry becomes valid on the wrapper output.
reg fcw_read_last_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        fcw_read_last_d <= 1'b0;
    else
        fcw_read_last_d <= fcw_rd_done && fcw_read_en;
end

// Preload path: fcw_preload_packer accepts 32b host words (from pool_data)
// and emits 80b writes to SRAM_FCW. Beat count is driven by length=864 from
// the controller, but we manage it locally here via pool_valid beats.
reg [9:0] fcw_pl_beat_cnt;  // up to 864 beats
wire      fcw_pl_en = fcw_active && !fcw_rd_mode && pool_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fcw_pl_beat_cnt <= 10'd0;
    end else if (fcw_start && fcw_preload_txn) begin
        fcw_pl_beat_cnt <= 10'd0;
    end else if (fcw_pl_en) begin
        fcw_pl_beat_cnt <= fcw_pl_beat_cnt + 10'd1;
    end
end

wire fcw_pl_done = fcw_active && !fcw_rd_mode && (fcw_pl_beat_cnt == 10'd863) && pool_valid;

// fcw_active tracks the FCW transaction
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        fcw_active <= 1'b0;
    else if (fcw_start)
        fcw_active <= 1'b1;
    else if (fcw_rd_done || fcw_pl_done)
        fcw_active <= 1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        fcw_rd_mode <= 1'b0;
    else if (fcw_start)
        fcw_rd_mode <= fcw_read_txn;
end

// Packer instance (only driven during preload)
wire                       packer_wea;
wire [FCW_ADDR_WIDTH-1:0]  packer_addr;
wire [FCW_DATA_WIDTH-1:0]  packer_dina;
wire                       packer_up_ready;

fcw_preload_packer #(
    .AW(FCW_ADDR_WIDTH),
    .DW(FCW_DATA_WIDTH)
) u_fcw_packer (
    .clk(clk),
    .rst_n(rst_n),
    .start(fcw_start && fcw_preload_txn),
    .up_valid(fcw_pl_en),
    .up_data(pool_data),
    .up_ready(packer_up_ready),
    .wea(packer_wea),
    .addra(packer_addr),
    .dina(packer_dina)
);

// SRAM_FCW access port: mux read vs. write
wire                       fcw_ena   = fcw_read_en | packer_wea;
wire                       fcw_wea   = packer_wea;
wire [FCW_ADDR_WIDTH-1:0]  fcw_addr  = packer_wea ? packer_addr : fcw_rd_addr;
wire [FCW_DATA_WIDTH-1:0]  fcw_dina  = packer_dina;

wire [FCW_DATA_WIDTH-1:0]  fcw_douta;
wire                       fcw_douta_valid;

sram_FCW_wrapper #(
    .AW(FCW_ADDR_WIDTH),
    .DW(FCW_DATA_WIDTH)
) u_sram_FCW (
    .clka(clk),
    .rsta(~rst_n),
    .ena(fcw_ena),
    .wea(fcw_wea),
    .addra(fcw_addr),
    .dina(fcw_dina),
    .douta(fcw_douta),
    .douta_valid(fcw_douta_valid)
);

assign fc_wt_read_data = fcw_douta;
assign fc_wt_valid     = fcw_douta_valid & fcw_rd_mode;
assign fc_wt_last      = fcw_read_last_d;

// ==================================================================
// Shared done / busy
// ==================================================================
assign busy      = txn_active | fcw_active;
// For FCW reads, use Addr_Gen.done pulse (fires on the last read enable) so
// done aligns with the existing 32b SRAM_A convention (done coincident with
// the last valid data beat being consumed).
wire fcw_done_pulse = fcw_active
                      ? (fcw_rd_mode ? fcw_rd_done : fcw_pl_done)
                      : 1'b0;
wire a32_write_done = write_en && txn_done;
wire a32_read_done  = read_mode && data_last;
assign done      = fcw_done_pulse
                   | (!fcw_active && (a32_write_done | a32_read_done));

// pool_ready: during non-FCW transactions behaves as before; during FCW
// preload the packer always accepts (up_ready=1) so we echo that through.
assign pool_ready = fcw_active
                    ? (!fcw_rd_mode ? packer_up_ready : 1'b0)
                    : pool_ready_int;

endmodule
