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

localparam [2:0] LAYER_L3  = 3'd3;
localparam [2:0] LAYER_FC  = 3'd4;
localparam [1:0] SEL_DATA  = 2'd2;
localparam integer FC_BUF_AW = 7;   // 2^7 = 128 >= 72 words
localparam [5:0] FC_PASS_LEN = 6'd36;
localparam [6:0] FC_FULL_LEN = 7'd72;

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
wire [31:0] main_read_data;
wire        main_data_valid;
wire        main_data_last;

reg        read_last_d;
reg        txn_active;

// L3 output -> FC input reorder buffer.
// Instead of storing pass0[0..35], pass1[0..35] and fixing the order on the
// FC read side, write pass0 to even addresses and pass1 to odd addresses.
// This trades a little extra BRAM for a simpler FC read path.
wire fc_buf_write_mirror = (layer_sel == LAYER_L3) && (data_sel == SEL_DATA) && write_mode;
wire fc_buf_read_txn     = (layer_sel == LAYER_FC) && (data_sel == SEL_DATA) && read_mode;
wire main_start          = start && !fc_buf_read_txn;

assign addr_step        = read_en | write_en;
assign unused_pool_last = pool_last;
assign read_en          = txn_active && read_mode  && data_ready;
assign write_en         = txn_active && write_mode && pool_valid;
assign pool_ready_int  = txn_active && write_mode;
assign main_data_last  = read_last_d & main_data_valid;

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
    else if (main_start)
        txn_active <= (length != 10'd0) && (read_mode || write_mode);
    else if (txn_done)
        txn_active <= 1'b0;
end

Addr_Gen #(
    .ADDR_WIDTH(10)
) u_addr_gen (
    .clk(clk),
    .rst_n(rst_n),
    .start(main_start),
    .enable(addr_step),
    .base_addr(base_addr),
    .length(length),
    .addr(addr),
    .done(txn_done)
);

sram_B_wrapper #(
    .AW(10)
) u_sram_B_wrapper (
    .clk(clk),
    .rst_n(rst_n),
    .write_en(write_en),
    .read_en(read_en),
    .addr(addr),
    .write_data(pool_data),
    .read_data(main_read_data),
    .read_valid(main_data_valid)
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

// Dedicated FC-order buffer. L3 still writes the original SRAM_B path; we
// mirror those writes into a second BRAM organized for FC sequential reads.
// pass0 writes even slots, pass1 writes odd slots, so FC can read 0..71
// with no address interleave logic.
(* ramstyle = "M10K" *)
reg [31:0] fc_input_mem [0:(1<<FC_BUF_AW)-1];

reg        fc_buf_rd_active;
reg [6:0]  fc_buf_rd_count;
reg [31:0] fc_buf_read_data_q;
reg        fc_buf_data_valid_q;
reg        fc_buf_read_last_d;

wire [9:0] counter_val = addr - base_addr;
wire       fc_buf_write_en = write_en && fc_buf_write_mirror;
wire       fc_buf_read_en  = fc_buf_rd_active && data_ready;
wire [6:0] fc_buf_wr_addr  = {counter_val[5:0], 1'b0} + pass_id;
wire       fc_buf_rd_done  = fc_buf_read_en  && (fc_buf_rd_count == (FC_FULL_LEN - 1'b1));
wire       fc_buf_data_last = fc_buf_data_valid_q && fc_buf_read_last_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fc_buf_rd_active    <= 1'b0;
        fc_buf_rd_count     <= 7'd0;
        fc_buf_read_data_q  <= 32'd0;
        fc_buf_data_valid_q <= 1'b0;
        fc_buf_read_last_d  <= 1'b0;
    end else begin
        fc_buf_data_valid_q <= 1'b0;
        fc_buf_read_last_d  <= 1'b0;

        if (fc_buf_write_en)
            fc_input_mem[fc_buf_wr_addr] <= pool_data;

        if (start && fc_buf_read_txn) begin
            fc_buf_rd_active    <= 1'b1;
            fc_buf_rd_count     <= 7'd0;
        end else if (fc_buf_read_en) begin
            fc_buf_read_data_q  <= fc_input_mem[fc_buf_rd_count];
            fc_buf_data_valid_q <= 1'b1;
            fc_buf_read_last_d  <= fc_buf_rd_done;
            if (fc_buf_rd_done)
                fc_buf_rd_active <= 1'b0;
            else
                fc_buf_rd_count <= fc_buf_rd_count + 7'd1;
        end
    end
end

assign busy       = fc_buf_read_txn ? fc_buf_rd_active : txn_active;
assign done       = fc_buf_read_txn ? fc_buf_data_last
                                    : (read_mode ? main_data_last : (write_en && txn_done));
assign pool_ready = pool_ready_int;
assign read_data  = fc_buf_read_txn ? fc_buf_read_data_q : main_read_data;
assign data_valid = fc_buf_read_txn ? fc_buf_data_valid_q : main_data_valid;
assign data_last  = fc_buf_read_txn ? fc_buf_data_last : main_data_last;

endmodule
