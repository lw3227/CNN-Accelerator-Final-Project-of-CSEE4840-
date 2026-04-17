# TCL File adapted for Component Editor / Platform Designer 21.1
#
# cnn_mmio_interface "cnn_mmio_interface" v1.0

package require -exact qsys 16.1

# ----------------------------------------------------------------------
# module cnn_mmio_interface
# ----------------------------------------------------------------------
set_module_property DESCRIPTION "Memory-mapped wrapper for the CNN_ACC gesture accelerator"
set_module_property NAME cnn_mmio_interface
set_module_property VERSION 1.0
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property AUTHOR ""
set_module_property DISPLAY_NAME cnn_mmio_interface
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false

# ----------------------------------------------------------------------
# file sets
# ----------------------------------------------------------------------
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL cnn_mmio_interface
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file input/RTL/interface/cnn_mmio_interface.v VERILOG PATH input/RTL/interface/cnn_mmio_interface.v TOP_LEVEL_FILE
add_fileset_file input/RTL/system_top.v VERILOG PATH input/RTL/system_top.v
add_fileset_file input/RTL/fsm/top_fsm.v VERILOG PATH input/RTL/fsm/top_fsm.v
add_fileset_file input/RTL/fsm/layer_runner_fsm.v VERILOG PATH input/RTL/fsm/layer_runner_fsm.v
add_fileset_file input/RTL/fsm/conv_data_adapter.v VERILOG PATH input/RTL/fsm/conv_data_adapter.v
add_fileset_file input/RTL/fsm/wt_prepad_inserter.v VERILOG PATH input/RTL/fsm/wt_prepad_inserter.v
add_fileset_file input/RTL/conv_core/conv_quant_pool.v VERILOG PATH input/RTL/conv_core/conv_quant_pool.v
add_fileset_file input/RTL/conv_core/conv_top.v VERILOG PATH input/RTL/conv_core/conv_top.v
add_fileset_file input/RTL/conv_core/conv_engine_ctrl.v VERILOG PATH input/RTL/conv_core/conv_engine_ctrl.v
add_fileset_file input/RTL/conv_core/weight_buffer.v VERILOG PATH input/RTL/conv_core/weight_buffer.v
add_fileset_file input/RTL/conv_core/Line_Buffer.v VERILOG PATH input/RTL/conv_core/Line_Buffer.v
add_fileset_file input/RTL/conv_core/input_row_aligner.v VERILOG PATH input/RTL/conv_core/input_row_aligner.v
add_fileset_file input/RTL/conv_core/Conv_Buffer.v VERILOG PATH input/RTL/conv_core/Conv_Buffer.v
add_fileset_file input/RTL/conv_core/sa_skew_feeder.v VERILOG PATH input/RTL/conv_core/sa_skew_feeder.v
add_fileset_file input/RTL/conv_core/systolic_array_top.v VERILOG PATH input/RTL/conv_core/systolic_array_top.v
add_fileset_file input/RTL/quant_pool/integration/quant_param_loader.v VERILOG PATH input/RTL/quant_pool/integration/quant_param_loader.v
add_fileset_file input/RTL/quant_pool/integration/conv_quant_adapter.v VERILOG PATH input/RTL/quant_pool/integration/conv_quant_adapter.v
add_fileset_file input/RTL/quant_pool/integration/quant_pool_adapter.v VERILOG PATH input/RTL/quant_pool/integration/quant_pool_adapter.v
add_fileset_file input/RTL/quant_pool/quant/Quantization_PE.v VERILOG PATH input/RTL/quant_pool/quant/Quantization_PE.v
add_fileset_file input/RTL/quant_pool/quant/Quantization_Top.v VERILOG PATH input/RTL/quant_pool/quant/Quantization_Top.v
add_fileset_file input/RTL/quant_pool/pool/pool_core.v VERILOG PATH input/RTL/quant_pool/pool/pool_core.v
add_fileset_file input/RTL/quant_pool/pool/pool_stream_top.v VERILOG PATH input/RTL/quant_pool/pool/pool_stream_top.v
add_fileset_file input/RTL/fc/mac.v VERILOG PATH input/RTL/fc/mac.v
add_fileset_file input/RTL/fc/fc_bias_loader.v VERILOG PATH input/RTL/fc/fc_bias_loader.v
add_fileset_file input/RTL/fc/fc_data_adapter.v VERILOG PATH input/RTL/fc/fc_data_adapter.v
add_fileset_file input/RTL/fc/FC.v VERILOG PATH input/RTL/fc/FC.v
add_fileset_file input/RTL/SRAM/Addr_Gen.v VERILOG PATH input/RTL/SRAM/Addr_Gen.v
add_fileset_file input/RTL/SRAM/sram_A_controller.v VERILOG PATH input/RTL/SRAM/sram_A_controller.v
add_fileset_file input/RTL/SRAM/sram_B_controller.v VERILOG PATH input/RTL/SRAM/sram_B_controller.v
add_fileset_file input/RTL/SRAM/sram_A_wrapper.v VERILOG PATH input/RTL/SRAM/sram_A_wrapper.v
add_fileset_file input/RTL/SRAM/sram_B_wrapper.v VERILOG PATH input/RTL/SRAM/sram_B_wrapper.v
add_fileset_file input/RTL/SRAM/sram_FCW_wrapper.v VERILOG PATH input/RTL/SRAM/sram_FCW_wrapper.v
add_fileset_file input/RTL/SRAM/fcw_preload_packer.v VERILOG PATH input/RTL/SRAM/fcw_preload_packer.v
add_fileset_file input/RTL/SRAM/top_sram_A.v VERILOG PATH input/RTL/SRAM/top_sram_A.v
add_fileset_file input/RTL/SRAM/top_sram_B.v VERILOG PATH input/RTL/SRAM/top_sram_B.v

