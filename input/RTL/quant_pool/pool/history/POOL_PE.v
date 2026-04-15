// whole POOL pipeline is triggered by en signal, en sent from FSM, comes with first cut data at
// the same cycle.
module POOL_pipeline_PE(
    input         clk, rst_n,
    input         shift_en,
    input         shift_finish,
    input signed [7:0]  cut,
    input         en,
    output reg    waitt,
    output reg signed [7:0] byte_out
);
    reg              cnt1;
    reg              next_cnt1;
    reg        [4:0] cnt2;
    reg        [4:0] next_cnt2;
    reg              cnt3;
    reg              next_cnt3;
    reg              next_waitt;
    reg signed [7:0] POOL_REG [0:30];
    reg signed [7:0] NEXT_POOL_REG;
    wire signed [7:0] data;

    integer i, i2;

    // cnt1 signal genrator
    always @* begin
        if (en) next_cnt1 = ~ cnt1;
        else next_cnt1 = 1'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt1 <= 1'd0;
        else cnt1 <= next_cnt1;
    end

    // cnt2 & cnt3 signals generators
    always @* begin
        if (cnt1 == 1'd1) begin 
            if (cnt2 != 5'd30) begin
                next_cnt2 = cnt2 + 5'd1;
                next_cnt3 = cnt3;
            end
            else begin
                next_cnt2 = 5'd0;
                next_cnt3 = ~ cnt3;
            end
        end
        else begin
            next_cnt2 = cnt2;
            next_cnt3 = cnt3;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt2 <= 5'd0;
            cnt3 <= 1'd0;
        end
        else begin
            cnt2 <= next_cnt2;
            cnt3 <= next_cnt3;
        end
    end
    // wait control signal generator
    always @* begin
        if (shift_finish) begin
            next_waitt = 1'd0;
        end
        else begin 
            if (cnt1 == 1'd1 && cnt2 == 5'd30 && cnt3 == 1'd1) next_waitt = 1'd1;
            else if (cnt1 == 1'd0 && cnt2 == 5'd0 && cnt3 == 1'd0) next_waitt = waitt;
            else next_waitt = 1'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) waitt <= 1'd0;
        else waitt <= next_waitt;
    end

    // combinational circuits
    // en selection, en is high only if cut1 is ready.
    assign data = en ? cut : - 8'sd128;

    // cnt1, cnt2, cnt3, wait controled operation types.
    always @* begin
        if (waitt) begin
        NEXT_POOL_REG = POOL_REG[cnt2];
        end 
        else begin
            if (cnt3) NEXT_POOL_REG = (data > POOL_REG[cnt2]) ? data : POOL_REG[cnt2];
            else begin
                if (cnt1) NEXT_POOL_REG = (data > POOL_REG[cnt2]) ? data : POOL_REG[cnt2];
                else NEXT_POOL_REG = data;
            end
        end
    end

    // sequantial circuits
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_out <= 8'sd0;
            for (i = 0 ; i < 31 ; i = i + 1) begin
                POOL_REG[i] <= 8'sd0;
            end
        end
        else begin
            if (shift_en) begin
                byte_out <= POOL_REG[0];
                for (i2 = 0 ; i2 < 30 ; i2 = i2 + 1) begin
                    POOL_REG[i2] <= POOL_REG[i2 + 1];
                end
                POOL_REG[30] <= 8'sd0;
            end
            else begin
                POOL_REG[cnt2] <= NEXT_POOL_REG;
            end
        end
    end

endmodule
