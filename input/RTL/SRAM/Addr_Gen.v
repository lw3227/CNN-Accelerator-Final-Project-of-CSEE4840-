module Addr_Gen #(
    parameter ADDR_WIDTH = 11
)(
    input  clk,
    input  rst_n,

    input  start,                     
    input  enable,    
    input  [ADDR_WIDTH-1:0] base_addr,
    input  [ADDR_WIDTH-1:0] length,

    output [ADDR_WIDTH-1:0] addr,
    output done
);

    // ----------------------------------------
    // Internal Registers
    // ----------------------------------------
    reg [ADDR_WIDTH-1:0] counter;
    reg                  running;

    // ----------------------------------------
    // Running Control
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            running <= 1'b0;
        else if (start)
            running <= 1'b1;
        else if (done)
            running <= 1'b0;
    end

    // ----------------------------------------
    // Counter
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            counter <= {ADDR_WIDTH{1'b0}};
        else if (start)
            counter <= {ADDR_WIDTH{1'b0}};
        else if (running && enable && !done)
            counter <= counter + 1'b1;
    end

    // ----------------------------------------
    // Combinational Outputs
    // ----------------------------------------
    assign addr = base_addr + counter;

    assign done = running && enable &&
                  (counter == (length - 1'b1));

endmodule
