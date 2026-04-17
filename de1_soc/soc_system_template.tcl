package require -exact qsys 18.0

# soc_system_template.tcl
# -----------------------
# Creates a minimal DE1-SoC style Platform Designer system from scratch:
#   - HPS enabled with the lightweight HPS-to-FPGA master bridge
#   - cnn_mmio_interface connected as an Avalon slave
#   - HPS DDR memory interface exported
#
# Usage:
#   qsys-script \
#     --search-path="$(pwd)/platform_designer/ip_index,$" \
#     --script=de1_soc/soc_system_template.tcl
#
# Notes:
# - Generate the custom component index first:
#     ip-make-ipx --source-directory=platform_designer \
#       --output=platform_designer/ip_index/components.ipx
# - This script intentionally stays minimal and does not attempt to apply a
#   full board preset for HPS pin muxing. It focuses on the bridge + accelerator
#   integration path needed for MMIO access from HPS software.

set system_name "soc_system"
set output_file "de1_soc/${system_name}.qsys"
set cnn_inst "cnn_mmio_0"
set hps_inst "hps_0"
set lw_bridge_base "0x0000"

create_system $system_name
set_project_property DEVICE_FAMILY {"Cyclone V"}
set_project_property DEVICE {5CSEMA5F31C6}

add_instance $hps_inst altera_hps
set_instance_parameter_value $hps_inst LWH2F_Enable true

add_instance $cnn_inst cnn_mmio_interface

add_connection ${hps_inst}.h2f_lw_axi_master ${cnn_inst}.avalon_slave
set_connection_parameter_value ${hps_inst}.h2f_lw_axi_master/${cnn_inst}.avalon_slave baseAddress $lw_bridge_base

add_connection ${hps_inst}.h2f_lw_axi_clock ${cnn_inst}.clock
add_connection ${hps_inst}.h2f_reset ${cnn_inst}.reset

# Export the HPS DDR memory interface so the generated system can be wrapped
# into a board-level top later.
add_interface memory conduit end
set_interface_property memory EXPORT_OF ${hps_inst}.memory

save_system $output_file