# ----------------------------------------------------------------------
# module assignments
# ----------------------------------------------------------------------
set_module_assignment embeddedsw.dts.group cnn_mmio_interface
set_module_assignment embeddedsw.dts.name cnn_mmio_interface
set_module_assignment embeddedsw.dts.vendor csee4840

# ----------------------------------------------------------------------
# connection point clock
# ----------------------------------------------------------------------
add_interface clock clock end
set_interface_property clock clockRate 0
set_interface_property clock ENABLED true
set_interface_property clock EXPORT_OF ""
set_interface_property clock PORT_NAME_MAP ""
set_interface_property clock CMSIS_SVD_VARIABLES ""
set_interface_property clock SVD_ADDRESS_GROUP ""
add_interface_port clock clk clk Input 1

# ----------------------------------------------------------------------
# connection point reset
# ----------------------------------------------------------------------
add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
set_interface_property reset ENABLED true
set_interface_property reset EXPORT_OF ""
set_interface_property reset PORT_NAME_MAP ""
set_interface_property reset CMSIS_SVD_VARIABLES ""
set_interface_property reset SVD_ADDRESS_GROUP ""
add_interface_port reset reset reset Input 1

# ----------------------------------------------------------------------
# connection point avalon_slave_0
# ----------------------------------------------------------------------
add_interface avalon_slave_0 avalon end
set_interface_property avalon_slave_0 addressUnits WORDS
set_interface_property avalon_slave_0 associatedClock clock
set_interface_property avalon_slave_0 associatedReset reset
set_interface_property avalon_slave_0 bitsPerSymbol 8
set_interface_property avalon_slave_0 burstOnBurstBoundariesOnly false
set_interface_property avalon_slave_0 burstcountUnits WORDS
set_interface_property avalon_slave_0 explicitAddressSpan 0
set_interface_property avalon_slave_0 holdTime 0
set_interface_property avalon_slave_0 linewrapBursts false
set_interface_property avalon_slave_0 maximumPendingReadTransactions 0
set_interface_property avalon_slave_0 maximumPendingWriteTransactions 0
set_interface_property avalon_slave_0 readLatency 0
set_interface_property avalon_slave_0 readWaitTime 1
set_interface_property avalon_slave_0 setupTime 0
set_interface_property avalon_slave_0 timingUnits Cycles
set_interface_property avalon_slave_0 writeWaitTime 0
set_interface_property avalon_slave_0 ENABLED true
set_interface_property avalon_slave_0 EXPORT_OF ""
set_interface_property avalon_slave_0 PORT_NAME_MAP ""
set_interface_property avalon_slave_0 CMSIS_SVD_VARIABLES ""
set_interface_property avalon_slave_0 SVD_ADDRESS_GROUP ""
add_interface_port avalon_slave_0 writedata writedata Input 16
add_interface_port avalon_slave_0 write write Input 1
add_interface_port avalon_slave_0 chipselect chipselect Input 1
add_interface_port avalon_slave_0 address address Input 20
add_interface_port avalon_slave_0 readdata readdata Output 16
set_interface_assignment avalon_slave_0 embeddedsw.configuration.isFlash 0
set_interface_assignment avalon_slave_0 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment avalon_slave_0 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment avalon_slave_0 embeddedsw.configuration.isPrintableDevice 0
