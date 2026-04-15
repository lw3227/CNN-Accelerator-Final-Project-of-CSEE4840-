`timescale 1ns/1ps

// fcw_preload_packer: pack three 32-bit host words into one 80-bit FCW write.
//
// Host preload stream carries FC weights at 32b/word. Each FCW slot holds
// 10 kernels x 8b = 80b. The packer consumes 3 host words per FCW slot:
//   word0 bits[31:0]  -> fcw_word[31:0]   = {k3, k2, k1, k0}
//   word1 bits[31:0]  -> fcw_word[63:32]  = {k7, k6, k5, k4}
//   word2 bits[15:0]  -> fcw_word[79:64]  = {k9, k8}    (upper 16b ignored)
//
// On the third beat the packer emits a single wea pulse at the current
// FCW address, then advances the address. 'start' resets the address
// counter and phase counter.

module fcw_preload_packer # (
    parameter AW = 9,
    parameter DW = 80
) (
    input              clk,
    input              rst_n,

    input              start,         // resets address/phase counters

    // 32b host preload stream
    input              up_valid,
    input      [31:0]  up_data,
    output             up_ready,

    // 80b write port to sram_FCW_wrapper
    output                 wea,
    output     [AW-1:0]    addra,
    output     [DW-1:0]    dina
);
    reg  [1:0]     phase;
    reg  [AW-1:0]  wr_cnt;
    reg  [31:0]    word0_r;
    reg  [31:0]    word1_r;

    wire fire = up_valid && up_ready;

    assign up_ready = 1'b1;

    // Combinationally emit wea on the cycle the third host word arrives.
    assign wea   = fire && (phase == 2'd2);
    assign addra = wr_cnt;
    assign dina  = {up_data[15:0], word1_r, word0_r};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase   <= 2'd0;
            wr_cnt  <= {AW{1'b0}};
            word0_r <= 32'd0;
            word1_r <= 32'd0;
        end else if (start) begin
            phase  <= 2'd0;
            wr_cnt <= {AW{1'b0}};
        end else if (fire) begin
            case (phase)
                2'd0: begin
                    word0_r <= up_data;
                    phase   <= 2'd1;
                end
                2'd1: begin
                    word1_r <= up_data;
                    phase   <= 2'd2;
                end
                2'd2: begin
                    phase  <= 2'd0;
                    wr_cnt <= wr_cnt + {{(AW-1){1'b0}}, 1'b1};
                end
                default: phase <= 2'd0;
            endcase
        end
    end

endmodule
