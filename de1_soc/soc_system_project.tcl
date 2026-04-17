# Generate Quartus project files for the DE1-SoC board.
#
# Adapted for CNN_ACC:
# - expects a generated Platform Designer system under soc_system/
# - expects a board-level top named soc_system_top in soc_system_top.sv
# - pulls in soc_system/synthesis/soc_system.qip
#
# Invoke as:
#   quartus_sh -t de1_soc/soc_system_project.tcl

set project "soc_system"

set systemVerilogSource "${project}_top.sv"
set qip "${project}/synthesis/${project}.qip"

project_new $project -overwrite

foreach {name value} {
    FAMILY "Cyclone V"
    DEVICE 5CSEMA5F31C6
    PROJECT_OUTPUT_DIRECTORY output_files
    CYCLONEII_RESERVE_NCEO_AFTER_CONFIGURATION "USE AS REGULAR IO"
    NUM_PARALLEL_PROCESSORS 4
} {
    set_global_assignment -name $name $value
}

set_global_assignment -name TOP_LEVEL_ENTITY "${project}_top"
set_global_assignment -name SYSTEMVERILOG_FILE $systemVerilogSource
set_global_assignment -name QIP_FILE $qip

# FPGA pin assignments
foreach {pin port} {
    PIN_AJ4 ADC_CS_N
    PIN_AK4 ADC_DIN
    PIN_AK3 ADC_DOUT
    PIN_AK2 ADC_SCLK

    PIN_K7 AUD_ADCDAT
    PIN_K8 AUD_ADCLRCK
    PIN_H7 AUD_BCLK
    PIN_J7 AUD_DACDAT
    PIN_H8 AUD_DACLRCK
    PIN_G7 AUD_XCK

    PIN_AA16 CLOCK2_50
    PIN_Y26 CLOCK3_50
    PIN_K14 CLOCK4_50
    PIN_AF14 CLOCK_50

    PIN_AK14 DRAM_ADDR[0]
    PIN_AH14 DRAM_ADDR[1]
    PIN_AG15 DRAM_ADDR[2]
    PIN_AE14 DRAM_ADDR[3]
    PIN_AB15 DRAM_ADDR[4]
    PIN_AC14 DRAM_ADDR[5]
    PIN_AD14 DRAM_ADDR[6]
    PIN_AF15 DRAM_ADDR[7]
    PIN_AH15 DRAM_ADDR[8]
    PIN_AG13 DRAM_ADDR[9]
    PIN_AG12 DRAM_ADDR[10]
    PIN_AH13 DRAM_ADDR[11]
    PIN_AJ14 DRAM_ADDR[12]
    PIN_AF13 DRAM_BA[0]
    PIN_AJ12 DRAM_BA[1]
    PIN_AF11 DRAM_CAS_N
    PIN_AK13 DRAM_CKE
    PIN_AH12 DRAM_CLK
    PIN_AG11 DRAM_CS_N
    PIN_AK6 DRAM_DQ[0]
    PIN_AJ7 DRAM_DQ[1]
    PIN_AK7 DRAM_DQ[2]
    PIN_AK8 DRAM_DQ[3]
    PIN_AK9 DRAM_DQ[4]
    PIN_AG10 DRAM_DQ[5]
    PIN_AK11 DRAM_DQ[6]
    PIN_AJ11 DRAM_DQ[7]
    PIN_AH10 DRAM_DQ[8]
    PIN_AJ10 DRAM_DQ[9]
    PIN_AJ9 DRAM_DQ[10]
    PIN_AH9 DRAM_DQ[11]
    PIN_AH8 DRAM_DQ[12]
    PIN_AH7 DRAM_DQ[13]
    PIN_AJ6 DRAM_DQ[14]
    PIN_AJ5 DRAM_DQ[15]
    PIN_AB13 DRAM_LDQM
    PIN_AE13 DRAM_RAS_N
    PIN_AK12 DRAM_UDQM
    PIN_AA13 DRAM_WE_N

    PIN_AA12 FAN_CTRL

    PIN_J12 FPGA_I2C_SCLK
    PIN_K12 FPGA_I2C_SDAT

    PIN_AE26 HEX0[0]
    PIN_AE27 HEX0[1]
    PIN_AE28 HEX0[2]
    PIN_AG27 HEX0[3]
    PIN_AF28 HEX0[4]
    PIN_AG28 HEX0[5]
    PIN_AH28 HEX0[6]

    PIN_AJ29 HEX1[0]
    PIN_AH29 HEX1[1]
    PIN_AH30 HEX1[2]
    PIN_AG30 HEX1[3]
    PIN_AF29 HEX1[4]
    PIN_AF30 HEX1[5]
    PIN_AD27 HEX1[6]

    PIN_AB23 HEX2[0]
    PIN_AE29 HEX2[1]
    PIN_AD29 HEX2[2]
    PIN_AC28 HEX2[3]
    PIN_AD30 HEX2[4]
    PIN_AC29 HEX2[5]
    PIN_AC30 HEX2[6]

    PIN_AD26 HEX3[0]
    PIN_AC27 HEX3[1]
    PIN_AD25 HEX3[2]
    PIN_AC25 HEX3[3]
    PIN_AB28 HEX3[4]
    PIN_AB25 HEX3[5]
    PIN_AB22 HEX3[6]

    PIN_AA24 HEX4[0]
    PIN_Y23 HEX4[1]
    PIN_Y24 HEX4[2]
    PIN_W22 HEX4[3]
    PIN_W24 HEX4[4]
    PIN_V23 HEX4[5]
    PIN_W25 HEX4[6]

    PIN_V25 HEX5[0]
    PIN_AA28 HEX5[1]
    PIN_Y27 HEX5[2]
    PIN_AB27 HEX5[3]
    PIN_AB26 HEX5[4]
    PIN_AA26 HEX5[5]
    PIN_AA25 HEX5[6]

    PIN_AA14 KEY[0]
    PIN_AA15 KEY[1]
    PIN_W15 KEY[2]
    PIN_Y16 KEY[3]

    PIN_V16 LEDR[0]
    PIN_W16 LEDR[1]
    PIN_V17 LEDR[2]
    PIN_V18 LEDR[3]
    PIN_W17 LEDR[4]
    PIN_W19 LEDR[5]
    PIN_Y19 LEDR[6]
    PIN_W20 LEDR[7]
    PIN_W21 LEDR[8]
    PIN_Y21 LEDR[9]

    PIN_AB12 SW[0]
    PIN_AC12 SW[1]
    PIN_AF9 SW[2]
    PIN_AF10 SW[3]
    PIN_AD11 SW[4]
    PIN_AD12 SW[5]
    PIN_AE11 SW[6]
    PIN_AC9 SW[7]
    PIN_AD10 SW[8]
    PIN_AE12 SW[9]
} {
    set_location_assignment $pin -to $port
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to $port
}

