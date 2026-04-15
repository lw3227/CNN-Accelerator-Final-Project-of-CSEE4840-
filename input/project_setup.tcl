# Rui ("Ray") Xu
# Nov 2021
# CISL @ Columbia, Kinget Group
# project_setup.tcl

# Tested on tsmc65gplus 1p9m6x1z1u
# Tested on Cadence Genus, Innovus, Tempus, Voltus versions 20.1
# All paths are relative to the syn/work (for Genus) or pnr/work (for Innovus) directory
# Requires the following environment variables: $PDK_PATH, $PDK_DIGITAL, $CDSHOME

# This set of scripts has been tested with the following tools:
# IC 6.1.8-64b.500.22
# GENUS 21.16-s062_1
# INNOVUS v21.16-s078_1
# QUANTUS 21.2.2-p045
# TEMPUS v21.16-s080_1
# VOLTUS v21.16-s080_1

# namespace for Genus operations.  Syntehsis.
namespace eval gn {}	
# namespace for innovus operations.  Place&Route.  Some variables from gn namespace may be used in innovus flow if shared.
namespace eval iv {}	

#####################################################################
# Project Information, Synthesis
#####################################################################
# Replace this with the name of your topcell
set TOPCELL		system_top
# List of HDL files (paths relative to $gn::RTLDir, which is project root)
set gn::VERILOG_LIST	[list \
    "input/RTL/conv_core/Line_Buffer.v" \
    "input/RTL/conv_core/input_row_aligner.v" \
    "input/RTL/conv_core/sa_skew_feeder.v" \
    "input/RTL/conv_core/Conv_Buffer.v" \
    "input/RTL/conv_core/systolic_array_top.v" \
    "input/RTL/conv_core/weight_buffer.v" \
    "input/RTL/conv_core/conv_engine_ctrl.v" \
    "input/RTL/conv_core/conv_top.v" \
    "input/RTL/quant_pool/integration/quant_param_loader.v" \
    "input/RTL/quant_pool/integration/conv_quant_adapter.v" \
    "input/RTL/quant_pool/integration/quant_pool_adapter.v" \
    "input/RTL/quant_pool/quant/Quantization_PE.v" \
    "input/RTL/quant_pool/quant/Quantization_Top.v" \
    "input/RTL/quant_pool/pool/pool_core.v" \
    "input/RTL/quant_pool/pool/pool_stream_top.v" \
    "input/RTL/conv_core/conv_quant_pool.v" \
    "input/RTL/fsm/top_fsm.v" \
    "input/RTL/fsm/layer_runner_fsm.v" \
    "input/RTL/fsm/conv_data_adapter.v" \
    "input/RTL/fsm/wt_prepad_inserter.v" \
    "input/RTL/fc/fc_bias_loader.v" \
    "input/RTL/fc/fc_data_adapter.v" \
    "input/RTL/fc/mac.v" \
    "input/RTL/fc/FC.v" \
    "input/RTL/SRAM/Addr_Gen.v" \
    "input/RTL/SRAM/sram_A_controller.v" \
    "input/RTL/SRAM/sram_B_controller.v" \
    "input/RTL/SRAM/sram_A_wrapper.v" \
    "input/RTL/SRAM/sram_B_wrapper.v" \
    "input/RTL/SRAM/top_sram_A.v" \
    "input/RTL/SRAM/top_sram_B.v" \
    "input/RTL/system_top.v" \
]
set gn::SDC_LIST	[list "system_top.sdc"]
# Tech node, in nm
set iv::node		65

