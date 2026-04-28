module soc_system_top (
    input  wire        CLOCK_50,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    input  wire        HPS_UART_RX,
    output wire        HPS_UART_TX,
    output wire        HPS_SD_CLK,
    inout  wire        HPS_SD_CMD,
    inout  wire [3:0]  HPS_SD_DATA,
    inout  wire        HPS_I2C1_SCLK,
    inout  wire        HPS_I2C1_SDAT,
    inout  wire        HPS_I2C2_SCLK,
    inout  wire        HPS_I2C2_SDAT,
    inout  wire        HPS_I2C_CONTROL,
    output wire        HPS_ENET_GTX_CLK,
    inout  wire        HPS_ENET_INT_N,
    output wire        HPS_ENET_MDC,
    inout  wire        HPS_ENET_MDIO,
    input  wire        HPS_ENET_RX_CLK,
    input  wire [3:0]  HPS_ENET_RX_DATA,
    input  wire        HPS_ENET_RX_DV,
    output wire [3:0]  HPS_ENET_TX_DATA,
    output wire        HPS_ENET_TX_EN,
    output wire        HPS_SPIM_CLK,
    input  wire        HPS_SPIM_MISO,
    output wire        HPS_SPIM_MOSI,
    inout  wire        HPS_SPIM_SS,
    input  wire        HPS_USB_CLKOUT,
    inout  wire [7:0]  HPS_USB_DATA,
    input  wire        HPS_USB_DIR,
    input  wire        HPS_USB_NXT,
    output wire        HPS_USB_STP,
    inout  wire        HPS_CONV_USB_N,
    inout  wire        HPS_GSENSOR_INT,
    inout  wire        HPS_KEY,
    inout  wire        HPS_LED,
    inout  wire        HPS_LTC_GPIO,

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
    wire [3:0] predict_class_dbg;
    wire       predict_done_dbg;
    wire       model_loaded_dbg;
    wire [15:0] interface_error_dbg;

    localparam [6:0] SEVEN_SEG_BLANK = 7'b1111111;

    function automatic [6:0] seven_seg_decode;
        input [3:0] value;
        begin
            case (value)
                4'h0: seven_seg_decode = 7'b1000000;
                4'h1: seven_seg_decode = 7'b1111001;
                4'h2: seven_seg_decode = 7'b0100100;
                4'h3: seven_seg_decode = 7'b0110000;
                4'h4: seven_seg_decode = 7'b0011001;
                4'h5: seven_seg_decode = 7'b0010010;
                4'h6: seven_seg_decode = 7'b0000010;
                4'h7: seven_seg_decode = 7'b1111000;
                4'h8: seven_seg_decode = 7'b0000000;
                4'h9: seven_seg_decode = 7'b0010000;
                4'hA: seven_seg_decode = 7'b0001000; // A
                4'hB: seven_seg_decode = 7'b0000011; // b
                4'hC: seven_seg_decode = 7'b1000110; // C
                4'hD: seven_seg_decode = 7'b0100001; // d
                4'hE: seven_seg_decode = 7'b0000110; // E
                default: seven_seg_decode = SEVEN_SEG_BLANK;
            endcase
        end
    endfunction

    soc_system u_soc_system (
        .clk_clk            (CLOCK_50),
        .cnn_debug_model_loaded(model_loaded_dbg),
        .cnn_debug_predict_done(predict_done_dbg),
        .cnn_debug_predict_class(predict_class_dbg),
        .cnn_debug_interface_error(interface_error_dbg),
        .reset_reset_n      (1'b1),
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
        .memory_oct_rzqin   (HPS_DDR3_RZQ),
        .hps_hps_io_emac1_inst_TX_CLK (HPS_ENET_GTX_CLK),
        .hps_hps_io_emac1_inst_TXD0   (HPS_ENET_TX_DATA[0]),
        .hps_hps_io_emac1_inst_TXD1   (HPS_ENET_TX_DATA[1]),
        .hps_hps_io_emac1_inst_TXD2   (HPS_ENET_TX_DATA[2]),
        .hps_hps_io_emac1_inst_TXD3   (HPS_ENET_TX_DATA[3]),
        .hps_hps_io_emac1_inst_RXD0   (HPS_ENET_RX_DATA[0]),
        .hps_hps_io_emac1_inst_MDIO   (HPS_ENET_MDIO),
        .hps_hps_io_emac1_inst_MDC    (HPS_ENET_MDC),
        .hps_hps_io_emac1_inst_RX_CTL (HPS_ENET_RX_DV),
        .hps_hps_io_emac1_inst_TX_CTL (HPS_ENET_TX_EN),
        .hps_hps_io_emac1_inst_RX_CLK (HPS_ENET_RX_CLK),
        .hps_hps_io_emac1_inst_RXD1   (HPS_ENET_RX_DATA[1]),
        .hps_hps_io_emac1_inst_RXD2   (HPS_ENET_RX_DATA[2]),
        .hps_hps_io_emac1_inst_RXD3   (HPS_ENET_RX_DATA[3]),
        .hps_hps_io_sdio_inst_CMD     (HPS_SD_CMD),
        .hps_hps_io_sdio_inst_D0      (HPS_SD_DATA[0]),
        .hps_hps_io_sdio_inst_D1      (HPS_SD_DATA[1]),
        .hps_hps_io_sdio_inst_CLK     (HPS_SD_CLK),
        .hps_hps_io_sdio_inst_D2      (HPS_SD_DATA[2]),
        .hps_hps_io_sdio_inst_D3      (HPS_SD_DATA[3]),
        .hps_hps_io_usb1_inst_D0      (HPS_USB_DATA[0]),
        .hps_hps_io_usb1_inst_D1      (HPS_USB_DATA[1]),
        .hps_hps_io_usb1_inst_D2      (HPS_USB_DATA[2]),
        .hps_hps_io_usb1_inst_D3      (HPS_USB_DATA[3]),
        .hps_hps_io_usb1_inst_D4      (HPS_USB_DATA[4]),
        .hps_hps_io_usb1_inst_D5      (HPS_USB_DATA[5]),
        .hps_hps_io_usb1_inst_D6      (HPS_USB_DATA[6]),
        .hps_hps_io_usb1_inst_D7      (HPS_USB_DATA[7]),
        .hps_hps_io_usb1_inst_CLK     (HPS_USB_CLKOUT),
        .hps_hps_io_usb1_inst_STP     (HPS_USB_STP),
        .hps_hps_io_usb1_inst_DIR     (HPS_USB_DIR),
        .hps_hps_io_usb1_inst_NXT     (HPS_USB_NXT),
        .hps_hps_io_spim1_inst_CLK    (HPS_SPIM_CLK),
        .hps_hps_io_spim1_inst_MOSI   (HPS_SPIM_MOSI),
        .hps_hps_io_spim1_inst_MISO   (HPS_SPIM_MISO),
        .hps_hps_io_spim1_inst_SS0    (HPS_SPIM_SS),
        .hps_hps_io_uart0_inst_RX     (HPS_UART_RX),
        .hps_hps_io_uart0_inst_TX     (HPS_UART_TX),
        .hps_hps_io_i2c0_inst_SDA     (HPS_I2C1_SDAT),
        .hps_hps_io_i2c0_inst_SCL     (HPS_I2C1_SCLK),
        .hps_hps_io_i2c1_inst_SDA     (HPS_I2C2_SDAT),
        .hps_hps_io_i2c1_inst_SCL     (HPS_I2C2_SCLK),
        .hps_hps_io_gpio_inst_GPIO09  (HPS_CONV_USB_N),
        .hps_hps_io_gpio_inst_GPIO35  (HPS_ENET_INT_N),
        .hps_hps_io_gpio_inst_GPIO40  (HPS_LTC_GPIO),
        .hps_hps_io_gpio_inst_GPIO48  (HPS_I2C_CONTROL),
        .hps_hps_io_gpio_inst_GPIO53  (HPS_LED),
        .hps_hps_io_gpio_inst_GPIO54  (HPS_KEY),
        .hps_hps_io_gpio_inst_GPIO61  (HPS_GSENSOR_INT)
    );

    // Current seven-segment policy:
    // - HEX0 shows the predicted class once predict_done is asserted
    // - HEX1 shows model_loaded / predict_done as two debug bits
    // - HEX2 shows the low nibble of interface_error when non-zero
    // - HEX3/HEX4 stay blank
    // - HEX5 shows "E" only when an interface error is latched
    assign HEX0 = predict_done_dbg ? seven_seg_decode(predict_class_dbg) : SEVEN_SEG_BLANK;
    assign HEX1 = seven_seg_decode({2'b00, model_loaded_dbg, predict_done_dbg});
    assign HEX2 = (interface_error_dbg != 16'h0000) ? seven_seg_decode(interface_error_dbg[3:0]) : SEVEN_SEG_BLANK;
    assign HEX3 = SEVEN_SEG_BLANK;
    assign HEX4 = SEVEN_SEG_BLANK;
    assign HEX5 = (interface_error_dbg != 16'h0000) ? seven_seg_decode(4'hE) : SEVEN_SEG_BLANK;

endmodule