# HPS assignments: 3.3-V LVTTL pins
foreach port {
    HPS_CONV_USB_N
    HPS_ENET_GTX_CLK
    HPS_ENET_INT_N
    HPS_ENET_MDC
    HPS_ENET_MDIO
    HPS_ENET_RX_CLK
    HPS_ENET_RX_DATA[0]
    HPS_ENET_RX_DATA[1]
    HPS_ENET_RX_DATA[2]
    HPS_ENET_RX_DATA[3]
    HPS_ENET_RX_DV
    HPS_ENET_TX_DATA[0]
    HPS_ENET_TX_DATA[1]
    HPS_ENET_TX_DATA[2]
    HPS_ENET_TX_DATA[3]
    HPS_ENET_TX_EN
    HPS_GSENSOR_INT
    HPS_I2C1_SCLK
    HPS_I2C1_SDAT
    HPS_I2C2_SCLK
    HPS_I2C2_SDAT
    HPS_I2C_CONTROL
    HPS_KEY
    HPS_LED
    HPS_LTC_GPIO
    HPS_SD_CLK
    HPS_SD_CMD
    HPS_SD_DATA[0]
    HPS_SD_DATA[1]
    HPS_SD_DATA[2]
    HPS_SD_DATA[3]
    HPS_SPIM_CLK
    HPS_SPIM_MISO
    HPS_SPIM_MOSI
    HPS_SPIM_SS
    HPS_UART_RX
    HPS_UART_TX
    HPS_USB_CLKOUT
    HPS_USB_DATA[0]
    HPS_USB_DATA[1]
    HPS_USB_DATA[2]
    HPS_USB_DATA[3]
    HPS_USB_DATA[4]
    HPS_USB_DATA[5]
    HPS_USB_DATA[6]
    HPS_USB_DATA[7]
    HPS_USB_DIR
    HPS_USB_NXT
    HPS_USB_STP
} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to $port
}

set sdcFilename "${project}.sdc"
set_global_assignment -name SDC_FILE $sdcFilename

set sdcf [open $sdcFilename "w"]
puts $sdcf {
    foreach {clock port} {
        clock_50_1 CLOCK_50
        clock_50_2 CLOCK2_50
        clock_50_3 CLOCK3_50
        clock_50_4 CLOCK4_50
    } {
        create_clock -name $clock -period 20ns [get_ports $port]
    }

    derive_pll_clocks -create_base_clocks
    derive_clock_uncertainty
}
close $sdcf

project_close
