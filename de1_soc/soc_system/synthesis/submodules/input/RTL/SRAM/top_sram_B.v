module top_sram_B(
    input clk,
    input rst_n,

    input [2:0] layer_sel,
    input [1:0] data_sel,
    input       pass_id,
    input       start,
    output      busy,
    output      done,

    // Read path from SRAM_B to conv / FC pipeline.
    input         data_ready,
    output [31:0] read_data,
    output        data_valid,
    output        data_last,

    // Write path from pool pipeline back to SRAM_B.
    output               pool_ready,
    input signed [31:0]  pool_data,
    input                pool_valid,
    input                pool_last
);

wire [9:0] addr;
wire [9:0] base_addr;
wire [9:0] length;
wire       read_mode;
wire       write_mode;
wire       read_en;
wire       write_en;
wire       addr_step;
wire       txn_done;
wire       pool_ready_int;
wire       unused_pool_last;
wire       fc_data_read;
wire [9:0] counter_val;
wire [9:0] addr_final;

reg        read_last_d;
reg        txn_active;

assign addr_step       = read_en | write_en;
assign busy            = txn_active;
assign done            = read_mode ? data_last : (write_en && txn_done);
assign pool_ready      = pool_ready_int;
assign data_last       = read_last_d & data_valid;
assign unused_pool_last = pool_last;
assign read_en         = txn_active && read_mode  && data_ready;
assign write_en        = txn_active && write_mode && pool_valid;
assign pool_ready_int  = txn_active && write_mode;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        read_last_d <= 1'b0;
    else
        read_last_d <= txn_done && read_en;
end

// Assumes the FSM holds layer_sel / data_sel / pass_id stable until txn_done.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        txn_active <= 1'b0;
    else if (start)
        txn_active <= (length != 10'd0) && (read_mode || write_mode);
    else if (txn_done)
        txn_active <= 1'b0;
end

Addr_Gen #(
    .ADDR_WIDTH(10)
) u_addr_gen (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .enable(addr_step),
    .base_addr(base_addr),
    .length(length),
    .addr(addr),
    .done(txn_done)
);

// FC DATA read interleave:
// L3 writes SRAM_B as pass0[0..35] followed by pass1[0..35].
// FC expects per-position 8-channel order, so reads must be:
//   0, 36, 1, 37, 2, 38, ...
wire [9:0] fc_pair_idx    = {1'b0, counter_val[9:1]};
wire [9:0] fc_half_offset = counter_val[0] ? 10'd36 : 10'd0;
assign fc_data_read = (layer_sel == 3'd4) && (data_sel == 2'd2) && read_mode;
assign counter_val  = addr - base_addr;
assign addr_final   = fc_data_read ? (base_addr + fc_pair_idx + fc_half_offset)
                                   : addr;

sram_B_wrapper #(
    .AW(10)
) u_sram_B_wrapper (
    .clk(clk),
    .rst_n(rst_n),
    .write_en(write_en),
    .read_en(read_en),
    .addr(addr_final),
    .write_data(pool_data),
    .read_data(read_data),
    .read_valid(data_valid)
);

sram_B_controller u_sram_B_controller(
    .layer_sel(layer_sel),
    .data_sel(data_sel),
    .pass_id(pass_id),
    .base_addr(base_addr),
    .length(length),
    .read_mode(read_mode),
    .write_mode(write_mode)
);

endmodule