#####################################################################
# Project Information, Floorplanning
#####################################################################
# Use Tempus engine?  More accurate for long wires
set iv::TEMPUS_ENGINE	1
# Incremental optimization?
set iv::INCR_OPT	1
# Power and ground net names as they should be implemented in your design
set iv::PWR_name	DVDD
set iv::GND_name	DVSS
# Power and ground pin names as they are in the digital std cell lib
set iv::PWR_libname	VDD
set iv::GND_libname	VSS
#### die dimensions ####
# system_top contains conv_quant_pool + FSMs + FC + two SRAM macros,
# so it needs a roomier floorplan than the conv-only flow.
set vars(fp,width)          890
set vars(fp,height)         890
set vars(fp,io_core_space)   27.5
#### ring parameters ####
# metal layer
set vars(ring,top_layer)        9  
set vars(ring,bottom_layer)     9  
set vars(ring,left_layer)       8  
set vars(ring,right_layer)      8  
# width
set vars(ring,top_width)        9.06  
set vars(ring,bottom_width)     9.06  
set vars(ring,left_width)       9.06  
set vars(ring,right_width)      9.06  
# spacing
set vars(ring,top_space)        4.44  
set vars(ring,bottom_space)     4.44  
set vars(ring,left_space)       4.44  
set vars(ring,right_space)      4.44  
# offset
set vars(ring,top_offset)       4.44  
set vars(ring,bottom_offset)    4.44  
set vars(ring,left_offset)      4.44  
set vars(ring,right_offset)     4.44  
#### stripes parameters ####
# stripes direction
set vars(stripe,dir)     vertical  
# stripes spacing between VDD and GND
set vars(stripe,space)          4.44  
# stripes metal layer
set vars(stripe,metal)          8  
# stripes width
set vars(stripe,width)         9.06  
# Stripes set distance
#set vars(stripe,setdist)	360
#set vars(stripe,setdist)	[expr { ($vars(fp,width)/2)-$vars(stripe,width)-0.5*$vars(stripe,space)-$vars(fp,io_core_space) }]
# This prevents an additional stripe at the right most edge
set vars(stripe,setdist)	[expr { ($vars(fp,width)/3)-   $vars(stripe,width)-0.5*$vars(stripe,space)-0.5*$vars(fp,io_core_space) }]
### Special cells
set vars(cell,decaps) "DCAP64 DCAP32 DCAP16 DCAP8 DCAP4"
set vars(cell,welltap) ""
set vars(cell,welltap,gap) ""
set vars(cell,tieHiLo) "TIEH TIEL"
#set vars(cell,filler) "FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1"
set vars(cell,filler) "DCAP64 DCAP32 DCAP16 DCAP8 DCAP4 FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1"
# do not export these cells into the schematic
set vars(cell,filler_nosch) "FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1"
set vars(cell,antenna) "ANTENNA"
# Special treatment for triple-majority voters, microns of separation between same TMR group.  Registers must be named with TMR1*, TMR2, and TMR3*
set iv::TMRDIST		25
# Routing variables
set iv::data_bottom_routing_layer	1
set iv::data_top_routing_layer		7
#####################################################################
# Project Information, Clock Tree Synthesis
#####################################################################
set vars(cell,clk_bufs) {CKBD1 CKBD12 CKBD16 CKBD2 CKBD20 CKBD24 CKBD3 CKBD4 CKBD6 CKBD8}
set vars(cell,clk_invs) {CKND1 CKND12 CKND16 CKND2 CKND20 CKND24 CKND3 CKND4 CKND6 CKND8}
set iv::clk_bottom_routing_layer	2
set iv::clk_top_routing_layer		7
set iv::clk_maxfanout			20
set iv::clk_maxcap			10pf
# Target setup and hold slack, in nS
set iv::setup_target_slack		0.1
set iv::hold_target_slack		0.05


#####################################################################
# PDK Information, Synthesis Only
#####################################################################
# Where possible, provide worst case corners.  Synthesis should always be done on the worst corner.
# See mmmc.tcl for library setup for innovus
# See user_timing_derating.tcl for user customization
# Grab from environment variable
set PDK_PATH		$env(PDK_PATH)	
set PDK_DIGITAL		$env(PDK_DIGITAL)	
# List of NLDM libraries of all std cell libraries + SRAM macros
set gn::NLDMLIB		[list \
    "$PDK_DIGITAL/Front_End/timing_power_noise/NLDM/tcbn65gplus_200a/tcbn65gpluswc.lib" \
    "../../input/SRAM_macro/sram_A/sram_A_libs/sram_A_nldm_ss_0p90v_0p90v_125c_syn.lib" \
    "../../input/SRAM_macro/sram_B/sram_B_libs/sram_B_nldm_ss_0p90v_0p90v_125c_syn.lib" \
]


#####################################################################
# PDK Information, Plkace&Route OpenAccess format
# IMPORTANT: The OpenAccess library associated here must match with the technology specifics in project.lib and mmmc.tcl
#####################################################################
# OA libraries containing abstracts and vias
set iv::OALIB		[list "tcbn65gplus_oalib" "sram_macros_oa" ]
# OA library containing tech data
set iv::OATECH		"tcbn65gplus_oalib"
# OA library containing physical cells (schematic, layout, symbol)
set iv::OAPHYS		"tcbn65gplus"
# OA tech library for OAPHYS
set iv::OAPHYSTECH		"tsmcN65"
# Verilog subcircuit definitions (with power)
set iv::VERILOG_SUBCKT  "$PDK_DIGITAL/Front_End/verilog/tcbn65gplus_200a/tcbn65gplus_pwr.v"
# SPICE subcircuit definitions (with power)
set iv::SPICE_SUBCKT    "$PDK_DIGITAL/Back_End/spice/tcbn65gplus_200a/tcbn65gplus_200a.spi"



#####################################################################
# Path Information (do not change this)
#####################################################################
# VERILOG_LIST paths are relative to project root (../../ from syn/work).
set gn::RTLDir		../../
set gn::SDCDir		../../input/SDC/
set gn::OutDir		../output
set gn::reportDir	../report
set iv::OutDir		../output
set iv::reportDir	../report
set iv::SYN_NETLIST	../../syn/output/$TOPCELL.syn.v
set iv::MMMC_FILE	../../input/mmmc.tcl
set iv::IO_FILE	../../input/pins_system_top.io
#####################################################################
# Tool Variables
#####################################################################
set gn::SYN_EFFORT	medium
set gn::MAP_EFFORT	high
set gn::INCR_EFFORT	high
# IF any Genus messages annoy you, add it here
set gn::SUPPRESS_MSG	{LBR-30 LBR-31 VLOGPT-35}
