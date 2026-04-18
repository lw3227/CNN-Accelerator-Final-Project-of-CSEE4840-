# Generate Quartus project files for the DE1-SoC board.
#
# Adapted for CNN_ACC:
# - expects a generated Platform Designer system under soc_system/
# - expects a board-level top named soc_system_top in soc_system_top.sv
# - pulls in soc_system/synthesis/soc_system.qip
#
# Invoke as:
#   quartus_sh -t de1_soc/soc_system_project.tcl

set script_dir [file dirname [file normalize [info script]]]
set project_name "soc_system"
set project_path [file join $script_dir $project_name]

set systemVerilogSource [file join $script_dir "${project_name}_top.sv"]
set qip [file join $script_dir $project_name "synthesis" "${project_name}.qip"]

project_new $project_path -overwrite

# Clean out any stale assignments from previous iterations of this project.
foreach stale_file {
    "input/SRAM_macro/sram_A/sram_A.v"
    "input/SRAM_macro/sram_B/sram_B.v"
    "/homes/user/stud/fall25/lw3227/CNN_ACC/input/SRAM_macro/sram_A/sram_A.v"
    "/homes/user/stud/fall25/lw3227/CNN_ACC/input/SRAM_macro/sram_B/sram_B.v"
} {
    catch { remove_global_assignment -name VERILOG_FILE $stale_file }
}

foreach {name value} {
    FAMILY "Cyclone V"
    DEVICE 5CSEMA5F31C6
    PROJECT_OUTPUT_DIRECTORY output_files
    CYCLONEII_RESERVE_NCEO_AFTER_CONFIGURATION "USE AS REGULAR IO"
    NUM_PARALLEL_PROCESSORS 4
} {
    set_global_assignment -name $name $value
}

set_global_assignment -name TOP_LEVEL_ENTITY "${project_name}_top"
set_global_assignment -name SYSTEMVERILOG_FILE $systemVerilogSource
set_global_assignment -name QIP_FILE $qip
# Match the original Quartus project: use synthesizable behavioral SRAM
# models instead of the foundry macro models, which contain sim-only code.
set_global_assignment -name VERILOG_FILE [file join [file dirname $script_dir] "input" "TB" "sram_behav.v"]

# Minimal board-level assignment set for the generated HPS/MMIO system.
# Follow the lab3-hw pattern: export the HPS DDR3 interface using the board-
# level HPS_DDR3_* port names and let the generated HPS SDRAM assignment Tcl
# handle the dedicated DDR3 pin standards/termination.
set_location_assignment PIN_AF14 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

set sdcFilename [file join $script_dir "${project_name}.sdc"]
set_global_assignment -name SDC_FILE $sdcFilename

set sdcf [open $sdcFilename "w"]
puts $sdcf {
    create_clock -name clock_50 -period 20ns [get_ports CLOCK_50]
    derive_pll_clocks -create_base_clocks
    derive_clock_uncertainty
}
close $sdcf

project_close
