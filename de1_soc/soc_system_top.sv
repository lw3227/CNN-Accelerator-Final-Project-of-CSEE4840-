module soc_system_top (
    input  wire        CLOCK_50,

    output wire [14:0] HPS_DDR3_ADDR,
    output wire [2:0]  HPS_DDR3_BA,
    output wire        HPS_DDR3_CAS_N,
    output wire        HPS_DDR3_CKE,
    output wire        HPS_DDR3_CK_N,
    output wire        HPS_DDR3_CK_P,
    output wire        HPS_DDR3_CS_N,
    output wire [3:0]  HPS_DDR3_DM,
    inout  wire [31:0] HPS_DDR3_DQ,
    inout  wire [3:0]  HPS_DDR3_DQS_N,
    inout  wire [3:0]  HPS_DDR3_DQS_P,
    output wire        HPS_DDR3_ODT,
    output wire        HPS_DDR3_RAS_N,
    output wire        HPS_DDR3_RESET_N,
    input  wire        HPS_DDR3_RZQ,
    output wire        HPS_DDR3_WE_N
);

    soc_system u_soc_system (
        .clk_clk            (CLOCK_50),
        .memory_mem_a       (HPS_DDR3_ADDR),
        .memory_mem_ba      (HPS_DDR3_BA),
        .memory_mem_ck      (HPS_DDR3_CK_P),
        .memory_mem_ck_n    (HPS_DDR3_CK_N),
        .memory_mem_cke     (HPS_DDR3_CKE),
        .memory_mem_cs_n    (HPS_DDR3_CS_N),
        .memory_mem_ras_n   (HPS_DDR3_RAS_N),
        .memory_mem_cas_n   (HPS_DDR3_CAS_N),
        .memory_mem_we_n    (HPS_DDR3_WE_N),
        .memory_mem_reset_n (HPS_DDR3_RESET_N),
        .memory_mem_dq      (HPS_DDR3_DQ),
        .memory_mem_dqs     (HPS_DDR3_DQS_P),
        .memory_mem_dqs_n   (HPS_DDR3_DQS_N),
        .memory_mem_odt     (HPS_DDR3_ODT),
        .memory_mem_dm      (HPS_DDR3_DM),
        .memory_oct_rzqin   (HPS_DDR3_RZQ)
    );

endmodule
